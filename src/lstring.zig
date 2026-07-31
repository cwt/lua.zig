// $Id: lstring.zig
// String interning for Lua.zig (Zig port of Lua 5.5.1)
// See Copyright Notice in lua.h
//
// Equal string contents share a single `lua_TString`, so table lookups can
// compare short strings by pointer identity (mirroring the C reference, where
// short strings are interned in `global_State.strt`).

const std = @import("std");
const lua = @import("lua.zig");
const llimits = @import("llimits.zig");

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

/// Return an interned `lua_TString` for the given byte slice.
///
/// Mirrors the C reference `luaS_new`: first check the global string cache
/// (`global_State.strcache`), a small content-addressed cache that reuses
/// recently-created strings — including long strings, which are otherwise
/// not interned. This guarantees that consecutive identical string literals
/// share a single object (relied on by the 'literals' test suite).
pub fn luaS_new(
    L: *lua.lua_State,
    s: []const u8,
) !*lua.lua_TString {
    const g = L.l_G orelse return error.NoGlobalState;

    if (s.len <= llimits.LUAI_MAXSHORTLEN) {
        // 1. Check the API string cache first for short strings.
        const hash = luaS_hash(s, g.seed);
        const bucket = hash % llimits.STRCACHE_N;
        const cache = &g.strcache[bucket];
        var j: usize = 0;
        while (j < llimits.STRCACHE_M) : (j += 1) {
            if (cache[j]) |ts| {
                if (ts.len == s.len and std.mem.eql(u8, s, ts.s)) {
                    ts.marked = true;
                    return ts; // cache hit: reuse same object
                }
            }
        }

        // 2. Normal route: intern short strings.
        const ts = try createString(L, s);

        // 3. Insert into the cache (shift back, put new at front).
        var k: usize = llimits.STRCACHE_M - 1;
        while (k > 0) : (k -= 1) {
            cache[k] = cache[k - 1];
        }
        cache[0] = ts;
        return ts;
    } else {
        return try createString(L, s);
    }
}

/// Create a fresh `lua_TString`: short strings are interned in `strt`,
/// long strings are allocated and registered with the GC.
fn createString(L: *lua.lua_State, s: []const u8) !*lua.lua_TString {
    const g = L.l_G orelse return error.NoGlobalState;
    if (s.len <= llimits.LUAI_MAXSHORTLEN) {
        // Short string: intern in strt (reuse identical strings).
        const gop = try g.strt.getOrPut(g.allocator, s);
        if (gop.found_existing) {
            return gop.value_ptr.*;
        }
        const key = try g.allocator.dupe(u8, s);
        gop.key_ptr.* = key;
        const ts = try g.allocator.create(lua.lua_TString);
        ts.* = .{
            .s = key,
            .len = key.len,
            .hash = luaS_hash(key, g.seed),
        };
        gop.value_ptr.* = ts;
        g.gc_count += 1;
        return ts;
    } else {
        const key = try g.allocator.dupe(u8, s);
        const ts = try g.allocator.create(lua.lua_TString);
        ts.* = .{
            .s = key,
            .len = key.len,
            .hash = luaS_hash(key, g.seed),
        };
        try lua.registerGC(L, ts);
        return ts;
    }
}

/// Raw equality of two (already interned) strings. Pointer identity is the
/// fast path; content equality is the safe fallback.
pub fn luaS_eqstr(a: *lua.lua_TString, b: *lua.lua_TString) bool {
    if (a == b) return true;
    return std.mem.eql(u8, a.s, b.s);
}
