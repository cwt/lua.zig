// $Id: luaconf.h $
// Configuration file for Lua.zig (Zig port of Lua 5.5.1)
// See Copyright Notice in c_compat.zig

const std = @import("std");

// ===================================================================
// General Configuration
// ===================================================================

// LUA_USE_C89: controls use of non-ISO-C89 features (not applicable in Zig)
// #define LUA_USE_C89

// Windows-specific features
// #define LUA_USE_WINDOWS
// #define LUA_DL_DLL

// POSIX features
// #define LUA_USE_POSIX
// #define LUA_USE_DLOPEN

// ===================================================================
// Number types configuration
// ===================================================================

// Default: double for floats, long long for integers
pub const LUA_NUMBER = f64;
pub const LUA_INTEGER = i64;
pub const LUA_UNSIGNED = u64;

// ===================================================================
// Path configuration
// ===================================================================

pub const LUA_PATH_SEP: u8 = ';';
pub const LUA_PATH_MARK: []const u8 = "?";
pub const LUA_EXEC_DIR: []const u8 = "!";

pub const LUA_VDIR: []const u8 = "5.5";

pub const LUA_LDIR: []const u8 = "!/lua/";
pub const LUA_CDIR: []const u8 = "//!";
pub const LUA_SHRDIR: []const u8 = "//!share/lua/";

pub const LUA_PATH_DEFAULT: []const u8 =
    LUA_LDIR ++ "?.lua;" ++ LUA_LDIR ++ "?/init.lua;" ++
    LUA_CDIR ++ "?.lua;" ++ LUA_CDIR ++ "?/init.lua;" ++
    "./?.lua;" ++ "./?/init.lua";

pub const LUA_CPATH_DEFAULT: []const u8 =
    LUA_CDIR ++ "?.so;" ++ LUA_CDIR ++ "loadall.so;" ++ "./?.so";

pub const LUA_DIRSEP: []const u8 = "/";

pub const LUA_IGMARK: []const u8 = "-";

// ===================================================================
// Exported symbols
// ===================================================================

// LUA_API: mark for all core API functions (exported)
pub const LUA_API = true;

pub const LUALIB_API = LUA_API;

// LUAMOD_API: mark for all standard library opening functions
pub const LUAMOD_API = true;

// ===================================================================
// Compatibility macros
// ===================================================================

// LUA_COMPAT_GLOBAL: avoids 'global' being a reserved word
pub const LUA_COMPAT_GLOBAL: bool = true;

// LUA_COMPAT_LOOPVAR: for-loop control variables not read-only
pub const LUA_COMPAT_LOOPVAR: bool = false;

// ===================================================================
// Local configuration
// ===================================================================

// LUA_EXTRASPACE: size of raw memory area associated with a Lua state
pub const LUA_EXTRASPACE: usize = @sizeOf(void);

// LUA_IDSIZE: maximum size for the description of the source of a function
pub const LUA_IDSIZE: usize = 60;

// LUAL_BUFFERSIZE: initial buffer size used by the lauxlib buffer system
pub const LUAL_BUFFERSIZE: usize = 16 * @sizeOf(void) * @sizeOf(LUA_NUMBER);
