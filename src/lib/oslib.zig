/*
** $Id: oslib.zig
** OS library for Zua (Zig port of Lua 5.5.1)
** See Copyright Notice in c_compat.zig
*/

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");

// ===================================================================
// OS library functions
// ===================================================================

pub fn openoslib(L: *lua_State) !void {
    // clock()
    lua.lua_pushcfunction(L, clock);
    lua.lua_setglobal(L, "clock");

    // date(format [, time])
    lua.lua_pushcfunction(L, date);
    lua.lua_setglobal(L, "date");

    // difftime(t1, t2)
    lua.lua_pushcfunction(L, difftime);
    lua.lua_setglobal(L, "difftime");

    // execute(cmd)
    lua.lua_pushcfunction(L, execute);
    lua.lua_setglobal(L, "execute");

    // exit(status [, close])
    lua.lua_pushcfunction(L, exit);
    lua.lua_setglobal(L, "exit");

    // getenv(name)
    lua.lua_pushcfunction(L, getenv);
    lua.lua_setglobal(L, "getenv");

    // remove(filename)
    lua.lua_pushcfunction(L, remove);
    lua.lua_setglobal(L, "remove");

    // rename(from, to)
    lua.lua_pushcfunction(L, rename);
    lua.lua_setglobal(L, "rename");

    // setlocale(category, locale)
    lua.lua_pushcfunction(L, setlocale);
    lua.lua_setglobal(L, "setlocale");

    // time(table)
    lua.lua_pushcfunction(L, time);
    lua.lua_setglobal(L, "time");

    // tmpname()
    lua.lua_pushcfunction(L, tmpname);
    lua.lua_setglobal(L, "tmpname");
}

// ===================================================================
// OS library function implementations
// ===================================================================

fn clock(L: *lua_State) i32 {
    lua.lua_pushnumber(L, @as(f64, @bitCast(@std.time.seconds()));
    return 1;
}

fn date(L: *lua_State) i32 {
    const format = luaL_checklstring(L, 1, null);
    if (format) |f| {
        const t = if (lua.lua_gettop(L) >= 2) {
            const t_val = lua.lua_tointeger(L, 2);
            if (t_val) |tv| @as(usize, @bitCast(tv.?))
            else @as(usize, @bitCast(std.time.seconds()))
        } else @as(usize, @bitCast(std.time.seconds()));

        // Simplified: would format date
        const date_str = std.fmt.fmtDate(.{}, .{ .year = 2026, .month = 7, .day = 10 });
        lua.lua_pushstring(L, date_str);
        return 1;
    }
    return 0;
}

fn difftime(L: *lua_State) i32 {
    const t1 = lua.lua_tointeger(L, 1);
    const t2 = lua.lua_tointeger(L, 2);
    if (t1 and t2) |v1| {
        lua.lua_pushnumber(L, @as(f64, @bitCast(@as(i64, v1.?) - @as(i64, v2.?))));
        return 1;
    }
    return 0;
}

fn execute(L: *lua_State) i32 {
    const cmd = luaL_checklstring(L, 1, null);
    if (cmd) |c| {
        // Simplified: would execute shell command
        lua.lua_pushnumber(L, 0);
        return 1;
    }
    return 0;
}

fn exit(L: *lua_State) i32 {
    const status = if (lua.lua_gettop(L) >= 1) {
        const s = lua.lua_tointeger(L, 1);
        s orelse 0
    } else 0;
    _ = status;
    // Would exit the program
    return 0;
}

fn getenv(L: *lua_State) i32 {
    const name = luaL_checklstring(L, 1, null);
    if (name) |n| {
        const val = std.posix.getenv(n);
        if (val) |v| {
            lua.lua_pushstring(L, v);
            return 1;
        }
    }
    lua.lua_pushnil(L);
    return 0;
}

fn remove(L: *lua_State) i32 {
    const filename = luaL_checklstring(L, 1, null);
    if (filename) |f| {
        std.fs.cwd().remove(f) catch {};
    }
    return 0;
}

fn rename(L: *lua_State) i32 {
    const from = luaL_checklstring(L, 1, null);
    const to = luaL_checklstring(L, 2, null);
    if (from and to) |f| {
        std.fs.cwd().rename(f, to) catch {};
    }
    return 0;
}

fn setlocale(L: *lua_State) i32 {
    const category = luaL_checklstring(L, 1, null);
    const locale = luaL_checklstring(L, 2, null);
    _ = category;
    _ = locale;
    // Simplified: would set locale
    return 0;
}

fn time(L: *lua_State) i32 {
    if (lua.lua_gettop(L) >= 1) {
        // Would create time table from table
    }
    const t = @as(usize, @bitCast(std.time.seconds()));
    lua.lua_pushinteger(L, @as(i64, @bitCast(t)));
    return 1;
}

fn tmpname(L: *lua_State) i32 {
    // Would generate temp filename
    const tmp = std.fs.getCwd().join("tmp_") catch "";
    lua.lua_pushstring(L, tmp);
    return 1;
}
