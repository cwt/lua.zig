// $Id: lprefix.h $
// Definitions for Lua code that must come before any other header file
// See Copyright Notice in c_compat.zig

const std = @import("std");

// Allows POSIX/XSI stuff (not directly applicable in Zig, but kept for compatibility)
// _XOPEN_SOURCE, _FILE_OFFSET_BITS, etc. are not used in Zig

// Windows stuff (not applicable)
// _CRT_SECURE_NO_WARNINGS is not used in Zig
