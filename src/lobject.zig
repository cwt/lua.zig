// $Id: lobject.zig $
//! Value utilities and the shared number-parsing engine (port of lobject.c's
//! number layer, Phase A.1 consolidation per docs/refactor.md).
//!
//! Design (best-for-Zig; docs/refactor.md "Design principle" — the C reference
//! is the semantics oracle, the mechanism is ours):
//!   * One float core: `std.fmt.parseFloat` — allocation-free, correctly
//!     rounded, overflow -> +-inf, whole-string (trailing junk rejected).
//!     It accepts every decimal and hex-float form the C reference accepts
//!     ("1.", "5.", ".5", "1.e2", "0x.8", "0x8.", "0x1.8P+1", ...) and
//!     rejects exactly what C rejects ("1e", "0x", "0x12p", trailing junk).
//!   * Integer-first classification via `parseInteger` (the C reference
//!     `l_str2int` semantics, including its u64 wrap for hex literals past
//!     64 bits — verified identical to the C reference).
//!   * The locale decimal point is DATA (`dp` parameter /
//!     `localeDecimalPoint()`), not global state. The lexer passes '.'
//!     (the reference lexer is locale-independent); coercion passes the
//!     live locale point, so both '.' and it are accepted — matching the
//!     C reference's strtod + replace-first-'.' fallback.
//!   * The C-oracle fixes pinned by the "A1 ..." tests in
//!     tests/test_basic.zig: signed inf/nan spellings are rejected
//!     ("-inf" -> null), there is no length cap (4000-digit strings
//!     parse to +inf), and "3,14" is rejected under the C locale.

const std = @import("std");
const Allocator = std.mem.Allocator;
const libm = @import("libm.zig");
const lua = @import("lua.zig");

// ---------------------------------------------------------------------------
// Character classification (moved here from llex.zig / lua.zig — single
// source; llex.zig re-exports the i32 set for its scanner)
// ---------------------------------------------------------------------------

/// i32 character classes (Lua's `lctype` semantics, ASCII).
pub fn ldigit(c: i32) bool {
    return c >= '0' and c <= '9';
}

pub fn lisxdigit(c: i32) bool {
    return (c >= '0' and c <= '9') or
        (c >= 'a' and c <= 'f') or
        (c >= 'A' and c <= 'F');
}

pub fn lisspace(c: i32) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == '\x0c' or c == '\x0b';
}

pub fn hexval(c: i32) u64 {
    if (c >= '0' and c <= '9') return @intCast(c - '0');
    if (c >= 'a' and c <= 'f') return @intCast(c - 'a' + 10);
    if (c >= 'A' and c <= 'F') return @intCast(c - 'A' + 10);
    return 0;
}

/// u8 character classes (parser-side; moved from lua.zig).
pub fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

pub fn isHexDigit(c: u8) bool {
    return isDigit(c) or (c >= 'a' and c <= 'f') or (c >= 'A' and c <= 'F');
}

pub fn isspace(c: u8) bool {
    return c == ' ' or c == '\t' or c == '\n' or c == '\r' or c == 0x0B or c == 0x0C;
}

pub fn hexValue(c: u8) u64 {
    if (c >= '0' and c <= '9') return c - '0';
    if (c >= 'a' and c <= 'f') return c - 'a' + 10;
    return c - 'A' + 10;
}

// ---------------------------------------------------------------------------
// Integer parsing (moved from lua.zig verbatim)
// ---------------------------------------------------------------------------

/// Parse a whole-string integer (leading/trailing spaces ignored, requires
/// the trimmed string to be an integer); returns null otherwise. Mirrors the
/// C reference `l_str2int`, including its u64 wrap-around when a hex literal
/// exceeds 64 bits (the C reference prints `0x10000000000000000` as 0).
pub fn parseInteger(s: []const u8) ?i64 {
    var i: usize = 0;
    while (i < s.len and isspace(s[i])) : (i += 1) {}
    if (i >= s.len) return null;
    var neg = false;
    if (s[i] == '+' or s[i] == '-') {
        neg = s[i] == '-';
        i += 1;
        if (i >= s.len) return null;
    }
    const is_neg_val: u32 = if (neg) 1 else 0;
    var a: u64 = 0;
    var digits: usize = 0;
    if (s[i] == '0' and i + 1 < s.len and (s[i + 1] == 'x' or s[i + 1] == 'X')) {
        i += 2;
        while (i < s.len and isHexDigit(s[i])) : (i += 1) {
            const d = hexValue(s[i]);
            a = a *% 16 +% d;
            digits += 1;
        }
    } else {
        const max_by_10 = @as(u64, 9223372036854775807) / 10;
        const max_last_d = @as(u32, 9223372036854775807 % 10);
        while (i < s.len and isDigit(s[i])) : (i += 1) {
            const d = @as(u32, s[i] - '0');
            if (a >= max_by_10 and (a > max_by_10 or d > max_last_d + is_neg_val)) {
                return null; // overflow
            }
            a = a * 10 + d;
            digits += 1;
        }
    }
    if (digits == 0) return null;
    var k = i;
    while (k < s.len and isspace(s[k])) : (k += 1) {}
    if (k != s.len) return null; // trailing non-space
    const unsigned_res = if (neg) (0 -% a) else a;
    return @bitCast(unsigned_res);
}

// ---------------------------------------------------------------------------
// Locale decimal point (moved from lua.zig)
// ---------------------------------------------------------------------------

extern "c" fn localeconv() *Lconv;
const Lconv = extern struct {
    decimal_point: [*:0]const u8,
    thousands_sep: [*:0]const u8,
    grouping: [*:0]const u8,
};

/// Return the current locale's decimal-point character ('.' if unknown).
pub fn localeDecimalPoint() u8 {
    const lc = localeconv();
    const dp = lc.decimal_point;
    if (dp[0] == 0) return '.';
    return dp[0];
}

// ---------------------------------------------------------------------------
// Shared float engine
// ---------------------------------------------------------------------------

// Maximum number of significant hex digits the reference reads per hex float.
const MAXSIGDIG: usize = 30;

/// The C reference `lua_strx2number` algorithm (hex floats only).
/// `end_out` receives the index just past the last consumed character.
/// Returns 0 when the text is not a hex float at all.
fn hexFloatValue(s: []const u8, end_out: *usize) f64 {
    var i: usize = 0;
    while (i < s.len and lisspace(s[i])) : (i += 1) {}
    const neg = (i < s.len and s[i] == '-');
    if (neg or (i < s.len and s[i] == '+')) i += 1;
    if (!(i + 1 < s.len and s[i] == '0' and (s[i + 1] == 'x' or s[i + 1] == 'X'))) {
        return 0;
    }
    i += 2;
    var r: f64 = 0;
    var sigdig: usize = 0;
    var nosigdig: usize = 0;
    var e: i32 = 0;
    var hasdot = false;
    while (i < s.len) : (i += 1) {
        if (s[i] == '.') {
            if (hasdot) break;
            hasdot = true;
        } else if (lisxdigit(s[i])) {
            const d: f64 = @floatFromInt(hexval(s[i]));
            if (sigdig == 0 and hexval(s[i]) == 0) {
                nosigdig += 1;
            } else if (sigdig < MAXSIGDIG) {
                sigdig += 1;
                r = r * 16 + d;
            } else {
                e += 1;
            }
            if (hasdot) e -= 1;
        } else break;
    }
    if (nosigdig + sigdig == 0) return 0;
    end_out.* = i;
    e *= 4;
    if (i < s.len and (s[i] == 'p' or s[i] == 'P')) {
        i += 1;
        const neg1 = (i < s.len and s[i] == '-');
        if (neg1 or (i < s.len and s[i] == '+')) i += 1;
        if (i >= s.len or !ldigit(s[i])) return 0;
        var exp1: i32 = 0;
        while (i < s.len and ldigit(s[i])) : (i += 1) {
            exp1 = exp1 * 10 + (s[i] - '0');
        }
        if (neg1) exp1 = -exp1;
        e += exp1;
        end_out.* = i;
    }
    if (neg) r = -r;
    return libm.getLibm().ldexp(r, e);
}

/// Parse `s` (whole string, no surrounding whitespace) as an f64 number.
/// `dp` is the locale decimal point as data: '.' and `dp` both act as the
/// decimal point, every other character makes the parse fail. Overflow
/// yields +-inf and underflow yields 0 (C `strtod` semantics).
///
/// Hex floats go through the C reference `lua_strx2number` algorithm
/// (bit-exact with the C reference; `std.fmt.parseFloat` is NOT
/// correctly rounded for long hex significands — 150-digit cases land
/// 1 ULP low).
///
/// `gpa` is used only in the rare case where remapping the locale decimal
/// point is required AND `s.len > 1024`; pass null for the allocation-free
/// usage (that single case then yields null instead).
pub fn parseNumericFloat(gpa: ?Allocator, s: []const u8, dp: u8) ?f64 {
    // Hex floats (the decimal point of a hex float is always '.').
    {
        var i: usize = 0;
        while (i < s.len and isspace(s[i])) : (i += 1) {}
        if (i + 1 < s.len and s[i] == '0' and (s[i + 1] == 'x' or s[i + 1] == 'X')) {
            const t = s[i..];
            var end: usize = 0;
            const v = hexFloatValue(t, &end);
            var j = end;
            while (j < t.len and isspace(t[j])) : (j += 1) {}
            if (j != t.len) return null; // trailing garbage
            return v;
        }
    }
    const need_map = dp != '.' and std.mem.indexOfScalar(u8, s, dp) != null;
    if (!need_map) {
        // Fast path: parse in place — no copy, no allocation, works for
        // arbitrarily long digit strings.
        return std.fmt.parseFloat(f64, s) catch null;
    }
    
    var small: [1024]u8 = undefined;
    if (s.len <= small.len) {
        for (s, 0..) |c, i| small[i] = if (c == dp) '.' else c;
        return std.fmt.parseFloat(f64, small[0..s.len]) catch null;
    }
    if (gpa) |a| {
        const buf = a.alloc(u8, s.len) catch return null;
        defer a.free(buf);
        for (s, 0..) |c, i| buf[i] = if (c == dp) '.' else c;
        return std.fmt.parseFloat(f64, buf) catch null;
    }
    return null;
}

// ---------------------------------------------------------------------------
// String -> number coercion (integer-first, C-oracle semantics)
// ---------------------------------------------------------------------------

/// True when `s` begins with "inf" or "nan" (case-insensitive).
fn isInfNanPrefix(s: []const u8) bool {
    if (s.len < 3) return false;
    const c0 = std.ascii.toLower(s[0]);
    const c1 = std.ascii.toLower(s[1]);
    const c2 = std.ascii.toLower(s[2]);
    return (c0 == 'i' and c1 == 'n' and c2 == 'f') or
        (c0 == 'n' and c1 == 'a' and c2 == 'n');
}

/// Coercion core (C-oracle semantics): leading/trailing spaces ignored,
/// integer-preferred, '.' and the locale decimal point accepted, all
/// inf/nan spellings (including signed) rejected, no length cap.
fn tonumberImpl(gpa: ?Allocator, s: []const u8) ?lua.TValue {
    if (s.len == 0) return null;
    var start: usize = 0;
    while (start < s.len and isspace(s[start])) : (start += 1) {}
    if (start >= s.len) return null;
    var end = s.len;
    while (end > start and isspace(s[end - 1])) : (end -= 1) {}
    const t = s[start..end];
    {
        var i: usize = 0;
        if (t[i] == '+' or t[i] == '-') i += 1;
        if (isInfNanPrefix(t[i..])) return null;
    }
    if (parseInteger(t)) |iv| return lua.TValue{ .integer = iv };
    if (parseNumericFloat(gpa, t, localeDecimalPoint())) |n| return lua.TValue{ .number = n };
    return null;
}

/// Allocation-free specialization (the VM hot path, via lua.zig's
/// re-export): under the C locale the common path never allocates.
pub fn tonumberValue(s: []const u8) ?lua.TValue {
    return tonumberImpl(null, s);
}

/// C API: parse `s` as a number and push it. Returns `s.len + 1` on
/// success (consumed-length + 1, reference convention), 0 on failure.
/// Full fidelity: threads `L.allocator` for the rare long-string locale
/// remapping case.
pub fn lua_stringtonumber(L: *lua.lua_State, s: []const u8) usize {
    if (tonumberImpl(L.allocator, s)) |v| {
        switch (v) {
            .integer => |iv| lua.lua_pushinteger(L, iv),
            .number => |n| lua.lua_pushnumber(L, n),
            else => unreachable,
        }
        return s.len + 1;
    }
    return 0;
}
