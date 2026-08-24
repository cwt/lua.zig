const std = @import("std");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");
pub const lvm = @import("lvm.zig");
const ltable = @import("ltable.zig");
pub const lstring = @import("lstring.zig");
const lundump = @import("lundump.zig");
const ldump = @import("ldump.zig");
const ltm = @import("ltm.zig");
const libm = @import("libm.zig");
pub const llex = @import("llex.zig");
pub const lcode = @import("lcode.zig");
pub const lparser = @import("lparser.zig");

pub const lua_Number = llimits.lua_Number;
pub const lua_Integer = llimits.lua_Integer;
pub const lua_Unsigned = llimits.lua_Unsigned;

pub const LUA_TNONE: i32 = llimits.LUA_TNONE;
pub const LUA_TNIL: i32 = llimits.LUA_TNIL;
pub const LUA_TBOOLEAN: i32 = llimits.LUA_TBOOLEAN;
pub const LUA_TLIGHTUSERDATA: i32 = llimits.LUA_TLIGHTUSERDATA;
pub const LUA_TTABLE: i32 = llimits.LUA_TTABLE;
pub const LUA_TNUMBER: i32 = llimits.LUA_TNUMBER;
pub const LUA_TSTRING: i32 = llimits.LUA_TSTRING;
pub const LUA_TFUNCTION: i32 = llimits.LUA_TFUNCTION;
pub const LUA_TUSERDATA: i32 = llimits.LUA_TUSERDATA;
pub const LUA_TTHREAD: i32 = llimits.LUA_TTHREAD;
pub const LUA_TUPVAL: i32 = llimits.LUA_TUPVAL;
pub const LUA_REGISTRYINDEX: i32 = llimits.LUA_REGISTRYINDEX;
pub const LUA_OK: i32 = llimits.LUA_OK;
pub const LUA_YIELD: i32 = llimits.LUA_YIELD;
pub const LUA_ERRRUN: i32 = llimits.LUA_ERRRUN;
pub const LUA_ERRMEM: i32 = llimits.LUA_ERRMEM;
pub const LUA_ERRERR: i32 = llimits.LUA_ERRERR;
pub const LUA_ERRSYNTAX: i32 = llimits.LUA_ERRSYNTAX;
pub const LUA_MINSTACK: i32 = llimits.LUA_MINSTACK;
pub const LUA_NUMTYPES: i32 = llimits.LUA_NUMTYPES;
pub const LUA_MAXINTEGER: lua_Integer = llimits.LUA_MAXINTEGER;
pub const LUA_MININTEGER: lua_Integer = llimits.LUA_MININTEGER;

// Arithmetic and bitwise operators
pub const LUA_OPADD: i32 = llimits.LUA_OPADD;
pub const LUA_OPSUB: i32 = llimits.LUA_OPSUB;
pub const LUA_OPMUL: i32 = llimits.LUA_OPMUL;
pub const LUA_OPMOD: i32 = llimits.LUA_OPMOD;
pub const LUA_OPPOW: i32 = llimits.LUA_OPPOW;
pub const LUA_OPDIV: i32 = llimits.LUA_OPDIV;
pub const LUA_OPIDIV: i32 = llimits.LUA_OPIDIV;
pub const LUA_OPBAND: i32 = llimits.LUA_OPBAND;
pub const LUA_OPBOR: i32 = llimits.LUA_OPBOR;
pub const LUA_OPBXOR: i32 = llimits.LUA_OPBXOR;
pub const LUA_OPSHL: i32 = llimits.LUA_OPSHL;
pub const LUA_OPSHR: i32 = llimits.LUA_OPSHR;
pub const LUA_OPUNM: i32 = llimits.LUA_OPUNM;
pub const LUA_OPBNOT: i32 = llimits.LUA_OPBNOT;

// Comparison operators
pub const LUA_OPEQ: i32 = llimits.LUA_OPEQ;
pub const LUA_OPLT: i32 = llimits.LUA_OPLT;
pub const LUA_OPLE: i32 = llimits.LUA_OPLE;

pub const lua_KContext = llimits.lua_KContext;
pub const lua_Alloc = llimits.lua_Alloc;
pub const lua_WarnFunction = llimits.lua_WarnFunction;

// Wrapper letting a `lua_Alloc` thunk (required by the C API) drive a
// std.mem.Allocator. Backs `global_State.allocf`/`alloc_ud`.
pub const AllocWrapper = struct {
    alloc: std.mem.Allocator,
};

// Default allocator thunk compatible with the C `lua_Alloc` typedef. Mirrors
// the semantics of the reference `l_alloc`: (ud -> AllocWrapper*) wraps a
// std.mem.Allocator; nsize==0 frees, osize==0 allocates, else reallocates.
fn l_alloc(ud: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) ?*anyopaque {
    const w = @as(*AllocWrapper, @ptrCast(@alignCast(ud orelse return null)));
    if (nsize == 0) {
        if (ptr) |p| {
            const old = @as([*]u8, @ptrCast(@alignCast(p)))[0..osize];
            w.alloc.free(old);
        }
        return null;
    } else if (osize == 0) {
        const m = w.alloc.alloc(u8, nsize) catch return null;
        return m.ptr;
    } else {
        const old = @as([*]u8, @ptrCast(@alignCast(ptr orelse return null)))[0..osize];
        const m = w.alloc.realloc(old, nsize) catch return null;
        return m.ptr;
    }
}

// Forward declarations
pub const lua_CFunction = *const fn (*lua_State) anyerror!i32;
pub const lua_KFunction = *const fn (*lua_State, i32, lua_KContext) anyerror!i32;

pub const lua_Reader = *const fn (*lua_State, ?*anyopaque, ?*usize) anyerror!?[]const u8;
pub const lua_Writer = *const fn (*lua_State, ?*anyopaque, usize, ?*anyopaque) i32;
pub const lua_Hook = *const fn (*lua_State, ?*lua_Debug) void;

pub const lua_Debug = struct {
    event: i32,
    name: ?[]const u8,
    namewhat: ?[]const u8,
    what: ?[]const u8,
    source: ?[]const u8,
    srclen: usize,
    currentline: i32,
    linedefined: i32,
    lastlinedefined: i32,
    nups: u8,
    nparams: u8,
    isvararg: bool,
    extraargs: i32,
    istailcall: bool,
    ftransfer: i32,
    ntransfer: i32,
    short_src: [LUA_IDSIZE]u8,
    i_ci: ?*CallInfo,
};

pub const LUA_IDSIZE: usize = llimits.LUA_IDSIZE;

pub const LUA_HOOKCALL: i32 = llimits.LUA_HOOKCALL;
pub const LUA_HOOKRET: i32 = llimits.LUA_HOOKRET;
pub const LUA_HOOKLINE: i32 = llimits.LUA_HOOKLINE;
pub const LUA_HOOKCOUNT: i32 = llimits.LUA_HOOKCOUNT;
pub const LUA_HOOKTAILCALL: i32 = llimits.LUA_HOOKTAILCALL;
pub const LUA_MASKCALL: u32 = llimits.LUA_MASKCALL;
pub const LUA_MASKRET: u32 = llimits.LUA_MASKRET;
pub const LUA_MASKLINE: u32 = llimits.LUA_MASKLINE;
pub const LUA_MASKCOUNT: u32 = llimits.LUA_MASKCOUNT;

pub const LUA_VERSION_NUM: lua_Number = @as(f64, @floatFromInt(@as(usize, LUA_VERSION_MAJOR_N) * 100 + LUA_VERSION_MINOR_N));
pub const LUA_N2SBUFFSZ: usize = 64;

pub const LUA_VERSION_MAJOR_N: u8 = 5;
pub const LUA_VERSION_MINOR_N: u8 = 5;
pub const LUA_VERSION_RELEASE_N: u8 = 1;

pub const LUA_VERSION_MAJOR: []const u8 = std.fmt.comptimePrint("{d}", .{LUA_VERSION_MAJOR_N});
pub const LUA_VERSION_MINOR: []const u8 = std.fmt.comptimePrint("{d}", .{LUA_VERSION_MINOR_N});
pub const LUA_VERSION_RELEASE: []const u8 = std.fmt.comptimePrint("{d}", .{LUA_VERSION_RELEASE_N});

pub const LUA_VERSION: []const u8 = "Lua " ++ LUA_VERSION_MAJOR ++ "." ++ LUA_VERSION_MINOR;
pub const LUA_RELEASE: []const u8 = LUA_VERSION ++ "." ++ LUA_VERSION_RELEASE;
pub const LUA_COPYRIGHT = LUA_RELEASE ++ "  Copyright (C) 1994-2026 Lua.org, PUC-Rio";
/// Extra banner line clarifying this is an independent Zig port, not a Lua.org
/// product. The Lua copyright line above is retained (as required by Lua's MIT
/// license and to match the reference interpreter's banner); this line makes
/// the port's provenance explicit.
pub const LUA_PORT_COPYRIGHT = "luazig: an independent, from-scratch Zig 0.16.0 port of the Lua reference implementation, by Lua.zig contributors — not affiliated with or endorsed by Lua.org/PUC-Rio";
pub const LUA_AUTHORS = "R. Ierusalimschy, L. H. de Figueiredo, W. Celes";
pub const LUA_SIGNATURE = "\x1bLua";

/// C API identification string (port of `lua_ident` from `lapi.c`).
/// Provides version and author strings embedded at link time in the C
/// reference; here a comptime `[]const u8` slice.
pub const lua_ident: []const u8 = "$LuaVersion: " ++ LUA_COPYRIGHT ++ " $" ++ "$LuaAuthors: " ++ LUA_AUTHORS ++ " $";

pub const LUA_MULTRET: i32 = -1;

pub const lua_TString = struct {
    s: []const u8,
    len: usize,
    hash: u32,
    marked: bool = false,
    gc: ?*VMGCObject = null,
    /// External strings (Lua 5.5 `lua_pushexternalstring`): the bytes in `s` are
    /// owned by a caller-provided allocator, not by Lua. `externally_owned` marks
    /// such strings so the GC tracks and frees them via `falloc`. Interned
    /// strings are always `false`.
    externally_owned: bool = false,
    /// External deallocation callback (Lua 5.5 `lua_Alloc` ABI). `null` for
    /// interned strings and for fixed external strings (LSTRFIX) whose bytes are
    /// static and never freed.
    falloc: ?lua_Alloc = null,
    /// User data passed back to `falloc` when freeing an LSTRMEM external string.
    ud: ?*anyopaque = null,
};

pub const lua_Udata = struct {
    metatable: ?*lua_Table = null,
    data: []u8,
    /// User values (created via lua_newuserdatauv). Nil-initialized, length
    /// equals the `nuvalue` requested at creation. Mirrors C `Udata->uv`.
    uv: []TValue = &.{},
    gc: ?*VMGCObject = null,
};

pub const TValue = union(enum) {
    nil: void,
    boolean: bool,
    lightud: ?*anyopaque,
    integer: i64,
    number: f64,
    string: ?*lua_TString,
    table: ?*lua_Table,
    function: ?*lua_Closure,
    userdata: ?*lua_Udata,
    thread: ?*lua_State,
    upval: ?*UpVal,
    proto: ?*lua_Proto,

    const type_map = blk: {
        const Tag = std.meta.Tag(TValue);
        const tags = std.enums.values(Tag);
        var table: [tags.len]i32 = undefined;
        for (tags) |t| {
            table[@intFromEnum(t)] = switch (t) {
                .nil => LUA_TNIL,
                .boolean => LUA_TBOOLEAN,
                .lightud => LUA_TLIGHTUSERDATA,
                .integer => LUA_TNUMBER,
                .number => LUA_TNUMBER,
                .string => LUA_TSTRING,
                .table => LUA_TTABLE,
                .function => LUA_TFUNCTION,
                .userdata => LUA_TUSERDATA,
                .thread => LUA_TTHREAD,
                .upval => LUA_TUPVAL,
                .proto => LUA_TFUNCTION,
            };
        }
        break :blk table;
    };

    pub inline fn typ(self: TValue) i32 {
        return type_map[@intFromEnum(self)];
    }

    fn toBoolean(self: TValue) bool {
        return switch (self) {
            .nil => false,
            .boolean => |b| b,
            else => true,
        };
    }

    /// Returns true if this is a numeric value (integer or float).
    pub fn isNumberValue(self: TValue) bool {
        return switch (self) {
            .number, .integer => true,
            else => false,
        };
    }

    /// Returns true if this is a string value.
    pub fn isString(self: TValue) bool {
        return switch (self) {
            .string => true,
            else => false,
        };
    }

    /// Extract the f64 value from a numeric TValue. Call only when isNumberValue is true.
    pub fn toFloat(self: TValue) f64 {
        return switch (self) {
            .number => |n| n,
            .integer => |n| @as(f64, @floatFromInt(n)),
            else => unreachable,
        };
    }

    /// Extract the i64 value from a numeric TValue by truncating floats.
    /// Call only when isNumberValue is true.
    pub fn toIntegerExact(self: TValue) i64 {
        return switch (self) {
            .integer => |n| n,
            .number => |n| @as(i64, @intFromFloat(n)),
            else => unreachable,
        };
    }

    /// Convert a numeric TValue to an integer, returning `null` when the value
    /// has no exact integer representation (non-integral float, or out of i64
    /// range). Unlike `toIntegerExact`, this never traps.
    pub fn toIntegerExactOpt(self: TValue) ?i64 {
        return switch (self) {
            .integer => |n| n,
            .number => |n| blk: {
                if (n == @floor(n) and n >= -9223372036854775808.0 and n < 9223372036854775808.0) {
                    break :blk @as(i64, @intFromFloat(n));
                }
                break :blk null;
            },
            else => null,
        };
    }

    /// Convert a numeric TValue to an integer, requiring the value to have an
    /// exact integer representation. A non-integral float (e.g. 2.3) raises
    /// "number has no integer representation", matching PUC-Rio's F2Ieq rule
    /// for bitwise/shift operands.
    pub fn toIntegerExactE(self: TValue, L: *lua_State) !i64 {
        switch (self) {
            .integer => |n| return n,
            .number => |n| {
                // Exact integer representation: integral value within i64 range.
                if (n == @floor(n) and n >= -9223372036854775808.0 and n < 9223372036854775808.0) {
                    return @intFromFloat(n);
                }
                const ts = lstring.luaS_new(L, "number has no integer representation") catch null;
                if (ts) |t| {
                    L.stack[L.top] = TValue{ .string = t };
                    L.top += 1;
                } else {
                    L.stack[L.top] = TValue{ .nil = {} };
                    L.top += 1;
                }
                return error.RuntimeError;
            },
            else => unreachable,
        }
    }
};

pub const Node = struct {
    key: TValue,
    val: TValue,
    next: i32,
};

pub const lua_Table = struct {
    allocator: std.mem.Allocator,
    array: std.ArrayList(TValue),
    node: std.ArrayList(Node),
    lastfree: usize,
    lenhint: usize,
    metatable: ?*lua_Table = null,
    flags: u8 = 0,
    gc: ?*VMGCObject = null,
};

pub const lua_CClosure = struct {
    f: lua_CFunction,
    upvals: []TValue,
    gc: ?*VMGCObject = null,
};

pub const lua_LClosure = struct {
    p: *lua_Proto,
    upvals: []?*UpVal,
    gc: ?*VMGCObject = null,
};

pub const lua_Closure = union(enum) {
    c: *lua_CClosure,
    lua: *lua_LClosure,
};

pub const Upvaldesc = struct {
    name: ?*lua_TString = null,
    instack: u8 = 0,
    idx: u8 = 0,
    kind: u8 = 0,
};

pub const LocVar = struct {
    varname: ?*lua_TString = null,
    startpc: i32 = 0,
    endpc: i32 = 0,
};

pub const AbsLineInfo = struct {
    pc: i32 = 0,
    line: i32 = 0,
};

pub const lua_Proto = struct {
    source: ?*lua_TString,
    lineDefined: i32,
    lastLineDefined: i32,
    numParams: u8,
    isVarArg: bool,
    flag: u8 = 0,
    maxStackSize: u8,
    code: []lvm.Instruction,
    k: []TValue,
    p: []*lua_Proto,
    upvalues: []Upvaldesc,
    lineinfo: []i8,
    abslineinfo: []AbsLineInfo,
    locvars: []LocVar,
    is_sub: bool = false,
    gc: ?*VMGCObject = null,
};

pub fn createProto(allocator: std.mem.Allocator) !*lua_Proto {
    const f = try allocator.create(lua_Proto);
    f.* = .{
        .source = null,
        .lineDefined = 0,
        .lastLineDefined = 0,
        .numParams = 0,
        .isVarArg = false,
        .flag = 0,
        .maxStackSize = 0,
        .code = &.{},
        .k = &.{},
        .p = &.{},
        .upvalues = &.{},
        .lineinfo = &.{},
        .abslineinfo = &.{},
        .locvars = &.{},
    };
    return f;
}

pub fn destroyProto(allocator: std.mem.Allocator, f: *lua_Proto) void {
    if (f.code.len > 0) allocator.free(f.code);
    if (f.k.len > 0) allocator.free(f.k);
    if (f.p.len > 0) allocator.free(f.p);
    if (f.upvalues.len > 0) allocator.free(f.upvalues);
    if (f.lineinfo.len > 0) allocator.free(f.lineinfo);
    if (f.abslineinfo.len > 0) allocator.free(f.abslineinfo);
    if (f.locvars.len > 0) allocator.free(f.locvars);
    allocator.destroy(f);
}

pub fn findupval(L: *lua_State, idx: usize) !*UpVal {
    const target_ptr = &L.stack[idx];
    const target_addr = @intFromPtr(target_ptr);
    var prev: ?*UpVal = null;
    var curr = L.openupval;
    while (curr) |uv| {
        const addr = @intFromPtr(uv.v);
        if (addr == target_addr) {
            return uv;
        }
        if (addr < target_addr) {
            break;
        }
        prev = uv;
        curr = uv.next;
    }
    const uv = try L.allocator.create(UpVal);
    uv.* = .{
        .value = .{ .nil = {} },
        .v = target_ptr,
        .next = curr,
        .refcount = 0,
    };
    try registerGC(L, uv);
    if (prev) |p| {
        p.next = uv;
    } else {
        L.openupval = uv;
    }
    return uv;
}

fn close_one_slot(L: *lua_State, abs: usize, err_val: ?TValue) anyerror!?TValue {
    if (abs >= L.stack.len) return null;
    const v = L.stack[abs];
    if (v == .nil) return null;
    if (v == .boolean and v.boolean == false) return null;
    const mt = switch (v) {
        .table => |t| if (t) |x| x.metatable else null,
        .userdata => |u| if (u) |x| x.metatable else null,
        else => null,
    };
    const tm = if (mt) |m| ltm.luaT_gettm(m, .CLOSE, G(L).tmname[@intFromEnum(ltm.TMS.CLOSE)].?) else null;
    if (tm == null) {
        const msg = "attempt to call a nil value (metamethod 'close')";
        const ts = lstring.luaS_new(L, msg) catch {
            return TValue{ .nil = {} };
        };
        return TValue{ .string = ts };
    }
    const old_top = L.top;
    if (err_val) |err| {
        ltm.luaT_callTM2(L, tm.?, &v, &err) catch |e| {
            if (e == error.Yield) return e;
            const saved_err = if (L.top > old_top and L.top - 1 < L.stack.len) L.stack[L.top - 1] else TValue{ .nil = {} };
            L.top = old_top;
            if (e == error.NotAFunction) {
                const tname = switch (tm.?) {
                    .nil => "nil",
                    .boolean => "boolean",
                    .integer, .number => "number",
                    .string => "string",
                    .table => "table",
                    .function => "function",
                    .userdata => "userdata",
                    .thread => "thread",
                    .lightud, .upval, .proto => "???",
                };
                var buf: [128]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "attempt to call a {s} value (metamethod 'close')", .{tname}) catch "attempt to call a bad value (metamethod 'close')";
                const ts = lstring.luaS_new(L, msg) catch {
                    return saved_err;
                };
                return TValue{ .string = ts };
            }
            return saved_err;
        };
    } else {
        ltm.luaT_callTM1(L, tm.?, &v) catch |e| {
            if (e == error.Yield) return e;
            const saved_err = if (L.top > old_top and L.top - 1 < L.stack.len) L.stack[L.top - 1] else TValue{ .nil = {} };
            L.top = old_top;
            if (e == error.NotAFunction) {
                const tname = switch (tm.?) {
                    .nil => "nil",
                    .boolean => "boolean",
                    .integer, .number => "number",
                    .string => "string",
                    .table => "table",
                    .function => "function",
                    .userdata => "userdata",
                    .thread => "thread",
                    .lightud, .upval, .proto => "???",
                };
                var buf: [128]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "attempt to call a {s} value (metamethod 'close')", .{tname}) catch "attempt to call a bad value (metamethod 'close')";
                const ts = lstring.luaS_new(L, msg) catch {
                    return saved_err;
                };
                return TValue{ .string = ts };
            }
            return saved_err;
        };
    }
    return null;
}

pub fn closeupvals(L: *lua_State, limit: usize, err_val: ?TValue) !void {
    const lim = if (limit < L.stack.len) limit else L.stack.len;
    const limit_addr = @intFromPtr(&L.stack[lim]);
    while (L.openupval) |uv| {
        const addr = @intFromPtr(uv.v);
        if (addr >= limit_addr) {
            const base = @intFromPtr(L.stack.ptr);
            const end = base + L.stack.len * @sizeOf(TValue);
            if (addr >= base and addr < end) {
                uv.value = uv.v.*;
            } else {
                uv.value = .{ .nil = {} };
            }
            uv.v = &uv.value;
            L.openupval = uv.next;
        } else {
            break;
        }
    }

    var has_err = (err_val != null);
    var close_raised = false;
    var needs_err_push = (err_val != null);
    var err_idx: usize = 0;
    if (needs_err_push and L.top > 0) {
        err_idx = L.top - 1;
    }

    while (L.tbclist.items.len > 0) {
        const last_idx = L.tbclist.items.len - 1;
        const abs = L.tbclist.items[last_idx];
        if (abs >= limit) {
            _ = L.tbclist.pop();
            const current_err = if (has_err and err_idx < L.stack.len) L.stack[err_idx] else null;
            // Extend L.top past this and all remaining TBC entries so GC
            // (triggered by a __close handler calling collectgarbage()) can
            // trace them. poscall sets L.top below the function's locals,
            // leaving TBC variables invisible to the GC collector.
            const gc_safe_top = @max(L.top, abs + 1);
            if (gc_safe_top >= L.stack.len) {
                try growStack(L, gc_safe_top + 10);
            }
            const old_top = L.top;
            L.top = gc_safe_top;
            if (try close_one_slot(L, abs, current_err)) |new_err| {
                L.top = old_top;
                if (needs_err_push) {
                    if (err_idx < L.stack.len) {
                        L.stack[err_idx] = new_err;
                    }
                } else {
                    if (L.top >= L.stack.len) {
                        try growStack(L, L.top + 5);
                    }
                    L.stack[L.top] = new_err;
                    err_idx = L.top;
                    L.top += 1;
                    needs_err_push = true;
                }
                has_err = true;
                close_raised = true;
            } else {
                L.top = old_top;
            }
        } else {
            break;
        }
    }
    if (close_raised) {
        if (err_idx >= L.stack.len) {
            try growStack(L, err_idx + 2);
        }
        const final_err = L.stack[err_idx];
        L.top = err_idx + 1;
        L.stack[err_idx] = final_err;
        // A __close metamethod raised (or the value was not closable): record
        // the error object so the surrounding protected call reports it (this
        // path does not go through luaG_errormsg, which is what normally sets
        // L.err_obj).
        L.err_obj = final_err;
        return error.RuntimeError;
    }
}
pub fn luaD_hook(L: *lua_State, event: i32, line: i32, ftransfer: i32, ntransfer: i32) void {
    const hook = L.hook;
    if (hook != null and L.allowhook != 0) {
        const old_oldpc = L.oldpc;
        defer L.oldpc = old_oldpc;
        const old_top = L.top;
        const ci = L.ci.?;
        const old_is_hooked = ci.is_hooked;
        ci.is_hooked = true;
        defer ci.is_hooked = old_is_hooked;
        const old_ci_top = ci.top;
        var ar = lua_Debug{
            .event = event,
            .name = null,
            .namewhat = null,
            .what = null,
            .source = null,
            .srclen = 0,
            .currentline = line,
            .linedefined = 0,
            .lastlinedefined = 0,
            .nups = 0,
            .nparams = 0,
            .isvararg = false,
            .extraargs = 0,
            .istailcall = false,
            .ftransfer = ftransfer,
            .ntransfer = ntransfer,
            .short_src = std.mem.zeroes([LUA_IDSIZE]u8),
            .i_ci = ci,
        };
        L.transferinfo = .{
            .ftransfer = ftransfer,
            .ntransfer = ntransfer,
        };
        const val = L.stack[ci.func];
        if (val == .function and val.function.?.* == .lua) {
            if (L.top < ci.top) {
                L.top = ci.top;
            }
        }
        if (lua_checkstack(L, 20) != 0) {
            if (ci.top < L.top + 20) {
                ci.top = L.top + 20;
            }
        }
        L.allowhook = 0;
        hook.?(L, &ar);
        L.allowhook = 1;
        ci.top = old_ci_top;
        L.top = old_top;
    }
}

pub fn luaG_traceexec(L: *lua_State) void {
    if (L.hookmask == 0) return;
    const ci = L.ci orelse return;
    if (!isLua(ci, L)) return;
    const val = L.stack[ci.func];
    if (val != .function or val.function == null or val.function.?.* != .lua) return;
    const p = val.function.?.lua.p;
    const mask = L.hookmask;
    const pc: i32 = currentpc(ci);
    if (pc >= 0 and @as(usize, @intCast(pc)) < p.code.len) {
        const op = @as(lvm.OpCode, @enumFromInt(p.code[@intCast(pc)] & 0x7F));
        if (op == .VARARGPREP) {
            L.oldpc = -1;
            return;
        }
    }

    var counthook = false;
    if ((mask & llimits.LUA_MASKCOUNT) != 0) {
        if (L.hookcount > 0) {
            L.hookcount -= 1;
        }
        if (L.hookcount == 0) {
            counthook = true;
            L.hookcount = L.basehookcount;
        }
    }

    if (counthook) {
        luaD_hook(L, LUA_HOOKCOUNT, -1, 0, 0);
    }

    if ((mask & llimits.LUA_MASKLINE) != 0) {
        const oldpc: i32 = @intCast(L.oldpc);
        if (oldpc == -1 or pc < oldpc or changedline(p, oldpc, pc)) {
            // Mirror the reference: always call the line hook on a line
            // change. For stripped code (no debug info) luaG_getfuncline
            // returns -1, which the debug-lib hook converts to nil.
            const newline = luaG_getfuncline(p, pc);
            luaD_hook(L, LUA_HOOKLINE, newline, 0, 0);
        }
        L.oldpc = @intCast(pc);
    }
}

fn changedline(p: *const lua_Proto, oldpc: i32, newpc: i32) bool {
    const line1 = luaG_getfuncline(p, oldpc);
    const line2 = luaG_getfuncline(p, newpc);
    return line1 != line2;
}

pub fn poscall(L: *lua_State, ci: *CallInfo, first_result_idx: usize, n: usize) !void {
    L.top = first_result_idx + n;
    try closeupvals(L, ci.base, null);

    if (L.hookmask & llimits.LUA_MASKRET != 0) {
        // Mirror the reference rethook: by the time poscall runs, ci.func has
        // already been restored (OP_RETURN* / tail call undo the PF_VAHID
        // relocation), so ftransfer is just firstres - ci.func.
        const firstres = first_result_idx;
        const ftransfer = @as(i32, @intCast(firstres)) - @as(i32, @intCast(ci.func));
        luaD_hook(L, LUA_HOOKRET, -1, ftransfer, @as(i32, @intCast(n)));
    }
    const func_idx = ci.func;
    const nresults = ci.nresults;
    const old_top = L.top;
    var new_top: usize = undefined;
    if (nresults >= 0) {
        const copy_count = @min(@as(usize, @intCast(nresults)), n);
        var i: usize = 0;
        while (i < copy_count) : (i += 1) {
            L.stack[func_idx + i] = L.stack[first_result_idx + i];
        }
        while (i < @as(usize, @intCast(nresults))) : (i += 1) {
            L.stack[func_idx + i] = .{ .nil = {} };
        }
        new_top = func_idx + @as(usize, @intCast(nresults));
    } else {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            L.stack[func_idx + i] = L.stack[first_result_idx + i];
        }
        new_top = func_idx + n;
    }
    if (new_top < old_top) {
        @memset(L.stack[new_top..@min(old_top, L.stack.len)], .{ .nil = {} });
    }
    L.top = new_top;
    if (ci.previous) |prev| {
        if (isLua(prev, L)) {
            L.oldpc = currentpc(prev);
        }
    }
}

/// Recycle a CallInfo from the freelist, or allocate a fresh one. Mirrors
/// C Lua's pre-grown call stack: a CallInfo is only allocated when the pool is
/// empty, never on every call.
pub fn allocCallInfo(L: *lua_State) !*CallInfo {
    if (L.ci_free) |free| {
        L.ci_free = free.freenext;
        return free;
    }
    return try L.allocator.create(CallInfo);
}

/// Return a CallInfo to the freelist for reuse (instead of freeing it).
pub fn freeCallInfo(L: *lua_State, ci: *CallInfo) void {
    ci.freenext = L.ci_free;
    L.ci_free = ci;
}

/// Free every CallInfo owned by `L`: the active call chain above `base_ci`
/// and all recycled CallInfos in the freelist. Used when a coroutine finishes
/// or is explicitly closed, mirroring C Lua discarding a dead thread's stack.
fn freeAllCallInfos(L: *lua_State) void {
    var curr = L.ci;
    while (curr) |ci| {
        const prev = ci.previous;
        if (ci != &L.base_ci) L.allocator.destroy(ci);
        curr = prev;
    }
    var f = L.ci_free;
    while (f) |ci| {
        const nextf = ci.freenext;
        L.allocator.destroy(ci);
        f = nextf;
    }
    L.ci_free = null;
    L.ci = &L.base_ci;
    L.base_ci.next = null;
}

// Proto flag bits (mirror lua/ldo.h PF_*). A Lua function is vararg when its
// 'flag' carries PF_VAHID (hidden vararg args) or PF_VATAB (vararg table);
// such functions begin with OP_VARARGPREP, which relocates the frame and must
// read the real argument count from 'L->top'.
const PF_VAHID: u8 = 1; // function has hidden vararg arguments
const PF_VATAB: u8 = 2; // function has a vararg table

pub fn precall(L: *lua_State, func_idx: usize, nresults: i32) !?*CallInfo {
    var ccmt: usize = 0;
    while (L.stack[func_idx] != .function) {
        const val = L.stack[func_idx];
        const tm = ltm.luaT_gettmbyobj(L, val, .CALL);
        if (tm == .nil) {
            try luaG_callerror(L, val);
        }
        ccmt += 1;
        if (ccmt > 15) {
            try luaG_runerror(L, "'__call' chain too long");
        }
        if (lua_checkstack(L, 1) == 0) return error.StackOverflow;
        var p = L.top;
        while (p > func_idx) : (p -= 1) {
            L.stack[p] = L.stack[p - 1];
        }
        L.top += 1;
        L.stack[func_idx] = tm;
    }
    const val = L.stack[func_idx];
    const cl = val.function.?;
    const needed = switch (cl.*) {
        .c => L.top + 20,
        .lua => |lc| func_idx + 1 + @as(usize, lc.p.maxStackSize) + 20,
    };
    if (needed > L.stack.len) {
        if (L.stack.len > llimits.LUAI_MAXSTACK) {
            // The stack is already at ERRORSTACKSIZE: we are handling a stack
            // error (inside its error handler). A further growth request here
            // must report "error in error handling" (mirrors luaD_growstack's
            // `size > MAXSTACK` branch -> luaD_errerr).
            try luaG_runerror(L, "error in error handling");
        }
        if (needed > llimits.ERRORSTACKSIZE) {
            return error.StackOverflow;
        }
        if (needed > llimits.LUAI_MAXSTACK) {
            reserveErrorStack(L) catch return error.StackOverflow;
            try luaG_runerror(L, "stack overflow");
        }
        const extra = if (needed > L.top) needed - L.top else 20;
        if (lua_checkstack(L, @intCast(extra)) == 0) {
            return error.StackOverflow;
        }
    }
    if (func_idx >= 2) {
        // nothing
    }
    switch (cl.*) {
        .c => |cc| {
            L.nCcalls += 1;
            defer L.nCcalls -= 1;
            if (lua_checkstack(L, 20) == 0) return error.StackOverflow;
            const old_ci = L.ci;
            const new_ci = try allocCallInfo(L);
            new_ci.* = .{
                .func = func_idx,
                .base = func_idx + 1,
                .top = L.top + 20,
                .nresults = nresults,
                .savedpc = 0,
                .previous = old_ci,
                .next = null,
                .nextraargs = @intCast(ccmt),
            };
            if (old_ci) |prev| {
                prev.next = new_ci;
            }
            L.ci = new_ci;
            // Check the C-call limit only after L.ci points at the new C frame
            // (mirrors precallC): luaG_runerror then reports no source:line,
            // so the message is exactly "C stack overflow".
            if (L.nCcalls == llimits.LUAI_MAXCCALLS) {
                try luaG_runerror(L, "C stack overflow");
            } else if (L.nCcalls >= llimits.LUAI_MAXCCALLS * 11 / 10) {
                // We are already handling a stack overflow (the error handler
                // itself keeps raising). Raise DIRECTLY without re-invoking the
                // handler, mirroring luaD_errerr -> LUA_ERRERR; this is what
                // terminates the error-handler recursion.
                return luaD_errerr(L);
            }
            if (L.hookmask & llimits.LUA_MASKCALL != 0) {
                const narg = L.top - func_idx - 1;
                luaD_hook(L, LUA_HOOKCALL, -1, 1, @intCast(narg));
            }
            const n = cc.f(L) catch |e| {
                if (e == error.Yield) {
                    return error.Yield;
                }
                var curr = L.ci;
                while (curr) |c| {
                    if (c == old_ci) break;
                    const prev = c.previous;
                    if (c != &L.base_ci) {
                        L.allocator.destroy(c);
                    }
                    curr = prev;
                }
                L.ci = old_ci;
                if (old_ci) |prev| {
                    prev.next = null;
                }
                return e;
            };
            if (n < 0) {
                L.ci = old_ci;
                if (old_ci) |prev| {
                    prev.next = null;
                }
                freeCallInfo(L, new_ci);
                return error.RuntimeError;
            }
            const num_returned = @as(usize, @intCast(n));
            const first_result = L.top - num_returned;
            try poscall(L, new_ci, first_result, num_returned);
            L.ci = old_ci;
            if (old_ci) |prev| {
                prev.next = null;
            }
            freeCallInfo(L, new_ci);
            return null;
        },
        .lua => |lc| {
            const proto = lc.p;
            const num_params = proto.numParams;
            const base_idx = func_idx + 1;
            const frame_top = base_idx + proto.maxStackSize;
            const is_vararg = (proto.flag & (PF_VAHID | PF_VATAB)) != 0;
            try growStack(L, frame_top + 1);
            const num_args_passed = L.top - base_idx;
            if (num_args_passed < num_params) {
                var i = num_args_passed;
                while (i < num_params) : (i += 1) {
                    L.stack[base_idx + i] = .{ .nil = {} };
                }
                L.top = base_idx + num_params;
            }
            const new_ci = try allocCallInfo(L);
            new_ci.* = .{
                .func = func_idx,
                .base = base_idx,
                .top = frame_top,
                .nresults = nresults,
                .savedpc = 0,
                .previous = L.ci,
                .next = null,
                .nextraargs = @intCast(ccmt),
                .is_lua = true,
                .is_hooked = (L.allowhook == 0),
            };
            if (L.ci) |prev| {
                prev.next = new_ci;
            }
            L.oldpc = -1;
            // For non-vararg Lua functions, lift 'L->top' to the frame top so
            // that auxiliary calls (e.g. metamethod invocations via
            // luaT_callTMres) are placed above all live registers, matching the
            // reference behaviour (L->top = ci->top). Vararg functions are left
            // at the caller's top: their first instruction (OP_VARARGPREP)
            // calls luaT_adjustvarargs, which relies on 'L->top' still being the
            // caller's top (the real argument count) to compute the number of
            // varargs; buildhiddenargs then re-establishes 'L->top = ci->top'.
            if (!is_vararg) {
                L.top = frame_top;
            }
            L.ci = new_ci;
            if (L.hookmask & llimits.LUA_MASKCALL != 0) {
                luaD_hook(L, LUA_HOOKCALL, -1, 1, proto.numParams);
            }
            return new_ci;
        },
    }
}

pub const UpVal = struct {
    value: TValue,
    v: *TValue,
    next: ?*UpVal,
    refcount: usize = 0,
    gc: ?*VMGCObject = null,
};

pub const CallInfo = struct {
    func: usize,
    base: usize,
    top: usize,
    nresults: i32,
    savedpc: usize,
    previous: ?*CallInfo,
    next: ?*CallInfo,
    k: ?lua_KFunction = null,
    ctx: lua_KContext = 0,
    nyield: i32 = 0,
    // Number of "extra" (vararg) arguments passed to a vararg function.
    // Set by luaT_adjustvarargs; read by OP_VARARG/OP_GETVARG in the
    // hidden-vararg (PF_VAHID) path.
    nextraargs: i32 = 0,
    // Freelist link used by the CallInfo pool (lua.allocCallInfo /
    // lua.freeCallInfo). Kept separate from `next`/`previous` so the active
    // call-chain links remain intact for the debug API (lua_getinfo, etc.).
    freenext: ?*CallInfo = null,
    // Saved number of return values when OP_RETURN's closeupvals yields.
    // Mirrors C reference ci->u2.nres / CIST_CLSRET.
    nres_saved: i32 = 0,
    clsret: bool = false,
    /// Set while running a __gc finalizer, mirroring the reference's CIST_FIN.
    /// Also marks a protected call (CIST_YPCALL): when a coroutine resumes and
    /// the resumed frame errors, precover unwinds to the nearest frame with
    /// this flag and runs its error recovery.
    ypcall: bool = false,
    /// For a protected call frame (ypcall): the stack index of the called
    /// function, used to close remaining to-be-closed variables with the error
    /// (mirrors the reference's ci->u2.funcidx in finishpcallk).
    pcall_func: usize = 0,
    /// Set while a protected call's error recovery is interrupted by a
    /// yielding __close metamethod; recover_err holds the pending error. On
    /// resume, the recovery completes with this error.
    recovering: bool = false,
    recover_err: TValue = .{ .nil = {} },
    is_lua: bool = false,
    is_hooked: bool = false,
    /// Set while running a __gc finalizer, mirroring the reference's CIST_FIN.
    is_fin: bool = false,
    /// Set when this frame was created by a tail call (OP_TAILCALL reusing the
    /// caller's frame), mirroring the reference's CIST_TAIL. Read by the
    /// debug API's `t` option (debug.getinfo(..., "t").istailcall).
    is_tailcall: bool = false,
};

pub const GCColor = enum(u2) {
    white = 0,
    gray = 1,
    black = 2,
};

pub const VMGCObject = struct {
    next: ?*VMGCObject,
    val: ValUnion,
    color: GCColor = .white,
    /// True once this object's __gc metamethod has been called, so a later
    /// collection frees it without running the finalizer again.
    finalized: bool = false,
    /// Set by the pre-sweep pass when this (dead) object has an unrun __gc
    /// finalizer and its metatable has been kept alive for it.
    pending_fin: bool = false,

    pub const ValUnion = union(enum) {
        table: *lua_Table,
        closure: *lua_Closure,
        upval: *UpVal,
        proto: *lua_Proto,
        userdata: *lua_Udata,
        string: *lua_TString,
        thread: *lua_State,
    };
};

pub const global_State = struct {
    allocator: std.mem.Allocator,
    // C-API allocator view (lua_Alloc typedef). Wraps `allocator` so that
    // lua_getallocf/lua_setallocf present a drop-in-compatible allocator to
    // C callers. `alloc_wrapper` holds the std.mem.Allocator the thunk uses.
    allocf: lua_Alloc,
    alloc_ud: ?*anyopaque,
    alloc_wrapper: AllocWrapper,
    strt: std.array_hash_map.String(*lua_TString),
    // API string cache (mirrors the C reference `strcache`): reuses recently
    // created strings by content so consecutive identical literals share one
    // object. Entries may be null before first use.
    strcache: [llimits.STRCACHE_N][llimits.STRCACHE_M]?*lua_TString = undefined,
    seed: usize,
    registry: TValue,
    allgc: ?*VMGCObject = null,
    /// Objects awaiting their __gc finalizer (kept alive for one cycle).
    finobj: ?*VMGCObject = null,
    mt: [9]?*lua_Table = [_]?*lua_Table{null} ** 9,
    tmname: [25]?*lua_TString = [_]?*lua_TString{null} ** 25,
    io_backend: ?std.Io.Threaded = null,
    io: std.Io,
    prng_state: [4]u64,
    mainthread: ?*lua_State = null,
    thread_list: ?*lua_State = null,
    clibs: std.ArrayList(*std.DynLib),
    /// Cache of C-function closures with no upvalues (keyed by the C function
    /// pointer). The reference represents such functions as light values that
    /// do not allocate; reusing one closure per function makes every
    /// `lua_pushcfunction` allocation-free after the first use. The closures
    /// are rooted in the registry so the GC never collects them.
    cfunc_cache: std.AutoHashMapUnmanaged(lua_CFunction, *lua_Closure) = .empty,
    panic: ?lua_CFunction = null,
    gc_threshold: usize = 1000,
    gc_count: usize = 0,
    totalbytes: usize = 0,
    /// GC control: if false, GC is stopped (LUA_GCSTOP). Allocations still
    /// happen but do not trigger collection.
    gc_running: bool = true,
    /// Set to true while luaC_collectgarbage is executing; prevents re-entrant
    /// GC cycles that would reset marks and corrupt the live set.
    gc_in_progress: bool = false,
    /// GC parameters (get/set via LUA_GCPARAM). Initialised to defaults
    /// matching the C reference (lstate.c setgcparam calls).
    gcparams: [LUA_GCPN]u8 = [_]u8{ 10, 20, 50, 200, 200, 13 },
};

inline fn G(L: *lua_State) *global_State {
    return L.l_G orelse @panic("global state not initialized");
}

pub fn registerGC(L: *lua_State, val: anytype) !void {
    const g = L.l_G orelse return;
    const gc = try L.allocator.create(VMGCObject);
    const union_val = switch (@TypeOf(val)) {
        *lua_Table => VMGCObject.ValUnion{ .table = val },
        *lua_Closure => VMGCObject.ValUnion{ .closure = val },
        *UpVal => VMGCObject.ValUnion{ .upval = val },
        *lua_Proto => VMGCObject.ValUnion{ .proto = val },
        *lua_Udata => VMGCObject.ValUnion{ .userdata = val },
        *lua_TString => VMGCObject.ValUnion{ .string = val },
        *lua_State => VMGCObject.ValUnion{ .thread = val },
        else => @compileError("Unsupported type for GC registration"),
    };
    gc.* = .{
        .next = g.allgc,
        .val = union_val,
        .color = if (g.gc_in_progress) .black else .white,
    };
    switch (union_val) {
        .table => |t| t.gc = gc,
        .closure => |cl| switch (cl.*) {
            .c => |cc| cc.gc = gc,
            .lua => |lc| lc.gc = gc,
        },
        .userdata => |ud| ud.gc = gc,
        .proto => |pr| pr.gc = gc,
        .string => |ts| ts.gc = gc,
        .upval => |uv| uv.gc = gc,
        .thread => |th| th.gc = gc,
    }
    g.allgc = gc;
    g.gc_count += 1;

    const sz: usize = switch (union_val) {
        .table => |t| @sizeOf(lua_Table) + t.array.capacity * @sizeOf(TValue) + t.node.capacity * @sizeOf(Node),
        .string => |ts| @sizeOf(lua_TString) + ts.s.len + 1,
        .closure => |cl| switch (cl.*) {
            .c => |cc| @sizeOf(lua_Closure) + @sizeOf(lua_CClosure) + cc.upvals.len * @sizeOf(TValue),
            .lua => |lc| @sizeOf(lua_Closure) + @sizeOf(lua_LClosure) + lc.upvals.len * @sizeOf(?*UpVal),
        },
        .userdata => |ud| @sizeOf(lua_Udata) + ud.data.len + ud.uv.len * @sizeOf(TValue),
        .proto => @sizeOf(lua_Proto),
        .upval => @sizeOf(UpVal),
        .thread => |th| @sizeOf(lua_State) + th.stack.len * @sizeOf(TValue),
    };
    g.totalbytes += sz + @sizeOf(VMGCObject);
}

pub const GCObject = struct {
    tt: i8,
    marked: u8,
    gch: u32,
};

pub const lua_longjmp = struct {};

pub const lua_State = struct {
    tt: i8,
    marked: u8,
    gch: u32,
    allowhook: u8,
    status: u8,
    top: usize,
    l_G: ?*global_State,
    ci: ?*CallInfo,
    // Freelist of recycled CallInfo structs (see lua.allocCallInfo /
    // lua.freeCallInfo). Avoids per-call allocator churn.
    ci_free: ?*CallInfo = null,
    stack: []TValue,
    stack_last: usize,
    openupval: ?*UpVal,
    gc: ?*VMGCObject = null,
    tbclist: std.ArrayListUnmanaged(usize),
    gclist: ?*GCObject,
    twups: ?*lua_State,
    errorJmp: ?*lua_longjmp,
    base_ci: CallInfo,
    hook: ?lua_Hook,
    errfunc: isize,
    err_obj: TValue = .{ .nil = {} },
    /// Name of the function that raised the current error (and how it was
    /// called, e.g. "global"). Recorded by luaG_errormsg so a dead coroutine's
    /// debug.traceback can report "[C]: in global 'error'" even though the
    /// erroring C frame is unwound during propagation. Strings are anchored by
    /// the caller's proto constants / global table, so they stay alive.
    err_name: ?[]const u8 = null,
    err_namewhat: ?[]const u8 = null,
    nCcalls: u32,
    /// Number of non-yieldable contexts entered (mirrors the reference's high
    /// 16 bits of nCcalls). The main thread starts at 1; parsing increments it.
    /// `lua_isyieldable` is true iff this is zero.
    noyield: u32 = 0,
    oldpc: i32,
    nci: i32,
    basehookcount: i32,
    hookcount: i32,
    hookmask: u8,
    transferinfo: struct {
        ftransfer: i32,
        ntransfer: i32,
    },
    allocator: std.mem.Allocator,
};

pub fn idxPtr(L: *lua_State, idx: i32) ?*TValue {
    if (idx > 0) {
        // Positive indices are frame-relative: 1 = ci.base, 2 = ci.base+1, etc.
        // If there is no active call frame, treat as 1-based absolute index.
        const base: usize = if (L.ci) |ci| ci.base else 0;
        const u = base + @as(usize, @intCast(idx - 1));
        if (u < L.top) return &L.stack[u];
    } else if (idx == LUA_REGISTRYINDEX) {
        return &G(L).registry;
    } else if (idx < LUA_REGISTRYINDEX) {
        // Upvalue pseudo-index: lua_upvalueindex(n) = LUA_REGISTRYINDEX - n
        // Decode n-1 (0-based) from the index.
        const upn: usize = @intCast(LUA_REGISTRYINDEX - idx - 1);
        if (L.ci) |ci| {
            const func_val = L.stack[ci.func];
            if (func_val == .function) {
                if (func_val.function) |cl| {
                    if (cl.* == .c and upn < cl.c.upvals.len) {
                        return &cl.c.upvals[upn];
                    }
                }
            }
        }
        return null;
    } else if (idx < 0) {
        const abs = @as(usize, @intCast(-idx));
        if (abs <= L.top) return &L.stack[L.top - abs];
    }
    return null;
}

fn toAbsoluteIndex(L: *lua_State, idx: i32) usize {
    if (idx > 0) {
        const base: usize = if (L.ci) |ci| ci.base else 0;
        return base + @as(usize, @intCast(idx - 1));
    } else if (idx < 0) {
        const abs = @as(usize, @intCast(-idx));
        if (abs <= L.top) {
            return L.top - abs;
        }
        return 0;
    }
    return 0;
}

pub fn lua_absindex(L: *lua_State, idx: i32) i32 {
    if (idx > 0 or idx <= LUA_REGISTRYINDEX) return idx;
    return lua_gettop(L) + idx + 1;
}

pub fn lua_gettop(L: *lua_State) i32 {
    const base: usize = if (L.ci) |ci| ci.base else 0;
    return @as(i32, @intCast(L.top - base));
}

pub fn lua_settop(L: *lua_State, idx: i32) void {
    const base: usize = if (L.ci) |ci| ci.base else 0;
    if (idx >= 0) {
        const n = base + @as(usize, @intCast(idx));
        if (n < L.top) {
            @memset(L.stack[n..L.top], TValue{ .nil = {} });
        } else if (n > L.top) {
            @memset(L.stack[L.top..n], TValue{ .nil = {} });
        }
        L.top = n;
    } else {
        const abs_top = @as(i32, @intCast(L.top));
        const n = abs_top + 1 + idx;
        if (n >= @as(i32, @intCast(base))) {
            const un = @as(usize, @intCast(n));
            if (un < L.top) {
                @memset(L.stack[un..L.top], TValue{ .nil = {} });
            }
            L.top = un;
        }
    }
}

pub fn lua_pushvalue(L: *lua_State, idx: i32) void {
    const src = idxPtr(L, idx) orelse return;
    growStack(L, 1) catch return;
    L.stack[L.top] = src.*;
    L.top += 1;
}

pub fn lua_rotate(L: *lua_State, idx: i32, n: i32) void {
    const base: usize = if (L.ci) |ci| ci.base else 0;
    const abs_idx = toAbsoluteIndex(L, idx);
    if (abs_idx < base or abs_idx >= L.top) return;
    const len: i32 = @as(i32, @intCast(L.top - abs_idx));
    if (len <= 0) return;
    const rot: usize = @intCast(@mod(@mod(n, len) + len, len));
    if (rot == 0) return;
    const top_idx: usize = L.top - 1;
    // Reverse full range
    var i: usize = abs_idx;
    var j: usize = top_idx;
    while (i < j) : ({
        i += 1;
        j -= 1;
    }) {
        const t = L.stack[i];
        L.stack[i] = L.stack[j];
        L.stack[j] = t;
    }
    // Reverse first rot elements
    i = abs_idx;
    j = abs_idx + rot - 1;
    while (i < j) : ({
        i += 1;
        j -= 1;
    }) {
        const t = L.stack[i];
        L.stack[i] = L.stack[j];
        L.stack[j] = t;
    }
    // Reverse remaining elements
    i = abs_idx + rot;
    j = top_idx;
    while (i < j) : ({
        i += 1;
        j -= 1;
    }) {
        const t = L.stack[i];
        L.stack[i] = L.stack[j];
        L.stack[j] = t;
    }
}

pub inline fn lua_insert(L: *lua_State, idx: i32) void {
    lua_rotate(L, idx, 1);
}

pub inline fn lua_remove(L: *lua_State, idx: i32) void {
    lua_rotate(L, idx, -1);
    L.top -= 1;
}

pub inline fn lua_newtable(L: *lua_State) void {
    lua_createtable(L, 0, 0);
}

pub fn lua_copy(L: *lua_State, fromidx: i32, toidx: i32) void {
    const src = idxPtr(L, fromidx) orelse return;
    const dst = idxPtr(L, toidx) orelse return;
    dst.* = src.*;
}

pub fn growStack(L: *lua_State, needed: usize) !void {
    if (needed <= L.stack.len) return;
    // Normal stack growth never crosses the working limit; the ERRORSTACKSIZE
    // headroom is reserved separately (see reserveErrorStack) only when a
    // stack overflow is about to be raised, mirroring luaD_growstack.
    if (needed > llimits.LUAI_MAXSTACK) return error.StackOverflow;
    const new_cap = @min(@max(L.stack.len * 2, needed + LUA_MINSTACK + 20), llimits.LUAI_MAXSTACK);
    try reallocStack(L, new_cap);
}

/// Reserve the error-handling headroom: grow the stack to ERRORSTACKSIZE so
/// the error handler (e.g. debug.traceback) can run after a stack overflow.
fn reserveErrorStack(L: *lua_State) !void {
    if (L.stack.len >= llimits.ERRORSTACKSIZE) return;
    try reallocStack(L, llimits.ERRORSTACKSIZE);
}

/// Raise "error in error handling" WITHOUT invoking the error handler
/// (mirrors luaD_errerr -> LUA_ERRERR). Used to terminate the error-handler
/// recursion when the C-call stack is exhausted: calling luaG_runerror here
/// would re-invoke the handler and recurse forever.
fn luaD_errerr(L: *lua_State) anyerror {
    const ts = lstring.luaS_new(L, "error in error handling") catch null;
    if (ts) |t| {
        L.err_obj = TValue{ .string = t };
        if (L.top < L.stack.len) {
            L.stack[L.top] = L.err_obj;
            L.top += 1;
        }
    }
    return error.RuntimeError;
}

/// Shrink the stack back to a reasonable size after it was overgrown (e.g. by
/// a stack overflow). Mirrors luaD_shrinkstack: notably, it does NOT shrink
/// when the stack is still being used at/over the working limit (inuse >
/// MAXSTACK), because that is the error-handling recursion, which must keep
/// the ERRORSTACKSIZE headroom for nested handler invocations.
fn shrinkStack(L: *lua_State) void {
    var lim = L.top;
    var ci = L.ci;
    while (ci) |c| {
        if (lim < c.top) lim = c.top;
        ci = c.previous;
    }
    const inuse = @max(lim, @as(usize, @intCast(LUA_MINSTACK))) + 1;
    const max = if (inuse > llimits.LUAI_MAXSTACK / 3) llimits.LUAI_MAXSTACK else inuse * 3;
    if (inuse <= llimits.LUAI_MAXSTACK and L.stack.len > max) {
        // BUG-100: log instead of swallowing on shrink failure.
        _ = reallocStack(L, @max(max, @as(usize, @intCast(LUA_MINSTACK)))) catch |e| {
            std.debug.print("luazig: warning: stack shrink failed: {any}\n", .{e});
        };
    }
}

fn reallocStack(L: *lua_State, new_cap: usize) !void {
    const old_ptr = L.stack.ptr;
    const old_len = L.stack.len;
    const old_base = @intFromPtr(old_ptr);
    const old_end = old_base + old_len * @sizeOf(TValue);
    L.stack = try L.allocator.realloc(L.stack, new_cap);
    var curr = L.openupval;
    while (curr) |uv| {
        const uv_addr = @intFromPtr(uv.v);
        if (uv_addr >= old_base and uv_addr < old_end) {
            const uv_idx = (uv_addr -| old_base) / @sizeOf(TValue);
            uv.v = &L.stack[uv_idx];
        }
        curr = uv.next;
    }
    // BUG-088: Also fix up open upvalue pointers of all other threads in the
    // same state.  An upvalue on a suspended coroutine may point into this
    // thread's stack; if we only update L.openupval the secondary thread
    // retains dangling pointers after reallocation.
    if (L.l_G) |g| {
        var th: ?*lua_State = g.thread_list;
        while (th) |t| {
            if (t != L) {
                var uv2 = t.openupval;
                while (uv2) |uv2_| {
                    const uv_addr2 = @intFromPtr(uv2_.v);
                    if (uv_addr2 >= old_base and uv_addr2 < old_end) {
                        const uv_idx2 = (uv_addr2 -| old_base) / @sizeOf(TValue);
                        uv2_.v = &L.stack[uv_idx2];
                    }
                    uv2 = uv2_.next;
                }
            }
            th = t.twups;
        }
    }
    if (new_cap > old_len) {
        @memset(L.stack[old_len..new_cap], .{ .nil = {} });
    }
    L.stack_last = L.stack.len - 1;
}

pub fn lua_checkstack(L: *lua_State, n: i32) i32 {
    if (n <= 0) return 1;
    const extra = @as(usize, @intCast(n));
    if (extra > llimits.LUAI_MAXSTACK) return 0;
    const needed = L.top + extra;
    // The stack may grow past LUAI_MAXSTACK up to ERRORSTACKSIZE: that
    // headroom is what lets the error handler (debug.traceback) run after a
    // stack overflow (mirrors luaD_growstack's 'ERRORSTACKSIZE' branch).
    if (needed > llimits.ERRORSTACKSIZE) return 0;
    growStack(L, needed) catch return 0;
    return 1;
}

pub fn lua_xmove(from: *lua_State, to: *lua_State, n: i32) void {
    if (n <= 0) return;
    const nn = @as(usize, @intCast(n));
    if (nn > from.top) return;
    const avail = to.stack.len - to.top;
    const to_copy = @min(nn, avail);
    @memcpy(to.stack[to.top..][0..to_copy], from.stack[from.top - to_copy .. from.top]);
    from.top -= to_copy;
    to.top += to_copy;
}

pub fn stackAt(L: *lua_State, idx: i32) TValue {
    const ptr = idxPtr(L, idx) orelse return TValue{ .nil = {} };
    return ptr.*;
}

pub inline fn lua_isnoneornil(L: *lua_State, idx: i32) bool {
    return lua_type(L, idx) <= 0;
}

// ===================================================================
// H.7 — Convenience macros (port of lua.h macro definitions)
// ===================================================================

/// Register a C function as a global. Equivalent to
/// `lua_pushcfunction(L, f); lua_setglobal(L, n)`.
pub inline fn lua_register(L: *lua_State, name: []const u8, func: lua_CFunction) !void {
    lua_pushcfunction(L, func);
    try lua_setglobal(L, name);
}

/// Push the global environment table onto the stack. Equivalent to
/// `lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS)`.
pub inline fn lua_pushglobaltable(L: *lua_State) void {
    _ = lua_rawgeti(L, LUA_REGISTRYINDEX, llimits.LUA_RIDX_GLOBALS);
}

/// Push a string literal (or any `[]const u8`) onto the stack.
pub inline fn lua_pushliteral(L: *lua_State, s: []const u8) ?[]const u8 {
    return lua_pushstring(L, s);
}

/// Return true if the value at `idx` is a function.
pub inline fn lua_isfunction(L: *lua_State, n: i32) bool {
    return lua_type(L, n) == LUA_TFUNCTION;
}

/// Return true if the value at `idx` is a thread (coroutine).
pub inline fn lua_isthread(L: *lua_State, n: i32) bool {
    return lua_type(L, n) == LUA_TTHREAD;
}

/// Return true if the value at `idx` is light userdata.
pub inline fn lua_islightuserdata(L: *lua_State, n: i32) bool {
    return lua_type(L, n) == LUA_TLIGHTUSERDATA;
}

pub fn lua_isnone(L: *lua_State, idx: i32) i32 {
    return if (lua_type(L, idx) == LUA_TNONE) 1 else 0;
}

pub fn lua_isnil(L: *lua_State, idx: i32) i32 {
    return if (lua_type(L, idx) == LUA_TNIL) 1 else 0;
}

pub fn lua_isboolean(L: *lua_State, idx: i32) i32 {
    return if (lua_type(L, idx) == LUA_TBOOLEAN) 1 else 0;
}

pub fn lua_istable(L: *lua_State, idx: i32) i32 {
    return if (lua_type(L, idx) == LUA_TTABLE) 1 else 0;
}

pub fn lua_isnumber(L: *lua_State, idx: i32) i32 {
    const v = stackAt(L, idx);
    return switch (v) {
        .number => 1,
        .integer => 1,
        else => 0,
    };
}

pub fn lua_isstring(L: *lua_State, idx: i32) i32 {
    const v = stackAt(L, idx);
    return switch (v) {
        .string => 1,
        .number => 1,
        .integer => 1,
        else => 0,
    };
}

pub fn lua_iscfunction(L: *lua_State, idx: i32) i32 {
    const v = stackAt(L, idx);
    if (v != .function) return 0;
    const cl = v.function orelse return 0;
    return switch (cl.*) {
        .c => 1,
        .lua => 0,
    };
}

pub fn lua_isinteger(L: *lua_State, idx: i32) i32 {
    const v = stackAt(L, idx);
    return switch (v) {
        .integer => 1,
        else => 0,
    };
}

pub fn lua_isuserdata(L: *lua_State, idx: i32) i32 {
    const v = stackAt(L, idx);
    return switch (v) {
        .userdata => 1,
        .lightud => 1,
        else => 0,
    };
}

pub fn lua_type(L: *lua_State, idx: i32) i32 {
    // Match the reference lua_type: an invalid (out-of-range) index yields
    // LUA_TNONE, not LUA_TNIL. This is what luaL_checkany/checktype/checknumber
    // rely on to validate argument presence.
    const ptr = idxPtr(L, idx) orelse return LUA_TNONE;
    return ptr.typ();
}

pub fn lua_typename(tp: i32) []const u8 {
    return switch (tp) {
        LUA_TNONE => "no value",
        LUA_TNIL => "nil",
        LUA_TBOOLEAN => "boolean",
        LUA_TLIGHTUSERDATA => "light userdata",
        LUA_TNUMBER => "number",
        LUA_TSTRING => "string",
        LUA_TTABLE => "table",
        LUA_TFUNCTION => "function",
        LUA_TUSERDATA => "userdata",
        LUA_TTHREAD => "thread",
        else => "unknown",
    };
}

pub fn lua_tonumberx(L: *lua_State, idx: i32, isnum: ?*i32) ?f64 {
    const v = stackAt(L, idx);
    const num = toNumeric(v);
    if (num) |val| {
        if (isnum) |p| p.* = 1;
        return switch (val) {
            .integer => |n| @as(f64, @floatFromInt(n)),
            .number => |n| n,
            else => unreachable,
        };
    }
    if (isnum) |p| p.* = 0;
    return null;
}

pub fn lua_tointegerx(L: *lua_State, idx: i32, isnum: ?*i32) ?i64 {
    const v = stackAt(L, idx);
    const num = toNumeric(v);
    const min_f64 = @as(f64, -9223372036854775808.0);
    const max_exclusive_f64 = @as(f64, 9223372036854775808.0);
    if (num) |val| {
        switch (val) {
            .integer => |n| {
                if (isnum) |p| p.* = 1;
                return n;
            },
            .number => |n| {
                const f = @floor(n);
                if (n == f and f >= min_f64 and f < max_exclusive_f64) {
                    if (isnum) |p| p.* = 1;
                    return @as(i64, @intFromFloat(f));
                }
            },
            else => unreachable,
        }
    }
    if (isnum) |p| p.* = 0;
    return null;
}

pub fn lua_tonumber(L: *lua_State, idx: i32) ?f64 {
    return lua_tonumberx(L, idx, null);
}

pub fn lua_tointeger(L: *lua_State, idx: i32) ?i64 {
    return lua_tointegerx(L, idx, null);
}

pub fn lua_toboolean(L: *lua_State, idx: i32) i32 {
    const v = stackAt(L, idx);
    return if (v.toBoolean()) 1 else 0;
}

extern "c" fn snprintf(buf: [*]u8, size: usize, format: [*]const u8, ...) c_int;
extern "c" fn strtod(nptr: [*:0]const u8, endptr: ?*?[*:0]const u8) f64;
extern "c" fn strspn(str1: [*]const u8, str2: [*]const u8) usize;

pub fn tostringbuffFloat(n: f64, buff: *[128]u8) usize {
    var len = snprintf(buff, 128, "%.15g", n);
    if (len < 0) return 0;
    buff[@intCast(len)] = 0;
    const check = strtod(@ptrCast(buff), null);
    if (check != n) {
        len = snprintf(buff, 128, "%.17g", n);
        if (len < 0) return 0;
        buff[@intCast(len)] = 0;
    }
    const idx = strspn(buff, "-0123456789");
    if (buff[idx] == 0) {
        const ulen: usize = @intCast(len);
        buff[ulen] = '.';
        buff[ulen + 1] = '0';
        buff[ulen + 2] = 0;
        return ulen + 2;
    }
    return @intCast(len);
}

pub fn luaO_tostringbuff(val: TValue, buff: *[128]u8) []const u8 {
    return switch (val) {
        .integer => |i| std.fmt.bufPrint(buff, "{d}", .{i}) catch "",
        .number => |n| {
            if (std.math.isNan(n)) {
                return "nan";
            } else if (std.math.isInf(n)) {
                return if (n < 0) "-inf" else "inf";
            }
            const len = tostringbuffFloat(n, buff);
            return buff[0..len];
        },
        .string => |s| if (s) |str| str.s else "",
        else => "",
    };
}

pub fn lua_tolstring(L: *lua_State, idx: i32, len: ?*usize) ?[]const u8 {
    const ptr = idxPtr(L, idx) orelse return null;
    switch (ptr.*) {
        .string => |s| {
            if (len) |p| p.* = s.?.len;
            return s.?.s;
        },
        .integer, .number => {
            var buf: [128]u8 = undefined;
            const s = luaO_tostringbuff(ptr.*, &buf);
            const ts = lstring.luaS_new(L, s) catch return null;
            ptr.* = TValue{ .string = ts };
            if (len) |p| p.* = ts.len;
            return ts.s;
        },
        else => return null,
    }
}

pub fn lua_rawlen(L: *lua_State, idx: i32) usize {
    const v = stackAt(L, idx);
    return switch (v) {
        .string => |s| s.?.len,
        .table => |t| {
            if (t) |tp| return ltable.getn(tp);
            return 0;
        },
        else => 0,
    };
}

pub fn lua_tocfunction(L: *lua_State, idx: i32) lua_CFunction {
    const v = stackAt(L, idx);
    return switch (v) {
        .function => |f| if (f) |cl| switch (cl.*) {
            .c => |cc| cc.f,
            else => undefined,
        } else undefined,
        else => undefined,
    };
}

pub fn lua_touserdata(L: *lua_State, idx: i32) ?*anyopaque {
    const v = stackAt(L, idx);
    return switch (v) {
        .userdata => |u| if (u) |p| @as(*anyopaque, @ptrCast(p.data.ptr)) else null,
        .lightud => |u| u,
        else => null,
    };
}

pub fn lua_tothread(L: *lua_State, idx: i32) ?*lua_State {
    const v = stackAt(L, idx);
    return switch (v) {
        .thread => |t| t,
        else => null,
    };
}

pub fn lua_topointer(L: *lua_State, idx: i32) ?*anyopaque {
    const v = stackAt(L, idx);
    return switch (v) {
        .string => |s| if (s) |p| @as(*anyopaque, @ptrCast(p)) else null,
        .table => |t| if (t) |p| @as(*anyopaque, @ptrCast(p)) else null,
        .function => |f| if (f) |p| @as(*anyopaque, @ptrCast(p)) else null,
        .userdata => |u| if (u) |p| @as(*anyopaque, @ptrCast(p)) else null,
        .lightud => |u| u,
        .thread => |t| if (t) |p| @as(*anyopaque, @ptrCast(p)) else null,
        else => null,
    };
}

fn numMod(a: f64, b: f64) f64 {
    var m = libm.getLibm().fmod(a, b);
    if (if (m > 0) b < 0 else (m < 0 and b > 0)) {
        m += b;
    }
    return m;
}

pub fn luaV_shift(x: i64, s: i64) i64 {
    const ux = @as(u64, @bitCast(x));
    const nbits: i64 = 64;
    if (s < 0) {
        // Arithmetic shift right by -s.
        if (s <= -nbits) return 0;
        return @as(i64, @bitCast(ux >> @as(u6, @intCast(-s))));
    }
    // Logical shift left by s.
    if (s >= nbits) return 0;
    return @as(i64, @bitCast(ux << @as(u6, @intCast(s))));
}

/// Try to convert a TValue to a numeric TValue (integer or float).
/// For strings, attempts number parsing. Returns null if not numeric.
pub fn toNumeric(v: TValue) ?TValue {
    return switch (v) {
        .integer => v,
        .number => v,
        .string => |s| {
            const str = s orelse return null;
            // Locale-aware parse (mirrors lua_stringtonumber via tonumberValue).
            return tonumberValue(str.s);
        },
        else => null,
    };
}

pub fn lua_arith(L: *lua_State, op: i32) !void {
    if (op < 0 or op > 13) return;
    const is_unary = (op == LUA_OPUNM or op == LUA_OPBNOT);
    if (is_unary) {
        if (L.top < 1) return;
        const p1 = L.stack[L.top - 1];
        if (p1 == .integer) {
            const result = switch (op) {
                LUA_OPUNM => @as(TValue, .{ .integer = 0 -% p1.integer }),
                LUA_OPBNOT => @as(TValue, .{ .integer = ~p1.integer }),
                else => unreachable,
            };
            L.stack[L.top - 1] = result;
        } else if (p1 == .number) {
            const result = switch (op) {
                LUA_OPUNM => @as(TValue, .{ .number = -p1.number }),
                LUA_OPBNOT => @as(TValue, .{ .number = @floatFromInt(~@as(i64, @intFromFloat(p1.number))) }),
                else => unreachable,
            };
            L.stack[L.top - 1] = result;
        } else {
            const event: ltm.TMS = switch (op) {
                LUA_OPUNM => .UNM,
                LUA_OPBNOT => .BNOT,
                else => unreachable,
            };
            try ltm.luaT_trybinTM(L, &p1, &p1, L.top - 1, event);
        }
    } else {
        if (L.top < 2) return;
        const p1 = L.stack[L.top - 2];
        const p2 = L.stack[L.top - 1];
        const num1 = toNumeric(p1);
        const num2 = toNumeric(p2);
        if (num1) |n1| {
            if (num2) |n2| {
                if (n1 == .integer and n2 == .integer) {
                    const result = switch (op) {
                        LUA_OPADD => @as(TValue, .{ .integer = n1.integer +% n2.integer }),
                        LUA_OPSUB => @as(TValue, .{ .integer = n1.integer -% n2.integer }),
                        LUA_OPMUL => @as(TValue, .{ .integer = n1.integer *% n2.integer }),
                        LUA_OPMOD => blk: {
                            const ib = n1.integer;
                            const ic = n2.integer;
                            const r = if (ic == 0 or ic == -1) @as(i64, 0) else @rem(ib, ic);
                            break :blk TValue{ .integer = if (r != 0 and (r ^ ic) < 0) r +% ic else r };
                        },
                        LUA_OPPOW => @as(TValue, .{ .number = libm.getLibm().pow(@as(f64, @floatFromInt(n1.integer)), @as(f64, @floatFromInt(n2.integer))) }),
                        LUA_OPDIV => @as(TValue, .{ .number = @as(f64, @floatFromInt(n1.integer)) / @as(f64, @floatFromInt(n2.integer)) }),
                        LUA_OPIDIV => blk: {
                            const ib = n1.integer;
                            const ic = n2.integer;
                            // Handle minint / -1 (overflows as wrapping) and /0
                            const q: i64 = if (ic == 0) 0 else if (ic == -1) 0 -% ib else @divTrunc(ib, ic);
                            const r: i64 = if (ic == 0 or ic == -1) 0 else @rem(ib, ic);
                            break :blk TValue{ .integer = if (r == 0 or (ib >= 0) == (ic >= 0)) q else q - 1 };
                        },
                        LUA_OPBAND => @as(TValue, .{ .integer = n1.integer & n2.integer }),
                        LUA_OPBOR => @as(TValue, .{ .integer = n1.integer | n2.integer }),
                        LUA_OPBXOR => @as(TValue, .{ .integer = n1.integer ^ n2.integer }),
                        LUA_OPSHL => @as(TValue, .{ .integer = luaV_shift(n1.integer, n2.integer) }),
                        LUA_OPSHR => @as(TValue, .{ .integer = luaV_shift(n1.integer, -%n2.integer) }),
                        else => unreachable,
                    };
                    L.top -= 1;
                    L.stack[L.top - 1] = result;
                } else if (n1.isNumberValue() and n2.isNumberValue()) {
                    const f1 = n1.toFloat();
                    const f2 = n2.toFloat();
                    const result: f64 = switch (op) {
                        LUA_OPADD => f1 + f2,
                        LUA_OPSUB => f1 - f2,
                        LUA_OPMUL => f1 * f2,
                        LUA_OPMOD => numMod(f1, f2),
                        LUA_OPPOW => libm.getLibm().pow(f1, f2),
                        LUA_OPDIV => f1 / f2,
                        LUA_OPIDIV => @floor(f1 / f2),
                        LUA_OPBAND => blk: {
                            const ival1 = n1.toIntegerExactOpt() orelse return luaG_runerror(L, "number has no integer representation");
                            const ival2 = n2.toIntegerExactOpt() orelse return luaG_runerror(L, "number has no integer representation");
                            break :blk @floatFromInt(ival1 & ival2);
                        },
                        LUA_OPBOR => blk: {
                            const ival1 = n1.toIntegerExactOpt() orelse return luaG_runerror(L, "number has no integer representation");
                            const ival2 = n2.toIntegerExactOpt() orelse return luaG_runerror(L, "number has no integer representation");
                            break :blk @floatFromInt(ival1 | ival2);
                        },
                        LUA_OPBXOR => blk: {
                            const ival1 = n1.toIntegerExactOpt() orelse return luaG_runerror(L, "number has no integer representation");
                            const ival2 = n2.toIntegerExactOpt() orelse return luaG_runerror(L, "number has no integer representation");
                            break :blk @floatFromInt(ival1 ^ ival2);
                        },
                        LUA_OPSHL => blk: {
                            const ival1 = n1.toIntegerExactOpt() orelse return luaG_runerror(L, "number has no integer representation");
                            const ival2 = n2.toIntegerExactOpt() orelse return luaG_runerror(L, "number has no integer representation");
                            break :blk @floatFromInt(luaV_shift(ival1, ival2));
                        },
                        LUA_OPSHR => blk: {
                            const ival1 = n1.toIntegerExactOpt() orelse return luaG_runerror(L, "number has no integer representation");
                            const ival2 = n2.toIntegerExactOpt() orelse return luaG_runerror(L, "number has no integer representation");
                            break :blk @floatFromInt(luaV_shift(ival1, -%ival2));
                        },
                        else => unreachable,
                    };
                    L.top -= 1;
                    L.stack[L.top - 1] = TValue{ .number = result };
                }
            }
        } else {
            const event: ltm.TMS = switch (op) {
                LUA_OPADD => .ADD,
                LUA_OPSUB => .SUB,
                LUA_OPMUL => .MUL,
                LUA_OPMOD => .MOD,
                LUA_OPPOW => .POW,
                LUA_OPDIV => .DIV,
                LUA_OPIDIV => .IDIV,
                LUA_OPBAND => .BAND,
                LUA_OPBOR => .BOR,
                LUA_OPBXOR => .BXOR,
                LUA_OPSHL => .SHL,
                LUA_OPSHR => .SHR,
                else => unreachable,
            };
            try ltm.luaT_trybinTM(L, &p1, &p2, L.top - 2, event);
            L.top -= 1;
        }
    }
}

pub fn luaV_rawequalobj(t1: TValue, t2: TValue) bool {
    if (t1 == .number and t2 == .number) {
        return t1.number == t2.number;
    }
    if (t1 == .integer and t2 == .integer) {
        return t1.integer == t2.integer;
    }
    if (t1 == .integer and t2 == .number) {
        const i = t1.integer;
        const f = t2.number;
        return f == @as(f64, @floatFromInt(i)) and i == @as(i64, @intFromFloat(f));
    }
    if (t1 == .number and t2 == .integer) {
        const f = t1.number;
        const i = t2.integer;
        return f == @as(f64, @floatFromInt(i)) and i == @as(i64, @intFromFloat(f));
    }
    if (@as(std.meta.Tag(TValue), t1) != @as(std.meta.Tag(TValue), t2)) {
        return false;
    }
    return switch (t1) {
        .nil => true,
        .boolean => |b| b == t2.boolean,
        .number => |n| n == t2.number,
        .integer => |n| n == t2.integer,
        .lightud => |p| p == t2.lightud,
        .string => |s| blk: {
            const t2s = t2.string;
            if (s == null and t2s == null) break :blk true;
            if (s == null or t2s == null) break :blk false;
            break :blk lstring.luaS_eqstr(s.?, t2s.?);
        },
        .function => |f| f == t2.function,
        .table => |t| t == t2.table,
        .userdata => |u| u == t2.userdata,
        .thread => |t| t == t2.thread,
        .upval => |u| u == t2.upval,
        .proto => |p| p == t2.proto,
    };
}

pub fn lua_rawequal(L: *lua_State, idx1: i32, idx2: i32) i32 {
    const a = stackAt(L, idx1);
    const b = stackAt(L, idx2);
    return if (luaV_rawequalobj(a, b)) 1 else 0;
}

pub fn lua_compare(L: *lua_State, idx1: i32, idx2: i32, op: i32) i32 {
    const a = stackAt(L, idx1);
    const b = stackAt(L, idx2);
    const res = switch (op) {
        LUA_OPEQ => ltm.luaT_equalobj(L, a, b) catch false,
        LUA_OPLT => ltm.luaT_lt(L, a, b) catch false,
        LUA_OPLE => ltm.luaT_le(L, a, b) catch false,
        else => false,
    };
    return if (res) 1 else 0;
}

pub fn lua_pushnil(L: *lua_State) void {
    if (L.top + 1 >= L.stack.len) _ = lua_checkstack(L, 2);
    L.stack[L.top] = TValue{ .nil = {} };
    L.top += 1;
}

pub fn lua_pushnumber(L: *lua_State, n: lua_Number) void {
    if (L.top + 1 >= L.stack.len) _ = lua_checkstack(L, 2);
    L.stack[L.top] = TValue{ .number = n };
    L.top += 1;
}

pub fn lua_pushinteger(L: *lua_State, n: lua_Integer) void {
    if (L.top + 1 >= L.stack.len) _ = lua_checkstack(L, 2);
    L.stack[L.top] = TValue{ .integer = n };
    L.top += 1;
}

pub fn lua_pushlstring(L: *lua_State, s: []const u8, len: usize) ?[]const u8 {
    if (L.top >= L.stack.len) {
        if (lua_checkstack(L, 1) == 0) return null;
    }
    const ts = lstring.luaS_new(L, s[0..len]) catch return null;
    L.stack[L.top] = TValue{ .string = ts };
    L.top += 1;
    return ts.s;
}

pub fn lua_pushstring(L: *lua_State, s: []const u8) ?[]const u8 {
    return lua_pushlstring(L, s, s.len);
}

/// Lua 5.5 `lua_pushexternalstring`: push a string whose bytes are owned by a
/// caller-provided allocator rather than copied by Lua. `s[0..len]` is the
/// string content (the C contract requires `s[len] == 0`); `falloc`/`ud` are
/// the external `lua_Alloc` and its user data. When `falloc` is non-null
/// (LSTRMEM) Lua takes ownership of the bytes and frees them via `falloc` when
/// the string is collected; when `falloc` is null (LSTRFIX) the bytes are
/// static and never freed. External strings are never interned, so equal
/// content yields distinct `lua_TString` objects. Returns the string content
/// pointer, or `null` on out-of-memory (in which case an LSTRMEM external
/// buffer is freed back to `falloc`).
pub fn lua_pushexternalstring(
    L: *lua_State,
    s: []const u8,
    len: usize,
    falloc: ?lua_Alloc,
    ud: ?*anyopaque,
) ?[]const u8 {
    const g = G(L);
    const ts = L.allocator.create(lua_TString) catch {
        // Could not allocate the header; an LSTRMEM buffer we were meant to
        // own must be returned to its allocator.
        if (falloc) |f| _ = f(ud, @constCast(s.ptr), len + 1, 0);
        return null;
    };
    ts.* = .{
        .s = s[0..len],
        .len = len,
        // External strings share a constant hash (the C reference uses the
        // global seed), so they never collide with interned (content-hashed)
        // strings of equal content.
        .hash = @as(u32, @truncate(g.seed)),
        .externally_owned = true,
        .falloc = falloc,
        .ud = ud,
    };
    registerGC(L, ts) catch {
        if (falloc) |f| _ = f(ud, @constCast(ts.s.ptr), ts.len + 1, 0);
        L.allocator.destroy(ts);
        return null;
    };
    L.stack[L.top] = TValue{ .string = ts };
    L.top += 1;
    return ts.s;
}

pub fn lua_pushvfstring(L: *lua_State, fmt: []const u8, argp: ?*anyopaque) ?[]const u8 {
    _ = argp;
    return lua_pushstring(L, fmt);
}

pub fn lua_pushfstring(L: *lua_State, fmt: []const u8) ?[]const u8 {
    return lua_pushstring(L, fmt);
}

pub fn lua_pushcclosure(L: *lua_State, cfunc: lua_CFunction, n: i32) void {
    if (n == 0) {
        // No upvalues: reuse the cached closure for this C function (the
        // reference pushes a light function value here, which does not
        // allocate either). Root the closure in the registry so it survives.
        if (L.l_G) |g| {
            if (g.cfunc_cache.get(cfunc)) |cached| {
                L.stack[L.top] = TValue{ .function = cached };
                L.top += 1;
                return;
            }
        }
        const cc = L.allocator.create(lua_CClosure) catch return;
        cc.* = .{ .f = cfunc, .upvals = &.{} };
        const cl = L.allocator.create(lua_Closure) catch {
            L.allocator.destroy(cc);
            return;
        };
        cl.* = lua_Closure{ .c = cc };
        registerGC(L, cl) catch {
            L.allocator.destroy(cc);
            L.allocator.destroy(cl);
            return;
        };
        // Root in the registry: registry[cfunc-as-lightuserdata] = closure.
        if (L.l_G) |g| {
            const reg = g.registry.table orelse return;
            ltable.set(reg, TValue{ .lightud = @ptrCast(@constCast(cfunc)) }, TValue{ .function = cl }) catch {};
            g.cfunc_cache.put(L.allocator, cfunc, cl) catch {};
        }
        growStack(L, 1) catch return;
        L.stack[L.top] = TValue{ .function = cl };
        L.top += 1;
        return;
    }
    const upvals = L.allocator.alloc(TValue, @intCast(n)) catch return;
    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) : (i += 1) {
        const stack_idx = L.top - @as(usize, @intCast(n)) + i;
        upvals[i] = L.stack[stack_idx];
    }
    L.top -= @as(usize, @intCast(n));

    const cc = L.allocator.create(lua_CClosure) catch {
        L.allocator.free(upvals);
        return;
    };
    cc.* = .{ .f = cfunc, .upvals = upvals };
    const cl = L.allocator.create(lua_Closure) catch {
        L.allocator.free(upvals);
        L.allocator.destroy(cc);
        return;
    };
    cl.* = lua_Closure{ .c = cc };
    registerGC(L, cl) catch {
        L.allocator.free(upvals);
        L.allocator.destroy(cc);
        L.allocator.destroy(cl);
        return;
    };
    L.stack[L.top] = TValue{ .function = cl };
    L.top += 1;
}

/// Shorthand: push a C function with no upvalues.
pub fn lua_pushcfunction(L: *lua_State, cfunc: lua_CFunction) void {
    lua_pushcclosure(L, cfunc, 0);
}

/// Convert an upvalue index (1-based) to a pseudo-index.
/// Mirrors the C macro: #define lua_upvalueindex(i) (LUA_REGISTRYINDEX - (i))
pub fn lua_upvalueindex(i: i32) i32 {
    return LUA_REGISTRYINDEX - i;
}

/// Get the value of upvalue `n` (1-based) of the C closure at the top of the
/// current call frame.  Returns nil if `n` is out of range.
pub fn lua_getupvalue(L: *lua_State, funcindex: i32, n: i32) ?[]const u8 {
    if (funcindex <= LUA_REGISTRYINDEX) return null;
    const abs = toAbsoluteIndex(L, funcindex);
    if (abs >= L.top) return null;
    const func_val = L.stack[abs];
    if (func_val != .function) return null;
    const cl = func_val.function orelse return null;

    const upn = n - 1;
    if (upn < 0) return null;
    switch (cl.*) {
        .c => |ccl| {
            if (upn >= ccl.upvals.len) return null;
            L.stack[L.top] = ccl.upvals[@intCast(upn)];
            L.top += 1;
            return ""; // unnamed
        },
        .lua => |lcl| {
            if (upn >= lcl.upvals.len) return null;
            const uv = lcl.upvals[@intCast(upn)] orelse return null;
            L.stack[L.top] = uv.v.*;
            L.top += 1;
            if (upn < lcl.p.upvalues.len) {
                if (lcl.p.upvalues[@intCast(upn)].name) |name_ts| {
                    return name_ts.s;
                }
            }
            return "(no name)";
        },
    }
}

pub fn lua_setupvalue(L: *lua_State, funcindex: i32, n: i32) ?[]const u8 {
    if (L.top == 0) return null;
    if (funcindex <= LUA_REGISTRYINDEX) return null;
    const abs = toAbsoluteIndex(L, funcindex);
    if (abs >= L.top) return null;
    const func_val = L.stack[abs];
    if (func_val != .function) return null;
    const cl = func_val.function orelse return null;

    const upn = n - 1;
    if (upn < 0) return null;
    switch (cl.*) {
        .c => |ccl| {
            if (upn >= ccl.upvals.len) return null;
            ccl.upvals[@intCast(upn)] = L.stack[L.top - 1];
            L.top -= 1;
            return ""; // unnamed
        },
        .lua => |lcl| {
            if (upn >= lcl.upvals.len) return null;
            const uv = lcl.upvals[@intCast(upn)] orelse return null;
            uv.v.* = L.stack[L.top - 1];
            L.top -= 1;
            if (upn < lcl.p.upvalues.len) {
                if (lcl.p.upvalues[@intCast(upn)].name) |name_ts| {
                    return name_ts.s;
                }
            }
            return "(no name)";
        },
    }
}

pub fn lua_upvalueid(L: *lua_State, fidx: i32, n: i32) ?*anyopaque {
    if (fidx <= LUA_REGISTRYINDEX) return null;
    const abs = toAbsoluteIndex(L, fidx);
    if (abs >= L.top) return null;
    const func_val = L.stack[abs];
    if (func_val != .function) return null;
    const cl = func_val.function orelse return null;

    const upn = n - 1;
    if (upn < 0) return null;
    switch (cl.*) {
        .c => |ccl| {
            if (upn >= ccl.upvals.len) return null;
            return @ptrCast(&ccl.upvals[@intCast(upn)]);
        },
        .lua => |lcl| {
            if (upn >= lcl.upvals.len) return null;
            return @ptrCast(lcl.upvals[@intCast(upn)] orelse return null);
        },
    }
}

pub fn lua_upvaluejoin(L: *lua_State, fidx1: i32, n1: i32, fidx2: i32, n2: i32) void {
    if (fidx1 <= LUA_REGISTRYINDEX or fidx2 <= LUA_REGISTRYINDEX) return;
    const abs1 = toAbsoluteIndex(L, fidx1);
    const abs2 = toAbsoluteIndex(L, fidx2);
    if (abs1 >= L.top or abs2 >= L.top) return;

    const func_val1 = L.stack[abs1];
    const func_val2 = L.stack[abs2];
    if (func_val1 != .function or func_val2 != .function) return;

    const cl1 = func_val1.function orelse return;
    const cl2 = func_val2.function orelse return;

    const upn1 = n1 - 1;
    const upn2 = n2 - 1;
    if (upn1 < 0 or upn2 < 0) return;

    switch (cl1.*) {
        .lua => |lcl1| {
            switch (cl2.*) {
                .lua => |lcl2| {
                    if (upn1 < lcl1.upvals.len and upn2 < lcl2.upvals.len) {
                        lcl1.upvals[@intCast(upn1)] = lcl2.upvals[@intCast(upn2)];
                    }
                },
                else => {},
            }
        },
        else => {},
    }
}

pub fn lua_pushboolean(L: *lua_State, b: i32) void {
    if (L.top + 1 >= L.stack.len) _ = lua_checkstack(L, 2);
    L.stack[L.top] = TValue{ .boolean = b != 0 };
    L.top += 1;
}

pub fn lua_pushlightuserdata(L: *lua_State, p: ?*anyopaque) void {
    if (L.top + 1 >= L.stack.len) _ = lua_checkstack(L, 2);
    L.stack[L.top] = TValue{ .lightud = p };
    L.top += 1;
}

pub fn lua_newthread(L: *lua_State) !*lua_State {
    const g = G(L);
    const L1 = try L.allocator.create(lua_State);
    errdefer L.allocator.destroy(L1);
    const stack = try L.allocator.alloc(TValue, LUA_MINSTACK + 1);
    for (stack) |*item| {
        item.* = .{ .nil = {} };
    }
    errdefer L.allocator.free(stack);
    L1.* = .{
        .tt = 0,
        .marked = 0,
        .gch = 0,
        .allowhook = 1,
        .status = 0,
        .top = 1,
        .l_G = g,
        .ci = null,
        .stack = stack,
        .stack_last = stack.len - 1,
        .openupval = null,
        .tbclist = .empty,
        .gclist = null,
        .twups = null,
        .errorJmp = null,
        .base_ci = .{ .func = 0, .base = 1, .top = LUA_MINSTACK, .nresults = 0, .savedpc = 0, .previous = null, .next = null, .k = null, .ctx = 0, .nyield = 0 },
        .hook = null,
        .errfunc = 0,
        .nCcalls = 0,
        .oldpc = 0,
        .nci = 0,
        .basehookcount = 0,
        .hookcount = 0,
        .hookmask = 0,
        .transferinfo = .{ .ftransfer = 0, .ntransfer = 0 },
        .allocator = L.allocator,
    };
    L1.ci = &L1.base_ci;
    L1.twups = g.thread_list;
    g.thread_list = L1;
    try registerGC(L, L1);
    try growStack(L, 1);
    L.stack[L.top] = TValue{ .thread = L1 };
    L.top += 1;
    return L1;
}

pub fn lua_closethread(L: *lua_State, from: ?*lua_State) i32 {
    const old_status = L.status;
    var err_val: ?TValue = if (old_status != 0 and old_status != LUA_YIELD and L.top > 0)
        L.stack[L.top - 1]
    else
        null;

    freeAllCallInfos(L);

    // Close all upvalues and TBC variables on the thread stack.
    // Index 1 corresponds to stack[1], since stack[0] is the thread function.
    var close_err = false;
    closeupvals(L, 1, err_val) catch {
        // A __close metamethod raised while closing; its error replaces the
        // thread's error (mirrors luaE_resetthread -> luaF_close).
        close_err = true;
        if (L.err_obj != .nil) {
            err_val = L.err_obj;
        } else if (L.top > 0) {
            err_val = L.stack[L.top - 1];
        }
    };

    if (close_err) {
        if (L.top > 1) {
            L.stack[1] = err_val.?;
            L.top = 2;
        } else {
            L.top = 1;
        }
        L.status = LUA_ERRRUN;
        // Copy the error object to the caller's stack (the reference does this
        // in lua_closethread: setobjs2s(from, from->top, L->top-1)).
        if (from) |f| {
            if (f.top < f.stack.len) {
                f.stack[f.top] = err_val.?;
                f.top += 1;
            }
        }
        return LUA_ERRRUN;
    }

    if (old_status != 0 and old_status != LUA_YIELD) {
        if (L.top > 1) {
            L.stack[1] = L.stack[L.top - 1];
            L.top = 2;
        } else {
            L.top = 1;
        }
        L.status = old_status;
        return old_status;
    } else {
        if (L.top > 1) {
            L.stack[1] = L.stack[L.top - 1];
            L.top = 2;
            L.status = LUA_ERRRUN;
            return LUA_ERRRUN;
        } else {
            L.top = 1;
            L.status = 0;
            return LUA_OK;
        }
    }
}

/// Deprecated alias for `lua_closethread(L, null)`.
pub inline fn lua_resetthread(L: *lua_State) i32 {
    return lua_closethread(L, null);
}

pub fn lua_getstack(L: *lua_State, level: i32, ar: *lua_Debug) i32 {
    if (level < 0) return 0;
    var ci: ?*CallInfo = L.ci;
    var lvl = level;
    while (lvl > 0 and ci != null) {
        if (ci.? == &L.base_ci) break;
        ci = ci.?.previous;
        lvl -= 1;
    }
    if (lvl == 0 and ci != null and ci.? != &L.base_ci) {
        ar.i_ci = ci;
        return 1;
    }
    return 0;
}

pub fn lua_sethook(L: *lua_State, func: ?lua_Hook, mask: i32, count: i32) void {
    var actual_func = func;
    var actual_mask = mask;
    if (func == null or mask == 0) {
        actual_mask = 0;
        actual_func = null;
    }
    L.hook = actual_func;
    L.basehookcount = count;
    L.hookcount = count;
    L.hookmask = @intCast(actual_mask);
    L.oldpc = -1;
}

pub fn lua_gethook(L: *lua_State) ?lua_Hook {
    return L.hook;
}

pub fn lua_gethookmask(L: *lua_State) i32 {
    return L.hookmask;
}

pub fn lua_gethookcount(L: *lua_State) i32 {
    return L.basehookcount;
}

fn testAMode(op: lvm.OpCode) bool {
    return switch (op) {
        .MOVE, .LOADI, .LOADF, .LOADK, .LOADKX, .LOADFALSE, .LFALSESKIP, .LOADTRUE, .LOADNIL, .GETUPVAL, .GETTABUP, .GETTABLE, .GETI, .GETFIELD, .NEWTABLE, .SELF, .ADDI, .ADDK, .SUBK, .MULK, .MODK, .POWK, .DIVK, .IDIVK, .BANDK, .BORK, .BXORK, .SHLI, .SHRI, .ADD, .SUB, .MUL, .MOD, .POW, .DIV, .IDIV, .BAND, .BOR, .BXOR, .SHL, .SHR, .UNM, .BNOT, .NOT, .LEN, .CONCAT, .TESTSET, .CALL, .TAILCALL, .FORLOOP, .FORPREP, .TFORLOOP, .CLOSURE, .VARARG, .GETVARG => true,
        else => false,
    };
}

fn testMMMode(op: lvm.OpCode) bool {
    return switch (op) {
        .MMBIN, .MMBINI, .MMBINK => true,
        else => false,
    };
}

fn filterpc(pc: i32, jmptarget: i32) i32 {
    return if (pc < jmptarget) -1 else pc;
}

fn findsetreg(p: *const lua_Proto, lastpc: i32, reg: i32) i32 {
    var pc: i32 = 0;
    var setreg: i32 = -1;
    var jmptarget: i32 = 0;
    var lpc = lastpc;
    if (lpc >= 0 and lpc < p.code.len) {
        if (testMMMode(lvm.GET_OPCODE(p.code[@intCast(lpc)]))) {
            lpc -= 1;
        }
    }
    while (pc < lpc) {
        const i = p.code[@intCast(pc)];
        const op = lvm.GET_OPCODE(i);
        const a = lvm.GETARG_A(i);
        var change = false;
        switch (op) {
            .LOADNIL => {
                const b = lvm.GETARG_B(i);
                change = (a <= reg and reg <= a + b);
            },
            .TFORCALL => {
                change = (reg >= a + 2);
            },
            .CALL, .TAILCALL => {
                change = (reg >= a);
            },
            .JMP => {
                const b = lvm.GETARG_sJ(i);
                const dest = pc + 1 + b;
                if (dest <= lpc and dest > jmptarget) {
                    jmptarget = dest;
                }
                change = false;
            },
            else => {
                change = (testAMode(op) and reg == a);
            },
        }
        if (change) {
            setreg = filterpc(pc, jmptarget);
        }
        pc += 1;
    }
    return setreg;
}

fn kname(p: *const lua_Proto, index: usize, name: *?[]const u8) ?[]const u8 {
    if (index < p.k.len) {
        const kvalue = p.k[index];
        if (kvalue == .string) {
            if (kvalue.string) |ts| {
                name.* = ts.s;
                return "constant";
            }
        }
    }
    name.* = "?";
    return null;
}

fn upvalname(p: *const lua_Proto, uv: usize) []const u8 {
    if (uv < p.upvalues.len) {
        if (p.upvalues[uv].name) |s| {
            return s.s;
        }
        if (uv == 0) return "_ENV";
    }
    return "?";
}

fn basicgetobjname(p: *const lua_Proto, ppc: *i32, reg: i32, name: *?[]const u8) ?[]const u8 {
    var pc = ppc.*;
    if (luaF_getlocalname(p, reg + 1, pc)) |ln| {
        name.* = ln;
        return "local";
    }
    ppc.* = findsetreg(p, pc, reg);
    pc = ppc.*;
    if (pc != -1) {
        const i = p.code[@intCast(pc)];
        const op = lvm.GET_OPCODE(i);
        switch (op) {
            .MOVE => {
                const b = lvm.GETARG_B(i);
                if (b < lvm.GETARG_A(i)) {
                    return basicgetobjname(p, ppc, b, name);
                }
            },
            .GETUPVAL => {
                name.* = upvalname(p, @intCast(lvm.GETARG_B(i)));
                return "upvalue";
            },
            .LOADK => {
                return kname(p, @intCast(lvm.GETARG_Bx(i)), name);
            },
            .LOADKX => {
                const extra = p.code[@intCast(pc + 1)];
                return kname(p, @intCast(lvm.GETARG_Ax(extra)), name);
            },
            else => {},
        }
    }
    return null;
}

fn isEnv(p: *const lua_Proto, pc: i32, i: lvm.Instruction, isup: bool) []const u8 {
    const t = lvm.GETARG_B(i);
    var name: ?[]const u8 = null;
    if (isup) {
        name = upvalname(p, @intCast(t));
    } else {
        var pc_copy = pc;
        const what = basicgetobjname(p, &pc_copy, t, &name);
        if (what == null or (!std.mem.eql(u8, what.?, "local") and !std.mem.eql(u8, what.?, "upvalue"))) {
            name = null;
        }
    }
    return if (name != null and std.mem.eql(u8, name.?, "_ENV")) "global" else "field";
}

fn rname(p: *const lua_Proto, pc: i32, c: i32, name: *?[]const u8) void {
    var pc_copy = pc;
    const what = basicgetobjname(p, &pc_copy, c, name);
    if (what == null or what.?[0] != 'c') { // "constant" starts with 'c'
        name.* = "?";
    }
}

fn getobjname(p: *const lua_Proto, lastpc: i32, reg: i32, name: *?[]const u8) ?[]const u8 {
    var lastpc_copy = lastpc;
    if (basicgetobjname(p, &lastpc_copy, reg, name)) |kind| {
        return kind;
    } else if (lastpc_copy != -1) {
        const i = p.code[@intCast(lastpc_copy)];
        const op = lvm.GET_OPCODE(i);
        switch (op) {
            .GETTABUP => {
                const k = lvm.GETARG_C(i);
                _ = kname(p, @intCast(k), name);
                return isEnv(p, lastpc_copy, i, true);
            },
            .GETTABLE, .GETVARG => {
                const k = lvm.GETARG_C(i);
                rname(p, lastpc_copy, k, name);
                return isEnv(p, lastpc_copy, i, false);
            },
            .GETI => {
                name.* = "integer index";
                return "field";
            },
            .GETFIELD => {
                const k = lvm.GETARG_C(i);
                _ = kname(p, @intCast(k), name);
                return isEnv(p, lastpc_copy, i, false);
            },
            .SELF => {
                const k = lvm.GETARG_C(i);
                _ = kname(p, @intCast(k), name);
                return "method";
            },
            else => {},
        }
    }
    return null;
}

fn funcnamefromcode(L: *lua_State, p: *const lua_Proto, pc: i32, name: *?[]const u8) ?[]const u8 {
    if (pc < 0 or pc >= p.code.len) {
        return null;
    }
    const i = p.code[@intCast(pc)];
    const op = lvm.GET_OPCODE(i);
    var tm: ?@import("ltm.zig").TMS = null;
    switch (op) {
        .CALL, .TAILCALL => {
            return getobjname(p, pc, lvm.GETARG_A(i), name);
        },
        .TFORCALL => {
            name.* = "for iterator";
            return "for iterator";
        },
        .SELF, .GETTABUP, .GETTABLE, .GETI, .GETFIELD => {
            tm = .INDEX;
        },
        .SETTABUP, .SETTABLE, .SETI, .SETFIELD => {
            tm = .NEWINDEX;
        },
        .MMBIN, .MMBINI, .MMBINK => {
            const tm_idx = lvm.GETARG_C(i);
            const TMS = @import("ltm.zig").TMS;
            if (tm_idx >= 0 and tm_idx < @typeInfo(TMS).@"enum".fields.len) {
                tm = @enumFromInt(tm_idx);
            }
        },
        .ADD, .ADDK, .ADDI => tm = .ADD,
        .SUB, .SUBK => tm = .SUB,
        .MUL, .MULK => tm = .MUL,
        .MOD, .MODK => tm = .MOD,
        .POW, .POWK => tm = .POW,
        .DIV, .DIVK => tm = .DIV,
        .IDIV, .IDIVK => tm = .IDIV,
        .BAND, .BANDK => tm = .BAND,
        .BOR, .BORK => tm = .BOR,
        .BXOR, .BXORK => tm = .BXOR,
        .SHL, .SHLI => tm = .SHL,
        .SHR, .SHRI => tm = .SHR,
        .UNM => tm = .UNM,
        .BNOT => tm = .BNOT,
        .LEN => tm = .LEN,
        .CONCAT => tm = .CONCAT,
        .EQ => tm = .EQ,
        .LT, .LTI, .GTI => tm = .LT,
        .LE, .LEI, .GEI => tm = .LE,
        .CLOSE, .RETURN => tm = .CLOSE,
        else => return null,
    }
    if (tm) |t| {
        const idx = @intFromEnum(t);
        if (L.l_G.?.tmname[idx]) |ts| {
            name.* = ts.s[2..];
            return "metamethod";
        }
    }
    return null;
}

fn funcnamefromcall(L: *lua_State, ci: *CallInfo, name: *?[]const u8) ?[]const u8 {
    if (ci.is_hooked) {
        name.* = "?";
        return "hook";
    }
    if (ci.is_fin) {
        name.* = "__gc";
        return "metamethod";
    }
    if (isLua(ci, L)) {
        const val = L.stack[ci.func];
        if (val == .function) {
            if (val.function) |cl| {
                if (cl.* == .lua) {
                    return funcnamefromcode(L, cl.lua.p, currentpc(ci), name);
                }
            }
        }
    }
    return null;
}

fn getfuncname(L: *lua_State, ci: ?*CallInfo, name: *?[]const u8) ?[]const u8 {
    // Mirror the reference: the name is looked up in the *calling* frame
    // (ci->previous); a hooked frame is reported via funcnamefromcall.
    if (ci) |c| {
        if (c.previous) |prev| {
            return funcnamefromcall(L, prev, name);
        }
    }
    return null;
}

pub fn isLua(ci: *CallInfo, L: *lua_State) bool {
    _ = L;
    return ci.is_lua;
}

pub fn currentpc(ci: *CallInfo) i32 {
    if (ci.savedpc == 0) return 0;
    return @intCast(ci.savedpc - 1);
}

pub fn luaF_getlocalname(f: *const lua_Proto, local_number: i32, pc: i32) ?[]const u8 {
    var lnum = local_number;
    for (f.locvars) |lv| {
        if (lv.startpc <= pc) {
            if (pc < lv.endpc) {
                lnum -= 1;
                if (lnum == 0) {
                    if (lv.varname) |ts| {
                        return ts.s;
                    }
                    return null;
                }
            }
        }
    }
    return null;
}

pub fn luaG_findlocal(L: *lua_State, ci: *CallInfo, n: i32, pos: *?usize) ?[]const u8 {
    const base = ci.base;
    var name: ?[]const u8 = null;
    const is_lua = isLua(ci, L);
    if (is_lua) {
        if (n < 0) {
            const nextra = ci.nextraargs;
            if (-n <= nextra) {
                const un = @as(usize, @intCast(-n));
                pos.* = ci.func - @as(usize, @intCast(nextra)) + (un - 1);
                return "(vararg)";
            }
            return null;
        } else {
            const val = L.stack[ci.func];
            if (val == .function) {
                if (val.function) |cl| {
                    if (cl.* == .lua) {
                        name = luaF_getlocalname(cl.lua.p, n, currentpc(ci));
                    }
                }
            }
        }
    }
    if (name == null) {
        // Mirror the reference: for the current frame the limit is L->top;
        // for an older frame it is the next frame's function position.
        const limit = if (ci == L.ci) L.top else (if (ci.next) |next| next.func else L.top);
        const un = @as(usize, @intCast(n));
        if (n > 0 and limit >= base + un) {
            name = if (is_lua) "(temporary)" else "(C temporary)";
        } else {
            return null;
        }
    }
    pos.* = base + @as(usize, @intCast(n - 1));
    return name;
}

pub fn lua_getlocal(L: *lua_State, ar: ?*const lua_Debug, n: i32) ?[]const u8 {
    var name: ?[]const u8 = null;
    if (ar == null) {
        if (L.top > 0) {
            const val = L.stack[L.top - 1];
            if (val == .function) {
                if (val.function) |cl| {
                    if (cl.* == .lua) {
                        name = luaF_getlocalname(cl.lua.p, n, 0);
                    }
                }
            }
        }
    } else {
        const ci = ar.?.i_ci orelse return null;
        var pos: ?usize = null;
        name = luaG_findlocal(L, ci, n, &pos);
        if (name != null and pos != null) {
            L.stack[L.top] = L.stack[pos.?];
            L.top += 1;
        }
    }
    return name;
}

pub fn lua_setlocal(L: *lua_State, ar: ?*const lua_Debug, n: i32) ?[]const u8 {
    if (L.top == 0) return null;
    const ci = ar.?.i_ci orelse return null;
    var pos: ?usize = null;
    const name = luaG_findlocal(L, ci, n, &pos);
    if (name != null and pos != null) {
        L.stack[pos.?] = L.stack[L.top - 1];
        L.top -= 1;
    }
    return name;
}

pub fn luaO_chunkid(out: *[LUA_IDSIZE]u8, source: []const u8) void {
    const bufflen = LUA_IDSIZE;
    @memset(out, 0);

    if (source.len > 0 and source[0] == '=') {
        const src = source[1..];
        const len = @min(src.len, bufflen - 1);
        @memcpy(out[0..len], src[0..len]);
    } else if (source.len > 0 and source[0] == '@') {
        const src = source[1..];
        if (src.len < bufflen) {
            @memcpy(out[0..src.len], src);
        } else {
            const RETS = "...";
            const rets_len = RETS.len;
            @memcpy(out[0..rets_len], RETS);
            const remaining = bufflen - rets_len - 1;
            const start = src.len - remaining;
            @memcpy(out[rets_len .. rets_len + remaining], src[start..]);
        }
    } else {
        const PRE = "[string \"";
        const POS = "\"]";
        const RETS = "...";

        var nl_idx: ?usize = null;
        for (source, 0..) |c, idx| {
            if (c == '\n') {
                nl_idx = idx;
                break;
            }
        }

        const reserved = PRE.len + RETS.len + POS.len + 1;
        const limit = if (bufflen > reserved) bufflen - reserved else 0;

        var write_idx: usize = 0;
        @memcpy(out[write_idx .. write_idx + PRE.len], PRE);
        write_idx += PRE.len;

        var srclen = source.len;
        if (nl_idx) |idx| {
            srclen = idx;
        }

        if (srclen <= limit and nl_idx == null) {
            @memcpy(out[write_idx .. write_idx + srclen], source[0..srclen]);
            write_idx += srclen;
        } else {
            const len = @min(srclen, limit);
            @memcpy(out[write_idx .. write_idx + len], source[0..len]);
            write_idx += len;
            @memcpy(out[write_idx .. write_idx + RETS.len], RETS);
            write_idx += RETS.len;
        }
        @memcpy(out[write_idx .. write_idx + POS.len], POS);
    }
}

fn funcinfo(ar: *lua_Debug, cl: *lua_Closure) void {
    switch (cl.*) {
        .c => {
            ar.source = "=[C]";
            ar.srclen = "=[C]".len;
            ar.linedefined = -1;
            ar.lastlinedefined = -1;
            ar.what = "C";
        },
        .lua => |lcl| {
            const p = lcl.p;
            if (p.source) |src_ts| {
                ar.source = src_ts.s;
                ar.srclen = ar.source.?.len;
            } else {
                ar.source = "=?";
                ar.srclen = "=?".len;
            }
            ar.linedefined = p.lineDefined;
            ar.lastlinedefined = p.lastLineDefined;
            ar.what = if (ar.linedefined == 0) "main" else "Lua";
        },
    }
    if (ar.source) |src| {
        luaO_chunkid(&ar.short_src, src);
    } else {
        luaO_chunkid(&ar.short_src, "=*");
    }
}

fn getcurrentline(ci: *CallInfo, L: *lua_State) i32 {
    const val = L.stack[ci.func];
    if (val == .function) {
        if (val.function) |cl| {
            if (cl.* == .lua) {
                return luaG_getfuncline(cl.lua.p, currentpc(ci));
            }
        }
    }
    return -1;
}

pub fn luaG_getfuncline(f: *const lua_Proto, pc: i32) i32 {
    if (f.lineinfo.len == 0) {
        return -1;
    } else {
        var basepc: i32 = undefined;
        var baseline = getbaseline(f, pc, &basepc);
        basepc += 1;
        while (basepc <= pc) {
            if (basepc >= 0 and @as(usize, @intCast(basepc)) < f.lineinfo.len) {
                baseline += @as(i32, f.lineinfo[@as(usize, @intCast(basepc))]);
            }
            basepc += 1;
        }
        return baseline;
    }
}

fn getbaseline(f: *const lua_Proto, pc: i32, basepc: *i32) i32 {
    const sizeabs = f.abslineinfo.len;
    if (sizeabs == 0 or pc < f.abslineinfo[0].pc) {
        basepc.* = -1;
        return f.lineDefined;
    } else {
        var i = @divTrunc(pc, 128) - 1;
        if (i < 0) {
            i = 0;
        } else if (i >= sizeabs) {
            i = @intCast(sizeabs - 1);
        }
        while (i + 1 < sizeabs and pc >= f.abslineinfo[@intCast(i + 1)].pc) {
            i += 1;
        }
        basepc.* = f.abslineinfo[@intCast(i)].pc;
        return f.abslineinfo[@intCast(i)].line;
    }
}

fn collectvalidlines(L: *lua_State, cl: *lua_Closure) !void {
    switch (cl.*) {
        .c => {
            L.stack[L.top] = .{ .nil = {} };
            L.top += 1;
        },
        .lua => |lcl| {
            const p = lcl.p;
            lua_createtable(L, 0, 0);
            if (p.lineinfo.len > 0) {
                var currentline = p.lineDefined;
                var i: usize = 0;
                if (p.isVarArg) {
                    currentline = nextline(p, currentline, 0);
                    i = 1;
                }
                while (i < p.lineinfo.len) {
                    currentline = nextline(p, currentline, @intCast(i));
                    lua_pushboolean(L, 1);
                    try lua_rawseti(L, -2, currentline);
                    i += 1;
                }
            }
        },
    }
}

fn nextline(p: *const lua_Proto, currentline: i32, pc: i32) i32 {
    if (pc < p.lineinfo.len) {
        if (p.lineinfo[@intCast(pc)] != -128) {
            return currentline + p.lineinfo[@intCast(pc)];
        } else {
            return luaG_getfuncline(p, pc);
        }
    }
    return currentline;
}

pub fn lua_getinfo(L: *lua_State, what: []const u8, ar: *lua_Debug) !i32 {
    var status: i32 = 1;
    var ci = ar.i_ci;
    var func_val: TValue = undefined;
    var what_str = what;

    if (what_str.len > 0 and what_str[0] == '>') {
        ci = null;
        if (L.top == 0) return 0;
        func_val = L.stack[L.top - 1];
        L.top -= 1;
        what_str = what_str[1..];
    } else {
        if (ci) |c| {
            func_val = L.stack[c.func];
        } else {
            return 0;
        }
    }

    if (func_val != .function) return 0;
    const cl = func_val.function orelse return 0;

    for (what_str) |c| {
        switch (c) {
            'S' => {
                funcinfo(ar, cl);
            },
            'l' => {
                ar.currentline = if (ci != null and isLua(ci.?, L)) getcurrentline(ci.?, L) else -1;
            },
            'u' => {
                switch (cl.*) {
                    .c => |ccl| {
                        ar.nups = @intCast(ccl.upvals.len);
                        ar.isvararg = true;
                        ar.nparams = 0;
                    },
                    .lua => |lcl| {
                        ar.nups = @intCast(lcl.upvals.len);
                        ar.isvararg = lcl.p.isVarArg;
                        ar.nparams = lcl.p.numParams;
                    },
                }
            },
            't' => {
                ar.istailcall = if (ci) |info_ci| info_ci.is_tailcall else false;
                ar.extraargs = if (ci) |info_ci| @intCast(@max(0, info_ci.nextraargs)) else 0;
            },
            'n' => {
                var name_opt: ?[]const u8 = null;
                ar.namewhat = getfuncname(L, ci, &name_opt);
                if (ar.namewhat) |_| {
                    ar.name = name_opt;
                } else {
                    ar.namewhat = "";
                    ar.name = null;
                }
            },
            'r' => {
                if (ci == null or !ci.?.is_hooked) {
                    ar.ftransfer = 0;
                    ar.ntransfer = 0;
                } else {
                    ar.ftransfer = L.transferinfo.ftransfer;
                    ar.ntransfer = L.transferinfo.ntransfer;
                }
            },
            'L', 'f' => {},
            else => {
                status = 0;
            },
        }
    }

    var i: usize = 0;
    while (i < what_str.len) : (i += 1) {
        const c = what_str[i];
        if (c == 'f') {
            L.stack[L.top] = func_val;
            L.top += 1;
        } else if (c == 'L') {
            try collectvalidlines(L, cl);
        }
    }

    return status;
}

pub fn lua_pushthread(L: *lua_State) i32 {
    L.stack[L.top] = TValue{ .thread = L };
    L.top += 1;
    const g = G(L);
    return if (g.mainthread == L) 1 else 0;
}

pub fn lua_pop(L: *lua_State, n: i32) void {
    if (n > 0) {
        const nn = @as(usize, @intCast(n));
        if (nn <= L.top) {
            L.top -= nn;
        }
    }
}

pub fn lua_replace(L: *lua_State, idx: i32) void {
    const abs = toAbsoluteIndex(L, idx);
    if (abs < L.top) {
        L.stack[abs] = L.stack[L.top - 1];
        L.top -= 1;
    }
}

pub fn lua_getglobal(L: *lua_State, name: []const u8) i32 {
    const g = G(L);
    // Extract the registry table from g.registry (a TValue)
    const registry: *lua_Table = switch (g.registry) {
        .table => |t_opt| t_opt orelse {
            lua_pushnil(L);
            return LUA_TNIL;
        },
        else => {
            lua_pushnil(L);
            return LUA_TNIL;
        },
    };
    // LUA_RIDX_GLOBALS == 2: globals table stored at registry[2]
    const globals_val = ltable.getInt(registry, 2);
    const globals: *lua_Table = switch (globals_val) {
        .table => |t_opt| t_opt orelse {
            lua_pushnil(L);
            return LUA_TNIL;
        },
        else => {
            lua_pushnil(L);
            return LUA_TNIL;
        },
    };
    const key = TValue{ .string = lstring.luaS_new(L, name) catch null };
    const val = ltable.get(globals, key);
    L.stack[L.top] = val;
    L.top += 1;
    return val.typ();
}

fn getTable(L: *lua_State, idx: i32) ?*lua_Table {
    const ptr = idxPtr(L, idx) orelse return null;
    if (ptr.* == .table) return ptr.table;
    return null;
}

pub fn lua_gettable(L: *lua_State, idx: i32) !i32 {
    const obj_ptr = idxPtr(L, idx) orelse {
        lua_pushnil(L);
        return LUA_TNIL;
    };
    if (obj_ptr.* == .nil) {
        lua_pushnil(L);
        return LUA_TNIL;
    }
    const key = L.stack[L.top - 1];
    const res = L.top - 1;
    try ltm.luaV_gettable(L, obj_ptr, key, res);
    L.top = res + 1;
    return L.stack[res].typ();
}

pub fn lua_getfield(L: *lua_State, idx: i32, k: []const u8) !i32 {
    const obj_ptr = idxPtr(L, idx) orelse {
        lua_pushnil(L);
        return LUA_TNIL;
    };
    if (obj_ptr.* == .nil) {
        lua_pushnil(L);
        return LUA_TNIL;
    }
    const ts = try lstring.luaS_new(L, k);
    const key = TValue{ .string = ts };
    growStack(L, 1) catch return LUA_TNIL;
    const res = L.top;
    L.stack[L.top] = .{ .nil = {} };
    L.top += 1;
    try ltm.luaV_gettable(L, obj_ptr, key, res);
    L.top = res + 1;
    return L.stack[res].typ();
}

pub fn lua_geti(L: *lua_State, idx: i32, n: lua_Integer) !i32 {
    const obj_ptr = idxPtr(L, idx) orelse {
        lua_pushnil(L);
        return LUA_TNIL;
    };
    if (obj_ptr.* == .nil) {
        lua_pushnil(L);
        return LUA_TNIL;
    }
    const key = TValue{ .integer = n };
    growStack(L, 1) catch return LUA_TNIL;
    const res = L.top;
    L.stack[L.top] = .{ .nil = {} };
    L.top += 1;
    try ltm.luaV_gettable(L, obj_ptr, key, res);
    L.top = res + 1;
    return L.stack[res].typ();
}

/// Raw (no metamethod) get — key is on top of stack.
pub fn lua_rawget(L: *lua_State, idx: i32) i32 {
    const t = getTable(L, idx) orelse {
        lua_pushnil(L);
        return LUA_TNIL;
    };
    const key = L.stack[L.top - 1];
    const val = ltable.get(t, key);
    L.top -= 1;
    L.stack[L.top] = val;
    L.top += 1;
    return val.typ();
}

/// Raw (no metamethod) integer-key get.
pub fn lua_rawgeti(L: *lua_State, idx: i32, n: lua_Integer) i32 {
    const t = getTable(L, idx) orelse {
        lua_pushnil(L);
        return LUA_TNIL;
    };
    const val = ltable.getInt(t, n);
    L.stack[L.top] = val;
    L.top += 1;
    return val.typ();
}

pub fn lua_rawgetp(L: *lua_State, idx: i32, p: ?*const anyopaque) i32 {
    const t = getTable(L, idx) orelse {
        lua_pushnil(L);
        return LUA_TNIL;
    };
    const val = ltable.get(t, TValue{ .lightud = @constCast(p) });
    L.stack[L.top] = val;
    L.top += 1;
    return val.typ();
}

pub fn lua_createtable(L: *lua_State, narr: i32, nrec: i32) void {
    const t = ltable.createTable(L.allocator, @intCast(narr), @intCast(nrec)) catch return;
    registerGC(L, t) catch return;
    L.stack[L.top] = TValue{ .table = t };
    L.top += 1;
}

pub fn lua_newuserdatauv(L: *lua_State, sz: usize, nuvalue: i32) ?*anyopaque {
    var uv: []TValue = &.{};
    if (nuvalue > 0) {
        uv = L.allocator.alloc(TValue, @intCast(nuvalue)) catch return null;
        for (uv) |*slot| slot.* = .{ .nil = {} };
    }
    const data = L.allocator.alloc(u8, sz) catch {
        if (uv.len > 0) L.allocator.free(uv);
        return null;
    };
    const u = L.allocator.create(lua_Udata) catch {
        L.allocator.free(data);
        if (uv.len > 0) L.allocator.free(uv);
        return null;
    };
    u.* = .{ .metatable = null, .data = data, .uv = uv };
    registerGC(L, u) catch {
        L.allocator.free(data);
        if (uv.len > 0) L.allocator.free(uv);
        L.allocator.destroy(u);
        return null;
    };
    L.stack[L.top] = TValue{ .userdata = u };
    L.top += 1;
    return @as(*anyopaque, @ptrCast(data.ptr));
}

/// Deprecated alias for `lua_newuserdatauv(L, s, 1)`.
pub inline fn lua_newuserdata(L: *lua_State, s: usize) ?*anyopaque {
    return lua_newuserdatauv(L, s, 1);
}

pub fn lua_getmetatable(L: *lua_State, objindex: i32) i32 {
    const val = idxPtr(L, objindex) orelse return 0;
    const mt: ?*lua_Table = switch (val.*) {
        .table => |t_opt| if (t_opt) |t| t.metatable else null,
        .userdata => |u_opt| if (u_opt) |u| u.metatable else null,
        else => {
            const t = val.typ();
            if (t >= 0 and t < 9) {
                if (G(L).mt[@intCast(t)]) |m| {
                    L.stack[L.top] = TValue{ .table = m };
                    L.top += 1;
                    return 1;
                }
            }
            return 0;
        },
    };
    if (mt) |m| {
        L.stack[L.top] = TValue{ .table = m };
        L.top += 1;
        return 1;
    }
    return 0;
}

pub fn lua_getiuservalue(L: *lua_State, idx: i32, n: i32) i32 {
    const val = idxPtr(L, idx) orelse {
        lua_pushnil(L);
        return LUA_TNONE;
    };
    const ud = switch (val.*) {
        .userdata => |u| u,
        else => null,
    };
    if (ud) |u| {
        if (n >= 1 and @as(usize, @intCast(n)) <= u.uv.len) {
            const v = u.uv[@as(usize, @intCast(n - 1))];
            L.stack[L.top] = v;
            L.top += 1;
            return v.typ();
        }
    }
    lua_pushnil(L);
    return LUA_TNONE;
}

/// Deprecated alias for `lua_getiuservalue(L, idx, 1)`.
pub inline fn lua_getuservalue(L: *lua_State, idx: i32) i32 {
    return lua_getiuservalue(L, idx, 1);
}

pub fn lua_setglobal(L: *lua_State, name: []const u8) !void {
    const g = G(L);
    // Extract the registry table from g.registry (a TValue)
    const registry: *lua_Table = switch (g.registry) {
        .table => |t_opt| t_opt orelse {
            L.top -= 1;
            return;
        },
        else => {
            L.top -= 1;
            return;
        },
    };
    const globals_val = ltable.getInt(registry, 2);
    const globals: *lua_Table = switch (globals_val) {
        .table => |t_opt| t_opt orelse {
            L.top -= 1;
            return;
        },
        else => {
            L.top -= 1;
            return;
        },
    };
    const s = lstring.luaS_new(L, name) catch null;
    if (s == null) {
        L.top -= 1;
        return error.OutOfMemory;
    }
    // BUG-100: propagate the error from the table set instead of swallowing it.
    try ltable.set(globals, TValue{ .string = s }, L.stack[L.top - 1]);
    L.top -= 1;
}

pub fn lua_settable(L: *lua_State, idx: i32) !void {
    const obj_ptr = idxPtr(L, idx) orelse {
        L.top -= 2;
        return;
    };
    if (obj_ptr.* == .nil) {
        L.top -= 2;
        return;
    }
    const key = L.stack[L.top - 2];
    const val = L.stack[L.top - 1];
    L.top -= 2;
    try ltm.luaV_settable(L, obj_ptr, key, val);
}

pub fn lua_setfield(L: *lua_State, idx: i32, k: []const u8) !void {
    const obj_ptr = idxPtr(L, idx) orelse {
        L.top -= 1;
        return;
    };
    if (obj_ptr.* == .nil) {
        L.top -= 1;
        return;
    }
    const ts = try lstring.luaS_new(L, k);
    const val = L.stack[L.top - 1];
    L.top -= 1;
    try ltm.luaV_settable(L, obj_ptr, TValue{ .string = ts }, val);
}

pub fn lua_seti(L: *lua_State, idx: i32, n: lua_Integer) !void {
    const obj_ptr = idxPtr(L, idx) orelse {
        L.top -= 1;
        return;
    };
    if (obj_ptr.* == .nil) {
        L.top -= 1;
        return;
    }
    const val = L.stack[L.top - 1];
    L.top -= 1;
    try ltm.luaV_settable(L, obj_ptr, TValue{ .integer = n }, val);
}

/// Raw (no metamethod) set — key and value are on top of stack.
pub fn lua_rawset(L: *lua_State, idx: i32) !void {
    const t = getTable(L, idx) orelse {
        L.top -= 2;
        return;
    };
    const key = L.stack[L.top - 2];
    const val = L.stack[L.top - 1];
    ltable.set(t, key, val) catch |err| {
        if (err == error.TableIndexIsNil) {
            try luaG_runerror(L, "table index is nil");
        } else if (err == error.TableIndexIsNaN) {
            try luaG_runerror(L, "table index is NaN");
        }
        return err;
    };
    L.top -= 2;
}

/// Raw (no metamethod) integer-key set.
pub fn lua_rawseti(L: *lua_State, idx: i32, n: lua_Integer) !void {
    const t = getTable(L, idx) orelse {
        L.top -= 1;
        return;
    };
    const val = L.stack[L.top - 1];
    try ltable.setInt(t, n, val);
    L.top -= 1;
}

pub fn lua_rawsetp(L: *lua_State, idx: i32, p: ?*anyopaque) !void {
    const t = getTable(L, idx) orelse {
        L.top -= 1;
        return;
    };
    const val = L.stack[L.top - 1];
    try ltable.set(t, TValue{ .lightud = @constCast(p) }, val);
    L.top -= 1;
}

pub fn lua_setmetatable(L: *lua_State, objindex: i32) i32 {
    if (L.top == 0) return 0;

    // Resolve idx before popping — negative indices shift after L.top changes.
    const abs_idx = lua_absindex(L, objindex);

    const mt_val = L.stack[L.top - 1];
    const mt: ?*lua_Table = switch (mt_val) {
        .nil => null,
        .table => |t| t,
        else => return 0,
    };
    L.top -= 1;

    const val = idxPtr(L, abs_idx) orelse return 0;
    switch (val.*) {
        .table => |t| {
            const tbl = t orelse return 0;
            tbl.metatable = mt;
            tbl.flags = 0;
        },
        .userdata => |u| {
            const ud = u orelse return 0;
            ud.metatable = mt;
        },
        else => {
            const t = val.typ();
            if (t >= 0 and t < 9) {
                G(L).mt[@intCast(t)] = mt;
            } else {
                return 0;
            }
        },
    }
    return 1;
}

pub fn lua_setiuservalue(L: *lua_State, idx: i32, n: i32) i32 {
    if (L.top == 0) return 0;
    const val = idxPtr(L, idx) orelse {
        L.top -= 1;
        return 0;
    };
    const ud = switch (val.*) {
        .userdata => |u| u,
        else => null,
    };
    var res: i32 = 0;
    if (ud) |u| {
        if (n >= 1 and @as(usize, @intCast(n)) <= u.uv.len) {
            u.uv[@as(usize, @intCast(n - 1))] = L.stack[L.top - 1];
            res = 1;
        }
    }
    L.top -= 1;
    return res;
}

/// Deprecated alias for `lua_setiuservalue(L, idx, 1)`.
pub inline fn lua_setuservalue(L: *lua_State, idx: i32) i32 {
    return lua_setiuservalue(L, idx, 1);
}

pub fn lua_callk(L: *lua_State, nargs: i32, nresults: i32, ctx: lua_KContext, k: ?lua_KFunction) !void {
    const yieldable_call = (k != null and lua_isyieldable(L) != 0);
    if (yieldable_call) {
        if (L.ci) |ci| {
            ci.k = k;
            ci.ctx = ctx;
        }
    }
    if (!yieldable_call) {
        // Non-yieldable call (no continuation): mirror luaD_callnoyield so
        // nested yields report "attempt to yield across a C-call boundary".
        // NOTE: the defer MUST be at function scope (Zig runs a block-scoped
        // defer at the end of the `if` block, reverting it too early).
        L.noyield += 1;
    }
    defer {
        if (!yieldable_call) L.noyield -= 1;
    }
    const func_idx = L.top - @as(usize, @intCast(nargs)) - 1;
    if (try precall(L, func_idx, nresults)) |new_ci| {
        L.nCcalls += 1;
        defer L.nCcalls -= 1;
        if (L.nCcalls >= llimits.LUAI_MAXCCALLS) {
            return error.StackOverflow;
        }
        try lvm.run(L, new_ci);
    }
}

pub fn lua_call(L: *lua_State, nargs: i32, nresults: i32) !void {
    try lua_callk(L, nargs, nresults, 0, null);
}

pub fn lua_pcallk(L: *lua_State, nargs: i32, nresults: i32, errfunc: i32, ctx: lua_KContext, k: ?lua_KFunction) anyerror!i32 {
    const yieldable_call = (k != null and lua_isyieldable(L) != 0);
    const old_ci = L.ci;
    if (yieldable_call) {
        if (old_ci) |ci| {
            ci.k = k;
            ci.ctx = ctx;
        }
    }
    const func_idx = L.top - @as(usize, @intCast(nargs)) - 1;
    if (yieldable_call) {
        // Mark the caller's frame as a protected call so a coroutine resume
        // that errors in this call's callee can route the error back here
        // (mirrors the reference's CIST_YPCALL).
        if (old_ci) |ci| {
            ci.ypcall = true;
            ci.pcall_func = func_idx;
        }
    }
    if (!yieldable_call) {
        // Non-yieldable protected call (no continuation): mirror the reference
        // (luaD_pcall -> f_call -> luaD_callnoyield). Kept until the call
        // finishes (including any error unwinding).
        L.noyield += 1;
    }
    defer {
        if (!yieldable_call) L.noyield -= 1;
    }

    // Resolve the error-function index to an *absolute* stack index up front.
    // At error time L.ci is no longer the caller's frame, so resolving the
    // (frame-relative) C-API index then would be wrong (mirrors the reference
    // lua_pcallk, which saves 'errfunc' as a stack offset before running).
    const errfunc_abs: ?usize = if (errfunc != 0) blk: {
        const base: usize = if (L.ci) |ci| ci.base else 0;
        const u = base + @as(usize, @intCast(errfunc - 1));
        if (u < L.top) break :blk u;
        break :blk null;
    } else null;
    const old_errfunc = L.errfunc;
    L.errfunc = if (errfunc_abs) |efi| @as(isize, @intCast(efi + 1)) else 0;
    defer L.errfunc = old_errfunc;

    var err_occurred = false;
    const new_ci = precall(L, func_idx, nresults) catch |err| b: {
        if (err == error.Yield) {
            return err;
        }
        err_occurred = true;
        if (err == error.NotAFunction) {
            const msg = "attempt to call a non-function value";
            if (lstring.luaS_new(L, msg)) |ts| {
                L.stack[L.top] = TValue{ .string = ts };
                L.top += 1;
            } else |_| {
                L.stack[L.top] = TValue{ .nil = {} };
                L.top += 1;
            }
            _ = luaG_errormsg(L) catch {};
        } else if (err == error.StackOverflow) {
            const msg = "stack overflow";
            if (lstring.luaS_new(L, msg)) |ts| {
                L.stack[L.top] = TValue{ .string = ts };
                L.top += 1;
            } else |_| {
                L.stack[L.top] = TValue{ .nil = {} };
                L.top += 1;
            }
            _ = luaG_errormsg(L) catch {};
        } else if (err == error.RuntimeError) {
            // Error object already in L.err_obj (captured by luaG_errormsg at origin)
        } else {
            if (lstring.luaS_new(L, "error")) |ts| {
                L.stack[L.top] = TValue{ .string = ts };
                L.top += 1;
            } else |_| {}
            _ = luaG_errormsg(L) catch {};
        }
        break :b @as(?*CallInfo, null);
    };

    if (!err_occurred) {
        if (new_ci) |ci| {
            L.nCcalls += 1;
            defer L.nCcalls -= 1;
            if (L.nCcalls >= llimits.LUAI_MAXCCALLS) {
                err_occurred = true;
                const msg = "stack overflow";
                if (lstring.luaS_new(L, msg)) |ts| {
                    L.stack[L.top] = TValue{ .string = ts };
                    L.top += 1;
                } else |_| {
                    L.stack[L.top] = TValue{ .nil = {} };
                    L.top += 1;
                }
            } else {
                lvm.run(L, ci) catch |err| {
                    if (err == error.Yield) {
                        return err;
                    }
                    err_occurred = true;
                    if (err == error.StackOverflow) {
                        const msg = "stack overflow";
                        if (lstring.luaS_new(L, msg)) |ts| {
                            L.stack[L.top] = TValue{ .string = ts };
                            L.top += 1;
                        } else |_| {
                            L.stack[L.top] = TValue{ .nil = {} };
                            L.top += 1;
                        }
                        _ = luaG_errormsg(L) catch {};
                    }
                };
            }
        }
    }

    if (err_occurred) {
        // Save the error object (captured in L.err_obj during luaG_errormsg).
        var err_obj = L.err_obj;

        // Clean up stale CallInfo frames (overflow frames from Lua recursion).
        var curr = L.ci;
        while (curr) |c| {
            if (c == old_ci) break;
            const prev = c.previous;
            if (c != &L.base_ci) {
                L.allocator.destroy(c);
            }
            curr = prev;
        }
        L.ci = old_ci;
        if (old_ci) |prev| {
            prev.next = null;
        }

        // Restore L.top to its pre-call level (func_idx + nargs + 1), making
        // room for the error handler to execute (the handler's precall checks
        // LUAI_MAXSTACK, and an inflated L.top would trigger StackError).
        const base_top = func_idx + @as(usize, @intCast(nargs)) + 1;

        // Push the error at a position past all TBC <close> variables,
        // so we don't overwrite them before closeupvals can process them.
        var err_push_pos = base_top;
        for (L.tbclist.items) |item| {
            if (item >= err_push_pos) err_push_pos = item + 1;
        }
        L.top = err_push_pos;
        L.stack[L.top] = err_obj;
        L.top += 1;

        closeupvals(L, func_idx, err_obj) catch |ce| {
            if (ce == error.Yield) {
                // A __close metamethod yielded during the error unwind: save
                // the recovery state and let the coroutine yield;
                // completePcallRecovery finishes the pcall on resume.
                if (old_ci) |oci| {
                    oci.recovering = true;
                    oci.recover_err = err_obj;
                }
                return error.Yield;
            }
            // A __close metamethod raised while unwinding; its error object
            // (left on the stack top by closeupvals) becomes the new error.
            if (L.err_obj != .nil) {
                err_obj = L.err_obj;
            } else if (L.top > 0) {
                err_obj = L.stack[L.top - 1];
            }
        };

        // Place the error object where the first result would go, so the
        // surrounding C pcall wrapper can prepend the status boolean.
        L.stack[func_idx] = err_obj;
        L.top = func_idx + 1;
        // After a stack overflow the stack was overgrown (ERRORSTACKSIZE);
        // shrink it back so subsequent calls don't inherit the overflow
        // headroom as their working limit (mirrors luaD_shrinkstack).
        shrinkStack(L);
        if (old_ci) |ci| ci.ypcall = false;
        return LUA_ERRRUN;
    }

    L.err_name = null;
    L.err_namewhat = null;
    if (old_ci) |ci| ci.ypcall = false;
    return LUA_OK;
}

pub inline fn lua_pcall(L: *lua_State, nargs: i32, nresults: i32, errfunc: i32) i32 {
    return lua_pcallk(L, nargs, nresults, errfunc, 0, null) catch |e| {
        return if (e == error.Yield) LUA_YIELD else LUA_ERRRUN;
    };
}

/// Push a runtime-error message onto the stack and return `error.RuntimeError`
/// so the surrounding protected call reports it. Mirrors PUC-Rio's
/// `luaG_runerror`. Returns `!lua.TValue` so it can be used as a function's
/// error return regardless of the function's success payload type.
pub fn luaG_runerror(L: *lua_State, msg: []const u8) !void {
    var full_msg: [512]u8 = undefined;
    var final_msg = msg;
    if (L.ci) |ci| {
        if (isLua(ci, L)) {
            const val = L.stack[ci.func];
            if (val == .function and val.function != null and val.function.?.* == .lua) {
                const proto = val.function.?.lua.p;
                if (proto.source) |src| {
                    var chunkid_buf: [LUA_IDSIZE]u8 = undefined;
                    luaO_chunkid(&chunkid_buf, src.s);
                    const chunkid = std.mem.sliceTo(&chunkid_buf, 0);
                    const line = luaG_getfuncline(proto, currentpc(ci));
                    if (std.fmt.bufPrint(&full_msg, "{s}:{d}: {s}", .{ chunkid, line, msg })) |formatted| {
                        final_msg = formatted;
                    } else |_| {}
                } else {
                    if (std.fmt.bufPrint(&full_msg, "?:?: {s}", .{msg})) |formatted| {
                        final_msg = formatted;
                    } else |_| {}
                }
            }
        }
    }
    const ts = lstring.luaS_new(L, final_msg) catch null;
    if (ts) |t| {
        L.stack[L.top] = TValue{ .string = t };
        L.top += 1;
    } else {
        L.stack[L.top] = TValue{ .nil = {} };
        L.top += 1;
    }
    return lua_error(L);
}

/// Value-equality test used by `varinfo` to locate the operand register.
fn tvEqual(a: TValue, b: TValue) bool {
    if (a == .nil and b == .nil) return true;
    if (a.isNumberValue() and b.isNumberValue()) {
        return a.toFloat() == b.toFloat();
    }
    if (a == .boolean and b == .boolean) return a.boolean == b.boolean;
    if (a == .integer and b == .integer) return a.integer == b.integer;
    if (a == .string and b == .string) return a.string == b.string;
    return false;
}

/// Mirror PUC-Rio `varinfo`: locate `o` in the current Lua frame and build a
/// description such as ` (field 'huge')` or ` (global 'x')`, written into `buf`.
/// Returns the slice of `buf` used, or `""` if unknown.
fn luaG_varinfo(L: *lua_State, o_ptr: *const TValue, buf: []u8) []u8 {
    var ci = L.ci orelse return "";
    if (!isLua(ci, L)) {
        ci = ci.previous orelse return "";
        if (!isLua(ci, L)) return "";
    }
    if (ci.func >= L.stack.len) return "";
    const val = L.stack[ci.func];
    if (val != .function or val.function == null) return "";
    const cl = val.function.?;
    if (cl.* != .lua) return "";
    const lcl = cl.lua;

    // 1. Check exact upvalue pointer match first
    for (lcl.upvals, 0..) |opt_uv, uv_idx| {
        if (opt_uv) |uv| {
            if (uv.v == o_ptr) {
                const uname = upvalname(lcl.p, uv_idx);
                return std.fmt.bufPrint(buf, " (upvalue '{s}')", .{uname}) catch "";
            }
        }
    }

    const p = lcl.p;
    const base = ci.base;
    var reg: i32 = -1;

    // 2. Check exact stack pointer match
    const o_addr = @intFromPtr(o_ptr);
    const stack_addr = @intFromPtr(L.stack.ptr);
    const stack_end_addr = stack_addr + L.stack.len * @sizeOf(TValue);
    if (o_addr >= stack_addr and o_addr < stack_end_addr) {
        const idx = (o_addr - stack_addr) / @sizeOf(TValue);
        if (idx >= base and idx < ci.top) {
            reg = @intCast(idx - base);
        }
    }

    // 3. Fall back to upvalue value match
    if (reg < 0) {
        for (lcl.upvals, 0..) |opt_uv, uv_idx| {
            if (opt_uv) |uv| {
                if (tvEqual(uv.v.*, o_ptr.*)) {
                    const uname = upvalname(lcl.p, uv_idx);
                    return std.fmt.bufPrint(buf, " (upvalue '{s}')", .{uname}) catch "";
                }
            }
        }
    }

    // 4. Fall back to stack register value match
    if (reg < 0) {
        var idx: usize = base;
        const limit = @min(ci.top, L.stack.len);
        while (idx < limit) : (idx += 1) {
            if (tvEqual(L.stack[idx], o_ptr.*)) {
                reg = @intCast(idx - base);
                break;
            }
        }
    }

    if (reg < 0) return "";
    var name: ?[]const u8 = null;
    const kind = getobjname(p, currentpc(ci), reg, &name) orelse return "";
    if (name == null) return "";
    return std.fmt.bufPrint(buf, " ({s} '{s}')", .{ kind, name.? }) catch "";
}

/// Error when a value cannot be converted to an integer (bitwise/shift operand
/// or `floor`/integer coercion). Mirrors PUC-Rio `luaG_tointerror`: the message
/// is `"number%s has no integer representation"`, where `%s` is the operand's
/// `varinfo` (e.g. ` (field 'huge')`).
pub fn luaG_errnnil(L: *lua_State, proto: *const lua_Proto, k: i32) !void {
    var globalname: []const u8 = "?";
    if (k > 0 and @as(usize, @intCast(k - 1)) < proto.k.len) {
        const kv = proto.k[@as(usize, @intCast(k - 1))];
        if (kv == .string) {
            if (kv.string) |ts| globalname = ts.s;
        }
    }
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "global '{s}' already defined", .{globalname}) catch "global already defined";
    return luaG_runerror(L, msg);
}

pub fn luaG_forerror(L: *lua_State, o: TValue, what: []const u8) !void {
    const t = ltm.luaT_objtypename(L, o);
    var msg: [256]u8 = undefined;
    const mslice = std.fmt.bufPrint(&msg, "bad 'for' {s} (number expected, got {s})", .{ what, t }) catch "bad 'for' value";
    return luaG_runerror(L, mslice);
}

pub fn luaG_tointerror(L: *lua_State, o: TValue) !void {
    var buf: [256]u8 = undefined;
    const info = luaG_varinfo(L, &o, &buf);
    var msg: [320]u8 = undefined;
    const mslice = std.fmt.bufPrint(&msg, "number{s} has no integer representation", .{info}) catch "number has no integer representation";
    return luaG_runerror(L, mslice);
}

pub fn luaG_typeerror(L: *lua_State, o: TValue, op: []const u8) !void {
    return luaG_typeerrorPtr(L, &o, op);
}

pub fn luaG_typeerrorPtr(L: *lua_State, o: *const TValue, op: []const u8) !void {
    var buf: [256]u8 = undefined;
    const info = luaG_varinfo(L, o, &buf);
    const t = ltm.luaT_objtypename(L, o.*);
    var msg: [320]u8 = undefined;
    const mslice = std.fmt.bufPrint(&msg, "attempt to {s} a {s} value{s}", .{ op, t, info }) catch "attempt to perform operation on value";
    return luaG_runerror(L, mslice);
}

pub fn luaG_callerror(L: *lua_State, o: TValue) !void {
    var fname: ?[]const u8 = null;
    var kind: ?[]const u8 = null;
    if (L.ci) |ci| {
        kind = funcnamefromcall(L, ci, &fname);
    }
    const t = ltm.luaT_objtypename(L, o);
    var msg: [320]u8 = undefined;
    if (kind) |k| {
        if (fname) |fnm| {
            const mslice = std.fmt.bufPrint(&msg, "attempt to call a {s} value ({s} '{s}')", .{ t, k, fnm }) catch "attempt to call a non-function value";
            return luaG_runerror(L, mslice);
        }
    }
    return luaG_typeerror(L, o, "call");
}

pub fn luaG_opinterror(L: *lua_State, p1: *const TValue, p2: *const TValue, msg: []const u8) !void {
    var err_obj = p1;
    if (p1.isNumberValue()) {
        err_obj = p2;
    }
    return luaG_typeerrorPtr(L, err_obj, msg);
}

pub fn luaG_concaterror(L: *lua_State, p1: *const TValue, p2: *const TValue) !void {
    // Port of the reference: if the first operand is (or can be converted to)
    // a string, blame the second operand. Without the string check, an already
    // coerced operand (e.g. `1..{}`) would wrongly report "a string value".
    var err_obj = p1;
    if (p1.isNumberValue() or p1.isString()) {
        err_obj = p2;
    }
    return luaG_typeerrorPtr(L, err_obj, "concatenate");
}

pub fn luaG_ordererror(L: *lua_State, p1: TValue, p2: TValue) !void {
    const t1 = ltm.luaT_objtypename(L, p1);
    const t2 = ltm.luaT_objtypename(L, p2);
    var msg: [256]u8 = undefined;
    const mslice = if (std.mem.eql(u8, t1, t2))
        std.fmt.bufPrint(&msg, "attempt to compare two {s} values", .{t1}) catch "attempt to compare values"
    else
        std.fmt.bufPrint(&msg, "attempt to compare {s} with {s}", .{ t1, t2 }) catch "attempt to compare values";
    return luaG_runerror(L, mslice);
}

pub fn lua_load(L: *lua_State, reader: lua_Reader, dt: ?*anyopaque, chunkname: []const u8, mode: []const u8) i32 {
    const initial_top = L.top;
    var size: usize = 0;
    const first_slice = (reader(L, dt, &size) catch |e| {
        if (e == error.SyntaxError or e == error.RuntimeError) {
            if (L.top > initial_top) {
                const err_val = L.stack[L.top - 1];
                L.stack[initial_top] = err_val;
                L.top = initial_top + 1;
            }
            return LUA_ERRSYNTAX;
        }
        return LUA_ERRSYNTAX;
    });
    if (first_slice == null or size == 0 or first_slice.?.len == 0) {
        if (std.mem.indexOfScalar(u8, mode, 't') == null) {
            var msg: [128]u8 = undefined;
            const m = std.fmt.bufPrint(&msg, "attempt to load a text chunk (mode is '{s}')", .{mode}) catch "attempt to load a text chunk";
            _ = lua_pushstring(L, m);
            if (L.top > initial_top) {
                const err_val = L.stack[L.top - 1];
                L.stack[initial_top] = err_val;
                L.top = initial_top + 1;
            }
            return LUA_ERRSYNTAX;
        }
        const proto = lparser.luaD_protectedparser(L, reader, dt, chunkname, "", true) catch |e| {
            if (e == error.SyntaxError or e == error.RuntimeError) {
                if (L.top > initial_top) {
                    const err_val = L.stack[L.top - 1];
                    L.stack[initial_top] = err_val;
                    L.top = initial_top + 1;
                }
                return LUA_ERRSYNTAX;
            }
            return LUA_ERRMEM;
        };
        return finishLoad(L, proto);
    }
    const c = first_slice.?[0];
    if (c == '\x1b') {
        if (std.mem.indexOfScalar(u8, mode, 'b') == null and std.mem.indexOfScalar(u8, mode, 'B') == null) {
            var msg: [128]u8 = undefined;
            const m = std.fmt.bufPrint(&msg, "attempt to load a binary chunk (mode is '{s}')", .{mode}) catch "attempt to load a binary chunk";
            _ = lua_pushstring(L, m);
            if (L.top > initial_top) {
                const err_val = L.stack[L.top - 1];
                L.stack[initial_top] = err_val;
                L.top = initial_top + 1;
            }
            return LUA_ERRSYNTAX;
        }
        const proto = lundump.loadBinaryChunk(L, reader, dt, first_slice.?, chunkname) catch |e| {
            if (e == error.OutOfMemory) return LUA_ERRMEM;
            var msg_buf: [256]u8 = undefined;
            const msg = switch (e) {
                error.TruncatedChunk => std.fmt.bufPrint(&msg_buf, "{s}: truncated chunk", .{chunkname}) catch "truncated chunk",
                error.IntegerOverflow => std.fmt.bufPrint(&msg_buf, "{s}: integer overflow", .{chunkname}) catch "integer overflow",
                error.VersionMismatch => std.fmt.bufPrint(&msg_buf, "{s}: bad binary format (version mismatch)", .{chunkname}) catch "bad binary format (version mismatch)",
                error.FormatMismatch => std.fmt.bufPrint(&msg_buf, "{s}: bad binary format (format mismatch)", .{chunkname}) catch "bad binary format (format mismatch)",
                error.BadHeader, error.CorruptedChunk => std.fmt.bufPrint(&msg_buf, "{s}: bad binary format (corrupted chunk)", .{chunkname}) catch "bad binary format (corrupted chunk)",
                error.TypeSizeMismatch, error.TypeFormatMismatch => std.fmt.bufPrint(&msg_buf, "{s}: bad binary format (size mismatch)", .{chunkname}) catch "bad binary format (size mismatch)",
                else => std.fmt.bufPrint(&msg_buf, "{s}: corrupted chunk", .{chunkname}) catch "corrupted chunk",
            };
            _ = lua_pushstring(L, msg);
            if (L.top > initial_top) {
                const err_val = L.stack[L.top - 1];
                L.stack[initial_top] = err_val;
                L.top = initial_top + 1;
            }
            return LUA_ERRSYNTAX;
        };
        _ = lua_checkstack(L, 1);
        L.stack[L.top] = .{ .proto = proto };
        L.top += 1;
        const status = finishLoad(L, proto);
        if (status == LUA_OK) {
            L.stack[L.top - 2] = L.stack[L.top - 1];
            L.top -= 1;
            return LUA_OK;
        } else {
            L.top = initial_top + 1;
            return status;
        }
    } else {
        if (std.mem.indexOfScalar(u8, mode, 't') == null) {
            var msg: [128]u8 = undefined;
            const m = std.fmt.bufPrint(&msg, "attempt to load a text chunk (mode is '{s}')", .{mode}) catch "attempt to load a text chunk";
            _ = lua_pushstring(L, m);
            if (L.top > initial_top) {
                const err_val = L.stack[L.top - 1];
                L.stack[initial_top] = err_val;
                L.top = initial_top + 1;
            }
            return LUA_ERRSYNTAX;
        }
        const proto = lparser.luaD_protectedparser(L, reader, dt, chunkname, first_slice.?, false) catch |e| {
            if (e == error.SyntaxError or e == error.RuntimeError) {
                if (L.top > initial_top) {
                    const err_val = L.stack[L.top - 1];
                    L.stack[initial_top] = err_val;
                    L.top = initial_top + 1;
                }
                return LUA_ERRSYNTAX;
            }
            return LUA_ERRMEM;
        };
        _ = lua_checkstack(L, 1);
        L.stack[L.top] = .{ .proto = proto };
        L.top += 1;
        const status = finishLoad(L, proto);
        if (status == LUA_OK) {
            L.stack[L.top - 2] = L.stack[L.top - 1];
            L.top -= 1;
            return LUA_OK;
        } else {
            L.top = initial_top + 1;
            return status;
        }
    }
}

// Instantiate a top-level closure for `proto` (wiring its _ENV upvalue to the
// global table) and push it onto the stack, ready to be called. Used by both
// the binary-chunk loader and the source-text parser paths.
pub fn finishLoad(L: *lua_State, proto: *lua_Proto) i32 {
    const lc = L.allocator.create(lua_LClosure) catch {
        return LUA_ERRMEM;
    };
    const upvals = L.allocator.alloc(?*UpVal, proto.upvalues.len) catch {
        L.allocator.destroy(lc);
        return LUA_ERRMEM;
    };
    @memset(upvals, null);
    lc.* = .{
        .p = proto,
        .upvals = upvals,
    };

    // Initialize upvalues for top-level closure (matching PUC-Rio ldo.c)
    if (proto.upvalues.len > 0) {
        const registry = G(L).registry.table orelse return LUA_ERRMEM;
        const globals = ltable.getInt(registry, 2); // RIDX_GLOBALS is 2
        const is_env = if (proto.upvalues[0].name) |name| std.mem.eql(u8, name.s, "_ENV") else true;
        for (0..proto.upvalues.len) |i| {
            const uv = L.allocator.create(UpVal) catch {
                for (0..i) |j| {
                    if (upvals[j]) |u| L.allocator.destroy(u);
                }
                L.allocator.free(upvals);
                L.allocator.destroy(lc);
                return LUA_ERRMEM;
            };
            const val: TValue = if (i == 0 and is_env) globals else .{ .nil = {} };
            uv.* = .{
                .value = val,
                .v = &uv.value,
                .next = null,
                .refcount = 1,
            };
            registerGC(L, uv) catch {
                L.allocator.destroy(uv);
                for (0..i) |j| {
                    if (upvals[j]) |u| L.allocator.destroy(u);
                }
                L.allocator.free(upvals);
                L.allocator.destroy(lc);
                return LUA_ERRMEM;
            };
            upvals[i] = uv;
        }
    }

    const cl = L.allocator.create(lua_Closure) catch {
        if (upvals.len > 0 and upvals[0] != null) L.allocator.destroy(upvals[0].?);
        L.allocator.free(upvals);
        L.allocator.destroy(lc);
        return LUA_ERRMEM;
    };
    cl.* = .{ .lua = lc };
    registerGC(L, cl) catch {
        if (upvals.len > 0 and upvals[0] != null) L.allocator.destroy(upvals[0].?);
        L.allocator.free(upvals);
        L.allocator.destroy(lc);
        return LUA_ERRMEM;
    };
    L.stack[L.top] = TValue{ .function = cl };
    L.top += 1;
    return LUA_OK;
}

pub fn lua_dump(L: *lua_State, writer: lua_Writer, data: ?*anyopaque, strip: i32) i32 {
    return ldump.lua_dump(L, writer, data, strip);
}

pub fn lua_yieldk(L: *lua_State, nresults: i32, ctx: lua_KContext, k: ?lua_KFunction) anyerror!i32 {
    const ci = L.ci orelse return error.RuntimeError;
    if (lua_isyieldable(L) == 0) {
        // Mirror the reference: report a different message depending on
        // whether this is the main thread or a coroutine stuck in a
        // non-yieldable context.
        if (G(L).mainthread != L) {
            try luaG_runerror(L, "attempt to yield across a C-call boundary");
        } else {
            try luaG_runerror(L, "attempt to yield from outside a coroutine");
        }
    }
    L.status = LUA_YIELD;
    ci.nyield = nresults;
    ci.k = k;
    ci.ctx = ctx;
    return error.Yield;
}

pub fn lua_yield(L: *lua_State, nresults: i32) anyerror!i32 {
    return lua_yieldk(L, nresults, 0, null);
}

fn resume_error(_: *lua_State, _: []const u8, _: i32) i32 {
    return LUA_ERRRUN;
}

/// Complete an interrupted protected-call error recovery: close any remaining
/// to-be-closed variables with the saved error and finish the pcall via its
/// continuation. The caller (unroll) sets L.ci to the pcall's caller.
fn completePcallRecovery(L: *lua_State, ci: *CallInfo) !void {
    var err_obj = ci.recover_err;
    const pcall_func = ci.pcall_func;
    // The error must be at L.top-1 for closeupvals to pass it to each
    // remaining __close (it reads current_err from there).
    if (L.top < L.stack.len) {
        L.stack[L.top] = err_obj;
        L.top += 1;
    }
    // Close any remaining to-be-closed variables (a resumed __close may
    // itself raise, replacing the error, or yield, interrupting the recovery).
    closeupvals(L, pcall_func, err_obj) catch |ce| {
        if (ce == error.Yield) {
            ci.recovering = true;
            ci.recover_err = err_obj;
            return error.Yield;
        }
        if (L.err_obj != .nil) {
            err_obj = L.err_obj;
        } else if (L.top > 0) {
            err_obj = L.stack[L.top - 1];
        }
    };
    ci.ypcall = false;
    ci.recovering = false;
    if (pcall_func < L.stack.len) {
        L.stack[pcall_func] = err_obj;
    }
    L.top = pcall_func + 1;
    if (ci.k) |kf| {
        const nres = try kf(L, LUA_ERRRUN, ci.ctx);
        const u_nres = @as(usize, @intCast(nres));
        try poscall(L, ci, L.top - u_nres, u_nres);
    }
    const prev = ci.previous;
    L.ci = prev;
    if (prev) |p| {
        p.next = null;
    }
    freeCallInfo(L, ci);
}

/// Route an error raised by a resumed coroutine frame back to the nearest
/// protected call (the CIST_YPCALL equivalent): unwind the frames above it,
/// close its remaining to-be-closed variables with the error (a __close may
/// raise or yield), and complete the pcall via its continuation.
/// Returns true if the error was handled (the coroutine may continue), false
/// if there is no recoverable protected call, or error.Yield if a __close
/// yielded during the recovery (the recovery resumes later).
fn precover(L: *lua_State) !bool {
    var opt: ?*CallInfo = L.ci;
    var target: ?*CallInfo = null;
    while (opt) |c| : (opt = c.previous) {
        if (c.ypcall) {
            target = c;
            break;
        }
    }
    const target_ci = target orelse return false;

    // Unwind the frames above the protected call.
    var curr = L.ci;
    while (curr) |c| {
        if (c == target_ci) break;
        const prev = c.previous;
        if (c != &L.base_ci) {
            L.allocator.destroy(c);
        }
        curr = prev;
    }
    L.ci = target_ci;
    if (target_ci.previous) |prev| {
        prev.next = null;
    }

    // The error object from the erroring frame is on the stack top. Move it
    // past any remaining TBC variables, then close them.
    const pcall_func = target_ci.pcall_func;
    var err_obj = if (L.top > 0) L.stack[L.top - 1] else TValue{ .nil = {} };
    closeupvals(L, pcall_func, err_obj) catch |ce| {
        if (ce == error.Yield) {
            // A __close metamethod yielded while closing with the error: save
            // the pending error and let the coroutine yield; on resume the
            // recovery completes (completePcallRecovery).
            target_ci.recovering = true;
            target_ci.recover_err = err_obj;
            return error.Yield;
        }
        if (L.err_obj != .nil) {
            err_obj = L.err_obj;
        } else if (L.top > 0) {
            err_obj = L.stack[L.top - 1];
        }
    };
    target_ci.recover_err = err_obj;
    try completePcallRecovery(L, target_ci);
    return true;
}

fn unroll(L: *lua_State) !void {
    while (L.ci) |ci| {
        if (ci == &L.base_ci) break;
        const val = L.stack[ci.func];
        if (val == .function and val.function.?.* == .lua) {
            // The frame was interrupted by a yield: complete the interrupted
            // instruction before resuming (mirrors luaV_finishOp in unroll).
            lvm.finishOp(L, ci);
            lvm.run(L, ci) catch |e| {
                if (e == error.Yield) return e;
                const handled = precover(L) catch |pe| {
                    if (pe == error.Yield) return pe;
                    return e;
                };
                if (!handled) return e;
                // Handled: the protected call completed; continue the loop
                // with the (unwound) call chain.
            };
        } else if (val == .function and val.function.?.* == .c) {
            if (ci.k) |kf| {
                if (ci.recovering) {
                    // Finish an error recovery that was interrupted by a
                    // yielding __close metamethod.
                    try completePcallRecovery(L, ci);
                } else {
                    const prev = ci.previous;
                    const nres = try kf(L, LUA_YIELD, ci.ctx);
                    const u_nres = @as(usize, @intCast(nres));
                    try poscall(L, ci, L.top - u_nres, u_nres);
                    L.ci = prev;
                    freeCallInfo(L, ci);
                }
            } else {
                const prev = ci.previous;
                try poscall(L, ci, L.top, 0);
                L.ci = prev;
                freeCallInfo(L, ci);
            }
        } else {
            return error.RuntimeError;
        }
    }
}

fn do_resume(L: *lua_State, narg: i32) !void {
    const n = @as(usize, @intCast(narg));
    const firstArg = L.top - n;

    if (L.status == LUA_OK) {
        if (try precall(L, firstArg - 1, LUA_MULTRET)) |ci| {
            try lvm.run(L, ci);
        }
    } else {
        L.status = LUA_OK;
        if (L.ci) |ci| {
            if (ci.k) |kf| {
                const prev = ci.previous;
                const nres = try kf(L, LUA_YIELD, ci.ctx);
                const u_nres = @as(usize, @intCast(nres));
                try poscall(L, ci, L.top - u_nres, u_nres);
                L.ci = prev;
                freeCallInfo(L, ci);
            } else {
                const val = L.stack[ci.func];
                if (val == .function and val.function.?.* == .lua) {
                    L.ci = ci;
                    lvm.finishOp(L, ci);
                    lvm.run(L, ci) catch |e| {
                        if (e == error.Yield) return e;
                        const handled = precover(L) catch |pe| {
                            if (pe == error.Yield) return pe;
                            return e;
                        };
                        if (!handled) return e;
                    };
                } else {
                    const prev = ci.previous;
                    try poscall(L, ci, firstArg, n);
                    L.ci = prev;
                    freeCallInfo(L, ci);
                }
            }
        } else {
            return error.RuntimeError;
        }
        try unroll(L);
    }
}

pub fn lua_resume(L: *lua_State, from: ?*lua_State, narg: i32, nresults: ?*i32) i32 {
    if (L.status == LUA_OK) {
        if (L.ci != &L.base_ci) return resume_error(L, "cannot resume non-suspended coroutine", narg);
    } else if (L.status != LUA_YIELD) {
        return resume_error(L, "cannot resume dead coroutine", narg);
    }
    if (L.top == 0) return resume_error(L, "cannot resume dead coroutine", narg);

    L.nCcalls = if (from) |f| f.nCcalls else 0;
    L.nCcalls += 1;

    do_resume(L, narg) catch |e| {
        if (e == error.Yield) {} else {
            const status = switch (e) {
                error.OutOfMemory => b: {
                    if (lstring.luaS_new(L, "not enough memory")) |ts| {
                        L.stack[L.top] = TValue{ .string = ts };
                        L.top += 1;
                    } else |_| {
                        L.stack[L.top] = TValue{ .nil = {} };
                        L.top += 1;
                    }
                    break :b LUA_ERRMEM;
                },
                error.StackOverflow, error.StackError => b: {
                    if (lstring.luaS_new(L, "stack overflow")) |ts| {
                        L.stack[L.top] = TValue{ .string = ts };
                        L.top += 1;
                    } else |_| {
                        L.stack[L.top] = TValue{ .nil = {} };
                        L.top += 1;
                    }
                    break :b LUA_ERRRUN;
                },
                else => LUA_ERRRUN,
            };
            L.status = @intCast(status);
        }
    };

    if (nresults) |nr| {
        if (L.status == LUA_YIELD) {
            nr.* = if (L.ci) |ci| ci.nyield else 0;
        } else if (L.status == LUA_OK) {
            if (L.ci) |ci| {
                nr.* = @as(i32, @intCast(L.top)) - @as(i32, @intCast(ci.func + 1));
            } else {
                nr.* = 0;
            }
        } else {
            nr.* = 0;
        }
    }

    if (L.status == LUA_YIELD) return LUA_YIELD;
    if (L.status == LUA_OK) {
        // Coroutine completed normally: its call frames were already popped
        // back to base_ci, so only recycled CallInfos remain. Discard them
        // (they would otherwise linger in the freelist until the thread is
        // explicitly closed, which the caller may never do).
        freeAllCallInfos(L);
    }
    // Otherwise the coroutine died with an error: keep its CallInfo chain so
    // that debug.traceback(co) can still report the frames where it failed
    // (mirrors the reference, which frees them at lua_closethread / lua_close).
    return L.status;
}

pub fn lua_status(L: *lua_State) i32 {
    return L.status;
}

pub fn lua_isyieldable(L: *lua_State) i32 {
    return if (L.noyield == 0) 1 else 0;
}

pub fn lua_setwarnf(L: *lua_State, f: lua_WarnFunction, ud: ?*anyopaque) void {
    _ = L;
    _ = f;
    _ = ud;
}

pub fn lua_warning(L: *lua_State, msg: []const u8, tocont: i32) void {
    _ = L;
    _ = msg;
    _ = tocont;
}

fn getGCObject(g: *global_State, ptr: anytype) ?*VMGCObject {
    if (@typeInfo(@TypeOf(ptr)) != .pointer) return null;
    if (@intFromPtr(ptr) == 0) return null;
    const T = @TypeOf(ptr);
    if (T == *lua_Table) {
        if (ptr.gc) |gc| return gc;
        var curr = g.allgc;
        while (curr) |obj| : (curr = obj.next) {
            if (obj.val == .table and obj.val.table == ptr) {
                ptr.gc = obj;
                return obj;
            }
        }
        return null;
    }
    if (T == *lua_Closure) {
        const gc_opt = switch (ptr.*) {
            .c => |cc| cc.gc,
            .lua => |lc| lc.gc,
        };
        if (gc_opt) |gc| return gc;
        var curr = g.allgc;
        while (curr) |obj| : (curr = obj.next) {
            if (obj.val == .closure and obj.val.closure == ptr) {
                switch (ptr.*) {
                    .c => |cc| cc.gc = obj,
                    .lua => |lc| lc.gc = obj,
                }
                return obj;
            }
        }
        return null;
    }
    if (T == *lua_Udata) {
        if (ptr.gc) |gc| return gc;
        var curr = g.allgc;
        while (curr) |obj| : (curr = obj.next) {
            if (obj.val == .userdata and obj.val.userdata == ptr) {
                ptr.gc = obj;
                return obj;
            }
        }
        return null;
    }
    if (T == *lua_Proto) {
        if (ptr.gc) |gc| return gc;
        var curr = g.allgc;
        while (curr) |obj| : (curr = obj.next) {
            if (obj.val == .proto and obj.val.proto == ptr) {
                ptr.gc = obj;
                return obj;
            }
        }
        return null;
    }
    if (T == *lua_TString) {
        // Short strings are interned in `strt` and never on allgc, so they
        // have no VMGCObject/back-pointer; long/external strings are always
        // GC-registered (registerGC sets `ts.gc`). A null `gc` therefore
        // means a short string: do NOT linear-scan allgc (that made marking
        // O(n^2) on workloads with many distinct interned strings).
        return ptr.gc;
    }
    if (T == *UpVal) {
        if (ptr.gc) |gc| return gc;
        var curr = g.allgc;
        while (curr) |obj| : (curr = obj.next) {
            if (obj.val == .upval and obj.val.upval == ptr) {
                ptr.gc = obj;
                return obj;
            }
        }
        return null;
    }
    if (T == *lua_State) {
        if (ptr.gc) |gc| return gc;
        var curr = g.allgc;
        while (curr) |obj| : (curr = obj.next) {
            if (obj.val == .thread and obj.val.thread == ptr) {
                ptr.gc = obj;
                return obj;
            }
        }
        return null;
    }
    return null;
}

fn markObject(L: *lua_State, gc: *VMGCObject, gray_list: *std.ArrayList(*VMGCObject)) !void {
    if (gc.color == .white) {
        gc.color = .gray;
        try gray_list.append(L.allocator, gc);
    }
}

fn markString(L: *lua_State, gray_list: *std.ArrayList(*VMGCObject), str: *lua_TString) !void {
    const g = G(L);
    str.marked = true;
    if (getGCObject(g, str)) |gc| try markObject(L, gc, gray_list);
}

fn markValue(L: *lua_State, gray_list: *std.ArrayList(*VMGCObject), val: TValue) !void {
    const g = G(L);
    switch (val) {
        .string => |s| if (s) |str| {
            str.marked = true;
            // Strings on allgc (long / external) need their VMGCObject
            // marked so the sweep keeps them alive while referenced.
            if (getGCObject(g, str)) |gc| try markObject(L, gc, gray_list);
        },
        .table => |t| if (t) |tbl| if (getGCObject(g, tbl)) |gc| try markObject(L, gc, gray_list),
        .function => |f| if (f) |cl| if (getGCObject(g, cl)) |gc| try markObject(L, gc, gray_list),
        .upval => |u| if (u) |uv| if (getGCObject(g, uv)) |gc| try markObject(L, gc, gray_list),
        .proto => |p| if (p) |pr| if (getGCObject(g, pr)) |gc| try markObject(L, gc, gray_list),
        .userdata => |u| if (u) |ud| if (getGCObject(g, ud)) |gc| try markObject(L, gc, gray_list),
        .thread => |t| if (t) |th| if (getGCObject(g, th)) |gc| try markObject(L, gc, gray_list),
        else => {},
    }
}

/// Mark a thread's stack slots (per its CallInfo chain) and open upvalues.
fn markThreadStack(L: *lua_State, gray_list: *std.ArrayList(*VMGCObject), th: *lua_State) !void {
    const g = G(L);
    var opt_th_ci: ?*CallInfo = th.ci;
    var next_th_ci_func: ?usize = null;
    while (opt_th_ci) |th_ci| {
        var s_idx = th_ci.func;
        const top_limit = if (next_th_ci_func) |nfunc| nfunc else th.top;
        const s_lim = @min(top_limit, th.stack.len);
        while (s_idx < s_lim) : (s_idx += 1) {
            try markValue(L, gray_list, th.stack[s_idx]);
        }
        next_th_ci_func = th_ci.func;
        opt_th_ci = th_ci.previous;
    }
    var curr_uv = th.openupval;
    while (curr_uv) |uv| {
        if (getGCObject(g, uv)) |gc| {
            try markObject(L, gc, gray_list);
        }
        curr_uv = uv.next;
    }
}

/// Traverse the outgoing references of a gray/black object, marking them.
/// Shared by the main collection and the pre-finalizer marking pass.
fn traverseGrayObject(L: *lua_State, gray_list: *std.ArrayList(*VMGCObject), gc: *VMGCObject) !void {
    const g = G(L);
    switch (gc.val) {
        .table => |t| {
            const mode = if (t.metatable) |mt| getWeakMode(L, mt) else WeakMode{ .keys = false, .vals = false };
            // Mark array part
            if (!mode.vals) {
                if (t.array.items.len > 0) {
                    for (t.array.items) |val| {
                        try markValue(L, gray_list, val);
                    }
                }
            }
            // Mark hash part
            for (t.node.items) |nd| {
                if (nd.val != .nil) {
                    if (!mode.keys) {
                        try markValue(L, gray_list, nd.key);
                    }
                    if (!mode.vals) {
                        try markValue(L, gray_list, nd.val);
                    }
                }
            }
            // Mark metatable
            if (t.metatable) |mt| {
                if (getGCObject(g, mt)) |mt_gc| {
                    try markObject(L, mt_gc, gray_list);
                }
            }
        },
        .closure => |cl| {
            switch (cl.*) {
                .c => |cc| {
                    for (cc.upvals) |uv| {
                        try markValue(L, gray_list, uv);
                    }
                },
                .lua => |lc| {
                    // Mark prototype
                    if (getGCObject(g, lc.p)) |proto_gc| {
                        try markObject(L, proto_gc, gray_list);
                    }
                    // Mark upvalues
                    for (lc.upvals) |opt_uv| {
                        if (opt_uv) |uv| {
                            if (getGCObject(g, uv)) |uv_gc| {
                                try markObject(L, uv_gc, gray_list);
                            }
                        }
                    }
                },
            }
        },
        .upval => |uv| {
            if (uv.v == &uv.value) {
                try markValue(L, gray_list, uv.value);
            } else {
                const addr = @intFromPtr(uv.v);
                var is_on_stack = false;
                var curr_th = G(L).thread_list;
                while (curr_th) |th| : (curr_th = th.twups) {
                    const base = @intFromPtr(th.stack.ptr);
                    const top_addr = base + th.top * @sizeOf(TValue);
                    if (addr >= base and addr < top_addr) {
                        is_on_stack = true;
                        break;
                    }
                }
                if (is_on_stack) {
                    try markValue(L, gray_list, uv.v.*);
                }
            }
        },
        .proto => |p| {
            if (p.source) |src| try markString(L, gray_list, src);
            // Mark upvalue names
            for (p.upvalues) |uvd| {
                if (uvd.name) |name| try markString(L, gray_list, name);
            }
            // Mark local variable names
            for (p.locvars) |lv| {
                if (lv.varname) |name| try markString(L, gray_list, name);
            }
            // Mark constants
            for (p.k) |val| {
                try markValue(L, gray_list, val);
            }
            // Mark nested prototypes
            for (p.p) |sub_p| {
                if (getGCObject(g, sub_p)) |sub_gc| {
                    try markObject(L, sub_gc, gray_list);
                }
            }
        },
        .userdata => |ud| {
            for (ud.uv) |val| {
                try markValue(L, gray_list, val);
            }
            if (ud.metatable) |mt| {
                if (getGCObject(g, mt)) |mt_gc| {
                    try markObject(L, mt_gc, gray_list);
                }
            }
        },
        .thread => |th| {
            try markThreadStack(L, gray_list, th);
        },
        // Strings (external) have no outgoing references to traverse.
        .string => {},
    }
}

fn freeGCObject(L: *lua_State, gc: *VMGCObject) void {
    const g = G(L);
    const sz: usize = switch (gc.val) {
        .table => |t| @sizeOf(lua_Table) + t.array.capacity * @sizeOf(TValue) + t.node.capacity * @sizeOf(Node),
        .string => |ts| @sizeOf(lua_TString) + ts.s.len + 1,
        .closure => |cl| switch (cl.*) {
            .c => |cc| @sizeOf(lua_Closure) + @sizeOf(lua_CClosure) + cc.upvals.len * @sizeOf(TValue),
            .lua => |lc| @sizeOf(lua_Closure) + @sizeOf(lua_LClosure) + lc.upvals.len * @sizeOf(?*UpVal),
        },
        .userdata => |ud| @sizeOf(lua_Udata) + ud.data.len + ud.uv.len * @sizeOf(TValue),
        .proto => @sizeOf(lua_Proto),
        .upval => @sizeOf(UpVal),
        .thread => |th| @sizeOf(lua_State) + th.stack.len * @sizeOf(TValue),
    };
    if (g.totalbytes >= sz + @sizeOf(VMGCObject)) {
        g.totalbytes -= sz + @sizeOf(VMGCObject);
    } else {
        g.totalbytes = 0;
    }
    switch (gc.val) {
        .table => |t| {
            ltable.deinit(t);
        },
        .closure => |cl| {
            switch (cl.*) {
                .c => |cc| {
                    L.allocator.free(cc.upvals);
                    L.allocator.destroy(cc);
                },
                .lua => |lc| {
                    L.allocator.free(lc.upvals);
                    L.allocator.destroy(lc);
                },
            }
            L.allocator.destroy(cl);
        },
        .upval => |uv| {
            L.allocator.destroy(uv);
        },
        .proto => |f| {
            destroyProto(L.allocator, f);
        },
        .userdata => |u| {
            L.allocator.free(u.data);
            if (u.uv.len > 0) L.allocator.free(u.uv);
            L.allocator.destroy(u);
        },
        .string => |ts| {
            if (ts.falloc) |falloc| {
                _ = falloc(ts.ud, @constCast(ts.s.ptr), ts.len + 1, 0);
            } else if (!ts.externally_owned and ts.s.len > 0) {
                L.allocator.free(ts.s);
            }
            L.allocator.destroy(ts);
        },
        .thread => |th| {
            if (g.thread_list == th) {
                g.thread_list = th.twups;
            } else {
                var prev_th = g.thread_list;
                while (prev_th) |p| {
                    if (p.twups == th) {
                        p.twups = th.twups;
                        break;
                    }
                    prev_th = p.twups;
                }
            }
            freeAllCallInfos(th);
            th.tbclist.deinit(th.allocator);
            th.allocator.free(th.stack);
            th.allocator.destroy(th);
        },
    }
    L.allocator.destroy(gc);
}

const WeakMode = struct { keys: bool, vals: bool };

fn getWeakMode(L: *lua_State, mt: *lua_Table) WeakMode {
    var keys = false;
    var vals = false;
    const g = G(L);
    const tm_mode_str = g.tmname[3] orelse return .{ .keys = false, .vals = false };
    const mode_val = ltable.get(mt, .{ .string = tm_mode_str });
    switch (mode_val) {
        .string => |s| {
            if (s) |str| {
                for (str.s) |c| {
                    if (c == 'k') keys = true;
                    if (c == 'v') vals = true;
                }
            }
        },
        else => {},
    }
    return .{ .keys = keys, .vals = vals };
}

fn getGCObjectFromValue(g: *global_State, val: TValue) ?*VMGCObject {
    return switch (val) {
        .table => |t| if (t) |p| getGCObject(g, p) else null,
        .string => |s| if (s) |p| getGCObject(g, p) else null,
        .function => |f| if (f) |p| getGCObject(g, p) else null,
        .userdata => |u| if (u) |p| getGCObject(g, p) else null,
        .thread => |t| if (t) |p| getGCObject(g, p) else null,
        .upval => |u| getGCObject(g, u),
        .proto => |p| if (p) |p_val| getGCObject(g, p_val) else null,
        else => null,
    };
}

fn isWhiteGCObject(g: *global_State, val: TValue) bool {
    if (getGCObjectFromValue(g, val)) |gc| {
        return gc.color == .white;
    }
    return false;
}

fn luaS_clearcache(L: *lua_State) void {
    const g = G(L);
    for (&g.strcache) |*bucket| {
        for (bucket) |*slot| {
            if (slot.*) |ts| {
                var is_dead = false;
                if (getGCObject(g, ts)) |gc| {
                    if (gc.color == .white) {
                        is_dead = true;
                    }
                } else {
                    if (!ts.marked) {
                        is_dead = true;
                    }
                }
                if (is_dead) {
                    slot.* = null;
                }
            }
        }
    }
}

pub inline fn luaC_condGC(L: *lua_State) void {
    const g = G(L);
    // Compare the live-object count against the count-based threshold (the
    // same condition the VM loop uses); comparing totalbytes here would fire
    // constantly, since a few large live objects can exceed the threshold.
    // BUG-100: GC failure on condGC is logged rather than silently ignored.
    if (g.gc_running and !g.gc_in_progress and g.gc_count > g.gc_threshold) {
        luaC_collectgarbage(L) catch |e| {
            std.debug.print("luazig: warning: GC error: {any}\n", .{e});
        };
    }
}

pub fn luaC_collectgarbage(L: *lua_State) !void {
    const g = G(L);
    if (g.gc_in_progress) return;
    g.gc_in_progress = true;
    defer g.gc_in_progress = false;

    // 1. Reset/Clear gray list
    var gray_list = std.ArrayList(*VMGCObject).empty;
    defer gray_list.deinit(L.allocator);

    // 2. Set all objects to white
    var curr = g.allgc;
    while (curr) |gc| {
        gc.color = .white;
        curr = gc.next;
    }
    var strt_it = g.strt.iterator();
    while (strt_it.next()) |entry| {
        entry.value_ptr.*.marked = false;
    }

    // 3. Mark roots
    // Root 1: Registry table
    try markValue(L, &gray_list, g.registry);

    // Root 2: Global metatables
    for (g.mt) |opt_mt| {
        if (opt_mt) |mt| {
            if (getGCObject(g, mt)) |gc| {
                try markObject(L, gc, &gray_list);
            }
        }
    }

    // Root 3: Metamethod names
    for (g.tmname) |opt_name| {
        if (opt_name) |name| {
            name.marked = true;
        }
    }

    // Root 3b: intentionally omitted. The string table is NOT a GC root:
    // interned strings are kept alive only when actually referenced (from the
    // stack, tables, protos, the metamethod-name table, or the API string
    // cache below). This matches the reference, which collects unreferenced
    // strings instead of pinning every interned literal.

    // Root 3c: intentionally omitted. The string cache is a weak reference
    // and is cleared of dead entries via luaS_clearcache before sweeping.

    // Root 4: The stack of all active states and call frames, plus the open
    // upvalues of the current thread. (The reference's traverseThread marks
    // open upvalues for every thread; ours were only marked for OTHER threads
    // in Root 4b, so a GC running on the current thread could collect an open
    // UpVal still linked in L.openupval -> use-after-free in closeupvals.)
    var opt_ci: ?*CallInfo = L.ci;
    var next_ci_func: ?usize = null;
    while (opt_ci) |ci| {
        var s_idx = ci.func;
        const top_limit = if (next_ci_func) |nfunc| nfunc else L.top;
        const s_lim = @min(top_limit, L.stack.len);
        while (s_idx < s_lim) : (s_idx += 1) {
            try markValue(L, &gray_list, L.stack[s_idx]);
        }
        next_ci_func = ci.func;
        opt_ci = ci.previous;
    }
    var curr_uv = L.openupval;
    while (curr_uv) |uv| {
        if (getGCObject(g, uv)) |gc| {
            try markObject(L, gc, &gray_list);
        }
        curr_uv = uv.next;
    }

    // Root 4b: The stack and open upvalues of the main thread (which is not
    // on allgc, so it is an unconditional GC root).
    if (g.mainthread) |mt| {
        if (mt != L) {
            try markThreadStack(L, &gray_list, mt);
        }
    }

    // 4. Traverse gray list until empty
    while (gray_list.pop()) |gc| {
        if (gc.color == .black) continue;
        gc.color = .black;
        try traverseGrayObject(L, &gray_list, gc);
    }

    // 4.5 Clear weak tables
    var clear_curr = g.allgc;
    while (clear_curr) |gc| {
        if (gc.color == .black) {
            switch (gc.val) {
                .table => |t| {
                    if (t.metatable) |mt| {
                        const mode = getWeakMode(L, mt);
                        if (mode.keys or mode.vals) {
                            // Clear weak array part (only values can be weak)
                            if (mode.vals) {
                                for (t.array.items) |*val| {
                                    if (isWhiteGCObject(g, val.*)) {
                                        val.* = .nil;
                                    }
                                }
                            }
                            // Clear weak hash part
                            for (t.node.items) |*nd| {
                                if (nd.key != .nil and nd.val != .nil) {
                                    const key_white = mode.keys and isWhiteGCObject(g, nd.key);
                                    const val_white = mode.vals and isWhiteGCObject(g, nd.val);
                                    if (key_white or val_white) {
                                        nd.val = .nil;
                                    }
                                }
                            }
                        }
                    }
                },
                else => {},
            }
        }
        clear_curr = gc.next;
    }

    luaS_clearcache(L);

    // 5. Sweep phase: free white objects
    // Pre-pass: identify objects with an unrun __gc finalizer and keep their
    // metatables alive (mark them gray and traverse), so the sweep can
    // safely inspect __gc and the finalizer call has a live metatable.
    var pending = std.ArrayList(*VMGCObject).empty;
    defer pending.deinit(L.allocator);
    {
        var pp = g.allgc;
        while (pp) |gc| : (pp = gc.next) {
            if (gc.color != .white or gc.finalized) continue;
            const mt = metatableOf(L, gc);
            if (mt) |m| {
                if (getGCObject(g, m)) |mt_gc| {
                    const fin = rawHasFinalizer(L, m);
                    if (fin) {
                        try pending.append(L.allocator, gc);
                        gc.pending_fin = true;
                        if (mt_gc.color == .white) {
                            mt_gc.color = .gray;
                            try gray_list.append(L.allocator, mt_gc);
                        }
                    }
                }
            }
        }
        // Traverse the metatables just kept alive (so __gc and friends survive).
        while (gray_list.pop()) |gc| {
            if (gc.color == .black) continue;
            gc.color = .black;
            try traverseGrayObject(L, &gray_list, gc);
        }
    }

    var prev_gc: ?*VMGCObject = null;
    var sweep_curr = g.allgc;
    g.gc_count = 0;
    while (sweep_curr) |gc| {
        const next_gc = gc.next;
        if (gc.color == .white) {
            if (gc.finalized) {
                // Finalizer already ran last cycle; now free it.
                if (prev_gc) |prev| {
                    prev.next = next_gc;
                } else {
                    g.allgc = next_gc;
                }
                freeGCObject(L, gc);
                sweep_curr = next_gc;
                continue;
            }
            // Objects with an unrun __gc finalizer (flagged by the pre-pass)
            // are kept for one cycle and finalized after the sweep; next
            // collection frees them.
            if (gc.pending_fin) {
                gc.pending_fin = false;
                // Unlink from allgc and link into the pending-finalization list.
                if (prev_gc) |prev| {
                    prev.next = next_gc;
                } else {
                    g.allgc = next_gc;
                }
                gc.next = g.finobj;
                g.finobj = gc;
                gc.color = .white;
                sweep_curr = next_gc;
                continue;
            }
            // Unlink from allgc
            if (prev_gc) |prev| {
                prev.next = next_gc;
            } else {
                g.allgc = next_gc;
            }

            // Free the object's resources
            freeGCObject(L, gc);
        } else {
            gc.color = .white; // Reset to white for next cycle
            prev_gc = gc;
            g.gc_count += 1;
        }
        sweep_curr = next_gc;
    }
    g.gc_threshold = @max(1000, g.gc_count * 2);

    // Sweep strings:
    // First, find all unmarked strings. Collect the `*lua_TString` values
    // (whose `.s` bytes are stable and independent of the map's key array);
    // do NOT retain slices into the map itself, because `swapRemove` below
    // reorders that array and would invalidate them.
    var dead_strings = std.ArrayList(*lua_TString).empty;
    defer dead_strings.deinit(L.allocator);

    var str_it = g.strt.iterator();
    while (str_it.next()) |entry| {
        const ts = entry.value_ptr.*;
        if (!ts.marked) {
            try dead_strings.append(L.allocator, ts);
        } else {
            ts.marked = false; // Reset for next GC cycle
        }
    }

    // Now remove from strt table and free the dead short strings. Short
    // strings are NOT registered in allgc (see lstring.createString), so the
    // allgc sweep above never sees them; without this they would leak.
    for (dead_strings.items) |ts| {
        _ = g.strt.swapRemove(ts.s);
        if (ts.falloc) |falloc| {
            _ = falloc(ts.ud, @constCast(ts.s.ptr), ts.len + 1, 0);
        } else if (!ts.externally_owned and ts.s.len > 0) {
            L.allocator.free(ts.s);
        }
        L.allocator.destroy(ts);
    }

    // 6. Run pending finalizers. Each object's fields are marked (so the
    // objects they reference survive during the __gc call), the finalizer
    // runs, and the object is linked back into allgc as finalized so the next
    // collection frees it without re-running __gc.
    while (g.finobj) |fobj| {
        g.finobj = fobj.next;
        try callFinalizer(L, fobj);
    }
}

/// True if `gc` is a table/userdata whose metatable defines a `__gc` field.
/// Requires the metatable to still be alive (not swept).
fn hasFinalizer(L: *lua_State, gc: *VMGCObject) bool {
    const g = G(L);
    const mt = metatableOf(L, gc) orelse return false;
    if (getGCObject(g, mt)) |mt_gc| {
        if (mt_gc.color == .white) return false;
    }
    return rawHasFinalizer(L, mt);
}

/// Check `__gc` in a metatable without any liveness guard (only safe before
/// the sweep frees anything).
fn rawHasFinalizer(L: *lua_State, mt: *lua_Table) bool {
    const g = G(L);
    if (g.tmname[@intFromEnum(ltm.TMS.GC)]) |gc_name| {
        const tm = ltable.get(mt, TValue{ .string = gc_name });
        if (tm == .function or tm == .table) return true;
    }
    return false;
}

/// Metatable of a table/userdata GC object, if any.
fn metatableOf(L: *lua_State, gc: *VMGCObject) ?*lua_Table {
    _ = L;
    return switch (gc.val) {
        .table => |t| t.metatable,
        .userdata => |u| u.metatable,
        else => null,
    };
}

/// Mark an object's outgoing references, then invoke its `__gc` metamethod
/// with the object as argument. The object is relinked into allgc as
/// finalized so the next collection frees it.
fn callFinalizer(L: *lua_State, gc: *VMGCObject) !void {
    const g = G(L);
    // Mark this object and its references so they survive the finalizer call.
    var gray_list = std.ArrayList(*VMGCObject).empty;
    defer gray_list.deinit(L.allocator);
    gc.color = .gray;
    try gray_list.append(L.allocator, gc);
    while (gray_list.pop()) |c| {
        if (c.color == .black) continue;
        c.color = .black;
        try traverseGrayObject(L, &gray_list, c);
    }

    const obj_val: TValue = switch (gc.val) {
        .table => |t| TValue{ .table = t },
        .userdata => |u| TValue{ .userdata = u },
        else => unreachable,
    };
    const mt: *lua_Table = switch (gc.val) {
        .table => |t| t.metatable.?,
        .userdata => |u| u.metatable.?,
        else => unreachable,
    };
    const tm = ltable.get(mt, TValue{ .string = g.tmname[@intFromEnum(ltm.TMS.GC)].? });
    if (tm == .function or tm == .table) {
        if (L.top + 2 < L.stack.len) {
            L.stack[L.top] = tm;
            L.stack[L.top + 1] = obj_val;
            L.top += 2;
            const old_allowhook = L.allowhook;
            L.allowhook = 0;
            const old_fin = if (L.ci) |ci| blk: {
                const o = ci.is_fin;
                ci.is_fin = true;
                break :blk o;
            } else null;
            _ = lua_pcallk(L, 1, 0, 0, 0, null) catch |e| {
                // BUG-100: log __gc finalizer errors instead of swallowing.
                std.debug.print("luazig: warning: __gc finalizer error: {any}\n", .{e});
            };
            if (L.ci) |ci| {
                ci.is_fin = old_fin orelse false;
            }
            L.allowhook = old_allowhook;
        }
    }

    // Relink into allgc; the next collection frees it (finalizer already ran).
    gc.finalized = true;
    gc.color = .white;
    gc.next = g.allgc;
    g.allgc = gc;
}

pub const LUA_GCSTOP: i32 = 0;
pub const LUA_GCRESTART: i32 = 1;
pub const LUA_GCCOLLECT: i32 = 2;
pub const LUA_GCCOUNT: i32 = 3;
pub const LUA_GCCOUNTB: i32 = 4;
pub const LUA_GCSTEP: i32 = 5;
pub const LUA_GCISRUNNING: i32 = 6;
pub const LUA_GCGEN: i32 = 7;
pub const LUA_GCINC: i32 = 8;
pub const LUA_GCPARAM: i32 = 9;

// GC parameter indices (for LUA_GCPARAM)
pub const LUA_GCPMINORMUL: i32 = 0;
pub const LUA_GCPMAJORMINOR: i32 = 1;
pub const LUA_GCPMINORMAJOR: i32 = 2;
pub const LUA_GCPPAUSE: i32 = 3;
pub const LUA_GCPSTEPMUL: i32 = 4;
pub const LUA_GCPSTEPSIZE: i32 = 5;
pub const LUA_GCPN: usize = 6;

/// Lua GC control. `what` selects the operation; `arg` is operation-dependent.
/// For all options except `LUA_GCPARAM`, `value` is ignored (pass 0).
/// For `LUA_GCPARAM`, `arg` is the parameter index and `value` is the new
/// value to set (pass -1 to get the current parameter without setting).
pub fn lua_gc(L: *lua_State, what: i32, arg: i32, value: i32) i32 {
    const g = G(L);
    switch (what) {
        LUA_GCSTOP => {
            g.gc_running = false;
            return 0;
        },
        LUA_GCRESTART => {
            g.gc_running = true;
            return 0;
        },
        LUA_GCCOLLECT => {
            luaC_collectgarbage(L) catch return -1;
            return 0;
        },
        LUA_GCCOUNT => {
            return @as(i32, @intCast(g.totalbytes / 1024));
        },
        LUA_GCCOUNTB => {
            return @as(i32, @intCast(g.totalbytes % 1024));
        },
        LUA_GCSTEP => {
            // Run a full synchronous collection for each step request.
            // (A real incremental GC would only do a portion.)
            luaC_collectgarbage(L) catch return -1;
            return 1;
        },
        LUA_GCISRUNNING => {
            return if (g.gc_running) 1 else 0;
        },
        LUA_GCGEN => {
            // Acknowledge request for generational mode; keep mark-and-sweep.
            return 0;
        },
        LUA_GCINC => {
            // Acknowledge request for incremental mode; keep mark-and-sweep.
            return 0;
        },
        LUA_GCPARAM => {
            const param = @as(usize, @intCast(arg));
            if (param >= LUA_GCPN) return -1;
            if (value >= 0) {
                g.gcparams[param] = @as(u8, @intCast(@min(@as(u64, @intCast(value)), 255)));
            }
            return @as(i32, @intCast(g.gcparams[param]));
        },
        else => return -1,
    }
}

pub fn luaG_errormsg(L: *lua_State) anyerror {
    if (L.top > 0) {
        L.err_obj = L.stack[L.top - 1];
    }
    if (L.errfunc != 0) {
        if (lua_checkstack(L, 2) == 0 or L.top + 2 >= L.stack.len) {
            if (lstring.luaS_new(L, "error in error handling")) |ts| {
                L.stack[L.top - 1] = TValue{ .string = ts };
                L.err_obj = L.stack[L.top - 1];
            } else |_| {}
            return error.StackError;
        }
        const errfunc = @as(usize, @intCast(L.errfunc - 1));
        const err_obj = L.stack[L.top - 1];

        L.stack[L.top] = err_obj;
        L.stack[L.top - 1] = L.stack[errfunc];
        L.top += 1;

        // Invoke the error handler. We deliberately do NOT clear L.errfunc
        // (mirroring the reference): if the handler raises, luaG_errormsg is
        // re-entered and invokes the handler again, so a bounded handler
        // recursion (e.g. xpcall(error, err, n) where err eventually returns
        // "END") resolves normally, while an unbounded one (xpcall(error,
        // error)) terminates via the C-call limit in precall -> luaD_errerr,
        // yielding "error in error handling".
        var handler_returned = true;
        const err_ci = precall(L, L.top - 2, 1) catch |e| b: {
            handler_returned = false;
            if (e == error.StackError or e == error.StackOverflow) {
                // The handler could not run at all (stack exhausted).
                if (lstring.luaS_new(L, "error in error handling")) |ts| {
                    L.err_obj = TValue{ .string = ts };
                } else |_| {}
            }
            // For RuntimeError, L.err_obj already holds the propagated error
            // (e.g. from a nested luaD_errerr), which we keep.
            break :b @as(?*CallInfo, null);
        };
        if (err_ci) |eci| {
            lvm.run(L, eci) catch |e| {
                handler_returned = false;
                if (e == error.StackOverflow or e == error.StackError) {
                    if (lstring.luaS_new(L, "error in error handling")) |ts| {
                        L.err_obj = TValue{ .string = ts };
                    } else |_| {}
                }
            };
        }
        if (handler_returned) {
            // Handler succeeded: its result is at L.top-1.
            if (L.top > 0) {
                L.err_obj = L.stack[L.top - 1];
            }
        } else if (L.top > 0) {
            // Handler raised: place the propagated error object on the stack.
            L.stack[L.top - 1] = L.err_obj;
        }
    }
    // Record the name of the erroring function (and how it was called), so a
    // dead coroutine's debug.traceback can report where it failed even though
    // the C frame is unwound during error propagation.
    if (L.ci) |eci| {
        var fname: ?[]const u8 = null;
        const kind = getfuncname(L, eci, &fname);
        if (kind) |k| {
            L.err_name = fname;
            L.err_namewhat = k;
        }
    }
    return error.RuntimeError;
}

pub fn lua_error(L: *lua_State) anyerror {
    const err_obj = L.stack[L.top - 1];
    if (err_obj == .nil) {
        const ts = try lstring.luaS_new(L, "<no error object>");
        L.stack[L.top - 1] = TValue{ .string = ts };
    }
    return luaG_errormsg(L);
}

pub fn lua_next(L: *lua_State, idx: i32) anyerror!i32 {
    const t = getTable(L, idx) orelse return 0;
    const key = stackAt(L, -1);
    const r = ltable.next(t, key) catch |err| switch (err) {
        error.InvalidKeyToNext => {
            try luaG_runerror(L, "invalid key to 'next'");
            return 0;
        },
        else => return err,
    };
    L.top -= 1;
    if (r) |kv| {
        L.stack[L.top] = kv.key;
        L.top += 1;
        L.stack[L.top] = kv.val;
        L.top += 1;
        return 1;
    }
    return 0;
}

pub inline fn isStringish(v: TValue) bool {
    return switch (v) {
        .string, .number, .integer => true,
        else => false,
    };
}

pub fn luaV_concat(L: *lua_State, total: usize, ra_idx: usize) !void {
    if (total <= 1) return;
    var list = std.ArrayListUnmanaged(u8).empty;
    defer list.deinit(L.allocator);
    var k: usize = total;
    while (k > 1) {
        const lhs_idx = ra_idx + k - 2;
        const rhs_idx = ra_idx + k - 1;
        const lhs = L.stack[lhs_idx];
        const rhs = L.stack[rhs_idx];
        if (isStringish(lhs) and isStringish(rhs)) {
            var start = k - 2;
            while (start > 0 and isStringish(L.stack[ra_idx + start - 1])) : (start -= 1) {}
            list.clearRetainingCapacity();
            var j = start;
            while (j < k) : (j += 1) {
                switch (L.stack[ra_idx + j]) {
                    .string => |s| try list.appendSlice(L.allocator, s.?.s),
                    .number, .integer => {
                        var b: [128]u8 = undefined;
                        try list.appendSlice(L.allocator, luaO_tostringbuff(L.stack[ra_idx + j], &b));
                    },
                    else => unreachable,
                }
            }
            const ts = try lstring.luaS_new(L, list.items);
            L.stack[ra_idx + start] = .{ .string = ts };
            k = start + 1;
        } else {
            try ltm.luaT_trybinTM(L, &lhs, &rhs, lhs_idx, .CONCAT);
            k -= 1;
        }
    }
}

pub fn lua_concat(L: *lua_State, n: i32) !void {
    if (n <= 0) {
        _ = lua_pushstring(L, "");
        return;
    }
    if (n == 1) return;
    const count = @as(usize, @intCast(n));
    if (count > L.top) return error.RuntimeError;
    const start = L.top - count;
    try luaV_concat(L, count, start);
    L.top = start + 1;
}

pub fn lua_len(L: *lua_State, idx: i32) !void {
    if (lua_checkstack(L, 1) == 0) return error.OutOfMemory;
    const v = stackAt(L, idx);
    switch (v) {
        .string => |s| {
            lua_pushinteger(L, @as(i64, @intCast(s.?.s.len)));
        },
        .table => |t| {
            const tm = if (t.?.metatable) |mt| ltm.luaT_gettm(mt, .LEN, G(L).tmname[@intFromEnum(ltm.TMS.LEN)].?) else null;
            if (tm) |tm_val| {
                const res_val = try ltm.luaT_callTMres(L, tm_val, &v, &v, L.stack.len);
                L.stack[L.top] = res_val;
                L.top += 1;
            } else {
                lua_pushinteger(L, @as(i64, @intCast(ltable.getn(t.?))));
            }
        },
        else => {
            const tm = ltm.luaT_gettmbyobj(L, v, .LEN);
            if (tm == .nil) {
                return error.RuntimeError;
            }
            const res_val = try ltm.luaT_callTMres(L, tm, &v, &v, L.stack.len);
            L.stack[L.top] = res_val;
            L.top += 1;
        },
    }
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isHexDigit(c: u8) bool {
    return isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

fn skipDigits(s: []const u8, i: usize) usize {
    var j = i;
    while (j < s.len and isDigit(s[j])) : (j += 1) {}
    return j;
}

fn isspace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0B or c == 0x0C;
}

fn hexValue(c: u8) u64 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    return c - 'A' + 10;
}

/// Parse a whole-string integer (leading/trailing spaces ignored, requires
/// the trimmed string to be an integer); returns null otherwise. Mirrors the
/// C reference `l_str2int`.
fn parseInteger(s: []const u8) ?i64 {
    var i: usize = 0;
    while (i < s.len and isspace(s[i])) : (i += 1) {}
    if (i >= s.len) return null;
    var neg = false;
    if (s[i] == '+' or s[i] == '-') {
        neg = s[i] == '-';
        i += 1;
        if (i >= s.len) return null;
    }
    const is_neg_val: u32 = if (neg) 1 else 0;
    var a: u64 = 0;
    var digits: usize = 0;
    if (s[i] == '0' and i + 1 < s.len and (s[i + 1] == 'x' or s[i + 1] == 'X')) {
        i += 2;
        while (i < s.len and isHexDigit(s[i])) : (i += 1) {
            const d = hexValue(s[i]);
            a = a *% 16 +% d;
            digits += 1;
        }
    } else {
        const max_by_10 = @as(u64, 9223372036854775807) / 10;
        const max_last_d = @as(u32, 9223372036854775807 % 10);
        while (i < s.len and isDigit(s[i])) : (i += 1) {
            const d = @as(u32, s[i] - '0');
            if (a >= max_by_10 and (a > max_by_10 or d > max_last_d + is_neg_val)) {
                return null; // overflow
            }
            a = a * 10 + d;
            digits += 1;
        }
    }
    if (digits == 0) return null;
    var k = i;
    while (k < s.len and isspace(s[k])) : (k += 1) {}
    if (k != s.len) return null; // trailing non-space
    const unsigned_res = if (neg) (0 -% a) else a;
    return @bitCast(unsigned_res);
}

/// True iff every byte of `s[off..]` is whitespace.
fn trailingAllSpace(s: []const u8, off: usize) bool {
    var k = off;
    while (k < s.len and isspace(s[k])) : (k += 1) {}
    return k == s.len;
}

extern "c" fn localeconv() *Lconv;
const Lconv = extern struct {
    decimal_point: [*:0]const u8,
    thousands_sep: [*:0]const u8,
    grouping: [*:0]const u8,
};

/// Return the current locale's decimal-point character ('.' if unknown).
fn localeDecimalPoint() u8 {
    const lc = localeconv();
    const dp = lc.decimal_point;
    if (dp[0] == 0) return '.';
    return dp[0];
}

/// Locale-aware float parse mirroring the C reference `l_str2d`: try the C
/// library `strtod` (which respects the current locale's decimal point),
/// and if that does not consume the whole (space-trimmed) string, retry after
/// replacing a '.' with the locale decimal point. Leading/trailing spaces are
/// tolerated (strtod skips leading; trailing is checked by the caller).
fn parseLocaleNumber(s: []const u8) ?f64 {
    if (s.len == 0) return null;
    var buf: [2048]u8 = undefined;
    if (s.len >= buf.len) return null; // too long for locale fallback
    @memcpy(buf[0..s.len], s);
    buf[s.len] = 0;
    var endptr: ?[*:0]const u8 = undefined;
    const cstr: [*:0]const u8 = @ptrCast(@constCast(&buf));
    const n = strtod(cstr, &endptr);
    if (endptr != null and endptr.? != cstr) {
        const off = @intFromPtr(endptr.?) - @intFromPtr(&buf);
        if (trailingAllSpace(s, off)) return n;
    }
    // Fallback: replace '.' or ',' with the locale decimal point and retry.
    const dp = localeDecimalPoint();
    var k: usize = 0;
    while (k < s.len) : (k += 1) {
        if (buf[k] == '.' or buf[k] == ',') {
            buf[k] = dp;
            break;
        }
    }
    const n2 = strtod(cstr, &endptr);
    if (endptr != null and endptr.? != cstr) {
        const off = @intFromPtr(endptr.?) - @intFromPtr(&buf);
        if (trailingAllSpace(s, off)) return n2;
    }
    return null;
}

/// Locale-aware parse of a string to a numeric TValue (integer or float).
/// Mirrors lua_stringtonumber's parsing (leading/trailing spaces ignored,
/// "inf"/"nan" rejected) but returns the value instead of pushing it.
pub fn tonumberValue(s: []const u8) ?TValue {
    if (s.len == 0) return null;
    // Trim leading and trailing whitespace (mirrors luaO_str2num: only
    // surrounding spaces are ignored; nothing else may trail the number).
    var start: usize = 0;
    while (start < s.len and isspace(s[start])) : (start += 1) {}
    if (start >= s.len) return null;
    var end = s.len;
    while (end > start and isspace(s[end - 1])) : (end -= 1) {}
    const trimmed = s[start..end];
    if (trimmed.len == 0) return null;
    // reject "inf"/"nan" tokens (reference: l_str2d rejects 'n'/'N')
    {
        var lower_i = trimmed[0];
        if (lower_i >= 'A' and lower_i <= 'Z') lower_i += 32;
        if (lower_i == 'i' or lower_i == 'n') {
            var rest_lower: [10]u8 = undefined;
            const copy_len = @min(trimmed.len, rest_lower.len);
            _ = std.ascii.lowerString(rest_lower[0..copy_len], trimmed[0..copy_len]);
            if (std.mem.eql(u8, rest_lower[0..3], "inf") or
                std.mem.eql(u8, rest_lower[0..3], "nan"))
            {
                return null;
            }
        }
    }
    if (parseInteger(trimmed)) |iv| return TValue{ .integer = iv };
    if (parseLocaleNumber(trimmed)) |n| return TValue{ .number = n };
    return null;
}

pub fn lua_stringtonumber(L: *lua_State, s: []const u8) usize {
    // Mirrors luaO_str2num: leading/trailing spaces ignored, but nothing else
    // may trail the number. Returns consumed-length + 1 on success, 0 on
    // failure. The reference rejects "inf"/"nan" tokens.
    if (tonumberValue(s)) |v| {
        if (v == .integer) {
            lua_pushinteger(L, v.integer);
        } else {
            lua_pushnumber(L, v.number);
        }
        return s.len + 1;
    }
    return 0;
}

/// Converts the number at stack index `idx` to a string and writes it into
/// `buff`. Returns the number of bytes written (including a trailing null)
/// on success, or 0 if the value is not a number. `buff` should be at least
/// `LUA_N2SBUFFSZ` bytes.
pub fn lua_numbertocstring(L: *lua_State, idx: i32, buff: []u8) usize {
    const v = stackAt(L, idx);
    switch (v) {
        .number => |n| {
            const s = std.fmt.bufPrint(buff, "{d}", .{n}) catch return 0;
            if (s.len >= buff.len) return 0;
            buff[s.len] = 0;
            return s.len + 1;
        },
        else => return 0,
    }
}

pub fn lua_atpanic(L: *lua_State, panicf: ?lua_CFunction) ?lua_CFunction {
    const g = G(L);
    const old = g.panic;
    g.panic = panicf;
    return old;
}

pub fn lua_version(L: *lua_State) lua_Number {
    _ = L;
    return LUA_VERSION_NUM;
}

pub fn lua_getallocf(L: *lua_State, ud: ?*?*anyopaque) lua_Alloc {
    const g = G(L);
    if (ud) |p| p.* = g.alloc_ud;
    return g.allocf;
}

pub fn lua_setallocf(L: *lua_State, f: lua_Alloc, ud: ?*anyopaque) void {
    const g = G(L);
    g.allocf = f;
    g.alloc_ud = ud;
}

pub fn checkclosemth(L: *lua_State, abs: usize) !void {
    const v = L.stack[abs];
    if (v == .nil or (v == .boolean and v.boolean == false)) {
        return;
    }
    const mt = switch (v) {
        .table => |t| if (t) |x| x.metatable else null,
        .userdata => |u| if (u) |x| x.metatable else null,
        else => null,
    };
    const tm = if (mt) |m| ltm.luaT_gettm(m, .CLOSE, G(L).tmname[@intFromEnum(ltm.TMS.CLOSE)].?) else null;
    if (tm == null or tm.? == .nil) {
        const ci = L.ci.?;
        const idx = @as(i32, @intCast(abs)) - @as(i32, @intCast(ci.base));
        var vname: ?[]const u8 = null;
        if (ci.func != 0) {
            const val = L.stack[ci.func];
            if (val == .function and val.function.?.* == .lua) {
                const proto = val.function.?.lua.p;
                vname = luaF_getlocalname(proto, idx + 1, @intCast(currentpc(ci)));
            }
        }
        const name = vname orelse "?";
        const msg = try std.fmt.allocPrint(L.allocator, "variable '{s}' got a non-closable value", .{name});
        defer L.allocator.free(msg);
        const ts = try lstring.luaS_new(L, msg);
        L.stack[L.top] = TValue{ .string = ts };
        L.top += 1;
        return luaG_errormsg(L);
    }
}

pub fn lua_toclose(L: *lua_State, idx: i32) !void {
    const abs = @as(usize, @intCast(lua_absindex(L, idx))) - 1;
    try checkclosemth(L, abs);
    const v = L.stack[abs];
    if (v != .nil and (v != .boolean or v.boolean != false)) {
        try L.tbclist.append(L.allocator, abs);
    }
}

pub fn lua_closeslot(L: *lua_State, idx: i32) void {
    const abs = @as(usize, @intCast(lua_absindex(L, idx))) - 1;
    if (L.tbclist.items.len > 0) {
        var i: usize = L.tbclist.items.len;
        while (i > 0) {
            i -= 1;
            if (L.tbclist.items[i] == abs) {
                _ = L.tbclist.swapRemove(i);
                break;
            }
        }
    }
    _ = close_one_slot(L, abs, null) catch null;
}

pub fn luaL_newstate_io(L: *lua_State, gpa: std.mem.Allocator, io: std.Io) !void {
    const g = try gpa.create(global_State);
    g.* = .{
        .allocator = gpa,
        .allocf = &l_alloc,
        .alloc_ud = null,
        .alloc_wrapper = .{ .alloc = gpa },
        .strt = std.array_hash_map.String(*lua_TString).empty,
        .seed = @intFromPtr(L) ^ 0x9e3779b97f4a7c15,
        .registry = TValue{ .nil = {} },
        .mt = [_]?*lua_Table{null} ** 9,
        .tmname = [_]?*lua_TString{null} ** 25,
        .io_backend = null,
        .io = io,
        .prng_state = [_]u64{ 0, 0, 0, 0 },
        .clibs = .empty,
    };
    g.prng_state[0] = g.seed;
    g.prng_state[1] = 0xff;
    g.prng_state[2] = 0;
    g.prng_state[3] = 0;
    {
        var i: i32 = 0;
        while (i < 16) : (i += 1) {
            const s0 = g.prng_state[0];
            const s1 = g.prng_state[1];
            const s2 = g.prng_state[2] ^ s0;
            const s3 = g.prng_state[3] ^ s1;
            g.prng_state[0] = s0 ^ s3;
            g.prng_state[1] = s1 ^ s2;
            g.prng_state[2] = s2 ^ (s1 << 17);
            g.prng_state[3] = (s3 << 45) | (s3 >> 19);
        }
    }
    g.alloc_ud = @ptrCast(&g.alloc_wrapper);
    // Initialize the API string cache to empty (all slots null).
    for (&g.strcache) |*bucket| {
        for (bucket) |*slot| slot.* = null;
    }
    const stack = try gpa.alloc(TValue, LUA_MINSTACK + 1);
    for (stack) |*item| {
        item.* = .{ .nil = {} };
    }
    L.* = .{
        .tt = 0,
        .marked = 0,
        .gch = 0,
        .allowhook = 1,
        .status = 0,
        .top = 0,
        .l_G = g,
        .ci = null,
        .stack = stack,
        .stack_last = stack.len - 1,
        .openupval = null,
        .tbclist = .empty,
        .gclist = null,
        .twups = null,
        .errorJmp = null,
        .base_ci = .{ .func = 0, .base = 0, .top = LUA_MINSTACK, .nresults = 0, .savedpc = 0, .previous = null, .next = null, .k = null, .ctx = 0, .nyield = 0 },
        .hook = null,
        .errfunc = 0,
        .nCcalls = 0,
        .noyield = 1, // main thread is always non-yieldable
        .oldpc = 0,
        .nci = 0,
        .basehookcount = 0,
        .hookcount = 0,
        .hookmask = 0,
        .transferinfo = .{ .ftransfer = 0, .ntransfer = 0 },
        .allocator = gpa,
    };
    L.ci = &L.base_ci;

    // Initialize registry and globals tables
    const registry_tab = try ltable.createTable(gpa, 3, 0);
    try registerGC(L, registry_tab);
    g.registry = TValue{ .table = registry_tab };
    g.mainthread = L;
    try ltable.setInt(registry_tab, llimits.LUA_RIDX_MAINTHREAD, TValue{ .thread = L });
    const globals_tab = try ltable.createTable(gpa, 0, 0);
    try registerGC(L, globals_tab);
    try ltable.setInt(registry_tab, 2, TValue{ .table = globals_tab });
    try ltm.luaT_init(L);
}

pub fn luaL_newstate(L: *lua_State, gpa: std.mem.Allocator) !void {
    if (@import("builtin").is_test) {
        var threaded: std.Io.Threaded = .init_single_threaded;
        threaded.allocator = gpa;
        try luaL_newstate_io(L, gpa, threaded.io());
        L.l_G.?.io_backend = threaded;
        L.l_G.?.io = L.l_G.?.io_backend.?.io();
    } else {
        var threaded = std.Io.Threaded.init(gpa, .{});
        errdefer threaded.deinit();
        try luaL_newstate_io(L, gpa, threaded.io());
        L.l_G.?.io_backend = threaded;
        L.l_G.?.io = L.l_G.?.io_backend.?.io();
    }
}

pub fn createargtable(L: *lua_State, args: []const []const u8) !void {
    // Build the `arg` table (as in the reference standalone interpreter):
    //   arg[0] = script name (args[1]), arg[1..] = extra CLI args (args[2..]).
    // When running the REPL (no script), the table is left empty.
    lua_createtable(L, 0, 0);
    if (args.len >= 2) {
        _ = lua_pushstring(L, args[1]);
        try lua_rawseti(L, -2, 0);
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            _ = lua_pushstring(L, args[i]);
            try lua_rawseti(L, -2, @as(i64, @intCast(i - 1)));
        }
    }
    try lua_setglobal(L, "arg");
}

pub fn luaL_dostring(L: *lua_State, s: []const u8, name: []const u8) !i32 {
    var data = s;
    const status = lua_load(L, luaL_dostringReader, @as(?*anyopaque, @ptrCast(&data)), name, "bt");
    if (status != LUA_OK) {
        return status;
    }
    return lua_pcallk(L, 0, LUA_MULTRET, 0, 0, null) catch |e| {
        return if (e == error.Yield) LUA_YIELD else LUA_ERRRUN;
    };
}

pub fn luaL_dostringReader(L: *lua_State, data: ?*anyopaque, size: ?*usize) anyerror!?[]const u8 {
    _ = L;
    const slice_ptr = @as(?*[]const u8, @ptrCast(@alignCast(data))) orelse return null;
    if (slice_ptr.*.len == 0) {
        if (size) |s| s.* = 0;
        return null;
    }
    const chunk = slice_ptr.*;
    slice_ptr.* = &[_]u8{};
    if (size) |s| s.* = chunk.len;
    return chunk;
}

pub const lauxlib = @import("lauxlib.zig");
pub const luaL_openlibs = lauxlib.luaL_openlibs;
pub const luaL_newmetatable = @import("lauxlib.zig").luaL_newmetatable;
pub const luaL_setmetatable = @import("lauxlib.zig").luaL_setmetatable;
pub const luaL_testudata = @import("lauxlib.zig").luaL_testudata;
pub const luaL_checkudata = @import("lauxlib.zig").luaL_checkudata;
pub const luaL_getenv = @import("lauxlib.zig").luaL_getenv;
pub const luaL_newtable = @import("lauxlib.zig").luaL_newtable;
pub const luaL_len = @import("lauxlib.zig").luaL_len;
pub const luaL_where = @import("lauxlib.zig").luaL_where;

pub const LUA_BASELIB: i32 = 1 << 0;
pub const LUA_COLIB: i32 = 1 << 1;
pub const LUA_TABLIB: i32 = 1 << 2;
pub const LUA_IOLIB: i32 = 1 << 3;
pub const LUA_OSLIB: i32 = 1 << 4;
pub const LUA_STRLIB: i32 = 1 << 5;
pub const LUA_MATHLIB: i32 = 1 << 6;
pub const LUA_UTF8LIB: i32 = 1 << 7;
pub const LUA_DBLIB: i32 = 1 << 8;
pub const LUA_LOADLIB: i32 = 1 << 9;
pub const LUA_BITLIB: i32 = 1 << 10;
pub const LUA_COROLIB: i32 = 1 << 1;

pub fn lua_tostring(L: *lua_State, idx: i32) ?[]const u8 {
    return lua_tolstring(L, idx, null);
}

pub fn lua_close(L: *lua_State) void {
    if (L.l_G) |g| {
        L.openupval = null;

        // Free CallInfo structs still on the active call chain.
        var curr_ci = L.ci;
        while (curr_ci) |ci| {
            const prev = ci.previous;
            if (ci != &L.base_ci) {
                L.allocator.destroy(ci);
            }
            curr_ci = prev;
        }
        L.ci = null;

        // Free recycled CallInfo structs held in the freelist.
        var free_ci = L.ci_free;
        while (free_ci) |ci| {
            const nextf = ci.freenext;
            L.allocator.destroy(ci);
            free_ci = nextf;
        }
        L.ci_free = null;

        // Free all GC objects registered in allgc
        var curr_gc = g.allgc;
        while (curr_gc) |gc| {
            const next_gc = gc.next;
            freeGCObject(L, gc);
            curr_gc = next_gc;
        }
        g.allgc = null;

        // BUG-090: Also free objects on the finobj list (objects whose __gc
        // finalizer ran but were deferred to the next sweep).
        var curr_fin = g.finobj;
        while (curr_fin) |gc| {
            const next_fin = gc.next;
            freeGCObject(L, gc);
            curr_fin = next_fin;
        }
        g.finobj = null;

        // Free string table entries
        var it = g.strt.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            g.allocator.destroy(entry.value_ptr.*);
            g.allocator.free(key);
        }
        g.strt.deinit(g.allocator);
        if (g.io_backend) |*threaded| {
            threaded.deinit();
        }
        // Free all created threads
        var curr_thread = g.thread_list;
        while (curr_thread) |t| {
            const next_thread = t.twups;
            freeAllCallInfos(t);
            t.tbclist.deinit(t.allocator);
            t.allocator.free(t.stack);
            t.allocator.destroy(t);
            curr_thread = next_thread;
        }

        // Free all opened dynamic libraries in g.clibs
        for (g.clibs.items) |lib| {
            lib.close();
            g.allocator.destroy(lib);
        }
        g.clibs.deinit(g.allocator);
        g.thread_list = null;
        g.cfunc_cache.deinit(g.allocator);

        L.allocator.destroy(g);
    }
    L.tbclist.deinit(L.allocator);
    L.allocator.free(L.stack);
}
