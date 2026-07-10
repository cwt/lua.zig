/*
** $Id: stringlib.zig
** String library for Zua (Zig port of Lua 5.5.1)
** See Copyright Notice in c_compat.zig
*/

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");

// ===================================================================
// String library functions
// ===================================================================

pub fn openstringlib(L: *lua_State) !void {
    // char(n1, n2, ...)
    lua.lua_pushcfunction(L, char);
    lua.lua_setfield(L, -1, "char");

    // charpattern
    lua.lua_pushstring(L, "[%u%U%Z%c%x%d%l%u]");
    lua.lua_setfield(L, -1, "charpattern");

    // byte(s [, i [, j]])
    lua.lua_pushcfunction(L, byte);
    lua.lua_setfield(L, -1, "byte");

    // dump(f [, strip])
    lua.lua_pushcfunction(L, dump);
    lua.lua_setfield(L, -1, "dump");

    // find(s, pattern [, init [, plain]])
    lua.lua_pushcfunction(L, find);
    lua.lua_setfield(L, -1, "find");

    // format(format, vararg)
    lua.lua_pushcfunction(L, format);
    lua.lua_setfield(L, -1, "format");

    // gsub(s, pattern, repl, n)
    lua.lua_pushcfunction(L, gsub);
    lua.lua_setfield(L, -1, "gsub");

    // len(s)
    lua.lua_pushcfunction(L, len);
    lua.lua_setfield(L, -1, "len");

    // lower(s)
    lua.lua_pushcfunction(L, lower);
    lua.lua_setfield(L, -1, "lower");

    // match(s, pattern [, init])
    lua.lua_pushcfunction(L, match);
    lua.lua_setfield(L, -1, "match");

    // rep(s, n [, sep])
    lua.lua_pushcfunction(L, rep);
    lua.lua_setfield(L, -1, "rep");

    // reverse(s)
    lua.lua_pushcfunction(L, reverse);
    lua.lua_setfield(L, -1, "reverse");

    // sub(s, i [, j])
    lua.lua_pushcfunction(L, sub);
    lua.lua_setfield(L, -1, "sub");

    // upper(s)
    lua.lua_pushcfunction(L, upper);
    lua.lua_setfield(L, -1, "upper");

    // gmatch(s, pattern)
    lua.lua_pushcfunction(L, gmatch);
    lua.lua_setfield(L, -1, "gmatch");
}

// ===================================================================
// String library function implementations
// ===================================================================

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

fn byte(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    if (s) |str| {
        var i: ?i64 = null;
        var j: ?i64 = null;
        while (lua.lua_next(L, 2) != 0) {
            i = lua.lua_tointeger(L, -1) orelse i;
            j = lua.lua_tointeger(L, -1) orelse j;
            lua.lua_pop(L, 1);
        }
        if (s) |str_ptr| {
            const start = if (i) |idx| @as(usize, @as(i32,(idx)) else 1;
            const end = if (j) |idx| @as(usize, @as(i32,(idx)) else str_ptr.len;
            if (start <= end and start <= str_ptr.len) {
                const bytes = str_ptr[start - 1 .. end];
                var result = "";
                var pos: usize = 0;
                while (pos < bytes.len and result.len < 256) : (pos += 1) {
                    result = result ++ std.fmt.fmtInt(u8, @as(i64, @bitCast(@as(usize, bytes[pos]))), .lower);
                }
                lua.lua_pushstring(L, result);
                return 1;
            }
        }
    }
    lua.lua_pushnil(L);
    return 0;
}

fn dump(L: *lua_State) i32 {
    if (!lua.lua_iscfunction(L, 1)) {
        return lua.lua_error(L);
    }
    const strip = if (lua.lua_gettop(L) >= 2) {
        const s = lua.lua_toboolean(L, 2);
        @as(i32, @as(i32,(s))
    } else 0;
    // Would dump function to string
    lua.lua_pushstring(L, "");
    return 1;
}

fn find(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    const pattern = luaL_checklstring(L, 2, null);
    if (s and pattern) |str| {
        const init = if (lua.lua_gettop(L) >= 3) {
            const i = luaL_checkinteger(L, 3);
            i orelse 1
        } else 1;
        // Simplified: would do pattern matching
        lua.lua_pushnil(L);
        return 2;
    }
    return 0;
}

fn format(L: *lua_State) i32 {
    const fmt = luaL_checklstring(L, 1, null);
    if (fmt) |f| {
        const args = if (lua.lua_gettop(L) >= 2) {
            const n = lua.lua_gettop(L) - 1;
        const base: [*]?TValue = @ptrCast(@alignCast(&L.stack));
        base[L.top .. @as(usize, L.top) + n]
        } else [_]TValue{}:{};
        // Simplified: would format string with arguments
        lua.lua_pushstring(L, f);
        return 1;
    }
    return 0;
}

fn gsub(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    const pattern = luaL_checklstring(L, 2, null);
    const repl = luaL_checklstring(L, 3, null);
    if (s and pattern and repl) |str| {
        const n = if (lua.lua_gettop(L) >= 4) {
            const n_val = luaL_checkinteger(L, 4);
            n_val orelse -1
        } else -1;
        // Simplified: would do global substitution
        lua.lua_pushstring(L, str);
        return 1;
    }
    return 0;
}

fn len(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    if (s) |str| {
        lua.lua_pushinteger(L, @as(i64, str.len));
        return 1;
    }
    return 0;
}

fn lower(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    if (s) |str| {
        const lower = std.mem.toLowerCase(u8, str);
        lua.lua_pushstring(L, lower);
        return 1;
    }
    return 0;
}

fn match(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    const pattern = luaL_checklstring(L, 2, null);
    if (s and pattern) |str| {
        const init = if (lua.lua_gettop(L) >= 3) {
            const i = luaL_checkinteger(L, 3);
            i orelse 1
        } else 1;
        // Simplified: would do pattern matching
        lua.lua_pushnil(L);
        return 0;
    }
    return 0;
}

fn rep(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    const n = luaL_checkinteger(L, 2);
    if (s and n) |str| {
        const count = @as(usize, @as(i32,(n));
        var result = "";
        var i: usize = 0;
        while (i < count) : (i += 1) {
            if (i > 0) {
                const sep = luaL_checklstring(L, 3, null);
                if (sep) |sep_str| {
                    result = result ++ sep_str;
                }
            }
            result = result ++ str;
        }
        lua.lua_pushstring(L, result);
        return 1;
    }
    return 0;
}

fn reverse(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    if (s) |str| {
        const reversed = std.mem.reverse(u8, str);
        lua.lua_pushstring(L, reversed);
        return 1;
    }
    return 0;
}

fn sub(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    const i = luaL_checkinteger(L, 2);
    if (s) |str| {
        const start = @as(usize, @as(i32,(i));
        const end = if (lua.lua_gettop(L) >= 3) {
            const e = luaL_checkinteger(L, 3);
            @as(usize, @as(i32,(e))
        } else str.len;
        if (start <= end and start <= str.len and end <= str.len) {
            lua.lua_pushstring(L, str[start..end]);
            return 1;
        }
    }
    lua.lua_pushnil(L);
    return 0;
}

fn upper(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    if (s) |str| {
        const upper = std.mem.toUpperCase(u8, str);
        lua.lua_pushstring(L, upper);
        return 1;
    }
    return 0;
}

fn gmatch(L: *lua_State) i32 {
    const s = luaL_checklstring(L, 1, null);
    const pattern = luaL_checklstring(L, 2, null);
    if (s and pattern) |str| {
        // Simplified: would iterate over all matches
        lua.lua_pushnil(L);
        return 1;
    }
    return 0;
}
