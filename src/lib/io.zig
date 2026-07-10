/*
** $Id: io.zig
** IO library for Zua (Zig port of Lua 5.5.1)
** See Copyright Notice in c_compat.zig
*/

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");

// ===================================================================
// IO library functions
// ===================================================================

pub fn openio(L: *lua_State) !void {
    // io.close(file)
    lua.lua_pushcfunction(L, close);
    lua.lua_setfield(L, -1, "close");

    // io.flush(file)
    lua.lua_pushcfunction(L, flush);
    lua.lua_setfield(L, -1, "flush");

    // io.input(file)
    lua.lua_pushcfunction(L, input);
    lua.lua_setfield(L, -1, "input");

    // io.lines([file [, vararg]])
    lua.lua_pushcfunction(L, lines);
    lua.lua_setfield(L, -1, "lines");

    // io.open(filename, mode)
    lua.lua_pushcfunction(L, open);
    lua.lua_setfield(L, -1, "open");

    // io.output(file)
    lua.lua_pushcfunction(L, output);
    lua.lua_setfield(L, -1, "output");

    // io.popen(cmd, mode)
    lua.lua_pushcfunction(L, popen);
    lua.lua_setfield(L, -1, "popen");

    // io.read(format [, vararg])
    lua.lua_pushcfunction(L, read);
    lua.lua_setfield(L, -1, "read");

    // io.tmpfile()
    lua.lua_pushcfunction(L, tmpfile);
    lua.lua_setfield(L, -1, "tmpfile");

    // io.type(v)
    lua.lua_pushcfunction(L, iotype);
    lua.lua_setfield(L, -1, "type");

    // io.write(vararg)
    lua.lua_pushcfunction(L, write);
    lua.lua_setfield(L, -1, "write");
}

// ===================================================================
// IO library function implementations
// ===================================================================

fn close(L: *lua_State) i32 {
    const file = luaL_checklstring(L, 1, null);
    if (file) |f| {
        // Would close file
    }
    return 0;
}

fn flush(L: *lua_State) i32 {
    const file = luaL_checklstring(L, 1, null);
    if (file) |f| {
        // Would flush file
    }
    return 0;
}

fn input(L: *lua_State) i32 {
    const file = luaL_checklstring(L, 1, null);
    if (file) |f| {
        // Would set/get input file
    }
    return 0;
}

fn lines(L: *lua_State) i32 {
    const file = luaL_checklstring(L, 1, null);
    if (file) |f| {
        // Would iterate over lines
    }
    return 0;
}

fn open(L: *lua_State) i32 {
    const filename = luaL_checklstring(L, 1, null);
    const mode = luaL_checklstring(L, 2, null);
    if (filename and mode) |f| {
        // Would open file
        const file = std.fs.cwd().createFile(f, .{}) catch null;
        if (file) |f_ptr| {
            lua.lua_pushlightuserdata(L, @ptrCast(f_ptr));
            return 1;
        }
    }
    return 0;
}

fn output(L: *lua_State) i32 {
    const file = luaL_checklstring(L, 1, null);
    if (file) |f| {
        // Would set/get output file
    }
    return 0;
}

fn popen(L: *lua_State) i32 {
    const cmd = luaL_checklstring(L, 1, null);
    const mode = luaL_checklstring(L, 2, null);
    if (cmd and mode) |c| {
        // Would open pipe
    }
    return 0;
}

fn read(L: *lua_State) i32 {
    const format = luaL_checklstring(L, 1, null);
    if (format) |f| {
        // Would read from input
    }
    return 0;
}

fn tmpfile(L: *lua_State) i32 {
    // Would create temporary file
    const tmp = std.fs.getCwd().createTempFile("lua_tmp", ".tmp") catch |e| {
        lua.lua_pushnil(L);
        return 0;
    };
    if (tmp) |t| {
        lua.lua_pushlightuserdata(L, @ptrCast(t));
        return 1;
    }
    return 0;
}

fn iotype(L: *lua_State) i32 {
    const v = luaL_checklstring(L, 1, null);
    if (v) |val| {
        // Would check if value is file
        lua.lua_pushstring(L, "file");
        return 1;
    }
    lua.lua_pushnil(L);
    return 0;
}

fn write(L: *lua_State) i32 {
    const file = luaL_checklstring(L, 1, null);
    if (file) |f| {
        // Would write to output
        while (lua.lua_next(L, 2) != 0) {
            const val = lua.lua_tolstring(L, -1, null);
            if (val) |v| {
                std.fs.cwd().writeFile(f, v) catch {};
            }
            lua.lua_pop(L, 1);
        }
    }
    return 0;
}
