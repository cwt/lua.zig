// $Id: pattern.zig $
// Pattern matching engine for Lua.zig
// See Copyright Notice in lua.h

const std = @import("std");
const lua = @import("../../lua.zig");
const lauxlib = @import("../../lauxlib.zig");

pub const CAP_UNFINISHED: i64 = -1;
pub const CAP_POSITION: i64 = -2;
pub const LUA_MAXCAPTURES: usize = 32;
pub const MAXCCALLS: i32 = 200;
pub const SPECIALS = "^$*+?.([%-";

pub const MatchState = struct {
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

pub fn posrelatI(pos: i64, len: usize) usize {
    if (pos >= 0) {
        return @as(usize, @intCast(pos));
    } else {
        const slen = @as(i64, @intCast(len));
        if (-pos > slen) return 0;
        return @as(usize, @intCast(slen + pos + 1));
    }
}

pub fn getendpos(L: *lua.lua_State, arg: i32, def: i64, len: usize) usize {
    const end_val = lauxlib.luaL_optinteger(L, arg, def);
    return posrelatI(end_val, len);
}

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
    const key_len = ms.capture[@as(usize, @intCast(i))].len;
    if (key_len == CAP_UNFINISHED) return lauxlib.luaL_error(ms.L, "unfinished capture");
    if (key_len == CAP_POSITION) {
        lua.lua_pushinteger(ms.L, @as(i64, @intCast(init - ms.src_init)) + 1);
    }
    return .{ .init = init, .len = key_len };
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

pub fn str_find(L: *lua.lua_State) anyerror!i32 {
    return str_find_aux(L, true);
}

pub fn str_match(L: *lua.lua_State) anyerror!i32 {
    return str_find_aux(L, false);
}

pub const GMatchState = struct {
    src: usize,
    p_idx: usize,
    lastmatch: usize,
    ms: MatchState,
};

pub fn gmatch_aux(L: *lua.lua_State) anyerror!i32 {
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

pub fn gmatch(L: *lua.lua_State) anyerror!i32 {
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

pub fn str_gsub(L: *lua.lua_State) anyerror!i32 {
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
