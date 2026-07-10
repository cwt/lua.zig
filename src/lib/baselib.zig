/*
** $Id: baselib.zig
** Base library for Zua (Zig port of Lua 5.5.1)
** See Copyright Notice in c_compat.zig
*/

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");

// ===================================================================
// Base library functions
// ===================================================================

pub fn openbaselib(L: *lua_State) !void {
    // Register base library functions in _G table

    // assert(cond [, message])
    lua.lua_pushcfunction(L, assert);
    lua.lua_setglobal(L, "assert");

    // collectgarbage(option [, vararg])
    lua.lua_pushcfunction(L, collectgarbage);
    lua.lua_setglobal(L, "collectgarbage");

    // dofile(filename)
    lua.lua_pushcfunction(L, dofile);
    lua.lua_setglobal(L, "dofile");

    // error(message [, level])
    lua.lua_pushcfunction(L, error);
    lua.lua_setglobal(L, "error");

    // getmetatable(object)
    lua.lua_pushcfunction(L, getmetatable);
    lua.lua_setglobal(L, "getmetatable");

    // ipairs(table)
    lua.lua_pushcfunction(L, ipairs);
    lua.lua_setglobal(L, "ipairs");

    // loadfile(filename [, mode])
    lua.lua_pushcfunction(L, loadfile);
    lua.lua_setglobal(L, "loadfile");

    // load(file [, chunkname [, mode [, env]]])
    lua.lua_pushcfunction(L, load);
    lua.lua_setglobal(L, "load");

    // next(table [, index])
    lua.lua_pushcfunction(L, next);
    lua.lua_setglobal(L, "next");

    // pairs(table)
    lua.lua_pushcfunction(L, pairs);
    lua.lua_setglobal(L, "pairs");

    // pcall(function, vararg)
    lua.lua_pushcfunction(L, pcall);
    lua.lua_setglobal(L, "pcall");

    // print(vararg)
    lua.lua_pushcfunction(L, print);
    lua.lua_setglobal(L, "print");

    // warn(vararg)
    lua.lua_pushcfunction(L, warn);
    lua.lua_setglobal(L, "warn");

    // rawequal(x, y)
    lua.lua_pushcfunction(L, rawequal);
    lua.lua_setglobal(L, "rawequal");

    // rawlen(v)
    lua.lua_pushcfunction(L, rawlen);
    lua.lua_setglobal(L, "rawlen");

    // rawget(table, key)
    lua.lua_pushcfunction(L, rawget);
    lua.lua_setglobal(L, "rawget");

    // rawset(table, key, value)
    lua.lua_pushcfunction(L, rawset);
    lua.lua_setglobal(L, "rawset");

    // select(index_or_# [, vararg])
    lua.lua_pushcfunction(L, select);
    lua.lua_setglobal(L, "select");

    // setmetatable(table, metatable)
    lua.lua_pushcfunction(L, setmetatable);
    lua.lua_setglobal(L, "setmetatable");

    // tonumber(v [, base])
    lua.lua_pushcfunction(L, tonumber);
    lua.lua_setglobal(L, "tonumber");

    // tostring(v)
    lua.lua_pushcfunction(L, tostring);
    lua.lua_setglobal(L, "tostring");

    // type(v)
    lua.lua_pushcfunction(L, type);
    lua.lua_setglobal(L, "type");

    // xpcall(function, errfunc, vararg)
    lua.lua_pushcfunction(L, xpcall);
    lua.lua_setglobal(L, "xpcall");
}

// ===================================================================
// Base library function implementations
// ===================================================================

fn assert(L: *lua_State) i32 {
    if (lua.lua_toboolean(L, 1) == 0) {
        const msg = if (lua.lua_gettop(L) >= 2) {
            const m = lua.lua_tolstring(L, 2, null);
            if (m) |s| s else "assertion failed!"
        } else "assertion failed!";
        lua.lua_pushstring(L, msg);
        return lua.lua_error(L);
    }
    return 0;
}

fn collectgarbage(L: *lua_State) i32 {
    const option = luaL_checkoption(L, 1, "", .{ "stop", "restart", "collect", "count", "step", "isrunning", "generational", "incremental", "param" });
    switch (option) {
        0 => { // stop
            // Would stop GC
        },
        1 => { // restart
            // Would restart GC
        },
        2 => { // collect
            // Would collect GC
        },
        3 => { // count
            // Would return GC count
            lua.lua_pushnumber(L, 0);
            return 1;
        },
        4 => { // step
            // Would step GC
        },
        5 => { // isrunning
            lua.lua_pushboolean(L, 0);
            return 1;
        },
        6 => { // generational
            // Would toggle generational mode
        },
        7 => { // incremental
            // Would toggle incremental mode
        },
        8 => { // param
            // Would set GC parameter
        },
    }
    return 0;
}

fn dofile(L: *lua_State) i32 {
    const filename = luaL_checklstring(L, 1, null);
    const mode = if (lua.lua_gettop(L) >= 2) {
        const m = luaL_checklstring(L, 2, null);
        m orelse ""
    } else "";
    const status = lua.lua_load(L, null, null, filename, mode);
    if (status == lua.LUA_OK) {
        const f = lua.lua_tothread(L, -1);
        if (f) |thread| {
            lua.lua_pushvalue(L, -1);
            lua.lua_pushvalue(L, -2);
            lua.lua_xmove(L, thread, 2);
            lua.lua_pcallk(L);
            lua.lua_pop(L, 1);
        }
    }
    return 0;
}

fn error(L: *lua_State) i32 {
    const msg = lua.lua_tolstring(L, 1, null);
    if (msg) |m| {
        std.debug.print("error: {s}\n", .{m});
    }
    return lua.LUA_ERRRUN;
}

fn getmetatable(L: *lua_State) i32 {
    if (lua.lua_gettop(L) != 1) {
        return lua.lua_error(L);
    }
    if (lua.lua_getmetatable(L, 1) == 0) {
        lua.lua_pushnil(L);
    }
    return 1;
}

fn ipairs(L: *lua_State) i32 {
    if (!lua.lua_istable(L, 1)) {
        return lua.lua_error(L);
    }
    lua.lua_pushnil(L);
    return 1;
}

fn loadfile(L: *lua_State) i32 {
    const filename = luaL_checklstring(L, 1, null);
    const mode = if (lua.lua_gettop(L) >= 2) {
        const m = luaL_checklstring(L, 2, null);
        m orelse ""
    } else "";
    const status = lua.lua_load(L, null, null, filename, mode);
    return status;
}

fn load(L: *lua_State) i32 {
    const chunk = luaL_checklstring(L, 1, null);
    const chunkname = if (lua.lua_gettop(L) >= 2) {
        luaL_checklstring(L, 2, null) orelse ""
    } else "";
    const mode = if (lua.lua_gettop(L) >= 3) {
        luaL_checklstring(L, 3, null) orelse ""
    } else "";
    const env = if (lua.lua_gettop(L) >= 4) {
        lua.lua_touserdata(L, 4)
    } else null;
    const status = lua.lua_load(L, null, env, chunkname, mode);
    return status;
}

fn next(L: *lua_State) i32 {
    if (!lua.lua_istable(L, 1)) {
        return lua.lua_error(L);
    }
    if (lua.lua_gettop(L) < 2) {
        lua.lua_pushnil(L);
    }
    return lua.lua_next(L, 1);
}

fn pairs(L: *lua_State) i32 {
    if (!lua.lua_istable(L, 1)) {
        return lua.lua_error(L);
    }
    if (lua.lua_gettop(L) < 2) {
        lua.lua_pushnil(L);
    }
    return 1;
}

fn pcall(L: *lua_State) i32 {
    if (lua.lua_gettop(L) < 1) {
        return lua.lua_error(L);
    }
    const func = lua.lua_tocfunction(L, 1);
    const nargs = lua.lua_gettop(L) - 1;
    const status = lua.lua_pcallk(L);
    return status;
}

fn print(L: *lua_State) i32 {
    const io = lua.lua_touserdata(L, 1);
    if (io) |out| {
        while (lua.lua_next(L, 2) != 0) {
            const val = lua.lua_tostring(L, -1);
            if (val) |v| {
                io.out.writeAll(v) catch {};
                io.out.writeAll(" ") catch {};
            }
            lua.lua_pop(L, 1);
        }
    } else {
        // Use stdout
        std.io.getStdOut().writer().print("{s}\n", .{}) catch {};
    }
    return 0;
}

fn warn(L: *lua_State) i32 {
    const msg = lua.lua_tolstring(L, 1, null);
    if (msg) |m| {
        std.debug.print("warning: {s}\n", .{m});
    }
    return 0;
}

fn rawequal(L: *lua_State) i32 {
    if (lua.lua_gettop(L) != 2) {
        return lua.lua_error(L);
    }
    const result = lua.lua_rawequal(L, 1, 2);
    lua.lua_pushboolean(L, result == 1);
    return 1;
}

fn rawlen(L: *lua_State) i32 {
    if (!lua.lua_istable(L, 1) and !lua.lua_isstring(L, 1)) {
        return lua.lua_error(L);
    }
    const len = lua.lua_rawlen(L, 1);
    lua.lua_pushinteger(L, @as(i64, @bitCast(len)));
    return 1;
}

fn rawget(L: *lua_State) i32 {
    if (!lua.lua_istable(L, 1)) {
        return lua.lua_error(L);
    }
    return lua.lua_rawget(L, 2);
}

fn rawset(L: *lua_State) i32 {
    if (!lua.lua_istable(L, 1)) {
        return lua.lua_error(L);
    }
    return 0;
}

fn select(L: *lua_State) i32 {
    const index = luaL_checkoption(L, 1, "", .{ "#", "c", "r", "n", "t" });
    switch (index) {
        0 => { // #
            if (!lua.lua_istable(L, 2)) {
                return lua.lua_error(L);
            }
            const len = lua.lua_rawlen(L, 2);
            lua.lua_pushinteger(L, @as(i64, @bitCast(len)));
        },
        1 => { // c
            // Would return count of results
        },
        2 => { // r
            // Would return results
        },
        3 => { // n
            // Would return number of results
        },
        4 => { // t
            // Would return tail info
        },
    }
    return 0;
}

fn setmetatable(L: *lua_State) i32 {
    if (lua.lua_gettop(L) != 2) {
        return lua.lua_error(L);
    }
    if (!lua.lua_istable(L, 1)) {
        return lua.lua_error(L);
    }
    // Would set metatable
    return 0;
}

fn tonumber(L: *lua_State) i32 {
    const base = if (lua.lua_gettop(L) >= 2) {
        const b = lua.lua_tointeger(L, 2);
        if (b) |n| @as(i32, @as(i32,(n))
        else 10
    } else 10;
    const s = luaL_checklstring(L, 1, null);
    if (s) |str| {
        const result = std.fmt.parseInt(f64, str, base) catch null;
        if (result) |r| {
            lua.lua_pushnumber(L, r);
            return 1;
        }
    }
    lua.lua_pushnil(L);
    return 0;
}

fn tostring(L: *lua_State) i32 {
    const val = lua.lua_tolstring(L, 1, null);
    if (val) |v| {
        lua.lua_pushstring(L, v);
        return 1;
    }
    return 0;
}

fn type(L: *lua_State) i32 {
    const t = lua.lua_type(L, 1);
    const name = switch (t) {
        lua.LUA_TNIL => "nil",
        lua.LUA_TBOOLEAN => "boolean",
        lua.LUA_TLIGHTUSERDATA => "light userdata",
        lua.LUA_TNUMBER => "number",
        lua.LUA_TSTRING => "string",
        lua.LUA_TTABLE => "table",
        lua.LUA_TFUNCTION => "function",
        lua.LUA_TUSERDATA => "userdata",
        lua.LUA_TTHREAD => "thread",
        else => "unknown",
    };
    lua.lua_pushstring(L, name);
    return 1;
}

fn xpcall(L: *lua_State) i32 {
    if (lua.lua_gettop(L) < 2) {
        return lua.lua_error(L);
    }
    const func = lua.lua_tocfunction(L, 1);
    const errfunc = lua.lua_tocfunction(L, 2);
    const nargs = lua.lua_gettop(L) - 2;
    const status = lua.lua_pcallk(L);
    return status;
}
