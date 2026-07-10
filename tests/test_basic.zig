const std = @import("std");
const lua = @import("lua.zig");

test "nil push and type check" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_pushnil(&L);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isnil(&L, -1));
    try std.testing.expectEqual(@as(i32, lua.LUA_TNIL), lua.lua_type(&L, -1));
}

test "boolean push and type check" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_pushboolean(&L, 1);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isboolean(&L, -1));
    try std.testing.expectEqual(@as(i32, 1), lua.lua_toboolean(&L, -1));

    lua.lua_pushboolean(&L, 0);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isboolean(&L, -1));
    try std.testing.expectEqual(@as(i32, 0), lua.lua_toboolean(&L, -1));
}

test "number push and type check" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_pushnumber(&L, 3.14);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isnumber(&L, -1));
    const n = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expect(std.math.approxEqAbs(f64, n, 3.14, 0.001));
}

test "integer push and type check" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_pushinteger(&L, 42);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isnumber(&L, -1));
    const i = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 42), i);
}

test "string push and type check" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    _ = lua.lua_pushstring(&L, "hello world");
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isstring(&L, -1));
}

test "table creation and type check" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_istable(&L, -1));
}

test "stack push pop round trip" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try std.testing.expectEqual(@as(i32, 0), lua.lua_gettop(&L));

    lua.lua_pushnumber(&L, 1.0);
    lua.lua_pushnumber(&L, 2.0);
    lua.lua_pushnumber(&L, 3.0);
    try std.testing.expectEqual(@as(i32, 3), lua.lua_gettop(&L));

    lua.lua_pop(&L, 2);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(&L));

    const v = lua.lua_tonumber(&L, 1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, 1.0), v);
}
