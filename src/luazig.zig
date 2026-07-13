const std = @import("std");
const lua = @import("lua.zig");

pub fn main(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;
    const arena = init.arena.allocator();

    const args = try init.minimal.args.toSlice(arena);

    const L = try gpa.create(lua.lua_State);
    defer gpa.destroy(L);

    try lua.luaL_newstate_io(L, gpa, io);
    try lua.createargtable(L, args);
    try lua.luaL_openlibs(L);

    if (args.len >= 2) {
        // Run script file
        const filename = args[1];
        const file_content = std.Io.Dir.cwd().readFileAlloc(io, filename, gpa, .unlimited) catch |err| {
            try std.Io.File.stderr().writeStreamingAll(io, "Error: cannot open file: ");
            try std.Io.File.stderr().writeStreamingAll(io, filename);
            try std.Io.File.stderr().writeStreamingAll(io, "\n");
            return err;
        };
        defer gpa.free(file_content);

        const status = try lua.luaL_dostring(L, file_content, filename);
        if (status != lua.LUA_OK) {
            if (lua.lua_tostring(L, -1)) |msg| {
                try std.Io.File.stderr().writeStreamingAll(io, msg);
                try std.Io.File.stderr().writeStreamingAll(io, "\n");
            }
        }
    } else {
        // Interactive REPL mode
        var buffer: [4096]u8 = undefined;
        try std.Io.File.stdout().writeStreamingAll(io, "Lua.Zig 5.5.1  Copyright (C) 1994-2026 Lua.org, PUC-Rio\n");
        while (true) {
            try std.Io.File.stdout().writeStreamingAll(io, "> ");
            const bytes_read = std.Io.File.stdin().readStreaming(io, &.{&buffer}) catch |err| {
                if (err == error.EndOfStream) break;
                return err;
            };
            if (bytes_read == 0) break;
            const line = std.mem.trimEnd(u8, buffer[0..bytes_read], "\r\n");
            if (line.len == 0) continue;
            if (std.mem.eql(u8, line, "exit")) break;

            const status = try lua.luaL_dostring(L, line, "=stdin");
            if (status != lua.LUA_OK) {
                if (lua.lua_tostring(L, -1)) |msg| {
                    try std.Io.File.stderr().writeStreamingAll(io, msg);
                    try std.Io.File.stderr().writeStreamingAll(io, "\n");
                }
            } else {
                const top = lua.lua_gettop(L);
                if (top > 0) {
                    var i: i32 = 1;
                    while (i <= top) : (i += 1) {
                        if (lua.lua_tostring(L, i)) |s| {
                            try std.Io.File.stdout().writeStreamingAll(io, s);
                        } else {
                            const name = lua.lua_typename(lua.lua_type(L, i));
                            try std.Io.File.stdout().writeStreamingAll(io, name);
                        }
                        if (i < top) try std.Io.File.stdout().writeStreamingAll(io, "\t");
                    }
                    try std.Io.File.stdout().writeStreamingAll(io, "\n");
                    lua.lua_settop(L, 0); // clear stack
                }
            }
        }
    }

    lua.lua_close(L);
}
