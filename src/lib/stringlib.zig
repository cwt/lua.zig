//
// ** $Id: stringlib.zig
// ** String library for Lua.zig (Zig port of Lua 5.5.1)
// ** See Copyright Notice in c_compat.zig
//

const std = @import("std");
const lua = @import("../lua.zig");
const lprefix = @import("../lprefix.zig");
const llimits = @import("../llimits.zig");
const lauxlib = @import("../lauxlib.zig");

const LUA_MAXCAPTURES: i32 = 32;
const MAXCCALLS: i32 = 200;
const CAP_UNFINISHED: i64 = -1;
const CAP_POSITION: i64 = -2;
const L_ESC: u8 = '%';
const SPECIALS: []const u8 = "^$*+?.([%-";
const LUAL_PACKPADBYTE: u8 = 0x00;
const MAXINTSIZE: usize = 16;
const NB: u6 = 8;
const MC: u64 = (1 << NB) - 1;
const SZINT: usize = @sizeOf(lua.lua_Integer);
const MAX_ITEMF: usize = 110 + 310;
const MAX_ITEM: usize = 120;
const MAX_FORMAT: usize = 32;

fn posrelatI(pos: i64, len: usize) usize {
    if (pos > 0) return @as(usize, @intCast(pos));
    if (pos == 0) return 1;
    const ulen = @as(i64, @intCast(len));
    if (pos < -ulen) return 1;
    return len + @as(usize, @intCast(pos)) + 1;
}

fn getendpos(L: *lua.lua_State, arg: i32, def: i64, len: usize) usize {
    const pos = lauxlib.luaL_optinteger(L, arg, def);
    const ilen = @as(i64, @intCast(len));
    if (pos > ilen) return len;
    if (pos >= 0) return @as(usize, @intCast(pos));
    if (pos < -ilen) return 0;
    return len + @as(usize, @intCast(pos)) + 1;
}

fn str_len(L: *lua.lua_State) anyerror!i32 {
    var l: usize = 0;
    _ = try lauxlib.luaL_checklstring(L, 1, &l);
    lua.lua_pushinteger(L, @as(i64, @intCast(l)));
    return 1;
}

fn str_sub(L: *lua.lua_State) anyerror!i32 {
    var l: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &l);
    const start = posrelatI(try lauxlib.luaL_checkinteger(L, 2), l);
    const end = getendpos(L, 3, -1, l);
    if (start <= end) {
        _ = lua.lua_pushlstring(L, s[start - 1 .. end], end - start + 1);
    } else {
        _ = lua.lua_pushlstring(L, "", 0);
    }
    return 1;
}

fn str_reverse(L: *lua.lua_State) anyerror!i32 {
    var l: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &l);
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);
    const p = try lauxlib.luaL_prepbuffsize(L, &b, l);
    var i: usize = 0;
    while (i < l) : (i += 1) {
        p[i] = s[l - i - 1];
    }
    lauxlib.luaL_addsize(&b, l);
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

fn str_lower(L: *lua.lua_State) anyerror!i32 {
    var l: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &l);
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);
    const p = try lauxlib.luaL_prepbuffsize(L, &b, l);
    var i: usize = 0;
    while (i < l) : (i += 1) {
        p[i] = std.ascii.toLower(s[i]);
    }
    lauxlib.luaL_addsize(&b, l);
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

fn str_upper(L: *lua.lua_State) anyerror!i32 {
    var l: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &l);
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);
    const p = try lauxlib.luaL_prepbuffsize(L, &b, l);
    var i: usize = 0;
    while (i < l) : (i += 1) {
        p[i] = std.ascii.toUpper(s[i]);
    }
    lauxlib.luaL_addsize(&b, l);
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

fn str_rep(L: *lua.lua_State) anyerror!i32 {
    var len: usize = 0;
    var lsep: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &len);
    const n = try lauxlib.luaL_checkinteger(L, 2);
    const sep = (try lauxlib.luaL_optlstring(L, 3, "", &lsep)) orelse "";
    if (n <= 0 or (len | lsep) == 0) {
        _ = lua.lua_pushlstring(L, "", 0);
        return 1;
    }
    const un: u64 = @intCast(n);
    const totallen = un * (@as(u64, @intCast(len)) + @as(u64, @intCast(lsep))) - @as(u64, @intCast(lsep));
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);
    const p = try lauxlib.luaL_prepbuffsize(L, &b, @intCast(totallen));
    var pos: usize = 0;
    var remaining = n;
    while (remaining > 1) : (remaining -= 1) {
        @memcpy(p[pos..][0..len], s);
        pos += len;
        if (lsep > 0) {
            @memcpy(p[pos..][0..lsep], sep);
            pos += lsep;
        }
    }
    @memcpy(p[pos..][0..len], s);
    lauxlib.luaL_addsize(&b, @intCast(totallen));
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

fn str_byte(L: *lua.lua_State) anyerror!i32 {
    var l: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &l);
    const pi = lauxlib.luaL_optinteger(L, 2, 1);
    const posi = posrelatI(pi, l);
    const pose = getendpos(L, 3, pi, l);
    if (posi > pose) return 0;
    const n = pose - posi + 1;
    try lauxlib.luaL_checkstack(L, @as(i32, @intCast(n)), "string slice too long");
    var i: usize = 0;
    while (i < n) : (i += 1) {
        lua.lua_pushinteger(L, @as(i64, @intCast(s[posi + i - 1])));
    }
    return @as(i32, @intCast(n));
}

fn str_char(L: *lua.lua_State) anyerror!i32 {
    const n = lua.lua_gettop(L);
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);
    const p = try lauxlib.luaL_prepbuffsize(L, &b, @as(usize, @intCast(n)));
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        const c = try lauxlib.luaL_checkinteger(L, i);
        if (c < 0 or c > 255) {
            return lauxlib.luaL_argerror(L, i, "value out of range");
        }
        p[@as(usize, @intCast(i - 1))] = @as(u8, @intCast(c));
    }
    lauxlib.luaL_addsize(&b, @as(usize, @intCast(n)));
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

fn dump_writer(_: *lua.lua_State, _: ?*anyopaque, _: usize, _: ?*anyopaque) i32 {
    return 0;
}

fn str_dump(L: *lua.lua_State) anyerror!i32 {
    const strip = lua.lua_toboolean(L, 2);
    const t = lua.lua_type(L, 1);
    if (t != lua.LUA_TFUNCTION or lua.lua_iscfunction(L, 1) != 0) {
        return lauxlib.luaL_argerror(L, 1, "Lua function expected");
    }
    lua.lua_pushvalue(L, 1);
    _ = lua.lua_dump(L, dump_writer, null, strip);
    lua.lua_settop(L, 1);
    return 1;
}

fn tonum(L: *lua.lua_State, arg: i32) bool {
    if (lua.lua_type(L, arg) == lua.LUA_TNUMBER) {
        lua.lua_pushvalue(L, arg);
        return true;
    }
    var len: usize = 0;
    const s = lua.lua_tolstring(L, arg, &len);
    if (s) |str| {
        if (lua.lua_stringtonumber(L, str) == len + 1) {
            return true;
        }
    }
    return false;
}

fn trymt(L: *lua.lua_State, mtkey: []const u8, opname: []const u8) !void {
    lua.lua_settop(L, 2);
    if (lua.lua_type(L, 2) == lua.LUA_TSTRING) {
        _ = lauxlib.luaL_getmetafield(L, 2, mtkey);
    }
    if (lauxlib.luaL_getmetafield(L, 2, mtkey) == lua.LUA_TNIL) {
        var buf: [256]u8 = undefined;
        const t1 = lua.lua_typename(lua.lua_type(L, -2));
        const t2 = lua.lua_typename(lua.lua_type(L, -1));
        const msg = std.fmt.bufPrint(&buf, "attempt to {s} a '{s}' with a '{s}'", .{ opname, t1, t2 }) catch unreachable;
        return lauxlib.luaL_error(L, msg);
    }
    lua.lua_insert(L, -3);
    try lua.lua_call(L, 2, 1);
}

fn arith(L: *lua.lua_State, op: i32, mtname: []const u8) anyerror!i32 {
    if (tonum(L, 1) and tonum(L, 2)) {
        lua.lua_arith(L, op);
    } else {
        try trymt(L, mtname, mtname[2..]);
    }
    return 1;
}

fn arith_add(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPADD, "__add");
}

fn arith_sub(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPSUB, "__sub");
}

fn arith_mul(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPMUL, "__mul");
}

fn arith_mod(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPMOD, "__mod");
}

fn arith_pow(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPPOW, "__pow");
}

fn arith_div(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPDIV, "__div");
}

fn arith_idiv(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPIDIV, "__idiv");
}

fn arith_unm(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPUNM, "__unm");
}

const MatchState = struct {
    src: []const u8,
    src_init: usize,
    src_end: usize,
    p: []const u8,
    p_end: usize,
    L: *lua.lua_State,
    matchdepth: i32,
    level: i32,
    capture: [LUA_MAXCAPTURES]struct { init: usize, len: i64 },
};

fn match_class(c: u8, cl: u8) bool {
    const res = switch (std.ascii.toLower(cl)) {
        'a' => std.ascii.isAlphabetic(c),
        'c' => std.ascii.isControl(c),
        'd' => std.ascii.isDigit(c),
        'g' => c >= 33 and c <= 126,
        'l' => std.ascii.isLower(c),
        'p' => std.ascii.isPunctuation(c),
        's' => std.ascii.isWhitespace(c),
        'u' => std.ascii.isUpper(c),
        'w' => std.ascii.isAlphanumeric(c),
        'x' => std.ascii.isHex(c),
        'z' => c == 0,
        else => return cl == c,
    };
    return if (std.ascii.isLower(cl)) res else !res;
}

fn classend(ms: *MatchState, p_idx: usize) usize {
    switch (ms.p[p_idx]) {
        '%' => {
            if (p_idx + 1 >= ms.p_end) {
                _ = lauxlib.luaL_error(ms.L, "malformed pattern (ends with '%%')") catch unreachable;
                return ms.p_end;
            }
            return p_idx + 2;
        },
        '[' => {
            var p = p_idx + 1;
            if (p < ms.p_end and ms.p[p] == '^') p += 1;
            while (true) {
                if (p >= ms.p_end) {
                    _ = lauxlib.luaL_error(ms.L, "malformed pattern (missing ']')") catch unreachable;
                    return ms.p_end;
                }
                if (ms.p[p] == '%' and p + 1 < ms.p_end) {
                    p += 2;
                } else if (ms.p[p] == ']') {
                    return p + 1;
                } else {
                    p += 1;
                }
            }
        },
        else => {
            return p_idx + 1;
        },
    }
}

fn matchbracketclass(ms: *MatchState, c: u8, p_idx: usize, ec: usize) bool {
    var sig = true;
    var p = p_idx;
    if (p + 1 < ec and ms.p[p + 1] == '^') {
        sig = false;
        p += 1;
    }
    p += 1;
    while (p < ec) {
        if (ms.p[p] == '%') {
            p += 1;
            if (match_class(c, ms.p[p])) return sig;
        } else if (p + 1 < ec and ms.p[p + 1] == '-') {
            p += 2;
            if (p < ec and ms.p[p - 2] <= c and c <= ms.p[p]) return sig;
        } else if (ms.p[p] == c) {
            return sig;
        }
        p += 1;
    }
    return !sig;
}

fn singlematch(ms: *MatchState, s: usize, p: usize, ep: usize) bool {
    if (s >= ms.src_end) return false;
    const c = ms.src[s];
    switch (ms.p[p]) {
        '.' => return true,
        '%' => return match_class(c, ms.p[p + 1]),
        '[' => return matchbracketclass(ms, c, p, ep - 1),
        else => return ms.p[p] == c,
    }
}

fn matchbalance(ms: *MatchState, s: usize, p: usize) ?usize {
    if (p + 1 >= ms.p_end) {
        _ = lauxlib.luaL_error(ms.L, "malformed pattern (missing arguments to '%%b')") catch unreachable;
        return null;
    }
    if (s >= ms.src_end or ms.src[s] != ms.p[p]) return null;
    const b = ms.p[p];
    const e = ms.p[p + 1];
    var cont: i32 = 1;
    var s_idx = s;
    while (s_idx + 1 < ms.src_end) {
        s_idx += 1;
        if (ms.src[s_idx] == e) {
            cont -= 1;
            if (cont == 0) return s_idx + 1;
        } else if (ms.src[s_idx] == b) {
            cont += 1;
        }
    }
    return null;
}

fn max_expand(ms: *MatchState, s: usize, p: usize, ep: usize) ?usize {
    var i: usize = 0;
    while (singlematch(ms, s + i, p, ep)) : (i += 1) {}
    while (true) {
        const res = match(ms, s + i, ep + 1);
        if (res) |r| return r;
        if (i == 0) return null;
        i -= 1;
    }
}

fn min_expand(ms: *MatchState, s: usize, p: usize, ep: usize) ?usize {
    var s_idx = s;
    while (true) {
        const res = match(ms, s_idx, ep + 1);
        if (res) |r| return r;
        if (singlematch(ms, s_idx, p, ep)) {
            s_idx += 1;
        } else {
            return null;
        }
    }
}

fn start_capture(ms: *MatchState, s: usize, p: usize, what: i64) ?usize {
    const level = ms.level;
    if (level >= LUA_MAXCAPTURES) {
        _ = lauxlib.luaL_error(ms.L, "too many captures") catch unreachable;
        return null;
    }
    ms.capture[@as(usize, @intCast(level))] = .{ .init = s, .len = what };
    ms.level = level + 1;
    const res = match(ms, s, p);
    if (res == null) ms.level = level;
    return res;
}

fn end_capture(ms: *MatchState, s: usize, p: usize) ?usize {
    const l = capture_to_close(ms) orelse return null;
    ms.capture[l].len = @as(i64, @intCast(s)) - @as(i64, @intCast(ms.capture[l].init));
    const res = match(ms, s, p);
    if (res == null) ms.capture[l].len = CAP_UNFINISHED;
    return res;
}

fn check_capture(ms: *MatchState, l_arg: u8) !usize {
    const l = @as(usize, @intCast(l_arg - '1'));
    if (l >= @as(usize, @intCast(ms.level)) or ms.capture[l].len == CAP_UNFINISHED) {
        return lauxlib.luaL_error(ms.L, "invalid capture index");
    }
    return l;
}

fn capture_to_close(ms: *MatchState) ?usize {
    var level: i32 = ms.level - 1;
    while (level >= 0) : (level -= 1) {
        if (ms.capture[@as(usize, @intCast(level))].len == CAP_UNFINISHED) {
            return @as(usize, @intCast(level));
        }
    }
    _ = lauxlib.luaL_error(ms.L, "invalid pattern capture") catch unreachable;
    return null;
}

fn match_capture(ms: *MatchState, s: usize, l: u8) ?usize {
    const cap_idx = check_capture(ms, l) catch return null;
    const init = ms.capture[cap_idx].init;
    const capl = @as(usize, @intCast(ms.capture[cap_idx].len));
    if (ms.src_end -| s >= capl and std.mem.eql(u8, ms.src[init..][0..capl], ms.src[s..][0..capl])) {
        return s + capl;
    }
    return null;
}

fn match(ms: *MatchState, s: usize, p: usize) ?usize {
    if (ms.matchdepth == 0) {
        _ = lauxlib.luaL_error(ms.L, "pattern too complex") catch unreachable catch unreachable;
        return null;
    }
    ms.matchdepth -= 1;

    var s_idx = s;
    var p_idx = p;

    while (p_idx < ms.p_end) {
        switch (ms.p[p_idx]) {
            '(' => {
                if (p_idx + 1 < ms.p_end and ms.p[p_idx + 1] == ')') {
                    s_idx = start_capture(ms, s_idx, p_idx + 2, CAP_POSITION) orelse return null;
                } else {
                    s_idx = start_capture(ms, s_idx, p_idx + 1, CAP_UNFINISHED) orelse return null;
                }
                break;
            },
            ')' => {
                s_idx = end_capture(ms, s_idx, p_idx + 1) orelse return null;
                break;
            },
            '$' => {
                if (p_idx + 1 == ms.p_end) {
                    if (s_idx != ms.src_end) return null;
                    break;
                }
                const ep = classend(ms, p_idx);
                if (!singlematch(ms, s_idx, p_idx, ep)) {
                    if (ep < ms.p_end and (ms.p[ep] == '*' or ms.p[ep] == '?' or ms.p[ep] == '-')) {
                        p_idx = ep + 1;
                        continue;
                    } else {
                        return null;
                    }
                } else {
                    switch (ms.p[ep]) {
                        '?' => {
                            if (match(ms, s_idx + 1, ep + 1)) |res| {
                                s_idx = res;
                            } else {
                                p_idx = ep + 1;
                                continue;
                            }
                        },
                        '+' => {
                            s_idx = max_expand(ms, s_idx + 1, p_idx, ep) orelse return null;
                        },
                        '*' => {
                            s_idx = max_expand(ms, s_idx, p_idx, ep) orelse return null;
                        },
                        '-' => {
                            s_idx = min_expand(ms, s_idx, p_idx, ep) orelse return null;
                        },
                        else => {
                            s_idx += 1;
                            p_idx = ep;
                            continue;
                        },
                    }
                    break;
                }
            },
            '%' => {
                p_idx += 1;
                if (p_idx >= ms.p_end) {
                    _ = lauxlib.luaL_error(ms.L, "malformed pattern (ends with '%%')") catch unreachable;
                    return null;
                }
                switch (ms.p[p_idx]) {
                    'b' => {
                        s_idx = matchbalance(ms, s_idx, p_idx + 1) orelse break;
                        p_idx += 3;
                        continue;
                    },
                    'f' => {
                        p_idx += 1;
                        if (p_idx >= ms.p_end or ms.p[p_idx] != '[') {
                            _ = lauxlib.luaL_error(ms.L, "missing '[' after '%%f' in pattern") catch unreachable;
                            return null;
                        }
                        const ep = classend(ms, p_idx);
                        const previous: u8 = if (s_idx == ms.src_init) 0 else ms.src[s_idx - 1];
                        if (!matchbracketclass(ms, previous, p_idx, ep - 1) and
                            matchbracketclass(ms, ms.src[s_idx], p_idx, ep - 1))
                        {
                            p_idx = ep;
                            continue;
                        }
                        return null;
                    },
                    '0'...'9' => {
                        s_idx = match_capture(ms, s_idx, ms.p[p_idx]) orelse return null;
                        p_idx += 2;
                        continue;
                    },
                    else => {
                        const ep = classend(ms, p_idx - 1);
                        if (!singlematch(ms, s_idx, p_idx - 1, ep)) {
                            if (ep < ms.p_end and (ms.p[ep] == '*' or ms.p[ep] == '?' or ms.p[ep] == '-')) {
                                p_idx = ep + 1;
                                continue;
                            } else {
                                return null;
                            }
                        } else {
                            switch (ms.p[ep]) {
                                '?' => {
                                    if (match(ms, s_idx + 1, ep + 1)) |res| {
                                        s_idx = res;
                                    } else {
                                        p_idx = ep + 1;
                                        continue;
                                    }
                                },
                                '+' => {
                                    s_idx = max_expand(ms, s_idx + 1, p_idx - 1, ep) orelse return null;
                                },
                                '*' => {
                                    s_idx = max_expand(ms, s_idx, p_idx - 1, ep) orelse return null;
                                },
                                '-' => {
                                    s_idx = min_expand(ms, s_idx, p_idx - 1, ep) orelse return null;
                                },
                                else => {
                                    s_idx += 1;
                                    p_idx = ep;
                                    continue;
                                },
                            }
                            break;
                        }
                    },
                }
                break;
            },
            else => {
                const ep = classend(ms, p_idx);
                if (!singlematch(ms, s_idx, p_idx, ep)) {
                    if (ep < ms.p_end and (ms.p[ep] == '*' or ms.p[ep] == '?' or ms.p[ep] == '-')) {
                        p_idx = ep + 1;
                        continue;
                    } else {
                        return null;
                    }
                } else {
                    switch (ms.p[ep]) {
                        '?' => {
                            if (match(ms, s_idx + 1, ep + 1)) |res| {
                                s_idx = res;
                            } else {
                                p_idx = ep + 1;
                                continue;
                            }
                        },
                        '+' => {
                            s_idx = max_expand(ms, s_idx + 1, p_idx, ep) orelse return null;
                        },
                        '*' => {
                            s_idx = max_expand(ms, s_idx, p_idx, ep) orelse return null;
                        },
                        '-' => {
                            s_idx = min_expand(ms, s_idx, p_idx, ep) orelse return null;
                        },
                        else => {
                            s_idx += 1;
                            p_idx = ep;
                            continue;
                        },
                    }
                    break;
                }
            },
        }
    }

    ms.matchdepth += 1;

    if (s_idx != 0) {
        // s_idx is a valid position; just return it
        // In C, s could be NULL or a valid pointer.
        // In our port, s_idx is checked against src_end for boundary.
        // Since we already checked bounds above, if we reach here,
        // s_idx is valid (and ms.src_end means success for anchoring).
        // But we need to ensure we return null correctly.
    }

    return s_idx;
}

fn lmemfind(s1: []const u8, l1: usize, s2: []const u8, l2: usize) ?usize {
    if (l2 == 0) return 0;
    if (l2 > l1) return null;
    var i: usize = 0;
    const max_i = l1 - l2;
    while (i <= max_i) : (i += 1) {
        if (s1[i] == s2[0]) {
            if (std.mem.eql(u8, s1[i..][0..l2], s2[0..l2])) {
                return i;
            }
        }
    }
    return null;
}

fn get_onecapture(ms: *MatchState, i: i32, s: usize, e: usize) !struct { init: usize, len: i64 } {
    if (i >= ms.level) {
        if (i != 0) return lauxlib.luaL_error(ms.L, "invalid capture index");
        return .{ .init = s, .len = @as(i64, @intCast(e -| s)) };
    }
    const init = ms.capture[@as(usize, @intCast(i))].init;
    const capl = ms.capture[@as(usize, @intCast(i))].len;
    if (capl == CAP_UNFINISHED) return lauxlib.luaL_error(ms.L, "unfinished capture");
    if (capl == CAP_POSITION) {
        lua.lua_pushinteger(ms.L, @as(i64, @intCast(init - ms.src_init)) + 1);
    }
    return .{ .init = init, .len = capl };
}

fn push_onecapture(ms: *MatchState, i: i32, s: usize, e: usize) !void {
    const cap_info = try get_onecapture(ms, i, s, e);
    if (cap_info.len != CAP_POSITION) {
        const len = @as(usize, @intCast(cap_info.len));
        _ = lua.lua_pushlstring(ms.L, ms.src[cap_info.init..][0..len], len);
    }
}

fn push_captures(ms: *MatchState, s: usize, e: usize) !i32 {
    const nlevels = if (ms.level == 0 and s == 0) @as(i32, 1) else ms.level;
    try lauxlib.luaL_checkstack(ms.L, nlevels, "too many captures");
    var i: i32 = 0;
    while (i < nlevels) : (i += 1) {
        try push_onecapture(ms, i, s, e);
    }
    return nlevels;
}

fn nospecials(p: []const u8, l: usize) bool {
    var upto: usize = 0;
    while (true) {
        if (std.mem.indexOfAny(u8, p[upto..], SPECIALS)) |_| {
            return false;
        }
        const next_zero = std.mem.indexOfScalar(u8, p[upto..], 0);
        if (next_zero) |nz| {
            upto += nz + 1;
            if (upto > l) return true;
        } else {
            return true;
        }
    }
}

fn prepstate(ms: *MatchState, L: *lua.lua_State, src: []const u8, ls: usize, p: []const u8, lp: usize) void {
    ms.L = L;
    ms.src = src;
    ms.src_init = 0;
    ms.src_end = ls;
    ms.p = p;
    ms.p_end = lp;
}

fn reprepstate(ms: *MatchState) void {
    ms.matchdepth = MAXCCALLS;
    ms.level = 0;
}

fn str_find_aux(L: *lua.lua_State, find: bool) anyerror!i32 {
    var ls: usize = 0;
    var lp: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &ls);
    const p = try lauxlib.luaL_checklstring(L, 2, &lp);
    const init = posrelatI(lauxlib.luaL_optinteger(L, 3, 1), ls) - 1;
    if (init > ls) {
        lauxlib.luaL_pushfail(L);
        return 1;
    }
    if (find and (lua.lua_toboolean(L, 4) != 0 or nospecials(p, lp))) {
        const s2_offset = lmemfind(s[init..], ls - init, p, lp);
        if (s2_offset) |off| {
            lua.lua_pushinteger(L, @as(i64, @intCast(off + 1)));
            lua.lua_pushinteger(L, @as(i64, @intCast(off + lp)));
            return 2;
        }
    } else {
        var ms: MatchState = undefined;
        const s1 = init;
        const anchor = (p.len > 0 and p[0] == '^');
        var p_adj = p;
        var lp_adj = lp;
        if (anchor) {
            p_adj = p[1..];
            lp_adj -= 1;
        }
        prepstate(&ms, L, s, ls, p_adj, lp_adj);
        var s_idx = s1;
        while (true) {
            reprepstate(&ms);
            const res = match(&ms, s_idx, 0);
            if (res) |r| {
                if (find) {
                    lua.lua_pushinteger(L, @as(i64, @intCast(s_idx)) + 1);
                    lua.lua_pushinteger(L, @as(i64, @intCast(r)));
                    const n = try push_captures(&ms, 0, 0);
                    return n + 2;
                } else {
                    return push_captures(&ms, s_idx, r);
                }
            }
            s_idx += 1;
            if (s_idx > ms.src_end or anchor) break;
        }
    }
    lauxlib.luaL_pushfail(L);
    return 1;
}

fn str_find(L: *lua.lua_State) anyerror!i32 {
    return str_find_aux(L, true);
}

fn str_match(L: *lua.lua_State) anyerror!i32 {
    return str_find_aux(L, false);
}

const GMatchState = struct {
    src: usize,
    p_idx: usize,
    lastmatch: usize,
    ms: MatchState,
};

fn gmatch_aux(L: *lua.lua_State) anyerror!i32 {
    const gm = @as(*GMatchState, @ptrCast(@alignCast(lua.lua_touserdata(L, lua.lua_upvalueindex(3)) orelse return 0)));
    gm.ms.L = L;
    var src = gm.src;
    while (src <= gm.ms.src_end) : (src += 1) {
        reprepstate(&gm.ms);
        const e = match(&gm.ms, src, gm.p_idx);
        if (e) |e_val| {
            if (e_val != gm.lastmatch) {
                gm.src = e_val;
                gm.lastmatch = e_val;
                return push_captures(&gm.ms, src, e_val);
            }
        }
    }
    return 0;
}

fn gmatch(L: *lua.lua_State) anyerror!i32 {
    var ls: usize = 0;
    var lp: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &ls);
    const p = try lauxlib.luaL_checklstring(L, 2, &lp);
    const init = posrelatI(lauxlib.luaL_optinteger(L, 3, 1), ls) - 1;
    lua.lua_settop(L, 2);
    const gm = @as(*GMatchState, @ptrCast(@alignCast(lua.lua_newuserdatauv(L, @sizeOf(GMatchState), 0) orelse return 0)));
    var adjusted_init = init;
    if (adjusted_init > ls) adjusted_init = ls + 1;
    prepstate(&gm.ms, L, s, ls, p, lp);
    gm.src = adjusted_init;
    gm.p_idx = 0;
    gm.lastmatch = 0;
    lua.lua_pushcclosure(L, gmatch_aux, 3);
    return 1;
}

fn add_s(ms: *MatchState, b: *lauxlib.luaL_Buffer, s: usize, e: usize) !void {
    const L = ms.L;
    var len: usize = 0;
    const news = lua.lua_tolstring(L, 3, &len) orelse return;
    var rest = news;
    while (std.mem.indexOfScalar(u8, rest, '%')) |pos| {
        try lauxlib.luaL_addlstring(L, b, rest[0..pos]);
        const p = pos + 1;
        if (p >= rest.len) {
            _ = lauxlib.luaL_error(L, "invalid use of '%c' in replacement string") catch unreachable;
            return;
        }
        const c = rest[p];
        if (c == '%') {
            try lauxlib.luaL_addchar(L, b, '%');
        } else if (c == '0') {
            try lauxlib.luaL_addlstring(L, b, ms.src[s..e]);
        } else if (c >= '1' and c <= '9') {
            const cap_i = @as(i32, @intCast(c - '1'));
            const cap_info = try get_onecapture(ms, cap_i, s, e);
            if (cap_info.len == CAP_POSITION) {
                try lauxlib.luaL_addvalue(L, b);
            } else {
                const len2 = @as(usize, @intCast(cap_info.len));
                try lauxlib.luaL_addlstring(L, b, ms.src[cap_info.init..][0..len2]);
            }
        } else {
            _ = lauxlib.luaL_error(L, "invalid use of '%c' in replacement string") catch unreachable;
            return;
        }
        rest = rest[p + 1 ..];
    }
    try lauxlib.luaL_addlstring(L, b, rest);
}

fn add_value(ms: *MatchState, b: *lauxlib.luaL_Buffer, s: usize, e: usize, tr: i32) !bool {
    const L = ms.L;
    switch (tr) {
        lua.LUA_TFUNCTION => {
            lua.lua_pushvalue(L, 3);
            const n = try push_captures(ms, s, e);
            try lua.lua_call(L, n, 1);
        },
        lua.LUA_TTABLE => {
            try push_onecapture(ms, 0, s, e);
            _ = try lua.lua_gettable(L, 3);
        },
        else => {
            try add_s(ms, b, s, e);
            return true;
        },
    }
    if (lua.lua_toboolean(L, -1) == 0) {
        lua.lua_pop(L, 1);
        try lauxlib.luaL_addlstring(L, b, ms.src[s..e]);
        return false;
    }
    if (lua.lua_isstring(L, -1) == 0) {
        return lauxlib.luaL_error(L, "invalid replacement value (a %s)");
    }
    try lauxlib.luaL_addvalue(L, b);
    return true;
}

fn str_gsub(L: *lua.lua_State) anyerror!i32 {
    var srcl: usize = 0;
    var lp: usize = 0;
    const src = try lauxlib.luaL_checklstring(L, 1, &srcl);
    const p = try lauxlib.luaL_checklstring(L, 2, &lp);
    const tr = lua.lua_type(L, 3);
    const max_s = lauxlib.luaL_optinteger(L, 4, @as(i64, @intCast(srcl)) + 1);
    try lauxlib.luaL_argcheck(L, tr == lua.LUA_TNUMBER or tr == lua.LUA_TSTRING or tr == lua.LUA_TFUNCTION or tr == lua.LUA_TTABLE, 3, "string/function/table");
    const anchor = (p.len > 0 and p[0] == '^');
    var ms: MatchState = undefined;
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);
    var p_adj = p;
    var lp_adj = lp;
    if (anchor) {
        p_adj = p[1..];
        lp_adj -= 1;
    }
    prepstate(&ms, L, src, srcl, p_adj, lp_adj);
    var src_idx: usize = 0;
    var n: i64 = 0;
    var changed = false;
    while (n < max_s) {
        reprepstate(&ms);
        const e = match(&ms, src_idx, 0);
        if (e) |e_val| {
            if (e_val != ms.src_init) { // lastmatch check
                n += 1;
                changed = (try add_value(&ms, &b, src_idx, e_val, tr)) or changed;
                src_idx = e_val;
            } else {
                // skip one char
                if (src_idx < ms.src_end) {
                    try lauxlib.luaL_addchar(L, &b, ms.src[src_idx]);
                    src_idx += 1;
                } else break;
            }
        } else {
            if (src_idx < ms.src_end) {
                try lauxlib.luaL_addchar(L, &b, ms.src[src_idx]);
                src_idx += 1;
            } else break;
        }
        if (anchor) break;
    }
    if (!changed) {
        lua.lua_pushvalue(L, 1);
    } else {
        try lauxlib.luaL_addlstring(L, &b, ms.src[src_idx..ms.src_end]);
        lauxlib.luaL_pushresult(L, &b);
    }
    lua.lua_pushinteger(L, n);
    return 2;
}

fn addquoted(L: *lua.lua_State, b: *lauxlib.luaL_Buffer, s: []const u8, len: usize) !void {
    try lauxlib.luaL_addchar(L, b, '"');
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const c = s[i];
        if (c == '\\' or c == '"') {
            try lauxlib.luaL_addchar(L, b, '\\');
            try lauxlib.luaL_addchar(L, b, c);
        } else if (c == 0) {
            try lauxlib.luaL_addlstring(L, b, "\\000");
        } else {
            try lauxlib.luaL_addchar(L, b, c);
        }
    }
    try lauxlib.luaL_addchar(L, b, '"');
}

fn quotefloat(f: f64) !struct { buf: [50]u8, len: usize } {
    var buf: [50]u8 = undefined;
    const buf_len = try std.fmt.bufPrint(&buf, "{d}", .{f});
    return .{ .buf = buf, .len = buf_len.len };
}

fn addliteral(L: *lua.lua_State, b: *lauxlib.luaL_Buffer, arg: i32) !void {
    switch (lua.lua_type(L, arg)) {
        lua.LUA_TNIL => try lauxlib.luaL_addlstring(L, b, "nil"),
        lua.LUA_TBOOLEAN => {
            if (lua.lua_toboolean(L, arg) != 0) {
                try lauxlib.luaL_addlstring(L, b, "true");
            } else {
                try lauxlib.luaL_addlstring(L, b, "false");
            }
        },
        lua.LUA_TNUMBER => {
            if (lua.lua_isinteger(L, arg) != 0) {
                try lauxlib.luaL_addchar(L, b, 'L');
                var buf: [50]u8 = undefined;
                const int_val = lua.lua_tointeger(L, arg) orelse 0;
                const s = try std.fmt.bufPrint(&buf, "{d}", .{int_val});
                try lauxlib.luaL_addlstring(L, b, s);
            } else {
                const n = lua.lua_tonumber(L, arg) orelse 0.0;
                const result = try quotefloat(n);
                try lauxlib.luaL_addlstring(L, b, result.buf[0..result.len]);
            }
        },
        lua.LUA_TSTRING => {
            var len: usize = 0;
            const s = lua.lua_tolstring(L, arg, &len) orelse "";
            try addquoted(L, b, s, len);
        },
        else => _ = lauxlib.luaL_error(L, "invalid value (%s) at index %d in format string") catch unreachable,
    }
}

fn get2digits(s: []const u8, pos: usize) struct { val: i32, new_pos: usize } {
    var val: i32 = 0;
    var p = pos;
    if (p < s.len and std.ascii.isDigit(s[p])) {
        val = @as(i32, @intCast(s[p] - '0'));
        p += 1;
    }
    if (p < s.len and std.ascii.isDigit(s[p])) {
        val = val * 10 + @as(i32, @intCast(s[p] - '0'));
        p += 1;
    }
    return .{ .val = val, .new_pos = p };
}

const MaxFormat = struct {
    flags: ComptimeFlags,
    width: i64,
    precision: i64,
};
const ComptimeFlags = packed struct(u8) {
    minus: bool = false,
    plus: bool = false,
    space: bool = false,
    num2: bool = false,
    zero: bool = false,
    _pad: u3 = 0,
};

fn checkformat(_: *lua.lua_State, form: []const u8, form_len: usize, max: *MaxFormat) !void {
    var idx: usize = 0;
    while (idx < form_len) {
        const c = form[idx];
        if (c == '-' or c == '+' or c == ' ') break;
        idx += 1;
    }
    max.flags = .{};
    while (idx < form_len) {
        const c = form[idx];
        switch (c) {
            '-' => max.flags.minus = true,
            '+' => max.flags.plus = true,
            ' ' => max.flags.space = true,
            '#' => max.flags.num2 = true,
            '0' => max.flags.zero = true,
            else => break,
        }
        idx += 1;
    }
    if (idx < form_len and std.ascii.isDigit(form[idx])) {
        const res = get2digits(form, idx);
        max.width = @intCast(res.val);
        idx = res.new_pos;
    } else {
        max.width = -1;
    }
    if (idx < form_len and form[idx] == '.') {
        idx += 1;
        if (idx < form_len and std.ascii.isDigit(form[idx])) {
            const res = get2digits(form, idx);
            max.precision = @intCast(res.val);
            idx = res.new_pos;
        } else {
            max.precision = 0;
        }
    } else {
        max.precision = -1;
    }
}

const StringFmt = struct {
    format: []const u8,
    length: i32,
};

fn getformat(L: *lua.lua_State, strfrmt: []const u8, len: usize, pos: *usize) !?StringFmt {
    while (pos.* < len and strfrmt[pos.*] != '\x00' and strfrmt[pos.*] != '%') {
        pos.* += 1;
    }
    if (pos.* >= len or strfrmt[pos.*] == '\x00') return null;
    pos.* += 1;
    const start = pos.*;
    if (pos.* >= len) return lauxlib.luaL_error(L, "malformed format string (ends with '%')");
    {
        const c = strfrmt[pos.*];
        pos.* += 1;
        if (c == 's' or c == 'f' or c == 'i' or c == 'd' or c == 'o' or c == 'x' or c == 'X' or c == 'u' or c == 'c' or c == 'b' or c == 'p' or c == 'q' or c == 'a' or c == 'A' or c == 'g' or c == 'G' or c == 'e' or c == 'E') {
            return StringFmt{ .format = strfrmt[start..pos.*], .length = 1 };
        }
        if (c == 'E' or c == 'f' or c == 'g' or c == 'G') return StringFmt{ .format = strfrmt[start..pos.*], .length = 1 };
    }
    return lauxlib.luaL_error(L, "malformed format string");
}

fn addlenmod(s: []const u8, mod: []const u8) ![]const u8 {
    if (std.mem.indexOf(u8, s, "l")) |pos| {
        const result = try std.fmt.allocPrint(std.heap.page_allocator, "{s}{s}{s}", .{ s[0..pos], mod, s[pos + 1 ..] });
        return result;
    }
    return s;
}

fn num2straux(buf: []u8, n: f64, is_upper: bool) []const u8 {
    if (std.math.isInf(n)) {
        if (is_upper) {
            _ = std.mem.replaceScalar(u8, buf[0..3], ' ', 'I');
            return "INF";
        } else {
            return "inf";
        }
    }
    if (std.math.isNan(n)) {
        if (is_upper) {
            _ = std.mem.replaceScalar(u8, buf[0..3], ' ', 'N');
            return "NAN";
        } else {
            return "nan";
        }
    }
    return "";
}

fn lua_number2strx(_: *lua.lua_State, _: []const u8, v: f64) ![]const u8 {
    if (std.math.isInf(v) or std.math.isNan(v)) {
        var buf: [20]u8 = undefined;
        const s = num2straux(&buf, v, true);
        if (s.len > 0) return s;
    }
    var buf: [100]u8 = undefined;
    const s = try std.fmt.bufPrint(&buf, "{d}", .{v});
    return s;
}

fn str_format(L: *lua.lua_State) anyerror!i32 {
    var len: usize = 0;
    const strfrmt = try lauxlib.luaL_checklstring(L, 1, &len);
    var pos: usize = 0;
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);
    var argn: i32 = 2;
    var nformats: i32 = 0;
    while (pos < len) {
        // Copy literal text before '%' or '\x00'
        const start = pos;
        while (pos < len and strfrmt[pos] != '\x00' and strfrmt[pos] != '%') {
            pos += 1;
        }
        if (pos > start) {
            try lauxlib.luaL_addlstring(L, &b, strfrmt[start..pos]);
        }
        if (pos >= len) break;
        const c = strfrmt[pos];
        if (c == '\x00') {
            pos += 1;
            continue;
        }
        // c == '%'
        pos += 1;
        if (pos >= len) return lauxlib.luaL_error(L, "malformed format string");

        // Skip % itself
        if (strfrmt[pos] == '%') {
            try lauxlib.luaL_addchar(L, &b, '%');
            pos += 1;
            continue;
        }

        nformats += 1;
        if (argn > lua.lua_gettop(L)) return lauxlib.luaL_error(L, "no value for format");
        try lauxlib.luaL_checkstack(L, 1, "too many formats");

        // Parse flags
        var flags: u8 = 0;
        while (pos < len) {
            const fc = strfrmt[pos];
            switch (fc) {
                '-' => flags |= 1,
                '+' => flags |= 2,
                ' ' => flags |= 4,
                '#' => flags |= 8,
                '0' => flags |= 16,
                else => break,
            }
            pos += 1;
        }

        // Parse width
        var width: i64 = -1;
        if (pos < len and strfrmt[pos] == '*') {
            width = try lauxlib.luaL_checkinteger(L, argn);
            argn += 1;
            pos += 1;
        } else if (pos < len and std.ascii.isDigit(strfrmt[pos])) {
            const res = get2digits(strfrmt, pos);
            width = @intCast(res.val);
            pos = res.new_pos;
        }

        // Parse precision
        var precision: i64 = -1;
        if (pos < len and strfrmt[pos] == '.') {
            pos += 1;
            if (pos < len and strfrmt[pos] == '*') {
                precision = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                pos += 1;
            } else if (pos < len and std.ascii.isDigit(strfrmt[pos])) {
                const res = get2digits(strfrmt, pos);
                precision = @intCast(res.val);
                pos = res.new_pos;
            } else {
                precision = 0;
            }
        }

        // Skip length modifier (we ignore it except 'I64' and 'l' vs 'L')
        var long: bool = false;
        var long64: bool = false;
        if (pos < len) {
            const cc = strfrmt[pos];
            if (cc == 'l') {
                long = true;
                pos += 1;
            } else if (cc == 'L') {
                long64 = true;
                pos += 1;
            } else if (cc == 'I') {
                pos += 1;
                if (pos < len and strfrmt[pos] == '6') {
                    pos += 1;
                    if (pos < len and strfrmt[pos] == '4') {
                        long64 = true;
                        pos += 1;
                    }
                }
            }
        }

        if (pos >= len) return lauxlib.luaL_error(L, "malformed format string");

        const spec = strfrmt[pos];
        pos += 1;

        // Handle floating point cases that need precision
        var need_precision = false;
        switch (spec) {
            'f', 'e', 'E', 'g', 'G', 'a', 'A' => need_precision = true,
            else => {},
        }

        // Build format spec string for Zig
        var fmt_buf: [50]u8 = undefined;
        var fmt_idx: usize = 0;

        if (need_precision) {
            fmt_buf[fmt_idx] = '{';
            fmt_idx += 1;
            if (width >= 0) {
                fmt_buf[fmt_idx] = ':';
                fmt_idx += 1;
                if (width >= 0) {
                    if ((flags & 1) != 0) { // '-'
                        fmt_buf[fmt_idx] = '<';
                        fmt_idx += 1;
                    }
                    if ((flags & 16) != 0) { // '0'
                        fmt_buf[fmt_idx] = '0';
                        fmt_idx += 1;
                    }
                    const width_val = @as(usize, @intCast(width));
                    const ws = try std.fmt.bufPrint(fmt_buf[fmt_idx..], "{d}", .{width_val});
                    fmt_idx += ws.len;
                }
                if (precision >= 0) {
                    fmt_buf[fmt_idx] = '.';
                    fmt_idx += 1;
                    const prec_val = @as(usize, @intCast(precision));
                    const ws2 = try std.fmt.bufPrint(fmt_buf[fmt_idx..], "{d}", .{prec_val});
                    fmt_idx += ws2.len;
                }
                switch (spec) {
                    'f' => { fmt_buf[fmt_idx] = '}'; fmt_idx += 1; },
                    else => { fmt_buf[fmt_idx] = '}'; fmt_idx += 1; },
                }
            } else if (precision >= 0) {
                fmt_buf[fmt_idx] = ':';
                fmt_idx += 1;
                if ((flags & 1) != 0) {
                    fmt_buf[fmt_idx] = '<';
                    fmt_idx += 1;
                }
                if ((flags & 16) != 0) {
                    fmt_buf[fmt_idx] = '0';
                    fmt_idx += 1;
                }
                if (precision >= 0) {
                    fmt_buf[fmt_idx] = '.';
                    fmt_idx += 1;
                    const prec_val = @as(usize, @intCast(precision));
                    const ws2 = try std.fmt.bufPrint(fmt_buf[fmt_idx..], "{d}", .{prec_val});
                    fmt_idx += ws2.len;
                }
                switch (spec) {
                    'f' => { fmt_buf[fmt_idx] = '}'; fmt_idx += 1; },
                    else => { fmt_buf[fmt_idx] = '}'; fmt_idx += 1; },
                }
            } else {
                fmt_buf[fmt_idx] = '}';
                fmt_idx += 1;
            }
            const float_fmt = fmt_buf[0..fmt_idx];
            _ = float_fmt;
        }

        switch (spec) {
            's' => {
                var sl: usize = 0;
                const s = try lauxlib.luaL_checklstring(L, argn, &sl);
                argn += 1;
                if (precision >= 0) {
                    const pl = @as(usize, @intCast(precision));
                    const sl_actual = if (pl < sl) pl else sl;
                    if (width > 0) {
                        const w = @as(usize, @intCast(width));
                        if ((flags & 1) != 0) { // left-justify
                            try lauxlib.luaL_addlstring(L, &b, s[0..sl_actual]);
                            var sp: usize = 0;
                            while (sp < w -| sl_actual) : (sp += 1) try lauxlib.luaL_addchar(L, &b, ' ');
                        } else {
                            var sp: usize = 0;
                            while (sp < w -| sl_actual) : (sp += 1) try lauxlib.luaL_addchar(L, &b, ' ');
                            try lauxlib.luaL_addlstring(L, &b, s[0..sl_actual]);
                        }
                    } else {
                        try lauxlib.luaL_addlstring(L, &b, s[0..sl_actual]);
                    }
                } else {
                    if (width > 0) {
                        const w = @as(usize, @intCast(width));
                        if ((flags & 1) != 0) {
                            try lauxlib.luaL_addlstring(L, &b, s[0..sl]);
                            var sp: usize = 0;
                            while (sp < w -| sl) : (sp += 1) try lauxlib.luaL_addchar(L, &b, ' ');
                        } else {
                            var sp: usize = 0;
                            while (sp < w -| sl) : (sp += 1) try lauxlib.luaL_addchar(L, &b, ' ');
                            try lauxlib.luaL_addlstring(L, &b, s[0..sl]);
                        }
                    } else {
                        try lauxlib.luaL_addlstring(L, &b, s[0..sl]);
                    }
                }
            },
            'c' => {
                const c_val = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                const cv = @as(u8, @intCast(@as(u32, @intCast(c_val))));
                try lauxlib.luaL_addchar(L, &b, cv);
            },
            'd', 'i' => {
                const n = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                var ibuf: [100]u8 = undefined;
                var ifmt: [20]u8 = undefined;
                var ifmt_idx: usize = 0;
                ifmt[ifmt_idx] = '{'; ifmt_idx += 1;
                if (width >= 0 or (flags & 2) != 0 or (flags & 4) != 0) {
                    ifmt[ifmt_idx] = ':'; ifmt_idx += 1;
                    if ((flags & 1) != 0) { ifmt[ifmt_idx] = '<'; ifmt_idx += 1; }
                    if ((flags & 2) != 0) { ifmt[ifmt_idx] = '+'; ifmt_idx += 1; }
                    if ((flags & 4) != 0) { ifmt[ifmt_idx] = ' '; ifmt_idx += 1; }
                    if ((flags & 16) != 0) { ifmt[ifmt_idx] = '0'; ifmt_idx += 1; }
                    if (width >= 0) {
                        const ws = try std.fmt.bufPrint(ifmt[ifmt_idx..], "{d}", .{width});
                        ifmt_idx += ws.len;
                    }
                }
                ifmt[ifmt_idx] = '}'; ifmt_idx += 1;
                const s = try std.fmt.bufPrint(&ibuf, "{d}", .{n});
                try lauxlib.luaL_addlstring(L, &b, s);
            },
            'o', 'u', 'x', 'X' => {
                const n = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                var ibuf: [100]u8 = undefined;
                const unsigned_n = @as(u64, @bitCast(n));
                var ifmt: [20]u8 = undefined;
                var ifmt_idx: usize = 0;
                ifmt[ifmt_idx] = '{'; ifmt_idx += 1;
                ifmt[ifmt_idx] = ':'; ifmt_idx += 1;
                if ((flags & 1) != 0) { ifmt[ifmt_idx] = '<'; ifmt_idx += 1; }
                if ((flags & 16) != 0) { ifmt[ifmt_idx] = '0'; ifmt_idx += 1; }
                if ((flags & 8) != 0 and spec == 'x') { ifmt[ifmt_idx] = '#'; ifmt_idx += 1; }
                if (width >= 0) {
                    const ws = try std.fmt.bufPrint(ifmt[ifmt_idx..], "{d}", .{width});
                    ifmt_idx += ws.len;
                }
                switch (spec) {
                    'o' => { ifmt[ifmt_idx] = 'o'; ifmt_idx += 1; },
                    'u' => { ifmt[ifmt_idx] = 'd'; ifmt_idx += 1; },
                    'x' => { ifmt[ifmt_idx] = 'x'; ifmt_idx += 1; },
                    'X' => { ifmt[ifmt_idx] = 'X'; ifmt_idx += 1; },
                    else => unreachable,
                }
                ifmt[ifmt_idx] = '}'; ifmt_idx += 1;
                const s = try std.fmt.bufPrint(&ibuf, "{}", .{unsigned_n});
                try lauxlib.luaL_addlstring(L, &b, s);
            },
            'f' => {
                const n = try lauxlib.luaL_checknumber(L, argn);
                argn += 1;
                var fbuf: [200]u8 = undefined;
                if (precision < 0) precision = 6;
                if (std.math.trunc(n) == n) {
                    // integer that fits, use d format
                    const int_val = @as(i64, @intFromFloat(n));
                    var ifmt: [20]u8 = undefined;
                    var ifmt_idx: usize = 0;
                    ifmt[ifmt_idx] = '{'; ifmt_idx += 1;
                    ifmt[ifmt_idx] = ':'; ifmt_idx += 1;
                    if ((flags & 1) != 0) { ifmt[ifmt_idx] = '<'; ifmt_idx += 1; }
                    if (width >= 0) {
                        const ws = try std.fmt.bufPrint(ifmt[ifmt_idx..], "{d}", .{width});
                        ifmt_idx += ws.len;
                    }
                    if (precision >= 0) {
                        ifmt[ifmt_idx] = '.'; ifmt_idx += 1;
                        const ps = try std.fmt.bufPrint(ifmt[ifmt_idx..], "{d}", .{precision});
                        ifmt_idx += ps.len;
                    }
                    ifmt[ifmt_idx] = '}'; ifmt_idx += 1;
                    const s = try std.fmt.bufPrint(&fbuf, "{d}", .{int_val});
                    try lauxlib.luaL_addlstring(L, &b, s);
                } else {
                    const p = @as(usize, @intCast(precision));
                    var ffmt: [20]u8 = undefined;
                    var ffmt_idx: usize = 0;
                    ffmt[ffmt_idx] = '{'; ffmt_idx += 1;
                    ffmt[ffmt_idx] = ':'; ffmt_idx += 1;
                    if ((flags & 1) != 0) { ffmt[ffmt_idx] = '<'; ffmt_idx += 1; }
                    if ((flags & 16) != 0) { ffmt[ffmt_idx] = '0'; ffmt_idx += 1; }
                    if ((flags & 2) != 0) { ffmt[ffmt_idx] = '+'; ffmt_idx += 1; }
                    if ((flags & 4) != 0) { ffmt[ffmt_idx] = ' '; ffmt_idx += 1; }
                    if (width >= 0) {
                        const ws = try std.fmt.bufPrint(ffmt[ffmt_idx..], "{d}", .{width});
                        ffmt_idx += ws.len;
                    }
                    ffmt[ffmt_idx] = '.'; ffmt_idx += 1;
                    const ps = try std.fmt.bufPrint(ffmt[ffmt_idx..], "{d}", .{p});
                    ffmt_idx += ps.len;
                    ffmt[ffmt_idx] = '}'; ffmt_idx += 1;
                    const s = try std.fmt.bufPrint(&fbuf, "{d}", .{n});
                    try lauxlib.luaL_addlstring(L, &b, s);
                }
            },
            'e', 'E', 'g', 'G' => {
                const n = try lauxlib.luaL_checknumber(L, argn);
                argn += 1;
                if (precision < 0) precision = 6;
                var fbuf: [200]u8 = undefined;
                var ffmt: [20]u8 = undefined;
                var ffmt_idx: usize = 0;
                ffmt[ffmt_idx] = '{'; ffmt_idx += 1;
                ffmt[ffmt_idx] = ':'; ffmt_idx += 1;
                if ((flags & 1) != 0) { ffmt[ffmt_idx] = '<'; ffmt_idx += 1; }
                if ((flags & 16) != 0) { ffmt[ffmt_idx] = '0'; ffmt_idx += 1; }
                if ((flags & 2) != 0) { ffmt[ffmt_idx] = '+'; ffmt_idx += 1; }
                if ((flags & 4) != 0) { ffmt[ffmt_idx] = ' '; ffmt_idx += 1; }
                if (width >= 0) {
                    const ws = try std.fmt.bufPrint(ffmt[ffmt_idx..], "{d}", .{width});
                    ffmt_idx += ws.len;
                }
                ffmt[ffmt_idx] = '.'; ffmt_idx += 1;
                const ps = try std.fmt.bufPrint(ffmt[ffmt_idx..], "{d}", .{precision});
                ffmt_idx += ps.len;
                switch (spec) {
                    'e' => { ffmt[ffmt_idx] = 'e'; ffmt_idx += 1; },
                    'E' => { ffmt[ffmt_idx] = 'E'; ffmt_idx += 1; },
                    'g' => { ffmt[ffmt_idx] = 'e'; ffmt_idx += 1; },
                    'G' => { ffmt[ffmt_idx] = 'E'; ffmt_idx += 1; },
                    else => unreachable,
                }
                ffmt[ffmt_idx] = '}'; ffmt_idx += 1;
                const s = try std.fmt.bufPrint(&fbuf, "{d}", .{n});
                var result = s;
                if (spec == 'g' or spec == 'G') {
                    // Remove trailing zeros for %g/%G
                    if (std.mem.indexOfScalar(u8, s, '.')) |dot| {
                        var end = s.len;
                        while (end > dot + 1 and s[end - 1] == '0') : (end -= 1) {}
                        if (end == dot + 1 and s[dot + 1] == '0') end = dot;
                        result = s[0..end];
                    }
                }
                try lauxlib.luaL_addlstring(L, &b, result[0..result.len]);
            },
            'a', 'A' => {
                var sl: usize = 0;
                _ = try lauxlib.luaL_checklstring(L, argn, &sl);
                const n = try lauxlib.luaL_checknumber(L, argn);
                argn += 1;
                var ifmt_offset: usize = 0;
                var fbuf: [200]u8 = undefined;
                if (spec == 'A') {
                    fbuf[0] = '%'; fbuf[1] = 'A';
                    ifmt_offset = 2;
                } else {
                    fbuf[0] = '%'; fbuf[1] = 'a';
                    ifmt_offset = 2;
                }
                if (width >= 0) {
                    const ws = try std.fmt.bufPrint(fbuf[ifmt_offset..], "{d}", .{width});
                    ifmt_offset += ws.len;
                }
                if (precision >= 0) {
                    fbuf[ifmt_offset] = '.';
                    ifmt_offset += 1;
                    const ps = try std.fmt.bufPrint(fbuf[ifmt_offset..], "{d}", .{precision});
                    ifmt_offset += ps.len;
                }
                const s = try lua_number2strx(L, fbuf[0..ifmt_offset], n);
                try lauxlib.luaL_addlstring(L, &b, s);
            },
            'p' => {
                var sl: usize = 0;
                _ = try lauxlib.luaL_checklstring(L, argn, &sl);
                const p_val = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                var ibuf: [100]u8 = undefined;
                const s = try std.fmt.bufPrint(&ibuf, "{d}", .{p_val});
                try lauxlib.luaL_addlstring(L, &b, s);
            },
            'q' => {
                try addliteral(L, &b, argn);
                argn += 1;
            },
            else => {
                // Unknown specifier, just add as literal
                try lauxlib.luaL_addchar(L, &b, '%');
                try lauxlib.luaL_addchar(L, &b, spec);
            },
        }
    }

    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

const Header = struct {
    endian: std.builtin.Endian,
    maxalign: usize,
};

const KOption = enum(u8) {
    int = 0,
    uint,
    float,
    char,
    zstr,
    str,
    strz,
    sizet,
    pad,
    padalign,
    max,
    _,
};

fn digit(c: u8) ?i32 {
    if (c >= '0' and c <= '9') return @as(i32, @intCast(c - '0'));
    return null;
}

fn getnum(s: []const u8, p: *usize) i32 {
    var val: i32 = 0;
    var pos = p.*;
    while (pos < s.len and std.ascii.isDigit(s[pos])) : (pos += 1) {
        val = val * 10 + @as(i32, @intCast(s[pos] - '0'));
    }
    p.* = pos;
    return val;
}

fn getnumlimit(_: *Header, s: []const u8, p: *usize, limit: i32) i32 {
    var pos = p.*;
    var val: i32 = 0;
    if (pos < s.len) {
        const c = s[pos];
        if (digit(c)) |_| {
            val = getnum(s, &pos);
            if (val > limit) {
                val = limit;
            }
        }
    }
    p.* = pos;
    return val;
}

fn initheader(L: *lua.lua_State, h: *Header) void {
    h.endian = @import("builtin").target.cpu.arch.endian();
    h.maxalign = 1;
    _ = L;
}

fn getoption(h: *Header, s: []const u8, pos: *usize, opt: *u8, size: *i32) KOption {
    var p = pos.*;
    if (p >= s.len) return .max;
    const c = s[p];
    p += 1;
    const res: KOption = switch (c) {
        'b' => blk: {
            size.* = @sizeOf(u8);
            break :blk .int;
        },
        'B' => blk: {
            size.* = @sizeOf(u8);
            break :blk .uint;
        },
        'h' => blk: {
            size.* = @sizeOf(i16);
            break :blk .int;
        },
        'H' => blk: {
            size.* = @sizeOf(u16);
            break :blk .uint;
        },
        'l' => blk: {
            size.* = @sizeOf(i32);
            break :blk .int;
        },
        'L' => blk: {
            size.* = @sizeOf(u32);
            break :blk .uint;
        },
        'j' => blk: {
            size.* = @sizeOf(i64);
            break :blk .int;
        },
        'J' => blk: {
            size.* = @sizeOf(u64);
            break :blk .uint;
        },
        'T' => blk: {
            size.* = @sizeOf(usize);
            break :blk .sizet;
        },
        'i' => blk: {
            const count = getnumlimit(h, s, &p, @as(i32, @intCast(@sizeOf(i64))));
            size.* = if (count > 0) count else @as(i32, @intCast(@sizeOf(i32)));
            break :blk .int;
        },
        'I' => blk: {
            const count = getnumlimit(h, s, &p, @as(i32, @intCast(@sizeOf(u64))));
            size.* = if (count > 0) count else @as(i32, @intCast(@sizeOf(u32)));
            break :blk .uint;
        },
        'f' => blk: {
            size.* = @sizeOf(f32);
            break :blk .float;
        },
        'd' => blk: {
            size.* = @sizeOf(f64);
            break :blk .float;
        },
        'n' => blk: {
            size.* = @sizeOf(f64);
            break :blk .float;
        },
        'z' => blk: {
            size.* = 1;
            break :blk .zstr;
        },
        'c' => blk: {
            const count = getnumlimit(h, s, &p, @as(i32, @intCast(@sizeOf(usize))));
            size.* = if (count > 0) count else 1;
            break :blk .char;
        },
        'p' => blk: {
            size.* = @sizeOf(u16);
            break :blk .str;
        },
        'P' => blk: {
            size.* = @sizeOf(u32);
            break :blk .str;
        },
        's' => blk: {
            size.* = @sizeOf(usize);
            break :blk .strz;
        },
        ' ' => blk: {
            size.* = 1;
            break :blk .pad;
        },
        'x' => blk: {
            size.* = 1;
            break :blk .pad;
        },
        'X' => blk: {
            size.* = 0;
            break :blk .padalign;
        },
        '<' => {
            h.endian = .little;
            return getoption(h, s, &p, opt, size);
        },
        '>' => {
            h.endian = .big;
            return getoption(h, s, &p, opt, size);
        },
        '=' => {
            h.endian = @import("builtin").target.cpu.arch.endian();
            return getoption(h, s, &p, opt, size);
        },
        '!' => {
            const count = getnumlimit(h, s, &p, @as(i32, @intCast(@sizeOf(usize))));
            h.maxalign = @as(usize, @intCast(count));
            return getoption(h, s, &p, opt, size);
        },
        else => {
            opt.* = c;
            return .max;
        },
    };
    pos.* = p;
    return res;
}

fn getdetails(h: *Header, totalsize: *usize, s: []const u8, pos: *usize, opt: *u8, size: *i32) KOption {
    const o = getoption(h, s, pos, opt, size);
    const st = @as(usize, @intCast(size.*));
    if (h.maxalign > 1) {
        const max_al = if (h.maxalign > st) st else h.maxalign;
        const mask = max_al - 1;
        if ((totalsize.* & mask) != 0) {
            totalsize.* += max_al - (totalsize.* & mask);
        }
    }
    return o;
}

fn packint(data: *std.ArrayList(u8), allocator: std.mem.Allocator, val: u64, size: usize, endian: std.builtin.Endian) !void {
    var i: usize = 0;
    while (i < size) : (i += 1) {
        const shift = @as(u6, @intCast(i * 8));
        const byte = @as(u8, @intCast(val >> shift));
        try data.append(allocator, byte);
    }
    if (endian == .big) {
        var j: usize = 0;
        while (j < size / 2) : (j += 1) {
            const tmp = data.items[j];
            data.items[j] = data.items[size - 1 - j];
            data.items[size - 1 - j] = tmp;
        }
    }
}

fn copywithendian(data: *std.ArrayList(u8), allocator: std.mem.Allocator, src: []const u8, count: usize, endian: std.builtin.Endian) !void {
    if (endian == .big) {
        var i: usize = count;
        while (i > 0) {
            i -= 1;
            try data.append(allocator, src[i]);
        }
    } else {
        try data.appendSlice(allocator, src[0..count]);
    }
}

fn str_pack(L: *lua.lua_State) anyerror!i32 {
    var len: usize = 0;
    const fmt = try lauxlib.luaL_checklstring(L, 1, &len);
    var h: Header = undefined;
    initheader(L, &h);
    var totalsize: usize = 0;
    var pos: usize = 0;
    const gpa = L.allocator;
    var data: std.ArrayList(u8) = .empty;

    while (pos < fmt.len) {
        var opt: u8 = 0;
        var size: i32 = 0;
        const k = getdetails(&h, &totalsize, fmt, &pos, &opt, &size);
        const st = @as(usize, @intCast(size));

        switch (k) {
            .int => {
                const arg = try lauxlib.luaL_checkinteger(L, lua.lua_gettop(L));
                lua.lua_pop(L, 1);
                const unsigned_val = @as(u64, @bitCast(arg));
                if (st > 8) return lauxlib.luaL_error(L, "integer too large");
                try data.ensureUnusedCapacity(gpa, st);
                try packint(&data, gpa, unsigned_val, st, h.endian);
                },
                .uint => {
                    const arg = try lauxlib.luaL_checkinteger(L, lua.lua_gettop(L));
                    lua.lua_pop(L, 1);
                    const unsigned_val = @as(u64, @bitCast(arg));
                    if (st > 8) return lauxlib.luaL_error(L, "integer too large");
                    try data.ensureUnusedCapacity(gpa, st);
                    try packint(&data, gpa, unsigned_val, st, h.endian);
                },
                .float => {
                    if (st == @sizeOf(f32)) {
                        const arg = @as(f32, @floatCast(try lauxlib.luaL_checknumber(L, lua.lua_gettop(L))));
                        lua.lua_pop(L, 1);
                        const bytes = std.mem.asBytes(&arg);
                        try data.ensureUnusedCapacity(gpa, st);
                        try copywithendian(&data, gpa, bytes, st, h.endian);
                    } else if (st == @sizeOf(f64)) {
                        const arg = try lauxlib.luaL_checknumber(L, lua.lua_gettop(L));
                        lua.lua_pop(L, 1);
                        const bytes = std.mem.asBytes(&arg);
                        try data.ensureUnusedCapacity(gpa, st);
                        try copywithendian(&data, gpa, bytes, st, h.endian);
                }
            },
            .char => {
                var sl: usize = 0;
                const s = try lauxlib.luaL_checklstring(L, -1, &sl);
                lua.lua_pop(L, 1);
                if (sl < st) {
                    try data.appendSlice(gpa, s);
                    var i: usize = 0;
                    while (i < st -| sl) : (i += 1) try data.append(gpa, 0);
                } else {
                    try data.appendSlice(gpa, s[0..st]);
                }
            },
            .str => {
                var sl: usize = 0;
                const s = try lauxlib.luaL_checklstring(L, -1, &sl);
                lua.lua_pop(L, 1);
                const max_len = @as(u64, 1) << @as(u6, @intCast(st * 8));
                if (sl >= max_len) return lauxlib.luaL_error(L, "string too long");
                try data.ensureUnusedCapacity(gpa, st + sl);
                try packint(&data, gpa, @as(u64, @intCast(sl)), st, h.endian);
                try data.appendSlice(gpa, s);
            },
            .strz => {
                var sl: usize = 0;
                const s = try lauxlib.luaL_checklstring(L, -1, &sl);
                lua.lua_pop(L, 1);
                try data.ensureUnusedCapacity(gpa, st + sl + 1);
                try packint(&data, gpa, @as(u64, @intCast(sl)), st, h.endian);
                try data.appendSlice(gpa, s);
                try data.append(gpa, 0);
            },
            .zstr => {
                var sl: usize = 0;
                const s = try lauxlib.luaL_checklstring(L, -1, &sl);
                lua.lua_pop(L, 1);
                try data.appendSlice(gpa, s);
                try data.append(gpa, 0);
            },
            .sizet => {
                const arg = try lauxlib.luaL_checkinteger(L, lua.lua_gettop(L));
                lua.lua_pop(L, 1);
                const unsigned_val = @as(u64, @bitCast(arg));
                if (st > 8) return lauxlib.luaL_error(L, "integer too large");
                try data.ensureUnusedCapacity(gpa, st);
                try packint(&data, gpa, unsigned_val, st, h.endian);
            },
            .pad => {
                try data.append(gpa, 0);
            },
            .padalign => {
                if (h.maxalign > 1) {
                    const mask = h.maxalign - 1;
                    if ((data.items.len & mask) != 0) {
                        var i: usize = 0;
                        const pad_count = h.maxalign - (data.items.len & mask);
                        while (i < pad_count) : (i += 1) try data.append(gpa, 0);
                    }
                }
            },
            .max => {
                if (opt == 0) break;
                var fmt_buf: [100]u8 = undefined;
                const fmt_msg = try std.fmt.bufPrint(&fmt_buf, "invalid format option '{c}'", .{opt});
                return lauxlib.luaL_error(L, fmt_msg);
            },
            else => unreachable,
        }
        totalsize += st;
    }

    _ = lua.lua_pushlstring(L, data.items, data.items.len);
    data.deinit(gpa);
    return 1;
}

fn str_packsize(L: *lua.lua_State) anyerror!i32 {
    var len: usize = 0;
    const fmt = try lauxlib.luaL_checklstring(L, 1, &len);
    var h: Header = undefined;
    initheader(L, &h);
    var totalsize: usize = 0;
    var pos: usize = 0;

    while (pos < fmt.len) {
        var opt: u8 = 0;
        var size: i32 = 0;
        const k = getdetails(&h, &totalsize, fmt, &pos, &opt, &size);
        const st = @as(usize, @intCast(size));

        switch (k) {
            .int, .uint, .float, .sizet => {
                if (st > 8) return lauxlib.luaL_error(L, "integer too large");
            },
            .char => {},
            .str, .strz, .zstr => return lauxlib.luaL_error(L, "variable-length format"),
            .pad => {},
            .padalign => {},
            .max => {
                if (opt == 0) break;
                var fmt_buf: [100]u8 = undefined;
                const fmt_msg = try std.fmt.bufPrint(&fmt_buf, "invalid format option '{c}'", .{opt});
                return lauxlib.luaL_error(L, fmt_msg);
            },
            else => unreachable,
        }
        totalsize += st;
    }

    lua.lua_pushinteger(L, @as(i64, @intCast(totalsize)));
    return 1;
}

fn unpackint(L: *lua.lua_State, data: []const u8, size: usize, endian: std.builtin.Endian) !u64 {
    if (size > 8) return lauxlib.luaL_error(L, "integer too large");
    var result: u64 = 0;
    var i: usize = 0;
    if (endian == .big) {
        while (i < size) : (i += 1) {
            result = (result << 8) | @as(u64, data[i]);
        }
    } else {
        var j: usize = size;
        while (j > 0) {
            j -= 1;
            result = (result << 8) | @as(u64, data[j]);
        }
    }
    return result;
}

fn str_unpack(L: *lua.lua_State) anyerror!i32 {
    var fmtlen: usize = 0;
    var datalen: usize = 0;
    const fmt = try lauxlib.luaL_checklstring(L, 1, &fmtlen);
    const data = try lauxlib.luaL_checklstring(L, 2, &datalen);
    const pos = lauxlib.luaL_optinteger(L, 3, 1);
    var h: Header = undefined;
    initheader(L, &h);
    var data_offset: usize = @as(usize, @intCast(pos - 1));
    var fmt_pos: usize = 0;
    var n: i32 = 0;

    while (fmt_pos < fmt.len) {
        var opt: u8 = 0;
        var size: i32 = 0;
        var totalsize: usize = data_offset;
        const k = getdetails(&h, &totalsize, fmt, &fmt_pos, &opt, &size);
        const st = @as(usize, @intCast(size));

        if (data_offset > datalen) return lauxlib.luaL_error(L, "data too short");
        if (k == .max and opt == 0) break;

        switch (k) {
            .int => {
                if (st > 8) return lauxlib.luaL_error(L, "integer too large");
                if (data_offset + st > datalen) return lauxlib.luaL_error(L, "data too short");
                const val = try unpackint(L, data[data_offset..], st, h.endian);
                const signed_val = @as(i64, @bitCast(val));
                lua.lua_pushinteger(L, signed_val);
                n += 1;
                data_offset += st;
            },
            .uint => {
                if (st > 8) return lauxlib.luaL_error(L, "integer too large");
                if (data_offset + st > datalen) return lauxlib.luaL_error(L, "data too short");
                const val = try unpackint(L, data[data_offset..], st, h.endian);
                lua.lua_pushinteger(L, @as(i64, @bitCast(val)));
                n += 1;
                data_offset += st;
            },
            .float => {
                if (data_offset + st > datalen) return lauxlib.luaL_error(L, "data too short");
                const chunk = data[data_offset..][0..st];
                if (st == @sizeOf(f32)) {
                    var bytes: [@sizeOf(f32)]u8 = undefined;
                    if (h.endian == .big) {
                        var i: usize = 0;
                        while (i < st) : (i += 1) bytes[i] = chunk[st - 1 - i];
                    } else {
                        @memcpy(&bytes, chunk);
                    }
                    const val = @as(f64, @floatCast(@as(f32, @bitCast(bytes))));
                    lua.lua_pushnumber(L, val);
                } else if (st == @sizeOf(f64)) {
                    var bytes: [@sizeOf(f64)]u8 = undefined;
                    if (h.endian == .big) {
                        var i: usize = 0;
                        while (i < st) : (i += 1) bytes[i] = chunk[st - 1 - i];
                    } else {
                        @memcpy(&bytes, chunk);
                    }
                    const val = @as(f64, @bitCast(bytes));
                    lua.lua_pushnumber(L, val);
                }
                n += 1;
                data_offset += st;
            },
            .char => {
                if (data_offset + st > datalen) return lauxlib.luaL_error(L, "data too short");
                _ = lua.lua_pushlstring(L, data[data_offset..][0..st], st);
                n += 1;
                data_offset += st;
            },
            .str => {
                if (data_offset + st > datalen) return lauxlib.luaL_error(L, "data too short");
                const sl_val = try unpackint(L, data[data_offset..], st, h.endian);
                const sl = @as(usize, @intCast(sl_val));
                data_offset += st;
                if (data_offset + sl > datalen) return lauxlib.luaL_error(L, "data too short");
                _ = lua.lua_pushlstring(L, data[data_offset..][0..sl], sl);
                n += 1;
                data_offset += sl;
            },
            .strz => {
                if (data_offset + st > datalen) return lauxlib.luaL_error(L, "data too short");
                const sl_val = try unpackint(L, data[data_offset..], st, h.endian);
                const sl = @as(usize, @intCast(sl_val));
                data_offset += st;
                if (data_offset + sl + 1 > datalen) return lauxlib.luaL_error(L, "data too short");
                _ = lua.lua_pushlstring(L, data[data_offset..][0..sl], sl);
                n += 1;
                data_offset += sl + 1;
            },
            .zstr => {
                var zero_pos: ?usize = null;
                var i: usize = data_offset;
                while (i < datalen) : (i += 1) {
                    if (data[i] == 0) {
                        zero_pos = i;
                        break;
                    }
                }
                if (zero_pos) |zp| {
                    _ = lua.lua_pushlstring(L, data[data_offset..][0 .. zp - data_offset], zp - data_offset);
                    n += 1;
                    data_offset = zp + 1;
                } else {
                    return lauxlib.luaL_error(L, "data too short (unfinished zero-terminated string)");
                }
            },
            .sizet => {
                if (st > 8) return lauxlib.luaL_error(L, "integer too large");
                if (data_offset + st > datalen) return lauxlib.luaL_error(L, "data too short");
                const val = try unpackint(L, data[data_offset..], st, h.endian);
                lua.lua_pushinteger(L, @as(i64, @bitCast(val)));
                n += 1;
                data_offset += st;
            },
            .pad => {
                if (data_offset + st > datalen) return lauxlib.luaL_error(L, "data too short");
                data_offset += st;
            },
            .padalign => {
                if (h.maxalign > 1) {
                    const mask = h.maxalign - 1;
                    if ((data_offset & mask) != 0) {
                        data_offset += h.maxalign - (data_offset & mask);
                    }
                }
            },
            .max => unreachable,
            else => unreachable,
        }
    }

    lua.lua_pushinteger(L, @as(i64, @intCast(data_offset + 1)));
    return n + 1;
}

const strlib = [_]struct {
    name: []const u8,
    func: lua.lua_CFunction,
}{
    .{ .name = "byte",    .func = str_byte },
    .{ .name = "char",    .func = str_char },
    .{ .name = "dump",    .func = str_dump },
    .{ .name = "find",    .func = str_find },
    .{ .name = "format",  .func = str_format },
    .{ .name = "gmatch",  .func = gmatch },
    .{ .name = "gsub",    .func = str_gsub },
    .{ .name = "len",     .func = str_len },
    .{ .name = "lower",   .func = str_lower },
    .{ .name = "match",   .func = str_match },
    .{ .name = "rep",     .func = str_rep },
    .{ .name = "reverse", .func = str_reverse },
    .{ .name = "sub",     .func = str_sub },
    .{ .name = "upper",   .func = str_upper },
    .{ .name = "pack",    .func = str_pack },
    .{ .name = "packsize", .func = str_packsize },
    .{ .name = "unpack",  .func = str_unpack },
};

fn createmetatable(L: *lua.lua_State) !void {
    lua.lua_createtable(L, 0, 1);
    lua.lua_pushvalue(L, -2);
    try lua.lua_setfield(L, -2, "__index");
    lua.lua_pushvalue(L, -1);
    _ = lua.lua_setmetatable(L, -2);
}

pub fn openstringlib(L: *lua.lua_State) anyerror!i32 {
    lua.lua_createtable(L, 0, @as(i32, @intCast(strlib.len)));
    for (&strlib) |reg| {
        lua.lua_pushcfunction(L, reg.func);
        try lua.lua_setfield(L, -2, reg.name);
    }
    try createmetatable(L);
    return 1;
}
