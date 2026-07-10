const std = @import("std");
const lua = @import("lua");

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

test "string interning shares pointer" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    _ = lua.lua_pushstring(&L, "shared");
    _ = lua.lua_pushstring(&L, "shared");
    const ta = lua.lua_topointer(&L, -2);
    const tb = lua.lua_topointer(&L, -1);
    try std.testing.expectEqual(@as(?*anyopaque, ta), tb);
}

test "table setfield/getfield" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    _ = lua.lua_pushstring(&L, "hello");
    lua.lua_setfield(&L, -2, "key");
    _ = lua.lua_getfield(&L, -1, "key");
    const s = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "hello", s);
}

test "table seti/geti and length" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    var i: i32 = 1;
    while (i <= 5) : (i += 1) {
        lua.lua_pushinteger(&L, i * 10);
        lua.lua_seti(&L, -2, i);
    }
    _ = lua.lua_geti(&L, -1, 3);
    const v = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 30), v);
    try std.testing.expectEqual(@as(usize, 5), lua.lua_rawlen(&L, -2));
}

test "empty table length is 0" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    try std.testing.expectEqual(@as(usize, 0), lua.lua_rawlen(&L, -1));
}

test "table remove entry" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    lua.lua_pushinteger(&L, 99);
    lua.lua_seti(&L, -2, 1);
    try std.testing.expectEqual(@as(usize, 1), lua.lua_rawlen(&L, -1));
    lua.lua_pushnil(&L);
    lua.lua_seti(&L, -2, 1);
    try std.testing.expectEqual(@as(usize, 0), lua.lua_rawlen(&L, -1));
}

test "table hash part stores string keys" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 4);
    _ = lua.lua_pushstring(&L, "v");
    lua.lua_setfield(&L, -2, "k");
    _ = lua.lua_pushstring(&L, "k");
    _ = lua.lua_rawget(&L, -2);
    const got = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "v", got);
}

test "table next traversal visits all entries" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    lua.lua_pushinteger(&L, 10);
    lua.lua_seti(&L, -2, 1);
    lua.lua_pushinteger(&L, 20);
    lua.lua_seti(&L, -2, 2);
    _ = lua.lua_pushstring(&L, "x");
    lua.lua_setfield(&L, -2, "a");

    lua.lua_pushnil(&L);
    var count: usize = 0;
    while (lua.lua_next(&L, -2) != 0) {
        count += 1;
        lua.lua_pop(&L, 1);
    }
    try std.testing.expectEqual(@as(usize, 3), count);
}

test "table gettable/settable with stack key" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    _ = lua.lua_pushstring(&L, "name");
    _ = lua.lua_pushstring(&L, "zig");
    lua.lua_settable(&L, -3);
    _ = lua.lua_pushstring(&L, "name");
    _ = lua.lua_gettable(&L, -2);
    const got = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "zig", got);
}
