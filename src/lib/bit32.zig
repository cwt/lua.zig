//
// ** $Id: bit32.zig $
// ** Bitwise library for Lua.zig (Zig port of Lua 5.3's bit32 library)
// ** See Copyright Notice in lua.h
//
// Ported from lua-5.3.6/src/lbitlib.c. All values are interpreted as
// unsigned 32-bit integers (LUA_NBITS = 32). Follows the reference
// semantics exactly: rotations use disp % 32, but shifts return 0 when
// |disp| >= 32, and arshift is arithmetic (sign-extends bit 31) only
// when bit 31 of the value is set.
//

const std = @import("std");
const lua = @import("../lua.zig");
const lauxlib = @import("../lauxlib.zig");

const MASK: u64 = 0xFFFFFFFF;
const NBITS: u6 = 32;

// Interpret an i64 argument as a 32-bit unsigned value (matches the C
// `checkunsigned` helper, which masks to NBITS bits).
fn maskfield(v: i64) u64 {
    return @as(u64, @bitCast(v)) & MASK;
}

// Logical left/right shift of a 32-bit value by |disp| bits.
// Returns 0 when |disp| >= NBITS (the C `b_shift` behaviour).
fn b_shift(x: u64, disp: i64) u64 {
    const r = x & MASK;
    if (disp == std.math.minInt(i64)) return 0;
    if (disp < 0) {
        const i = -disp;
        if (i >= NBITS) return 0;
        return (r >> @as(u6, @intCast(i))) & MASK;
    } else {
        const i = disp;
        if (i >= NBITS) return 0;
        return (r << @as(u6, @intCast(i))) & MASK;
    }
}

fn bit_and(L: *lua.lua_State) !i32 {
    var r: u64 = ~@as(u64, 0);
    const n = lua.lua_gettop(L);
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        r &= maskfield(try lauxlib.luaL_checkinteger(L, i));
    }
    lua.lua_pushinteger(L, @as(i64, @bitCast(r & MASK)));
    return 1;
}

fn bit_or(L: *lua.lua_State) !i32 {
    var r: u64 = 0;
    const n = lua.lua_gettop(L);
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        r |= maskfield(try lauxlib.luaL_checkinteger(L, i));
    }
    lua.lua_pushinteger(L, @as(i64, @bitCast(r & MASK)));
    return 1;
}

fn bit_xor(L: *lua.lua_State) !i32 {
    var r: u64 = 0;
    const n = lua.lua_gettop(L);
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        r ^= maskfield(try lauxlib.luaL_checkinteger(L, i));
    }
    lua.lua_pushinteger(L, @as(i64, @bitCast(r & MASK)));
    return 1;
}

fn bit_not(L: *lua.lua_State) !i32 {
    const x = maskfield(try lauxlib.luaL_checkinteger(L, 1));
    lua.lua_pushinteger(L, @as(i64, @bitCast(~x & MASK)));
    return 1;
}

fn bit_test(L: *lua.lua_State) !i32 {
    var r: u64 = ~@as(u64, 0);
    const n = lua.lua_gettop(L);
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        r &= maskfield(try lauxlib.luaL_checkinteger(L, i));
    }
    lua.lua_pushboolean(L, if ((r & MASK) != 0) 1 else 0);
    return 1;
}

fn bit_lshift(L: *lua.lua_State) !i32 {
    const x = maskfield(try lauxlib.luaL_checkinteger(L, 1));
    const disp = try lauxlib.luaL_checkinteger(L, 2);
    lua.lua_pushinteger(L, @as(i64, @bitCast(b_shift(x, disp))));
    return 1;
}

fn bit_rshift(L: *lua.lua_State) !i32 {
    const x = maskfield(try lauxlib.luaL_checkinteger(L, 1));
    const disp = try lauxlib.luaL_checkinteger(L, 2);
    lua.lua_pushinteger(L, @as(i64, @bitCast(b_shift(x, -%disp))));
    return 1;
}

fn bit_arshift(L: *lua.lua_State) !i32 {
    const x = maskfield(try lauxlib.luaL_checkinteger(L, 1));
    const disp = try lauxlib.luaL_checkinteger(L, 2);
    if (disp < 0 or (x & (@as(u64, 1) << 31)) == 0) {
        lua.lua_pushinteger(L, @as(i64, @bitCast(b_shift(x, -%disp))));
        return 1;
    }
    if (disp >= NBITS) {
        lua.lua_pushinteger(L, @as(i64, @bitCast(MASK)));
        return 1;
    }
    const i: u6 = @intCast(disp);
    const hi = (~(MASK >> i)) & MASK;
    const res = ((x >> i) | hi) & MASK;
    lua.lua_pushinteger(L, @as(i64, @bitCast(res)));
    return 1;
}

fn bit_lrotate(L: *lua.lua_State) !i32 {
    const x = maskfield(try lauxlib.luaL_checkinteger(L, 1));
    const disp = try lauxlib.luaL_checkinteger(L, 2);
    const d: u6 = @intCast(disp & 31);
    const r = x & MASK;
    if (d == 0) {
        lua.lua_pushinteger(L, @as(i64, @bitCast(r)));
        return 1;
    }
    const res = ((r << d) | (r >> (NBITS - d))) & MASK;
    lua.lua_pushinteger(L, @as(i64, @bitCast(res)));
    return 1;
}

fn bit_rrotate(L: *lua.lua_State) !i32 {
    const x = maskfield(try lauxlib.luaL_checkinteger(L, 1));
    const disp = try lauxlib.luaL_checkinteger(L, 2);
    const d: u6 = @intCast(disp & 31);
    const r = x & MASK;
    if (d == 0) {
        lua.lua_pushinteger(L, @as(i64, @bitCast(r)));
        return 1;
    }
    const res = ((r >> d) | (r << (NBITS - d))) & MASK;
    lua.lua_pushinteger(L, @as(i64, @bitCast(res)));
    return 1;
}

fn bit_extract(L: *lua.lua_State) !i32 {
    const x = maskfield(try lauxlib.luaL_checkinteger(L, 1));
    const field = try lauxlib.luaL_checkinteger(L, 2);
    const width = lauxlib.luaL_optinteger(L, 3, 1);
    try lauxlib.luaL_argcheck(L, field >= 0, 2, "field cannot be negative");
    try lauxlib.luaL_argcheck(L, width > 0, 3, "width must be positive");
    if (field > NBITS or width > NBITS or field + width > NBITS) {
        return lauxlib.luaL_error(L, "trying to access non-existent bits");
    }
    const f: u6 = @intCast(field);
    const w: u6 = @intCast(width);
    const wmask: u64 = if (w >= NBITS) MASK else ((@as(u64, 1) << w) - 1);
    const res = (x >> f) & wmask;
    lua.lua_pushinteger(L, @as(i64, @bitCast(res)));
    return 1;
}

fn bit_replace(L: *lua.lua_State) !i32 {
    const x = maskfield(try lauxlib.luaL_checkinteger(L, 1));
    const v = maskfield(try lauxlib.luaL_checkinteger(L, 2));
    const field = try lauxlib.luaL_checkinteger(L, 3);
    const width = lauxlib.luaL_optinteger(L, 4, 1);
    try lauxlib.luaL_argcheck(L, field >= 0, 3, "field cannot be negative");
    try lauxlib.luaL_argcheck(L, width > 0, 4, "width must be positive");
    if (field > NBITS or width > NBITS or field + width > NBITS) {
        return lauxlib.luaL_error(L, "trying to access non-existent bits");
    }
    const f: u6 = @intCast(field);
    const w: u6 = @intCast(width);
    const wmask: u64 = if (w >= NBITS) MASK else ((@as(u64, 1) << w) - 1);
    const res = (x & ~(wmask << f)) | ((v & wmask) << f);
    lua.lua_pushinteger(L, @as(i64, @bitCast(res & MASK)));
    return 1;
}

// ===================================================================
// Library registration
// ===================================================================

pub fn openbit32(L: *lua.lua_State) !void {
    lua.lua_createtable(L, 0, 12);

    lua.lua_pushcfunction(L, bit_and);
    try lua.lua_setfield(L, -2, "band");

    lua.lua_pushcfunction(L, bit_or);
    try lua.lua_setfield(L, -2, "bor");

    lua.lua_pushcfunction(L, bit_xor);
    try lua.lua_setfield(L, -2, "bxor");

    lua.lua_pushcfunction(L, bit_not);
    try lua.lua_setfield(L, -2, "bnot");

    lua.lua_pushcfunction(L, bit_test);
    try lua.lua_setfield(L, -2, "btest");

    lua.lua_pushcfunction(L, bit_lshift);
    try lua.lua_setfield(L, -2, "lshift");

    lua.lua_pushcfunction(L, bit_rshift);
    try lua.lua_setfield(L, -2, "rshift");

    lua.lua_pushcfunction(L, bit_arshift);
    try lua.lua_setfield(L, -2, "arshift");

    lua.lua_pushcfunction(L, bit_lrotate);
    try lua.lua_setfield(L, -2, "lrotate");

    lua.lua_pushcfunction(L, bit_rrotate);
    try lua.lua_setfield(L, -2, "rrotate");

    lua.lua_pushcfunction(L, bit_extract);
    try lua.lua_setfield(L, -2, "extract");

    lua.lua_pushcfunction(L, bit_replace);
    try lua.lua_setfield(L, -2, "replace");

    try lua.lua_setglobal(L, "bit32");
}
