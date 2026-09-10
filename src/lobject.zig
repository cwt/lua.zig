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
const lstring = @import("lstring.zig");
const ltm = @import("ltm.zig");

// C interop (same linkage as the declaration in lua.zig).
extern "c" fn strtod(nptr: [*:0]const u8, endptr: ?*?[*:0]const u8) f64;
extern "c" fn strspn(str1: [*]const u8, str2: [*]const u8) usize;

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


// ---------------------------------------------------------------------------
// Message builders + tostring/ equality helpers (lobject.c remainder,
// Refactor B3 — moved from lua.zig; re-exported by lua.zig)
// ---------------------------------------------------------------------------
pub fn tostringbuffFloat(n: f64, buff: *[128]u8) usize {
    var len = lua.snprintf(buff, 128, "%.15g", n);
    if (len < 0) return 0;
    buff[@intCast(len)] = 0;
    const check = strtod(@ptrCast(buff), null);
    if (check != n) {
        len = lua.snprintf(buff, 128, "%.17g", n);
        if (len < 0) return 0;
        buff[@intCast(len)] = 0;
    }
    const idx = strspn(buff, "-0123456789");
    if (buff[idx] == 0) {
        const ulen: usize = @intCast(len);
        buff[ulen] = '.';
        buff[ulen + 1] = '0';
        buff[ulen + 2] = 0;
        return ulen + 2;
    }
    return @intCast(len);
}

pub fn luaO_tostringbuff(val: lua.TValue, buff: *[128]u8) []const u8 {
    return switch (val) {
        .integer => |i| lua.fmtMsg(buff, "", "{d}", .{i}),
        .number => |n| {
            if (std.math.isNan(n)) {
                return "nan";
            } else if (std.math.isInf(n)) {
                return if (n < 0) "-inf" else "inf";
            }
            const len = tostringbuffFloat(n, buff);
            return buff[0..len];
        },
        .string => |s| if (s) |str| str.s else "",
        else => "",
    };
}

pub fn toNumeric(v: lua.TValue) ?lua.TValue {
    return switch (v) {
        .integer => v,
        .number => v,
        .string => |s| {
            const str = s orelse return null;
            // Locale-aware parse (mirrors lua_stringtonumber via tonumberValue).
            return tonumberValue(str.s);
        },
        else => null,
    };
}

pub fn luaV_rawequalobj(t1: lua.TValue, t2: lua.TValue) bool {
    if (t1 == .number and t2 == .number) {
        return t1.number == t2.number;
    }
    if (t1 == .integer and t2 == .integer) {
        return t1.integer == t2.integer;
    }
    if (t1 == .integer and t2 == .number) {
        const i = t1.integer;
        const f = t2.number;
        return f == @as(f64, @floatFromInt(i)) and i == @as(i64, @intFromFloat(f));
    }
    if (t1 == .number and t2 == .integer) {
        const f = t1.number;
        const i = t2.integer;
        return f == @as(f64, @floatFromInt(i)) and i == @as(i64, @intFromFloat(f));
    }
    if (@as(std.meta.Tag(lua.TValue), t1) != @as(std.meta.Tag(lua.TValue), t2)) {
        return false;
    }
    return switch (t1) {
        .nil => true,
        .boolean => |b| b == t2.boolean,
        .number => |n| n == t2.number,
        .integer => |n| n == t2.integer,
        .lightud => |p| p == t2.lightud,
        .string => |s| blk: {
            const t2s = t2.string;
            if (s == null and t2s == null) break :blk true;
            if (s == null or t2s == null) break :blk false;
            break :blk lstring.luaS_eqstr(s.?, t2s.?);
        },
        .function => |f| f == t2.function,
        .table => |t| t == t2.table,
        .userdata => |u| u == t2.userdata,
        .thread => |t| t == t2.thread,
        .upval => |u| u == t2.upval,
        .proto => |p| p == t2.proto,
    };
}

pub fn luaG_runerror(L: *lua.lua_State, msg: []const u8) !void {
    var full_msg: [512]u8 = undefined;
    var final_msg = msg;
    if (L.ci) |ci| {
        if (lua.isLua(ci, L)) {
            const val = L.stack[ci.func];
            if (val == .function and val.function != null and val.function.?.* == .lua) {
                const proto = val.function.?.lua.p;
                if (proto.source) |src| {
                    var chunkid_buf: [lua.LUA_IDSIZE]u8 = undefined;
                    lua.luaO_chunkid(&chunkid_buf, src.s);
                    const chunkid = std.mem.sliceTo(&chunkid_buf, 0);
                    const line = lua.luaG_getfuncline(proto, lua.currentpc(ci));
                    if (std.fmt.bufPrint(&full_msg, "{s}:{d}: {s}", .{ chunkid, line, msg })) |formatted| {
                        final_msg = formatted;
                    } else |_| {}
                } else {
                    if (std.fmt.bufPrint(&full_msg, "?:?: {s}", .{msg})) |formatted| {
                        final_msg = formatted;
                    } else |_| {}
                }
            }
        }
    }
    const ts = lstring.luaS_new(L, final_msg) catch null;
    if (ts) |t| {
        L.stack[L.top] = lua.TValue{ .string = t };
        L.top += 1;
    } else {
        L.stack[L.top] = lua.TValue{ .nil = {} };
        L.top += 1;
    }
    return lua.lua_error(L);
}

/// Value-equality test used by `varinfo` to locate the operand register.
fn tvEqual(a: lua.TValue, b: lua.TValue) bool {
    if (a == .nil and b == .nil) return true;
    if (a.isNumberValue() and b.isNumberValue()) {
        return a.toFloat() == b.toFloat();
    }
    if (a == .boolean and b == .boolean) return a.boolean == b.boolean;
    if (a == .integer and b == .integer) return a.integer == b.integer;
    if (a == .string and b == .string) return a.string == b.string;
    return false;
}

/// Mirror PUC-Rio `varinfo`: locate `o` in the current Lua frame and build a
/// description such as ` (field 'huge')` or ` (global 'x')`, written into `buf`.
/// Returns the slice of `buf` used, or `""` if unknown.
fn luaG_varinfo(L: *lua.lua_State, o_ptr: *const lua.TValue, buf: []u8) []const u8 {
    var ci = L.ci orelse return "";
    if (!lua.isLua(ci, L)) {
        ci = ci.previous orelse return "";
        if (!lua.isLua(ci, L)) return "";
    }
    if (ci.func >= L.stack.len) return "";
    const val = L.stack[ci.func];
    if (val != .function or val.function == null) return "";
    const cl = val.function.?;
    if (cl.* != .lua) return "";
    const lcl = cl.lua;

    // 1. Check exact upvalue pointer match first
    for (lcl.upvals, 0..) |opt_uv, uv_idx| {
        if (opt_uv) |uv| {
            if (uv.v == o_ptr) {
                const uname = lua.upvalname(lcl.p, uv_idx);
                return lua.fmtMsg(buf, "", " (upvalue '{s}')", .{uname});
            }
        }
    }

    const p = lcl.p;
    const base = ci.base;
    var reg: i32 = -1;

    // 2. Check exact stack pointer match
    const o_addr = @intFromPtr(o_ptr);
    const stack_addr = @intFromPtr(L.stack.ptr);
    const stack_end_addr = stack_addr + L.stack.len * @sizeOf(lua.TValue);
    if (o_addr >= stack_addr and o_addr < stack_end_addr) {
        const idx = (o_addr - stack_addr) / @sizeOf(lua.TValue);
        if (idx >= base and idx < ci.top) {
            reg = @intCast(idx - base);
        }
    }

    // 3. Fall back to upvalue value match
    if (reg < 0) {
        for (lcl.upvals, 0..) |opt_uv, uv_idx| {
            if (opt_uv) |uv| {
                if (tvEqual(uv.v.*, o_ptr.*)) {
                    const uname = lua.upvalname(lcl.p, uv_idx);
                    return lua.fmtMsg(buf, "", " (upvalue '{s}')", .{uname});
                }
            }
        }
    }

    // 4. Fall back to stack register value match
    if (reg < 0) {
        var idx: usize = base;
        const limit = @min(ci.top, L.stack.len);
        while (idx < limit) : (idx += 1) {
            if (tvEqual(L.stack[idx], o_ptr.*)) {
                reg = @intCast(idx - base);
                break;
            }
        }
    }

    if (reg < 0) return "";
    var name: ?[]const u8 = null;
    const kind = lua.getobjname(p, lua.currentpc(ci), reg, &name) orelse return "";
    if (name == null) return "";
    return lua.fmtMsg(buf, "", " ({s} '{s}')", .{ kind, name.? });
}

/// Error when a value cannot be converted to an integer (bitwise/shift operand
/// or `floor`/integer coercion). Mirrors PUC-Rio `luaG_tointerror`: the message
/// is `"number%s has no integer representation"`, where `%s` is the operand's
/// `varinfo` (e.g. ` (field 'huge')`).
/// A4 (docs/refactor.md): shared tail of the `luaG_*` error-message
/// builders — the repeated
/// `const mslice = lua.fmtMsg(buf, fallback, fmt, args); return
/// luaG_runerror(L, mslice);` two-step. Callers keep their own fixed
/// buffer (each site's overflow behavior is preserved exactly) and pass
/// pre-formatted fragments (e.g. `luaG_varinfo` results) as args.
fn luaG_err(L: *lua.lua_State, buf: []u8, fallback: []const u8, comptime fmt: []const u8, args: anytype) !void {
    return luaG_runerror(L, lua.fmtMsg(buf, fallback, fmt, args));
}

pub fn luaG_errnnil(L: *lua.lua_State, proto: *const lua.lua_Proto, k: i32) !void {
    var globalname: []const u8 = "?";
    if (k > 0 and @as(usize, @intCast(k - 1)) < proto.k.len) {
        const kv = proto.k[@as(usize, @intCast(k - 1))];
        if (kv == .string) {
            if (kv.string) |ts| globalname = ts.s;
        }
    }
    var buf: [256]u8 = undefined;
    return luaG_err(L, &buf, "global already defined", "global '{s}' already defined", .{globalname});
}

pub fn luaG_forerror(L: *lua.lua_State, o: lua.TValue, what: []const u8) !void {
    const t = ltm.luaT_objtypename(L, o);
    var msg: [256]u8 = undefined;
    return luaG_err(L, &msg, "bad 'for' value", "bad 'for' {s} (number expected, got {s})", .{ what, t });
}

pub fn luaG_tointerror(L: *lua.lua_State, o: lua.TValue) !void {
    var buf: [256]u8 = undefined;
    const info = luaG_varinfo(L, &o, &buf);
    var msg: [320]u8 = undefined;
    return luaG_err(L, &msg, "number has no integer representation", "number{s} has no integer representation", .{info});
}

pub fn luaG_typeerror(L: *lua.lua_State, o: lua.TValue, op: []const u8) !void {
    return luaG_typeerrorPtr(L, &o, op);
}

pub fn luaG_typeerrorPtr(L: *lua.lua_State, o: *const lua.TValue, op: []const u8) !void {
    var buf: [256]u8 = undefined;
    const info = luaG_varinfo(L, o, &buf);
    const t = ltm.luaT_objtypename(L, o.*);
    var msg: [320]u8 = undefined;
    return luaG_err(L, &msg, "attempt to perform operation on value", "attempt to {s} a {s} value{s}", .{ op, t, info });
}

pub fn luaG_callerror(L: *lua.lua_State, o: lua.TValue) !void {
    var fname: ?[]const u8 = null;
    var kind: ?[]const u8 = null;
    if (L.ci) |ci| {
        kind = lua.funcnamefromcall(L, ci, &fname);
    }
    const t = ltm.luaT_objtypename(L, o);
    var msg: [320]u8 = undefined;
    if (kind) |k| {
        if (fname) |fnm| {
            return luaG_err(L, &msg, "attempt to call a non-function value", "attempt to call a {s} value ({s} '{s}')", .{ t, k, fnm });
        }
    }
    return luaG_typeerror(L, o, "call");
}

pub fn luaG_opinterror(L: *lua.lua_State, p1: *const lua.TValue, p2: *const lua.TValue, msg: []const u8) !void {
    var err_obj = p1;
    if (p1.isNumberValue()) {
        err_obj = p2;
    }
    return luaG_typeerrorPtr(L, err_obj, msg);
}

pub fn luaG_concaterror(L: *lua.lua_State, p1: *const lua.TValue, p2: *const lua.TValue) !void {
    // Port of the reference: if the first operand is (or can be converted to)
    // a string, blame the second operand. Without the string check, an already
    // coerced operand (e.g. `1..{}`) would wrongly report "a string value".
    var err_obj = p1;
    if (p1.isNumberValue() or p1.isString()) {
        err_obj = p2;
    }
    return luaG_typeerrorPtr(L, err_obj, "concatenate");
}

pub fn luaG_ordererror(L: *lua.lua_State, p1: lua.TValue, p2: lua.TValue) !void {
    const t1 = ltm.luaT_objtypename(L, p1);
    const t2 = ltm.luaT_objtypename(L, p2);
    var msg: [256]u8 = undefined;
    const mslice = if (std.mem.eql(u8, t1, t2))
        lua.fmtMsg(&msg, "attempt to compare values", "attempt to compare two {s} values", .{t1})
    else
        lua.fmtMsg(&msg, "attempt to compare values", "attempt to compare {s} with {s}", .{ t1, t2 });
    return luaG_runerror(L, mslice);
}
