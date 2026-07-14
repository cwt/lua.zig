//
// ** $Id: baselib.zig
// ** Base library for Zua (Zig port of Lua 5.5.1)
// ** See Copyright Notice in c_compat.zig
//

const std = @import("std");
const lua = @import("../lua.zig");
const lprefix = @import("../lprefix.zig");
const llimits = @import("../llimits.zig");
const lauxlib = @import("../lauxlib.zig");

// ===================================================================
// Base library functions
// ===================================================================

pub fn openbaselib(L: *lua.lua_State) !void {
    // Register base library functions in _G table

    // assert(cond [, message])
    lua.lua_pushcfunction(L, assert);
    lua.lua_setglobal(L, "assert");

    // collectgarbage(option [, vararg])
    lua.lua_pushcfunction(L, collectgarbage);
    lua.lua_setglobal(L, "collectgarbage");

    // dofile(filename)
    lua.lua_pushcfunction(L, dofile);
    lua.lua_setglobal(L, "dofile");

    // error(message [, level])
    lua.lua_pushcfunction(L, error_fn);
    lua.lua_setglobal(L, "error");

    // getmetatable(object)
    lua.lua_pushcfunction(L, getmetatable);
    lua.lua_setglobal(L, "getmetatable");

    // ipairs(table)
    lua.lua_pushcfunction(L, ipairs);
    lua.lua_setglobal(L, "ipairs");

    // loadfile(filename [, mode])
    lua.lua_pushcfunction(L, loadfile);
    lua.lua_setglobal(L, "loadfile");

    // load(file [, chunkname [, mode [, env]]])
    lua.lua_pushcfunction(L, load);
    lua.lua_setglobal(L, "load");

    // next(table [, index])
    lua.lua_pushcfunction(L, next_fn);
    lua.lua_setglobal(L, "next");

    // pairs(table)
    lua.lua_pushcfunction(L, pairs);
    lua.lua_setglobal(L, "pairs");

    // pcall(function, vararg)
    lua.lua_pushcfunction(L, pcall);
    lua.lua_setglobal(L, "pcall");

    // print(vararg)
    lua.lua_pushcfunction(L, print);
    lua.lua_setglobal(L, "print");

    // warn(vararg)
    lua.lua_pushcfunction(L, warn);
    lua.lua_setglobal(L, "warn");

    // rawequal(x, y)
    lua.lua_pushcfunction(L, rawequal);
    lua.lua_setglobal(L, "rawequal");

    // rawlen(v)
    lua.lua_pushcfunction(L, rawlen);
    lua.lua_setglobal(L, "rawlen");

    // rawget(table, key)
    lua.lua_pushcfunction(L, rawget);
    lua.lua_setglobal(L, "rawget");

    // rawset(table, key, value)
    lua.lua_pushcfunction(L, rawset);
    lua.lua_setglobal(L, "rawset");

    // select(index_or_# [, vararg])
    lua.lua_pushcfunction(L, select);
    lua.lua_setglobal(L, "select");

    // setmetatable(table, metatable)
    lua.lua_pushcfunction(L, setmetatable);
    lua.lua_setglobal(L, "setmetatable");

    // tonumber(v [, base])
    lua.lua_pushcfunction(L, tonumber);
    lua.lua_setglobal(L, "tonumber");

    // tostring(v)
    lua.lua_pushcfunction(L, tostring);
    lua.lua_setglobal(L, "tostring");

    // type(v)
    lua.lua_pushcfunction(L, type_fn);
    lua.lua_setglobal(L, "type");

    // xpcall(function, errfunc, vararg)
    lua.lua_pushcfunction(L, xpcall);
    lua.lua_setglobal(L, "xpcall");
}

// ===================================================================
// Helper reader for slice loading
// ===================================================================

fn sliceReader(L: *lua.lua_State, dt: ?*anyopaque, size: ?*usize) ?[]const u8 {
    _ = L;
    const slice_ptr = @as(?*[]const u8, @ptrCast(@alignCast(dt))) orelse return null;
    if (slice_ptr.*.len == 0) {
        if (size) |s| s.* = 0;
        return null;
    }
    const chunk = slice_ptr.*;
    slice_ptr.* = &[_]u8{}; // empty it so next read returns 0
    if (size) |s| s.* = chunk.len;
    return chunk;
}

// ===================================================================
// Base library function implementations
// ===================================================================

fn assert(L: *lua.lua_State) anyerror!i32 {
    if (lua.lua_toboolean(L, 1) != 0) {
        return lua.lua_gettop(L);
    }
    try lauxlib.luaL_checkany(L, 1);
    lua.lua_remove(L, 1);
    if (lua.lua_gettop(L) == 0) {
        _ = lua.lua_pushstring(L, "assertion failed!");
    }
    lua.lua_settop(L, 1);
    return error_fn(L);
}

fn collectgarbage(L: *lua.lua_State) anyerror!i32 {
    var opts_arr = [_][]const u8{ "stop", "restart", "collect", "count", "step", "isrunning", "generational", "incremental", "param" };
    const optsnum = [_]i32{ lua.LUA_GCSTOP, lua.LUA_GCRESTART, lua.LUA_GCCOLLECT, lua.LUA_GCCOUNT, lua.LUA_GCSTEP, lua.LUA_GCISRUNNING, lua.LUA_GCGEN, lua.LUA_GCINC, lua.LUA_GCPARAM };
    const o = try lauxlib.luaL_checkoption(L, 1, "collect", &opts_arr);
    const which = optsnum[@as(usize, @intCast(o))];
    switch (which) {
        lua.LUA_GCPARAM => {
            var param_arr = [_][]const u8{ "minormul", "majorminor", "minormajor", "pause", "stepmul", "stepsize" };
            const param_num = [_]i32{ lua.LUA_GCPMINORMUL, lua.LUA_GCPMAJORMINOR, lua.LUA_GCPMINORMAJOR, lua.LUA_GCPPAUSE, lua.LUA_GCPSTEPMUL, lua.LUA_GCPSTEPSIZE };
            const p = try lauxlib.luaL_checkoption(L, 2, null, &param_arr);
            const value = lauxlib.luaL_optinteger(L, 3, -1);
            const res = lua.lua_gc(L, lua.LUA_GCPARAM, param_num[@as(usize, @intCast(p))], @as(i32, @intCast(value)));
            lua.lua_pushinteger(L, res);
            return 1;
        },
        lua.LUA_GCCOUNT => {
            const k = lua.lua_gc(L, which, 0, 0);
            const b = lua.lua_gc(L, lua.LUA_GCCOUNTB, 0, 0);
            lua.lua_pushnumber(L, @as(f64, @floatFromInt(k)) + (@as(f64, @floatFromInt(b)) / 1024.0));
            return 1;
        },
        lua.LUA_GCSTEP, lua.LUA_GCISRUNNING => {
            const res = lua.lua_gc(L, which, @as(i32, @intCast(lauxlib.luaL_optinteger(L, 2, 0))), 0);
            lua.lua_pushboolean(L, if (res != 0) 1 else 0);
            return 1;
        },
        else => {
            const ex = @as(i32, @intCast(lauxlib.luaL_optinteger(L, 2, 0)));
            const res = lua.lua_gc(L, which, ex, 0);
            lua.lua_pushinteger(L, res);
            return 1;
        },
    }
}

fn dofile(L: *lua.lua_State) anyerror!i32 {
    const filename = try lauxlib.luaL_checklstring(L, 1, null);
    lua.lua_settop(L, 1);
    
    const io = L.l_G.?.io;
    const contents = std.Io.Dir.cwd().readFileAlloc(io, filename, L.allocator, .unlimited) catch |err| {
        const msg = if (err == error.FileNotFound) "cannot open file: No such file or directory" else "error reading file";
        _ = lua.lua_pushstring(L, msg);
        return lua.lua_error(L);
    };
    defer L.allocator.free(contents);

    var slice_data = contents;
    const status = lua.lua_load(L, sliceReader, @as(?*anyopaque, @ptrCast(&slice_data)), filename, "bt");
    if (status != lua.LUA_OK) {
        return lua.lua_error(L);
    }
    
    try lua.lua_call(L, 0, lua.LUA_MULTRET);
    return @as(i32, @intCast(lua.lua_gettop(L) - 1));
}

fn error_fn(L: *lua.lua_State) anyerror!i32 {
    lua.lua_settop(L, 1);
    return lua.lua_error(L);
}

fn getmetatable(L: *lua.lua_State) anyerror!i32 {
    try lauxlib.luaL_checkany(L, 1);
    if (lua.lua_getmetatable(L, 1) == 0) {
        lua.lua_pushnil(L);
        return 1;
    }
    _ = lauxlib.luaL_getmetafield(L, 1, "__metatable");
    return 1;
}

fn ipairsaux(L: *lua.lua_State) anyerror!i32 {
    const i = (try lauxlib.luaL_checkinteger(L, 2)) + 1;
    lua.lua_pushinteger(L, i);
    return if (try lua.lua_geti(L, 1, i) == lua.LUA_TNIL) 1 else 2;
}

fn ipairs(L: *lua.lua_State) anyerror!i32 {
    try lauxlib.luaL_checkany(L, 1);
    lua.lua_pushcfunction(L, ipairsaux);
    lua.lua_pushvalue(L, 1);
    lua.lua_pushinteger(L, 0);
    return 3;
}

fn loadfile(L: *lua.lua_State) anyerror!i32 {
    const filename = try lauxlib.luaL_checklstring(L, 1, null);
    const mode = try lauxlib.luaL_optlstring(L, 2, "bt", null) orelse "bt";

    const io = L.l_G.?.io;
    const contents = std.Io.Dir.cwd().readFileAlloc(io, filename, L.allocator, .unlimited) catch |err| {
        lua.lua_pushnil(L);
        const msg = if (err == error.FileNotFound) "cannot open file: No such file or directory" else "error reading file";
        _ = lua.lua_pushstring(L, msg);
        return 2;
    };
    defer L.allocator.free(contents);

    var slice_data = contents;
    const status = lua.lua_load(L, sliceReader, @as(?*anyopaque, @ptrCast(&slice_data)), filename, mode);
    if (status == lua.LUA_OK) {
        return 1;
    } else {
        lua.lua_pushnil(L);
        lua.lua_insert(L, -2);
        return 2;
    }
}

fn load(L: *lua.lua_State) anyerror!i32 {
    const chunk = try lauxlib.luaL_checklstring(L, 1, null);
    const chunkname = try lauxlib.luaL_optlstring(L, 2, "=(load)", null) orelse "=(load)";
    const mode = try lauxlib.luaL_optlstring(L, 3, "bt", null) orelse "bt";

    var slice_data = chunk;
    const status = lua.lua_load(L, sliceReader, @as(?*anyopaque, @ptrCast(&slice_data)), chunkname, mode);
    if (status == lua.LUA_OK) {
        return 1;
    } else {
        lua.lua_pushnil(L);
        lua.lua_insert(L, -2);
        return 2;
    }
}

fn next_fn(L: *lua.lua_State) anyerror!i32 {
    try lauxlib.luaL_checkany(L, 1);
    if (lua.lua_istable(L, 1) == 0) {
        _ = lua.lua_pushstring(L, "table expected");
        return lua.lua_error(L);
    }
    lua.lua_settop(L, 2);
    if (lua.lua_next(L, 1) != 0) {
        return 2;
    }
    lua.lua_pushnil(L);
    return 1;
}

fn pairs(L: *lua.lua_State) anyerror!i32 {
    try lauxlib.luaL_checkany(L, 1);
    if (lauxlib.luaL_getmetafield(L, 1, "__pairs") == lua.LUA_TNIL) {
        lua.lua_pushcfunction(L, next_fn);
        lua.lua_pushvalue(L, 1);
        lua.lua_pushnil(L);
    } else {
        lua.lua_pushvalue(L, 1);
        try lua.lua_call(L, 1, 3);
    }
    return 3;
}

fn pcall(L: *lua.lua_State) anyerror!i32 {
    try lauxlib.luaL_checkany(L, 1);
    const status = lua.lua_pcallk(L, lua.lua_gettop(L) - 1, lua.LUA_MULTRET, 0, 0, null);
    lua.lua_pushboolean(L, if (status == lua.LUA_OK) @as(i32, 1) else @as(i32, 0));
    lua.lua_insert(L, 1);
    return lua.lua_gettop(L);
}

fn print(L: *lua.lua_State) anyerror!i32 {
    const n = lua.lua_gettop(L);
    const io = L.l_G.?.io;
    try lauxlib.luaL_checkstack(L, 1, "no extra stack slots");
    _ = lua.lua_getglobal(L, "tostring");
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        lua.lua_pushvalue(L, -1);
        lua.lua_pushvalue(L, i);
        try lua.lua_call(L, 1, 1);
        var len: usize = 0;
        const s = lua.lua_tolstring(L, -1, &len);
        if (i > 1) {
            try std.Io.File.stdout().writeStreamingAll(io, "\t");
        }
        if (s) |str| {
            try std.Io.File.stdout().writeStreamingAll(io, str);
        }
        lua.lua_pop(L, 1);
    }
    lua.lua_pop(L, 1);
    try std.Io.File.stdout().writeStreamingAll(io, "\n");
    return 0;
}

fn warn(L: *lua.lua_State) anyerror!i32 {
    const n = lua.lua_gettop(L);
    const io = L.l_G.?.io;
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        var len: usize = 0;
        const s = lauxlib.luaL_tolstring(L, i, &len);
        if (s) |str| {
            try std.Io.File.stderr().writeStreamingAll(io, str);
        }
        lua.lua_pop(L, 1);
    }
    try std.Io.File.stderr().writeStreamingAll(io, "\n");
    return 0;
}

fn rawequal(L: *lua.lua_State) anyerror!i32 {
    try lauxlib.luaL_checkany(L, 1);
    try lauxlib.luaL_checkany(L, 2);
    const result = lua.lua_rawequal(L, 1, 2);
    lua.lua_pushboolean(L, result);
    return 1;
}

fn rawlen(L: *lua.lua_State) anyerror!i32 {
    const t = lua.lua_type(L, 1);
    if (t != lua.LUA_TTABLE and t != lua.LUA_TSTRING) {
        return lauxlib.luaL_typeerror(L, 1, "table or string");
    }
    const len = lua.lua_rawlen(L, 1);
    lua.lua_pushinteger(L, @as(i64, @intCast(len)));
    return 1;
}

fn rawget(L: *lua.lua_State) anyerror!i32 {
    try lauxlib.luaL_checktype(L, 1, lua.LUA_TTABLE);
    lua.lua_settop(L, 2);
    _ = lua.lua_rawget(L, 1);
    return 1;
}

fn rawset(L: *lua.lua_State) anyerror!i32 {
    try lauxlib.luaL_checktype(L, 1, lua.LUA_TTABLE);
    try lauxlib.luaL_checkany(L, 2);
    try lauxlib.luaL_checkany(L, 3);
    lua.lua_settop(L, 3);
    lua.lua_rawset(L, 1);
    return 1;
}

fn select(L: *lua.lua_State) anyerror!i32 {
    const n = lua.lua_gettop(L);
    if (lua.lua_type(L, 1) == lua.LUA_TSTRING) {
        const s = lua.lua_tostring(L, 1);
        if (s != null and s.?.len > 0 and s.?[0] == '#') {
            lua.lua_pushinteger(L, @as(i64, @intCast(n - 1)));
            return 1;
        }
    }
    const idx = try lauxlib.luaL_checkinteger(L, 1);
    var i: i32 = @intCast(idx);
    if (i < 0) {
        i = n + i;
    } else if (i > n) {
        i = n;
    }
    if (i < 1) {
        return lauxlib.luaL_error(L, "index out of range");
    }
    return n - i;
}

fn setmetatable(L: *lua.lua_State) anyerror!i32 {
    const t = lua.lua_type(L, 2);
    try lauxlib.luaL_checktype(L, 1, lua.LUA_TTABLE);
    if (t != lua.LUA_TNIL and t != lua.LUA_TTABLE) {
        return lauxlib.luaL_typeerror(L, 2, "nil or table");
    }
    if (lauxlib.luaL_getmetafield(L, 1, "__metatable") != lua.LUA_TNIL) {
        return lauxlib.luaL_error(L, "cannot change a protected metatable");
    }
    lua.lua_settop(L, 2);
    _ = lua.lua_setmetatable(L, 1);
    return 1;
}

fn tonumber(L: *lua.lua_State) anyerror!i32 {
    if (lua.lua_isnoneornil(L, 2)) {
        if (lua.lua_type(L, 1) == lua.LUA_TNUMBER) {
            lua.lua_settop(L, 1);
            return 1;
        }
        const s = lua.lua_tostring(L, 1);
        if (s) |str| {
            if (std.fmt.parseFloat(f64, str)) |val| {
                lua.lua_pushnumber(L, val);
                return 1;
            } else |_| {}
            if (std.fmt.parseInt(i64, str, 10)) |val| {
                lua.lua_pushinteger(L, val);
                return 1;
            } else |_| {}
        }
    } else {
        const base = try lauxlib.luaL_checkinteger(L, 2);
        if (base < 2 or base > 36) {
            return lauxlib.luaL_error(L, "base out of range");
        }
        const s = try lauxlib.luaL_checklstring(L, 1, null);
        if (std.fmt.parseInt(i64, s, @as(u8, @intCast(base)))) |val| {
            lua.lua_pushinteger(L, val);
            return 1;
        } else |_| {}
    }
    lua.lua_pushnil(L);
    return 1;
}

fn tostring(L: *lua.lua_State) anyerror!i32 {
    try lauxlib.luaL_checkany(L, 1);
    _ = lauxlib.luaL_tolstring(L, 1, null);
    return 1;
}

fn type_fn(L: *lua.lua_State) anyerror!i32 {
    try lauxlib.luaL_checkany(L, 1);
    const t = lua.lua_type(L, 1);
    const name = switch (t) {
        lua.LUA_TNIL => "nil",
        lua.LUA_TBOOLEAN => "boolean",
        lua.LUA_TLIGHTUSERDATA => "light userdata",
        lua.LUA_TNUMBER => "number",
        lua.LUA_TSTRING => "string",
        lua.LUA_TTABLE => "table",
        lua.LUA_TFUNCTION => "function",
        lua.LUA_TUSERDATA => "userdata",
        lua.LUA_TTHREAD => "thread",
        else => "unknown",
    };
    _ = lua.lua_pushstring(L, name);
    return 1;
}

fn xpcall(L: *lua.lua_State) anyerror!i32 {
    const n = lua.lua_gettop(L);
    try lauxlib.luaL_checkany(L, 2);
    lua.lua_pushvalue(L, 2);
    lua.lua_insert(L, 1);
    lua.lua_remove(L, 3);
    const status = lua.lua_pcallk(L, n - 2, lua.LUA_MULTRET, 1, 0, null);
    lua.lua_pushboolean(L, if (status == lua.LUA_OK) @as(i32, 1) else @as(i32, 0));
    lua.lua_insert(L, 1);
    return lua.lua_gettop(L);
}
