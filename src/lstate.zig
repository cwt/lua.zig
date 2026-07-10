const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");
const luaconf = @import("luaconf.zig");

pub const CallInfo = struct {
    func: usize,
    top: usize,
    previous: ?*CallInfo,
    next: ?*CallInfo,
    u: union(enum) {
        l: struct {
            savedpc: usize,
            trap: u8,
            nextraargs: i32,
        },
        c: struct {
            k: ?lua.lua_KFunction,
            old_errfunc: isize,
            ctx: lua.lua_KContext,
        },
    },
    u2: union(enum) {
        funcidx: i32,
        nyield: i32,
        nres: i32,
    },
    callstatus: u32,
};

pub const stringtable = struct {
    hash: []?[*]lua.lua_TString,
    nuse: i32,
    size: i32,
};

pub const global_State = struct {
    frealloc: llimits.lua_Alloc,
    ud: ?*anyopaque,
    GCtotalbytes: usize,
    GCdebt: usize,
    GCmarked: usize,
    GCmajorminor: i32,
    strt: stringtable,
    l_registry: lua.TValue,
    nilvalue: lua.TValue,
    seed: usize,
    currentwhite: u8,
    gcstate: u8,
    gckind: u8,
    gcstopem: u8,
    gcstp: u8,
    gcemergency: u8,
    allgc: ?*lua.GCObject,
    sweepgc: ?*lua.GCObject,
    finobj: ?*lua.GCObject,
    gray: ?*lua.GCObject,
    grayagain: ?*lua.GCObject,
    weak: ?*lua.GCObject,
    ephemeron: ?*lua.GCObject,
    allweak: ?*lua.GCObject,
    tobefnz: ?*lua.GCObject,
    fixedgc: ?*lua.GCObject,
    twups: ?*lua.lua_State,
    panic: ?lua.lua_CFunction,
    memerrmsg: ?lua.lua_TString,
    mainth: lua.lua_State,
    warnf: ?lua.lua_WarnFunction,
    ud_warn: ?*anyopaque,
};

pub const LX = struct {
    extra_: [luaconf.LUA_EXTRASPACE]u8,
    l: lua.lua_State,
};

pub const GCUnion = union(enum) {
    gc: lua.GCObject,
    ts: lua.lua_TString,
    u: lua.lua_Udata,
    cl: lua.lua_Closure,
    h: lua.lua_Table,
    p: lua.lua_Proto,
    th: lua.lua_State,
    upv: lua.lua_UpVal,
};

pub const lua_longjmp = struct {
    status: i32,
    ci: ?*CallInfo,
    errfunc: isize,
    nresults: i32,
};

pub inline fn G(L: *lua.lua_State) ?*global_State {
    return L.l_G;
}

pub inline fn mainthread(g: *global_State) *lua.lua_State {
    return &g.mainth;
}

pub inline fn completestate(g: *global_State) bool {
    return false;
}

pub inline fn gettotalbytes(g: *global_State) usize {
    return g.GCtotalbytes - g.GCdebt;
}
