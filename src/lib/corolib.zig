const std = @import("std");
const lua = @import("../lua.zig");
const llimits = @import("../llimits.zig");
const lauxlib = @import("../lauxlib.zig");

fn getco(L: *lua.lua_State) !*lua.lua_State {
    const co = lua.lua_tothread(L, 1);
    try lauxlib.luaL_argexpected(L, co != null, 1, "thread");
    return co.?;
}

fn auxresume(L: *lua.lua_State, co: *lua.lua_State, narg: i32) i32 {
    if (lua.lua_checkstack(co, narg) == 0) {
        _ = lua.lua_pushstring(L, "too many arguments to resume");
        return -1;
    }
    lua.lua_xmove(L, co, narg);
    var nres: i32 = 0;
    const status = lua.lua_resume(co, L, narg, &nres);
    if (status == lua.LUA_OK or status == lua.LUA_YIELD) {
        if (lua.lua_checkstack(L, nres + 1) == 0) {
            lua.lua_pop(co, nres);
            _ = lua.lua_pushstring(L, "too many results to resume");
            return -1;
        }
        lua.lua_xmove(co, L, nres);
        return nres;
    } else {
        lua.lua_xmove(co, L, 1);
        return -1;
    }
}

fn luaB_coresume(L: *lua.lua_State) anyerror!i32 {
    const co = try getco(L);
    const r = auxresume(L, co, lua.lua_gettop(L) - 1);
    if (r < 0) {
        lua.lua_pushboolean(L, 0);
        lua.lua_insert(L, -2);
        return 2;
    } else {
        lua.lua_pushboolean(L, 1);
        lua.lua_insert(L, -(r + 1));
        return r + 1;
    }
}

fn luaB_auxwrap(L: *lua.lua_State) anyerror!i32 {
    const co = lua.lua_tothread(L, lua.lua_upvalueindex(1)) orelse return error.NotAThread;
    const r = auxresume(L, co, lua.lua_gettop(L));
    if (r < 0) {
        var stat = lua.lua_status(co);
        if (stat != lua.LUA_OK and stat != lua.LUA_YIELD) {
            stat = lua.lua_closethread(co, L);
            lua.lua_xmove(co, L, 1);
        }
        if (stat != lua.LUA_ERRMEM and lua.lua_type(L, -1) == lua.LUA_TSTRING) {
            lauxlib.luaL_where(L, 1);
            lua.lua_insert(L, -2);
            lua.lua_concat(L, 2);
        }
        return lua.lua_error(L);
    }
    return r;
}

fn luaB_cocreate(L: *lua.lua_State) anyerror!i32 {
    try lauxlib.luaL_checktype(L, 1, lua.LUA_TFUNCTION);
    const NL = try lua.lua_newthread(L);
    lua.lua_pushvalue(L, 1);
    lua.lua_xmove(L, NL, 1);
    return 1;
}

fn luaB_cowrap(L: *lua.lua_State) anyerror!i32 {
    _ = try luaB_cocreate(L);
    lua.lua_pushcclosure(L, luaB_auxwrap, 1);
    return 1;
}

fn luaB_yield(L: *lua.lua_State) anyerror!i32 {
    return lua.lua_yield(L, lua.lua_gettop(L));
}

const COS_RUN: i32 = 0;
const COS_DEAD: i32 = 1;
const COS_YIELD: i32 = 2;
const COS_NORM: i32 = 3;

const statname = [_][]const u8{ "running", "dead", "suspended", "normal" };

fn auxstatus(L: *lua.lua_State, co: *lua.lua_State) i32 {
    if (L == co) return COS_RUN;
    switch (lua.lua_status(co)) {
        lua.LUA_YIELD => return COS_YIELD,
        lua.LUA_OK => {
            var ar: lua.lua_Debug = undefined;
            if (lua.lua_getstack(co, 0, &ar) != 0) return COS_NORM;
            if (lua.lua_gettop(co) == 0) return COS_DEAD;
            return COS_YIELD;
        },
        else => return COS_DEAD,
    }
}

fn luaB_costatus(L: *lua.lua_State) anyerror!i32 {
    const co = try getco(L);
    const st = auxstatus(L, co);
    _ = lua.lua_pushstring(L, statname[@as(usize, @intCast(st))]);
    return 1;
}

fn getoptco(L: *lua.lua_State) *lua.lua_State {
    if (lua.lua_isnone(L, 1) != 0) return L;
    return getco(L) catch L;
}

fn luaB_yieldable(L: *lua.lua_State) anyerror!i32 {
    const co = getoptco(L);
    lua.lua_pushboolean(L, lua.lua_isyieldable(co));
    return 1;
}

fn luaB_corunning(L: *lua.lua_State) anyerror!i32 {
    const ismain = lua.lua_pushthread(L);
    lua.lua_pushboolean(L, ismain);
    return 2;
}

fn luaB_close(L: *lua.lua_State) anyerror!i32 {
    const co = getoptco(L);
    const st = auxstatus(L, co);
    switch (st) {
        COS_DEAD, COS_YIELD => {
            const status = lua.lua_closethread(co, L);
            if (status == lua.LUA_OK) {
                lua.lua_pushboolean(L, 1);
                return 1;
            } else {
                lua.lua_pushboolean(L, 0);
                lua.lua_xmove(co, L, 1);
                return 2;
            }
        },
        COS_NORM => return lauxlib.luaL_error(L, "cannot close a normal coroutine"),
        COS_RUN => {
            _ = try lua.lua_geti(L, lua.LUA_REGISTRYINDEX, llimits.LUA_RIDX_MAINTHREAD);
            if (lua.lua_tothread(L, -1)) |main| {
                if (main == co) return lauxlib.luaL_error(L, "cannot close main thread");
            }
            _ = lua.lua_closethread(co, L);
            return 0;
        },
        else => unreachable,
    }
}

pub fn opencorolib(L: *lua.lua_State) !void {
    lua.lua_newtable(L);

    _ = lua.lua_pushcfunction(L, luaB_cocreate);
    try lua.lua_setfield(L, -2, "create");

    _ = lua.lua_pushcfunction(L, luaB_coresume);
    try lua.lua_setfield(L, -2, "resume");

    _ = lua.lua_pushcfunction(L, luaB_corunning);
    try lua.lua_setfield(L, -2, "running");

    _ = lua.lua_pushcfunction(L, luaB_costatus);
    try lua.lua_setfield(L, -2, "status");

    _ = lua.lua_pushcfunction(L, luaB_cowrap);
    try lua.lua_setfield(L, -2, "wrap");

    _ = lua.lua_pushcfunction(L, luaB_yield);
    try lua.lua_setfield(L, -2, "yield");

    _ = lua.lua_pushcfunction(L, luaB_yieldable);
    try lua.lua_setfield(L, -2, "isyieldable");

    _ = lua.lua_pushcfunction(L, luaB_close);
    try lua.lua_setfield(L, -2, "close");
}
