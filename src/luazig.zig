const std = @import("std");
const lua = @import("lua.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    _ = init.io;

    const L = try gpa.create(lua.lua_State);
    defer gpa.destroy(L);

    try lua.luaL_newstate(L, gpa);
    try lua.createargtable(L, init.minimal.args);
    try lua.luaL_openlibs(L);

    const status = try lua.luaL_dostring(L, "", "bt");

    if (status != lua.LUA_OK) {
        _ = lua.lua_tostring(L, -1);
    }

    lua.lua_close(L);
}
