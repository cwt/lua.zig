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
    /// Pending unread byte (one-level pushback) so read helpers can return a
    /// look-ahead char to the stream. `null` means no pending byte.
    unget: ?u8,
};

/// Default buffer size for `setvbuf` when no size is given (cf. stdio `BUFSIZ`).
const IO_BUFSIZE: usize = 8192;

fn tostream(L_: *L, idx: i32) !*LStream {
    const p = try lauxlib.luaL_checkudata(L_, idx, LUA_FILEHANDLE);
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
        try tostream(L_, 1)
    else blk: {
        _ = lua.lua_rawgetp(L_, lua.LUA_REGISTRYINDEX, @ptrCast(IO_OUTPUT.ptr));
        break :blk try tostream(L_, -1);
    };
    return f_close(L_, p);
}

fn f_gc(L_: *L) !i32 {
    const p = try tostream(L_, 1);
    if (p.closef != null) {
        _ = f_close(L_, p) catch {};
    }
    return 0;
}

fn io_fclose(L_: *L) !i32 {
    const p = try tostream(L_, 1);
    return f_close(L_, p);
}

fn newfile(L_: *L) !*LStream {
    const p = lua.lua_newuserdatauv(L_, @sizeOf(LStream), 0) orelse return error.OutOfMemory;
    const stream = @as(*LStream, @ptrCast(@alignCast(p)));
    stream.* = LStream{ .fd = -1, .closef = null, .buf = null, .buf_len = 0, .buf_mode = 0, .unget = null };
    try lauxlib.luaL_setmetatable(L_, LUA_FILEHANDLE);
    return stream;
}

fn getiofile(L_: *L, findex: []const u8) !*LStream {
    _ = lua.lua_rawgetp(L_, lua.LUA_REGISTRYINDEX, @ptrCast(findex.ptr));
    if (lua.lua_type(L_, -1) == lua.LUA_TNIL) {
        return lauxlib.luaL_error(L_, "default file is closed");
    }
    return try tostream(L_, -1);
}

fn g_iofile(L_: *L, findex: []const u8, mode: []const u8) !i32 {
    if (!lua.lua_isnoneornil(L_, 1)) {
        const filename = lua.lua_tostring(L_, 1);
        if (filename) |fn_| {
            const f = fopen(fn_, mode) orelse {
                return lauxlib.luaL_fileresult(L_, false, fn_);
            };
            const p = try newfile(L_);
            p.* = LStream{ .fd = f, .closef = io_fclose, .buf = null, .buf_len = 0, .buf_mode = 0, .unget = null };
        } else {
            _ = try tostream(L_, 1);
            lua.lua_pushvalue(L_, 1);
        }
        lua.lua_rawsetp(L_, lua.LUA_REGISTRYINDEX, @constCast(@ptrCast(findex.ptr)));
    }
    _ = lua.lua_rawgetp(L_, lua.LUA_REGISTRYINDEX, @ptrCast(findex.ptr));
    return 1;
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
    p.* = LStream{ .fd = f, .closef = io_fclose, .buf = null, .buf_len = 0, .buf_mode = 0, .unget = null };
    return 1;
}

fn io_popen(L_: *L) !i32 {
    lua.lua_pushnil(L_);
    _ = lua.lua_pushstring(L_, "'popen' not supported") orelse {};
    return 2;
}

var tmpfile_counter: u64 = 0;

fn io_tmpfile(L_: *L) !i32 {
    var buf: [64]u8 = undefined;
    const unique = @atomicRmw(u64, &tmpfile_counter, .Add, 1, .monotonic);
    const path = std.fmt.bufPrint(&buf, "/tmp/luazig_{x:0>16}", .{unique}) catch {
        lua.lua_pushnil(L_);
        _ = lua.lua_pushstring(L_, "cannot create tmp file") orelse {};
        return 2;
    };
    const a = std.posix.openatZ(std.posix.AT.FDCWD, buf[0..path.len :0].ptr, .{ .ACCMODE = .RDWR, .CREAT = true, .EXCL = true }, 0o600) catch {
        lua.lua_pushnil(L_);
        _ = lua.lua_pushstring(L_, "cannot create tmp file") orelse {};
        return 2;
    };
    defer {
        buf[path.len] = 0;
        _ = std.c.unlink(buf[0..path.len :0]);
    }
    const p = try newfile(L_);
    p.* = LStream{ .fd = a, .closef = io_fclose, .buf = null, .buf_len = 0, .buf_mode = 0, .unget = null };
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

// Maximum length of a numeral accepted by `read_number` (cf. C `L_MAXLENNUM`).
const L_MAXLENNUM: usize = 200;

// Read a single byte from stream `p`, honoring a pending unget. Returns `null`
// on EOF or read error (callers treat both as end-of-input).
fn read_byte(p: *LStream) ?u8 {
    if (p.unget) |b| {
        p.unget = null;
        return b;
    }
    var one: [1]u8 = undefined;
    const n = std.posix.read(p.fd, &one) catch return null;
    if (n == 0) return null;
    return one[0];
}

fn read_chars(L_: *L, p: *LStream, n: usize) bool {
    var buf = L_.allocator.alloc(u8, n) catch return false;
    defer L_.allocator.free(buf);
    var got: usize = 0;
    if (p.unget) |b| {
        buf[0] = b;
        p.unget = null;
        got = 1;
    }
    while (got < n) {
        const r = std.posix.read(p.fd, buf[got..]) catch break;
        if (r == 0) break;
        got += r;
    }
    if (got == 0) return false;
    _ = lua.lua_pushlstring(L_, buf[0..got], got) orelse {};
    return true;
}

// Read the entire remaining file content. Per Lua 5.5 semantics, `*a` on an
// empty file returns an empty string (not nil).
fn read_all(L_: *L, p: *LStream) bool {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(L_.allocator);
    if (p.unget) |b| {
        buf.append(L_.allocator, b) catch return false;
        p.unget = null;
    }
    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = std.posix.read(p.fd, &chunk) catch return false;
        if (n == 0) break;
        buf.appendSlice(L_.allocator, chunk[0..n]) catch return false;
    }
    _ = lua.lua_pushlstring(L_, buf.items, buf.items.len) orelse {};
    return true;
}

fn read_line(L_: *L, p: *LStream) bool {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(L_.allocator);
    while (true) {
        const c = read_byte(p) orelse break;
        if (c == '\n') break;
        buf.append(L_.allocator, c) catch break;
    }
    if (buf.items.len > 0) {
        _ = lua.lua_pushlstring(L_, buf.items, buf.items.len) orelse {};
        return true;
    }
    return false;
}

// Auxiliary state for `read_number`: a single-byte look-ahead reader that builds
// a valid numeral prefix into `buff` (mirrors C `liolib.c` `RN` / `read_number`).
const RN = struct {
    c: ?u8,
    n: usize,
    buff: [L_MAXLENNUM + 1]u8,
    p: *LStream,

    fn next(rn: *RN) bool {
        if (rn.n >= L_MAXLENNUM) {
            rn.buff[0] = 0;
            return false;
        }
        if (rn.c) |ch| {
            rn.buff[rn.n] = ch;
            rn.n += 1;
        }
        rn.c = read_byte(rn.p);
        return true;
    }

    fn test2(rn: *RN, set: []const u8) bool {
        if (rn.c) |ch| {
            if (ch == set[0] or ch == set[1]) {
                _ = rn.next();
                return true;
            }
        }
        return false;
    }

    fn readdigits(rn: *RN, hex: bool) usize {
        var count: usize = 0;
        while (rn.c) |ch| {
            const isd = if (hex)
                (std.ascii.isDigit(ch) or (ch >= 'a' and ch <= 'f') or (ch >= 'A' and ch <= 'F'))
            else
                std.ascii.isDigit(ch);
            if (!isd) break;
            _ = rn.next();
            count += 1;
        }
        return count;
    }
};

// Read a Lua number (`*n` format): read a valid numeral prefix into a buffer,
// then convert it with `lua_stringtonumber`. On success the number is left on
// the stack; on failure nothing is pushed (the caller pushes `nil`).
fn read_number(L_: *L, p: *LStream) bool {
    var rn: RN = .{ .c = null, .n = 0, .buff = undefined, .p = p };
    // skip leading whitespace
    while (true) {
        rn.c = read_byte(p);
        if (rn.c == null) break;
        if (!std.ascii.isWhitespace(rn.c.?)) break;
    }
    var hex = false;
    var count: usize = 0;
    _ = rn.test2("-+");
    if (rn.test2("00")) {
        if (rn.test2("xX")) hex = true else {
            count = 1; // leading '0' counts as a digit
        }
    }
    count += rn.readdigits(hex);
    if (rn.c) |ch| {
        if (ch == '.') {
            _ = rn.next();
            count += rn.readdigits(hex);
        }
    }
    if (count > 0) {
        if (rn.c) |ch| {
            const is_exp = if (hex) (ch == 'p' or ch == 'P') else (ch == 'e' or ch == 'E');
            if (is_exp) {
                _ = rn.next();
                _ = rn.test2("-+");
                _ = rn.readdigits(false);
            }
        }
    }
    if (rn.c) |ch| {
        p.unget = ch; // push back the first non-numeral char
    }
    rn.buff[rn.n] = 0;
    return lua.lua_stringtonumber(L_, rn.buff[0..rn.n]) > 0;
}

fn g_read(L_: *L, p: *LStream, first: i32) !i32 {
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
            success = read_line(L_, p);
        } else {
            const fmt_int = lua.lua_tointeger(L_, n);
            if (fmt_int) |num| {
                if (num > 0) {
                    success = read_chars(L_, p, @as(usize, @intCast(num)));
                }
            } else {
                const s = lua.lua_tostring(L_, n) orelse "";
                // Lua 5.5 accepts the optional '*' format prefix.
                const fmt = if (s.len > 0 and s[0] == '*') s[1..] else s;
                if (fmt.len > 0) {
                    switch (fmt[0]) {
                        'l', 'L' => success = read_line(L_, p),
                        'a' => success = read_all(L_, p),
                        'n' => success = read_number(L_, p),
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
    return g_read(L_, p, 2);
}

fn f_read(L_: *L) !i32 {
    const p = try tostream(L_, 1);
    return g_read(L_, p, 2);
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
    const top = lua.lua_gettop(L_);
    if (top < arg) return 1;
    const nargs = top - arg + 1;
    var status = true;
    for (0..@as(usize, @intCast(nargs))) |i| {
        const idx = arg + @as(i32, @intCast(i));
        var len: usize = 0;
        if (lua.lua_type(L_, idx) == lua.LUA_TSTRING) {
            const str = (try lauxlib.luaL_checklstring(L_, idx, &len));
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
        } else if (lua.lua_type(L_, idx) == lua.LUA_TNUMBER) {
            const num = lua.lua_tonumber(L_, idx) orelse 0.0;
            var buf: [64]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{d}", .{num}) catch unreachable;
            if (!writeToStream(p, formatted)) {
                status = false;
                break;
            }
        } else {
            const str = (try lauxlib.luaL_checklstring(L_, idx, &len));
            if (!writeToStream(p, str)) {
                status = false;
                break;
            }
        }
    }
    if (status) {
        lua.lua_pushvalue(L_, 1);
        return 1;
    }
    return lauxlib.luaL_fileresult(L_, false, null);
}

fn io_write(L_: *L) !i32 {
    const p = getiofile(L_, IO_OUTPUT) catch return lauxlib.luaL_error(L_, "default output file is closed");
    // Mirror the reference `io_write`: the current output file becomes
    // argument 1 and the user's values follow it (so the write loop starts at
    // index 2), and the file handle is returned on success.
    lua.lua_insert(L_, 1);
    return g_write(L_, p, 2);
}

fn f_write(L_: *L) !i32 {
    const p = try tostream(L_, 1);
    return g_write(L_, p, 2);
}

fn f_seek(L_: *L) !i32 {
    const p = try tostream(L_, 1);
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
    const p = try tostream(L_, 1);
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
    const p = try tostream(L_, 1);
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
        p.* = LStream{ .fd = f, .closef = io_fclose, .buf = null, .buf_len = 0, .buf_mode = 0, .unget = null };
        lua.lua_replace(L_, 1);
    }
    lua.lua_pushcfunction(L_, f_lines);
    lua.lua_pushvalue(L_, 1);
    return 2;
}

fn f_lines(L_: *L) !i32 {
    const p = try tostream(L_, 1);
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(L_.allocator);
    while (true) {
        const c = read_byte(p) orelse break;
        if (c == '\n') break;
        buf.append(L_.allocator, c) catch break;
    }
    if (buf.items.len > 0) {
        _ = lua.lua_pushlstring(L_, buf.items, buf.items.len) orelse {};
        return 1;
    }
    return 0;
}

fn io_noclose(L_: *L) anyerror!i32 {
    const p = try tostream(L_, 1);
    p.closef = io_noclose;
    _ = lua.lua_pushstring(L_, "cannot close standard file");
    return 1;
}

fn createstdfile(L_: *L, fd: i32, k: ?[]const u8, fname: ?[]const u8, cf: ?lua.lua_CFunction) !void {
    const p = lua.lua_newuserdatauv(L_, @sizeOf(LStream), 0) orelse return error.OutOfMemory;
    const stream = @as(*LStream, @ptrCast(@alignCast(p)));
    stream.* = LStream{ .fd = fd, .closef = cf, .buf = null, .buf_len = 0, .buf_mode = 0, .unget = null };
    try lauxlib.luaL_setmetatable(L_, LUA_FILEHANDLE);
    if (k) |key| {
        lua.lua_pushvalue(L_, -1);
        lua.lua_rawsetp(L_, lua.LUA_REGISTRYINDEX, @constCast(@ptrCast(key.ptr)));
    }
    if (fname) |name| {
        try lua.lua_setfield(L_, -2, name);
    }
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
    try lauxlib.luaL_setfuncs(L_, &flib, 0);
    // Make the metatable its own __index so that `file:method(...)` resolves
    // the methods stored as fields of the metatable (matches PUC-Rio liolib).
    lua.lua_pushvalue(L_, -1);
    try lua.lua_setfield(L_, -2, "__index");
    lua.lua_pop(L_, 1); // remove FILE* metatable from the stack
    try lauxlib.luaL_newlib(L_, &iolib_reg);
    try createstdfile(L_, 0, IO_INPUT, "stdin", io_noclose);
    try createstdfile(L_, 1, IO_OUTPUT, "stdout", io_noclose);
    try createstdfile(L_, 2, null, "stderr", io_noclose);
}
