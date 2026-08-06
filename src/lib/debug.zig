// $Id: debug.zig
// Debug library for Zua (Zig port of Lua 5.5.0)
// See Copyright Notice in c_compat.zig

const std = @import("std");
const lua = @import("../lua.zig");
const lauxlib = @import("../lauxlib.zig");
const llimits = @import("../llimits.zig");

// ===================================================================
// Helpers
// ===================================================================

const HOOKKEY = "_HOOKKEY";

/// Return the target thread and argument offset.
/// If arg 1 is a thread, returns it with offset 1.
/// Otherwise returns the calling thread with offset 0.
fn getthread(L: *lua.lua_State, arg: *i32) *lua.lua_State {
    if (lua.lua_type(L, 1) == lua.LUA_TTHREAD) {
        arg.* = 1;
        return lua.lua_tothread(L, 1).?;
    } else {
        arg.* = 0;
        return L;
    }
}

// ===================================================================
// Debug library function implementations
// ===================================================================

fn db_getregistry(L: *lua.lua_State) !i32 {
    lua.lua_pushvalue(L, lua.LUA_REGISTRYINDEX);
    return 1;
}

fn db_getmetatable(L: *lua.lua_State) !i32 {
    try lauxlib.luaL_checkany(L, 1);
    if (lua.lua_getmetatable(L, 1) == 0) {
        lua.lua_pushnil(L);
    }
    return 1;
}

fn db_setmetatable(L: *lua.lua_State) !i32 {
    const t = lua.lua_type(L, 2);
    if (t != lua.LUA_TNIL and t != lua.LUA_TTABLE) {
        return lauxlib.luaL_argerror(L, 2, "nil or table expected");
    }
    lua.lua_settop(L, 2);
    _ = lua.lua_setmetatable(L, 1);
    return 1;
}

fn db_getuservalue(L: *lua.lua_State) !i32 {
    const n = @as(i32, @intCast(lauxlib.luaL_optinteger(L, 2, 1)));
    if (lua.lua_type(L, 1) != lua.LUA_TUSERDATA) {
        lua.lua_pushnil(L);
    } else if (lua.lua_getiuservalue(L, 1, n) != -1) {
        lua.lua_pushboolean(L, 1);
        return 2;
    }
    return 1;
}

fn db_setuservalue(L: *lua.lua_State) !i32 {
    const n = @as(i32, @intCast(lauxlib.luaL_optinteger(L, 3, 1)));
    try lauxlib.luaL_checktype(L, 1, lua.LUA_TUSERDATA);
    try lauxlib.luaL_checkany(L, 2);
    lua.lua_settop(L, 2);
    if (lua.lua_setiuservalue(L, 1, n) == 0) {
        lua.lua_pushnil(L);
    }
    return 1;
}

/// The hook Zig function that calls back into Lua
fn hookf(L1: *lua.lua_State, ar: ?*lua.lua_Debug) void {
    _ = lua.lua_getfield(L1, lua.LUA_REGISTRYINDEX, HOOKKEY) catch return;
    if (lua.lua_type(L1, -1) == lua.LUA_TTABLE) {
        lua.lua_pushlightuserdata(L1, L1);
        _ = lua.lua_gettable(L1, -2) catch {
            lua.lua_pop(L1, 2);
            return;
        };
        const val_type = lua.lua_type(L1, -1);
        if (val_type == lua.LUA_TFUNCTION) {
            const event_str: []const u8 = if (ar != null) switch (ar.?.event) {
                lua.LUA_HOOKCALL => "call",
                lua.LUA_HOOKRET => "return",
                lua.LUA_HOOKLINE => "line",
                lua.LUA_HOOKCOUNT => "count",
                else => "tail call",
            } else "unknown";
            _ = lua.lua_pushstring(L1, event_str);
            if (ar != null and ar.?.event == lua.LUA_HOOKLINE) {
                if (ar.?.currentline >= 0) {
                    lua.lua_pushinteger(L1, ar.?.currentline);
                } else {
                    lua.lua_pushnil(L1);
                }
            } else {
                lua.lua_pushnil(L1);
            }
            const status = lua.lua_pcall(L1, 2, 0, 0);
            if (status != 0) {
                lua.lua_pop(L1, 1);
            }
        } else {
            lua.lua_pop(L1, 1);
        }
    }
    lua.lua_pop(L1, 1);
}

fn db_sethook(L: *lua.lua_State) !i32 {
    var arg: i32 = undefined;
    const L1 = getthread(L, &arg);

    var mask: u32 = 0;
    var count: i32 = 0;
    var func: ?lua.lua_Hook = null;

    // sethook(L, nil) or sethook(nil) removes hook
    if (lua.lua_isnone(L, arg + 1) != 0 or lua.lua_isnil(L, arg + 1) != 0) {
        lua.lua_settop(L, arg);
    } else {
        const mask_str = try lauxlib.luaL_checkstring(L, arg + 2);
        count = @as(i32, @intCast(lauxlib.luaL_optinteger(L, arg + 3, 0)));
        try lauxlib.luaL_checktype(L, arg + 1, lua.LUA_TFUNCTION);

        for (mask_str) |c| {
            switch (c) {
                'c' => mask |= lua.LUA_MASKCALL,
                'r' => mask |= lua.LUA_MASKRET,
                'l' => mask |= lua.LUA_MASKLINE,
                else => {},
            }
        }
        if (count > 0) {
            mask |= lua.LUA_MASKCOUNT;
        }
        func = hookf;
    }

    // Store the Lua function in the registry table keyed by thread pointer
    _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, HOOKKEY);
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        lua.lua_pop(L, 1);
        lua.lua_createtable(L, 0, 0);
        lua.lua_createtable(L, 0, 1);
        _ = lua.lua_pushstring(L, "k");
        try lua.lua_setfield(L, -2, "__mode");
        _ = lua.lua_setmetatable(L, -2);
        lua.lua_pushvalue(L, -1);
        try lua.lua_setfield(L, lua.LUA_REGISTRYINDEX, HOOKKEY);
    }

    lua.lua_pushlightuserdata(L, L1);
    if (func != null) {
        lua.lua_pushvalue(L, arg + 1);
    } else {
        lua.lua_pushnil(L);
    }
    try lua.lua_settable(L, -3);
    lua.lua_pop(L, 1);
    lua.lua_sethook(L1, func, @bitCast(mask), count);
    return 0;
}

fn db_gethook(L: *lua.lua_State) !i32 {
    var arg: i32 = undefined;
    const L1 = getthread(L, &arg);
    const mask = lua.lua_gethookmask(L1);
    const count = lua.lua_gethookcount(L1);
    const func = lua.lua_gethook(L1);

    if (func != null) {
        _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, HOOKKEY);
        if (lua.lua_type(L, -1) == lua.LUA_TTABLE) {
            lua.lua_pushlightuserdata(L, L1);
            _ = try lua.lua_gettable(L, -2);
            lua.lua_remove(L, -2);
        } else {
            lua.lua_pop(L, 1);
            lua.lua_pushnil(L);
        }
    } else {
        lua.lua_pushnil(L);
    }

    var mask_buf: [4]u8 = undefined;
    var mask_len: usize = 0;
    const umask = @as(u32, @bitCast(mask));
    if ((umask & lua.LUA_MASKCALL) != 0) { mask_buf[mask_len] = 'c'; mask_len += 1; }
    if ((umask & lua.LUA_MASKRET) != 0)  { mask_buf[mask_len] = 'r'; mask_len += 1; }
    if ((umask & lua.LUA_MASKLINE) != 0) { mask_buf[mask_len] = 'l'; mask_len += 1; }
    _ = lua.lua_pushlstring(L, &mask_buf, mask_len);
    lua.lua_pushinteger(L, count);

    return 3;
}

fn treatstackoption(L: *lua.lua_State, L1: *lua.lua_State, fname: []const u8) void {
    if (L == L1) {
        lua.lua_rotate(L, -2, 1);
    } else {
        lua.lua_xmove(L1, L, 1);
    }
    lua.lua_setfield(L, -2, fname) catch {};
}

fn db_getinfo(L: *lua.lua_State) !i32 {
    var ar: lua.lua_Debug = std.mem.zeroes(lua.lua_Debug);
    var arg: i32 = undefined;
    const L1 = getthread(L, &arg);
    const options_opt = lauxlib.luaL_optstring(L, arg + 2, "flnSrtu");
    const options: []const u8 = options_opt orelse "flnSrtu";

    if (L != L1 and lua.lua_checkstack(L1, 3) == 0) {
        return lauxlib.luaL_error(L, "stack overflow");
    }

    if (options.len > 0 and options[0] == '>') {
        return lauxlib.luaL_argerror(L, arg + 2, "invalid option '>'");
    }

    if (lua.lua_type(L, arg + 1) == lua.LUA_TFUNCTION) {
        const new_options = try std.fmt.allocPrint(L.allocator, ">{s}", .{options});
        defer L.allocator.free(new_options);
        lua.lua_pushvalue(L, arg + 1);
        lua.lua_xmove(L, L1, 1);
        if (try lua.lua_getinfo(L1, new_options, &ar) == 0) {
            return lauxlib.luaL_argerror(L, arg + 2, "invalid option");
        }
    } else {
        const level = @as(i32, @intCast(try lauxlib.luaL_checkinteger(L, arg + 1)));
        if (lua.lua_getstack(L1, level, &ar) == 0) {
            lua.lua_pushnil(L);
            return 1;
        }
        if (try lua.lua_getinfo(L1, options, &ar) == 0) {
            return lauxlib.luaL_argerror(L, arg + 2, "invalid option");
        }
    }

    lua.lua_createtable(L, 0, 0);

    if (std.mem.indexOfScalar(u8, options, 'S') != null) {
        if (ar.source) |src| {
            _ = lua.lua_pushlstring(L, src, src.len);
        } else {
            lua.lua_pushnil(L);
        }
        try lua.lua_setfield(L, -2, "source");

        _ = lua.lua_pushlstring(L, &ar.short_src, std.mem.sliceTo(&ar.short_src, 0).len);
        try lua.lua_setfield(L, -2, "short_src");

        lua.lua_pushinteger(L, ar.linedefined);
        try lua.lua_setfield(L, -2, "linedefined");

        lua.lua_pushinteger(L, ar.lastlinedefined);
        try lua.lua_setfield(L, -2, "lastlinedefined");

        if (ar.what) |w| {
            _ = lua.lua_pushstring(L, w);
        } else {
            lua.lua_pushnil(L);
        }
        try lua.lua_setfield(L, -2, "what");
    }

    if (std.mem.indexOfScalar(u8, options, 'l') != null) {
        lua.lua_pushinteger(L, ar.currentline);
        try lua.lua_setfield(L, -2, "currentline");
    }

    if (std.mem.indexOfScalar(u8, options, 'u') != null) {
        lua.lua_pushinteger(L, ar.nups);
        try lua.lua_setfield(L, -2, "nups");

        lua.lua_pushinteger(L, ar.nparams);
        try lua.lua_setfield(L, -2, "nparams");

        lua.lua_pushboolean(L, if (ar.isvararg) 1 else 0);
        try lua.lua_setfield(L, -2, "isvararg");
    }

    if (std.mem.indexOfScalar(u8, options, 'n') != null) {
        if (ar.name) |n| {
            _ = lua.lua_pushlstring(L, n, n.len);
        } else {
            lua.lua_pushnil(L);
        }
        try lua.lua_setfield(L, -2, "name");

        if (ar.namewhat) |nw| {
            _ = lua.lua_pushlstring(L, nw, nw.len);
        } else {
            lua.lua_pushnil(L);
        }
        try lua.lua_setfield(L, -2, "namewhat");
    }

    if (std.mem.indexOfScalar(u8, options, 'r') != null) {
        lua.lua_pushinteger(L, ar.ftransfer);
        try lua.lua_setfield(L, -2, "ftransfer");

        lua.lua_pushinteger(L, ar.ntransfer);
        try lua.lua_setfield(L, -2, "ntransfer");
    }

    if (std.mem.indexOfScalar(u8, options, 't') != null) {
        lua.lua_pushboolean(L, if (ar.istailcall) 1 else 0);
        try lua.lua_setfield(L, -2, "istailcall");

        lua.lua_pushinteger(L, ar.extraargs);
        try lua.lua_setfield(L, -2, "extraargs");
    }

    if (std.mem.indexOfScalar(u8, options, 'L') != null) {
        treatstackoption(L, L1, "activelines");
    }
    if (std.mem.indexOfScalar(u8, options, 'f') != null) {
        treatstackoption(L, L1, "func");
    }

    return 1;
}

fn db_getlocal(L: *lua.lua_State) !i32 {
    var arg: i32 = undefined;
    const L1 = getthread(L, &arg);
    const nvar = @as(i32, @intCast(try lauxlib.luaL_checkinteger(L, arg + 2)));
    if (lua.lua_type(L, arg + 1) == lua.LUA_TFUNCTION) {
        lua.lua_pushvalue(L, arg + 1);
        if (lua.lua_getlocal(L, null, nvar)) |name| {
            _ = lua.lua_pushlstring(L, name, name.len);
            return 1;
        }
        lua.lua_pushnil(L);
        return 1;
    } else {
        var ar: lua.lua_Debug = std.mem.zeroes(lua.lua_Debug);
        const level = @as(i32, @intCast(try lauxlib.luaL_checkinteger(L, arg + 1)));
        if (lua.lua_getstack(L1, level, &ar) == 0) {
            return lauxlib.luaL_argerror(L, arg + 1, "level out of range");
        }
        if (L != L1 and lua.lua_checkstack(L1, 1) == 0) {
            return lauxlib.luaL_error(L, "stack overflow");
        }
        if (lua.lua_getlocal(L1, &ar, nvar)) |name| {
            if (L != L1) {
                lua.lua_xmove(L1, L, 1);
            }
            _ = lua.lua_pushlstring(L, name, name.len);
            lua.lua_rotate(L, -2, 1);
            return 2;
        } else {
            lua.lua_pushnil(L);
            return 1;
        }
    }
}

fn db_setlocal(L: *lua.lua_State) !i32 {
    var arg: i32 = undefined;
    const L1 = getthread(L, &arg);
    var ar: lua.lua_Debug = std.mem.zeroes(lua.lua_Debug);
    const level = @as(i32, @intCast(try lauxlib.luaL_checkinteger(L, arg + 1)));
    const nvar = @as(i32, @intCast(try lauxlib.luaL_checkinteger(L, arg + 2)));
    if (lua.lua_getstack(L1, level, &ar) == 0) {
        return lauxlib.luaL_argerror(L, arg + 1, "level out of range");
    }
    try lauxlib.luaL_checkany(L, arg + 3);
    if (L != L1 and lua.lua_checkstack(L1, 1) == 0) {
        return lauxlib.luaL_error(L, "stack overflow");
    }
    lua.lua_pushvalue(L, arg + 3);
    if (L != L1) {
        lua.lua_xmove(L, L1, 1);
    }
    if (lua.lua_setlocal(L1, &ar, nvar)) |name| {
        _ = lua.lua_pushlstring(L, name, name.len);
    } else {
        if (L != L1) {
            lua.lua_pop(L1, 1);
        } else {
            lua.lua_pop(L, 1);
        }
        lua.lua_pushnil(L);
    }
    return 1;
}

fn auxupvalue(L: *lua.lua_State, get: bool) !i32 {
    const n = @as(i32, @intCast(try lauxlib.luaL_checkinteger(L, 2)));
    try lauxlib.luaL_checktype(L, 1, lua.LUA_TFUNCTION);
    const name = if (get) lua.lua_getupvalue(L, 1, n) else lua.lua_setupvalue(L, 1, n);
    if (name) |nm| {
        _ = lua.lua_pushlstring(L, nm, nm.len);
        if (get) {
            lua.lua_insert(L, -2);
            return 2;
        }
        return 1;
    }
    return 0;
}

fn db_getupvalue(L: *lua.lua_State) !i32 {
    return auxupvalue(L, true);
}

fn db_setupvalue(L: *lua.lua_State) !i32 {
    try lauxlib.luaL_checkany(L, 3);
    return auxupvalue(L, false);
}

fn checkupval(L: *lua.lua_State, argf: i32, argnup: i32, check_bounds: bool) !?*anyopaque {
    const n = @as(i32, @intCast(try lauxlib.luaL_checkinteger(L, argnup)));
    try lauxlib.luaL_checktype(L, argf, lua.LUA_TFUNCTION);
    const id = lua.lua_upvalueid(L, argf, n);
    if (check_bounds and id == null) {
        return lauxlib.luaL_argerror(L, argnup, "invalid upvalue index");
    }
    return id;
}

fn db_upvalueid(L: *lua.lua_State) !i32 {
    if (try checkupval(L, 1, 2, false)) |id| {
        lua.lua_pushlightuserdata(L, id);
    } else {
        lauxlib.luaL_pushfail(L);
    }
    return 1;
}

fn db_upvaluejoin(L: *lua.lua_State) !i32 {
    const n1 = @as(i32, @intCast(try lauxlib.luaL_checkinteger(L, 2)));
    const n2 = @as(i32, @intCast(try lauxlib.luaL_checkinteger(L, 4)));
    _ = try checkupval(L, 1, 2, true);
    _ = try checkupval(L, 3, 4, true);
    if (lua.lua_iscfunction(L, 1) != 0) {
        return lauxlib.luaL_argerror(L, 1, "Lua function expected");
    }
    if (lua.lua_iscfunction(L, 3) != 0) {
        return lauxlib.luaL_argerror(L, 3, "Lua function expected");
    }
    lua.lua_upvaluejoin(L, 1, n1, 3, n2);
    return 0;
}

fn db_debug(L: *lua.lua_State) !i32 {
    const g = L.l_G orelse return 0;
    const io = g.io;
    std.Io.File.stderr().writeStreamingAll(io, "lua_debug> compilation not supported in this port yet\n") catch {};
    return 0;
}

fn db_traceback(L: *lua.lua_State) !i32 {
    var arg: i32 = undefined;
    const L1 = getthread(L, &arg);
    const msg = lua.lua_tostring(L, arg + 1);
    if (msg == null and !lua.lua_isnoneornil(L, arg + 1)) {
        lua.lua_pushvalue(L, arg + 1);
        return 1;
    } else {
        const level = @as(i32, @intCast(lauxlib.luaL_optinteger(L, arg + 2, if (L == L1) 1 else 0)));
        try lauxlib.luaL_traceback(L, L1, if (msg) |m| m else "", level);

    }
    return 1;
}

// ===================================================================
// Library registration
// ===================================================================

pub fn opendbalib(L: *lua.lua_State) !void {
    lua.lua_createtable(L, 0, 16);

    inline for (.{
        .{ .name = "getregistry",  .func = db_getregistry  },
        .{ .name = "getmetatable", .func = db_getmetatable },
        .{ .name = "setmetatable", .func = db_setmetatable },
        .{ .name = "getuservalue", .func = db_getuservalue },
        .{ .name = "setuservalue", .func = db_setuservalue },
        .{ .name = "gethook",      .func = db_gethook      },
        .{ .name = "sethook",      .func = db_sethook      },
        .{ .name = "getinfo",      .func = db_getinfo      },
        .{ .name = "getlocal",     .func = db_getlocal     },
        .{ .name = "setlocal",     .func = db_setlocal     },
        .{ .name = "getupvalue",   .func = db_getupvalue   },
        .{ .name = "setupvalue",   .func = db_setupvalue   },
        .{ .name = "upvalueid",    .func = db_upvalueid    },
        .{ .name = "upvaluejoin",  .func = db_upvaluejoin  },
        .{ .name = "debug",        .func = db_debug        },
        .{ .name = "traceback",    .func = db_traceback    },
    }) |reg| {
        lua.lua_pushcfunction(L, reg.func);
        try lua.lua_setfield(L, -2, reg.name);
    }
    // Create _HOOKKEY table with weak keys metatable in registry
    lua.lua_createtable(L, 0, 1);
    lua.lua_createtable(L, 0, 1);
    _ = lua.lua_pushstring(L, "k");
    try lua.lua_setfield(L, -2, "__mode");
    _ = lua.lua_setmetatable(L, -2);
    try lua.lua_setfield(L, lua.LUA_REGISTRYINDEX, HOOKKEY);
}
