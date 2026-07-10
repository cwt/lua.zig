/*
** $Id: tablib.zig
** Table library for Zua (Zig port of Lua 5.5.1)
** See Copyright Notice in c_compat.zig
*/

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");

// ===================================================================
// Table library functions
// ===================================================================

pub fn opentablib(L: *lua_State) !void {
    // table.concat(t [, sep [, i [, j]]])
    lua.lua_pushcfunction(L, concat);
    lua.lua_setfield(L, -1, "concat");

    // table.create(arraysize [, hashsize])
    lua.lua_pushcfunction(L, create);
    lua.lua_setfield(L, -1, "create");

    // table.insert(t, val [, pos])
    lua.lua_pushcfunction(L, insert);
    lua.lua_setfield(L, -1, "insert");

    // table.pack(vararg)
    lua.lua_pushcfunction(L, pack);
    lua.lua_setfield(L, -1, "pack");

    // table.unpack(t [, i [, j]])
    lua.lua_pushcfunction(L, unpack);
    lua.lua_setfield(L, -1, "unpack");

    // table.remove(t [, pos])
    lua.lua_pushcfunction(L, remove);
    lua.lua_setfield(L, -1, "remove");

    // table.move(t, f, e, t, to)
    lua.lua_pushcfunction(L, move);
    lua.lua_setfield(L, -1, "move");

    // table.sort(t [, comp])
    lua.lua_pushcfunction(L, sort);
    lua.lua_setfield(L, -1, "sort");
}

// ===================================================================
// Table library function implementations
// ===================================================================

fn concat(L: *lua_State) i32 {
    if (!lua.lua_istable(L, 1)) {
        return lua.lua_error(L);
    }
    const sep = if (lua.lua_gettop(L) >= 2) {
        const s = luaL_checklstring(L, 2, null);
        s orelse ""
    } else "";
    const i = if (lua.lua_gettop(L) >= 3) {
        const iv = luaL_checkinteger(L, 3);
        iv orelse 1
    } else 1;
    const j = if (lua.lua_gettop(L) >= 4) {
        const jv = luaL_checkinteger(L, 4);
        jv orelse lua.lua_rawlen(L, 1)
    } else lua.lua_rawlen(L, 1);
    // Simplified: would concatenate table elements
    lua.lua_pushstring(L, "");
    return 1;
}

fn create(L: *lua_State) i32 {
    const arrsize = luaL_checkinteger(L, 1);
    const hashsize = if (lua.lua_gettop(L) >= 2) {
        luaL_checkinteger(L, 2) orelse arrsize
    } else arrsize;
    // Would preallocate table
    lua.lua_pushstring(L, "");
    return 1;
}

fn insert(L: *lua_State) i32 {
    if (!lua.lua_istable(L, 1)) {
        return lua.lua_error(L);
    }
    const pos = if (lua.lua_gettop(L) >= 3) {
        const p = luaL_checkinteger(L, 3);
        p orelse @as(i64, @bitCast(lua.lua_rawlen(L, 1) + 1))
    } else @as(i64, @bitCast(lua.lua_rawlen(L, 1) + 1));
    // Would insert element at position
    return 0;
}

fn pack(L: *lua_State) i32 {
    const nargs = lua.lua_gettop(L);
    if (nargs > 0) {
        const base: [*]?TValue = @ptrCast(@alignCast(&L.stack));
        @memcpy(base[L.top .. @as(usize, L.top) + nargs], base[0..nargs]);
        lua.lua_newtable(L);
        const tbl = @ptrCast(@as(usize, L.top));
        var i: i32 = 1;
        while (i <= nargs) : (i += 1) {
            lua.lua_rawseti(L, -1, @as(i64, @bitCast(i)));
        }
        L.top = L.top + 1;
    }
    return 1;
}

fn unpack(L: *lua_State) i32 {
    if (!lua.lua_istable(L, 1)) {
        return lua.lua_error(L);
    }
    const i = if (lua.lua_gettop(L) >= 2) {
        const iv = luaL_checkinteger(L, 2);
        iv orelse 1
    } else 1;
    const j = if (lua.lua_gettop(L) >= 3) {
        const jv = luaL_checkinteger(L, 3);
        jv orelse lua.lua_rawlen(L, 1)
    } else lua.lua_rawlen(L, 1);
    // Would unpack table elements
    return nargs;
}

fn remove(L: *lua_State) i32 {
    if (!lua.lua_istable(L, 1)) {
        return lua.lua_error(L);
    }
    const pos = if (lua.lua_gettop(L) >= 2) {
        const p = luaL_checkinteger(L, 2);
        p orelse @as(i64, @bitCast(lua.lua_rawlen(L, 1)))
    } else @as(i64, @bitCast(lua.lua_rawlen(L, 1)));
    // Would remove element at position
    return 1;
}

fn move(L: *lua_State) i32 {
    if (!lua.lua_istable(L, 1)) {
        return lua.lua_error(L);
    }
    const f = luaL_checkinteger(L, 2);
    const e = luaL_checkinteger(L, 3);
    const t = luaL_checkinteger(L, 4);
    const to = luaL_checkinteger(L, 5);
    // Would move slice of table
    return 0;
}

fn sort(L: *lua_State) i32 {
    if (!lua.lua_istable(L, 1)) {
        return lua.lua_error(L);
    }
    const comp = if (lua.lua_gettop(L) >= 2) {
        const c = lua.lua_iscfunction(L, 2);
        c
    } else false;
    // Would sort table
    return 0;
}
