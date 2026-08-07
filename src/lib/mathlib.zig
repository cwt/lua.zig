const std = @import("std");
const lua = @import("../lua.zig");
const lauxlib = @import("../lauxlib.zig");
const libm = @import("../libm.zig");

// ===================================================================
// Math library functions
// ===================================================================

fn pushNumInt(L: *lua.lua_State, d: lua.lua_Number) void {
    const min_f64 = @as(f64, -9223372036854775808.0);
    const max_exclusive_f64 = @as(f64, 9223372036854775808.0);
    if (@trunc(d) == d and d >= min_f64 and d < max_exclusive_f64) {
        lua.lua_pushinteger(L, @as(i64, @intFromFloat(d)));
    } else {
        lua.lua_pushnumber(L, d);
    }
}

fn math_abs(L: *lua.lua_State) !i32 {
    if (lua.lua_isinteger(L, 1) != 0) {
        const n = try lauxlib.luaL_checkinteger(L, 1);
        if (n < 0) {
            const un = @as(lua.lua_Unsigned, @bitCast(n));
            lua.lua_pushinteger(L, @as(i64, @bitCast(@as(u64, 0) -% un)));
        } else {
            lua.lua_pushinteger(L, n);
        }
    } else {
        lua.lua_pushnumber(L, @abs(try lauxlib.luaL_checknumber(L, 1)));
    }
    return 1;
}

fn math_sin(L: *lua.lua_State) !i32 {
    const m = libm.getLibm();
    lua.lua_pushnumber(L, m.sin(try lauxlib.luaL_checknumber(L, 1)));
    return 1;
}

fn math_cos(L: *lua.lua_State) !i32 {
    const m = libm.getLibm();
    lua.lua_pushnumber(L, m.cos(try lauxlib.luaL_checknumber(L, 1)));
    return 1;
}

fn math_tan(L: *lua.lua_State) !i32 {
    const m = libm.getLibm();
    lua.lua_pushnumber(L, m.tan(try lauxlib.luaL_checknumber(L, 1)));
    return 1;
}

fn math_asin(L: *lua.lua_State) !i32 {
    const m = libm.getLibm();
    lua.lua_pushnumber(L, m.asin(try lauxlib.luaL_checknumber(L, 1)));
    return 1;
}

fn math_acos(L: *lua.lua_State) !i32 {
    const m = libm.getLibm();
    lua.lua_pushnumber(L, m.acos(try lauxlib.luaL_checknumber(L, 1)));
    return 1;
}

fn math_atan(L: *lua.lua_State) !i32 {
    const m = libm.getLibm();
    const y = try lauxlib.luaL_checknumber(L, 1);
    const x = lauxlib.luaL_optnumber(L, 2, 1.0);
    lua.lua_pushnumber(L, m.atan2(y, x));
    return 1;
}

fn math_toint(L: *lua.lua_State) !i32 {
    var isnum: i32 = 0;
    const n = lua.lua_tointegerx(L, 1, &isnum);
    if (isnum != 0) {
        lua.lua_pushinteger(L, n.?);
    } else {
        try lauxlib.luaL_checkany(L, 1);
        lauxlib.luaL_pushfail(L);
    }
    return 1;
}

fn math_floor(L: *lua.lua_State) !i32 {
    if (lua.lua_isinteger(L, 1) != 0) {
        lua.lua_settop(L, 1);
    } else {
        const d = @floor(try lauxlib.luaL_checknumber(L, 1));
        pushNumInt(L, d);
    }
    return 1;
}

fn math_ceil(L: *lua.lua_State) !i32 {
    if (lua.lua_isinteger(L, 1) != 0) {
        lua.lua_settop(L, 1);
    } else {
        const d = @ceil(try lauxlib.luaL_checknumber(L, 1));
        pushNumInt(L, d);
    }
    return 1;
}

fn math_fmod(L: *lua.lua_State) !i32 {
    const m = libm.getLibm();
    if (lua.lua_isinteger(L, 1) != 0 and lua.lua_isinteger(L, 2) != 0) {
        const d = try lauxlib.luaL_checkinteger(L, 2);
        try lauxlib.luaL_argcheck(L, d != 0, 2, "zero");
        if ((@as(lua.lua_Unsigned, @bitCast(d)) +% 1) <= 1) {
            lua.lua_pushinteger(L, 0);
        } else {
            lua.lua_pushinteger(L, @rem(try lauxlib.luaL_checkinteger(L, 1), d));
        }
    } else {
        lua.lua_pushnumber(L, m.fmod(try lauxlib.luaL_checknumber(L, 1), try lauxlib.luaL_checknumber(L, 2)));
    }
    return 1;
}

fn math_modf(L: *lua.lua_State) !i32 {
    if (lua.lua_isinteger(L, 1) != 0) {
        lua.lua_settop(L, 1);
        lua.lua_pushnumber(L, 0.0);
    } else {
        const n = try lauxlib.luaL_checknumber(L, 1);
        const ip = if (n < 0) @ceil(n) else @floor(n);
        pushNumInt(L, ip);
        lua.lua_pushnumber(L, if (n == ip) 0.0 else n - ip);
    }
    return 2;
}

fn math_sqrt(L: *lua.lua_State) !i32 {
    lua.lua_pushnumber(L, @sqrt(try lauxlib.luaL_checknumber(L, 1)));
    return 1;
}

fn math_ult(L: *lua.lua_State) !i32 {
    const a = try lauxlib.luaL_checkinteger(L, 1);
    const b = try lauxlib.luaL_checkinteger(L, 2);
    lua.lua_pushboolean(L, if (@as(lua.lua_Unsigned, @bitCast(a)) < @as(lua.lua_Unsigned, @bitCast(b))) 1 else 0);
    return 1;
}

fn math_log(L: *lua.lua_State) !i32 {
    const m = libm.getLibm();
    const x = try lauxlib.luaL_checknumber(L, 1);
    const res: f64 = if (lua.lua_isnoneornil(L, 2)) m.log(x) else blk: {
        const base = try lauxlib.luaL_checknumber(L, 2);
        break :blk if (base == 2.0) m.log2(x) else if (base == 10.0) m.log10(x) else m.log(x) / m.log(base);
    };
    lua.lua_pushnumber(L, res);
    return 1;
}

fn math_exp(L: *lua.lua_State) !i32 {
    const m = libm.getLibm();
    lua.lua_pushnumber(L, m.exp(try lauxlib.luaL_checknumber(L, 1)));
    return 1;
}

fn math_pow(L: *lua.lua_State) !i32 {
    const m = libm.getLibm();
    const x = try lauxlib.luaL_checknumber(L, 1);
    const y = try lauxlib.luaL_checknumber(L, 2);
    lua.lua_pushnumber(L, m.pow(x, y));
    return 1;
}

fn math_deg(L: *lua.lua_State) !i32 {
    lua.lua_pushnumber(L, try lauxlib.luaL_checknumber(L, 1) * (180.0 / std.math.pi));
    return 1;
}

fn math_rad(L: *lua.lua_State) !i32 {
    lua.lua_pushnumber(L, try lauxlib.luaL_checknumber(L, 1) * (std.math.pi / 180.0));
    return 1;
}

fn math_frexp(L: *lua.lua_State) !i32 {
    const m = libm.getLibm();
    const x = try lauxlib.luaL_checknumber(L, 1);
    var exp: i32 = 0;
    const sig = m.frexp(x, &exp);
    lua.lua_pushnumber(L, sig);
    lua.lua_pushinteger(L, exp);
    return 2;
}

fn math_ldexp(L: *lua.lua_State) !i32 {
    const m = libm.getLibm();
    const x = try lauxlib.luaL_checknumber(L, 1);
    const ep = try lauxlib.luaL_checkinteger(L, 2);
    lua.lua_pushnumber(L, m.ldexp(x, @as(i32, @intCast(ep))));
    return 1;
}

fn math_min(L: *lua.lua_State) !i32 {
    const n = lua.lua_gettop(L);
    try lauxlib.luaL_argcheck(L, n >= 1, 1, "value expected");
    var imin: i32 = 1;
    var i: i32 = 2;
    while (i <= n) : (i += 1) {
        if (lua.lua_compare(L, i, imin, lua.LUA_OPLT) != 0) {
            imin = i;
        }
    }
    lua.lua_pushvalue(L, imin);
    return 1;
}

fn math_max(L: *lua.lua_State) !i32 {
    const n = lua.lua_gettop(L);
    try lauxlib.luaL_argcheck(L, n >= 1, 1, "value expected");
    var imax: i32 = 1;
    var i: i32 = 2;
    while (i <= n) : (i += 1) {
        if (lua.lua_compare(L, imax, i, lua.LUA_OPLT) != 0) {
            imax = i;
        }
    }
    lua.lua_pushvalue(L, imax);
    return 1;
}

fn math_type(L: *lua.lua_State) !i32 {
    if (lua.lua_type(L, 1) == lua.LUA_TNUMBER) {
        if (lua.lua_isinteger(L, 1) != 0) {
            _ = lua.lua_pushstring(L, "integer");
        } else {
            _ = lua.lua_pushstring(L, "float");
        }
    } else {
        try lauxlib.luaL_checkany(L, 1);
        lauxlib.luaL_pushfail(L);
    }
    return 1;
}

fn rotl(x: u64, n: i32) u64 {
    const un = @as(u6, @intCast(n));
    return (x << un) | (x >> @as(u6, @intCast(64 - n)));
}

fn nextrand(state: *[4]u64) u64 {
    const state0 = state[0];
    const state1 = state[1];
    const state2 = state[2] ^ state0;
    const state3 = state[3] ^ state1;
    const res = rotl(state1 *% 5, 7) *% 9;
    state[0] = state0 ^ state3;
    state[1] = state1 ^ state2;
    state[2] = state2 ^ (state1 << 17);
    state[3] = rotl(state3, 45);
    return res;
}

fn I2d(x: u64) f64 {
    const FIGS = 53;
    const shift64_FIG = 64 - FIGS;
    const scaleFIG = 1.0 / 9007199254740992.0;
    const sx = @as(i64, @bitCast(x >> shift64_FIG));
    var res = @as(f64, @floatFromInt(sx)) * scaleFIG;
    if (sx < 0) {
        res += 1.0;
    }
    return res;
}

fn setseed(state: *[4]u64, n1: u64, n2: u64) void {
    state[0] = n1;
    state[1] = 0xff;
    state[2] = n2;
    state[3] = 0;
    var i: i32 = 0;
    while (i < 16) : (i += 1) {
        _ = nextrand(state);
    }
}

fn project(ran: u64, n: u64, state: *[4]u64) u64 {
    var r = ran;
    var lim = n;
    var sh: u32 = 1;
    while ((lim & (lim +% 1)) != 0) {
        lim |= (lim >> @as(u6, @intCast(sh)));
        sh *= 2;
    }
    r &= lim;
    while (r > n) {
        r = nextrand(state) & lim;
    }
    return r;
}

fn math_random(L: *lua.lua_State) !i32 {
    const g = L.l_G.?;
    const state = &g.prng_state;
    const rv = nextrand(state);
    const nargs = lua.lua_gettop(L);
    if (nargs == 0) {
        lua.lua_pushnumber(L, I2d(rv));
        return 1;
    } else if (nargs == 1) {
        const up = try lauxlib.luaL_checkinteger(L, 1);
        if (up == 0) {
            lua.lua_pushinteger(L, @as(i64, @bitCast(rv)));
            return 1;
        }
        const p = project(rv, @as(u64, @bitCast(up -% 1)), state);
        lua.lua_pushinteger(L, @as(i64, @bitCast(p)) + 1);
        return 1;
    } else if (nargs == 2) {
        const low = try lauxlib.luaL_checkinteger(L, 1);
        const up = try lauxlib.luaL_checkinteger(L, 2);
        try lauxlib.luaL_argcheck(L, low <= up, 1, "interval is empty");
        const p = project(rv, @as(u64, @bitCast(up -% low)), state);
        lua.lua_pushinteger(L, @as(i64, @bitCast(p +% @as(u64, @bitCast(low)))));
        return 1;
    } else {
        return lauxlib.luaL_error(L, "wrong number of arguments");
    }
}

fn math_randomseed(L: *lua.lua_State) !i32 {
    const g = L.l_G.?;
    const io = g.io;
    const state = &g.prng_state;
    var n1: lua.lua_Unsigned = 0;
    var n2: lua.lua_Unsigned = 0;
    if (lua.lua_type(L, 1) == lua.LUA_TNONE) {
        n1 = @as(u64, @intCast(std.Io.Timestamp.now(io, .real).nanoseconds));
        n2 = nextrand(state);
    } else {
        n1 = @as(lua.lua_Unsigned, @bitCast(try lauxlib.luaL_checkinteger(L, 1)));
        n2 = @as(lua.lua_Unsigned, @bitCast(lauxlib.luaL_optinteger(L, 2, 0)));
    }
    setseed(state, n1, n2);
    lua.lua_pushinteger(L, @as(i64, @bitCast(n1)));
    lua.lua_pushinteger(L, @as(i64, @bitCast(n2)));
    return 2;
}

// ===================================================================
// Library registration
// ===================================================================

pub fn openmathlib(L: *lua.lua_State) !void {
    lua.lua_createtable(L, 0, 25);

    for ([_]struct { name: []const u8, func: lua.lua_CFunction }{
        .{ .name = "abs", .func = math_abs },
        .{ .name = "acos", .func = math_acos },
        .{ .name = "asin", .func = math_asin },
        .{ .name = "atan", .func = math_atan },
        .{ .name = "ceil", .func = math_ceil },
        .{ .name = "cos", .func = math_cos },
        .{ .name = "deg", .func = math_deg },
        .{ .name = "exp", .func = math_exp },
        .{ .name = "floor", .func = math_floor },
        .{ .name = "fmod", .func = math_fmod },
        .{ .name = "frexp", .func = math_frexp },
        .{ .name = "ldexp", .func = math_ldexp },
        .{ .name = "log", .func = math_log },
        .{ .name = "max", .func = math_max },
        .{ .name = "min", .func = math_min },
        .{ .name = "modf", .func = math_modf },
        .{ .name = "pow", .func = math_pow },
        .{ .name = "rad", .func = math_rad },
        .{ .name = "sin", .func = math_sin },
        .{ .name = "sqrt", .func = math_sqrt },
        .{ .name = "tan", .func = math_tan },
        .{ .name = "tointeger", .func = math_toint },
        .{ .name = "type", .func = math_type },
        .{ .name = "ult", .func = math_ult },
        .{ .name = "random", .func = math_random },
        .{ .name = "randomseed", .func = math_randomseed },
    }) |reg| {
        lua.lua_pushcfunction(L, reg.func);
        try lua.lua_setfield(L, -2, reg.name);
    }

    lua.lua_pushnumber(L, std.math.pi);
    try lua.lua_setfield(L, -2, "pi");
    lua.lua_pushnumber(L, std.math.inf(f64));
    try lua.lua_setfield(L, -2, "huge");
    lua.lua_pushinteger(L, lua.LUA_MAXINTEGER);
    try lua.lua_setfield(L, -2, "maxinteger");
    lua.lua_pushinteger(L, lua.LUA_MININTEGER);
    try lua.lua_setfield(L, -2, "mininteger");

    try lua.lua_setglobal(L, "math");
}
