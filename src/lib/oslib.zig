const std = @import("std");
const lua = @import("../lua.zig");
const lauxlib = @import("../lauxlib.zig");

const L = lua.lua_State;
const luaL_Reg = lauxlib.luaL_Reg;

// `std.c` does not expose the broken-down-time / formatting libc functions on
// Linux, so we bind them directly. This is the same `extern "c"` mechanism
// `std.os.linux` uses for syscalls (not `@cImport`). The `tm` layout matches
// glibc, the libc this port links against.
const TimeT = std.c.time_t;
const Tm = extern struct {
    tm_sec: c_int,
    tm_min: c_int,
    tm_hour: c_int,
    tm_mday: c_int,
    tm_mon: c_int,
    tm_year: c_int,
    tm_wday: c_int,
    tm_yday: c_int,
    tm_isdst: c_int,
    tm_gmtoff: c_long,
    tm_zone: ?[*:0]const u8,
};
extern "c" fn localtime_r(timer: *const TimeT, result: *Tm) ?*Tm;
extern "c" fn gmtime_r(timer: *const TimeT, result: *Tm) ?*Tm;
extern "c" fn mktime(timeptr: *Tm) TimeT;
extern "c" fn strftime(s: [*:0]u8, maxsize: usize, format: [*:0]const u8, timeptr: *const Tm) usize;
extern "c" fn time(timer: ?*TimeT) TimeT;
extern "c" fn remove(filename: [*:0]const u8) c_int;
extern "c" fn rename(old: [*:0]const u8, new: [*:0]const u8) c_int;
extern "c" fn clock() std.c.clock_t;

fn os_execute(L_: *L) !i32 {
    // No command: report whether a shell is available.
    if (lua.lua_gettop(L_) == 0 or lua.lua_isnil(L_, 1) != 0) {
        lua.lua_pushboolean(L_, 1);
        return 1;
    }
    const cmd = lua.lua_tostring(L_, 1) orelse return luaL_error(L_, "command must be a string");

    const io = (L_.l_G orelse return luaL_error(L_, "no I/O context")).io;
    const argv = [_][]const u8{ "/bin/sh", "-c", cmd };
    var child = std.process.spawn(io, .{
        .argv = &argv,
        .stdin = .inherit,
        .stdout = .inherit,
        .stderr = .inherit,
    }) catch {
        lua.lua_pushnil(L_);
        _ = lua.lua_pushstring(L_, "exit");
        lua.lua_pushinteger(L_, 127);
        return 3;
    };
    const term = child.wait(io) catch {
        lua.lua_pushnil(L_);
        _ = lua.lua_pushstring(L_, "exit");
        lua.lua_pushinteger(L_, 127);
        return 3;
    };
    switch (term) {
        .exited => |code| {
            if (code == 0) {
                lua.lua_pushboolean(L_, 1);
            } else {
                lua.lua_pushnil(L_);
            }
            _ = lua.lua_pushstring(L_, "exit");
            lua.lua_pushinteger(L_, code);
            return 3;
        },
        .signal, .stopped => |sig| {
            lua.lua_pushnil(L_);
            _ = lua.lua_pushstring(L_, "signal");
            lua.lua_pushinteger(L_, @intFromEnum(sig));
            return 3;
        },
        .unknown => |code| {
            lua.lua_pushnil(L_);
            _ = lua.lua_pushstring(L_, "exit");
            lua.lua_pushinteger(L_, @intCast(code));
            return 3;
        },
    }
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
    if (remove(filename) != 0) {
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
    if (rename(from, to) != 0) {
        lua.lua_pushboolean(L_, 0);
        return 1;
    }
    lua.lua_pushboolean(L_, 1);
    return 1;
}

fn os_tmpname(L_: *L) !i32 {
    var buf: [64]u8 = undefined;
    const seed = if (L_.l_G) |g| g.seed else 0;
    const ptr_val = @intFromPtr(L_);
    var t: TimeT = 0;
    _ = time(&t);
    const path = std.fmt.bufPrint(&buf, "/tmp/lua_{x}_{x}_{x}", .{ t, seed, ptr_val & 0xFFFF }) catch "/tmp/lua_tmp";
    _ = lua.lua_pushlstring(L_, path, path.len);
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
    const ticks = clock();
    const secs = @as(f64, @floatFromInt(ticks)) / 1000000.0;
    lua.lua_pushnumber(L_, secs);
    return 1;
}

fn setfieldint(L_: *L, key: []const u8, val: anytype) !void {
    lua.lua_pushinteger(L_, @intCast(val));
    try lua.lua_setfield(L_, -2, key);
}

fn os_date(L_: *L) !i32 {
    var fmt: []const u8 = "%c";
    if (lua.lua_gettop(L_) >= 1 and lua.lua_type(L_, 1) == lua.LUA_TSTRING) {
        fmt = lua.lua_tostring(L_, 1) orelse "%c";
    }
    const is_utc = fmt.len > 0 and fmt[0] == '!';
    if (is_utc) fmt = fmt[1..];

    // Resolve the epoch seconds to format.
    var t: TimeT = 0;
    if (lua.lua_gettop(L_) >= 2) {
        if (lua.lua_tointeger(L_, 2)) |secs| t = @intCast(secs);
    } else if (lua.lua_gettop(L_) >= 1 and lua.lua_type(L_, 1) != lua.LUA_TSTRING) {
        if (lua.lua_tointeger(L_, 1)) |secs| t = @intCast(secs);
    } else {
        _ = time(&t);
    }

    if (std.mem.eql(u8, fmt, "*t")) {
        var tm: Tm = undefined;
        if (is_utc) {
            _ = gmtime_r(&t, &tm);
        } else {
            _ = localtime_r(&t, &tm);
        }
        lua.lua_createtable(L_, 0, 9);
        try setfieldint(L_, "year", tm.tm_year + 1900);
        try setfieldint(L_, "month", tm.tm_mon + 1);
        try setfieldint(L_, "day", tm.tm_mday);
        try setfieldint(L_, "hour", tm.tm_hour);
        try setfieldint(L_, "min", tm.tm_min);
        try setfieldint(L_, "sec", tm.tm_sec);
        try setfieldint(L_, "wday", tm.tm_wday + 1);
        try setfieldint(L_, "yday", tm.tm_yday + 1);
        if (tm.tm_isdst > 0) {
            lua.lua_pushboolean(L_, 1);
            try lua.lua_setfield(L_, -2, "isdst");
        } else if (tm.tm_isdst == 0) {
            lua.lua_pushboolean(L_, 0);
            try lua.lua_setfield(L_, -2, "isdst");
        }
        return 1;
    }

    const cfmt = L_.allocator.dupeZ(u8, fmt) catch return error.OutOfMemory;
    defer L_.allocator.free(cfmt);
    var tm: Tm = undefined;
    if (is_utc) {
        _ = gmtime_r(&t, &tm);
    } else {
        _ = localtime_r(&t, &tm);
    }

    var bufsize: usize = 256;
    while (true) {
        const buf = L_.allocator.alloc(u8, bufsize) catch return error.OutOfMemory;
        defer L_.allocator.free(buf);
        const n = strftime(@ptrCast(buf.ptr), bufsize, cfmt, &tm);
        if (n > 0 or fmt.len == 0) {
            _ = lua.lua_pushlstring(L_, buf[0..n], n);
            return 1;
        }
        if (bufsize >= 4096) {
            _ = lua.lua_pushlstring(L_, buf[0..n], n);
            return 1;
        }
        bufsize *= 2;
    }
}

fn fieldint(L_: *L, key: []const u8, dft: i64, delta: i64) !i64 {
    _ = try lua.lua_getfield(L_, 1, key);
    const typ = lua.lua_type(L_, -1);
    const raw: i64 = if (typ == lua.LUA_TNIL) dft else (lua.lua_tointeger(L_, -1) orelse dft);
    lua.lua_pop(L_, 1);
    return raw - delta;
}

fn os_time(L_: *L) !i32 {
    if (lua.lua_gettop(L_) >= 1 and lua.lua_type(L_, 1) == lua.LUA_TTABLE) {
        lua.lua_settop(L_, 1);
        inline for (.{ "year", "month", "day" }) |k| {
            _ = try lua.lua_getfield(L_, 1, k);
            const present = lua.lua_type(L_, -1) != lua.LUA_TNIL;
            lua.lua_pop(L_, 1);
            if (!present) return luaL_error(L_, "field '" ++ k ++ "' missing in date table");
        }
        var tm: Tm = std.mem.zeroes(Tm);
        tm.tm_year = @intCast(try fieldint(L_, "year", -1, 1900));
        tm.tm_mon = @intCast(try fieldint(L_, "month", -1, 1));
        tm.tm_mday = @intCast(try fieldint(L_, "day", -1, 0));
        tm.tm_hour = @intCast(try fieldint(L_, "hour", 12, 0));
        tm.tm_min = @intCast(try fieldint(L_, "min", 0, 0));
        tm.tm_sec = @intCast(try fieldint(L_, "sec", 0, 0));
        tm.tm_isdst = @intCast(try fieldint(L_, "isdst", -1, 0));
        const t = mktime(&tm);
        if (t < 0) {
            lua.lua_pushnil(L_);
            return 1;
        }
        lua.lua_pushinteger(L_, @intCast(t));
        return 1;
    }
    var t: TimeT = 0;
    _ = time(&t);
    lua.lua_pushinteger(L_, @intCast(t));
    return 1;
}

fn os_difftime(L_: *L) !i32 {
    const t1 = lua.lua_tointeger(L_, 1) orelse return 0;
    const t2 = lua.lua_tointeger(L_, 2) orelse return 0;
    lua.lua_pushnumber(L_, @as(f64, @floatFromInt(t1 - t2)));
    return 1;
}

fn classcat(s: ?[]const u8) std.c.LC {
    const c = if (s) |x| x else "all";
    if (std.mem.eql(u8, c, "all")) return std.c.LC.ALL;
    if (std.mem.eql(u8, c, "collate")) return std.c.LC.COLLATE;
    if (std.mem.eql(u8, c, "ctype")) return std.c.LC.CTYPE;
    if (std.mem.eql(u8, c, "monetary")) return std.c.LC.MONETARY;
    if (std.mem.eql(u8, c, "numeric")) return std.c.LC.NUMERIC;
    if (std.mem.eql(u8, c, "time")) return std.c.LC.TIME;
    return std.c.LC.ALL;
}

fn os_setlocale(L_: *L) !i32 {
    const locale = lua.lua_tostring(L_, 1);
    const category_s = if (lua.lua_gettop(L_) >= 2) lua.lua_tostring(L_, 2) else null;
    const cat = classcat(category_s);
    const locale_z = if (locale) |l| L_.allocator.dupeZ(u8, l) catch return error.OutOfMemory else null;
    defer if (locale_z) |lz| L_.allocator.free(lz);
    const res = std.c.setlocale(cat, if (locale_z) |lz| lz else null);
    if (res) |r| {
        const sl = std.mem.span(r);
        _ = lua.lua_pushstring(L_, sl);
        return 1;
    }
    lua.lua_pushnil(L_);
    return 1;
}

fn os_exit(L_: *L) !i32 {
    const status: i32 = if (lua.lua_isboolean(L_, 1) != 0)
        if (lua.lua_toboolean(L_, 1) != 0) @as(i32, 0) else @as(i32, 1)
    else
        @as(i32, @intCast(lua.lua_tointeger(L_, 1) orelse 0));
    // Only close the Lua state (run __close/__gc finalizers) if the
    // caller explicitly requests it via the second argument.
    if (lua.lua_toboolean(L_, 2) != 0)
        lua.lua_close(L_);
    std.process.exit(@intCast(@as(i32, @max(0, @min(status, 255)))));
}

fn luaL_error(L_: *L, msg: []const u8) !i32 {
    _ = lua.lua_pushstring(L_, msg);
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
