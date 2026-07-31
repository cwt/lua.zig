// $Id: llimits.zig
// Limits and basic types for Lua.zig (Zig port of Lua 5.5.0)
// See Copyright Notice in c_compat.zig

const std = @import("std");
const luaconf = @import("luaconf.zig");

// ===================================================================
// Basic types
// ===================================================================

// Character types
pub const lu_byte = u8;
pub const ls_byte = i8;

// Type for thread status/error codes
pub const TStatus = u8;

// Type for continuation-function contexts
pub const lua_KContext = usize;

// Type for memory-allocation functions
pub const lua_Alloc = *const fn (?*anyopaque, ?*anyopaque, usize, usize) ?*anyopaque;

// Type for warning functions
pub const lua_WarnFunction = *const fn (?*anyopaque, []const u8, i32) void;

// ===================================================================
// Constants
// ===================================================================

pub const LUA_REGISTRYINDEX: i32 = -2000;

export fn lua_upvalueindex(i: i32) i32 {
    return LUA_REGISTRYINDEX - i;
}

// Thread status
pub const LUA_OK: i32 = 0;
pub const LUA_YIELD: i32 = 1;
pub const LUA_ERRRUN: i32 = 2;
pub const LUA_ERRSYNTAX: i32 = 3;
pub const LUA_ERRMEM: i32 = 4;
pub const LUA_ERRERR: i32 = 5;

// Maximum number of nested C calls (for yieldability)
pub const LUAI_MAXCCALLS: u32 = 200;
pub const LUAI_MAXSTACK: usize = 1000000;
pub const STACKERRSPACE: usize = 200;
pub const ERRORSTACKSIZE: usize = LUAI_MAXSTACK + STACKERRSPACE;

// Short strings (< LUAI_MAXSHORTLEN) are interned; long strings (>=) are not.
pub const LUAI_MAXSHORTLEN: usize = 40;

// Size of the API string cache used by luaS_new. The cache reuses recently
// created strings (including long ones) by content, so consecutive identical
// string literals share one object. Mirrors the C reference STRCACHE_N/M.
pub const STRCACHE_N = 53;
pub const STRCACHE_M = 2;

// Basic types
pub const LUA_TNONE: i32 = -1;
pub const LUA_TNIL: i32 = 0;
pub const LUA_TBOOLEAN: i32 = 1;
pub const LUA_TLIGHTUSERDATA: i32 = 2;
pub const LUA_TNUMBER: i32 = 3;
pub const LUA_TSTRING: i32 = 4;
pub const LUA_TTABLE: i32 = 5;
pub const LUA_TFUNCTION: i32 = 6;
pub const LUA_TUSERDATA: i32 = 7;
pub const LUA_TTHREAD: i32 = 8;
pub const LUA_TUPVAL: i32 = 9;

pub const LUA_NUMTYPES: i32 = 10;

// Minimum Lua stack available to a C function
pub const LUA_MINSTACK: i32 = 20;

// Predefined values in the registry
pub const LUA_RIDX_GLOBALS: i32 = 2;
pub const LUA_RIDX_MAINTHREAD: i32 = 3;
pub const LUA_RIDX_LAST: i32 = 3;

// Type of numbers in Lua
pub const lua_Number = luaconf.LUA_NUMBER;

// Type for integer functions
pub const lua_Integer = luaconf.LUA_INTEGER;

// Type for unsigned integer
pub const lua_Unsigned = luaconf.LUA_UNSIGNED;

// Maximum and minimum integer values
pub const LUA_MAXINTEGER: lua_Integer = std.math.maxInt(lua_Integer);
pub const LUA_MININTEGER: lua_Integer = std.math.minInt(lua_Integer);

// ===================================================================
// Debug API constants
// ===================================================================

pub const LUA_IDSIZE: usize = 60;

pub const LUA_HOOKCALL: i32 = 0;
pub const LUA_HOOKRET: i32 = 1;
pub const LUA_HOOKLINE: i32 = 2;
pub const LUA_HOOKCOUNT: i32 = 3;
pub const LUA_HOOKTAILCALL: i32 = 4;

pub const LUA_MASKCALL: u32 = 1 << LUA_HOOKCALL;
pub const LUA_MASKRET: u32 = 1 << LUA_HOOKRET;
pub const LUA_MASKLINE: u32 = 1 << LUA_HOOKLINE;
pub const LUA_MASKCOUNT: u32 = 1 << LUA_HOOKCOUNT;

// Arithmetic and bitwise operators
pub const LUA_OPADD: i32 = 0;
pub const LUA_OPSUB: i32 = 1;
pub const LUA_OPMUL: i32 = 2;
pub const LUA_OPMOD: i32 = 3;
pub const LUA_OPPOW: i32 = 4;
pub const LUA_OPDIV: i32 = 5;
pub const LUA_OPIDIV: i32 = 6;
pub const LUA_OPBAND: i32 = 7;
pub const LUA_OPBOR: i32 = 8;
pub const LUA_OPBXOR: i32 = 9;
pub const LUA_OPSHL: i32 = 10;
pub const LUA_OPSHR: i32 = 11;
pub const LUA_OPUNM: i32 = 12;
pub const LUA_OPBNOT: i32 = 13;

// Comparison operators
pub const LUA_OPEQ: i32 = 0;
pub const LUA_OPLT: i32 = 1;
pub const LUA_OPLE: i32 = 2;

