/*
** $Id: loadlib.zig
** Load library functionality for Zua (Zig port of Lua 5.5.1)
** See Copyright Notice in c_compat.zig
*/

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");

// ===================================================================
// Load library functions
// ===================================================================

pub fn openloadlib(L: *lua_State) !void {
    // package.loadlib(path, init)
    lua.lua_pushcfunction(L, loadlib);
    lua.lua_setfield(L, -1, "loadlib");

    // package.searchpath(name, path [, sep [, dirsep]])
    lua.lua_pushcfunction(L, searchpath);
    lua.lua_setfield(L, -1, "searchpath");
}

// ===================================================================
// Load library function implementations
// ===================================================================

fn loadlib(L: *lua_State) i32 {
    const path = luaL_checklstring(L, 1, null);
    const init = luaL_checklstring(L, 2, null);
    if (path and init) |p| {
        // Would load dynamic library and return function
        lua.lua_pushnil(L);
        return 1;
    }
    return 0;
}

fn searchpath(L: *lua_State) i32 {
    const name = luaL_checklstring(L, 1, null);
    const path = luaL_checklstring(L, 2, null);
    if (name and path) |n| {
        // Would search for file on path
        lua.lua_pushnil(L);
        return 1;
    }
    return 0;
}
