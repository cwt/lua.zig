/*
** $Id: bit32.zig
** Bit32 library for Zua (Zig port of Lua 5.5.1)
** See Copyright Notice in c_compat.zig
*/

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");

// ===================================================================
// Bit32 library functions
// ===================================================================

pub fn openbit32(L: *lua_State) !void {
    // band(x, y)
    lua.lua_pushcfunction(L, band);
    lua.lua_setfield(L, -1, "band");

    // bor(x, y)
    lua.lua_pushcfunction(L, bor);
    lua.lua_setfield(L, -1, "bor");

    // bxor(x, y)
    lua.lua_pushcfunction(L, bxor);
    lua.lua_setfield(L, -1, "bxor");

    // bnot(x)
    lua.lua_pushcfunction(L, bnot);
    lua.lua_setfield(L, -1, "bnot");

    // shl(x, y)
    lua.lua_pushcfunction(L, shl);
    lua.lua_setfield(L, -1, "shl");

    // shr(x, y)
    lua.lua_pushcfunction(L, shr);
    lua.lua_setfield(L, -1, "shr");

    // btest(x, y)
    lua.lua_pushcfunction(L, btest);
    lua.lua_setfield(L, -1, "btest");

    // bandi(x, y)
    lua.lua_pushcfunction(L, bandi);
    lua.lua_setfield(L, -1, "bandi");

    // bori(x, y)
    lua.lua_pushcfunction(L, bori);
    lua.lua_setfield(L, -1, "bori");

    // bxori(x, y)
    lua.lua_pushcfunction(L, bxori);
    lua.lua_setfield(L, -1, "bxori");

    // bori(x, y)
    lua.lua_pushcfunction(L, bor);
    lua.lua_setfield(L, -1, "bori");

    // bxori(x, y)
    lua.lua_pushcfunction(L, bxor);
    lua.lua_setfield(L, -1, "bxori");

    // band(x, y)
    lua.lua_pushcfunction(L, band);
    lua.lua_setfield(L, -1, "bandi");

    // bor(x, y)
    lua.lua_pushcfunction(L, bor);
    lua.lua_setfield(L, -1, "bori");

    // bxor(x, y)
    lua.lua_pushcfunction(L, bxor);
    lua.lua_setfield(L, -1, "bxori");

    // lshift(x, y)
    lua.lua_pushcfunction(L, shl);
    lua.lua_setfield(L, -1, "lshift");

    // rshift(x, y)
    lua.lua_pushcfunction(L, shr);
    lua.lua_setfield(L, -1, "rshift");

    // arshift(x, y)
    lua.lua_pushcfunction(L, shr);
    lua.lua_setfield(L, -1, "arshift");
}

// ===================================================================
// Bit32 library function implementations
// ===================================================================

fn band(L: *lua_State) i32 {
    const x = lua.lua_tointeger(L, 1);
    const y = lua.lua_tointeger(L, 2);
    if (x and y) |vx| {
        lua.lua_pushinteger(L, @as(i64, @bitAnd(vx, y.?)));
        return 1;
    }
    return 0;
}

fn bor(L: *lua_State) i32 {
    const x = lua.lua_tointeger(L, 1);
    const y = lua.lua_tointeger(L, 2);
    if (x and y) |vx| {
        lua.lua_pushinteger(L, @as(i64, @bitOr(vx, y.?)));
        return 1;
    }
    return 0;
}

fn bxor(L: *lua_State) i32 {
    const x = lua.lua_tointeger(L, 1);
    const y = lua.lua_tointeger(L, 2);
    if (x and y) |vx| {
        lua.lua_pushinteger(L, @as(i64, @bitXor(vx, y.?)));
        return 1;
    }
    return 0;
}

fn bnot(L: *lua_State) i32 {
    const x = lua.lua_tointeger(L, 1);
    if (x) |vx| {
        lua.lua_pushinteger(L, @as(i64, ~vx));
        return 1;
    }
    return 0;
}

fn shl(L: *lua_State) i32 {
    const x = lua.lua_tointeger(L, 1);
    const n = lua.lua_tointeger(L, 2);
    if (x and n) |vx| {
        lua.lua_pushinteger(L, @as(i64, @bitShiftLeft(vx, @as(i32, @as(i32,(n.?))));
        return 1;
    }
    return 0;
}

fn shr(L: *lua_State) i32 {
    const x = lua.lua_tointeger(L, 1);
    const n = lua.lua_tointeger(L, 2);
    if (x and n) |vx| {
        lua.lua_pushinteger(L, @as(i64, @bitShiftRight(vx, @as(i32, @as(i32,(n.?))));
        return 1;
    }
    return 0;
}

fn btest(L: *lua_State) i32 {
    const x = lua.lua_tointeger(L, 1);
    const y = lua.lua_tointeger(L, 2);
    if (x and y) |vx| {
        lua.lua_pushboolean(L, @bitAnd(vx, y.?) != 0);
        return 1;
    }
    return 0;
}

fn bandi(L: *lua_State) i32 {
    const x = lua.lua_tointeger(L, 1);
    const y = lua.lua_tointeger(L, 2);
    if (x and y) |vx| {
        lua.lua_pushinteger(L, @as(i64, @bitAnd(vx, y.?)));
        return 1;
    }
    return 0;
}

fn bori(L: *lua_State) i32 {
    const x = lua.lua_tointeger(L, 1);
    const y = lua.lua_tointeger(L, 2);
    if (x and y) |vx| {
        lua.lua_pushinteger(L, @as(i64, @bitOr(vx, y.?)));
        return 1;
    }
    return 0;
}

fn bxori(L: *lua_State) i32 {
    const x = lua.lua_tointeger(L, 1);
    const y = lua.lua_tointeger(L, 2);
    if (x and y) |vx| {
        lua.lua_pushinteger(L, @as(i64, @bitXor(vx, y.?)));
        return 1;
    }
    return 0;
}
