//
// ** $Id: lualib.zig $
// ** Standard library functions for Lua.zig (Zig port of Lua 5.5.0)
// ** See Copyright Notice in c_compat.zig
//


const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");

// ===================================================================
// Base Library
// ===================================================================

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
    try baselib.openbaselib(L);
    // Register _G in package.loaded for `require "_G"`
    try registerLoaded(L, "_G");
}

// ===================================================================
// Coroutine Library
// ===================================================================

pub fn opencorolib(L: *lua.lua_State) !void {
    try corolib.opencorolib(L);
    try lua.lua_setglobal(L, "coroutine");
    try registerLoaded(L, "coroutine");
}

// ===================================================================
// Table Library
// ===================================================================

pub fn opentablib(L: *lua.lua_State) !void {
    _ = try tablib.opentablib(L);
    try lua.lua_setglobal(L, "table");
    try registerLoaded(L, "table");
}

// ===================================================================
// String Library
// ===================================================================

pub fn openstringlib(L: *lua.lua_State) !void {
    _ = try stringlib.openstringlib(L);
    try lua.lua_setglobal(L, "string");
    try registerLoaded(L, "string");
}

// ===================================================================
// Math Library
// ===================================================================

pub fn openmathlib(L: *lua.lua_State) !void {
    try mathlib.openmathlib(L);
    try registerLoaded(L, "math");
}

// ===================================================================
// OS Library
// ===================================================================

pub fn openoslib(L: *lua.lua_State) !void {
    try oslib.openoslib(L);
    try lua.lua_setglobal(L, "os");
    try registerLoaded(L, "os");
}

// ===================================================================
// IO Library
// ===================================================================

pub fn openio(L: *lua.lua_State) !void {
    try iolib.openio(L);
    try lua.lua_setglobal(L, "io");
    try registerLoaded(L, "io");
}

// ===================================================================
// Loadlib
// ===================================================================

const loadlib = @import("lib/loadlib.zig");

pub fn openloadlib(L: *lua.lua_State) !void {
    try loadlib.openloadlib(L);
    try registerLoaded(L, "package");
}

// ===================================================================
// Debug Library
// ===================================================================

pub fn opendbalib(L: *lua.lua_State) !void {
    try debug.opendbalib(L);
    try lua.lua_setglobal(L, "debug");
    try registerLoaded(L, "debug");
}

// ===================================================================
// Bit32 Library
// ===================================================================

pub fn openbit32(L: *lua.lua_State) !void {
    try bit32.openbit32(L);
    try registerLoaded(L, "bit32");
}

// ===================================================================
// UTF-8 Library
// ===================================================================

pub fn openutf8lib(L: *lua.lua_State) !void {
    try utf8lib.openutf8lib(L);
    try registerLoaded(L, "utf8");
}
