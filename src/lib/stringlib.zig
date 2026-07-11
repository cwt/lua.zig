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
    const MAX_SIZE = @min(std.math.maxInt(usize) / 2, @as(usize, @intCast(std.math.maxInt(i64))));
    const un = @as(u64, @intCast(n));
    if (len > MAX_SIZE -| lsep or (len + lsep) > MAX_SIZE / un) {
        return lauxlib.luaL_error(L, "resulting string too large");
    }
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
    if (pose - posi >= @as(usize, @intCast(std.math.maxInt(i32)))) {
        return lauxlib.luaL_error(L, "string slice too long");
    }
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

fn classend(ms: *MatchState, p_idx: usize) anyerror!usize {
    switch (ms.p[p_idx]) {
        '%' => {
            if (p_idx + 1 >= ms.p_end) {
                return lauxlib.luaL_error(ms.L, "malformed pattern (ends with '%')");
            }
            return p_idx + 2;
        },
        '[' => {
            var p = p_idx + 1;
            if (p < ms.p_end and ms.p[p] == '^') p += 1;
            while (true) {
                if (p >= ms.p_end) {
                    return lauxlib.luaL_error(ms.L, "malformed pattern (missing ']')");
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

fn matchbalance(ms: *MatchState, s: usize, p: usize) anyerror!?usize {
    if (p + 1 >= ms.p_end) {
        return lauxlib.luaL_error(ms.L, "malformed pattern (missing arguments to '%b')");
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

fn max_expand(ms: *MatchState, s: usize, p: usize, ep: usize) anyerror!?usize {
    var i: usize = 0;
    while (singlematch(ms, s + i, p, ep)) : (i += 1) {}
    while (true) {
        const res = try match(ms, s + i, ep + 1);
        if (res) |r| return r;
        if (i == 0) return null;
        i -= 1;
    }
}

fn min_expand(ms: *MatchState, s: usize, p: usize, ep: usize) anyerror!?usize {
    var s_idx = s;
    while (true) {
        const res = try match(ms, s_idx, ep + 1);
        if (res) |r| return r;
        if (singlematch(ms, s_idx, p, ep)) {
            s_idx += 1;
        } else {
            return null;
        }
    }
}

fn start_capture(ms: *MatchState, s: usize, p: usize, what: i64) anyerror!?usize {
    const level = ms.level;
    if (level >= LUA_MAXCAPTURES) {
        return lauxlib.luaL_error(ms.L, "too many captures");
    }
    ms.capture[@as(usize, @intCast(level))] = .{ .init = s, .len = what };
    ms.level = level + 1;
    const res = try match(ms, s, p);
    if (res == null) ms.level = level;
    return res;
}

fn end_capture(ms: *MatchState, s: usize, p: usize) anyerror!?usize {
    const l = try capture_to_close(ms) orelse return null;
    ms.capture[l].len = @as(i64, @intCast(s)) - @as(i64, @intCast(ms.capture[l].init));
    const res = try match(ms, s, p);
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

fn capture_to_close(ms: *MatchState) anyerror!?usize {
    var level: i32 = ms.level - 1;
    while (level >= 0) : (level -= 1) {
        if (ms.capture[@as(usize, @intCast(level))].len == CAP_UNFINISHED) {
            return @as(usize, @intCast(level));
        }
    }
    return lauxlib.luaL_error(ms.L, "invalid pattern capture");
}

fn match_capture(ms: *MatchState, s: usize, l: u8) anyerror!?usize {
    const cap_idx = try check_capture(ms, l);
    const init = ms.capture[cap_idx].init;
    const capl = @as(usize, @intCast(ms.capture[cap_idx].len));
    if (ms.src_end -| s >= capl and std.mem.eql(u8, ms.src[init..][0..capl], ms.src[s..][0..capl])) {
        return s + capl;
    }
    return null;
}

fn match(ms: *MatchState, s: usize, p: usize) anyerror!?usize {
    if (ms.matchdepth == 0) {
        return lauxlib.luaL_error(ms.L, "pattern too complex");
    }
    ms.matchdepth -= 1;
    defer ms.matchdepth += 1;

    var s_idx = s;
    var p_idx = p;

    while (p_idx < ms.p_end) {
        switch (ms.p[p_idx]) {
            '(' => {
                if (p_idx + 1 < ms.p_end and ms.p[p_idx + 1] == ')') {
                    s_idx = (try start_capture(ms, s_idx, p_idx + 2, CAP_POSITION)) orelse return null;
                } else {
                    s_idx = (try start_capture(ms, s_idx, p_idx + 1, CAP_UNFINISHED)) orelse return null;
                }
                break;
            },
            ')' => {
                s_idx = (try end_capture(ms, s_idx, p_idx + 1)) orelse return null;
                break;
            },
            '$' => {
                if (p_idx + 1 == ms.p_end) {
                    if (s_idx != ms.src_end) return null;
                    break;
                }
                const ep = try classend(ms, p_idx);
                if (!singlematch(ms, s_idx, p_idx, ep)) {
                    if (ep < ms.p_end and (ms.p[ep] == '*' or ms.p[ep] == '?' or ms.p[ep] == '-')) {
                        p_idx = ep + 1;
                        continue;
                    } else {
                        return null;
                    }
                } else {
                    const suffix = if (ep < ms.p_end) ms.p[ep] else 0;
                    switch (suffix) {
                        '?' => {
                            if (try match(ms, s_idx + 1, ep + 1)) |res| {
                                s_idx = res;
                            } else {
                                p_idx = ep + 1;
                                continue;
                            }
                        },
                        '+' => {
                            s_idx = (try max_expand(ms, s_idx + 1, p_idx, ep)) orelse return null;
                        },
                        '*' => {
                            s_idx = (try max_expand(ms, s_idx, p_idx, ep)) orelse return null;
                        },
                        '-' => {
                            s_idx = (try min_expand(ms, s_idx, p_idx, ep)) orelse return null;
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
                    return lauxlib.luaL_error(ms.L, "malformed pattern (ends with '%')");
                }
                switch (ms.p[p_idx]) {
                    'b' => {
                        s_idx = (try matchbalance(ms, s_idx, p_idx + 1)) orelse break;
                        p_idx += 3;
                        continue;
                    },
                    'f' => {
                        p_idx += 1;
                        if (p_idx >= ms.p_end or ms.p[p_idx] != '[') {
                            return lauxlib.luaL_error(ms.L, "missing '[' after '%f' in pattern");
                        }
                        const ep = try classend(ms, p_idx);
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
                        s_idx = (try match_capture(ms, s_idx, ms.p[p_idx])) orelse return null;
                        p_idx += 2;
                        continue;
                    },
                    else => {
                        const ep = try classend(ms, p_idx - 1);
                        if (!singlematch(ms, s_idx, p_idx - 1, ep)) {
                            if (ep < ms.p_end and (ms.p[ep] == '*' or ms.p[ep] == '?' or ms.p[ep] == '-')) {
                                p_idx = ep + 1;
                                continue;
                            } else {
                                return null;
                            }
                        } else {
                            const suffix = if (ep < ms.p_end) ms.p[ep] else 0;
                            switch (suffix) {
                                '?' => {
                                    if (try match(ms, s_idx + 1, ep + 1)) |res| {
                                        s_idx = res;
                                    } else {
                                        p_idx = ep + 1;
                                        continue;
                                    }
                                },
                                '+' => {
                                    s_idx = (try max_expand(ms, s_idx + 1, p_idx - 1, ep)) orelse return null;
                                },
                                '*' => {
                                    s_idx = (try max_expand(ms, s_idx, p_idx - 1, ep)) orelse return null;
                                },
                                '-' => {
                                    s_idx = (try min_expand(ms, s_idx, p_idx - 1, ep)) orelse return null;
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
                const ep = try classend(ms, p_idx);
                if (!singlematch(ms, s_idx, p_idx, ep)) {
                    if (ep < ms.p_end and (ms.p[ep] == '*' or ms.p[ep] == '?' or ms.p[ep] == '-')) {
                        p_idx = ep + 1;
                        continue;
                    } else {
                        return null;
                    }
                } else {
                    const suffix = if (ep < ms.p_end) ms.p[ep] else 0;
                    switch (suffix) {
                        '?' => {
                            if (try match(ms, s_idx + 1, ep + 1)) |res| {
                                s_idx = res;
                            } else {
                                p_idx = ep + 1;
                                continue;
                            }
                        },
                        '+' => {
                            s_idx = (try max_expand(ms, s_idx + 1, p_idx, ep)) orelse return null;
                        },
                        '*' => {
                            s_idx = (try max_expand(ms, s_idx, p_idx, ep)) orelse return null;
                        },
                        '-' => {
                            s_idx = (try min_expand(ms, s_idx, p_idx, ep)) orelse return null;
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
            const res = try match(&ms, s_idx, 0);
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
        const e = try match(&gm.ms, src, gm.p_idx);
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
            return lauxlib.luaL_error(L, "invalid use of '%' in replacement string");
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
            return lauxlib.luaL_error(L, "invalid use of '%' in replacement string");
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
        var temp_buf: [128]u8 = undefined;
        const typename = lua.lua_typename(lua.lua_type(L, -1));
        const msg = try std.fmt.bufPrint(&temp_buf, "invalid replacement value (a {s})", .{typename});
        return lauxlib.luaL_error(L, msg);
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
        const e = try match(&ms, src_idx, 0);
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
        if (c == '"' or c == '\\' or c == '\n') {
            try lauxlib.luaL_addchar(L, b, '\\');
            try lauxlib.luaL_addchar(L, b, c);
        } else if (std.ascii.isControl(c)) {
            var buff: [10]u8 = undefined;
            var nb: usize = 0;
            const next_is_digit = (i + 1 < len) and std.ascii.isDigit(s[i + 1]);
            if (!next_is_digit) {
                const slice = try std.fmt.bufPrint(&buff, "\\{d}", .{c});
                nb = slice.len;
            } else {
                const slice = try std.fmt.bufPrint(&buff, "\\{d:0>3}", .{c});
                nb = slice.len;
            }
            try lauxlib.luaL_addlstring(L, b, buff[0..nb]);
        } else {
            try lauxlib.luaL_addchar(L, b, c);
        }
    }
    try lauxlib.luaL_addchar(L, b, '"');
}

fn quotefloat(buf: []u8, n: f64) ![]const u8 {
    if (std.math.isInf(n)) {
        return if (n > 0) "1e9999" else "-1e9999";
    }
    if (std.math.isNan(n)) {
        return "(0/0)";
    }
    var temp_buf: [150]u8 = undefined;
    const hex_float = try formatFloatA(&temp_buf, @abs(n), 'a', null);
    
    var prefix: []const u8 = "";
    if (std.math.signbit(n)) {
        prefix = "-";
    }
    
    if (prefix.len + hex_float.len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[0..prefix.len], prefix);
    @memcpy(buf[prefix.len..][0..hex_float.len], hex_float);
    return buf[0..prefix.len + hex_float.len];
}

fn addliteral(L: *lua.lua_State, b: *lauxlib.luaL_Buffer, arg: i32) !void {
    switch (lua.lua_type(L, arg)) {
        lua.LUA_TNIL, lua.LUA_TBOOLEAN => {
            var len: usize = 0;
            _ = lauxlib.luaL_tolstring(L, arg, &len);
            try lauxlib.luaL_addvalue(L, b);
        },
        lua.LUA_TNUMBER => {
            if (lua.lua_isinteger(L, arg) != 0) {
                const n = lua.lua_tointeger(L, arg) orelse 0;
                var buf: [100]u8 = undefined;
                var s: []const u8 = "";
                if (n == std.math.minInt(i64)) {
                    s = try std.fmt.bufPrint(&buf, "0x{x}", .{@as(u64, @bitCast(n))});
                } else {
                    s = try std.fmt.bufPrint(&buf, "{d}", .{n});
                }
                try lauxlib.luaL_addlstring(L, b, s);
            } else {
                const n = lua.lua_tonumber(L, arg) orelse 0.0;
                var buf: [150]u8 = undefined;
                const s = try quotefloat(&buf, n);
                try lauxlib.luaL_addlstring(L, b, s);
            }
        },
        lua.LUA_TSTRING => {
            var len: usize = 0;
            const s = lua.lua_tolstring(L, arg, &len) orelse "";
            try addquoted(L, b, s, len);
        },
        else => {
            return lauxlib.luaL_argerror(L, arg, "value has no literal form");
        },
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

fn intToString(comptime val: usize) []const u8 {
    if (val == 0) return "0";
    var res: []const u8 = "";
    var temp = val;
    while (temp > 0) {
        const digit_char = &[_]u8{ '0' + @as(u8, @intCast(temp % 10)) };
        res = digit_char ++ res;
        temp /= 10;
    }
    return res;
}

fn formatFloatF(buf: []u8, abs_val: f64, precision: usize) ![]const u8 {
    const fmts = comptime blk: {
        var arr: [101][]const u8 = undefined;
        for (0..101) |i| {
            arr[i] = "{d:." ++ intToString(i) ++ "}";
        }
        break :blk arr;
    };
    const prec = if (precision > 100) 100 else precision;
    inline for (0..101) |i| {
        if (prec == i) {
            return try std.fmt.bufPrint(buf, fmts[i], .{abs_val});
        }
    }
    return error.NoSpaceLeft;
}

fn formatFloatE(buf: []u8, abs_val: f64, spec: u8, precision: usize) ![]const u8 {
    const fmts = comptime blk: {
        var arr: [101][]const u8 = undefined;
        for (0..101) |i| {
            arr[i] = "{e:." ++ intToString(i) ++ "}";
        }
        break :blk arr;
    };
    const prec = if (precision > 100) 100 else precision;
    var raw: []const u8 = "";
    var raw_buf: [150]u8 = undefined;
    inline for (0..101) |i| {
        if (prec == i) {
            raw = try std.fmt.bufPrint(&raw_buf, fmts[i], .{abs_val});
        }
    }
    if (raw.len == 0) return error.NoSpaceLeft;
    
    var out_buf: [150]u8 = undefined;
    var len: usize = 0;
    var e_idx: ?usize = null;
    for (raw, 0..) |c, idx| {
        if (c == 'e') {
            e_idx = idx;
            break;
        }
    }
    
    if (e_idx) |ei| {
        @memcpy(out_buf[0..ei], raw[0..ei]);
        len = ei;
        out_buf[len] = if (spec == 'E' or spec == 'G') 'E' else 'e';
        len += 1;
        const exp_str = raw[ei+1..];
        var exp_sign: u8 = '+';
        var exp_val_str = exp_str;
        if (exp_str.len > 0 and (exp_str[0] == '-' or exp_str[0] == '+')) {
            exp_sign = exp_str[0];
            exp_val_str = exp_str[1..];
        }
        out_buf[len] = exp_sign;
        len += 1;
        if (exp_val_str.len == 1) {
            out_buf[len] = '0';
            out_buf[len+1] = exp_val_str[0];
            len += 2;
        } else {
            @memcpy(out_buf[len..][0..exp_val_str.len], exp_val_str);
            len += exp_val_str.len;
        }
    } else {
        @memcpy(out_buf[0..raw.len], raw);
        len = raw.len;
    }
    if (len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[0..len], out_buf[0..len]);
    return buf[0..len];
}

fn formatFloatG(buf: []u8, abs_val: f64, spec: u8, precision: usize, strip_zeros: bool) ![]const u8 {
    if (std.math.isNan(abs_val)) {
        return if (spec == 'G') "NAN" else "nan";
    }
    if (std.math.isInf(abs_val)) {
        return if (spec == 'G') "INF" else "inf";
    }
    if (abs_val == 0.0) {
        if (strip_zeros) return "0";
        return try formatFloatF(buf, 0.0, precision - 1);
    }
    const log10_val = std.math.log10(abs_val);
    const exponent = @as(i32, @intCast(@as(i64, @intFromFloat(std.math.floor(log10_val)))));
    const p = if (precision == 0) @as(usize, 1) else precision;
    var temp_buf: [150]u8 = undefined;
    var raw: []const u8 = "";
    if (exponent < -4 or exponent >= p) {
        const prec_e = p - 1;
        raw = try formatFloatE(&temp_buf, abs_val, spec, prec_e);
    } else {
        const dec_places = @as(i32, @intCast(p)) - 1 - exponent;
        if (dec_places > 0) {
            raw = try formatFloatF(&temp_buf, abs_val, @intCast(dec_places));
        } else {
            raw = try formatFloatF(&temp_buf, abs_val, 0);
        }
    }
    var out_buf: [150]u8 = undefined;
    @memcpy(out_buf[0..raw.len], raw);
    var len = raw.len;
    if (strip_zeros) {
        var exp_idx: ?usize = null;
        for (out_buf[0..len], 0..) |c, i| {
            if (c == 'e' or c == 'E') {
                exp_idx = i;
                break;
            }
        }
        const end_frac = exp_idx orelse len;
        var dot_idx: ?usize = null;
        for (out_buf[0..end_frac], 0..) |c, i| {
            if (c == '.') {
                dot_idx = i;
                break;
            }
        }
        if (dot_idx) |di| {
            var new_end_frac = end_frac;
            while (new_end_frac > di + 1 and out_buf[new_end_frac - 1] == '0') {
                new_end_frac -= 1;
            }
            if (new_end_frac == di + 1) {
                new_end_frac = di;
            }
            if (exp_idx) |ei| {
                const exp_len = len - ei;
                std.mem.copyForwards(u8, out_buf[new_end_frac..][0..exp_len], out_buf[ei..][0..exp_len]);
                len = new_end_frac + exp_len;
            } else {
                len = new_end_frac;
            }
        }
    }
    if (len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[0..len], out_buf[0..len]);
    return buf[0..len];
}

fn formatFloatA(buf: []u8, abs_val: f64, spec: u8, precision: ?usize) ![]const u8 {
    var raw: []const u8 = "";
    var temp_buf: [150]u8 = undefined;
    if (precision) |p| {
        const fmts = comptime blk: {
            var arr: [101][]const u8 = undefined;
            for (0..101) |i| {
                arr[i] = "{x:." ++ intToString(i) ++ "}";
            }
            break :blk arr;
        };
        const prec = if (p > 100) 100 else p;
        inline for (0..101) |i| {
            if (prec == i) {
                raw = try std.fmt.bufPrint(&temp_buf, fmts[i], .{abs_val});
            }
        }
    } else {
        raw = try std.fmt.bufPrint(&temp_buf, "{x}", .{abs_val});
    }
    if (raw.len == 0) return error.NoSpaceLeft;
    
    var out_buf: [150]u8 = undefined;
    var len: usize = 0;
    var p_idx: ?usize = null;
    for (raw, 0..) |c, i| {
        if (c == 'p' or c == 'P') {
            p_idx = i;
            break;
        }
    }
    
    if (p_idx) |pi| {
        @memcpy(out_buf[0..pi], raw[0..pi]);
        len = pi;
        out_buf[len] = if (spec == 'A') 'P' else 'p';
        len += 1;
        const exp_str = raw[pi+1..];
        if (exp_str.len > 0 and exp_str[0] != '+' and exp_str[0] != '-') {
            out_buf[len] = '+';
            len += 1;
        }
        @memcpy(out_buf[len..][0..exp_str.len], exp_str);
        len += exp_str.len;
    } else {
        @memcpy(out_buf[0..raw.len], raw);
        len = raw.len;
    }
    
    if (spec == 'A') {
        if (len >= 2 and out_buf[0] == '0' and out_buf[1] == 'x') {
            out_buf[1] = 'X';
        }
        const hex_end = p_idx orelse len;
        for (out_buf[2..hex_end]) |*c| {
            c.* = std.ascii.toUpper(c.*);
        }
    }
    
    if (len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[0..len], out_buf[0..len]);
    return buf[0..len];
}

fn formatFloat(buf: []u8, val: f64, spec: u8, flags: u8, precision: ?usize) ![]const u8 {
    var prefix: []const u8 = "";
    const is_neg = std.math.signbit(val);
    if (is_neg) {
        prefix = "-";
    } else {
        if ((flags & 2) != 0) { // '+'
            prefix = "+";
        } else if ((flags & 4) != 0) { // ' '
            prefix = " ";
        }
    }
    const abs_val = @abs(val);
    var val_buf: [150]u8 = undefined;
    var raw: []const u8 = "";
    const prec = precision orelse 6;
    switch (spec) {
        'f' => {
            raw = try formatFloatF(&val_buf, abs_val, prec);
        },
        'e', 'E' => {
            raw = try formatFloatE(&val_buf, abs_val, spec, prec);
        },
        'g', 'G' => {
            const strip_zeros = (flags & 8) == 0;
            raw = try formatFloatG(&val_buf, abs_val, spec, prec, strip_zeros);
        },
        'a', 'A' => {
            raw = try formatFloatA(&val_buf, abs_val, spec, precision);
        },
        else => unreachable,
    }
    const total_len = prefix.len + raw.len;
    if (total_len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[0..prefix.len], prefix);
    @memcpy(buf[prefix.len..][0..raw.len], raw);
    return buf[0..total_len];
}

fn formatInteger(buf: []u8, val: i64, spec: u8, flags: u8, precision: ?usize) ![]const u8 {
    var prefix: []const u8 = "";
    var abs_val: u64 = undefined;
    if (spec == 'd' or spec == 'i') {
        if (val < 0) {
            prefix = "-";
            abs_val = @as(u64, @bitCast(-%val));
        } else {
            if ((flags & 2) != 0) { // '+'
                prefix = "+";
            } else if ((flags & 4) != 0) { // ' '
                prefix = " ";
            }
            abs_val = @as(u64, @intCast(val));
        }
    } else {
        abs_val = @as(u64, @bitCast(val));
        if ((flags & 8) != 0 and abs_val != 0) { // '#'
            if (spec == 'x') {
                prefix = "0x";
            } else if (spec == 'X') {
                prefix = "0X";
            } else if (spec == 'o') {
                prefix = "0";
            }
        }
    }
    var digits_buf: [100]u8 = undefined;
    var digits: []const u8 = "";
    if (abs_val == 0 and precision == 0) {
        digits = "";
    } else {
        const base: u8 = switch (spec) {
            'o' => 8,
            'x', 'X' => 16,
            else => 10,
        };
        const case: std.fmt.Case = if (spec == 'X') .upper else .lower;
        const len = std.fmt.printInt(&digits_buf, abs_val, base, case, .{});
        digits = digits_buf[0..len];
    }
    var prec_digits_buf: [150]u8 = undefined;
    var prec_digits = digits;
    if (precision) |p| {
        if (digits.len < p) {
            const pad_len = p - digits.len;
            @memset(prec_digits_buf[0..pad_len], '0');
            @memcpy(prec_digits_buf[pad_len..][0..digits.len], digits);
            prec_digits = prec_digits_buf[0..p];
        }
    }
    const total_len = prefix.len + prec_digits.len;
    if (total_len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[0..prefix.len], prefix);
    @memcpy(buf[prefix.len..][0..prec_digits.len], prec_digits);
    return buf[0..total_len];
}

fn getPrefixLen(s: []const u8) usize {
    if (s.len >= 3) {
        const p3 = s[0..3];
        if (std.mem.eql(u8, p3, "-0x") or std.mem.eql(u8, p3, "-0X") or
            std.mem.eql(u8, p3, "+0x") or std.mem.eql(u8, p3, "+0X") or
            std.mem.eql(u8, p3, " 0x") or std.mem.eql(u8, p3, " 0X")) {
            return 3;
        }
    }
    if (s.len >= 2) {
        const p2 = s[0..2];
        if (std.mem.eql(u8, p2, "0x") or std.mem.eql(u8, p2, "0X")) {
            return 2;
        }
    }
    if (s.len >= 1) {
        const c = s[0];
        if (c == '-' or c == '+' or c == ' ') {
            return 1;
        }
    }
    return 0;
}

fn padAndAlign(L: *lua.lua_State, b: *lauxlib.luaL_Buffer, content: []const u8, flags: u8, width: ?usize, is_int: bool, has_precision: bool) !void {
    if (width) |w| {
        if (content.len < w) {
            const pad_len = w - content.len;
            const use_zero_pad = ((flags & 16) != 0) and ((flags & 1) == 0) and (!is_int or !has_precision);
            if (use_zero_pad) {
                const pl = getPrefixLen(content);
                try lauxlib.luaL_addlstring(L, b, content[0..pl]);
                var i: usize = 0;
                while (i < pad_len) : (i += 1) try lauxlib.luaL_addchar(L, b, '0');
                try lauxlib.luaL_addlstring(L, b, content[pl..]);
            } else {
                if ((flags & 1) != 0) { // left aligned
                    try lauxlib.luaL_addlstring(L, b, content);
                    var i: usize = 0;
                    while (i < pad_len) : (i += 1) try lauxlib.luaL_addchar(L, b, ' ');
                } else { // right aligned
                    var i: usize = 0;
                    while (i < pad_len) : (i += 1) try lauxlib.luaL_addchar(L, b, ' ');
                    try lauxlib.luaL_addlstring(L, b, content);
                }
            }
            return;
        }
    }
    try lauxlib.luaL_addlstring(L, b, content);
}

fn str_format(L: *lua.lua_State) anyerror!i32 {
    var len: usize = 0;
    const strfrmt = try lauxlib.luaL_checklstring(L, 1, &len);
    var pos: usize = 0;
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);
    var argn: i32 = 2;
    const top = lua.lua_gettop(L);
    
    while (pos < len) {
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
        pos += 1;
        if (pos >= len) return lauxlib.luaL_error(L, "malformed format string");

        if (strfrmt[pos] == '%') {
            try lauxlib.luaL_addchar(L, &b, '%');
            pos += 1;
            continue;
        }

        if (argn > top) return lauxlib.luaL_error(L, "no value for format");

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

        var width: i64 = -1;
        if (pos < len and std.ascii.isDigit(strfrmt[pos])) {
            const res = get2digits(strfrmt, pos);
            width = @intCast(res.val);
            pos = res.new_pos;
        }

        var precision: i64 = -1;
        if (pos < len and strfrmt[pos] == '.') {
            pos += 1;
            if (pos < len and std.ascii.isDigit(strfrmt[pos])) {
                const res = get2digits(strfrmt, pos);
                precision = @intCast(res.val);
                pos = res.new_pos;
            } else {
                precision = 0;
            }
        }

        if (pos >= len) return lauxlib.luaL_error(L, "malformed format string");

        const spec = strfrmt[pos];
        pos += 1;

        switch (spec) {
            'c' => {
                const c_val = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                if (c_val < 0 or c_val > 255) {
                    return lauxlib.luaL_argerror(L, argn - 1, "value out of range");
                }
                const cv = @as(u8, @intCast(c_val));
                const char_slice = &[1]u8{cv};
                const w = if (width >= 0) @as(usize, @intCast(width)) else null;
                try padAndAlign(L, &b, char_slice, flags, w, false, false);
            },
            'd', 'i' => {
                const n = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                var ibuf: [150]u8 = undefined;
                const prec_val = if (precision >= 0) @as(usize, @intCast(precision)) else null;
                const s_slice = try formatInteger(&ibuf, n, spec, flags, prec_val);
                const w = if (width >= 0) @as(usize, @intCast(width)) else null;
                try padAndAlign(L, &b, s_slice, flags, w, true, precision >= 0);
            },
            'o', 'u', 'x', 'X' => {
                const n = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                var ibuf: [150]u8 = undefined;
                const prec_val = if (precision >= 0) @as(usize, @intCast(precision)) else null;
                const s_slice = try formatInteger(&ibuf, n, spec, flags, prec_val);
                const w = if (width >= 0) @as(usize, @intCast(width)) else null;
                try padAndAlign(L, &b, s_slice, flags, w, true, precision >= 0);
            },
            'f', 'e', 'E', 'g', 'G', 'a', 'A' => {
                const n = try lauxlib.luaL_checknumber(L, argn);
                argn += 1;
                var fbuf: [250]u8 = undefined;
                const prec_val = if (precision >= 0) @as(usize, @intCast(precision)) else null;
                const s_slice = try formatFloat(&fbuf, n, spec, flags, prec_val);
                const w = if (width >= 0) @as(usize, @intCast(width)) else null;
                try padAndAlign(L, &b, s_slice, flags, w, false, false);
            },
            'p' => {
                const p = lua.lua_topointer(L, argn);
                argn += 1;
                var ibuf: [100]u8 = undefined;
                var s_slice: []const u8 = "";
                if (p) |ptr| {
                    s_slice = try std.fmt.bufPrint(&ibuf, "0x{x}", .{@intFromPtr(ptr)});
                } else {
                    s_slice = "(null)";
                }
                const w = if (width >= 0) @as(usize, @intCast(width)) else null;
                try padAndAlign(L, &b, s_slice, flags, w, false, false);
            },
            'q' => {
                if (flags != 0 or width >= 0 or precision >= 0) {
                    return lauxlib.luaL_error(L, "specifier '%q' cannot have modifiers");
                }
                try addliteral(L, &b, argn);
                argn += 1;
            },
            's' => {
                var sl: usize = 0;
                const s = lauxlib.luaL_tolstring(L, argn, &sl) orelse "";
                argn += 1;
                if (flags == 0 and width == -1 and precision == -1) {
                    try lauxlib.luaL_addvalue(L, &b);
                } else {
                    if (std.mem.indexOfScalar(u8, s, 0) != null) {
                        return lauxlib.luaL_argerror(L, argn - 1, "string contains zeros");
                    }
                    var actual_s = s;
                    if (precision >= 0) {
                        const p = @as(usize, @intCast(precision));
                        if (actual_s.len > p) {
                            actual_s = actual_s[0..p];
                        }
                    }
                    const w = if (width >= 0) @as(usize, @intCast(width)) else null;
                    try padAndAlign(L, &b, actual_s, flags, w, false, false);
                    lua.lua_pop(L, 1);
                }
            },
            else => {
                return lauxlib.luaL_error(L, "invalid conversion to 'format'");
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
    _ = lua.lua_pushlstring(L, "", 0);
    lua.lua_pushvalue(L, -2);
    _ = lua.lua_setmetatable(L, -2);
    lua.lua_pop(L, 2);
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
