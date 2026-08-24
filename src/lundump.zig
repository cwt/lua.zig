// $Id: lundump.zig $
// Load precompiled Lua chunks (Zig port of Lua 5.5.0)
// See Copyright Notice in lua.zig

const std = @import("std");
const lua = @import("lua.zig");
const lvm = @import("lvm.zig");
const lstring = @import("lstring.zig");
const ltable = @import("ltable.zig");

const LUAC_DATA = "\x19\x93\r\n\x1a\n";
const LUAC_INT = -@as(i64, 0x5678);
const LUAC_INST = @as(u32, 0x12345678);
const LUAC_NUM = @as(f64, -370.5);
const LUAC_VERSION = @as(u8, 5 * 16 + 5); // major * 16 + minor
const LUAC_FORMAT = @as(u8, 0);

// Prototype flag bits (lua/lobject.h). PF_FIXED means parts live in fixed
// memory and is irrelevant to our allocator model, so we mask it out like C.
const PF_VAHID = 1; // function has hidden vararg arguments
const PF_VATAB = 2; // function has vararg table
const PF_FIXED = 4; // prototype has parts in fixed memory

const Zio = struct {
    L: *lua.lua_State,
    reader: lua.lua_Reader,
    data: ?*anyopaque,
    buffer: []const u8,
    offset: usize,

    pub fn init(L: *lua.lua_State, reader: lua.lua_Reader, data: ?*anyopaque, first_slice: []const u8) Zio {
        return .{
            .L = L,
            .reader = reader,
            .data = data,
            .buffer = first_slice,
            .offset = 1,
        };
    }

    pub fn readBlock(self: *Zio, dest: []u8) !void {
        var bytes_read: usize = 0;
        while (bytes_read < dest.len) {
            if (self.offset >= self.buffer.len) {
                var size: usize = 0;
                // The reader returns the next block of the input stream
                const res = (try self.reader(self.L, self.data, &size)) orelse return error.TruncatedChunk;
                if (res.len == 0 or size == 0) return error.TruncatedChunk;
                self.buffer = res;
                self.offset = 0;
            }
            const avail = self.buffer.len - self.offset;
            const to_copy = @min(avail, dest.len - bytes_read);
            @memcpy(dest[bytes_read..][0..to_copy], self.buffer[self.offset..][0..to_copy]);
            self.offset += to_copy;
            bytes_read += to_copy;
        }
    }
};

const LoadState = struct {
    L: *lua.lua_State,
    zio: Zio,
    name: []const u8,
    offset: usize,
    strings: std.ArrayList(*lua.lua_TString),
    anchor_tab: *lua.lua_Table,
    allocator: std.mem.Allocator,

    fn loadBlock(self: *LoadState, dest: []u8) !void {
        try self.zio.readBlock(dest);
        self.offset += dest.len;
    }

    fn loadByte(self: *LoadState) !u8 {
        var b: [1]u8 = undefined;
        try self.loadBlock(&b);
        return b[0];
    }

    fn loadVarint(self: *LoadState, limit: u64) !u64 {
        var x: u64 = 0;
        const shifted_limit = limit >> 7;
        while (true) {
            const b = try self.loadByte();
            if (x > shifted_limit) {
                return error.IntegerOverflow;
            }
            x = (x << 7) | (b & 0x7f);
            if ((b & 0x80) == 0) break;
        }
        return x;
    }

    fn loadSize(self: *LoadState) !usize {
        const val = try self.loadVarint(std.math.maxInt(usize));
        return @intCast(val);
    }

    fn loadInt(self: *LoadState) !i32 {
        const val = try self.loadVarint(std.math.maxInt(i32));
        return @intCast(val);
    }

    fn loadNumber(self: *LoadState) !f64 {
        var bytes: [8]u8 = undefined;
        try self.loadBlock(&bytes);
        return @bitCast(bytes);
    }

    fn loadInteger(self: *LoadState) !i64 {
        const cx = try self.loadVarint(std.math.maxInt(u64));
        if ((cx & 1) != 0) {
            return @bitCast(~(cx >> 1));
        } else {
            return @bitCast(cx >> 1);
        }
    }

    fn loadAlign(self: *LoadState, align_val: usize) !void {
        const padding = align_val - (self.offset % align_val);
        if (padding < align_val) {
            var temp: [8]u8 = undefined;
            try self.loadBlock(temp[0..padding]);
        }
    }

    fn loadString(self: *LoadState) !?*lua.lua_TString {
        const size = try self.loadSize();
        if (size == 0) {
            const idx = try self.loadVarint(std.math.maxInt(u64));
            if (idx == 0) return null;
            if (idx > self.strings.items.len) return error.InvalidStringIndex;
            return self.strings.items[idx - 1];
        }

        const len = size - 1;
        const buf = try self.allocator.alloc(u8, size);
        defer self.allocator.free(buf);
        try self.loadBlock(buf);

        const ts = try lstring.luaS_new(self.L, buf[0..len]);
        try ltable.set(self.anchor_tab, .{ .string = ts }, .{ .boolean = true });

        try self.strings.append(self.allocator, ts);
        return ts;
    }

    fn loadCode(self: *LoadState, f: *lua.lua_Proto) !void {
        const n = try self.loadInt();
        if (n < 0) return error.BadFormat;
        try self.loadAlign(4);
        const code = try self.allocator.alloc(lvm.Instruction, @intCast(n));
        f.code = code; // Assign immediately; GC owns this via allgc
        try self.loadBlock(std.mem.sliceAsBytes(code));
    }

    fn loadConstants(self: *LoadState, f: *lua.lua_Proto) !void {
        const n = try self.loadInt();
        if (n < 0) return error.BadFormat;
        const k = try self.allocator.alloc(lua.TValue, @intCast(n));
        f.k = k; // Assign immediately; GC owns this via allgc

        for (k) |*val| {
            val.* = .{ .nil = {} };
        }

        var i: usize = 0;
        while (i < @as(usize, @intCast(n))) : (i += 1) {
            const t = try self.loadByte();
            switch (t) {
                0 => { // LUA_VNIL
                    k[i] = .{ .nil = {} };
                },
                1 => { // LUA_VFALSE
                    k[i] = .{ .boolean = false };
                },
                17 => { // LUA_VTRUE
                    k[i] = .{ .boolean = true };
                },
                19 => { // LUA_VNUMFLT
                    k[i] = .{ .number = try self.loadNumber() };
                },
                3 => { // LUA_VNUMINT
                    k[i] = .{ .integer = try self.loadInteger() };
                },
                4, 20 => { // LUA_VSHRSTR, LUA_VLNGSTR
                    const ts = try self.loadString();
                    if (ts == null) return error.BadFormat;
                    k[i] = .{ .string = ts };
                },
                else => return error.InvalidConstantTag,
            }
        }
    }

    fn loadProtos(self: *LoadState, f: *lua.lua_Proto) anyerror!void {
        const n = try self.loadInt();
        if (n < 0) return error.BadFormat;
        const sub_protos = try self.allocator.alloc(*lua.lua_Proto, @intCast(n));
        f.p = sub_protos; // Assign immediately; GC owns this via allgc

        var loaded: usize = 0;
        while (loaded < @as(usize, @intCast(n))) : (loaded += 1) {
            const sub = try lua.createProto(self.allocator);
            sub.is_sub = true;
            try lua.registerGC(self.L, sub);
            sub_protos[loaded] = sub;
            try self.loadFunction(sub);
        }
    }

    fn loadUpvalues(self: *LoadState, f: *lua.lua_Proto) !void {
        const n = try self.loadInt();
        if (n < 0) return error.BadFormat;
        const upvals = try self.allocator.alloc(lua.Upvaldesc, @intCast(n));
        f.upvalues = upvals; // Assign immediately; GC owns this via allgc

        for (upvals) |*up| {
            up.name = null;
            up.instack = 0;
            up.idx = 0;
            up.kind = 0;
        }

        for (upvals) |*up| {
            up.instack = try self.loadByte();
            up.idx = try self.loadByte();
            up.kind = try self.loadByte();
        }
    }

    fn loadDebug(self: *LoadState, f: *lua.lua_Proto) !void {
        // 1. lineinfo
        const n_lineinfo = try self.loadInt();
        if (n_lineinfo < 0) return error.BadFormat;
        const lineinfo = try self.allocator.alloc(i8, @intCast(n_lineinfo));
        f.lineinfo = lineinfo; // Assign immediately; GC owns this via allgc
        try self.loadBlock(std.mem.sliceAsBytes(lineinfo));

        // 2. abslineinfo
        const n_abslineinfo = try self.loadInt();
        if (n_abslineinfo < 0) return error.BadFormat;
        if (n_abslineinfo > 0) {
            try self.loadAlign(@alignOf(lua.AbsLineInfo));
            const abslineinfo = try self.allocator.alloc(lua.AbsLineInfo, @intCast(n_abslineinfo));
            f.abslineinfo = abslineinfo; // Assign immediately
            try self.loadBlock(std.mem.sliceAsBytes(abslineinfo));
        } else {
            f.abslineinfo = &[_]lua.AbsLineInfo{};
        }

        // 3. locvars
        const n_locvars = try self.loadInt();
        if (n_locvars < 0) return error.BadFormat;
        const locvars = try self.allocator.alloc(lua.LocVar, @intCast(n_locvars));
        f.locvars = locvars; // Assign immediately; GC owns this via allgc
        for (locvars) |*lv| {
            lv.varname = null;
            lv.startpc = 0;
            lv.endpc = 0;
        }
        for (locvars) |*lv| {
            lv.varname = try self.loadString();
            lv.startpc = try self.loadInt();
            lv.endpc = try self.loadInt();
        }

        // 4. upval names
        const n_upvalnames = try self.loadInt();
        const actual_upvalnames_len = if (n_upvalnames != 0) f.upvalues.len else 0;
        var i: usize = 0;
        while (i < actual_upvalnames_len) : (i += 1) {
            f.upvalues[i].name = try self.loadString();
        }
    }

    fn loadFunction(self: *LoadState, f: *lua.lua_Proto) anyerror!void {
        f.lineDefined = try self.loadInt();
        f.lastLineDefined = try self.loadInt();
        f.numParams = try self.loadByte();
        const flag = try self.loadByte();
        // Decode the meaningful flags: a function is vararg if it has hidden
        // vararg arguments and/or a vararg table (lua/lobject.h isvararg()).
        f.isVarArg = (flag & (PF_VAHID | PF_VATAB)) != 0;
        f.flag = flag;
        f.maxStackSize = try self.loadByte();

        try self.loadCode(f);
        try self.loadConstants(f);

        try self.loadUpvalues(f);
        try self.loadProtos(f);
        f.source = try self.loadString();
        try self.loadDebug(f);
    }

    fn checkliteral(self: *LoadState, expected: []const u8, msg: []const u8) !void {
        var buf: [32]u8 = undefined;
        const len = expected.len;
        if (len > buf.len) return error.BufferOverflow;
        try self.loadBlock(buf[0..len]);
        if (!std.mem.eql(u8, expected, buf[0..len])) {
            std.debug.print("Header mismatch: {s}\n", .{msg});
            return error.BadHeader;
        }
    }

    fn checknum(self: *LoadState, expected_size: u8, expected_val: anytype, tname: []const u8) !void {
        const size = try self.loadByte();
        if (size != expected_size) {
            std.debug.print("{s} size mismatch: expected {d}, got {d}\n", .{ tname, expected_size, size });
            return error.TypeSizeMismatch;
        }
        const T = @TypeOf(expected_val);
        var val: T = undefined;
        try self.loadBlock(std.mem.asBytes(&val));
        if (val != expected_val) {
            std.debug.print("{s} format mismatch: expected {any}, got {any}\n", .{ tname, expected_val, val });
            return error.TypeFormatMismatch;
        }
    }

    fn checkHeader(self: *LoadState) !void {
        // Skip first char (which was already checked by caller)
        try self.checkliteral(lua.LUA_SIGNATURE[1..], "not a binary chunk");
        if (try self.loadByte() != LUAC_VERSION) return error.VersionMismatch;
        if (try self.loadByte() != LUAC_FORMAT) return error.FormatMismatch;
        try self.checkliteral(LUAC_DATA, "corrupted chunk");
        try self.checknum(@sizeOf(i32), @as(i32, -0x5678), "int"); // C int is checked as -0x5678 in checknum
        try self.checknum(@sizeOf(u32), LUAC_INST, "instruction");
        try self.checknum(@sizeOf(i64), LUAC_INT, "Lua integer");
        try self.checknum(@sizeOf(f64), LUAC_NUM, "Lua number");
    }
};

pub fn loadBinaryChunk(L: *lua.lua_State, reader: lua.lua_Reader, dt: ?*anyopaque, first_slice: []const u8, name: []const u8) !*lua.lua_Proto {
    const anchor_tab = try ltable.createTable(L.allocator, 0, 4);
    try lua.registerGC(L, anchor_tab);
    if (L.l_G) |g| {
        if (g.registry.table) |reg| {
            try ltable.set(reg, .{ .lightud = @ptrCast(anchor_tab) }, .{ .table = anchor_tab });
        }
    }
    defer {
        if (L.l_G) |g| {
            if (g.registry.table) |reg| {
                // BUG-100: best-effort cleanup on unloader teardown.
                _ = ltable.set(reg, .{ .lightud = @ptrCast(anchor_tab) }, .{ .nil = {} }) catch {};
            }
        }
    }

    var S = LoadState{
        .L = L,
        .zio = Zio.init(L, reader, dt, first_slice),
        .name = name,
        .offset = 1, // first byte already read
        .strings = .empty,
        .anchor_tab = anchor_tab,
        .allocator = L.allocator,
    };
    defer S.strings.deinit(L.allocator);

    try S.checkHeader();
    const cl_nupval = try S.loadByte();
    _ = cl_nupval; // nupval for the main closure, will be verified/used when closure is instantiated

    const proto = try lua.createProto(L.allocator);
    try lua.registerGC(L, proto);

    try ltable.set(anchor_tab, .{ .proto = proto }, .{ .boolean = true });

    try S.loadFunction(proto);
    return proto;
}
