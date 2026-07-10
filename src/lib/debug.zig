/*
** $Id: debug.zig
** Debug library for Zua (Zig port of Lua 5.5.1)
** See Copyright Notice in c_compat.zig
*/

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");

// ===================================================================
// Debug library functions
// ===================================================================

pub fn opendbalib(L: *lua_State) !void {
    // debug.gethook(L)
    lua.lua_pushcfunction(L, gethook);
    lua.lua_setfield(L, -1, "gethook");

    // debug.gethookcount(L)
    lua.lua_pushcfunction(L, gethookcount);
    lua.lua_setfield(L, -1, "gethookcount");

    // debug.gethookmask(L)
    lua.lua_pushcfunction(L, gethookmask);
    lua.lua_setfield(L, -1, "gethookmask");

    // debug.getlocal(L, ar, n)
    lua.lua_pushcfunction(L, getlocal);
    lua.lua_setfield(L, -1, "getlocal");

    // debug.getstack(L, level, ar)
    lua.lua_pushcfunction(L, getstack);
    lua.lua_setfield(L, -1, "getstack");

    // debug.getinfo(L, what, ar)
    lua.lua_pushcfunction(L, getinfo);
    lua.lua_setfield(L, -1, "getinfo");

    // debug.getupvalue(L, funcindex, n)
    lua.lua_pushcfunction(L, getupvalue);
    lua.lua_setfield(L, -1, "getupvalue");

    // debug.getuservalue(L, idx, n)
    lua.lua_pushcfunction(L, getuservalue);
    lua.lua_setfield(L, -1, "getuservalue");

    // debug.getmetatable(L, object)
    lua.lua_pushcfunction(L, getmetatable);
    lua.lua_setfield(L, -1, "getmetatable");

    // debug.getregistry(L)
    lua.lua_pushcfunction(L, getregistry);
    lua.lua_setfield(L, -1, "getregistry");

    // debug.getupvalueid(L, fidx, n)
    lua.lua_pushcfunction(L, getupvalueid);
    lua.lua_setfield(L, -1, "getupvalueid");

    // debug.sethook(L, func, mask, count)
    lua.lua_pushcfunction(L, sethook);
    lua.lua_setfield(L, -1, "sethook");

    // debug.setupvalue(L, funcindex, n)
    lua.lua_pushcfunction(L, setupvalue);
    lua.lua_setfield(L, -1, "setupvalue");
}

// ===================================================================
// Debug library function implementations
// ===================================================================

fn gethook(L: *lua_State) i32 {
    // Would return current hook function
    lua.lua_pushnil(L);
    return 1;
}

fn gethookcount(L: *lua_State) i32 {
    // Would return hook count
    lua.lua_pushinteger(L, 0);
    return 1;
}

fn gethookmask(L: *lua_State) i32 {
    // Would return hook mask
    lua.lua_pushinteger(L, 0);
    return 1;
}

fn getlocal(L: *lua_State) i32 {
    // Would return local variable name/value
    lua.lua_pushnil(L);
    return 1;
}

fn getstack(L: *lua_State) i32 {
    // Would return stack level
    lua.lua_pushnil(L);
    return 1;
}

fn getinfo(L: *lua_State) i32 {
    // Would return function info
    lua.lua_pushnil(L);
    return 1;
}

fn getupvalue(L: *lua_State) i32 {
    // Would return upvalue name/value
    lua.lua_pushnil(L);
    return 1;
}

fn getuservalue(L: *lua_State) i32 {
    // Would return userdata value
    lua.lua_pushnil(L);
    return 1;
}

fn getmetatable(L: *lua_State) i32 {
    // Would return metatable
    lua.lua_pushnil(L);
    return 1;
}

fn getregistry(L: *lua_State) i32 {
    // Would return registry table
    lua.lua_pushnil(L);
    return 1;
}

fn getupvalueid(L: *lua_State) i32 {
    // Would return upvalue id
    lua.lua_pushnil(L);
    return 1;
}

fn sethook(L: *lua_State) i32 {
    // Would set hook function
    return 0;
}

fn setupvalue(L: *lua_State) i32 {
    // Would set upvalue value
    return 0;
}
