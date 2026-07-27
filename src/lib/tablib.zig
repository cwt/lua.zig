const std = @import("std");
const lua = @import("../lua.zig");
const lauxlib = @import("../lauxlib.zig");

const TAB_R = 1;
const TAB_W = 2;
const TAB_L = 4;
const TAB_RW = TAB_R | TAB_W;

const RANLIMIT: u32 = 100;
const LUA_MAXINTEGER: i64 = std.math.maxInt(i64);

fn checkfield(L: *lua.lua_State, key: []const u8, n: i32) bool {
    _ = lua.lua_pushstring(L, key);
    return lua.lua_rawget(L, -n) != lua.LUA_TNIL;
}

fn checktab(L: *lua.lua_State, arg: i32, what: i32) !void {
    const tp = lua.lua_type(L, arg);
    if (tp != lua.LUA_TTABLE) {
        var n: i32 = 1;
        if (lua.lua_getmetatable(L, arg) != 0 and
            ((what & TAB_R) == 0 or checkfield(L, "__index", blk: { n += 1; break :blk n; })) and
            ((what & TAB_W) == 0 or checkfield(L, "__newindex", blk: { n += 1; break :blk n; })) and
            ((what & TAB_L) == 0 or
                tp == lua.LUA_TSTRING or checkfield(L, "__len", blk: { n += 1; break :blk n; })))
        {
            lua.lua_pop(L, n);
        } else {
            try lauxlib.luaL_checktype(L, arg, lua.LUA_TTABLE);
        }
    }
}

fn aux_getn(L: *lua.lua_State, n: i32, w: i32) !i64 {
    try checktab(L, n, w | TAB_L);
    return @as(i64, @intCast(try lauxlib.luaL_len(L, n)));
}

fn tcreate(L: *lua.lua_State) anyerror!i32 {
    const s = try lauxlib.luaL_checkinteger(L, 1);
    try lauxlib.luaL_argcheck(L, s >= 0 and s <= std.math.maxInt(i32), 1, "out of range");
    const r = lauxlib.luaL_optinteger(L, 2, 0);
    try lauxlib.luaL_argcheck(L, r >= 0 and r <= std.math.maxInt(i32), 2, "out of range");
    const max_size: i64 = 1 << 26; // Max ~67 million elements
    if (s > max_size or r > max_size) {
        return lauxlib.luaL_error(L, "table overflow");
    }
    lua.lua_createtable(L, @intCast(s), @intCast(r));
    return 1;
}

fn tinsert(L: *lua.lua_State) anyerror!i32 {
    const e = (try aux_getn(L, 1, TAB_RW)) + 1;
    const pos: i64 = switch (lua.lua_gettop(L)) {
        2 => e,
        3 => blk: {
            const p = try lauxlib.luaL_checkinteger(L, 2);
            try lauxlib.luaL_argcheck(L, @as(u64, @intCast(p)) - 1 < @as(u64, @intCast(e)), 2, "position out of bounds");
            var i = e;
            while (i > p) : (i -= 1) {
                _ = try lua.lua_geti(L, 1, i - 1);
                try lua.lua_seti(L, 1, i);
            }
            break :blk p;
        },
        else => return lauxlib.luaL_error(L, "wrong number of arguments to 'insert'"),
    };
    try lua.lua_seti(L, 1, pos);
    return 0;
}

fn tremove(L: *lua.lua_State) anyerror!i32 {
    const size = try aux_getn(L, 1, TAB_RW);
    const pos = lauxlib.luaL_optinteger(L, 2, size);
    if (pos != size) {
        try lauxlib.luaL_argcheck(L, @as(u64, @intCast(pos)) - 1 <= @as(u64, @intCast(size)), 2, "position out of bounds");
    }
    _ = try lua.lua_geti(L, 1, pos);
    var p = pos;
    while (p < size) : (p += 1) {
        _ = try lua.lua_geti(L, 1, p + 1);
        try lua.lua_seti(L, 1, p);
    }
    lua.lua_pushnil(L);
    try lua.lua_seti(L, 1, p);
    return 1;
}

fn tmove(L: *lua.lua_State) anyerror!i32 {
    const f = try lauxlib.luaL_checkinteger(L, 2);
    const e = try lauxlib.luaL_checkinteger(L, 3);
    const t = try lauxlib.luaL_checkinteger(L, 4);
    const tt: i32 = if (lua.lua_isnoneornil(L, 5)) 1 else 5;
    try checktab(L, 1, TAB_R);
    try checktab(L, tt, TAB_W);
    if (e >= f) {
        try lauxlib.luaL_argcheck(L, f > 0 or e < LUA_MAXINTEGER + f, 3, "too many elements to move");
        const n = e - f + 1;
        try lauxlib.luaL_argcheck(L, t <= LUA_MAXINTEGER - n + 1, 4, "destination wrap around");
        if (t > e or t <= f or (tt != 1 and lua.lua_compare(L, 1, tt, lua.LUA_OPEQ) == 0)) {
            var i: i64 = 0;
            while (i < n) : (i += 1) {
                _ = try lua.lua_geti(L, 1, f + i);
                try lua.lua_seti(L, tt, t + i);
            }
        } else {
            var i: i64 = n - 1;
            while (i >= 0) : (i -= 1) {
                _ = try lua.lua_geti(L, 1, f + i);
                try lua.lua_seti(L, tt, t + i);
            }
        }
    }
    lua.lua_pushvalue(L, tt);
    return 1;
}

fn addfield(L: *lua.lua_State, b: *lauxlib.luaL_Buffer, i: i64) !void {
    _ = try lua.lua_geti(L, 1, i);
    if (lua.lua_isstring(L, -1) == 0) {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "invalid value ({s}) at index {} in table for 'concat'", .{ try lauxlib.luaL_typename(L, -1), i }) catch "invalid value in table for 'concat'";
        return lauxlib.luaL_error(L, msg);
    }
    try lauxlib.luaL_addvalue(L, b);
}

fn tconcat(L: *lua.lua_State) anyerror!i32 {
    const last_max = try aux_getn(L, 1, TAB_R);
    var sep_len: usize = 0;
    const sep = (try lauxlib.luaL_optlstring(L, 2, "", &sep_len)).?;
    var i = lauxlib.luaL_optinteger(L, 3, 1);
    const last_val = lauxlib.luaL_optinteger(L, 4, last_max);
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);
    errdefer b.buf.deinit(L.allocator);
    while (i < last_val) : (i += 1) {
        try addfield(L, &b, i);
        try lauxlib.luaL_addlstring(L, &b, sep);
    }
    if (i == last_val) {
        try addfield(L, &b, i);
    }
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

fn tpack(L: *lua.lua_State) anyerror!i32 {
    const n = lua.lua_gettop(L);
    lua.lua_createtable(L, n, 1);
    lua.lua_insert(L, 1);
    var i: i64 = @intCast(n);
    while (i >= 1) : (i -= 1) {
        lua.lua_rawseti(L, 1, i);
    }
    lua.lua_pushinteger(L, @intCast(n));
    try lua.lua_setfield(L, 1, "n");
    return 1;
}

fn tunpack(L: *lua.lua_State) anyerror!i32 {
    const len = try aux_getn(L, 1, TAB_R);
    const i_val = lauxlib.luaL_optinteger(L, 2, 1);
    const e_val = lauxlib.luaL_optinteger(L, 3, len);
    if (i_val > e_val) return 0;
    const diff = @as(u64, @bitCast(e_val)) -% @as(u64, @bitCast(i_val));
    if (diff >= @as(u64, @intCast(std.math.maxInt(i32) - 1))) {
        return lauxlib.luaL_error(L, "too many results to unpack");
    }
    const n: i32 = @intCast(diff + 1);
    if (lua.lua_checkstack(L, n) == 0) {
        return lauxlib.luaL_error(L, "too many results to unpack");
    }
    var idx = i_val;
    while (idx < e_val) : (idx += 1) {
        _ = try lua.lua_geti(L, 1, idx);
    }
    _ = try lua.lua_geti(L, 1, e_val);
    return n;
}

fn sort_comp(L: *lua.lua_State, a: i32, b: i32) !bool {
    if (lua.lua_isnil(L, 2) != 0) {
        return lua.lua_compare(L, a, b, lua.LUA_OPLT) != 0;
    } else {
        lua.lua_pushvalue(L, 2);
        lua.lua_pushvalue(L, a - 1);
        lua.lua_pushvalue(L, b - 2);
        try lua.lua_call(L, 2, 1);
        const res = lua.lua_toboolean(L, -1) != 0;
        lua.lua_pop(L, 1);
        return res;
    }
}

fn set2(L: *lua.lua_State, i: u32, j: u32) !void {
    try lua.lua_seti(L, 1, @intCast(i));
    try lua.lua_seti(L, 1, @intCast(j));
}

fn choosePivot(lo: u32, up_: u32, rnd: u32) u32 {
    const r4 = (up_ - lo) / 4;
    return (rnd ^ lo ^ up_) % (r4 * 2) + (lo + r4);
}

fn partition(L: *lua.lua_State, lo: u32, up_: u32) !u32 {
    var i: u32 = lo;
    var j: u32 = up_ - 1;
    while (true) {
        while (true) {
            i += 1;
            _ = try lua.lua_geti(L, 1, i);
            if (!(try sort_comp(L, -1, -2))) break;
            if (i == up_ - 1) {
                return lauxlib.luaL_error(L, "invalid order function for sorting");
            }
            lua.lua_pop(L, 1);
        }
        while (true) {
            _ = try lua.lua_geti(L, 1, j);
            if (!(try sort_comp(L, -3, -1))) break;
            if (j < i) {
                return lauxlib.luaL_error(L, "invalid order function for sorting");
            }
            lua.lua_pop(L, 1);
            j -= 1;
        }
        if (j < i) {
            lua.lua_pop(L, 1);
            try set2(L, up_ - 1, i);
            return i;
        }
        try set2(L, i, j);
    }
}

fn auxsort(L: *lua.lua_State, lo: u32, up_: u32, rnd: u32) !void {
    var lo_val = lo;
    var up_val = up_;
    var rnd_val = rnd;
    while (lo_val < up_val) {
        _ = try lua.lua_geti(L, 1, lo_val);
        _ = try lua.lua_geti(L, 1, up_val);
        if (try sort_comp(L, -1, -2)) {
            try set2(L, lo_val, up_val);
        } else {
            lua.lua_pop(L, 2);
        }
        if (up_val - lo_val == 1) return;
        const p: u32 = if (up_val - lo_val < RANLIMIT or rnd_val == 0)
            (lo_val + up_val) / 2
        else
            choosePivot(lo_val, up_val, rnd_val);
        _ = try lua.lua_geti(L, 1, p);
        _ = try lua.lua_geti(L, 1, lo_val);
        if (try sort_comp(L, -2, -1)) {
            try set2(L, p, lo_val);
        } else {
            lua.lua_pop(L, 1);
            _ = try lua.lua_geti(L, 1, up_val);
            if (try sort_comp(L, -1, -2)) {
                try set2(L, p, up_val);
            } else {
                lua.lua_pop(L, 2);
            }
        }
        if (up_val - lo_val == 2) return;
        _ = try lua.lua_geti(L, 1, p);
        lua.lua_pushvalue(L, -1);
        _ = try lua.lua_geti(L, 1, up_val - 1);
        try set2(L, p, up_val - 1);
        const pivot = try partition(L, lo_val, up_val);
        const n: u32 = if (pivot - lo_val < up_val - pivot) pivot - lo_val else up_val - pivot;
        if (pivot - lo_val < up_val - pivot) {
            try auxsort(L, lo_val, pivot - 1, rnd_val);
            lo_val = pivot + 1;
        } else {
            try auxsort(L, pivot + 1, up_val, rnd_val);
            up_val = pivot - 1;
        }
        if ((up_val - lo_val) / 128 > n) {
            rnd_val = 0;
        }
    }
}

fn sort(L: *lua.lua_State) anyerror!i32 {
    const n = try aux_getn(L, 1, TAB_RW);
    if (n > 1) {
        try lauxlib.luaL_argcheck(L, n < std.math.maxInt(i32), 1, "array too big");
        if (!lua.lua_isnoneornil(L, 2)) {
            try lauxlib.luaL_checktype(L, 2, lua.LUA_TFUNCTION);
        }
        lua.lua_settop(L, 2);
        try auxsort(L, 1, @intCast(n), 0);
    }
    return 0;
}

pub fn opentablib(L: *lua.lua_State) anyerror!i32 {
    lua.lua_createtable(L, 0, 8);

    lua.lua_pushcfunction(L, tconcat);
    try lua.lua_setfield(L, -2, "concat");

    lua.lua_pushcfunction(L, tcreate);
    try lua.lua_setfield(L, -2, "create");

    lua.lua_pushcfunction(L, tinsert);
    try lua.lua_setfield(L, -2, "insert");

    lua.lua_pushcfunction(L, tpack);
    try lua.lua_setfield(L, -2, "pack");

    lua.lua_pushcfunction(L, tunpack);
    try lua.lua_setfield(L, -2, "unpack");

    lua.lua_pushcfunction(L, tremove);
    try lua.lua_setfield(L, -2, "remove");

    lua.lua_pushcfunction(L, tmove);
    try lua.lua_setfield(L, -2, "move");

    lua.lua_pushcfunction(L, sort);
    try lua.lua_setfield(L, -2, "sort");

    return 1;
}
