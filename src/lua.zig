const std = @import("std");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");
pub const lvm = @import("lvm.zig");
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
pub const LUA_TUPVAL: i32 = llimits.LUA_TUPVAL;
pub const LUA_REGISTRYINDEX: i32 = llimits.LUA_REGISTRYINDEX;
pub const LUA_OK: i32 = llimits.LUA_OK;
pub const LUA_YIELD: i32 = llimits.LUA_YIELD;
pub const LUA_ERRRUN: i32 = llimits.LUA_ERRRUN;
pub const LUA_ERRMEM: i32 = llimits.LUA_ERRMEM;
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


// Forward declarations
pub const lua_CFunction = *const fn (*lua_State) anyerror!i32;
pub const lua_KFunction = *const fn (*lua_State, i32, lua_KContext) anyerror!i32;

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
    i_ci: ?*CallInfo,
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
    marked: bool = false,
};

pub const lua_Udata = struct {
    metatable: ?*lua_Table = null,
    // Payload buffer. `lua_touserdata` returns `data.ptr`; `lua_topointer`
    // (identity) returns the header address. The buffer is freed alongside the
    // object in `freeGCObject`.
    data: []u8,
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
            .upval => LUA_TUPVAL,
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
            if (lua_checkstack(L, 20) == 0) return error.StackOverflow;
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
            const n = try cc.f(L);
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

pub const GCColor = enum(u2) {
    white = 0,
    gray = 1,
    black = 2,
};

pub const VMGCObject = struct {
    next: ?*VMGCObject,
    val: ValUnion,
    color: GCColor = .white,

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
    io_backend: ?std.Io.Threaded = null,
    io: std.Io,
    prng: std.Random.Xoshiro256,
    mainthread: ?*lua_State = null,
    thread_list: ?*lua_State = null,
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
    if (idx > 0) return idx;
    const base: usize = if (L.ci) |ci| ci.base else 0;
    const abs_idx = toAbsoluteIndex(L, idx);
    return @as(i32, @intCast(abs_idx - base)) + 1;
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
    while (i < j) : ({ i += 1; j -= 1; }) { const t = L.stack[i]; L.stack[i] = L.stack[j]; L.stack[j] = t; }
    // Reverse first rot elements
    i = abs_idx; j = abs_idx + rot - 1;
    while (i < j) : ({ i += 1; j -= 1; }) { const t = L.stack[i]; L.stack[i] = L.stack[j]; L.stack[j] = t; }
    // Reverse remaining elements
    i = abs_idx + rot; j = top_idx;
    while (i < j) : ({ i += 1; j -= 1; }) { const t = L.stack[i]; L.stack[i] = L.stack[j]; L.stack[j] = t; }
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

pub inline fn lua_isnoneornil(L: *lua_State, idx: i32) bool {
    return lua_type(L, idx) <= 0;
}

pub fn lua_isnone(L: *lua_State, idx: i32) i32 {
    return if (lua_type(L, idx) == LUA_TNONE) 1 else 0;
}

pub fn lua_yield(L: *lua_State, nresults: i32) i32 {
    return lua_yieldk(L, nresults, 0, null);
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
    const v = stackAt(L, idx);
    return switch (v) {
        .number => |n| if (@trunc(n) == n) 1 else 0,
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
    const min_f64 = @as(f64, -9223372036854775808.0);
    const max_exclusive_f64 = @as(f64, 9223372036854775808.0);
    if (isnum) |p| p.* = switch (v) {
        .number => |n| if (@trunc(n) == n and n >= min_f64 and n < max_exclusive_f64) 1 else 0,
        else => 0,
    };
    return switch (v) {
        .number => |n| {
            if (@trunc(n) == n and n >= min_f64 and n < max_exclusive_f64) {
                return @as(i64, @intFromFloat(n));
            }
            return null;
        },
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

pub fn luaV_shift(x: i64, s: i64) i64 {
    const ux = @as(u64, @bitCast(x));
    if (s < 0) return @as(i64, @bitCast(ux >> @as(u6, @intCast(-s & 0x3F))));
    return @as(i64, @bitCast(ux << @as(u6, @intCast(s & 0x3F))));
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
                LUA_OPSHL => @as(f64, @floatFromInt(luaV_shift(@as(i64, @intFromFloat(p1.number)), @as(i64, @intFromFloat(p2.number))))),
                LUA_OPSHR => @as(f64, @floatFromInt(luaV_shift(@as(i64, @intFromFloat(p1.number)), -@as(i64, @intFromFloat(p2.number))))),
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

pub fn lua_newthread(L: *lua_State) !*lua_State {
    const g = G(L);
    const L1 = try L.allocator.create(lua_State);
    errdefer L.allocator.destroy(L1);
    const stack = try L.allocator.alloc(TValue, LUA_MINSTACK + 1);
    errdefer L.allocator.free(stack);
    L1.* = .{
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
        .allocator = L.allocator,
    };
    L1.ci = &L1.base_ci;
    L1.twups = g.thread_list;
    g.thread_list = L1;
    L.stack[L.top] = TValue{ .thread = L1 };
    L.top += 1;
    return L1;
}

pub fn lua_closethread(L: *lua_State, from: *lua_State) i32 {
    _ = from;
    L.status = 0;
    L.top = 0;
    L.ci = &L.base_ci;
    return LUA_OK;
}

pub fn lua_getstack(L: *lua_State, level: i32, ar: *lua_Debug) i32 {
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
    const key = TValue{ .string = lstring.luaS_new(g.allocator, &g.strt, g.seed, name) catch null };
    const val = ltable.get(globals, key);
    L.stack[L.top] = val;
    L.top += 1;
    return val.typ();
}

fn getTable(L: *lua_State, idx: i32) ?*lua_Table {
    const v = stackAt(L, idx);
    if (v == .table) return v.table;
    return null;
}

pub fn lua_gettable(L: *lua_State, idx: i32) !i32 {
    const obj = stackAt(L, idx);
    if (obj == .nil) {
        lua_pushnil(L);
        return LUA_TNIL;
    }
    const key = L.stack[L.top - 1];
    const res = L.top - 1;
    try ltm.luaV_gettable(L, obj, key, res);
    return L.stack[res].typ();
}

pub fn lua_getfield(L: *lua_State, idx: i32, k: []const u8) !i32 {
    const obj = stackAt(L, idx);
    if (obj == .nil) {
        lua_pushnil(L);
        return LUA_TNIL;
    }
    const g = G(L);
    const ts = try lstring.luaS_new(g.allocator, &g.strt, g.seed, k);
    const key = TValue{ .string = ts };
    const res = L.top;
    L.stack[L.top] = .{ .nil = {} };
    L.top += 1;
    try ltm.luaV_gettable(L, obj, key, res);
    return L.stack[res].typ();
}

pub fn lua_geti(L: *lua_State, idx: i32, n: lua_Integer) !i32 {
    const obj = stackAt(L, idx);
    if (obj == .nil) {
        lua_pushnil(L);
        return LUA_TNIL;
    }
    const key = TValue{ .number = @floatFromInt(n) };
    const res = L.top;
    L.stack[L.top] = .{ .nil = {} };
    L.top += 1;
    try ltm.luaV_gettable(L, obj, key, res);
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
    _ = nuvalue;
    const data = L.allocator.alloc(u8, sz) catch return null;
    const u = L.allocator.create(lua_Udata) catch {
        L.allocator.free(data);
        return null;
    };
    u.* = .{ .metatable = null, .data = data };
    registerGC(L, u) catch {
        L.allocator.free(data);
        L.allocator.destroy(u);
        return null;
    };
    L.stack[L.top] = TValue{ .userdata = u };
    L.top += 1;
    return @as(*anyopaque, @ptrCast(data.ptr));
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
    _ = idx;
    _ = n;
    lua_pushnil(L);
    return 1;
}

pub fn lua_setglobal(L: *lua_State, name: []const u8) void {
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
    // LUA_RIDX_GLOBALS == 2
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
    const val = L.stack[L.top - 1];
    L.top -= 1;
    const key = TValue{ .string = lstring.luaS_new(g.allocator, &g.strt, g.seed, name) catch null };
    ltable.set(globals, key, val) catch {};
}

pub fn lua_settable(L: *lua_State, idx: i32) !void {
    const obj = stackAt(L, idx);
    if (obj == .nil) {
        L.top -= 2;
        return;
    }
    const key = L.stack[L.top - 2];
    const val = L.stack[L.top - 1];
    L.top -= 2;
    try ltm.luaV_settable(L, obj, key, val);
}

pub fn lua_setfield(L: *lua_State, idx: i32, k: []const u8) !void {
    const obj = stackAt(L, idx);
    if (obj == .nil) {
        L.top -= 1;
        return;
    }
    const g = G(L);
    const ts = try lstring.luaS_new(g.allocator, &g.strt, g.seed, k);
    const val = L.stack[L.top - 1];
    L.top -= 1;
    try ltm.luaV_settable(L, obj, TValue{ .string = ts }, val);
}

pub fn lua_seti(L: *lua_State, idx: i32, n: lua_Integer) !void {
    const obj = stackAt(L, idx);
    if (obj == .nil) {
        L.top -= 1;
        return;
    }
    const val = L.stack[L.top - 1];
    L.top -= 1;
    try ltm.luaV_settable(L, obj, TValue{ .number = @floatFromInt(n) }, val);
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

pub fn lua_callk(L: *lua_State, nargs: i32, nresults: i32, ctx: lua_KContext, k: ?lua_KFunction) !void {
    _ = ctx;
    _ = k;
    const func_idx = L.top - @as(usize, @intCast(nargs)) - 1;
    if (try precall(L, func_idx, nresults)) |new_ci| {
        try lvm.run(L, new_ci);
    }
}

pub fn lua_call(L: *lua_State, nargs: i32, nresults: i32) !void {
    try lua_callk(L, nargs, nresults, 0, null);
}

pub fn lua_pcallk(L: *lua_State, nargs: i32, nresults: i32, errfunc: i32, ctx: lua_KContext, k: ?lua_KFunction) i32 {
    _ = ctx;
    _ = k;
    const old_ci = L.ci;

    const func_idx = L.top - @as(usize, @intCast(nargs)) - 1;
    
    var err_occurred = false;
    const new_ci = precall(L, func_idx, nresults) catch |err| b: {
        err_occurred = true;
        if (err == error.NotAFunction) {
            const msg = "attempt to call a non-function value";
            const g = G(L);
            if (lstring.luaS_new(g.allocator, &g.strt, g.seed, msg)) |ts| {
                L.stack[L.top] = TValue{ .string = ts };
                L.top += 1;
            } else |_| {
                L.stack[L.top] = TValue{ .nil = {} };
                L.top += 1;
            }
        }
        break :b @as(?*CallInfo, null);
    };

    if (!err_occurred) {
        if (new_ci) |ci| {
            lvm.run(L, ci) catch {
                err_occurred = true;
            };
        }
    }

    if (err_occurred) {
        // Run error function if errfunc is not zero
        if (errfunc != 0) {
            // Find error function
            if (idxPtr(L, errfunc)) |err_fn_ptr| {
                if (err_fn_ptr.* == .function) {
                    const err_obj = L.stack[L.top - 1];
                    // Push error handler function
                    L.stack[L.top] = err_fn_ptr.*;
                    L.top += 1;
                    // Push error object
                    L.stack[L.top] = err_obj;
                    L.top += 1;
                    // Call it (1 arg, 1 result)
                    const err_ci = precall(L, L.top - 2, 1) catch null;
                    if (err_ci) |eci| {
                        lvm.run(L, eci) catch {};
                    }
                }
            }
        }

        // Get the final error object
        const final_err_obj = if (L.top > func_idx + @as(usize, @intCast(nargs)) + 1)
            L.stack[L.top - 1]
        else b: {
            const g = G(L);
            const ts = lstring.luaS_new(g.allocator, &g.strt, g.seed, "error during execution") catch null;
            break :b if (ts) |t| TValue{ .string = t } else TValue{ .nil = {} };
        };

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
        L.top = func_idx + 1;
        L.stack[func_idx] = final_err_obj;
        return LUA_ERRRUN;
    }

    return LUA_OK;
}

pub inline fn lua_pcall(L: *lua_State, nargs: i32, nresults: i32, errfunc: i32) i32 {
    return lua_pcallk(L, nargs, nresults, errfunc, 0, null);
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
    return L.status;
}

pub fn lua_isyieldable(L: *lua_State) i32 {
    if (L.ci == &L.base_ci) return 0;
    if (L.nCcalls > 0) return 0;
    return 1;
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
    var curr = g.allgc;
    while (curr) |gc| {
        switch (gc.val) {
            .table => |t| if (@intFromPtr(t) == @intFromPtr(ptr)) return gc,
            .closure => |cl| if (@intFromPtr(cl) == @intFromPtr(ptr)) return gc,
            .upval => |uv| if (@intFromPtr(uv) == @intFromPtr(ptr)) return gc,
            .proto => |p| if (@intFromPtr(p) == @intFromPtr(ptr)) return gc,
            .userdata => |ud| if (@intFromPtr(ud) == @intFromPtr(ptr)) return gc,
        }
        curr = gc.next;
    }
    return null;
}

fn markObject(L: *lua_State, gc: *VMGCObject, gray_list: *std.ArrayList(*VMGCObject)) !void {
    if (gc.color == .white) {
        gc.color = .gray;
        try gray_list.append(L.allocator, gc);
    }
}

fn markValue(L: *lua_State, gray_list: *std.ArrayList(*VMGCObject), val: TValue) !void {
    const g = G(L);
    switch (val) {
        .string => |s| if (s) |str| {
            str.marked = true;
        },
        .table => |t| if (t) |tbl| if (getGCObject(g, tbl)) |gc| try markObject(L, gc, gray_list),
        .function => |f| if (f) |cl| if (getGCObject(g, cl)) |gc| try markObject(L, gc, gray_list),
        .upval => |u| if (u) |uv| if (getGCObject(g, uv)) |gc| try markObject(L, gc, gray_list),
        .proto => |p| if (p) |pr| if (getGCObject(g, pr)) |gc| try markObject(L, gc, gray_list),
        .userdata => |u| if (u) |ud| if (getGCObject(g, ud)) |gc| try markObject(L, gc, gray_list),
        else => {},
    }
}

fn freeGCObject(L: *lua_State, gc: *VMGCObject) void {
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
            L.allocator.free(u.data);
            L.allocator.destroy(u);
        },
    }
    L.allocator.destroy(gc);
}

pub fn luaC_collectgarbage(L: *lua_State) !void {
    const g = G(L);
    
    // 1. Reset/Clear gray list
    var gray_list = std.ArrayList(*VMGCObject).empty;
    defer gray_list.deinit(L.allocator);

    // 2. Set all objects to white
    var curr = g.allgc;
    while (curr) |gc| {
        gc.color = .white;
        curr = gc.next;
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

    // Root 4: The stack of all active states
    var i: usize = 0;
    while (i < L.top) : (i += 1) {
        try markValue(L, &gray_list, L.stack[i]);
    }

    // Root 5: Open upvalues
    var curr_uv = L.openupval;
    while (curr_uv) |uv| {
        if (getGCObject(g, uv)) |gc| {
            try markObject(L, gc, &gray_list);
        }
        curr_uv = uv.next;
    }

    // 4. Traverse gray list until empty
    while (gray_list.pop()) |gc| {
        if (gc.color == .black) continue;
        gc.color = .black;

        // Traverse fields of the object and mark them
        switch (gc.val) {
            .table => |t| {
                // Mark array part
                for (t.array.items) |val| {
                    try markValue(L, &gray_list, val);
                }
                // Mark hash part
                for (t.node.items) |nd| {
                    try markValue(L, &gray_list, nd.key);
                    try markValue(L, &gray_list, nd.val);
                }
                // Mark metatable
                if (t.metatable) |mt| {
                    if (getGCObject(g, mt)) |mt_gc| {
                        try markObject(L, mt_gc, &gray_list);
                    }
                }
            },
            .closure => |cl| {
                switch (cl.*) {
                    .c => |cc| {
                        for (cc.upvals) |uv| {
                            try markValue(L, &gray_list, uv);
                        }
                    },
                    .lua => |lc| {
                        // Mark prototype
                        if (getGCObject(g, lc.p)) |proto_gc| {
                            try markObject(L, proto_gc, &gray_list);
                        }
                        // Mark upvalues
                        for (lc.upvals) |opt_uv| {
                            if (opt_uv) |uv| {
                                if (getGCObject(g, uv)) |uv_gc| {
                                    try markObject(L, uv_gc, &gray_list);
                                }
                            }
                        }
                    },
                }
            },
            .upval => |uv| {
                try markValue(L, &gray_list, uv.value);
            },
            .proto => |p| {
                if (p.source) |src| src.marked = true;
                // Mark upvalue names
                for (p.upvalues) |uvd| {
                    if (uvd.name) |name| name.marked = true;
                }
                // Mark local variable names
                for (p.locvars) |lv| {
                    if (lv.varname) |name| name.marked = true;
                }
                // Mark constants
                for (p.k) |val| {
                    try markValue(L, &gray_list, val);
                }
                // Mark nested prototypes
                for (p.p) |sub_p| {
                    if (getGCObject(g, sub_p)) |sub_gc| {
                        try markObject(L, sub_gc, &gray_list);
                    }
                }
            },
            .userdata => |ud| {
                if (ud.metatable) |mt| {
                    if (getGCObject(g, mt)) |mt_gc| {
                        try markObject(L, mt_gc, &gray_list);
                    }
                }
            },
        }
    }

    // 5. Sweep phase: free white objects
    var prev_gc: ?*VMGCObject = null;
    var sweep_curr = g.allgc;
    while (sweep_curr) |gc| {
        const next_gc = gc.next;
        if (gc.color == .white) {
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
        }
        sweep_curr = next_gc;
    }

    // Sweep strings:
    // First, find all unmarked strings
    var dead_strings = std.ArrayList([]const u8).empty;
    defer dead_strings.deinit(L.allocator);
    
    var str_it = g.strt.iterator();
    while (str_it.next()) |entry| {
        const ts = entry.value_ptr.*;
        if (!ts.marked) {
            try dead_strings.append(L.allocator, entry.key_ptr.*);
        } else {
            ts.marked = false; // Reset for next GC cycle
        }
    }

    // Now remove and free them
    for (dead_strings.items) |key| {
        const ts = g.strt.get(key).?;
        _ = g.strt.swapRemove(key);
        g.allocator.free(key);
        g.allocator.destroy(ts);
    }
}

pub const LUA_GCSTOP: i32 = 0;
pub const LUA_GCRESTART: i32 = 1;
pub const LUA_GCCOLLECT: i32 = 2;
pub const LUA_GCCOUNT: i32 = 3;
pub const LUA_GCCOUNTB: i32 = 4;
pub const LUA_GCSTEP: i32 = 5;
pub const LUA_GCSETPAUSE: i32 = 6;
pub const LUA_GCSETSTEPMUL: i32 = 7;
pub const LUA_GCISRUNNING: i32 = 9;
pub const LUA_GCGEN: i32 = 10;
pub const LUA_GCINC: i32 = 11;

pub fn lua_gc(L: *lua_State, what: i32, arg: i32) i32 {
    _ = arg;
    switch (what) {
        LUA_GCCOLLECT => {
            luaC_collectgarbage(L) catch return -1;
            return 0;
        },
        else => return 0,
    }
}

pub fn lua_error(L: *lua_State) anyerror {
    const err_obj = L.stack[L.top - 1];
    if (err_obj == .nil) {
        const g = G(L);
        const ts = try lstring.luaS_new(g.allocator, &g.strt, g.seed, "<no error object>");
        L.stack[L.top - 1] = TValue{ .string = ts };
    }
    return error.RuntimeError;
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

pub fn lua_stringtonumber(L: *lua_State, s: []const u8) usize {
    // returns consumed prefix length + 1 if valid number, else 0
    if (s.len == 0) return 0;

    var i: usize = 0;
    // optional sign
    if (s[i] == '+' or s[i] == '-') {
        i += 1;
        if (i >= s.len) return 0;
    }

    // check for special tokens: inf, nan
    if (i < s.len) {
        var lower_i = s[i];
        if (lower_i >= 'A' and lower_i <= 'Z') lower_i = lower_i - 'A' + 'a';
        if (lower_i == 'i' and i + 2 < s.len) {
            const rest = s[i..];
            var rest_lower: [10]u8 = undefined;
            const copy_len = @min(rest.len, rest_lower.len);
            @memcpy(rest_lower[0..copy_len], rest[0..copy_len]);
            _ = std.ascii.lowerString(rest_lower[0..copy_len], rest[0..copy_len]);
            if (std.mem.eql(u8, rest_lower[0..3], "inf")) {
                if (copy_len >= 8 and std.mem.eql(u8, rest_lower[0..8], "infinity")) {
                    const val: f64 = if (s[0] == '-') -std.math.inf(f64) else std.math.inf(f64);
                    lua_pushnumber(L, val);
                    return i + 8;
                }
                const val: f64 = if (s[0] == '-') -std.math.inf(f64) else std.math.inf(f64);
                lua_pushnumber(L, val);
                return i + 3;
            }
            if (std.mem.eql(u8, rest_lower[0..3], "nan")) {
                const val: f64 = std.math.nan(f64);
                lua_pushnumber(L, val);
                return i + 3;
            }
        }
    }

    // hex float?
    if (i + 1 < s.len and s[i] == '0' and (s[i + 1] == 'x' or s[i + 1] == 'X')) {
        i += 2;
        var j = i;
        // integer part
        while (j < s.len and isHexDigit(s[j])) : (j += 1) {}
        // optional fractional part
        if (j < s.len and s[j] == '.') {
            j += 1;
            while (j < s.len and isHexDigit(s[j])) : (j += 1) {}
        }
        if (j == i) return 0; // at least one hex digit required
        // optional binary exponent
        if (j < s.len and (s[j] == 'p' or s[j] == 'P')) {
            j += 1;
            if (j < s.len and (s[j] == '+' or s[j] == '-')) j += 1;
            j = skipDigits(s, j);
            if (j > i and s[j - 1] < '0' or s[j - 1] > '9') {
                if (j > i + 1 and (s[j - 2] >= '0' and s[j - 2] <= '9')) {} else return 0;
            }
        }
        const sub = s[0..j];
        const n = std.fmt.parseFloat(f64, sub) catch return 0;
        lua_pushnumber(L, n);
        return j + 1;
    }

    // decimal
    var j = i;
    // integer part (or go to fractional)
    j = skipDigits(s, j);
    // is this just digits? could be integer
    // check for dot (fractional)
    var has_dot = false;
    if (j < s.len and s[j] == '.') {
        has_dot = true;
        j += 1;
        j = skipDigits(s, j);
    }
    // exponent
    if (j < s.len and (s[j] == 'e' or s[j] == 'E')) {
        j += 1;
        if (j < s.len and (s[j] == '+' or s[j] == '-')) j += 1;
        j = skipDigits(s, j);
    }
    if (j == i) return 0; // no digits consumed

    const sub = s[0..j];
    // try integer first (only if no dot)
    if (!has_dot) {
        if (std.fmt.parseInt(i64, sub, 0)) |iv| {
            lua_pushinteger(L, iv);
            return j + 1;
        } else |_| {}
    }
    // try float
    const n = std.fmt.parseFloat(f64, sub) catch return 0;
    lua_pushnumber(L, n);
    return j + 1;
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

pub fn luaL_newstate_io(L: *lua_State, gpa: std.mem.Allocator, io: std.Io) !void {
    const g = try gpa.create(global_State);
    g.* = .{
        .allocator = gpa,
        .strt = std.array_hash_map.String(*lua_TString).empty,
        .seed = @intFromPtr(L) ^ 0x9e3779b97f4a7c15,
        .registry = TValue{ .nil = {} },
        .mt = [_]?*lua_Table{null} ** 9,
        .tmname = [_]?*lua_TString{null} ** 25,
        .io_backend = null,
        .io = io,
        .prng = std.Random.Xoshiro256.init(@intFromPtr(L)),
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
    g.mainthread = L;
    try ltable.setInt(registry_tab, llimits.LUA_RIDX_MAINTHREAD, TValue{ .thread = L });
    const globals_tab = try ltable.createTable(gpa, 0, 0);
    try registerGC(L, globals_tab);
    try ltable.setInt(registry_tab, 2, TValue{ .table = globals_tab });
    try ltm.luaT_init(L);
}

pub fn luaL_newstate(L: *lua_State, gpa: std.mem.Allocator) !void {
    var threaded = std.Io.Threaded.init(gpa, .{});
    errdefer threaded.deinit();
    try luaL_newstate_io(L, gpa, threaded.io());
    L.l_G.?.io_backend = threaded;
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
            freeGCObject(L, gc);
            curr_gc = next_gc;
        }
        g.allgc = null;

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
            t.allocator.free(t.stack);
            t.allocator.destroy(t);
            curr_thread = next_thread;
        }
        g.thread_list = null;

        L.allocator.destroy(g);
    }
    L.allocator.free(L.stack);
}
