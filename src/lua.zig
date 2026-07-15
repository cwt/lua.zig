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

pub const LUA_VERSION_NUM: lua_Number = @as(f64, @floatFromInt(@as(usize, LUA_VERSION_MAJOR_N) * 100 + LUA_VERSION_MINOR_N));
pub const LUA_N2SBUFFSZ: usize = 64;
pub const LUA_COPYRIGHT = "Lua 5.5  Copyright (C) 1994-2026 Lua.org, PUC-Rio";
pub const LUA_AUTHORS = "R. Ierusalimschy, L. H. de Figueiredo, W. Celes";
pub const LUA_SIGNATURE = "\x1bLua";

/// C API identification string (port of `lua_ident` from `lapi.c`).
/// Provides version and author strings embedded at link time in the C
/// reference; here a comptime `[]const u8` slice.
pub const lua_ident: []const u8 = "$LuaVersion: " ++ LUA_COPYRIGHT ++ " $" ++ "$LuaAuthors: " ++ LUA_AUTHORS ++ " $";

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

    pub fn typ(self: TValue) i32 {
        return switch (self) {
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
    allocator.free(f.code);
    allocator.free(f.k);
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
}

// Proto flag bits (mirror lua/ldo.h PF_*). A Lua function is vararg when its
// 'flag' carries PF_VAHID (hidden vararg args) or PF_VATAB (vararg table);
// such functions begin with OP_VARARGPREP, which relocates the frame and must
// read the real argument count from 'L->top'.
const PF_VAHID: u8 = 1; // function has hidden vararg arguments
const PF_VATAB: u8 = 2; // function has a vararg table

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
            const new_ci = try allocCallInfo(L);
            new_ci.* = .{
                .func = func_idx,
                .base = func_idx + 1,
                .top = L.top + 20,
                .nresults = nresults,
                .savedpc = 0,
                .previous = old_ci,
                .next = null,
            };
            if (old_ci) |prev| {
                prev.next = new_ci;
            }
            L.ci = new_ci;
            const n = cc.f(L) catch |e| {
                if (e == error.Yield) {
                    return error.Yield;
                }
                L.ci = old_ci;
                if (old_ci) |prev| {
                    prev.next = null;
                }
                freeCallInfo(L, new_ci);
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
            poscall(L, new_ci, first_result, num_returned);
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
            const new_ci = try allocCallInfo(L);
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
            return new_ci;
        },
    }
}

pub const UpVal = struct {
    value: TValue,
    index: ?usize,
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
        string: *lua_TString,
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
    clibs: std.ArrayList(*std.DynLib),
    panic: ?lua_CFunction = null,
    gc_threshold: usize = 1000,
    gc_count: usize = 0,
    /// GC control: if false, GC is stopped (LUA_GCSTOP). Allocations still
    /// happen but do not trigger collection.
    gc_running: bool = true,
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
        else => @compileError("Unsupported type for GC registration"),
    };
    gc.* = .{
        .next = g.allgc,
        .val = union_val,
    };
    g.allgc = gc;
    g.gc_count += 1;

    switch (union_val) {
        .table => |t| t.gc = gc,
        .closure => |cl| switch (cl.*) {
            .c => |cc| cc.gc = gc,
            .lua => |lc| lc.gc = gc,
        },
        .upval => |uv| uv.gc = gc,
        .proto => |p| p.gc = gc,
        .userdata => |ud| ud.gc = gc,
        .string => |ts| ts.gc = gc,
    }
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
    // C reference: (idx > 0 || idx <= LUA_REGISTRYINDEX) ? idx : lua_gettop(L) + 1 + idx
    if (idx > 0 or idx <= LUA_REGISTRYINDEX) return idx;
    const base: usize = if (L.ci) |ci| ci.base else 0;
    // Negative stack index: convert to positive relative to base
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

pub fn lua_checkstack(L: *lua_State, n: i32) i32 {
    const needed = L.top + @as(usize, @intCast(n));
    if (needed <= L.stack.len) return 1;
    const new_cap = needed + LUA_MINSTACK;
    const old_len = L.stack.len;
    L.stack = L.allocator.realloc(L.stack, new_cap) catch return 0;
    for (L.stack[old_len..]) |*item| {
        item.* = .{ .nil = {} };
    }
    L.stack_last = L.stack.len - 1;
    return 1;
}

pub fn lua_xmove(from: *lua_State, to: *lua_State, n: i32) void {
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
pub inline fn lua_register(L: *lua_State, name: []const u8, func: lua_CFunction) void {
    lua_pushcfunction(L, func);
    lua_setglobal(L, name);
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
    if (isnum) |p| p.* = switch (v) {
        .number => 1,
        .integer => 1,
        else => 0,
    };
    return switch (v) {
        .number => |n| n,
        .integer => |n| @as(f64, @floatFromInt(n)),
        else => null,
    };
}

pub fn lua_tointegerx(L: *lua_State, idx: i32, isnum: ?*i32) ?i64 {
    const v = stackAt(L, idx);
    const min_f64 = @as(f64, -9223372036854775808.0);
    const max_exclusive_f64 = @as(f64, 9223372036854775808.0);
    if (isnum) |p| p.* = switch (v) {
        .integer => 1,
        .number => |n| if (@trunc(n) == n and n >= min_f64 and n < max_exclusive_f64) 1 else 0,
        else => 0,
    };
    return switch (v) {
        .integer => |n| n,
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
            const src = std.mem.trim(u8, str.s, &std.ascii.whitespace);
            if (std.fmt.parseInt(i64, src, 0)) |i| {
                return TValue{ .integer = i };
            } else |_| {}
            if (std.fmt.parseFloat(f64, src)) |n| {
                return TValue{ .number = n };
            } else |_| {}
            return null;
        },
        else => null,
    };
}

pub fn lua_arith(L: *lua_State, op: i32) void {
    if (op < 0 or op > 13) return;
    const is_unary = (op == LUA_OPUNM or op == LUA_OPBNOT);
    if (is_unary) {
        if (L.top < 1) return;
        const p1 = L.stack[L.top - 1];
        if (p1 == .integer) {
            const result = switch (op) {
                LUA_OPUNM => @as(TValue, .{ .integer = -p1.integer }),
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
            ltm.luaT_trybinTM(L, p1, p1, L.top - 1, event) catch {};
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
                        LUA_OPADD => @as(TValue, .{ .integer = n1.integer + n2.integer }),
                        LUA_OPSUB => @as(TValue, .{ .integer = n1.integer - n2.integer }),
                        LUA_OPMUL => @as(TValue, .{ .integer = n1.integer * n2.integer }),
                        LUA_OPMOD => @as(TValue, .{ .integer = @rem(n1.integer, n2.integer) }),
                        LUA_OPPOW => @as(TValue, .{ .number = libm.getLibm().pow(@as(f64, @floatFromInt(n1.integer)), @as(f64, @floatFromInt(n2.integer))) }),
                        LUA_OPDIV => @as(TValue, .{ .number = @as(f64, @floatFromInt(n1.integer)) / @as(f64, @floatFromInt(n2.integer)) }),
                        LUA_OPIDIV => blk: {
                            const ib = n1.integer;
                            const ic = n2.integer;
                            // Handle minint / -1 (overflows as wrapping)
                            const q = if (ic == -1) ib else @divTrunc(ib, ic);
                            const r = @rem(ib, ic);
                            break :blk TValue{ .integer = if (r == 0 or (ib >= 0) == (ic >= 0)) q else q - 1 };
                        },
                        LUA_OPBAND => @as(TValue, .{ .integer = n1.integer & n2.integer }),
                        LUA_OPBOR => @as(TValue, .{ .integer = n1.integer | n2.integer }),
                        LUA_OPBXOR => @as(TValue, .{ .integer = n1.integer ^ n2.integer }),
                        LUA_OPSHL => @as(TValue, .{ .integer = luaV_shift(n1.integer, n2.integer) }),
                        LUA_OPSHR => @as(TValue, .{ .integer = luaV_shift(n1.integer, -n2.integer) }),
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
                        LUA_OPMOD => f1 - @floor(f1 / f2) * f2,
                        LUA_OPPOW => libm.getLibm().pow(f1, f2),
                        LUA_OPDIV => f1 / f2,
                        LUA_OPIDIV => @floor(f1 / f2),
                        LUA_OPBAND => @floatFromInt(n1.toIntegerExact() & n2.toIntegerExact()),
                        LUA_OPBOR => @floatFromInt(n1.toIntegerExact() | n2.toIntegerExact()),
                        LUA_OPBXOR => @floatFromInt(n1.toIntegerExact() ^ n2.toIntegerExact()),
                        LUA_OPSHL => @floatFromInt(luaV_shift(n1.toIntegerExact(), n2.toIntegerExact())),
                        LUA_OPSHR => @floatFromInt(luaV_shift(n1.toIntegerExact(), -n2.toIntegerExact())),
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
        .integer => |v| if (v == b.integer) 1 else 0,
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
    if (L.top >= L.stack.len) _ = lua_checkstack(L, 1);
    L.stack[L.top] = TValue{ .nil = {} };
    L.top += 1;
}

pub fn lua_pushnumber(L: *lua_State, n: lua_Number) void {
    if (L.top >= L.stack.len) _ = lua_checkstack(L, 1);
    L.stack[L.top] = TValue{ .number = n };
    L.top += 1;
}

pub fn lua_pushinteger(L: *lua_State, n: lua_Integer) void {
    if (L.top >= L.stack.len) _ = lua_checkstack(L, 1);
    L.stack[L.top] = TValue{ .integer = n };
    L.top += 1;
}

pub fn lua_pushlstring(L: *lua_State, s: []const u8, len: usize) ?[]const u8 {
    if (L.top >= L.stack.len) {
        if (lua_checkstack(L, 1) == 0) return null;
    }
    const g = G(L);
    const ts = lstring.luaS_new(g, s[0..len]) catch return null;
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
            L.stack[L.top] = if (uv.index) |idx| L.stack[idx] else uv.value;
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
            const new_val = L.stack[L.top - 1];
            if (uv.index) |idx| {
                L.stack[idx] = new_val;
            } else {
                uv.value = new_val;
            }
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
    if (L.top >= L.stack.len) _ = lua_checkstack(L, 1);
    L.stack[L.top] = TValue{ .boolean = b != 0 };
    L.top += 1;
}

pub fn lua_pushlightuserdata(L: *lua_State, p: ?*anyopaque) void {
    if (L.top >= L.stack.len) _ = lua_checkstack(L, 1);
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
        .base_ci = .{ .func = 0, .base = 0, .top = LUA_MINSTACK, .nresults = 0, .savedpc = 0, .previous = null, .next = null, .k = null, .ctx = 0, .nyield = 0 },
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

pub fn lua_closethread(L: *lua_State, from: ?*lua_State) i32 {
    _ = from;
    freeAllCallInfos(L);
    L.status = 0;
    L.top = 0;
    return LUA_OK;
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
            name.* = ts.s;
            return "metamethod";
        }
    }
    return null;
}

fn funcnamefromcall(L: *lua_State, ci: *CallInfo, name: *?[]const u8) ?[]const u8 {
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
    if (ci) |c| {
        if (c.previous) |prev| {
            if (prev != &L.base_ci) {
                return funcnamefromcall(L, prev, name);
            }
        }
    }
    return null;
}

pub fn isLua(ci: *CallInfo, L: *lua_State) bool {
    const val = L.stack[ci.func];
    if (val == .function) {
        if (val.function) |cl| {
            return cl.* == .lua;
        }
    }
    return false;
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
        const limit = if (ci.next) |next| next.func else L.top;
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

    if (source.len == 0) return;

    if (source[0] == '=') {
        const src = source[1..];
        const len = @min(src.len, bufflen - 1);
        @memcpy(out[0..len], src[0..len]);
    } else if (source[0] == '@') {
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
        while (basepc < pc) {
            if (basepc < f.lineinfo.len) {
                baseline += f.lineinfo[@intCast(basepc)];
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
            const tbl_idx = L.top - 1;
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
                    try lua_seti(L, @intCast(tbl_idx), currentline);
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
                ar.istailcall = false;
                ar.extraargs = 0;
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
                ar.ftransfer = 0;
                ar.ntransfer = 0;
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
    const key = TValue{ .string = lstring.luaS_new(g, name) catch null };
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
    const ts = try lstring.luaS_new(g, k);
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
    _ = idx;
    _ = n;
    lua_pushnil(L);
    return 1;
}

/// Deprecated alias for `lua_getiuservalue(L, idx, 1)`.
pub inline fn lua_getuservalue(L: *lua_State, idx: i32) i32 {
    return lua_getiuservalue(L, idx, 1);
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
    const key = TValue{ .string = lstring.luaS_new(g, name) catch null };
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
    const ts = try lstring.luaS_new(g, k);
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
    _ = L;
    _ = idx;
    _ = n;
    return 1;
}

/// Deprecated alias for `lua_setiuservalue(L, idx, 1)`.
pub inline fn lua_setuservalue(L: *lua_State, idx: i32) i32 {
    return lua_setiuservalue(L, idx, 1);
}

pub fn lua_callk(L: *lua_State, nargs: i32, nresults: i32, ctx: lua_KContext, k: ?lua_KFunction) !void {
    if (k != null and lua_isyieldable(L) != 0) {
        if (L.ci) |ci| {
            ci.k = k;
            ci.ctx = ctx;
        }
    }
    const func_idx = L.top - @as(usize, @intCast(nargs)) - 1;
    if (try precall(L, func_idx, nresults)) |new_ci| {
        try lvm.run(L, new_ci);
    }
}

pub fn lua_call(L: *lua_State, nargs: i32, nresults: i32) !void {
    try lua_callk(L, nargs, nresults, 0, null);
}

pub fn lua_pcallk(L: *lua_State, nargs: i32, nresults: i32, errfunc: i32, ctx: lua_KContext, k: ?lua_KFunction) i32 {
    if (k != null and lua_isyieldable(L) != 0) {
        if (L.ci) |ci| {
            ci.k = k;
            ci.ctx = ctx;
        }
    }
    const old_ci = L.ci;

    const func_idx = L.top - @as(usize, @intCast(nargs)) - 1;

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

    var err_occurred = false;
    const new_ci = precall(L, func_idx, nresults) catch |err| b: {
        if (err == error.Yield) {
            return LUA_YIELD;
        }
        err_occurred = true;
        if (err == error.NotAFunction) {
            const msg = "attempt to call a non-function value";
            const g = G(L);
            if (lstring.luaS_new(g, msg)) |ts| {
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
            lvm.run(L, ci) catch |err| {
                if (err == error.Yield) {
                    return LUA_YIELD;
                }
                err_occurred = true;
            };
        }
    }

    if (err_occurred) {
        // Run error function if errfunc was provided
        if (errfunc_abs) |efi| {
            const err_fn_ptr = &L.stack[efi];
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

        // Get the final error object
        const final_err_obj = if (L.top > func_idx + @as(usize, @intCast(nargs)) + 1)
            L.stack[L.top - 1]
        else b: {
            const g = G(L);
            const ts = lstring.luaS_new(g, "error during execution") catch null;
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
        return finishLoad(L, proto);
    } else {
        const proto = lparser.luaD_protectedparser(L, reader, dt, chunkname, first_slice.?) catch |e| {
            if (e == error.SyntaxError) return LUA_ERRSYNTAX;
            return LUA_ERRMEM;
        };
        return finishLoad(L, proto);
    }
}

// Instantiate a top-level closure for `proto` (wiring its _ENV upvalue to the
// global table) and push it onto the stack, ready to be called. Used by both
// the binary-chunk loader and the source-text parser paths.
pub fn finishLoad(L: *lua_State, proto: *lua_Proto) i32 {
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
        const registry = G(L).registry.table orelse return LUA_ERRMEM;
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
        if (upvals.len > 0 and upvals[0] != null) L.allocator.destroy(upvals[0].?);
        L.allocator.free(upvals);
        L.allocator.destroy(lc);
        destroyProto(L.allocator, proto);
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
        return error.RuntimeError;
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
                poscall(L, ci, L.top - u_nres, u_nres);
                L.ci = prev;
                freeCallInfo(L, ci);
            } else {
                // Check if the yielded frame is a Lua function. If so, resume
                // lvm.run on the existing CallInfo — savedpc already points past
                // the yield. Re-precalling would lose savedpc and restart from 0.
                const val = L.stack[ci.func];
                if (val == .function and val.function.?.* == .lua) {
                    L.ci = ci;
                    try lvm.run(L, ci);
                } else {
                    const prev = ci.previous;
                    const func_idx = ci.func;
                    L.ci = prev;
                    freeCallInfo(L, ci);
                    if (try precall(L, func_idx, LUA_MULTRET)) |new_ci| {
                        try lvm.run(L, new_ci);
                    }
                }
            }
        } else {
            return error.RuntimeError;
        }
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
            L.status = 0;
        }
    };

    if (nresults) |nr| {
        if (L.status == LUA_YIELD) {
            nr.* = if (L.ci) |ci| ci.nyield else 0;
        } else if (L.ci) |ci| {
            nr.* = @as(i32, @intCast(L.top)) - @as(i32, @intCast(ci.func + 1));
        } else {
            nr.* = 0;
        }
    }

    if (L.status == LUA_YIELD) return LUA_YIELD;
    // Coroutine finished (dead/completed): discard its call stack. Recycled
    // CallInfos would otherwise linger in the freelist until the thread is
    // explicitly closed, which the caller may never do.
    freeAllCallInfos(L);
    return LUA_OK;
}

pub fn lua_status(L: *lua_State) i32 {
    return L.status;
}

pub fn lua_isyieldable(L: *lua_State) i32 {
    if (L.ci == &L.base_ci) return 0;
    if (L.nCcalls >= llimits.LUAI_MAXCCALLS) return 0;
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
    _ = g;
    const T = @TypeOf(ptr);
    if (T == *lua_Table) return ptr.gc;
    if (T == *lua_Closure) {
        return switch (ptr.*) {
            .c => |cc| cc.gc,
            .lua => |lc| lc.gc,
        };
    }
    if (T == *UpVal) return ptr.gc;
    if (T == *lua_Proto) return ptr.gc;
    if (T == *lua_Udata) return ptr.gc;
    if (T == *lua_TString) return ptr.gc;
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
            // External strings are real GC objects; mark their VMGCObject so
            // the sweep keeps them alive while referenced.
            if (str.externally_owned) {
                if (getGCObject(g, str)) |gc| try markObject(L, gc, gray_list);
            }
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
            destroyProto(L.allocator, f);
        },
        .userdata => |u| {
            L.allocator.free(u.data);
            L.allocator.destroy(u);
        },
        .string => |ts| {
            // External strings only. Free the caller-owned bytes via the
            // external allocator (LSTRMEM); fixed external strings (LSTRFIX,
            // falloc == null) keep their static bytes. Always free the
            // lua_TString struct itself, which Lua allocated.
            if (ts.falloc) |falloc| {
                _ = falloc(ts.ud, @constCast(ts.s.ptr), ts.len + 1, 0);
            }
            L.allocator.destroy(ts);
        },
    }
    L.allocator.destroy(gc);
}

const WeakMode = struct { keys: bool, vals: bool };

fn getWeakMode(L: *lua_State, mt: *lua_Table) WeakMode {
    var keys = false;
    var vals = false;
    const g = G(L);
    const tm_mode_str = lstring.luaS_new(g, "__mode") catch return .{ .keys = false, .vals = false };
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

    // Root 4: The stack of all active states.
    // Mark only up to L.top; ci.top is a frame's allocated ceiling, but
    // values above L.top are uninitialized (nil) and do not need marking.
    // Using ci.top would expand the scan to LUA_MINSTACK for the base
    // frame, causing popped stack slots to survive GC.
    var i: usize = 0;
    while (i < L.top) : (i += 1) {
        try markValue(L, &gray_list, L.stack[i]);
    }

    // Root 4b: The stacks of all created threads
    var curr_th = g.thread_list;
    while (curr_th) |th| {
        var j: usize = 0;
        while (j < th.top) : (j += 1) {
            try markValue(L, &gray_list, th.stack[j]);
        }
        curr_th = th.twups;
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
                const mode = if (t.metatable) |mt| getWeakMode(L, mt) else WeakMode{ .keys = false, .vals = false };
                // Mark array part
                if (!mode.vals) {
                    for (t.array.items) |val| {
                        try markValue(L, &gray_list, val);
                    }
                }
                // Mark hash part
                for (t.node.items) |nd| {
                    if (!mode.keys) {
                        try markValue(L, &gray_list, nd.key);
                    }
                    if (!mode.vals) {
                        try markValue(L, &gray_list, nd.val);
                    }
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
            // Strings (external) have no outgoing references to traverse.
            .string => {},
        }
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
                                if (nd.key != .nil) {
                                    const key_white = mode.keys and isWhiteGCObject(g, nd.key);
                                    const val_white = mode.vals and isWhiteGCObject(g, nd.val);
                                    if (key_white or val_white) {
                                        nd.key = .nil;
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

    // 5. Sweep phase: free white objects
    var prev_gc: ?*VMGCObject = null;
    var sweep_curr = g.allgc;
    g.gc_count = 0;
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

    // Now remove and free them
    for (dead_strings.items) |ts| {
        _ = g.strt.swapRemove(ts.s);
        L.allocator.free(ts.s);
        L.allocator.destroy(ts);
    }
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
            // Total memory tracked by the allocator is not available directly
            // from std.mem.Allocator; return 0 for now.
            return 0;
        },
        LUA_GCCOUNTB => {
            return 0;
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

pub fn lua_error(L: *lua_State) anyerror {
    const err_obj = L.stack[L.top - 1];
    if (err_obj == .nil) {
        const g = G(L);
        const ts = try lstring.luaS_new(g, "<no error object>");
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
    if (n <= 0) {
        _ = lua_pushstring(L, "");
        return;
    }
    const g = G(L);
    const top = L.top;
    const start = top - @as(usize, @intCast(n));
    var list = std.ArrayListUnmanaged(u8).empty;
    defer list.deinit(L.allocator);
    var k: usize = 0;
    while (k < @as(usize, @intCast(n))) : (k += 1) {
        const val = L.stack[start + k];
        switch (val) {
            .string => |s| list.appendSlice(L.allocator, s.?.s) catch {},
            .number => |num| {
                var buf: [64]u8 = undefined;
                const slice = std.fmt.bufPrint(&buf, "{d}", .{num}) catch "";
                list.appendSlice(L.allocator, slice) catch {};
            },
            .integer => |num| {
                var buf: [32]u8 = undefined;
                const slice = std.fmt.bufPrint(&buf, "{d}", .{num}) catch "";
                list.appendSlice(L.allocator, slice) catch {};
            },
            else => {
                // Non-scalar value: default "<type>: 0x...>" representation
                // (mirrors luaL_tolstring's fallback; __tostring is not wired
                // through the TMS enum in luazig).
                var buf: [64]u8 = undefined;
                const tname = lua_typename(lua_type(L, @as(i32, @intCast(start + k))));
                const ptr = lua_topointer(L, @as(i32, @intCast(start + k)));
                const s = std.fmt.bufPrint(&buf, "{s}: 0x{x:0>14}", .{ tname, @intFromPtr(ptr) }) catch "";
                list.appendSlice(L.allocator, s) catch {};
            },
        }
    }
    const ts = lstring.luaS_new(g, list.items) catch {
        _ = lua_pushstring(L, "");
        return;
    };
    L.stack[start] = .{ .string = ts };
    L.top = start + 1;
}

pub fn lua_len(L: *lua_State, idx: i32) !void {
    const v = stackAt(L, idx);
    switch (v) {
        .string => |s| {
            lua_pushinteger(L, @as(i64, @intCast(s.?.s.len)));
        },
        .table => |t| {
            const tm = if (t.?.metatable) |mt| ltm.luaT_gettm(mt, .LEN, G(L).tmname[@intFromEnum(ltm.TMS.LEN)].?) else null;
            if (tm) |tm_val| {
                _ = try ltm.luaT_callTMres(L, tm_val, v, v, L.top);
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
            _ = try ltm.luaT_callTMres(L, tm, v, v, L.top);
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

pub fn lua_toclose(L: *lua_State, idx: i32) void {
    // Record the stack slot at `idx` as to-be-closed. luazig keeps a single
    // to-be-closed slot per state in `L.tbclist`; the deferred __close runs
    // when the enclosing frame closes (VM CLOSE opcode). Marking is what the
    // C API requires; honoring it on scope exit depends on the VM CLOSE path.
    L.tbclist = @as(usize, @intCast(lua_absindex(L, idx))) - 1;
}

pub fn lua_closeslot(L: *lua_State, idx: i32) void {
    // Explicitly run the __close metamethod on the value at `idx`, if any.
    const v = stackAt(L, idx);
    const mt = switch (v) {
        .table => |t| if (t) |x| x.metatable else null,
        .userdata => |u| if (u) |x| x.metatable else null,
        else => null,
    };
    const tm = if (mt) |m| ltm.luaT_gettm(m, .CLOSE, G(L).tmname[@intFromEnum(ltm.TMS.CLOSE)].?) else null;
    if (tm) |tm_val| {
        // Call __close(value, nil, nil); results are discarded (nresults = 0).
        _ = ltm.luaT_callTM(L, tm_val, v, TValue{ .nil = {} }, TValue{ .nil = {} }) catch {};
    }
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
        .prng = std.Random.Xoshiro256.init(@intFromPtr(L)),
        .clibs = .empty,
    };
    g.alloc_ud = @ptrCast(&g.alloc_wrapper);
    const stack = try gpa.alloc(TValue, LUA_MINSTACK + 1);
    for (stack) |*item| {
        item.* = .{ .nil = {} };
    }
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
        .base_ci = .{ .func = 0, .base = 0, .top = LUA_MINSTACK, .nresults = 0, .savedpc = 0, .previous = null, .next = null, .k = null, .ctx = 0, .nyield = 0 },
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
    // `threaded.io()` above captured a pointer to the stack-local `threaded`;
    // now that `threaded` lives in `io_backend` (heap), re-point `io` at it.
    L.l_G.?.io = L.l_G.?.io_backend.?.io();
}

pub fn createargtable(L: *lua_State, args: []const []const u8) !void {
    // Build the `arg` table (as in the reference standalone interpreter):
    //   arg[0] = script name (args[1]), arg[1..] = extra CLI args (args[2..]).
    // When running the REPL (no script), the table is left empty.
    lua_createtable(L, 0, 0);
    if (args.len >= 2) {
        _ = lua_pushstring(L, args[1]);
        lua_rawseti(L, -2, 0);
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            _ = lua_pushstring(L, args[i]);
            lua_rawseti(L, -2, @as(i64, @intCast(i - 1)));
        }
    }
    lua_setglobal(L, "arg");
}

pub fn luaL_dostring(L: *lua_State, s: []const u8, name: []const u8) !i32 {
    var data = s;
    const status = lua_load(L, luaL_dostringReader, @as(?*anyopaque, @ptrCast(&data)), name, "t");
    if (status != LUA_OK) {
        return status;
    }
    return lua_pcallk(L, 0, LUA_MULTRET, 0, 0, null);
}

pub fn luaL_dostringReader(L: *lua_State, data: ?*anyopaque, size: ?*usize) ?[]const u8 {
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

        // Free dynamically loaded libraries
        for (g.clibs.items) |lib| {
            lib.close();
            g.allocator.destroy(lib);
        }
        g.clibs.deinit(g.allocator);

        L.allocator.destroy(g);
    }
    L.allocator.free(L.stack);
}
