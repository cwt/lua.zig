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
        if (lua.lua_tostring(L, -1)) |msg| {
            try std.Io.File.stderr().writeStreamingAll(init.io, msg);
            try std.Io.File.stderr().writeStreamingAll(init.io, "\n");
        }
    }

    lua.lua_close(L);
}
