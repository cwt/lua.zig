// $Id: lstring.zig
// String interning for Lua.zig (Zig port of Lua 5.5.1)
// See Copyright Notice in lua.h
//
// Equal string contents share a single `lua_TString`, so table lookups can
// compare short strings by pointer identity (mirroring the C reference, where
// short strings are interned in `global_State.strt`).

const std = @import("std");
const lua = @import("lua.zig");

/// Hash a string with the given seed. A good, stable distribution is what
/// matters here; we use FNV-1a over the bytes.
pub fn luaS_hash(str: []const u8, seed: usize) u32 {
    var h: u32 = @as(u32, @truncate(seed)) ^ 0x9e3779b9;
    for (str) |c| {
        h ^= c;
        h *%= 16777619;
    }
    return h;
}

/// Return an interned `lua_TString` for the given byte slice. If an equal
/// string already exists it is reused; otherwise a fresh `lua_TString` is
/// allocated and linked into `strt`. The bytes are owned by the map's key
/// storage, so `ts.s` points at stable memory.
pub fn luaS_new(
    allocator: std.mem.Allocator,
    strt: *std.array_hash_map.String(*lua.lua_TString),
    seed: usize,
    s: []const u8,
) !*lua.lua_TString {
    const gop = try strt.getOrPut(allocator, s);
    if (gop.found_existing) {
        return gop.value_ptr.*;
    }
    const key = gop.key_ptr.*;
    const ts = try allocator.create(lua.lua_TString);
    ts.* = .{
        .s = key,
        .len = key.len,
        .hash = luaS_hash(key, seed),
    };
    gop.value_ptr.* = ts;
    return ts;
}

/// Raw equality of two (already interned) strings. Pointer identity is the
/// fast path; content equality is the safe fallback.
pub fn luaS_eqstr(a: *lua.lua_TString, b: *lua.lua_TString) bool {
    if (a == b) return true;
    return std.mem.eql(u8, a.s, b.s);
}
