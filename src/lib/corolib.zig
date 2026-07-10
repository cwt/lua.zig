/*
** $Id: corolib.zig
** Coroutine library for Zua (Zig port of Lua 5.5.1)
** See Copyright Notice in c_compat.zig
*/

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");

// ===================================================================
// Coroutine library functions
// ===================================================================

pub fn opencorolib(L: *lua_State) !void {
    // coroutine.create(fn)
    lua.lua_pushcfunction(L, create);
    lua.lua_setfield(L, -1, "create");

    // coroutine.resume(co, vararg)
    lua.lua_pushcfunction(L, resume);
    lua.lua_setfield(L, -1, "resume");

    // coroutine.running()
    lua.lua_pushcfunction(L, running);
    lua.lua_setfield(L, -1, "running");

    // coroutine.status(co)
    lua.lua_pushcfunction(L, status);
    lua.lua_setfield(L, -1, "status");

    // coroutine.wrap(fn)
    lua.lua_pushcfunction(L, wrap);
    lua.lua_setfield(L, -1, "wrap");

    // coroutine.yield(vararg)
    lua.lua_pushcfunction(L, yield);
    lua.lua_setfield(L, -1, "yield");

    // coroutine.isyieldable()
    lua.lua_pushcfunction(L, isyieldable);
    lua.lua_setfield(L, -1, "isyieldable");

    // coroutine.close(co)
    lua.lua_pushcfunction(L, close);
    lua.lua_setfield(L, -1, "close");
}

// ===================================================================
// Coroutine library function implementations
// ===================================================================

fn create(L: *lua_State) i32 {
    if (!lua.lua_iscfunction(L, 1)) {
        return lua.lua_error(L);
    }
    const func = lua.lua_tocfunction(L, 1);
    // Would create a coroutine
    lua.lua_pushlightuserdata(L, func);
    return 1;
}

fn resume(L: *lua_State) i32 {
    if (!lua.lua_isthread(L, 1)) {
        return lua.lua_error(L);
    }
    const nargs = lua.lua_gettop(L) - 1;
    const nres = if (lua.lua_gettop(L) >= 2) {
        const n = lua.lua_tointeger(L, 2);
        n orelse nargs
    } else nargs;
    const status = lua.lua_resume(L, 1, nres, null);
    return status;
}

fn running(L: *lua_State) i32 {
    // Would return current thread
    lua.lua_pushthread(L);
    return 1;
}

fn status(L: *lua_State) i32 {
    if (!lua.lua_isthread(L, 1)) {
        return lua.lua_error(L);
    }
    // Would return status string
    lua.lua_pushstring(L, "suspended");
    return 1;
}

fn wrap(L: *lua_State) i32 {
    if (!lua.lua_iscfunction(L, 1)) {
        return lua.lua_error(L);
    }
    const func = lua.lua_tocfunction(L, 1);
    // Would create and return wrapped coroutine
    lua.lua_pushlightuserdata(L, func);
    return 1;
}

fn yield(L: *lua_State) i32 {
    const nargs = lua.lua_gettop(L);
    const status = lua.lua_yieldk(L, nargs, 0, null);
    return status;
}

fn isyieldable(L: *lua_State) i32 {
    if (lua.lua_gettop(L) == 0) {
        const mt = lua.lua_getmetatable(L, 1);
        if (mt) |m| {
            const is_yieldable = lua.lua_getiuservalue(L, 1, 1);
            if (is_yieldable) {
                lua.lua_pushboolean(L, 1);
                return 1;
            }
        }
    }
    lua.lua_pushboolean(L, 0);
    return 1;
}

fn close(L: *lua_State) i32 {
    if (!lua.lua_isthread(L, 1)) {
        return lua.lua_error(L);
    }
    // Would close coroutine
    return 0;
}
