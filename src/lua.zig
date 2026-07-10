const std = @import("std");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");
const lvm = @import("lvm.zig");

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
pub const LUA_REGISTRYINDEX: i32 = llimits.LUA_REGISTRYINDEX;
pub const LUA_OK: i32 = llimits.LUA_OK;
pub const LUA_YIELD: i32 = llimits.LUA_YIELD;
pub const LUA_ERRRUN: i32 = llimits.LUA_ERRRUN;
pub const LUA_ERRMEM: i32 = llimits.LUA_ERRMEM;
pub const LUA_ERRSYNTAX: i32 = llimits.LUA_ERRSYNTAX;
pub const LUA_MINSTACK: i32 = llimits.LUA_MINSTACK;
pub const LUA_NUMTYPES: i32 = llimits.LUA_NUMTYPES;

pub const lua_KContext = llimits.lua_KContext;
pub const lua_Alloc = llimits.lua_Alloc;
pub const lua_WarnFunction = llimits.lua_WarnFunction;

// Forward declarations
pub const lua_CFunction = *const fn (*lua_State) i32;
pub const lua_KFunction = *const fn (*lua_State, i32, lua_KContext) i32;
pub const lua_Reader = *const fn (*lua_State, ?*anyopaque, ?*usize) ?[]const u8;
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
    extraargs: u8,
    istailcall: bool,
    ftransfer: i32,
    ntransfer: i32,
    short_src: [LUA_IDSIZE]u8,
    i_ci: ?*lua_State,
};

pub const LUA_IDSIZE: usize = llimits.LUA_IDSIZE;

pub const LUA_HOOKCALL: i32 = llimits.LUA_HOOKCALL;
pub const LUA_HOOKRET: i32 = llimits.LUA_HOOKRET;
pub const LUA_HOOKLINE: i32 = llimits.LUA_HOOKLINE;
pub const LUA_HOOKCOUNT: i32 = llimits.LUA_HOOKCOUNT;
pub const LUA_MASKCALL: u32 = llimits.LUA_MASKCALL;
pub const LUA_MASKRET: u32 = llimits.LUA_MASKRET;
pub const LUA_MASKLINE: u32 = llimits.LUA_MASKLINE;
pub const LUA_MASKCOUNT: u32 = llimits.LUA_MASKCOUNT;

pub const LUA_COPYRIGHT = "Lua 5.5  Copyright (C) 1994-2026 Lua.org, PUC-Rio";
pub const LUA_AUTHORS = "R. Ierusalimschy, L. H. de Figueiredo, W. Celes";

pub const LUA_VERSION_MAJOR_N: u8 = 5;
pub const LUA_VERSION_MINOR_N: u8 = 5;
pub const LUA_VERSION_RELEASE_N: u8 = 1;

pub const LUA_VERSION_MAJOR: []const u8 = std.fmt.comptimePrint("{d}", .{LUA_VERSION_MAJOR_N});
pub const LUA_VERSION_MINOR: []const u8 = std.fmt.comptimePrint("{d}", .{LUA_VERSION_MINOR_N});
pub const LUA_VERSION_RELEASE: []const u8 = std.fmt.comptimePrint("{d}", .{LUA_VERSION_RELEASE_N});

pub const LUA_VERSION: []const u8 = "Lua " ++ LUA_VERSION_MAJOR ++ "." ++ LUA_VERSION_MINOR;
pub const LUA_RELEASE: []const u8 = LUA_VERSION ++ "." ++ LUA_VERSION_RELEASE;

pub const LUA_MULTRET: i32 = -1;

pub const lua_TString = struct {
    s: []const u8,
    len: usize,
};

pub const lua_Udata = struct {
    len: usize,
    metatable: ?*anyopaque,
};

pub const TValue = union(enum) {
    nil: void,
    boolean: bool,
    lightud: ?*anyopaque,
    number: f64,
    string: ?*lua_TString,
    table: ?*lua_Table,
    function: ?*lua_Closure,
    userdata: ?*lua_Udata,
    thread: ?*lua_State,
    upval: ?*UpVal,
    proto: ?*lua_Proto,

    fn typ(self: TValue) i32 {
        return switch (self) {
            .nil => LUA_TNIL,
            .boolean => LUA_TBOOLEAN,
            .lightud => LUA_TLIGHTUSERDATA,
            .number => LUA_TNUMBER,
            .string => LUA_TSTRING,
            .table => LUA_TTABLE,
            .function => LUA_TFUNCTION,
            .userdata => LUA_TUSERDATA,
            .thread => LUA_TTHREAD,
            .upval => LUA_TTHREAD,
            .proto => LUA_TFUNCTION,
        };
    }

    fn toBoolean(self: TValue) bool {
        return self != .nil;
    }
};

pub const lua_Table = struct {
    flags: u8,
    ls: i8,
    array: std.ArrayList(?TValue),
    i_size: u32,
    nsize: u32,
};

pub const lua_CClosure = struct {
    f: lua_CFunction,
    nups: u8,
};

pub const lua_Closure = union(enum) {
    c: *lua_CClosure,
    lua: *lua_Proto,
};

pub const lua_Proto = struct {
    source: ?[]const u8,
    size: usize,
    lineDefined: i32,
    lastLineDefined: i32,
    numParams: i32,
    isVarArg: bool,
    maxStackSize: i32,
    code: []lvm.Instruction,
    k: ?[]TValue,
    p: ?*lua_Proto,
};

pub const UpVal = struct {
    t: TValue,
    uv: ?*UpVal,
};

pub const CallInfo = struct {
    func: ?*lua_Proto,
    top: usize,
    nresults: i32,
};

pub const global_State = struct {
    // placeholder — full definition in lstate.zig
};

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
    stack: []TValue,
    stack_last: usize,
    openupval: ?*UpVal,
    tbclist: usize,
    gclist: ?*GCObject,
    twups: ?*lua_State,
    errorJmp: ?*lua_longjmp,
    base_ci: CallInfo,
    hook: ?lua_Hook,
    errfunc: isize,
    nCcalls: u32,
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

fn idxPtr(L: *lua_State, idx: i32) ?*TValue {
    if (idx > 0) {
        const u = @as(usize, @intCast(idx - 1));
        if (u < L.top) return &L.stack[u];
    } else if (idx < 0) {
        const abs = @as(usize, @intCast(-idx));
        if (abs <= L.top) return &L.stack[L.top - abs];
    }
    return null;
}

pub fn lua_absindex(L: *lua_State, idx: i32) i32 {
    if (idx >= 1 and @as(usize, @intCast(idx)) <= L.top) return idx;
    return @as(i32, @intCast(L.top)) + 1 + idx;
}

pub fn lua_gettop(L: *lua_State) i32 {
    return @as(i32, @intCast(L.top));
}

pub fn lua_settop(L: *lua_State, idx: i32) void {
    if (idx >= 0) {
        const n = @as(usize, @intCast(idx));
        if (n < L.top) {
            @memset(L.stack[n..L.top], TValue{ .nil = {} });
        } else if (n > L.top) {
            @memset(L.stack[L.top..n], TValue{ .nil = {} });
        }
        L.top = n;
    } else {
        lua_settop(L, @as(i32, @intCast(L.top)) + 1 + idx);
    }
}

pub fn lua_pushvalue(L: *lua_State, idx: i32) void {
    const src = idxPtr(L, idx) orelse return;
    L.stack[L.top] = src.*;
    L.top += 1;
}

pub fn lua_rotate(L: *lua_State, idx: i32, n: i32) void {
    _ = L;
    _ = idx;
    _ = n;
}

pub fn lua_copy(L: *lua_State, fromidx: i32, toidx: i32) void {
    const src = idxPtr(L, fromidx) orelse return;
    const dst = idxPtr(L, toidx) orelse return;
    dst.* = src.*;
}

pub fn lua_checkstack(L: *lua_State, n: i32) i32 {
    const needed = L.top + @as(usize, @intCast(n));
    if (needed <= L.stack.len) return 1;
    const new_cap = needed + LUA_MINSTACK;
    L.stack = L.allocator.realloc(L.stack, new_cap) catch return 0;
    L.stack_last = L.stack.len - 1;
    return 1;
}

pub fn lua_xmove(L: *lua_State, from: *lua_State, n: i32) void {
    const nn = @as(usize, @intCast(n));
    if (nn > from.top) return;
    const avail = L.stack.len - L.top;
    const to_copy = @min(nn, avail);
    @memcpy(L.stack[L.top..][0..to_copy], from.stack[from.top - to_copy .. from.top]);
    from.top -= to_copy;
    L.top += to_copy;
}

fn stackAt(L: *lua_State, idx: i32) TValue {
    const ptr = idxPtr(L, idx) orelse return TValue{ .nil = {} };
    return ptr.*;
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
        else => 0,
    };
}

pub fn lua_isstring(L: *lua_State, idx: i32) i32 {
    const v = stackAt(L, idx);
    return switch (v) {
        .string => 1,
        .number => 1,
        else => 0,
    };
}

pub fn lua_iscfunction(L: *lua_State, idx: i32) i32 {
    const v = stackAt(L, idx);
    return switch (v) {
        .function => 1,
        else => 0,
    };
}

pub fn lua_isinteger(L: *lua_State, idx: i32) i32 {
    _ = L;
    _ = idx;
    return 0;
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
    return stackAt(L, idx).typ();
}

pub fn lua_typename(tp: i32) []const u8 {
    return switch (tp) {
        LUA_TNONE => "none",
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
    if (isnum) |p| p.* = switch (v) { .number => 1, else => 0 };
    return switch (v) {
        .number => |n| n,
        else => null,
    };
}

pub fn lua_tointegerx(L: *lua_State, idx: i32, isnum: ?*i32) ?i64 {
    const v = stackAt(L, idx);
    if (isnum) |p| p.* = switch (v) { .number => 1, else => 0 };
    return switch (v) {
        .number => |n| @as(i64, @intFromFloat(n)),
        else => null,
    };
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

pub fn lua_tolstring(L: *lua_State, idx: i32, len: ?*usize) ?[]const u8 {
    const v = stackAt(L, idx);
    return switch (v) {
        .string => |s| {
            if (len) |p| p.* = s.?.len;
            return s.?.s;
        },
        else => null,
    };
}

pub fn lua_rawlen(L: *lua_State, idx: i32) usize {
    const v = stackAt(L, idx);
    return switch (v) {
        .string => |s| s.?.len,
        .table => |t| {
            if (t) |tp| return tp.array.items.len;
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
        .userdata => |u| if (u) |p| @as(*anyopaque, @ptrCast(p)) else null,
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

pub fn lua_arith(L: *lua_State, op: i32) void {
    const a = lua_tonumber(L, -2) orelse {
        lua_pushstring(L, "can't perform arithmetic");
        return;
    };
    const b = lua_tonumber(L, -1) orelse {
        lua_pushstring(L, "can't perform arithmetic");
        return;
    };
    const result = switch (op) {
        0 => a + b,
        1 => a - b,
        2 => a * b,
        3 => @mod(a, b),
        4 => std.math.pow(f64, a, b),
        5 => a / b,
        6 => @floor(a / b),
        else => {
            lua_pushstring(L, "unsupported operation");
            return;
        },
    };
    _ = lua_pop(L, 1);
    L.stack[L.top - 1] = TValue{ .number = result };
}

pub fn lua_rawequal(L: *lua_State, idx1: i32, idx2: i32) i32 {
    const a = stackAt(L, idx1);
    const b = stackAt(L, idx2);
    if (@as(std.meta.Tag(TValue), a) != @as(std.meta.Tag(TValue), b)) return 0;
    return switch (a) {
        .nil => 1,
        .boolean => |v| if (v == b.boolean) 1 else 0,
        .number => |v| if (v == b.number) 1 else 0,
        .string => |v| if (v == b.string) 1 else 0,
        .table => |v| if (v == b.table) 1 else 0,
        .function => |v| if (v == b.function) 1 else 0,
        .userdata => |v| if (v == b.userdata) 1 else 0,
        .thread => |v| if (v == b.thread) 1 else 0,
        .lightud => |v| if (v == b.lightud) 1 else 0,
        .upval => |v| if (v == b.upval) 1 else 0,
        .proto => |v| if (v == b.proto) 1 else 0,
    };
}

pub fn lua_compare(L: *lua_State, idx1: i32, idx2: i32, op: i32) i32 {
    const a = stackAt(L, idx1);
    const b = stackAt(L, idx2);
    return switch (op) {
        0 => lua_rawequal(L, idx1, idx2),
        1 => if (a == .number and b == .number)
            if (a.number < b.number) 1 else 0
        else
            0,
        2 => if (a == .number and b == .number)
            if (a.number <= b.number) 1 else 0
        else
            0,
        else => 0,
    };
}

pub fn lua_pushnil(L: *lua_State) void {
    L.stack[L.top] = TValue{ .nil = {} };
    L.top += 1;
}

pub fn lua_pushnumber(L: *lua_State, n: lua_Number) void {
    L.stack[L.top] = TValue{ .number = n };
    L.top += 1;
}

pub fn lua_pushinteger(L: *lua_State, n: lua_Integer) void {
    L.stack[L.top] = TValue{ .number = @as(f64, @floatFromInt(n)) };
    L.top += 1;
}

pub fn lua_pushlstring(L: *lua_State, s: []const u8, len: usize) ?[]const u8 {
    const str = L.allocator.create(lua_TString) catch return null;
    str.* = .{ .s = s[0..len], .len = len };
    L.stack[L.top] = TValue{ .string = str };
    L.top += 1;
    return str.s;
}

pub fn lua_pushstring(L: *lua_State, s: []const u8) ?[]const u8 {
    return lua_pushlstring(L, s, s.len);
}

pub fn lua_pushvfstring(L: *lua_State, fmt: []const u8, argp: ?*anyopaque) ?[]const u8 {
    _ = argp;
    return lua_pushstring(L, fmt);
}

pub fn lua_pushfstring(L: *lua_State, fmt: []const u8) ?[]const u8 {
    return lua_pushstring(L, fmt);
}

pub fn lua_pushcclosure(L: *lua_State, cfunc: lua_CFunction, n: i32) void {
    const cc = L.allocator.create(lua_CClosure) catch return;
    cc.* = .{ .f = cfunc, .nups = @intCast(n) };
    const cl = L.allocator.create(lua_Closure) catch return;
    cl.* = lua_Closure{ .c = cc };
    L.stack[L.top] = TValue{ .function = cl };
    L.top += 1;
}

pub fn lua_pushboolean(L: *lua_State, b: i32) void {
    L.stack[L.top] = TValue{ .boolean = b != 0 };
    L.top += 1;
}

pub fn lua_pushlightuserdata(L: *lua_State, p: ?*anyopaque) void {
    L.stack[L.top] = TValue{ .lightud = p };
    L.top += 1;
}

pub fn lua_pushthread(L: *lua_State) i32 {
    L.stack[L.top] = TValue{ .thread = L };
    L.top += 1;
    return 1;
}

pub fn lua_pop(L: *lua_State, n: i32) void {
    if (n > 0) {
        const nn = @as(usize, @intCast(n));
        if (nn <= L.top) {
            L.top -= nn;
        }
    }
}

pub fn lua_getglobal(L: *lua_State, name: []const u8) i32 {
    _ = name;
    lua_pushnil(L);
    return 1;
}

pub fn lua_gettable(L: *lua_State, idx: i32) i32 {
    _ = idx;
    lua_pushnil(L);
    return 1;
}

pub fn lua_getfield(L: *lua_State, idx: i32, k: []const u8) i32 {
    _ = idx;
    _ = k;
    lua_pushnil(L);
    return 1;
}

pub fn lua_geti(L: *lua_State, idx: i32, n: lua_Integer) i32 {
    _ = idx;
    _ = n;
    lua_pushnil(L);
    return 1;
}

pub fn lua_rawget(L: *lua_State, idx: i32) i32 {
    _ = idx;
    lua_pushnil(L);
    return 1;
}

pub fn lua_rawgeti(L: *lua_State, idx: i32, n: lua_Integer) i32 {
    _ = idx;
    _ = n;
    lua_pushnil(L);
    return 1;
}

pub fn lua_rawgetp(L: *lua_State, idx: i32, p: ?*const anyopaque) i32 {
    _ = idx;
    _ = p;
    lua_pushnil(L);
    return 1;
}

pub fn lua_createtable(L: *lua_State, narr: i32, nrec: i32) void {
    _ = narr;
    _ = nrec;
    const t = L.allocator.create(lua_Table) catch return;
    t.* = .{
        .flags = 0,
        .ls = 0,
        .array = std.ArrayList(?TValue).empty,
        .i_size = 0,
        .nsize = 0,
    };
    L.stack[L.top] = TValue{ .table = t };
    L.top += 1;
}

pub fn lua_newuserdatauv(L: *lua_State, sz: usize, nuvalue: i32) ?*anyopaque {
    _ = nuvalue;
    const u = L.allocator.create(lua_Udata) catch return null;
    u.* = .{ .len = sz, .metatable = null };
    L.stack[L.top] = TValue{ .userdata = u };
    L.top += 1;
    return @as(*anyopaque, @ptrCast(u));
}

pub fn lua_getmetatable(L: *lua_State, objindex: i32) i32 {
    _ = L;
    _ = objindex;
    return 0;
}

pub fn lua_getiuservalue(L: *lua_State, idx: i32, n: i32) i32 {
    _ = idx;
    _ = n;
    lua_pushnil(L);
    return 1;
}

pub fn lua_setglobal(L: *lua_State, name: []const u8) void {
    _ = L;
    _ = name;
}

pub fn lua_settable(L: *lua_State, idx: i32) void {
    _ = L;
    _ = idx;
}

pub fn lua_setfield(L: *lua_State, idx: i32, k: []const u8) void {
    _ = L;
    _ = idx;
    _ = k;
}

pub fn lua_seti(L: *lua_State, idx: i32, n: lua_Integer) void {
    _ = L;
    _ = idx;
    _ = n;
}

pub fn lua_rawset(L: *lua_State, idx: i32) void {
    _ = L;
    _ = idx;
}

pub fn lua_rawseti(L: *lua_State, idx: i32, n: lua_Integer) void {
    _ = L;
    _ = idx;
    _ = n;
}

pub fn lua_rawsetp(L: *lua_State, idx: i32, p: ?*anyopaque) void {
    _ = L;
    _ = idx;
    _ = p;
}

pub fn lua_setmetatable(L: *lua_State, objindex: i32) i32 {
    _ = L;
    _ = objindex;
    return 1;
}

pub fn lua_setiuservalue(L: *lua_State, idx: i32, n: i32) i32 {
    _ = L;
    _ = idx;
    _ = n;
    return 1;
}

pub fn lua_callk(L: *lua_State, nargs: i32, nresults: i32, ctx: lua_KContext, k: ?lua_KFunction) void {
    _ = L;
    _ = nargs;
    _ = nresults;
    _ = ctx;
    _ = k;
}

pub fn lua_pcallk(L: *lua_State, nargs: i32, nresults: i32, errfunc: i32, ctx: lua_KContext, k: ?lua_KFunction) i32 {
    _ = L;
    _ = nargs;
    _ = nresults;
    _ = errfunc;
    _ = ctx;
    _ = k;
    return LUA_OK;
}

pub fn lua_load(L: *lua_State, reader: lua_Reader, dt: ?*anyopaque, chunkname: []const u8, mode: []const u8) i32 {
    _ = L;
    _ = reader;
    _ = dt;
    _ = chunkname;
    _ = mode;
    return LUA_OK;
}

pub fn lua_dump(L: *lua_State, writer: lua_Writer, data: ?*anyopaque, strip: i32) i32 {
    _ = L;
    _ = writer;
    _ = data;
    _ = strip;
    return LUA_OK;
}

pub fn lua_yieldk(L: *lua_State, nresults: i32, ctx: lua_KContext, k: ?lua_KFunction) i32 {
    _ = L;
    _ = nresults;
    _ = ctx;
    _ = k;
    return LUA_YIELD;
}

pub fn lua_resume(L: *lua_State, from: ?*lua_State, narg: i32, nresults: ?*i32) i32 {
    _ = L;
    _ = from;
    _ = narg;
    _ = nresults;
    return LUA_OK;
}

pub fn lua_status(L: *lua_State) i32 {
    _ = L;
    return LUA_OK;
}

pub fn lua_isyieldable(L: *lua_State) i32 {
    _ = L;
    return 0;
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

pub fn lua_gc(L: *lua_State, what: i32, arg: i32) i32 {
    _ = L;
    _ = what;
    _ = arg;
    return 0;
}

pub fn lua_error(L: *lua_State) i32 {
    const msg = lua_tolstring(L, 1, null);
    if (msg) |m| {
        std.debug.print("error: {s}\n", .{m});
    }
    return LUA_ERRRUN;
}

pub fn lua_next(L: *lua_State, idx: i32) i32 {
    _ = L;
    _ = idx;
    return 0;
}

pub fn lua_concat(L: *lua_State, n: i32) void {
    _ = L;
    _ = n;
}

pub fn lua_len(L: *lua_State, idx: i32) void {
    _ = L;
    _ = idx;
}

pub fn lua_stringtonumber(L: *lua_State, s: []const u8) usize {
    _ = L;
    _ = s;
    return 0;
}

pub fn lua_getallocf(L: *lua_State, ud: ?*?*anyopaque) lua_Alloc {
    _ = L;
    _ = ud;
    return undefined;
}

pub fn lua_setallocf(L: *lua_State, f: lua_Alloc, ud: ?*anyopaque) void {
    _ = L;
    _ = f;
    _ = ud;
}

pub fn lua_toclose(L: *lua_State, idx: i32) void {
    _ = L;
    _ = idx;
}

pub fn lua_closeslot(L: *lua_State, idx: i32) void {
    _ = L;
    _ = idx;
}

pub fn luaL_newstate(L: *lua_State, gpa: std.mem.Allocator) !void {
    const stack = try gpa.alloc(TValue, LUA_MINSTACK + 1);
    L.* = .{
        .tt = 0,
        .marked = 0,
        .gch = 0,
        .allowhook = 0,
        .status = 0,
        .top = 0,
        .l_G = null,
        .ci = null,
        .stack = stack,
        .stack_last = stack.len - 1,
        .openupval = null,
        .tbclist = 0,
        .gclist = null,
        .twups = null,
        .errorJmp = null,
        .base_ci = .{ .func = null, .top = 0, .nresults = 0 },
        .hook = null,
        .errfunc = 0,
        .nCcalls = 0,
        .oldpc = 0,
        .nci = 0,
        .basehookcount = 0,
        .hookcount = 0,
        .hookmask = 0,
        .transferinfo = .{ .ftransfer = 0, .ntransfer = 0 },
        .allocator = gpa,
    };
}

pub fn createargtable(L: *lua_State, args: anytype) !void {
    _ = L;
    _ = args;
}

pub fn luaL_dostring(L: *lua_State, s: []const u8, name: []const u8) !i32 {
    _ = L;
    _ = s;
    _ = name;
    return LUA_OK;
}

pub const luaL_openlibs = @import("lauxlib.zig").luaL_openlibs;

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
    L.allocator.free(L.stack);
}
