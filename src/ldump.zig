// $Id: ldump.zig $
// Dump Lua chunks to precompiled bytecode (Zig port of Lua 5.5.0 ldump.c)
// See Copyright Notice in lua.zig

const std = @import("std");
const lua = @import("lua.zig");
const lvm = @import("lvm.zig");
const lstring = @import("lstring.zig");

// On-disk constants — MUST match lundump.zig exactly (that file is the loader
// and defines the authoritative format).
const LUAC_DATA = "\x19\x93\r\n\x1a\n";
const LUAC_INT = -@as(i64, 0x5678);
const LUAC_INST = @as(u32, 0x12345678);
const LUAC_NUM = @as(f64, -370.5);
const LUAC_VERSION = @as(u8, 5 * 16 + 5); // major * 16 + minor
const LUAC_FORMAT = @as(u8, 0);

// Constant tags in the dump (must match lundump.zig's loadConstants).
const LUA_VNIL: u8 = 0;
const LUA_VFALSE: u8 = 1;
const LUA_VNUMINT: u8 = 3;
const LUA_VSHRSTR: u8 = 4;
const LUA_VTRUE: u8 = 17;
const LUA_VNUMFLT: u8 = 19;
const LUA_VLNGSTR: u8 = 20;

const DumpState = struct {
    L: *lua.lua_State,
    writer: lua.lua_Writer,
    data: ?*anyopaque,
    status: i32,
    written: usize,
    strings: std.array_hash_map.String(usize) = .empty,
    nstr: usize = 0,

    fn dumpBlock(self: *DumpState, b: []const u8) void {
        if (self.status != lua.LUA_OK) return;
        if (b.len == 0) return;
        self.status = self.writer(self.L, @as(?*anyopaque, @constCast(@ptrCast(b.ptr))), b.len, self.data);
        if (self.status != lua.LUA_OK) return;
        self.written += b.len;
    }

    fn dumpByte(self: *DumpState, x: u8) void {
        var b: [1]u8 = .{x};
        self.dumpBlock(&b);
    }

    // Emit `x` as a LEB128-style unsigned varint, most-significant 7-bit
    // group first. All bytes except the last carry the 0x80 marker bit, matching
    // lundump.zig's loadVarint (which breaks when the 0x80 bit is clear).
    fn dumpVarint(self: *DumpState, x_in: u64) void {
        var chunks: [16]u8 = undefined;
        var n: usize = 0;
        var x = x_in;
        while (true) {
            chunks[n] = @as(u8, @intCast(x & 0x7f));
            x >>= 7;
            n += 1;
            if (x == 0) break;
        }
        // chunks[0] = LSB ... chunks[n-1] = MSB. Emit MSB first.
        var i: usize = n;
        while (i > 0) {
            i -= 1;
            var byte = chunks[i];
            if (i != 0) byte |= 0x80;
            self.dumpByte(byte);
        }
    }

    fn dumpSize(self: *DumpState, x: usize) void {
        self.dumpVarint(@as(u64, @intCast(x)));
    }

    fn dumpInt(self: *DumpState, x: i32) void {
        self.dumpVarint(@bitCast(@as(i64, x)));
    }

    fn dumpNumber(self: *DumpState, x: f64) void {
        const bytes: [8]u8 = @bitCast(x);
        self.dumpBlock(&bytes);
    }

    // Encode an i64 using the loader's sign-in-low-bit scheme:
    //   negative x -> ((~x) << 1) | 1 ;  non-negative x -> x << 1
    fn dumpInteger(self: *DumpState, x: i64) void {
        const xbits: u64 = @bitCast(x);
        const ux: u64 = if (x < 0) ((~xbits) << 1) | 1 else xbits << 1;
        self.dumpVarint(ux);
    }

    fn dumpString(self: *DumpState, ts: ?*lua.lua_TString) void {
        if (ts == null) {
            self.dumpVarint(0);
            self.dumpVarint(0);
            return;
        }
        const s = ts.?.s;
        const gop = self.strings.getOrPut(self.L.allocator, s) catch {
            self.status = lua.LUA_ERRMEM;
            return;
        };
        if (gop.found_existing) {
            self.dumpVarint(0);
            self.dumpVarint(gop.value_ptr.*);
        } else {
            self.dumpSize(s.len + 1);
            self.dumpBlock(s);
            self.dumpByte(0);
            self.nstr += 1;
            gop.value_ptr.* = self.nstr;
        }
    }

    fn dumpAlign(self: *DumpState, alignment: usize) void {
        const rem = self.written % alignment;
        if (rem != 0) {
            var i: usize = 0;
            while (i < alignment - rem) : (i += 1) {
                self.dumpByte(0);
            }
        }
    }

    fn dumpCode(self: *DumpState, f: *lua.lua_Proto) void {
        self.dumpInt(@as(i32, @intCast(f.code.len)));
        self.dumpAlign(4);
        self.dumpBlock(std.mem.sliceAsBytes(f.code));
    }

    fn dumpConstants(self: *DumpState, f: *lua.lua_Proto) void {
        self.dumpInt(@as(i32, @intCast(f.k.len)));
        for (f.k) |val| {
            switch (val) {
                .nil => self.dumpByte(LUA_VNIL),
                .boolean => |b| self.dumpByte(if (b) LUA_VTRUE else LUA_VFALSE),
                .integer => |n| {
                    self.dumpByte(LUA_VNUMINT);
                    self.dumpInteger(n);
                },
                .number => |n| {
                    self.dumpByte(LUA_VNUMFLT);
                    self.dumpNumber(n);
                },
                .string => |ts| {
                    self.dumpByte(LUA_VSHRSTR);
                    self.dumpString(ts);
                },
                else => self.dumpByte(LUA_VNIL),
            }
        }
    }

    fn dumpUpvalues(self: *DumpState, f: *lua.lua_Proto) void {
        self.dumpInt(@as(i32, @intCast(f.upvalues.len)));
        for (f.upvalues) |up| {
            self.dumpByte(up.instack);
            self.dumpByte(up.idx);
            self.dumpByte(up.kind);
        }
    }

    fn dumpProtos(self: *DumpState, f: *lua.lua_Proto, strip: bool) void {
        self.dumpInt(@as(i32, @intCast(f.p.len)));
        for (f.p) |sub| {
            self.dumpFunction(sub, strip);
        }
    }

    fn dumpDebug(self: *DumpState, f: *lua.lua_Proto, strip: bool) void {
        // lineinfo
        const nline = if (strip) 0 else f.lineinfo.len;
        self.dumpInt(@as(i32, @intCast(nline)));
        if (nline > 0) {
            self.dumpBlock(std.mem.sliceAsBytes(f.lineinfo));
        }
        // abslineinfo
        const nabs = if (strip) 0 else f.abslineinfo.len;
        self.dumpInt(@as(i32, @intCast(nabs)));
        if (nabs > 0) {
            self.dumpAlign(@alignOf(lua.AbsLineInfo));
            self.dumpBlock(std.mem.sliceAsBytes(f.abslineinfo));
        }
        // locvars
        const nloc = if (strip) 0 else f.locvars.len;
        self.dumpInt(@as(i32, @intCast(nloc)));
        if (!strip) {
            for (f.locvars) |lv| {
                self.dumpString(lv.varname);
                self.dumpInt(lv.startpc);
                self.dumpInt(lv.endpc);
            }
        }
        // upvalue names
        const nup = if (strip) 0 else f.upvalues.len;
        self.dumpInt(@as(i32, @intCast(nup)));
        if (!strip) {
            for (f.upvalues) |up| {
                self.dumpString(up.name);
            }
        }
    }

    fn dumpFunction(self: *DumpState, f: *lua.lua_Proto, strip: bool) void {
        self.dumpInt(f.lineDefined);
        self.dumpInt(f.lastLineDefined);
        self.dumpByte(f.numParams);
        self.dumpByte(f.flag);
        self.dumpByte(f.maxStackSize);
        self.dumpCode(f);
        self.dumpConstants(f);
        self.dumpUpvalues(f);
        self.dumpProtos(f, strip);
        self.dumpString(if (strip) null else f.source);
        self.dumpDebug(f, strip);
    }

    fn dumpHeader(self: *DumpState) void {
        self.dumpBlock(lua.LUA_SIGNATURE);
        self.dumpByte(LUAC_VERSION);
        self.dumpByte(LUAC_FORMAT);
        self.dumpBlock(LUAC_DATA);
        var int_v: i32 = -0x5678;
        self.dumpByte(4);
        self.dumpBlock(std.mem.asBytes(&int_v));
        var inst_v: u32 = LUAC_INST;
        self.dumpByte(4);
        self.dumpBlock(std.mem.asBytes(&inst_v));
        var int64_v: i64 = LUAC_INT;
        self.dumpByte(8);
        self.dumpBlock(std.mem.asBytes(&int64_v));
        var num_v: f64 = LUAC_NUM;
        self.dumpByte(8);
        self.dumpBlock(std.mem.asBytes(&num_v));
    }
};

pub fn lua_dump(L: *lua.lua_State, writer: lua.lua_Writer, data: ?*anyopaque, strip: i32) i32 {
    // The function to dump is at the top of the stack (str_dump pushes it
    // before calling). It must be a Lua (not C) closure.
    const v = lua.stackAt(L, -1);
    if (v != .function) return lua.LUA_ERRRUN;
    const cl = v.function orelse return lua.LUA_ERRRUN;
    if (cl.* != .lua) return lua.LUA_ERRRUN;
    const f = cl.lua.p;

    var D = DumpState{
        .L = L,
        .writer = writer,
        .data = data,
        .status = lua.LUA_OK,
        .written = 0,
    };
    defer D.strings.deinit(L.allocator);

    D.dumpHeader();
    D.dumpByte(@as(u8, @intCast(f.upvalues.len)));
    D.dumpFunction(f, strip != 0);
    return D.status;
}
