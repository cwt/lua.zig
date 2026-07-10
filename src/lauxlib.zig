//
// ** $Id: lauxlib.zig
// ** Auxiliary library for Lua.zig (Zig port of Lua 5.5.1)
// ** See Copyright Notice in c_compat.zig
//

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");
const lualib = @import("lualib.zig");

// ===================================================================
// Table operations
// ===================================================================

pub fn luaL_newtable(L: *lua.lua_State) !void {
    _ = L;
}

pub fn luaL_setn(L: *lua.lua_State) !void {
    _ = L;
}

pub fn luaL_checktype(L: *lua.lua_State, idx: i32, t: i32) !void {
    const actual = lua.lua_type(L, idx);
    if (actual != t) {
        return error.WrongType;
    }
}

pub fn luaL_typename(L: *lua.lua_State, idx: i32) ![]const u8 {
    const actual_type = lua.lua_type(L, idx);
    return switch (actual_type) {
        lua.LUA_TNONE => "none",
        lua.LUA_TNIL => "nil",
        lua.LUA_TBOOLEAN => "boolean",
        lua.LUA_TLIGHTUSERDATA => "light userdata",
        lua.LUA_TNUMBER => "number",
        lua.LUA_TSTRING => "string",
        lua.LUA_TTABLE => "table",
        lua.LUA_TFUNCTION => "function",
        lua.LUA_TUSERDATA => "userdata",
        lua.LUA_TTHREAD => "thread",
        else => return error.UnknownType,
    };
}

pub fn luaL_len(L: *lua.lua_State, idx: i32) !usize {
    _ = L;
    _ = idx;
    return 0;
}

pub fn luaL_checkinteger(L: *lua.lua_State, idx: i32) !i64 {
    const n = lua.lua_tointeger(L, idx);
    if (n == null) return error.InvalidType;
    return n.?;
}

pub fn luaL_checklstring(L: *lua.lua_State, idx: i32, len: ?*usize) ![]const u8 {
    const s = lua.lua_tolstring(L, idx, len);
    return s orelse error.InvalidType;
}

pub fn luaL_checkoption(L: *lua.lua_State, idx: i32, def: []const u8, opts: [][]const u8) !i32 {
    _ = def;
    const s = try luaL_checklstring(L, idx, null);
    var i: i32 = 0;
    while (i < opts.len) : (i += 1) {
        if (std.mem.eql(u8, s, opts[i])) return i;
    }
    return @intCast(opts.len);
}

pub fn luaL_register(L: *lua.lua_State, libname: []const u8, l: ?[]?lua.lua_CFunction) !void {
    if (lua.lua_getglobal(L, libname) == 0) {
        lua.lua_newtable(L);
    }
    if (l) |funcs| {
        for (funcs) |f_opt| {
            if (f_opt) |f| {
                lua.lua_pushcfunction(L, f);
                lua.lua_setfield(L, -2, "func");
            }
        }
    }
    lua.lua_setglobal(L, libname);
}

// ===================================================================
// Error handling
// ===================================================================

pub fn luaL_error(L: *lua.lua_State, msg: []const u8) !void {
    lua.lua_pushstring(L, msg);
    return lua.lua_error(L);
}

pub fn luaL_argerror(L: *lua.lua_State, arg: i32, msg: []const u8) !void {
    _ = arg;
    lua.lua_pushstring(L, msg);
    return lua.lua_error(L);
}

pub fn luaL_typeerror(L: *lua.lua_State, idx: i32, msg: []const u8) !void {
    _ = idx;
    lua.lua_pushstring(L, msg);
    return lua.lua_error(L);
}

// ===================================================================
// Utility functions
// ===================================================================

pub fn luaL_checkstack(L: *lua.lua_State, n: i32, msg: []const u8) !void {
    _ = msg;
    if (lua.lua_gettop(L) + n > lua.LUA_MINSTACK) {
        const newstack = @as(usize, @intCast(lua.lua_gettop(L))) + @as(usize, @intCast(n)) + lua.LUA_MINSTACK;
        _ = newstack;
        return error.StackOverflow;
    }
}

pub fn luaL_tolstring(L: *lua.lua_State, idx: i32, len: ?*usize) ?[]const u8 {
    const actual_type = lua.lua_type(L, idx);
    if (actual_type == lua.LUA_TSTRING) {
        return lua.lua_tolstring(L, idx, len);
    } else if (actual_type == lua.LUA_TNUMBER) {
        var buf: [128]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "{d}", .{0}) catch return null;
        lua.lua_pushstring(L, s);
        return lua.lua_tolstring(L, -1, len);
    } else {
        return null;
    }
}

pub fn luaL_traceback(L: *lua.lua_State, L2: *lua.lua_State, msg: []const u8, level: i32) !void {
    _ = L;
    _ = L2;
    _ = msg;
    _ = level;
    return error.NotImplemented;
}

// ===================================================================
// Library opening functions
// ===================================================================

pub fn luaL_openlibs(L: *lua.lua_State) !void {
    try luaL_openselectedlibs(L, ~@as(i32, 0), 0);
}

pub fn luaL_openselectedlibs(L: *lua.lua_State, openmask: i32, closedmask: i32) !void {
    _ = closedmask;
    if ((openmask & lua.LUA_BASELIB) != 0) {
        try lualib.openbaselib(L);
    }
    if ((openmask & lua.LUA_COROLIB) != 0) {
        try lualib.opencorolib(L);
    }
    if ((openmask & lua.LUA_TABLIB) != 0) {
        try lualib.opentablib(L);
    }
    if ((openmask & lua.LUA_STRLIB) != 0) {
        try lualib.openstringlib(L);
    }
    if ((openmask & lua.LUA_MATHLIB) != 0) {
        try lualib.openmathlib(L);
    }
    if ((openmask & lua.LUA_OSLIB) != 0) {
        try lualib.openoslib(L);
    }
    if ((openmask & lua.LUA_IOLIB) != 0) {
        try lualib.openio(L);
    }
    if ((openmask & lua.LUA_LOADLIB) != 0) {
        try lualib.openloadlib(L);
    }
    if ((openmask & lua.LUA_DBLIB) != 0) {
        try lualib.opendbalib(L);
    }
    if ((openmask & lua.LUA_BITLIB) != 0) {
        try lualib.openbit32(L);
    }
}
