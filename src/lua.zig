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
pub const lapi = @import("lapi.zig");

// Re-exports of the shared number-parsing engine (lobject.zig, Phase A.1):
// lvm.zig's hot path calls `tonumberValue`; the standard libraries call
// `lua_stringtonumber` (stringlib/iolib/baselib).
pub const tonumberValue = lobject.tonumberValue;
pub const lua_stringtonumber = lobject.lua_stringtonumber;
// B3: the lobject.c remainder moved into lobject.zig (re-exported).
pub const tostringbuffFloat = lobject.tostringbuffFloat;
pub const luaO_tostringbuff = lobject.luaO_tostringbuff;
pub const toNumeric = lobject.toNumeric;
pub const luaV_rawequalobj = lobject.luaV_rawequalobj;
pub const luaG_runerror = lobject.luaG_runerror;
pub const luaG_errnnil = lobject.luaG_errnnil;
pub const luaG_forerror = lobject.luaG_forerror;
pub const luaG_tointerror = lobject.luaG_tointerror;
pub const luaG_typeerror = lobject.luaG_typeerror;
pub const luaG_typeerrorPtr = lobject.luaG_typeerrorPtr;
pub const luaG_callerror = lobject.luaG_callerror;
pub const luaG_opinterror = lobject.luaG_opinterror;
pub const luaG_concaterror = lobject.luaG_concaterror;
pub const luaG_ordererror = lobject.luaG_ordererror;


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
// Re-exports of the C API module (lapi.zig, Refactor B6).
pub const idxPtr = lapi.idxPtr;
pub const toAbsoluteIndex = lapi.toAbsoluteIndex;
pub const lua_absindex = lapi.lua_absindex;
pub const stackAt = lapi.stackAt;
pub const lua_gettop = lapi.lua_gettop;
pub const lua_settop = lapi.lua_settop;
pub const lua_pushvalue = lapi.lua_pushvalue;
pub const lua_rotate = lapi.lua_rotate;
pub const lua_insert = lapi.lua_insert;
pub const lua_remove = lapi.lua_remove;
pub const lua_newtable = lapi.lua_newtable;
pub const lua_copy = lapi.lua_copy;
pub const lua_isnoneornil = lapi.lua_isnoneornil;
pub const lua_register = lapi.lua_register;
pub const lua_pushglobaltable = lapi.lua_pushglobaltable;
pub const lua_pushliteral = lapi.lua_pushliteral;
pub const lua_isfunction = lapi.lua_isfunction;
pub const lua_isthread = lapi.lua_isthread;
pub const lua_islightuserdata = lapi.lua_islightuserdata;
pub const lua_isnone = lapi.lua_isnone;
pub const lua_isnil = lapi.lua_isnil;
pub const lua_isboolean = lapi.lua_isboolean;
pub const lua_istable = lapi.lua_istable;
pub const lua_isnumber = lapi.lua_isnumber;
pub const lua_isstring = lapi.lua_isstring;
pub const lua_iscfunction = lapi.lua_iscfunction;
pub const lua_isinteger = lapi.lua_isinteger;
pub const lua_isuserdata = lapi.lua_isuserdata;
pub const lua_type = lapi.lua_type;
pub const lua_typename = lapi.lua_typename;
pub const lua_tonumberx = lapi.lua_tonumberx;
pub const lua_tointegerx = lapi.lua_tointegerx;
pub const lua_tonumber = lapi.lua_tonumber;
pub const lua_tointeger = lapi.lua_tointeger;
pub const lua_toboolean = lapi.lua_toboolean;
pub const lua_tolstring = lapi.lua_tolstring;
pub const lua_rawlen = lapi.lua_rawlen;
pub const lua_tocfunction = lapi.lua_tocfunction;
pub const lua_touserdata = lapi.lua_touserdata;
pub const lua_tothread = lapi.lua_tothread;
pub const lua_topointer = lapi.lua_topointer;
pub const numMod = lapi.numMod;
pub const luaV_shift = lapi.luaV_shift;
pub const lua_arith = lapi.lua_arith;
pub const lua_rawequal = lapi.lua_rawequal;
pub const lua_compare = lapi.lua_compare;
pub const lua_pushnil = lapi.lua_pushnil;
pub const lua_pushnumber = lapi.lua_pushnumber;
pub const lua_pushinteger = lapi.lua_pushinteger;
pub const lua_pushlstring = lapi.lua_pushlstring;
pub const lua_pushstring = lapi.lua_pushstring;
pub const lua_pushexternalstring = lapi.lua_pushexternalstring;
pub const lua_pushvfstring = lapi.lua_pushvfstring;
pub const lua_pushfstring = lapi.lua_pushfstring;
pub const lua_pushcclosure = lapi.lua_pushcclosure;
pub const lua_pushcfunction = lapi.lua_pushcfunction;
pub const lua_upvalueindex = lapi.lua_upvalueindex;
pub const lua_getupvalue = lapi.lua_getupvalue;
pub const lua_setupvalue = lapi.lua_setupvalue;
pub const lua_upvalueid = lapi.lua_upvalueid;
pub const lua_upvaluejoin = lapi.lua_upvaluejoin;
pub const lua_pushboolean = lapi.lua_pushboolean;
pub const lua_pushlightuserdata = lapi.lua_pushlightuserdata;
pub const lua_resetthread = lapi.lua_resetthread;
pub const lua_pushthread = lapi.lua_pushthread;
pub const lua_pop = lapi.lua_pop;
pub const lua_replace = lapi.lua_replace;
pub const lua_getglobal = lapi.lua_getglobal;
pub const getTable = lapi.getTable;
pub const lua_gettable = lapi.lua_gettable;
pub const lua_getfield = lapi.lua_getfield;
pub const lua_geti = lapi.lua_geti;
pub const lua_rawget = lapi.lua_rawget;
pub const lua_rawgeti = lapi.lua_rawgeti;
pub const lua_rawgetp = lapi.lua_rawgetp;
pub const lua_createtable = lapi.lua_createtable;
pub const lua_newuserdatauv = lapi.lua_newuserdatauv;
pub const lua_newuserdata = lapi.lua_newuserdata;
pub const lua_getmetatable = lapi.lua_getmetatable;
pub const lua_getiuservalue = lapi.lua_getiuservalue;
pub const lua_getuservalue = lapi.lua_getuservalue;
pub const lua_setglobal = lapi.lua_setglobal;
pub const lua_settable = lapi.lua_settable;
pub const lua_setfield = lapi.lua_setfield;
pub const lua_seti = lapi.lua_seti;
pub const lua_rawset = lapi.lua_rawset;
pub const lua_rawseti = lapi.lua_rawseti;
pub const lua_rawsetp = lapi.lua_rawsetp;
pub const lua_setmetatable = lapi.lua_setmetatable;
pub const lua_setiuservalue = lapi.lua_setiuservalue;
pub const lua_setuservalue = lapi.lua_setuservalue;
pub const lua_callk = lapi.lua_callk;
pub const lua_call = lapi.lua_call;
pub const lua_pcallk = lapi.lua_pcallk;
pub const lua_pcall = lapi.lua_pcall;
pub const lua_load = lapi.lua_load;
pub const finishLoad = lapi.finishLoad;
pub const lua_dump = lapi.lua_dump;
pub const lua_next = lapi.lua_next;
pub const isStringish = lapi.isStringish;
pub const luaV_concat = lapi.luaV_concat;
pub const lua_concat = lapi.lua_concat;
pub const lua_len = lapi.lua_len;
pub const lua_atpanic = lapi.lua_atpanic;
pub const lua_version = lapi.lua_version;
pub const lua_getallocf = lapi.lua_getallocf;
pub const lua_setallocf = lapi.lua_setallocf;
pub const checkclosemth = lapi.checkclosemth;
pub const lua_toclose = lapi.lua_toclose;
pub const lua_closeslot = lapi.lua_closeslot;
pub const luaL_dostring = lapi.luaL_dostring;
pub const luaL_dostringReader = lapi.luaL_dostringReader;
pub const lua_tostring = lapi.lua_tostring;

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

    pub fn toBoolean(self: TValue) bool {
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

pub extern "c" fn snprintf(buf: [*]u8, size: usize, format: [*]const u8, ...) c_int;
extern "c" fn strtod(nptr: [*:0]const u8, endptr: ?*?[*:0]const u8) f64;
extern "c" fn strspn(str1: [*]const u8, str2: [*]const u8) usize;


/// D5 dedupe (docs/refactor.md): shared "format into a fixed buffer, fall
/// back to `fallback` on overflow" helper. Replaces the
/// `std.fmt.bufPrint(&buf, fmt, args) catch "..."` idiom that was
/// copy-pasted across lua.zig / lauxlib.zig / lparser.zig. Behavior is
/// identical: the formatted slice is returned when it fits, otherwise
/// `fallback` verbatim.
pub fn fmtMsg(buf: []u8, fallback: []const u8, comptime fmt: []const u8, args: anytype) []const u8 {
    return std.fmt.bufPrint(buf, fmt, args) catch fallback;
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


