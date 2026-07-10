/*
** $Id: mathlib.zig
** Math library for Zua (Zig port of Lua 5.5.1)
** See Copyright Notice in c_compat.zig
*/

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");

// ===================================================================
// Math library functions
// ===================================================================

pub fn openmathlib(L: *lua_State) !void {
    // Constants
    lua.lua_pushnumber(L, std.math.pi);
    lua.lua_setfield(L, -1, "pi");

    lua.lua_pushnumber(L, std.math.inf);
    lua.lua_setfield(L, -1, "huge");

    // Functions
    lua.lua_pushcfunction(L, abs);
    lua.lua_setfield(L, -1, "abs");

    lua.lua_pushcfunction(L, acos);
    lua.lua_setfield(L, -1, "acos");

    lua.lua_pushcfunction(L, asin);
    lua.lua_setfield(L, -1, "asin");

    lua.lua_pushcfunction(L, atan);
    lua.lua_setfield(L, -1, "atan");

    lua.lua_pushcfunction(L, ceil);
    lua.lua_setfield(L, -1, "ceil");

    lua.lua_pushcfunction(L, cos);
    lua.lua_setfield(L, -1, "cos");

    lua.lua_pushcfunction(L, deg);
    lua.lua_setfield(L, -1, "deg");

    lua.lua_pushcfunction(L, exp);
    lua.lua_setfield(L, -1, "exp");

    lua.lua_pushcfunction(L, floor);
    lua.lua_setfield(L, -1, "floor");

    lua.lua_pushcfunction(L, fmod);
    lua.lua_setfield(L, -1, "fmod");

    lua.lua_pushcfunction(L, frexp);
    lua.lua_setfield(L, -1, "frexp");

    lua.lua_pushcfunction(L, ldexp);
    lua.lua_setfield(L, -1, "ldexp");

    lua.lua_pushcfunction(L, log);
    lua.lua_setfield(L, -1, "log");

    lua.lua_pushcfunction(L, max);
    lua.lua_setfield(L, -1, "max");

    lua.lua_pushcfunction(L, min);
    lua.lua_setfield(L, -1, "min");

    lua.lua_pushcfunction(L, modf);
    lua.lua_setfield(L, -1, "modf");

    lua.lua_pushcfunction(L, rad);
    lua.lua_setfield(L, -1, "rad");

    lua.lua_pushcfunction(L, sin);
    lua.lua_setfield(L, -1, "sin");

    lua.lua_pushcfunction(L, sqrt);
    lua.lua_setfield(L, -1, "sqrt");

    lua.lua_pushcfunction(L, tan);
    lua.lua_setfield(L, -1, "tan");

    // random
    lua.lua_pushcfunction(L, random);
    lua.lua_setfield(L, -1, "random");

    // randomseed
    lua.lua_pushcfunction(L, randomseed);
    lua.lua_setfield(L, -1, "randomseed");
}

// ===================================================================
// Math library function implementations
// ===================================================================

fn abs(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        lua.lua_pushnumber(L, @abs(v));
        return 1;
    }
    return 0;
}

fn acos(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        lua.lua_pushnumber(L, std.math.acos(v));
        return 1;
    }
    return 0;
}

fn asin(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        lua.lua_pushnumber(L, std.math.asin(v));
        return 1;
    }
    return 0;
}

fn atan(L: *lua_State) i32 {
    if (lua.lua_gettop(L) >= 2) {
        const y = lua.lua_tonumber(L, 2);
        const x = lua.lua_tonumber(L, 1);
        if (x and y) |vx| {
            lua.lua_pushnumber(L, std.math.atan2(vx, y));
            return 1;
        }
    } else {
        const x = lua.lua_tonumber(L, 1);
        if (x) |v| {
            lua.lua_pushnumber(L, std.math.atan(v));
            return 1;
        }
    }
    return 0;
}

fn ceil(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        lua.lua_pushnumber(L, @ceil(v));
        return 1;
    }
    return 0;
}

fn cos(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        lua.lua_pushnumber(L, std.math.cos(v));
        return 1;
    }
    return 0;
}

fn deg(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        lua.lua_pushnumber(L, @as(f64, @bitCast(@as(i64, @intCast(@round(@as(f64, v) * 180.0 / std.math.pi))))));
        return 1;
    }
    return 0;
}

fn exp(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        lua.lua_pushnumber(L, std.math.exp(v));
        return 1;
    }
    return 0;
}

fn floor(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        lua.lua_pushnumber(L, @floor(v));
        return 1;
    }
    return 0;
}

fn fmod(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    const y = lua.lua_tonumber(L, 2);
    if (x and y) |vx| {
        lua.lua_pushnumber(L, @fmod(vx, y.?));
        return 1;
    }
    return 0;
}

fn frexp(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        const result = std.math.frexp(v);
        lua.lua_pushnumber(L, result.fraction);
        lua.lua_pushinteger(L, @as(i64, @bitCast(result.exponent)));
        return 2;
    }
    return 0;
}

fn ldexp(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    const n = lua.lua_tointeger(L, 2);
    if (x and n) |vx| {
        lua.lua_pushnumber(L, std.math.ldexp(vx, @as(i32, @as(i32,(n.?))));
        return 1;
    }
    return 0;
}

fn log(L: *lua_State) i32 {
    if (lua.lua_gettop(L) >= 2) {
        const base = lua.lua_tonumber(L, 2);
        const x = lua.lua_tonumber(L, 1);
        if (x and base) |vx| {
            if (base.? > 0 and base.? != 1) {
                lua.lua_pushnumber(L, std.math.log(vx) / std.math.log(base.?));
                return 1;
            }
        }
    } else {
        const x = lua.lua_tonumber(L, 1);
        if (x) |v| {
            lua.lua_pushnumber(L, std.math.log(v));
            return 1;
        }
    }
    return 0;
}

fn max(L: *lua_State) i32 {
    var result: ?f64 = null;
    var i: ?i64 = null;
    while (lua.lua_next(L, 2) != 0) {
        const n = lua.lua_tonumber(L, -1);
        if (n) |v| {
            if (result) |r| {
                result = @max(r, v);
            } else {
                result = v;
            }
        }
        lua.lua_pop(L, 1);
    }
    if (result) |v| {
        lua.lua_pushnumber(L, v);
        return 1;
    }
    return 0;
}

fn min(L: *lua_State) i32 {
    var result: ?f64 = null;
    var i: ?i64 = null;
    while (lua.lua_next(L, 2) != 0) {
        const n = lua.lua_tonumber(L, -1);
        if (n) |v| {
            if (result) |r| {
                result = @min(r, v);
            } else {
                result = v;
            }
        }
        lua.lua_pop(L, 1);
    }
    if (result) |v| {
        lua.lua_pushnumber(L, v);
        return 1;
    }
    return 0;
}

fn modf(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        const result = std.math.modf(v);
        lua.lua_pushnumber(L, result.integer);
        lua.lua_pushnumber(L, result.fraction);
        return 2;
    }
    return 0;
}

fn rad(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        lua.lua_pushnumber(L, @as(f64, @bitCast(@as(i64, @intCast(@round(@as(f64, v) * std.math.pi / 180.0))))));
        return 1;
    }
    return 0;
}

fn sin(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        lua.lua_pushnumber(L, std.math.sin(v));
        return 1;
    }
    return 0;
}

fn sqrt(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        lua.lua_pushnumber(L, std.math.sqrt(v));
        return 1;
    }
    return 0;
}

fn tan(L: *lua_State) i32 {
    const x = lua.lua_tonumber(L, 1);
    if (x) |v| {
        lua.lua_pushnumber(L, std.math.tan(v));
        return 1;
    }
    return 0;
}

fn random(L: *lua_State) i32 {
    if (lua.lua_gettop(L) == 0) {
        // math.random()
        lua.lua_pushnumber(L, std.math.random());
        return 1;
    } else if (lua.lua_gettop(L) == 1) {
        // math.random(m)
        const m = lua.lua_tointeger(L, 1);
        if (m) |val| {
            lua.lua_pushinteger(L, @as(i64, @bitCast(std.math.random(@as(i32,(val)))));
            return 1;
        }
    } else if (lua.lua_gettop(L) == 2) {
        // math.random(m, n)
        const m = lua.lua_tointeger(L, 1);
        const n = lua.lua_tointeger(L, 2);
        if (m and n) |mv| {
            lua.lua_pushinteger(L, @as(i64, @bitCast(std.math.random(@as(i32,(mv.?), @as(i32,(n.?))));
            return 1;
        }
    }
    return 0;
}

fn randomseed(L: *lua_State) i32 {
    const seed = if (lua.lua_gettop(L) >= 2) {
        const n1 = lua.lua_tointeger(L, 1);
        const n2 = lua.lua_tointeger(L, 2);
        if (n1 and n2) |v1| @as(usize, @bitCast(v1.?) + @as(usize, @bitCast(n2.?)))
        else @as(usize, @bitCast(n1.?))
    } else {
        std.time.nanos()
    };
    std.math.srand(seed);
    lua.lua_pushinteger(L, @as(i64, @bitCast(seed)));
    return 1;
}
