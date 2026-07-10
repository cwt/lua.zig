const std = @import("std");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");
const lvm = @import("lvm.zig");
const ltable = @import("ltable.zig");
const lstring = @import("lstring.zig");
const lundump = @import("lundump.zig");
const ltm = @import("ltm.zig");

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
pub const LUA_SIGNATURE = "\x1bLua";

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
    hash: u32,
};

pub const lua_Udata = struct {
    len: usize,
    metatable: ?*lua_Table = null,
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

    pub fn typ(self: TValue) i32 {
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
        return switch (self) {
            .nil => false,
            .boolean => |b| b,
            else => true,
        };
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
};

pub const lua_CClosure = struct {
    f: lua_CFunction,
    upvals: []TValue,
};

pub const lua_LClosure = struct {
    p: *lua_Proto,
    upvals: []?*UpVal,
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
    maxStackSize: u8,
    code: []lvm.Instruction,
    k: []TValue,
    p: []*lua_Proto,
    upvalues: []Upvaldesc,
    lineinfo: []i8,
    abslineinfo: []AbsLineInfo,
    locvars: []LocVar,
    is_sub: bool = false,
};

pub fn createProto(allocator: std.mem.Allocator) !*lua_Proto {
    const f = try allocator.create(lua_Proto);
    f.* = .{
        .source = null,
        .lineDefined = 0,
        .lastLineDefined = 0,
        .numParams = 0,
        .isVarArg = false,
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
    allocator.free(f.code);
    allocator.free(f.k);
    for (f.p) |sub| {
        destroyProto(allocator, sub);
    }
    allocator.free(f.p);
    allocator.free(f.upvalues);
    allocator.free(f.lineinfo);
    allocator.free(f.abslineinfo);
    allocator.free(f.locvars);
    allocator.destroy(f);
}

pub fn findupval(L: *lua_State, idx: usize) !*UpVal {
    var prev: ?*UpVal = null;
    var curr = L.openupval;
    while (curr) |uv| {
        if (uv.index) |uv_idx| {
            if (uv_idx == idx) {
                return uv;
            }
            if (uv_idx < idx) {
                break;
            }
        }
        prev = uv;
        curr = uv.next;
    }
    const uv = try L.allocator.create(UpVal);
    uv.* = .{
        .value = .{ .nil = {} },
        .index = idx,
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

pub fn closeupvals(L: *lua_State, limit: usize) void {
    var curr = L.openupval;
    while (curr) |uv| {
        if (uv.index) |idx| {
            if (idx >= limit) {
                uv.value = L.stack[idx];
                uv.index = null;
                L.openupval = uv.next;
                curr = L.openupval;
                continue;
            }
        }
        break;
    }
}

pub fn poscall(L: *lua_State, ci: *CallInfo, first_result_idx: usize, n: usize) void {
    closeupvals(L, ci.base);
    const func_idx = ci.func;
    const nresults = ci.nresults;
    if (nresults >= 0) {
        const copy_count = @min(@as(usize, @intCast(nresults)), n);
        var i: usize = 0;
        while (i < copy_count) : (i += 1) {
            L.stack[func_idx + i] = L.stack[first_result_idx + i];
        }
        while (i < @as(usize, @intCast(nresults))) : (i += 1) {
            L.stack[func_idx + i] = .{ .nil = {} };
        }
        L.top = func_idx + @as(usize, @intCast(nresults));
    } else {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            L.stack[func_idx + i] = L.stack[first_result_idx + i];
        }
        L.top = func_idx + n;
    }
}

pub fn precall(L: *lua_State, func_idx: usize, nresults: i32) !?*CallInfo {
    const val = L.stack[func_idx];
    if (val != .function) {
        return error.NotAFunction;
    }
    const cl = val.function.?;
    switch (cl.*) {
        .c => |cc| {
            const old_ci = L.ci;
            var new_ci = CallInfo{
                .func = func_idx,
                .base = func_idx + 1,
                .top = L.top + 20,
                .nresults = nresults,
                .savedpc = 0,
                .previous = old_ci,
                .next = null,
            };
            if (old_ci) |prev| {
                prev.next = &new_ci;
            }
            L.ci = &new_ci;
            defer {
                L.ci = old_ci;
                if (old_ci) |prev| {
                    prev.next = null;
                }
            }
            const n = cc.f(L);
            if (n < 0) return error.RuntimeError;
            const num_returned = @as(usize, @intCast(n));
            const first_result = L.top - num_returned;
            poscall(L, &new_ci, first_result, num_returned);
            return null;
        },
        .lua => |lc| {
            const proto = lc.p;
            const num_params = proto.numParams;
            const base_idx = func_idx + 1;
            const frame_top = base_idx + proto.maxStackSize;
            if (frame_top >= L.stack.len) {
                const old_len = L.stack.len;
                const new_len = @max(L.stack.len * 2, frame_top + 10);
                L.stack = try L.allocator.realloc(L.stack, new_len);
                @memset(L.stack[old_len..], .{ .nil = {} });
                L.stack_last = L.stack.len - 1;
            }
            const num_args_passed = L.top - base_idx;
            if (num_args_passed < num_params) {
                var i = num_args_passed;
                while (i < num_params) : (i += 1) {
                    L.stack[base_idx + i] = .{ .nil = {} };
                }
                L.top = base_idx + num_params;
            }
            const new_ci = try L.allocator.create(CallInfo);
            new_ci.* = .{
                .func = func_idx,
                .base = base_idx,
                .top = frame_top,
                .nresults = nresults,
                .savedpc = 0,
                .previous = L.ci,
                .next = null,
            };
            if (L.ci) |prev| {
                prev.next = new_ci;
            }
            L.ci = new_ci;
            return new_ci;
        },
    }
}

pub const UpVal = struct {
    value: TValue,
    index: ?usize,
    next: ?*UpVal,
    refcount: usize = 0,
};

pub const CallInfo = struct {
    func: usize,
    base: usize,
    top: usize,
    nresults: i32,
    savedpc: usize,
    previous: ?*CallInfo,
    next: ?*CallInfo,
};

pub const VMGCObject = struct {
    next: ?*VMGCObject,
    val: ValUnion,

    pub const ValUnion = union(enum) {
        table: *lua_Table,
        closure: *lua_Closure,
        upval: *UpVal,
        proto: *lua_Proto,
        userdata: *lua_Udata,
    };
};

pub const global_State = struct {
    allocator: std.mem.Allocator,
    strt: std.array_hash_map.String(*lua_TString),
    seed: usize,
    registry: TValue,
    allgc: ?*VMGCObject = null,
    mt: [9]?*lua_Table = [_]?*lua_Table{null} ** 9,
    tmname: [25]?*lua_TString = [_]?*lua_TString{null} ** 25,
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
        else => @compileError("Unsupported type for GC registration"),
    };
    gc.* = .{
        .next = g.allgc,
        .val = union_val,
    };
    g.allgc = gc;
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
        // Positive indices are frame-relative: 1 = ci.base, 2 = ci.base+1, etc.
        // If there is no active call frame, treat as 1-based absolute index.
        const base: usize = if (L.ci) |ci| ci.base else 0;
        const u = base + @as(usize, @intCast(idx - 1));
        if (u < L.top) return &L.stack[u];
    } else if (idx == LUA_REGISTRYINDEX) {
        // Registry pseudo-index: not yet implemented (returns null).
        return null;
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
    if (op < 0 or op > 13) return;
    const is_unary = (op == LUA_OPUNM or op == LUA_OPBNOT);
    if (is_unary) {
        if (L.top < 1) return;
        const p1 = L.stack[L.top - 1];
        if (p1 == .number) {
            const result = switch (op) {
                LUA_OPUNM => -p1.number,
                LUA_OPBNOT => @as(f64, @floatFromInt(~@as(i64, @intFromFloat(p1.number)))),
                else => unreachable,
            };
            L.stack[L.top - 1] = TValue{ .number = result };
        } else {
            const event: ltm.TMS = switch (op) {
                LUA_OPUNM => .UNM,
                LUA_OPBNOT => .BNOT,
                else => unreachable,
            };
            ltm.luaT_trybinTM(L, p1, p1, L.top - 1, event) catch {};
        }
    } else {
        if (L.top < 2) return;
        const p1 = L.stack[L.top - 2];
        const p2 = L.stack[L.top - 1];
        if (p1 == .number and p2 == .number) {
            const result = switch (op) {
                LUA_OPADD => p1.number + p2.number,
                LUA_OPSUB => p1.number - p2.number,
                LUA_OPMUL => p1.number * p2.number,
                LUA_OPMOD => p1.number - @floor(p1.number / p2.number) * p2.number,
                LUA_OPPOW => std.math.pow(f64, p1.number, p2.number),
                LUA_OPDIV => p1.number / p2.number,
                LUA_OPIDIV => @floor(p1.number / p2.number),
                LUA_OPBAND => @as(f64, @floatFromInt(@as(i64, @intFromFloat(p1.number)) & @as(i64, @intFromFloat(p2.number)))),
                LUA_OPBOR => @as(f64, @floatFromInt(@as(i64, @intFromFloat(p1.number)) | @as(i64, @intFromFloat(p2.number)))),
                LUA_OPBXOR => @as(f64, @floatFromInt(@as(i64, @intFromFloat(p1.number)) ^ @as(i64, @intFromFloat(p2.number)))),
                LUA_OPSHL => @as(f64, @floatFromInt(@as(i64, @intFromFloat(p1.number)) << @intCast(@as(i64, @intFromFloat(p2.number))))),
                LUA_OPSHR => @as(f64, @floatFromInt(@as(i64, @intFromFloat(p1.number)) >> @intCast(@as(i64, @intFromFloat(p2.number))))),
                else => unreachable,
            };
            L.top -= 1;
            L.stack[L.top - 1] = TValue{ .number = result };
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
            ltm.luaT_trybinTM(L, p1, p2, L.top - 2, event) catch {};
            L.top -= 1;
        }
    }
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
    const res = switch (op) {
        LUA_OPEQ => ltm.luaT_equalobj(L, a, b) catch false,
        LUA_OPLT => ltm.luaT_lt(L, a, b) catch false,
        LUA_OPLE => ltm.luaT_le(L, a, b) catch false,
        else => false,
    };
    return if (res) 1 else 0;
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
    const g = G(L);
    const ts = lstring.luaS_new(g.allocator, &g.strt, g.seed, s[0..len]) catch return null;
    L.stack[L.top] = TValue{ .string = ts };
    L.top += 1;
    return ts.s;
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
pub fn lua_getupvalue(L: *lua_State, _: i32, n: i32) ?[]const u8 {
    if (L.ci) |ci| {
        const func_val = L.stack[ci.func];
        if (func_val == .function) {
            if (func_val.function) |cl| {
                if (cl.* == .c) {
                    const upn: usize = @intCast(n - 1);
                    if (upn < cl.c.upvals.len) {
                        L.stack[L.top] = cl.c.upvals[upn];
                        L.top += 1;
                        return ""; // unnamed upvalue
                    }
                }
            }
        }
    }
    return null;
}

/// Set upvalue `n` (1-based) of the C closure at the current call frame to
/// the value on top of the stack (pops it).  Returns the upvalue name or null
/// when `n` is out of range.
pub fn lua_setupvalue(L: *lua_State, _: i32, n: i32) ?[]const u8 {
    if (L.top == 0) return null;
    if (L.ci) |ci| {
        const func_val = L.stack[ci.func];
        if (func_val == .function) {
            if (func_val.function) |cl| {
                if (cl.* == .c) {
                    const upn: usize = @intCast(n - 1);
                    if (upn < cl.c.upvals.len) {
                        cl.c.upvals[upn] = L.stack[L.top - 1];
                        L.top -= 1;
                        return "";
                    }
                }
            }
        }
    }
    return null;
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

fn getTable(L: *lua_State, idx: i32) ?*lua_Table {
    const v = stackAt(L, idx);
    if (v == .table) return v.table;
    return null;
}

pub fn lua_gettable(L: *lua_State, idx: i32) i32 {
    const obj = stackAt(L, idx);
    if (obj == .nil) {
        lua_pushnil(L);
        return 1;
    }
    const key = L.stack[L.top - 1];
    const res = L.top - 1;
    // Overwrite the key slot with the result (mirrors C API contract).
    ltm.luaV_gettable(L, obj, key, res) catch {
        L.stack[res] = .{ .nil = {} };
    };
    return 1;
}

pub fn lua_getfield(L: *lua_State, idx: i32, k: []const u8) i32 {
    const obj = stackAt(L, idx);
    if (obj == .nil) {
        lua_pushnil(L);
        return 1;
    }
    const g = G(L);
    const ts = lstring.luaS_new(g.allocator, &g.strt, g.seed, k) catch {
        lua_pushnil(L);
        return 1;
    };
    const key = TValue{ .string = ts };
    const res = L.top;
    L.stack[L.top] = .{ .nil = {} };
    L.top += 1;
    ltm.luaV_gettable(L, obj, key, res) catch {
        L.stack[res] = .{ .nil = {} };
    };
    return 1;
}

pub fn lua_geti(L: *lua_State, idx: i32, n: lua_Integer) i32 {
    const obj = stackAt(L, idx);
    if (obj == .nil) {
        lua_pushnil(L);
        return 1;
    }
    const key = TValue{ .number = @floatFromInt(n) };
    const res = L.top;
    L.stack[L.top] = .{ .nil = {} };
    L.top += 1;
    ltm.luaV_gettable(L, obj, key, res) catch {
        L.stack[res] = .{ .nil = {} };
    };
    return 1;
}

/// Raw (no metamethod) get — key is on top of stack.
pub fn lua_rawget(L: *lua_State, idx: i32) i32 {
    const t = getTable(L, idx) orelse {
        lua_pushnil(L);
        return 1;
    };
    const key = L.stack[L.top - 1];
    const val = ltable.get(t, key);
    L.top -= 1;
    L.stack[L.top] = val;
    L.top += 1;
    return 1;
}

/// Raw (no metamethod) integer-key get.
pub fn lua_rawgeti(L: *lua_State, idx: i32, n: lua_Integer) i32 {
    const t = getTable(L, idx) orelse {
        lua_pushnil(L);
        return 1;
    };
    const val = ltable.getInt(t, n);
    L.stack[L.top] = val;
    L.top += 1;
    return 1;
}

pub fn lua_rawgetp(L: *lua_State, idx: i32, p: ?*const anyopaque) i32 {
    const t = getTable(L, idx) orelse {
        lua_pushnil(L);
        return 1;
    };
    const val = ltable.get(t, TValue{ .lightud = @constCast(p) });
    L.stack[L.top] = val;
    L.top += 1;
    return 1;
}

pub fn lua_createtable(L: *lua_State, narr: i32, nrec: i32) void {
    const t = ltable.createTable(L.allocator, @intCast(narr), @intCast(nrec)) catch return;
    registerGC(L, t) catch return;
    L.stack[L.top] = TValue{ .table = t };
    L.top += 1;
}

pub fn lua_newuserdatauv(L: *lua_State, sz: usize, nuvalue: i32) ?*anyopaque {
    _ = nuvalue;
    const u = L.allocator.create(lua_Udata) catch return null;
    u.* = .{ .len = sz, .metatable = null };
    registerGC(L, u) catch return null;
    L.stack[L.top] = TValue{ .userdata = u };
    L.top += 1;
    return @as(*anyopaque, @ptrCast(u));
}

pub fn lua_getmetatable(L: *lua_State, objindex: i32) i32 {
    const val = idxPtr(L, objindex) orelse return 0;
    const mt: ?*lua_Table = switch (val.*) {
        .table => |t| t.metatable,
        .userdata => |u| u.metatable,
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
    const obj = stackAt(L, idx);
    if (obj == .nil) {
        L.top -= 2;
        return;
    }
    const key = L.stack[L.top - 2];
    const val = L.stack[L.top - 1];
    L.top -= 2;
    ltm.luaV_settable(L, obj, key, val) catch {};
}

pub fn lua_setfield(L: *lua_State, idx: i32, k: []const u8) void {
    const obj = stackAt(L, idx);
    if (obj == .nil) {
        L.top -= 1;
        return;
    }
    const g = G(L);
    const ts = lstring.luaS_new(g.allocator, &g.strt, g.seed, k) catch {
        L.top -= 1;
        return;
    };
    const val = L.stack[L.top - 1];
    L.top -= 1;
    ltm.luaV_settable(L, obj, TValue{ .string = ts }, val) catch {};
}

pub fn lua_seti(L: *lua_State, idx: i32, n: lua_Integer) void {
    const obj = stackAt(L, idx);
    if (obj == .nil) {
        L.top -= 1;
        return;
    }
    const val = L.stack[L.top - 1];
    L.top -= 1;
    ltm.luaV_settable(L, obj, TValue{ .number = @floatFromInt(n) }, val) catch {};
}

/// Raw (no metamethod) set — key and value are on top of stack.
pub fn lua_rawset(L: *lua_State, idx: i32) void {
    const t = getTable(L, idx) orelse {
        L.top -= 2;
        return;
    };
    const key = L.stack[L.top - 2];
    const val = L.stack[L.top - 1];
    ltable.set(t, key, val) catch {};
    L.top -= 2;
}

/// Raw (no metamethod) integer-key set.
pub fn lua_rawseti(L: *lua_State, idx: i32, n: lua_Integer) void {
    const t = getTable(L, idx) orelse {
        L.top -= 1;
        return;
    };
    const val = L.stack[L.top - 1];
    ltable.setInt(t, n, val) catch {};
    L.top -= 1;
}

pub fn lua_rawsetp(L: *lua_State, idx: i32, p: ?*anyopaque) void {
    const t = getTable(L, idx) orelse {
        L.top -= 1;
        return;
    };
    const val = L.stack[L.top - 1];
    ltable.set(t, TValue{ .lightud = @constCast(p) }, val) catch {};
    L.top -= 1;
}

pub fn lua_setmetatable(L: *lua_State, objindex: i32) i32 {
    if (L.top == 0) return 0;
    const mt_val = L.stack[L.top - 1];
    const mt: ?*lua_Table = switch (mt_val) {
        .nil => null,
        .table => |t| t,
        else => return 0,
    };
    L.top -= 1;

    const val = idxPtr(L, objindex) orelse return 0;
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
    _ = L;
    _ = idx;
    _ = n;
    return 1;
}

pub fn lua_callk(L: *lua_State, nargs: i32, nresults: i32, ctx: lua_KContext, k: ?lua_KFunction) void {
    _ = ctx;
    _ = k;
    const func_idx = L.top - @as(usize, @intCast(nargs)) - 1;
    if (precall(L, func_idx, nresults) catch |err| {
        std.debug.print("Runtime error in precall: {any}\n", .{err});
        return;
    }) |new_ci| {
        lvm.run(L, new_ci) catch |err| {
            std.debug.print("Runtime error in VM: {any}\n", .{err});
        };
    }
}

pub fn lua_pcallk(L: *lua_State, nargs: i32, nresults: i32, errfunc: i32, ctx: lua_KContext, k: ?lua_KFunction) i32 {
    _ = errfunc;
    _ = ctx;
    _ = k;
    const old_top = L.top;
    const old_ci = L.ci;

    const func_idx = L.top - @as(usize, @intCast(nargs)) - 1;
    const new_ci = precall(L, func_idx, nresults) catch |err| {
        std.debug.print("Runtime error in precall: {any}\n", .{err});
        L.top = old_top;
        L.ci = old_ci;
        return LUA_ERRRUN;
    };

    if (new_ci) |ci| {
        lvm.run(L, ci) catch |err| {
            std.debug.print("Runtime error in VM: {any}\n", .{err});
            // Restore CallInfo chain and stack
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
            L.top = old_top;
            return LUA_ERRRUN;
        };
    }

    return LUA_OK;
}

pub fn lua_load(L: *lua_State, reader: lua_Reader, dt: ?*anyopaque, chunkname: []const u8, mode: []const u8) i32 {
    _ = mode;
    var size: usize = 0;
    const first_slice = reader(L, dt, &size);
    if (first_slice == null or first_slice.?.len == 0 or size == 0) {
        return LUA_ERRSYNTAX;
    }
    const c = first_slice.?[0];
    if (c == '\x1b') {
        const proto = lundump.loadBinaryChunk(L, reader, dt, first_slice.?, chunkname) catch |err| {
            std.debug.print("Failed to load binary chunk: {any}\n", .{err});
            return LUA_ERRSYNTAX;
        };
        const lc = L.allocator.create(lua_LClosure) catch {
            destroyProto(L.allocator, proto);
            return LUA_ERRMEM;
        };
        const upvals = L.allocator.alloc(?*UpVal, proto.upvalues.len) catch {
            L.allocator.destroy(lc);
            destroyProto(L.allocator, proto);
            return LUA_ERRMEM;
        };
        @memset(upvals, null);
        lc.* = .{
            .p = proto,
            .upvals = upvals,
        };

        // Initialize first upvalue (_ENV) if proto expects it
        if (proto.upvalues.len > 0) {
            const registry = G(L).registry.table.?;
            const globals = ltable.getInt(registry, 2); // RIDX_GLOBALS is 2
            const env_uv = L.allocator.create(UpVal) catch {
                L.allocator.free(upvals);
                L.allocator.destroy(lc);
                destroyProto(L.allocator, proto);
                return LUA_ERRMEM;
            };
            env_uv.* = .{
                .value = globals,
                .index = null,
                .next = null,
                .refcount = 1,
            };
            registerGC(L, env_uv) catch {
                L.allocator.free(upvals);
                L.allocator.destroy(lc);
                destroyProto(L.allocator, proto);
                return LUA_ERRMEM;
            };
            upvals[0] = env_uv;
        }

        const cl = L.allocator.create(lua_Closure) catch {
            if (upvals.len > 0 and upvals[0] != null) L.allocator.destroy(upvals[0].?);
            L.allocator.free(upvals);
            L.allocator.destroy(lc);
            destroyProto(L.allocator, proto);
            return LUA_ERRMEM;
        };
        cl.* = .{ .lua = lc };
        registerGC(L, cl) catch {
            L.allocator.free(upvals);
            L.allocator.destroy(lc);
            destroyProto(L.allocator, proto);
            return LUA_ERRMEM;
        };
        L.stack[L.top] = TValue{ .function = cl };
        L.top += 1;
        return LUA_OK;
    } else {
        return LUA_ERRSYNTAX;
    }
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
    const t = getTable(L, idx) orelse return 0;
    const key = stackAt(L, -1);
    const r = ltable.next(t, key);
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
    const g = try gpa.create(global_State);
    g.* = .{
        .allocator = gpa,
        .strt = std.array_hash_map.String(*lua_TString).empty,
        .seed = @intFromPtr(L) ^ 0x9e3779b97f4a7c15,
        .registry = TValue{ .nil = {} },
        .mt = [_]?*lua_Table{null} ** 9,
        .tmname = [_]?*lua_TString{null} ** 25,
    };
    const stack = try gpa.alloc(TValue, LUA_MINSTACK + 1);
    L.* = .{
        .tt = 0,
        .marked = 0,
        .gch = 0,
        .allowhook = 0,
        .status = 0,
        .top = 0,
        .l_G = g,
        .ci = null,
        .stack = stack,
        .stack_last = stack.len - 1,
        .openupval = null,
        .tbclist = 0,
        .gclist = null,
        .twups = null,
        .errorJmp = null,
        .base_ci = .{ .func = 0, .base = 0, .top = LUA_MINSTACK, .nresults = 0, .savedpc = 0, .previous = null, .next = null },
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
    L.ci = &L.base_ci;

    // Initialize registry and globals tables
    const registry_tab = try ltable.createTable(gpa, 3, 0);
    try registerGC(L, registry_tab);
    g.registry = TValue{ .table = registry_tab };
    try ltable.setInt(registry_tab, 1, TValue{ .thread = L });
    const globals_tab = try ltable.createTable(gpa, 0, 0);
    try registerGC(L, globals_tab);
    try ltable.setInt(registry_tab, 2, TValue{ .table = globals_tab });
    try ltm.luaT_init(L);
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
    if (L.l_G) |g| {
        L.openupval = null;

        // Free CallInfo structs
        var curr_ci = L.ci;
        while (curr_ci) |ci| {
            const prev = ci.previous;
            if (ci != &L.base_ci) {
                L.allocator.destroy(ci);
            }
            curr_ci = prev;
        }
        L.ci = null;

        // Free all GC objects registered in allgc
        var curr_gc = g.allgc;
        while (curr_gc) |gc| {
            const next_gc = gc.next;
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
                    L.allocator.free(f.code);
                    L.allocator.free(f.k);
                    L.allocator.free(f.p);
                    L.allocator.free(f.upvalues);
                    L.allocator.free(f.lineinfo);
                    L.allocator.free(f.abslineinfo);
                    L.allocator.free(f.locvars);
                    L.allocator.destroy(f);
                },
                .userdata => |u| {
                    L.allocator.destroy(u);
                },
            }
            L.allocator.destroy(gc);
            curr_gc = next_gc;
        }
        g.allgc = null;

        // Free string table entries
        var it = g.strt.iterator();
        while (it.next()) |entry| {
            g.allocator.destroy(entry.value_ptr.*);
        }
        g.strt.deinit(g.allocator);
        L.allocator.destroy(g);
    }
    L.allocator.free(L.stack);
}
