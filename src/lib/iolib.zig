const std = @import("std");
const lua = @import("../lua.zig");
const lauxlib = @import("../lauxlib.zig");

const L = lua.lua_State;
const luaL_Reg = lauxlib.luaL_Reg;

const LUA_FILEHANDLE = "FILE*";
const IO_INPUT = "INPUT*";
const IO_OUTPUT = "OUTPUT*";

const LStream = struct {
    fd: i32,
    closef: ?lua.lua_CFunction,
};

fn tostream(L_: *L, idx: i32) *LStream {
    const p = lua.lua_touserdata(L_, idx) orelse unreachable;
    return @as(*LStream, @ptrCast(@alignCast(p)));
}

fn fopen(name: []const u8, mode: []const u8) ?i32 {
    if (name.len == 0) return null;
    const first = if (mode.len > 0) mode[0] else 'r';
    const flags: std.posix.O = switch (first) {
        'r' => .{ .ACCMODE = .RDONLY },
        'w' => .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true },
        'a' => .{ .ACCMODE = .WRONLY, .CREAT = true, .APPEND = true },
        else => return null,
    };
    const mode_bits: std.posix.mode_t = switch (first) {
        'w', 'a' => 0o666,
        else => 0,
    };
    const fd = std.posix.openat(std.posix.AT.FDCWD, name, flags, mode_bits) catch return null;
    return fd;
}

fn f_close(L_: *L, p: *LStream) !i32 {
    if (p.closef) |cf| {
        p.closef = null;
        return cf(L_);
    }
    _ = std.os.linux.close(p.fd);
    p.fd = -1;
    lua.lua_pushboolean(L_, 1);
    return 1;
}

fn io_close(L_: *L) !i32 {
    const p = if (lua.lua_isnone(L_, 1) == 0)
        tostream(L_, 1)
    else blk: {
        _ = try lua.lua_getfield(L_, lua.LUA_REGISTRYINDEX, IO_OUTPUT);
        break :blk tostream(L_, -1);
    };
    return f_close(L_, p);
}

fn f_gc(L_: *L) !i32 {
    const p = tostream(L_, 1);
    if (p.closef != null) {
        _ = f_close(L_, p) catch {};
    }
    return 0;
}

fn io_fclose(L_: *L) !i32 {
    return f_gc(L_);
}

fn newfile(L_: *L) !*LStream {
    const p = lua.lua_newuserdatauv(L_, @sizeOf(LStream), 0) orelse unreachable;
    const stream = @as(*LStream, @ptrCast(@alignCast(p)));
    stream.* = LStream{ .fd = -1, .closef = null };
    try lauxlib.luaL_setmetatable(L_, LUA_FILEHANDLE);
    return stream;
}

fn getiofile(L_: *L, findex: []const u8) !*LStream {
    _ = try lua.lua_getfield(L_, lua.LUA_REGISTRYINDEX, findex);
    if (lua.lua_type(L_, -1) == lua.LUA_TNIL) {
        return lauxlib.luaL_error(L_, "default file is closed");
    }
    return tostream(L_, -1);
}

fn g_iofile(L_: *L, findex: []const u8, mode: []const u8) !i32 {
    if (lua.lua_isnoneornil(L_, 1)) {
            _ = lua.lua_rawgetp(L_, lua.LUA_REGISTRYINDEX, @ptrCast(findex.ptr));
        return 1;
    }
    const filename = lua.lua_tostring(L_, 1);
    if (filename) |fn_| {
        const f = fopen(fn_, mode) orelse {
            return lauxlib.luaL_fileresult(L_, false, fn_);
        };
        const p = try newfile(L_);
        p.* = LStream{ .fd = f, .closef = io_fclose };
        lua.lua_replace(L_, 1);
        lua.lua_rawsetp(L_, lua.LUA_REGISTRYINDEX, @constCast(@ptrCast(findex.ptr)));
        return 0;
    }
    lua.lua_rawsetp(L_, lua.LUA_REGISTRYINDEX, @constCast(@ptrCast(findex.ptr)));
    return 0;
}

fn io_input(L_: *L) !i32 {
    return g_iofile(L_, IO_INPUT, "r");
}

fn io_output(L_: *L) !i32 {
    return g_iofile(L_, IO_OUTPUT, "w");
}

fn io_open(L_: *L) !i32 {
    const filename = lua.lua_tostring(L_, 1) orelse {
        return lauxlib.luaL_fileresult(L_, false, "?");
    };
    const mode = lua.lua_tostring(L_, 2) orelse "r";
    const f = fopen(filename, mode) orelse {
        return lauxlib.luaL_fileresult(L_, false, filename);
    };
    const p = try newfile(L_);
    p.* = LStream{ .fd = f, .closef = io_fclose };
    return 1;
}

fn io_popen(L_: *L) !i32 {
    lua.lua_pushnil(L_);
    _ = lua.lua_pushstring(L_, "'popen' not supported") orelse {};
    return 2;
}

fn io_tmpfile(L_: *L) !i32 {
    var buf: [32]u8 = undefined;
    const a = std.posix.openat(std.posix.AT.FDCWD, "/tmp", .{ .ACCMODE = .RDWR, .TMPFILE = true }, 0o600) catch {
        lua.lua_pushnil(L_);
        _ = lua.lua_pushstring(L_, "cannot create tmp file") orelse {};
        return 2;
    };
    _ = &buf;
    const p = try newfile(L_);
    p.* = LStream{ .fd = a, .closef = io_fclose };
    return 1;
}

fn io_type(L_: *L) !i32 {
    const p = lua.lua_touserdata(L_, 1);
    if (p != null and lua.lua_getmetatable(L_, 1) != 0) {
        _ = try lua.lua_getfield(L_, lua.LUA_REGISTRYINDEX, LUA_FILEHANDLE);
        if (lua.lua_rawequal(L_, -1, -2) != 0) {
            lua.lua_pop(L_, 2);
            _ = lua.lua_pushstring(L_, "file") orelse {};
            return 1;
        }
        lua.lua_pop(L_, 2);
    }
    lua.lua_pushnil(L_);
    return 1;
}

fn read_chars(L_: *L, fd: i32, n: usize) bool {
    var buf = std.heap.page_allocator.alloc(u8, n) catch return false;
    defer std.heap.page_allocator.free(buf);
    const bytes_read = std.posix.read(fd, buf) catch return false;
    if (bytes_read == 0) return false;
    _ = lua.lua_pushlstring(L_, buf[0..bytes_read], buf.len) orelse {};
    return true;
}

fn read_line(L_: *L, fd: i32) bool {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.heap.page_allocator);
    var single: [1]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &single) catch break;
        if (n == 0) break;
        if (single[0] == '\n') break;
        buf.append(std.heap.page_allocator, single[0]) catch break;
    }
    if (buf.items.len > 0) {
        _ = lua.lua_pushlstring(L_, buf.items, buf.items.len) orelse {};
        return true;
    }
    return false;
}

fn g_read(L_: *L, fd: i32, first: i32) !i32 {
    var n: i32 = first;
    var nread: i32 = 0;
    const top = lua.lua_gettop(L_);
    var nargs = top - 1;
    if (nargs == 0) {
        nargs = 1;
        n = 0;
    }
    for (0..@as(usize, @intCast(nargs))) |_| {
        var success = false;
        if (n > 0) {
            success = read_line(L_, fd);
        } else {
            const fmt = lua.lua_tointeger(L_, n) orelse 0;
            if (fmt == 0) {
                const s = lua.lua_tostring(L_, n) orelse "";
                if (s.len > 0 and s[0] == '*') {
                    if (s.len >= 2) {
                        switch (s[1]) {
                            'l' => success = read_line(L_, fd),
                            'a' => success = read_chars(L_, fd, 4096),
                            else => success = false,
                        }
                    }
                } else {
                    const fmt_len = if (fmt > 0) @as(usize, @intCast(fmt)) else 1;
                    success = read_chars(L_, fd, fmt_len);
                }
            }
        }
        n += 1;
        if (!success) {
            lua.lua_pushnil(L_);
            if (nread == 0) {
                lua.lua_pushnil(L_);
                return 2;
            }
        }
        nread += 1;
    }
    return nread;
}

fn io_read(L_: *L) !i32 {
    return f_read(L_);
}

fn f_read(L_: *L) !i32 {
    const p = getiofile(L_, IO_INPUT) catch return lauxlib.luaL_error(L_, "default input file is closed");
    return g_read(L_, p.fd, 2);
}

fn g_write(L_: *L, fd: i32, arg: i32) !i32 {
    const nargs = lua.lua_gettop(L_) - (arg - 1);
    var status = true;
    for (0..@as(usize, @intCast(nargs))) |i| {
        const idx = arg + @as(i32, @intCast(i));
        const s = lua.lua_tostring(L_, idx);
        if (s) |str| {
            const rc = std.os.linux.write(fd, str.ptr, str.len);
            if (@as(isize, @bitCast(rc)) < 0) {
                status = false;
                break;
            }
        } else if (lua.lua_isinteger(L_, idx) != 0) {
            const val = lua.lua_tointeger(L_, idx) orelse 0;
            var buf: [32]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{val}) catch unreachable;
            const rc = std.os.linux.write(fd, formatted.ptr, formatted.len);
            if (@as(isize, @bitCast(rc)) < 0) {
                status = false;
                break;
            }
        } else {
            const num = lua.lua_tonumber(L_, idx) orelse 0.0;
            var buf: [64]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{num}) catch unreachable;
            const rc = std.os.linux.write(fd, formatted.ptr, formatted.len);
            if (@as(isize, @bitCast(rc)) < 0) {
                status = false;
                break;
            }
        }
    }
    return lauxlib.luaL_fileresult(L_, status, null);
}

fn io_write(L_: *L) !i32 {
    return f_write(L_);
}

fn f_write(L_: *L) !i32 {
    const p = getiofile(L_, IO_OUTPUT) catch return lauxlib.luaL_error(L_, "default output file is closed");
    return g_write(L_, p.fd, 1);
}

fn f_seek(L_: *L) !i32 {
    const p = tostream(L_, 1);
    const whence_s = lua.lua_tostring(L_, 2) orelse "cur";
    const offset = lua.lua_tointeger(L_, 3) orelse 0;
    const whence: usize = if (std.mem.eql(u8, whence_s, "set")) 0 else if (std.mem.eql(u8, whence_s, "end")) 2 else 1;
    const result = std.os.linux.lseek(p.fd, offset, whence);
    if (result != std.math.maxInt(usize)) {
        lua.lua_pushinteger(L_, @intCast(@as(i64, @intCast(result))));
        return 1;
    }
    lua.lua_pushboolean(L_, 0);
    return 1;
}

fn f_setvbuf(L_: *L) !i32 {
    _ = lua.lua_tostring(L_, 2);
    _ = lua.lua_tointeger(L_, 3);
    lua.lua_pushboolean(L_, 1);
    return 1;
}

fn io_flush(L_: *L) !i32 {
    return f_flush(L_);
}

fn f_flush(L_: *L) !i32 {
    _ = tostream(L_, 1);
    lua.lua_pushboolean(L_, 1);
    return 1;
}

fn io_lines(L_: *L) !i32 {
    if (!lua.lua_isnoneornil(L_, 1)) {
        const filename = lua.lua_tostring(L_, 1) orelse "";
        const f = fopen(filename, "r") orelse {
            return lauxlib.luaL_fileresult(L_, false, filename);
        };
        const p = try newfile(L_);
        p.* = LStream{ .fd = f, .closef = io_fclose };
        lua.lua_replace(L_, 1);
    }
    lua.lua_pushcfunction(L_, f_lines);
    lua.lua_pushvalue(L_, 1);
    return 2;
}

fn f_lines(L_: *L) !i32 {
    const p = tostream(L_, 1);
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(std.heap.page_allocator);
    var single: [1]u8 = undefined;
    while (true) {
        const n = std.posix.read(p.fd, &single) catch break;
        if (n == 0) break;
        if (single[0] == '\n') break;
        buf.append(std.heap.page_allocator, single[0]) catch break;
    }
    if (buf.items.len > 0) {
        _ = lua.lua_pushlstring(L_, buf.items, buf.items.len) orelse {};
        return 1;
    }
    return 0;
}

fn createstdfile(L_: *L, fd: i32, k: []const u8, cf: ?lua.lua_CFunction) !void {
    const p = lua.lua_newuserdatauv(L_, @sizeOf(LStream), 0) orelse unreachable;
    const stream = @as(*LStream, @ptrCast(@alignCast(p)));
    stream.* = LStream{ .fd = fd, .closef = cf };
    try lauxlib.luaL_setmetatable(L_, LUA_FILEHANDLE);
    lua.lua_rawsetp(L_, lua.LUA_REGISTRYINDEX, @constCast(@ptrCast(k.ptr)));
}

const iolib_reg = [_]luaL_Reg{
    .{ .name = "close", .func = io_close },
    .{ .name = "flush", .func = io_flush },
    .{ .name = "input", .func = io_input },
    .{ .name = "lines", .func = io_lines },
    .{ .name = "open", .func = io_open },
    .{ .name = "output", .func = io_output },
    .{ .name = "popen", .func = io_popen },
    .{ .name = "read", .func = io_read },
    .{ .name = "tmpfile", .func = io_tmpfile },
    .{ .name = "type", .func = io_type },
    .{ .name = "write", .func = io_write },
    .{ .name = "", .func = undefined },
};

const flib = [_]luaL_Reg{
    .{ .name = "close", .func = io_close },
    .{ .name = "flush", .func = f_flush },
    .{ .name = "lines", .func = f_lines },
    .{ .name = "read", .func = f_read },
    .{ .name = "seek", .func = f_seek },
    .{ .name = "setvbuf", .func = f_setvbuf },
    .{ .name = "write", .func = f_write },
    .{ .name = "__gc", .func = f_gc },
    .{ .name = "__close", .func = io_fclose },
    .{ .name = "", .func = undefined },
};

pub fn openio(L_: *L) !void {
    _ = try lauxlib.luaL_newmetatable(L_, LUA_FILEHANDLE);
    lauxlib.luaL_setfuncs(L_, &flib, 0);
    lauxlib.luaL_newlib(L_, &iolib_reg);
    try createstdfile(L_, 0, IO_INPUT, null);  // stdin
    try createstdfile(L_, 1, IO_OUTPUT, null); // stdout
}
