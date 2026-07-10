/*
** $Id: utf8lib.zig
** UTF-8 library for Zua (Zig port of Lua 5.5.1)
** See Copyright Notice in c_compat.zig
*/

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");

// ===================================================================
// UTF-8 library functions
// ===================================================================

pub fn openutf8lib(L: *lua_State) !void {
    // utf8.charpattern
    lua.lua_pushstring(L, "[%c%u%U%Z%c%x%d%l%u]");
    lua.lua_setfield(L, -1, "charpattern");

    // utf8.byteoffset(s, n [, i])
    lua.lua_pushcfunction(L, byteoffset);
    lua.lua_setfield(L, -1, "byteoffset");

    // utf8.codepoint(s [, i [, j [, lax]]])
    lua.lua_pushcfunction(L, codepoint);
    lua.lua_setfield(L, -1, "codepoint");

    // utf8.len(s [, i [, j [, lax]]])
    lua.lua_pushcfunction(L, len);
    lua.lua_setfield(L, -1, "len");

    // utf8.offset(s, n [, i])
    lua.lua_pushcfunction(L, offset);
    lua.lua_setfield(L, -1, "offset");

    // utf8.char(n1, n2, ...)
    lua.lua_pushcfunction(L, char);
    lua.lua_setfield(L, -1, "char");

    // utf8.codes(s)
    lua.lua_pushcfunction(L, codes);
    lua.lua_setfield(L, -1, "codes");
}

// ===================================================================
// UTF-8 library function implementations
// ===================================================================

fn byteoffset(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    const n = luaL_checkinteger(L, 2);
    if (s and n) |str| {
        const start = if (lua.lua_gettop(L) >= 3) {
            const i = luaL_checkinteger(L, 3);
            i orelse 1
        } else 1;
        // Simplified: would compute byte offset for n-th character
        lua.lua_pushinteger(L, @as(i64, @bitCast(start)));
        return 1;
    }
    return 0;
}

fn codepoint(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    if (s) |str| {
        const i = if (lua.lua_gettop(L) >= 2) {
            const iv = luaL_checkinteger(L, 2);
            iv orelse 1
        } else 1;
        // Simplified: would return codepoint
        lua.lua_pushinteger(L, @as(i64, @bitCast(str[i - 1] orelse 0)));
        return 1;
    }
    return 0;
}

fn len(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    if (s) |str| {
        const i = if (lua.lua_gettop(L) >= 2) {
            const iv = luaL_checkinteger(L, 2);
            iv orelse 1
        } else 1;
        const j = if (lua.lua_gettop(L) >= 3) {
            const jv = luaL_checkinteger(L, 3);
            jv orelse str.len
        } else str.len;
        // Simplified: would count characters
        lua.lua_pushinteger(L, @as(i64, @bitCast(j - i + 1)));
        return 1;
    }
    return 0;
}

fn offset(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    const n = luaL_checkinteger(L, 2);
    if (s and n) |str| {
        const start = if (lua.lua_gettop(L) >= 3) {
            const i = luaL_checkinteger(L, 3);
            i orelse 1
        } else 1;
        // Simplified: would compute character offset
        lua.lua_pushinteger(L, @as(i64, @bitCast(start)));
        return 1;
    }
    return 0;
}

fn char(L: *lua_State) i32 {
    var n: ?i64 = null;
    while (lua.lua_next(L, 2) != 0) {
        n = lua.lua_tointeger(L, -1) orelse n;
        lua.lua_pop(L, 1);
    }
    if (n) |val| {
        const ch = std.fmt.fmtInt(u8, val, .lower);
        if (ch) |s| {
            lua.lua_pushstring(L, s);
            return 1;
        }
    }
    lua.lua_pushnil(L);
    return 0;
}

fn codes(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    if (s) |str| {
        // Simplified: would iterate over codepoints
        lua.lua_pushnil(L);
        return 1;
    }
    return 0;
}
