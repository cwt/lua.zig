//
// ** $Id: lualib.zig $
// ** Standard library functions for Lua.zig (Zig port of Lua 5.5.1)
// ** See Copyright Notice in c_compat.zig
//

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");

const baselib = @import("lib/baselib.zig");
const mathlib = @import("lib/mathlib.zig");
const bit32 = @import("lib/bit32.zig");
const utf8lib = @import("lib/utf8lib.zig");
const stringlib = @import("lib/stringlib.zig");
const tablib = @import("lib/tablib.zig");
const corolib = @import("lib/corolib.zig");
const iolib = @import("lib/iolib.zig");
const oslib = @import("lib/oslib.zig");
const debug = @import("lib/debug.zig");
const loadlib = @import("lib/loadlib.zig");

// ===================================================================
// Standard Openers (luaopen_*) - each leaves module table on the stack
// ===================================================================

pub fn luaopen_base(L: *lua.lua_State) anyerror!i32 {
    try baselib.openbaselib(L);
    lua.lua_pushglobaltable(L);
    return 1;
}

pub fn luaopen_package(L: *lua.lua_State) anyerror!i32 {
    try loadlib.openloadlib(L);
    _ = lua.lua_getglobal(L, "package");
    return 1;
}

pub fn luaopen_coroutine(L: *lua.lua_State) anyerror!i32 {
    try corolib.opencorolib(L);
    return 1;
}

pub fn luaopen_table(L: *lua.lua_State) anyerror!i32 {
    return tablib.opentablib(L);
}

pub fn luaopen_string(L: *lua.lua_State) anyerror!i32 {
    return stringlib.openstringlib(L);
}

pub fn luaopen_math(L: *lua.lua_State) anyerror!i32 {
    try mathlib.openmathlib(L);
    _ = lua.lua_getglobal(L, "math");
    return 1;
}

pub fn luaopen_os(L: *lua.lua_State) anyerror!i32 {
    try oslib.openoslib(L);
    return 1;
}

pub fn luaopen_io(L: *lua.lua_State) anyerror!i32 {
    try iolib.openio(L);
    return 1;
}

pub fn luaopen_debug(L: *lua.lua_State) anyerror!i32 {
    try debug.opendbalib(L);
    return 1;
}

pub fn luaopen_bit32(L: *lua.lua_State) anyerror!i32 {
    try bit32.openbit32(L);
    _ = lua.lua_getglobal(L, "bit32");
    return 1;
}

pub fn luaopen_utf8(L: *lua.lua_State) anyerror!i32 {
    try utf8lib.openutf8lib(L);
    _ = lua.lua_getglobal(L, "utf8");
    return 1;
}

/// Standard Libraries list (matching ordering and bitmask constants in Lua 5.5.1 linit.c / lualib.h).
pub const stdlibs = [_]struct { name: []const u8, func: lua.lua_CFunction, mask: i32 }{
    .{ .name = "_G", .func = luaopen_base, .mask = lua.LUA_GLIBK },
    .{ .name = "package", .func = luaopen_package, .mask = lua.LUA_LOADLIBK },
    .{ .name = "coroutine", .func = luaopen_coroutine, .mask = lua.LUA_COLIBK },
    .{ .name = "debug", .func = luaopen_debug, .mask = lua.LUA_DBLIBK },
    .{ .name = "io", .func = luaopen_io, .mask = lua.LUA_IOLIBK },
    .{ .name = "math", .func = luaopen_math, .mask = lua.LUA_MATHLIBK },
    .{ .name = "os", .func = luaopen_os, .mask = lua.LUA_OSLIBK },
    .{ .name = "string", .func = luaopen_string, .mask = lua.LUA_STRLIBK },
    .{ .name = "table", .func = luaopen_table, .mask = lua.LUA_TABLIBK },
    .{ .name = "utf8", .func = luaopen_utf8, .mask = lua.LUA_UTF8LIBK },
    .{ .name = "bit32", .func = luaopen_bit32, .mask = lua.LUA_BITLIBK },
};

/// Register a library module in `package.loaded[name]` so that
/// `require "name"` works. The library must already be set as a global.
fn registerLoaded(L: *lua.lua_State, name: []const u8) !void {
    _ = try lua.lauxlib.luaL_getsubtable(L, lua.LUA_REGISTRYINDEX, lua.lauxlib.LUA_LOADED_TABLE);
    defer lua.lua_pop(L, 1); // pop _LOADED
    _ = try lua.lua_getfield(L, -1, name);
    if (lua.lua_toboolean(L, -1) == 0) {
        lua.lua_pop(L, 1);
        defer lua.lua_pop(L, 1); // pop the remaining global copy
        _ = lua.lua_getglobal(L, name);
        lua.lua_pushvalue(L, -1);
        try lua.lua_setfield(L, -3, name);
    } else {
        lua.lua_pop(L, 1);
    }
}

pub fn openbaselib(L: *lua.lua_State) !void {
    _ = try luaopen_base(L);
    lua.lua_pop(L, 1);
    try registerLoaded(L, "_G");
}

pub fn opencorolib(L: *lua.lua_State) !void {
    _ = try luaopen_coroutine(L);
    try lua.lua_setglobal(L, "coroutine");
    try registerLoaded(L, "coroutine");
}

pub fn opentablib(L: *lua.lua_State) !void {
    _ = try luaopen_table(L);
    try lua.lua_setglobal(L, "table");
    try registerLoaded(L, "table");
}

pub fn openstringlib(L: *lua.lua_State) !void {
    _ = try luaopen_string(L);
    try lua.lua_setglobal(L, "string");
    try registerLoaded(L, "string");
}

pub fn openmathlib(L: *lua.lua_State) !void {
    _ = try luaopen_math(L);
    lua.lua_pop(L, 1);
    try registerLoaded(L, "math");
}

pub fn openoslib(L: *lua.lua_State) !void {
    _ = try luaopen_os(L);
    try lua.lua_setglobal(L, "os");
    try registerLoaded(L, "os");
}

pub fn openio(L: *lua.lua_State) !void {
    _ = try luaopen_io(L);
    try lua.lua_setglobal(L, "io");
    try registerLoaded(L, "io");
}

pub fn openloadlib(L: *lua.lua_State) !void {
    _ = try luaopen_package(L);
    lua.lua_pop(L, 1);
    try registerLoaded(L, "package");
}

pub fn opendbalib(L: *lua.lua_State) !void {
    _ = try luaopen_debug(L);
    try lua.lua_setglobal(L, "debug");
    try registerLoaded(L, "debug");
}

pub fn openbit32(L: *lua.lua_State) !void {
    _ = try luaopen_bit32(L);
    lua.lua_pop(L, 1);
    try registerLoaded(L, "bit32");
}

pub fn openutf8lib(L: *lua.lua_State) !void {
    _ = try luaopen_utf8(L);
    lua.lua_pop(L, 1);
    try registerLoaded(L, "utf8");
}
