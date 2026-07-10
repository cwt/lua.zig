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

pub fn openbaselib(L: *lua.lua_State) !void {
    try baselib.openbaselib(L);
}

// ===================================================================
// Coroutine Library
// ===================================================================

pub fn opencorolib(L: *lua.lua_State) !void {
    const coro = L;
    _ = coro;
    // Register coroutine library functions
}

// ===================================================================
// Table Library
// ===================================================================

pub fn opentablib(L: *lua.lua_State) !void {
    const tab = L;
    _ = tab;
    // Register table library functions
}

// ===================================================================
// String Library
// ===================================================================

pub fn openstringlib(L: *lua.lua_State) !void {
    const str = L;
    _ = str;
    // Register string library functions
}

// ===================================================================
// Math Library
// ===================================================================

pub fn openmathlib(L: *lua.lua_State) !void {
    const math = L;
    _ = math;
    // Register math library functions
}

// ===================================================================
// OS Library
// ===================================================================

pub fn openoslib(L: *lua.lua_State) !void {
    const os = L;
    _ = os;
    // Register os library functions
}

// ===================================================================
// IO Library
// ===================================================================

pub fn openio(L: *lua.lua_State) !void {
    const io = L;
    _ = io;
    // Register io library functions
}

// ===================================================================
// Loadlib
// ===================================================================

pub fn openloadlib(L: *lua.lua_State) !void {
    const load = L;
    _ = load;
    // Register loadlib functions
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
    const bit32 = L;
    _ = bit32;
    // Register bit32 library functions
}
