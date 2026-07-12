//
// ** $Id: lualib.zig $
// ** Standard library functions for Lua.zig (Zig port of Lua 5.5.1)
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

pub fn openbaselib(L: *lua.lua_State) !void {
    try baselib.openbaselib(L);
}

// ===================================================================
// Coroutine Library
// ===================================================================

pub fn opencorolib(L: *lua.lua_State) !void {
    try corolib.opencorolib(L);
    lua.lua_setglobal(L, "coroutine");
}

// ===================================================================
// Table Library
// ===================================================================

pub fn opentablib(L: *lua.lua_State) !void {
    _ = try tablib.opentablib(L);
    lua.lua_setglobal(L, "table");
}

// ===================================================================
// String Library
// ===================================================================

pub fn openstringlib(L: *lua.lua_State) !void {
    _ = try stringlib.openstringlib(L);
    lua.lua_setglobal(L, "string");
}

// ===================================================================
// Math Library
// ===================================================================

pub fn openmathlib(L: *lua.lua_State) !void {
    try mathlib.openmathlib(L);
}

// ===================================================================
// OS Library
// ===================================================================

pub fn openoslib(L: *lua.lua_State) !void {
    try oslib.openoslib(L);
    lua.lua_setglobal(L, "os");
}

// ===================================================================
// IO Library
// ===================================================================

pub fn openio(L: *lua.lua_State) !void {
    try iolib.openio(L);
    lua.lua_setglobal(L, "io");
}

// ===================================================================
// Loadlib
// ===================================================================

const loadlib = @import("lib/loadlib.zig");

pub fn openloadlib(L: *lua.lua_State) !void {
    try loadlib.openloadlib(L);
}

// ===================================================================
// Debug Library
// ===================================================================

pub fn opendbalib(L: *lua.lua_State) !void {
    const debug = L;
    _ = debug;
    // Register debug library functions
}

// ===================================================================
// Bit32 Library
// ===================================================================

pub fn openbit32(L: *lua.lua_State) !void {
    try bit32.openbit32(L);
}

// ===================================================================
// UTF-8 Library
// ===================================================================

pub fn openutf8lib(L: *lua.lua_State) !void {
    try utf8lib.openutf8lib(L);
}
