const std = @import("std");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");
pub const lvm = @import("lvm.zig");
pub const ltable = @import("ltable.zig");
pub const lstring = @import("lstring.zig");
const lundump = @import("lundump.zig");
const ldump = @import("ldump.zig");
pub const ltm = @import("ltm.zig");
const libm = @import("libm.zig");
pub const llex = @import("llex.zig");
pub const lcode = @import("lcode.zig");
pub const lparser = @import("lparser.zig");
pub const lobject = @import("lobject.zig");
pub const ldebug = @import("ldebug.zig");
pub const lgc = @import("lgc.zig");
pub const ldo = @import("ldo.zig");
pub const lstate = @import("lstate.zig");

// Re-exports of the shared number-parsing engine (lobject.zig, Phase A.1):
// lvm.zig's hot path calls `tonumberValue`; the standard libraries call
// `lua_stringtonumber` (stringlib/iolib/baselib).
pub const tonumberValue = lobject.tonumberValue;
pub const lua_stringtonumber = lobject.lua_stringtonumber;

// Re-exports of the debug-introspection module (ldebug.zig, Refactor B1):
// callers keep the `lua.` qualification unchanged.
pub const lua_getstack = ldebug.lua_getstack;
pub const lua_sethook = ldebug.lua_sethook;
pub const lua_gethook = ldebug.lua_gethook;
pub const lua_gethookmask = ldebug.lua_gethookmask;
pub const lua_gethookcount = ldebug.lua_gethookcount;
pub const luaF_getlocalname = ldebug.luaF_getlocalname;
pub const luaG_findlocal = ldebug.luaG_findlocal;
pub const lua_getlocal = ldebug.lua_getlocal;
pub const lua_setlocal = ldebug.lua_setlocal;
pub const luaO_chunkid = ldebug.luaO_chunkid;
pub const isLua = ldebug.isLua;
pub const currentpc = ldebug.currentpc;
pub const luaG_getfuncline = ldebug.luaG_getfuncline;
pub const lua_getinfo = ldebug.lua_getinfo;
// Cross-module helpers (called by the error-message builders that stay in
// this file until B4/B6): exposed pub in ldebug.zig for the move.
pub const upvalname = ldebug.upvalname;
pub const funcnamefromcall = ldebug.funcnamefromcall;
pub const getfuncname = ldebug.getfuncname;
pub const getobjname = ldebug.getobjname;

// Re-exports of the GC engine (lgc.zig, Refactor B2).
pub const registerGC = lgc.registerGC;
pub const luaC_condGC = lgc.luaC_condGC;
pub const luaC_checkGC = lgc.luaC_checkGC;
pub const luaC_collectgarbage = lgc.luaC_collectgarbage;
pub const luaS_clearcache = lgc.luaS_clearcache;
pub const lua_gc = lgc.lua_gc;
// Re-exports of the state-lifecycle module (lstate.zig, Refactor B5) and
// the err handler moved into ldo.zig.
pub const growStack = lstate.growStack;
pub const reserveErrorStack = lstate.reserveErrorStack;
pub const shrinkStack = lstate.shrinkStack;
pub const reallocStack = lstate.reallocStack;
pub const lua_checkstack = lstate.lua_checkstack;
pub const lua_xmove = lstate.lua_xmove;
pub const lua_newthread = lstate.lua_newthread;
pub const lua_closethread = lstate.lua_closethread;
pub const luaE_warning = lstate.luaE_warning;
pub const luaE_warnerror = lstate.luaE_warnerror;
pub const lua_setwarnf = lstate.lua_setwarnf;
pub const lua_warning = lstate.lua_warning;
pub const luaL_newstate_io = lstate.luaL_newstate_io;
pub const luaL_newstate = lstate.luaL_newstate;
pub const createargtable = lstate.createargtable;
pub const lua_close = lstate.lua_close;
pub const luaD_errerr = ldo.luaD_errerr;

// Re-exports of the call/continuation module (ldo.zig, Refactor B4).
pub const close_one_slot = ldo.close_one_slot;
pub const luaF_closeupval = ldo.luaF_closeupval;
pub const closeupvals = ldo.closeupvals;
pub const luaD_hook = ldo.luaD_hook;
pub const luaG_traceexec = ldo.luaG_traceexec;
pub const poscall = ldo.poscall;
pub const allocCallInfo = ldo.allocCallInfo;
pub const freeCallInfo = ldo.freeCallInfo;
pub const freeAllCallInfos = ldo.freeAllCallInfos;
pub const recycleCallInfos = ldo.recycleCallInfos;
pub const unwindCis = ldo.unwindCis;
pub const PF_VAHID = ldo.PF_VAHID;
pub const PF_VATAB = ldo.PF_VATAB;
pub const precall = ldo.precall;
pub const lua_yieldk = ldo.lua_yieldk;
pub const lua_yield = ldo.lua_yield;
pub const lua_resume = ldo.lua_resume;
pub const lua_status = ldo.lua_status;
pub const lua_isyieldable = ldo.lua_isyieldable;
pub const luaG_errormsg = ldo.luaG_errormsg;
pub const lua_error = ldo.lua_error;


// Re-exports of the GC constants + cross-module GC helper (lgc.zig, Refactor B2).
pub const LUA_GCSTOP = lgc.LUA_GCSTOP;
pub const LUA_GCRESTART = lgc.LUA_GCRESTART;
pub const LUA_GCCOLLECT = lgc.LUA_GCCOLLECT;
pub const LUA_GCCOUNT = lgc.LUA_GCCOUNT;
pub const LUA_GCCOUNTB = lgc.LUA_GCCOUNTB;
pub const LUA_GCSTEP = lgc.LUA_GCSTEP;
pub const LUA_GCISRUNNING = lgc.LUA_GCISRUNNING;
pub const LUA_GCGEN = lgc.LUA_GCGEN;
pub const LUA_GCINC = lgc.LUA_GCINC;
pub const LUA_GCPARAM = lgc.LUA_GCPARAM;
pub const LUA_GCPMINORMUL = lgc.LUA_GCPMINORMUL;
pub const LUA_GCPMAJORMINOR = lgc.LUA_GCPMAJORMINOR;
pub const LUA_GCPMINORMAJOR = lgc.LUA_GCPMINORMAJOR;
pub const LUA_GCPPAUSE = lgc.LUA_GCPPAUSE;
pub const LUA_GCPSTEPMUL = lgc.LUA_GCPSTEPMUL;
pub const LUA_GCPSTEPSIZE = lgc.LUA_GCPSTEPSIZE;
pub const LUA_GCPN = lgc.LUA_GCPN;
pub const freeGCObject = lgc.freeGCObject;



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
pub const LUA_ERRFILE: i32 = llimits.LUA_ERRFILE;
pub const LUA_ERRSYNTAX: i32 = llimits.LUA_ERRSYNTAX;
pub const LUA_MINSTACK: i32 = llimits.LUA_MINSTACK;
pub const LUA_NUMTYPES: i32 = llimits.LUA_NUMTYPES;
pub const LUA_MAXINTEGER: lua_Integer = llimits.LUA_MAXINTEGER;
pub const LUA_MININTEGER: lua_Integer = llimits.LUA_MININTEGER;
pub const MAX_SIZET: usize = llimits.MAX_SIZET;
pub const MAX_SIZE: usize = llimits.MAX_SIZE;

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
pub fn l_alloc(ud: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) ?*anyopaque {
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
    metatable: ?*lua_Table = null,
    flags: u8 = 0,
    gc: ?*VMGCObject = null,
    g: ?*global_State = null,
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

/// A3 (docs/refactor.md): shared failure handling for `__close` metamethod
/// calls. Previously two ~30-line catch blocks copy-pasted in
/// `close_one_slot` (one per callTM shape). Propagates `Yield`/
/// `ThreadClosed` as Zig errors (restoring `L.top` on a self-close,
/// BUG-168); a `NotAFunction` call produces the reference's "attempt to
/// call a <type> value (metamethod 'close')" error object; any other
/// failure reports the object the handler itself pushed (`saved_err`).
pub fn closeCallFailed(L: *lua_State, e: anyerror, tm: TValue, old_top: usize) anyerror!?TValue {
    if (e == error.Yield) return e;
    if (e == error.ThreadClosed) {
        // The `__close` handler closed the thread itself (a
        // `coroutine.close` self-close). Propagate the signal so
        // `closeupvals` can treat it as a clean self-close rather
        // than a close error (BUG-168).
        L.top = old_top;
        return error.ThreadClosed;
    }
    const saved_err = if (L.top > old_top and L.top - 1 < L.stack.len) L.stack[L.top - 1] else TValue{ .nil = {} };
    L.top = old_top;
    if (e == error.NotAFunction) {
        const tname = switch (tm) {
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
        const msg = fmtMsg(&buf, "attempt to call a bad value (metamethod 'close')", "attempt to call a {s} value (metamethod 'close')", .{tname});
        const ts = lstring.luaS_new(L, msg) catch {
            return saved_err;
        };
        return TValue{ .string = ts };
    }
    return saved_err;
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
    concat_k: usize = 0,
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
    warnf: ?lua_WarnFunction = null,
    ud_warn: ?*anyopaque = null,
    prng_state: [4]u64,
    tmpname_counter: u64 = 0,
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
    /// Current GC mode (LUA_GCINC default or LUA_GCGEN). `lua_gc` with
    /// LUA_GCGEN/LUA_GCINC switches the mode and returns the *previous* one,
    /// matching `collectgarbage("generational"/"incremental")` returning the
    /// old mode name (BUG-158). The engine stays mark-and-sweep; only the
    /// mode label is tracked so the return-value contract is conformant.
    gc_mode: i32 = LUA_GCINC,
    /// Accumulated work for `LUA_GCSTEP` (BUG-169): each `collectgarbage(
    /// "step", n)` advances this by `n` units; when it reaches the step
    /// budget (`gcparams[LUA_GCPSTEPMUL]`) a full mark-and-sweep collection
    /// runs and the accumulator resets, returning 1 (cycle complete). This
    /// mirrors the reference's bounded incremental stepping so that
    /// `dosteps(10) < dosteps(2)` in gc.lua holds.
    gc_step_accum: usize = 0,
};

pub inline fn G(L: *lua_State) *global_State {
    return L.l_G orelse @panic("global state not initialized");
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
    /// Re-entrancy guard for `lua_closethread`: set while a thread is being
    /// closed so a nested self-close (a `__close` metamethod calling
    /// `coroutine.close` on the thread it is running on) skips the
    /// destructive teardown that would free the live CallInfo chain the outer
    /// close (and its `__close` C frames) still holds (BUG-168).
    close_in_progress: bool = false,
    /// Set once a closed thread's pending error has been reported by
    /// `lua_closethread`, so a subsequent close of the same (already-closed)
    /// thread is clean instead of re-reporting the stale error (BUG-168, the
    /// "after closing, no more errors" case in coroutine.lua).
    close_err_consumed: bool = false,
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
    growStack(L, L.top + 1) catch return;
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
        .integer => |i| fmtMsg(buff, "", "{d}", .{i}),
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

/// D5 dedupe (docs/refactor.md): shared "format into a fixed buffer, fall
/// back to `fallback` on overflow" helper. Replaces the
/// `std.fmt.bufPrint(&buf, fmt, args) catch "..."` idiom that was
/// copy-pasted across lua.zig / lauxlib.zig / lparser.zig. Behavior is
/// identical: the formatted slice is returned when it fits, otherwise
/// `fallback` verbatim.
pub fn fmtMsg(buf: []u8, fallback: []const u8, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buf, fmt, args) catch fallback;
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
            luaC_condGC(L);
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
    luaC_condGC(L);
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
    growStack(L, L.top + 1) catch {
        if (falloc) |f| _ = f(ud, @constCast(s.ptr), len + 1, 0);
        return null;
    };
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
    luaC_condGC(L);
    return ts.s;
}

pub fn lua_pushvfstring(L: *lua_State, fmt: []const u8, argp: ?*anyopaque) ?[]const u8 {
    _ = argp;
    const s = lua_pushstring(L, fmt);
    luaC_condGC(L);
    return s;
}

pub fn lua_pushfstring(L: *lua_State, fmt: []const u8) ?[]const u8 {
    const s = lua_pushstring(L, fmt);
    luaC_condGC(L);
    return s;
}

pub fn lua_pushcclosure(L: *lua_State, cfunc: lua_CFunction, n: i32) void {
    if (n == 0) {
        // No upvalues: reuse the cached closure for this C function (the
        // reference pushes a light function value here, which does not
        // allocate either). Root the closure in the registry so it survives.
        if (L.l_G) |g| {
            if (g.cfunc_cache.get(cfunc)) |cached| {
                growStack(L, L.top + 1) catch return;
                L.stack[L.top] = TValue{ .function = cached };
                L.top += 1;
                luaC_condGC(L);
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
        growStack(L, L.top + 1) catch return;
        L.stack[L.top] = TValue{ .function = cl };
        L.top += 1;
        luaC_condGC(L);
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
    luaC_condGC(L);
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


/// Deprecated alias for `lua_closethread(L, null)`.
pub inline fn lua_resetthread(L: *lua_State) i32 {
    return lua_closethread(L, null);
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
    growStack(L, L.top + 1) catch return LUA_TNIL;
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
    const res = L.top;
    L.stack[L.top] = .{ .nil = {} };
    L.top += 1;
    try ltm.luaV_gettable(L, obj_ptr, key, res);
    L.top = res + 1;
    return L.stack[res].typ();
}

pub fn lua_geti(L: *lua_State, idx: i32, n: lua_Integer) !i32 {
    growStack(L, L.top + 1) catch return LUA_TNIL;
    const obj_ptr = idxPtr(L, idx) orelse {
        lua_pushnil(L);
        return LUA_TNIL;
    };
    if (obj_ptr.* == .nil) {
        lua_pushnil(L);
        return LUA_TNIL;
    }
    const key = TValue{ .integer = n };
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
    luaC_condGC(L);
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
        if (err == error.Yield or err == error.ThreadClosed) {
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
            // luaG_errormsg dispatches to the error handler and saves the result in L.err_obj;
            // catching the returned error union keeps L.err_obj populated for the pcall recovery path.
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
            // luaG_errormsg dispatches to the error handler and saves the result in L.err_obj;
            // catching the returned error union keeps L.err_obj populated for the pcall recovery path.
            _ = luaG_errormsg(L) catch {};
        } else if (err == error.RuntimeError) {
            // Error object already in L.err_obj (captured by luaG_errormsg at origin)
        } else {
            if (lstring.luaS_new(L, "error")) |ts| {
                L.stack[L.top] = TValue{ .string = ts };
                L.top += 1;
            } else |_| {}
            // luaG_errormsg dispatches to the error handler and saves the result in L.err_obj;
            // catching the returned error union keeps L.err_obj populated for the pcall recovery path.
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
                    if (err == error.Yield or err == error.ThreadClosed) {
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
                        // luaG_errormsg dispatches to the error handler and saves the result in L.err_obj;
                        // catching the returned error union keeps L.err_obj populated for the pcall recovery path.
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
        unwindCis(L, old_ci);

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
        L.err_name = null;
        L.err_namewhat = null;
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
        return switch (e) {
            error.Yield => LUA_YIELD,
            error.OutOfMemory => LUA_ERRMEM,
            error.ErrorError => LUA_ERRERR,
            else => LUA_ERRRUN,
        };
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
fn luaG_varinfo(L: *lua_State, o_ptr: *const TValue, buf: []u8) []const u8 {
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
                return fmtMsg(buf, "", " (upvalue '{s}')", .{uname});
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
                    return fmtMsg(buf, "", " (upvalue '{s}')", .{uname});
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
    return fmtMsg(buf, "", " ({s} '{s}')", .{ kind, name.? });
}

/// Error when a value cannot be converted to an integer (bitwise/shift operand
/// or `floor`/integer coercion). Mirrors PUC-Rio `luaG_tointerror`: the message
/// is `"number%s has no integer representation"`, where `%s` is the operand's
/// `varinfo` (e.g. ` (field 'huge')`).
/// A4 (docs/refactor.md): shared tail of the `luaG_*` error-message
/// builders — the repeated
/// `const mslice = fmtMsg(buf, fallback, fmt, args); return
/// luaG_runerror(L, mslice);` two-step. Callers keep their own fixed
/// buffer (each site's overflow behavior is preserved exactly) and pass
/// pre-formatted fragments (e.g. `luaG_varinfo` results) as args.
fn luaG_err(L: *lua_State, buf: []u8, fallback: []const u8, comptime fmt: []const u8, args: anytype) !void {
    return luaG_runerror(L, fmtMsg(buf, fallback, fmt, args));
}

pub fn luaG_errnnil(L: *lua_State, proto: *const lua_Proto, k: i32) !void {
    var globalname: []const u8 = "?";
    if (k > 0 and @as(usize, @intCast(k - 1)) < proto.k.len) {
        const kv = proto.k[@as(usize, @intCast(k - 1))];
        if (kv == .string) {
            if (kv.string) |ts| globalname = ts.s;
        }
    }
    var buf: [256]u8 = undefined;
    return luaG_err(L, &buf, "global already defined", "global '{s}' already defined", .{globalname});
}

pub fn luaG_forerror(L: *lua_State, o: TValue, what: []const u8) !void {
    const t = ltm.luaT_objtypename(L, o);
    var msg: [256]u8 = undefined;
    return luaG_err(L, &msg, "bad 'for' value", "bad 'for' {s} (number expected, got {s})", .{ what, t });
}

pub fn luaG_tointerror(L: *lua_State, o: TValue) !void {
    var buf: [256]u8 = undefined;
    const info = luaG_varinfo(L, &o, &buf);
    var msg: [320]u8 = undefined;
    return luaG_err(L, &msg, "number has no integer representation", "number{s} has no integer representation", .{info});
}

pub fn luaG_typeerror(L: *lua_State, o: TValue, op: []const u8) !void {
    return luaG_typeerrorPtr(L, &o, op);
}

pub fn luaG_typeerrorPtr(L: *lua_State, o: *const TValue, op: []const u8) !void {
    var buf: [256]u8 = undefined;
    const info = luaG_varinfo(L, o, &buf);
    const t = ltm.luaT_objtypename(L, o.*);
    var msg: [320]u8 = undefined;
    return luaG_err(L, &msg, "attempt to perform operation on value", "attempt to {s} a {s} value{s}", .{ op, t, info });
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
            return luaG_err(L, &msg, "attempt to call a non-function value", "attempt to call a {s} value ({s} '{s}')", .{ t, k, fnm });
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
        fmtMsg(&msg, "attempt to compare values", "attempt to compare two {s} values", .{t1})
    else
        fmtMsg(&msg, "attempt to compare values", "attempt to compare {s} with {s}", .{ t1, t2 });
    return luaG_runerror(L, mslice);
}

pub fn lua_load(L: *lua_State, reader: lua_Reader, dt: ?*anyopaque, chunkname: []const u8, mode: []const u8) i32 {
    luaC_condGC(L);
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
            const m = fmtMsg(&msg, "attempt to load a text chunk", "attempt to load a text chunk (mode is '{s}')", .{mode});
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
            const m = fmtMsg(&msg, "attempt to load a binary chunk", "attempt to load a binary chunk (mode is '{s}')", .{mode});
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
                error.TruncatedChunk => fmtMsg(&msg_buf, "truncated chunk", "{s}: truncated chunk", .{chunkname}),
                error.IntegerOverflow => fmtMsg(&msg_buf, "integer overflow", "{s}: integer overflow", .{chunkname}),
                error.VersionMismatch => fmtMsg(&msg_buf, "bad binary format (version mismatch)", "{s}: bad binary format (version mismatch)", .{chunkname}),
                error.FormatMismatch => fmtMsg(&msg_buf, "bad binary format (format mismatch)", "{s}: bad binary format (format mismatch)", .{chunkname}),
                error.BadHeader, error.CorruptedChunk => fmtMsg(&msg_buf, "bad binary format (corrupted chunk)", "{s}: bad binary format (corrupted chunk)", .{chunkname}),
                error.TypeSizeMismatch, error.TypeFormatMismatch => fmtMsg(&msg_buf, "bad binary format (size mismatch)", "{s}: bad binary format (size mismatch)", .{chunkname}),
                else => fmtMsg(&msg_buf, "corrupted chunk", "{s}: corrupted chunk", .{chunkname}),
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
            const m = fmtMsg(&msg, "attempt to load a text chunk", "attempt to load a text chunk (mode is '{s}')", .{mode});
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

    const cl = L.allocator.create(lua_Closure) catch {
        L.allocator.free(upvals);
        L.allocator.destroy(lc);
        return LUA_ERRMEM;
    };
    cl.* = .{ .lua = lc };
    registerGC(L, cl) catch {
        L.allocator.free(upvals);
        L.allocator.destroy(lc);
        L.allocator.destroy(cl);
        return LUA_ERRMEM;
    };

    // Ensure stack capacity and anchor cl on the stack immediately so it and its upvalues are tracked by GC roots
    growStack(L, L.top + 1) catch {
        return LUA_ERRMEM;
    };
    L.stack[L.top] = TValue{ .function = cl };
    L.top += 1;

    // Initialize upvalues for top-level closure (matching PUC-Rio ldo.c)
    if (proto.upvalues.len > 0) {
        const registry = G(L).registry.table orelse {
            L.top -= 1;
            return LUA_ERRMEM;
        };
        const globals = ltable.getInt(registry, 2); // RIDX_GLOBALS is 2
        const is_env = if (proto.upvalues[0].name) |name| std.mem.eql(u8, name.s, "_ENV") else true;
        for (0..proto.upvalues.len) |i| {
            const uv = L.allocator.create(UpVal) catch {
                L.top -= 1;
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
                L.top -= 1;
                return LUA_ERRMEM;
            };
            upvals[i] = uv;
        }
    }

    return LUA_OK;
}

pub fn lua_dump(L: *lua_State, writer: lua_Writer, data: ?*anyopaque, strip: i32) i32 {
    return ldump.lua_dump(L, writer, data, strip);
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
            if (L.ci) |ci| {
                ci.concat_k = k;
            }
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
    luaC_condGC(L);
}


pub fn luaL_dostring(L: *lua_State, s: []const u8, name: []const u8) !i32 {
    var data = s;
    const status = lua_load(L, luaL_dostringReader, @as(?*anyopaque, @ptrCast(&data)), name, "bt");
    if (status != LUA_OK) {
        return status;
    }
    return lua_pcall(L, 0, LUA_MULTRET, 0);
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

