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
    /// Owned write buffer (allocated via `L.allocator`); `null` means no buffering.
    buf: ?[]u8,
    /// Bytes currently buffered in `buf`.
    buf_len: usize,
    /// 0 = unbuffered (write straight to fd), 1 = full buffering, 2 = line buffering.
    buf_mode: u8,
};

/// Default buffer size for `setvbuf` when no size is given (cf. stdio `BUFSIZ`).
const IO_BUFSIZE: usize = 8192;

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

fn doClose(L_: *L, p: *LStream) !i32 {
    // Flush any pending buffered output before releasing the fd.
    _ = flushBuffer(p);
    if (p.fd >= 0) {
        _ = std.os.linux.close(p.fd);
        p.fd = -1;
    }
    if (p.buf) |b| {
        L_.allocator.free(b);
        p.buf = null;
    }
    lua.lua_pushboolean(L_, 1);
    return 1;
}

fn f_close(L_: *L, p: *LStream) !i32 {
    if (p.closef) |cf| {
        p.closef = null;
        return cf(L_);
    }
    return doClose(L_, p);
}

fn io_close(L_: *L) !i32 {
    const p = if (lua.lua_isnone(L_, 1) == 0)
        tostream(L_, 1)
    else blk: {
        _ = lua.lua_rawgetp(L_, lua.LUA_REGISTRYINDEX, @ptrCast(IO_OUTPUT.ptr));
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
    const p = tostream(L_, 1);
    return f_close(L_, p);
}

fn newfile(L_: *L) !*LStream {
    const p = lua.lua_newuserdatauv(L_, @sizeOf(LStream), 0) orelse unreachable;
    const stream = @as(*LStream, @ptrCast(@alignCast(p)));
    stream.* = LStream{ .fd = -1, .closef = null, .buf = null, .buf_len = 0, .buf_mode = 0 };
    try lauxlib.luaL_setmetatable(L_, LUA_FILEHANDLE);
    return stream;
}

fn getiofile(L_: *L, findex: []const u8) !*LStream {
    _ = lua.lua_rawgetp(L_, lua.LUA_REGISTRYINDEX, @ptrCast(findex.ptr));
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
        p.* = LStream{ .fd = f, .closef = io_fclose, .buf = null, .buf_len = 0, .buf_mode = 0 };
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
    p.* = LStream{ .fd = f, .closef = io_fclose, .buf = null, .buf_len = 0, .buf_mode = 0 };
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
    p.* = LStream{ .fd = a, .closef = io_fclose, .buf = null, .buf_len = 0, .buf_mode = 0 };
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
    var buf = L_.allocator.alloc(u8, n) catch return false;
    defer L_.allocator.free(buf);
    const bytes_read = std.posix.read(fd, buf) catch return false;
    if (bytes_read == 0) return false;
    _ = lua.lua_pushlstring(L_, buf[0..bytes_read], bytes_read) orelse {};
    return true;
}

// Read the entire remaining file content. Per Lua 5.5 semantics, `*a` on an
// empty file returns an empty string (not nil).
fn read_all(L_: *L, fd: i32) bool {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(L_.allocator);
    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &chunk) catch return false;
        if (n == 0) break;
        buf.appendSlice(L_.allocator, chunk[0..n]) catch return false;
    }
    _ = lua.lua_pushlstring(L_, buf.items, buf.items.len) orelse {};
    return true;
}

fn read_line(L_: *L, fd: i32) bool {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(L_.allocator);
    var single: [1]u8 = undefined;
    while (true) {
        const n = std.posix.read(fd, &single) catch break;
        if (n == 0) break;
        if (single[0] == '\n') break;
        buf.append(L_.allocator, single[0]) catch break;
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
    var nargs = top - (first - 1);
    if (nargs == 0) {
        nargs = 1;
        n = 0;
    }
    for (0..@as(usize, @intCast(nargs))) |_| {
        var success = false;
        if (n == 0) {
            success = read_line(L_, fd);
        } else {
            const fmt_int = lua.lua_tointeger(L_, n);
            if (fmt_int) |num| {
                if (num > 0) {
                    success = read_chars(L_, fd, @as(usize, @intCast(num)));
                }
            } else {
                const s = lua.lua_tostring(L_, n) orelse "";
                // Lua 5.5 accepts the optional '*' format prefix.
                const fmt = if (s.len > 0 and s[0] == '*') s[1..] else s;
                if (fmt.len > 0) {
                    switch (fmt[0]) {
                        'l', 'L' => success = read_line(L_, fd),
                        'a' => success = read_all(L_, fd),
                        else => {},
                    }
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
    const p = getiofile(L_, IO_INPUT) catch return lauxlib.luaL_error(L_, "default input file is closed");
    return g_read(L_, p.fd, 2);
}

fn f_read(L_: *L) !i32 {
    const p = tostream(L_, 1);
    return g_read(L_, p.fd, 2);
}

/// Write all bytes in `data` to `fd`, looping until complete. Returns true on success.
fn rawWrite(fd: i32, data: []const u8) bool {
    var off: usize = 0;
    while (off < data.len) {
        const rc = std.os.linux.write(fd, data.ptr + off, data.len - off);
        if (rc == 0 and data.len > 0) return false;
        if (rc > std.math.maxInt(isize)) return false;
        off += rc;
    }
    return true;
}

/// Flush the write buffer of `p` to its fd. Safe when no buffer is allocated.
fn flushBuffer(p: *LStream) bool {
    if (p.buf) |b| {
        if (p.buf_len > 0) {
            const ok = rawWrite(p.fd, b[0..p.buf_len]);
            p.buf_len = 0;
            return ok;
        }
    }
    return true;
}

/// Append `data` to the stream buffer, flushing when full. Writes directly when the
/// datum exceeds the buffer size.
fn appendBuf(p: *LStream, data: []const u8) bool {
    const b = p.buf.?;
    if (p.buf_len + data.len > b.len) {
        if (!flushBuffer(p)) return false;
        if (data.len >= b.len) {
            return rawWrite(p.fd, data);
        }
    }
    @memcpy(b[p.buf_len .. p.buf_len + data.len], data);
    p.buf_len += data.len;
    return true;
}

/// Write `data` to stream `p`, honouring its buffering mode.
fn writeToStream(p: *LStream, data: []const u8) bool {
    if (p.buf == null) {
        return rawWrite(p.fd, data);
    }
    if (p.buf_mode == 2) {
        // Line buffering: flush up to and including each newline.
        var off: usize = 0;
        while (off < data.len) : (off += 1) {
            if (data[off] == '\n') {
                if (!appendBuf(p, data[0 .. off + 1])) return false;
                if (!flushBuffer(p)) return false;
                const rest = data[off + 1 ..];
                if (!writeToStream(p, rest)) return false;
                return true;
            }
        }
        return appendBuf(p, data);
    }
    return appendBuf(p, data);
}

fn g_write(L_: *L, p: *LStream, arg: i32) !i32 {
    const nargs = lua.lua_gettop(L_) - (arg - 1);
    var status = true;
    for (0..@as(usize, @intCast(nargs))) |i| {
        const idx = arg + @as(i32, @intCast(i));
        const s = lua.lua_tostring(L_, idx);
        if (s) |str| {
            if (!writeToStream(p, str)) {
                status = false;
                break;
            }
        } else if (lua.lua_isinteger(L_, idx) != 0) {
            const val = lua.lua_tointeger(L_, idx) orelse 0;
            var buf: [32]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{val}) catch unreachable;
            if (!writeToStream(p, formatted)) {
                status = false;
                break;
            }
        } else {
            const num = lua.lua_tonumber(L_, idx) orelse 0.0;
            var buf: [64]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{num}) catch unreachable;
            if (!writeToStream(p, formatted)) {
                status = false;
                break;
            }
        }
    }
    return lauxlib.luaL_fileresult(L_, status, null);
}

fn io_write(L_: *L) !i32 {
    const p = getiofile(L_, IO_OUTPUT) catch return lauxlib.luaL_error(L_, "default output file is closed");
    return g_write(L_, p, 1);
}

fn f_write(L_: *L) !i32 {
    const p = tostream(L_, 1);
    return g_write(L_, p, 2);
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
    const p = tostream(L_, 1);
    const mode = lua.lua_tostring(L_, 2) orelse "full";
    const size = lua.lua_tointeger(L_, 3);
    if (p.buf) |b| {
        L_.allocator.free(b);
        p.buf = null;
        p.buf_len = 0;
    }
    if (std.mem.eql(u8, mode, "no")) {
        p.buf_mode = 0;
        lua.lua_pushboolean(L_, 1);
        return 1;
    }
    const sz = if (size) |s| (if (s > 0) @as(usize, @intCast(s)) else 0) else 0;
    const bufsize = if (sz == 0) IO_BUFSIZE else sz;
    const buf = L_.allocator.alloc(u8, bufsize) catch {
        return lauxlib.luaL_fileresult(L_, false, null);
    };
    p.buf = buf;
    p.buf_len = 0;
    p.buf_mode = if (std.mem.eql(u8, mode, "line")) 2 else 1;
    lua.lua_pushboolean(L_, 1);
    return 1;
}

fn io_flush(L_: *L) !i32 {
    const p = getiofile(L_, IO_OUTPUT) catch return lauxlib.luaL_error(L_, "default output file is closed");
    const ok = flushBuffer(p);
    return lauxlib.luaL_fileresult(L_, ok, null);
}

fn f_flush(L_: *L) !i32 {
    const p = tostream(L_, 1);
    const ok = flushBuffer(p);
    return lauxlib.luaL_fileresult(L_, ok, null);
}

fn io_lines(L_: *L) !i32 {
    if (!lua.lua_isnoneornil(L_, 1)) {
        const filename = lua.lua_tostring(L_, 1) orelse "";
        const f = fopen(filename, "r") orelse {
            return lauxlib.luaL_fileresult(L_, false, filename);
        };
        const p = try newfile(L_);
        p.* = LStream{ .fd = f, .closef = io_fclose, .buf = null, .buf_len = 0, .buf_mode = 0 };
        lua.lua_replace(L_, 1);
    }
    lua.lua_pushcfunction(L_, f_lines);
    lua.lua_pushvalue(L_, 1);
    return 2;
}

fn f_lines(L_: *L) !i32 {
    const p = tostream(L_, 1);
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(L_.allocator);
    var single: [1]u8 = undefined;
    while (true) {
        const n = std.posix.read(p.fd, &single) catch break;
        if (n == 0) break;
        if (single[0] == '\n') break;
        buf.append(L_.allocator, single[0]) catch break;
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
    stream.* = LStream{ .fd = fd, .closef = cf, .buf = null, .buf_len = 0, .buf_mode = 0 };
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
    // luaL_newmetatable stores the file metatable in the registry but does not
    // leave it on the stack, so push it here to populate it.
    _ = try lauxlib.luaL_newmetatable(L_, LUA_FILEHANDLE);
    _ = try lua.lua_getfield(L_, lua.LUA_REGISTRYINDEX, LUA_FILEHANDLE);
    try lauxlib.luaL_setfuncs(L_, &flib, 0);
    // Make the metatable its own __index so that `file:method(...)` resolves
    // the methods stored as fields of the metatable (matches PUC-Rio liolib).
    lua.lua_pushvalue(L_, -1);
    try lua.lua_setfield(L_, -2, "__index");
    lua.lua_pop(L_, 1); // remove FILE* metatable from the stack
    try lauxlib.luaL_newlib(L_, &iolib_reg);
    try createstdfile(L_, 0, IO_INPUT, null);
    try createstdfile(L_, 1, IO_OUTPUT, null);
}
