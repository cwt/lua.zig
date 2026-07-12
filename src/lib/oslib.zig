const std = @import("std");
const lua = @import("../lua.zig");
const lauxlib = @import("../lauxlib.zig");
const linux = std.os.linux;

const L = lua.lua_State;
const luaL_Reg = lauxlib.luaL_Reg;

fn os_execute(L_: *L) !i32 {
    const cmd = lua.lua_tostring(L_, 1);
    if (cmd) |_s| {
        _ = _s;
    }
    lua.lua_pushboolean(L_, 1);
    return 1;
}

fn os_remove(L_: *L) !i32 {
    const filename_s = lua.lua_tostring(L_, 1) orelse {
        lua.lua_pushnil(L_);
        return 1;
    };
    const filename = L_.allocator.dupeZ(u8, filename_s) catch {
        lua.lua_pushboolean(L_, 0);
        return 1;
    };
    defer L_.allocator.free(filename);
    if (linux.unlink(filename) != 0) {
        lua.lua_pushboolean(L_, 0);
        return 1;
    }
    lua.lua_pushboolean(L_, 1);
    return 1;
}

fn os_rename(L_: *L) !i32 {
    const from_s = lua.lua_tostring(L_, 1) orelse return luaL_error(L_, "missing 'from' argument");
    const to_s = lua.lua_tostring(L_, 2) orelse return luaL_error(L_, "missing 'to' argument");
    const from = L_.allocator.dupeZ(u8, from_s) catch return luaL_error(L_, "out of memory");
    defer L_.allocator.free(from);
    const to = L_.allocator.dupeZ(u8, to_s) catch return luaL_error(L_, "out of memory");
    defer L_.allocator.free(to);
    if (linux.rename(from, to) != 0) {
        lua.lua_pushboolean(L_, 0);
        return 1;
    }
    lua.lua_pushboolean(L_, 1);
    return 1;
}

fn os_tmpname(L_: *L) !i32 {
    var buf: [@as(usize, 1) + 6 + 6]u8 = undefined;
    buf[0] = '/';
    buf[1..7].* = "tmp/lu"[0..6].*;
    _ = linux.getrandom(buf[7..], 6, 0);
    const hex = "0123456789abcdef";
    for (buf[7..], 0..) |*b, i| {
        b.* = hex[b.* % 16];
        _ = i;
    }
    const name = lua.lua_pushlstring(L_, &buf, buf.len) orelse return 1;
    _ = name;
    return 1;
}

fn os_getenv(L_: *L) !i32 {
    const name = lua.lua_tostring(L_, 1) orelse {
        lua.lua_pushnil(L_);
        return 1;
    };
    const val_opt = lauxlib.luaL_getenv(L_, name) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
    if (val_opt) |val| {
        defer L_.allocator.free(val);
        _ = lua.lua_pushlstring(L_, val, val.len);
        return 1;
    }
    lua.lua_pushnil(L_);
    return 1;
}

fn os_clock(L_: *L) !i32 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(linux.CLOCK.PROCESS_CPUTIME_ID, &ts);
    const secs = @as(f64, @floatFromInt(ts.sec)) + @as(f64, @floatFromInt(ts.nsec)) / 1.0e9;
    lua.lua_pushnumber(L_, secs);
    return 1;
}

fn os_date(L_: *L) !i32 {
    var s = if (lua.lua_gettop(L_) >= 1)
        (lua.lua_tostring(L_, 1) orelse "%c")
    else
        "%c";
    const is_utc = s.len > 0 and s[0] == '!';
    if (is_utc) s = s[1..];
    if (std.mem.eql(u8, s, "*t")) {
        lua.lua_createtable(L_, 0, 9);
        return 1;
    }
    _ = lua.lua_pushstring(L_, s) orelse {};
    return 1;
}

fn os_time(L_: *L) !i32 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(linux.CLOCK.REALTIME, &ts);
    lua.lua_pushinteger(L_, @intCast(ts.sec));
    return 1;
}

fn os_difftime(L_: *L) !i32 {
    const t1 = lua.lua_tointeger(L_, 1) orelse return 0;
    const t2 = lua.lua_tointeger(L_, 2) orelse return 0;
    lua.lua_pushnumber(L_, @as(f64, @floatFromInt(t1 - t2)));
    return 1;
}

fn os_setlocale(L_: *L) !i32 {
    _ = lua.lua_tostring(L_, 1);
    _ = lua.lua_tostring(L_, 2);
    _ = lua.lua_pushstring(L_, "C") orelse {};
    return 1;
}

fn os_exit(L_: *L) !i32 {
    const status: i32 = if (lua.lua_isboolean(L_, 1) != 0)
        if (lua.lua_toboolean(L_, 1) != 0) @as(i32, 0) else @as(i32, 1)
    else
        @as(i32, @intCast(lua.lua_tointeger(L_, 1) orelse 0));
    std.process.exit(@intCast(@as(i32, @max(0, @min(status, 255)))));
    return 0;
}

fn luaL_error(L_: *L, msg: []const u8) !i32 {
    _ = lua.lua_pushstring(L_, msg) orelse {};
    return lua.lua_error(L_);
}

const syslib = [_]luaL_Reg{
    .{ .name = "clock", .func = os_clock },
    .{ .name = "date", .func = os_date },
    .{ .name = "difftime", .func = os_difftime },
    .{ .name = "execute", .func = os_execute },
    .{ .name = "exit", .func = os_exit },
    .{ .name = "getenv", .func = os_getenv },
    .{ .name = "remove", .func = os_remove },
    .{ .name = "rename", .func = os_rename },
    .{ .name = "setlocale", .func = os_setlocale },
    .{ .name = "time", .func = os_time },
    .{ .name = "tmpname", .func = os_tmpname },
    .{ .name = "", .func = undefined },
};

pub fn openoslib(L_: *L) !void {
    try lauxlib.luaL_newlib(L_, &syslib);
}
