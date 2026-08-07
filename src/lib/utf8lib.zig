//
// ** $Id: utf8lib.zig $
// ** UTF-8 library for Lua.zig (Zig port of Lua 5.5.0's lutf8lib.c)
// ** See Copyright Notice in lua.h
//

const std = @import("std");
const lua = @import("../lua.zig");
const lauxlib = @import("../lauxlib.zig");

const MAXUNICODE: u32 = 0x10FFFF;
const MAXUTF: u32 = 0x7FFFFFFF;
const MSGInvalid: []const u8 = "invalid UTF-8 code";

// Pattern to match a single UTF-8 character (a literal NUL is part of the
// first class, so it must be written with an explicit \x00 escape).
const UTF8PATT: []const u8 = "[\x00-\x7F\xC2-\xFD][\x80-\xBF]*";

// Continuation byte: top two bits are 10.
fn iscont(c: u8) bool {
    return (c & 0xC0) == 0x80;
}

// `iscont` for an index that may be at or past the end of the slice.
// Past the end behaves like a NUL terminator (not a continuation byte),
// matching the C reference's NUL-terminated string semantics.
fn iscont_at(s: []const u8, idx: usize) bool {
    if (idx >= s.len) return false;
    return iscont(s[idx]);
}

// Decode one UTF-8 sequence from `s`, returning the number of bytes consumed
// (1-based count) or `null` if the byte sequence is invalid. The decoded
// codepoint is written to `val` when non-null.
fn utf8_decode(s: []const u8, val: ?*u32, strict: bool) ?usize {
    const limits = [_]u32{
        ~@as(u32, 0),
        0x80,
        0x800,
        0x10000,
        0x200000,
        0x4000000,
    };
    if (s.len == 0) return null;
    const c0 = s[0];
    var res: u32 = 0;
    var consumed: usize = 1;
    if (c0 < 0x80) {
        res = c0;
    } else if (c0 >= 0xFE) {
        return null;
    } else {
        var count: usize = 0;
        var c: u32 = c0;
        while (c & 0x40 != 0) {
            count += 1;
            if (count >= s.len) return null;
            const cc = s[count];
            if (!iscont(cc)) return null;
            res = (res << 6) | (@as(u32, cc & 0x3F));
            c <<= 1;
        }
        if (count >= limits.len) return null;
        res |= (@as(u32, c & 0x7F) << @as(u5, @truncate(count * 5)));
        if (res > MAXUTF or res < limits[count]) return null;
        if (strict) {
            if (res > MAXUNICODE or (0xD800 <= res and res <= 0xDFFF)) return null;
        }
        consumed = count + 1;
    }
    if (val) |v| v.* = res;
    return consumed;
}

// Translate a relative string position: negative means back from end.
fn u_posrelat(pos: i64, slen: usize) i64 {
    if (pos >= 0) return pos;
    const abs: usize = @as(usize, @intCast(-pos));
    if (abs > slen) return 0;
    return @as(i64, @intCast(slen)) + pos + 1;
}

// Encode a codepoint (up to MAXUTF) into UTF-8 bytes, returning the count.
fn encode_utf8(code: u32, buf: *[6]u8) usize {
    var x = code;
    if (x < 0x80) {
        buf[0] = @as(u8, @intCast(x));
        return 1;
    }
    var nb: u32 = 1;
    if (x >= 0x80) nb = 2;
    if (x >= 0x800) nb = 3;
    if (x >= 0x10000) nb = 4;
    if (x >= 0x200000) nb = 5;
    if (x >= 0x4000000) nb = 6;
    const i: usize = nb - 1;
    buf[i] = @as(u8, @intCast(x & 0x3F)) | 0x80;
    x >>= 6;
    var j: u32 = nb - 1;
    while (j > 1) : (j -= 1) {
        buf[j - 1] = @as(u8, @intCast(x & 0x3F)) | 0x80;
        x >>= 6;
    }
    const first: u8 = @as(u8, 0xFF) << @as(u3, @intCast(8 - nb));
    buf[0] = @as(u8, @intCast(x)) | first;
    return nb;
}

// ===================================================================
// utf8.len
// ===================================================================

fn len(L: *lua.lua_State) !i32 {
    const s = try lauxlib.luaL_checklstring(L, 1, null);
    const slen = s.len;
    const posi = u_posrelat(lauxlib.luaL_optinteger(L, 2, 1), slen);
    const posj = u_posrelat(lauxlib.luaL_optinteger(L, 3, -1), slen);
    const lax = lua.lua_toboolean(L, 4) != 0;

    try lauxlib.luaL_argcheck(L, 1 <= posi and (posi - 1) <= @as(i64, @intCast(slen)), 2, "initial position out of bounds");
    try lauxlib.luaL_argcheck(L, (posj - 1) < @as(i64, @intCast(slen)), 3, "final position out of bounds");

    var pi: i64 = posi - 1;
    const pj: i64 = posj - 1;
    var n: i64 = 0;
    while (pi <= pj) {
        const consumed = utf8_decode(s[@as(usize, @intCast(pi))..], null, !lax);
        if (consumed == null) {
            lauxlib.luaL_pushfail(L);
            lua.lua_pushinteger(L, pi + 1);
            return 2;
        }
        pi += @as(i64, @intCast(consumed.?));
        n += 1;
    }
    lua.lua_pushinteger(L, n);
    return 1;
}

// ===================================================================
// utf8.codepoint
// ===================================================================

fn codepoint(L: *lua.lua_State) !i32 {
    const s = try lauxlib.luaL_checklstring(L, 1, null);
    const slen = s.len;
    const posi = u_posrelat(lauxlib.luaL_optinteger(L, 2, 1), slen);
    const pose = u_posrelat(lauxlib.luaL_optinteger(L, 3, posi), slen);
    const lax = lua.lua_toboolean(L, 4) != 0;

    try lauxlib.luaL_argcheck(L, posi >= 1, 2, "out of bounds");
    try lauxlib.luaL_argcheck(L, pose <= @as(i64, @intCast(slen)), 3, "out of bounds");
    if (posi > pose) return 0;

    const n_ret: i32 = @as(i32, @intCast(pose - posi)) + 1;
    try lauxlib.luaL_checkstack(L, n_ret, "string slice too long");

    var start: usize = @as(usize, @intCast(posi - 1));
    const end_pos: usize = @as(usize, @intCast(pose));
    var count: i32 = 0;
    while (start < end_pos) {
        var code: u32 = 0;
        const consumed = utf8_decode(s[start..], &code, !lax) orelse {
            return lauxlib.luaL_error(L, MSGInvalid);
        };
        lua.lua_pushinteger(L, @as(i64, code));
        count += 1;
        start += consumed;
    }
    return count;
}

// ===================================================================
// utf8.char
// ===================================================================

fn pushutfchar(L: *lua.lua_State, arg: i32) !void {
    const code_i = try lauxlib.luaL_checkinteger(L, arg);
    try lauxlib.luaL_argcheck(L, code_i >= 0 and code_i <= MAXUTF, arg, "value out of range");
    const code: u32 = @intCast(code_i);
    var buf: [6]u8 = undefined;
    const written = encode_utf8(code, &buf);
    _ = lua.lua_pushlstring(L, buf[0..written], written);
}

fn char_(L: *lua.lua_State) !i32 {
    const n = lua.lua_gettop(L);
    if (n == 1) {
        try pushutfchar(L, 1);
    } else {
        var list = std.ArrayList(u8).empty;
        defer list.deinit(L.allocator);
        var i: i32 = 1;
        while (i <= n) : (i += 1) {
            const code_i = try lauxlib.luaL_checkinteger(L, i);
            try lauxlib.luaL_argcheck(L, code_i >= 0 and code_i <= MAXUTF, i, "value out of range");
            const code: u32 = @intCast(code_i);
            var buf: [6]u8 = undefined;
            const written = encode_utf8(code, &buf);
            try list.appendSlice(L.allocator, buf[0..written]);
        }
        _ = lua.lua_pushlstring(L, list.items, list.items.len);
    }
    return 1;
}

// ===================================================================
// utf8.offset
// ===================================================================

fn offset(L: *lua.lua_State) !i32 {
    const s = try lauxlib.luaL_checklstring(L, 1, null);
    const slen = s.len;
    const n = try lauxlib.luaL_checkinteger(L, 2);
    const posi0: i64 = if (n >= 0) 1 else @as(i64, @intCast(slen)) + 1;
    const posi = u_posrelat(lauxlib.luaL_optinteger(L, 3, posi0), slen);

    try lauxlib.luaL_argcheck(L, 1 <= posi and (posi - 1) <= @as(i64, @intCast(slen)), 3, "position out of bounds");

    var posi_b: i64 = posi - 1;
    var m = n;
    if (n == 0) {
        while (posi_b > 0 and iscont_at(s, @as(usize, @intCast(posi_b)))) {
            posi_b -= 1;
        }
    } else {
        if (iscont_at(s, @as(usize, @intCast(posi_b)))) {
            return lauxlib.luaL_error(L, "initial position is a continuation byte");
        }
        if (n < 0) {
            while (m < 0 and posi_b > 0) {
                posi_b -= 1;
                while (posi_b > 0 and iscont_at(s, @as(usize, @intCast(posi_b)))) {
                    posi_b -= 1;
                }
                m += 1;
            }
        } else {
            m -= 1;
            while (m > 0 and posi_b < @as(i64, @intCast(slen))) {
                posi_b += 1;
                while (iscont_at(s, @as(usize, @intCast(posi_b)))) {
                    posi_b += 1;
                }
                m -= 1;
            }
        }
    }
    if (m != 0) {
        lauxlib.luaL_pushfail(L);
        return 1;
    }
    lua.lua_pushinteger(L, posi_b + 1);
    // Multi-byte character? Push its final position too.
    if (posi_b < @as(i64, @intCast(slen)) and (s[@as(usize, @intCast(posi_b))] & 0x80) != 0) {
        if (iscont_at(s, @as(usize, @intCast(posi_b)))) {
            return lauxlib.luaL_error(L, "initial position is a continuation byte");
        }
        while (posi_b + 1 < @as(i64, @intCast(slen)) and iscont_at(s, @as(usize, @intCast(posi_b + 1)))) {
            posi_b += 1;
        }
    }
    lua.lua_pushinteger(L, posi_b + 1);
    return 2;
}

// ===================================================================
// utf8.codes iterator
// ===================================================================

fn iter_aux(L: *lua.lua_State, strict: bool) !i32 {
    const s = try lauxlib.luaL_checklstring(L, 1, null);
    const slen = s.len;
    const n = lua.lua_tointeger(L, 2) orelse 0;
    var nn: usize = if (n < 0) 0 else @intCast(n);
    if (nn < slen) {
        while (iscont_at(s, nn)) nn += 1;
    }
    if (nn >= slen) return 0;
    var code: u32 = 0;
    const consumed = utf8_decode(s[nn..], &code, strict) orelse {
        return lauxlib.luaL_error(L, MSGInvalid);
    };
    if (iscont_at(s, nn + consumed)) {
        return lauxlib.luaL_error(L, MSGInvalid);
    }
    lua.lua_pushinteger(L, @intCast(nn + 1));
    lua.lua_pushinteger(L, @as(i64, code));
    return 2;
}

fn iter_auxstrict(L: *lua.lua_State) !i32 {
    return iter_aux(L, true);
}

fn iter_auxlax(L: *lua.lua_State) !i32 {
    return iter_aux(L, false);
}

fn codes(L: *lua.lua_State) !i32 {
    const lax = lua.lua_toboolean(L, 2) != 0;
    const s = try lauxlib.luaL_checklstring(L, 1, null);
    try lauxlib.luaL_argcheck(L, !iscont_at(s, 0), 1, MSGInvalid);
    lua.lua_pushcfunction(L, if (lax) &iter_auxlax else &iter_auxstrict);
    lua.lua_pushvalue(L, 1);
    lua.lua_pushinteger(L, 0);
    return 3;
}

// ===================================================================
// Library registration
// ===================================================================

pub fn openutf8lib(L: *lua.lua_State) !void {
    lua.lua_createtable(L, 0, 6);

    lua.lua_pushcfunction(L, offset);
    try lua.lua_setfield(L, -2, "offset");

    lua.lua_pushcfunction(L, codepoint);
    try lua.lua_setfield(L, -2, "codepoint");

    lua.lua_pushcfunction(L, char_);
    try lua.lua_setfield(L, -2, "char");

    lua.lua_pushcfunction(L, len);
    try lua.lua_setfield(L, -2, "len");

    lua.lua_pushcfunction(L, codes);
    try lua.lua_setfield(L, -2, "codes");

    _ = lua.lua_pushlstring(L, UTF8PATT, UTF8PATT.len);
    try lua.lua_setfield(L, -2, "charpattern");

    try lua.lua_setglobal(L, "utf8");
}
