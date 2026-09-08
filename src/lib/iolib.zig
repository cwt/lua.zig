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
    /// Child process for `io.popen` streams. `null` for regular files.
    child: ?std.process.Child = null,
};

/// Default buffer size for `setvbuf` when no size is given (cf. stdio `BUFSIZ`).
const IO_BUFSIZE: usize = 8192;

fn tostream(L_: *L, idx: i32) !*LStream {
    const p = try lauxlib.luaL_checkudata(L_, idx, LUA_FILEHANDLE);
    return @as(*LStream, @ptrCast(@alignCast(p)));
}

fn isclosed(p: *const LStream) bool {
    return p.closef == null or p.fd < 0;
}

fn tofile(L_: *L, idx: i32) !*LStream {
    const p = try tostream(L_, idx);
    if (isclosed(p)) {
        return lauxlib.luaL_error(L_, "attempt to use a closed file");
    }
    return p;
}

/// Validate a file-open mode string (mirrors the reference l_checkmode):
/// 'r'/'w'/'a' followed by an optional immediate '+' and then only 'b'.
fn checkmode(mode: []const u8) bool {
    if (mode.len == 0) return false;
    const first = mode[0];
    if (first != 'r' and first != 'w' and first != 'a') return false;
    var i: usize = 1;
    if (i < mode.len and mode[i] == '+') i += 1;
    while (i < mode.len) : (i += 1) {
        if (mode[i] != 'b') return false;
    }
    return true;
}

fn fopen(name: []const u8, mode: []const u8, eno_out: ?*i32) ?i32 {
    if (name.len == 0) return null;
    const first = if (mode.len > 0) mode[0] else 'r';
    var flags: std.c.O = .{};
    switch (first) {
        'r' => flags.ACCMODE = .RDONLY,
        'w' => {
            flags.ACCMODE = .WRONLY;
            flags.CREAT = true;
            flags.TRUNC = true;
        },
        'a' => {
            flags.ACCMODE = .WRONLY;
            flags.CREAT = true;
            flags.APPEND = true;
        },
        else => return null,
    }
    const mode_bits: std.c.mode_t = switch (first) {
        'w', 'a' => 0o666,
        else => 0,
    };
    var buf: [std.fs.max_path_bytes:0]u8 = undefined;
    if (name.len >= buf.len) return null;
    @memcpy(buf[0..name.len], name);
    buf[name.len] = 0;
    const rc = std.c.open(&buf, flags, mode_bits);
    if (rc < 0) {
        if (eno_out) |p| p.* = @intCast(std.c._errno().*);
        return null;
    }
    return @intCast(rc);
}

fn doClose(L_: *L, p: *LStream) !i32 {
    // Flush any pending buffered output before releasing the fd.
    _ = flushBuffer(p);
    if (p.child) |*child| {
        // Wait for the child process to avoid zombies, then close the pipe fd.
        _ = child.wait(L_.l_G.?.io) catch {};
        p.child = null;
    }
    if (p.fd >= 0) {
        _ = std.c.close(p.fd);
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

/// File-method `close`: requires the file as argument 1 (raises "got no value"
/// otherwise), mirroring the reference's f_close -> tofile -> luaL_checkudata.
fn f_close_method(L_: *L) anyerror!i32 {
    const p = try tofile(L_, 1);
    return f_close(L_, p);
}

fn io_close(L_: *L) !i32 {
    const p = if (lua.lua_isnone(L_, 1) == 0)
        try tofile(L_, 1)
    else blk: {
        _ = lua.lua_rawgetp(L_, lua.LUA_REGISTRYINDEX, @ptrCast(IO_OUTPUT.ptr));
        break :blk try tofile(L_, -1);
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
    const p = try tostream(L_, -1);
    if (isclosed(p)) {
        return lauxlib.luaL_error(L_, "default file is closed");
    }
    return p;
}

fn g_iofile(L_: *L, findex: []const u8, mode: []const u8) !i32 {
    if (!lua.lua_isnoneornil(L_, 1)) {
        const filename = lua.lua_tostring(L_, 1);
        if (filename) |fn_| {
            var eno: i32 = 0;
            const f = fopen(fn_, mode, &eno) orelse {
                // Mirror the reference opencheck: raise with the strerror text.
                var mbuf: [256]u8 = undefined;
                const msg = std.fmt.bufPrint(&mbuf, "cannot open file '{s}' ({s})", .{ fn_, lauxlib.strerrorName(eno) }) catch "cannot open file";
                return lauxlib.luaL_error(L_, msg);
            };
            errdefer _ = std.c.close(f);
            const p = try newfile(L_);
            p.* = LStream{ .fd = f, .closef = io_fclose, .buf = null, .buf_len = 0, .buf_mode = 0, .unget = null };
        } else {
            _ = try tofile(L_, 1);
            lua.lua_pushvalue(L_, 1);
        }
        try lua.lua_rawsetp(L_, lua.LUA_REGISTRYINDEX, @ptrCast(@constCast(findex.ptr)));
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
        return lauxlib.luaL_fileresult(L_, false, "?", 0);
    };
    const mode = lua.lua_tostring(L_, 2) orelse "r";
    // Validate the mode (mirrors the reference l_checkmode/luaL_argcheck).
    try lauxlib.luaL_argcheck(L_, checkmode(mode), 2, "invalid mode");
    var eno: i32 = 0;
    const f = fopen(filename, mode, &eno) orelse {
        return lauxlib.luaL_fileresult(L_, false, filename, eno);
    };
    errdefer _ = std.c.close(f);
    const p = try newfile(L_);
    p.* = LStream{ .fd = f, .closef = io_fclose, .buf = null, .buf_len = 0, .buf_mode = 0, .unget = null };
    return 1;
}

fn io_pclose(L_: *L) !i32 {
    const p = try tostream(L_, 1);
    // Wait for the child and close the pipe fd.
    var stat: i32 = 0;
    if (p.child) |*child| {
        switch (try child.wait(L_.l_G.?.io)) {
            .exited => |code| stat = @intCast(code),
            .signal => |sig| stat = @intCast(@as(u32, @intFromEnum(sig))),
            .stopped => |sig| stat = @intCast(@as(u32, @intFromEnum(sig))),
            .unknown => |code| stat = @intCast(code),
        }
        p.child = null;
    }
    // Close the pipe fd.
    if (p.fd >= 0) {
        _ = std.c.close(p.fd);
        p.fd = -1;
    }
    // Reset closef so we don't double-close.
    p.closef = null;
    return lauxlib.luaL_execresult(L_, stat);
}

fn io_popen(L_: *L) !i32 {
    const cmd = lua.lua_tostring(L_, 1) orelse {
        return lauxlib.luaL_error(L_, "string expected");
    };
    const mode_s = lua.lua_tostring(L_, 2) orelse "r";
    // Validate mode: popen only accepts "r" or "w" (no '+' or 'b').
    if (mode_s.len != 1 or (mode_s[0] != 'r' and mode_s[0] != 'w')) {
        return lauxlib.luaL_argerror(L_, 2, "invalid mode");
    }
    const is_read = mode_s[0] == 'r';

    const io = L_.l_G orelse return lauxlib.luaL_error(L_, "no I/O context");

    // Build argv: ["/bin/sh", "-c", cmd]
    const argv = [_][]const u8{ "/bin/sh", "-c", cmd };

    // Spawn the child with pipes.
    var child = std.process.spawn(io.io, .{
        .argv = &argv,
        .stdin = if (is_read) .inherit else .pipe,
        .stdout = if (is_read) .pipe else .inherit,
        .stderr = .inherit,
    }) catch {
        lua.lua_pushnil(L_);
        _ = lua.lua_pushstring(L_, "cannot open pipe");
        return 2;
    };

    // Grab the pipe fd.
    var pipe_fd: i32 = undefined;
    if (is_read) {
        if (child.stdout) |f| {
            pipe_fd = f.handle;
        } else {
            // Child spawned without expected stdout pipe; reap child to prevent zombie.
            _ = child.wait(io.io) catch {};
            lua.lua_pushnil(L_);
            _ = lua.lua_pushstring(L_, "cannot open pipe");
            return 2;
        }
    } else {
        if (child.stdin) |f| {
            pipe_fd = f.handle;
        } else {
            // Child spawned without expected stdin pipe; reap child to prevent zombie.
            _ = child.wait(io.io) catch {};
            lua.lua_pushnil(L_);
            _ = lua.lua_pushstring(L_, "cannot open pipe");
            return 2;
        }
    }

    const p = newfile(L_) catch {
        if (pipe_fd >= 0) _ = std.c.close(pipe_fd);
        child.kill(io.io);
        _ = child.wait(io.io) catch {};
        return error.OutOfMemory;
    };
    p.* = LStream{
        .fd = pipe_fd,
        .closef = io_pclose,
        .buf = null,
        .buf_len = 0,
        .buf_mode = 0,
        .unget = null,
        .child = child,
    };
    return 1;
}

fn io_tmpfile(L_: *L) !i32 {
    var buf: [64]u8 = undefined;
    const seed = if (L_.l_G) |g| g.seed else 0;
    const ptr_val = @intFromPtr(L_);
    var attempts: usize = 0;
    while (attempts < 100) : (attempts += 1) {
        const path = std.fmt.bufPrint(&buf, "/tmp/luazig_{x:0>8}_{x:0>8}_{d}", .{ seed, ptr_val & 0xFFFFFFFF, attempts }) catch {
            break;
        };
        buf[path.len] = 0;
        if (std.posix.openatZ(std.posix.AT.FDCWD, buf[0..path.len :0].ptr, .{ .ACCMODE = .RDWR, .CREAT = true, .EXCL = true }, 0o600)) |a| {
            errdefer _ = std.c.close(a);
            defer {
                _ = std.c.unlink(buf[0..path.len :0]);
            }
            const p = try newfile(L_);
            p.* = LStream{ .fd = a, .closef = io_fclose, .buf = null, .buf_len = 0, .buf_mode = 0, .unget = null };
            return 1;
        } else |_| {}
    }
    lua.lua_pushnil(L_);
    _ = lua.lua_pushstring(L_, "cannot create tmp file");
    return 2;
}

fn io_type(L_: *L) !i32 {
    try lauxlib.luaL_checkany(L_, 1);
    const udata = lauxlib.luaL_testudata(L_, 1, LUA_FILEHANDLE);
    if (udata) |p| {
        const stream = @as(*const LStream, @ptrCast(@alignCast(p)));
        if (isclosed(stream)) {
            _ = lua.lua_pushliteral(L_, "closed file");
        } else {
            _ = lua.lua_pushliteral(L_, "file");
        }
        return 1;
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

fn test_eof(L_: *L, p: *LStream) bool {
    if (p.unget != null) {
        _ = lua.lua_pushliteral(L_, "");
        return true;
    }
    const c = read_byte(p) orelse {
        _ = lua.lua_pushliteral(L_, "");
        return false;
    };
    p.unget = c;
    _ = lua.lua_pushliteral(L_, "");
    return true;
}

fn read_chars(L_: *L, p: *LStream, n: usize) bool {
    if (n == 0) return test_eof(L_, p);
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
    _ = lua.lua_pushlstring(L_, buf[0..got], got);
    return got > 0;
}

// Read the entire remaining file content. Per Lua 5.5 semantics, `*a` on an
// empty file returns an empty string (not nil).
fn read_all(L_: *L, p: *LStream) bool {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(L_.allocator);
    while (true) {
        const c = read_byte(p) orelse break;
        buf.append(L_.allocator, c) catch break;
    }
    _ = lua.lua_pushlstring(L_, buf.items, buf.items.len);
    return true;
}

fn read_line(L_: *L, p: *LStream, chop: bool) bool {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(L_.allocator);
    var had_nl = false;
    while (true) {
        const c = read_byte(p) orelse break;
        if (c == '\n') {
            had_nl = true;
            if (!chop) {
                buf.append(L_.allocator, '\n') catch break;
            }
            break;
        }
        buf.append(L_.allocator, c) catch break;
    }
    _ = lua.lua_pushlstring(L_, buf.items, buf.items.len);
    return had_nl or buf.items.len > 0;
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
    if (lua.lua_stringtonumber(L_, rn.buff[0..rn.n]) > 0) {
        return true;
    } else {
        lua.lua_pushnil(L_);
        return false;
    }
}

fn g_read(L_: *L, p: *LStream, first: i32) !i32 {
    const nargs = lua.lua_gettop(L_) - 1;
    var success = true;
    var n: i32 = first;
    if (nargs <= 0) {
        success = read_line(L_, p, true);
        n = first + 1;
    } else {
        var count = nargs;
        while (count > 0 and success) : (count -= 1) {
            if (lua.lua_type(L_, n) == lua.LUA_TNUMBER) {
                const l = lua.lua_tointeger(L_, n) orelse 0;
                if (l < 0) return lauxlib.luaL_argerror(L_, n, "invalid format");
                success = read_chars(L_, p, @as(usize, @intCast(l)));
            } else {
                const s = try lauxlib.luaL_checkstring(L_, n);
                const fmt = if (s.len > 0 and s[0] == '*') s[1..] else s;
                if (fmt.len == 0) return lauxlib.luaL_argerror(L_, n, "invalid format");
                switch (fmt[0]) {
                    'n' => success = read_number(L_, p),
                    'l' => success = read_line(L_, p, true),
                    'L' => success = read_line(L_, p, false),
                    'a' => {
                        _ = read_all(L_, p);
                        success = true;
                    },
                    else => return lauxlib.luaL_argerror(L_, n, "invalid format"),
                }
            }
            n += 1;
        }
    }
    if (!success) {
        lua.lua_pop(L_, 1);
        lua.lua_pushnil(L_);
    }
    return n - first;
}

fn io_read(L_: *L) !i32 {
    const p = getiofile(L_, IO_INPUT) catch return lauxlib.luaL_error(L_, "default input file is closed");
    return g_read(L_, p, 1);
}

fn f_read(L_: *L) !i32 {
    const p = try tofile(L_, 1);
    return g_read(L_, p, 2);
}

/// Write all bytes in `data` to `fd`, looping until complete. Returns true on success.
fn rawWrite(fd: i32, data: []const u8) bool {
    var off: usize = 0;
    while (off < data.len) {
        const rc = std.c.write(fd, data.ptr + off, data.len - off);
        if (rc <= 0 and data.len > 0) return false;
        off += @intCast(rc);
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
        } else if (lua.lua_type(L_, idx) == lua.LUA_TNUMBER) {
            const v = lua.stackAt(L_, idx);
            var buf: [128]u8 = undefined;
            const formatted = lua.luaO_tostringbuff(v, &buf);
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
    return lauxlib.luaL_fileresult(L_, false, null, 0);
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
    const p = try tofile(L_, 1);
    return g_write(L_, p, 2);
}

fn f_seek(L_: *L) !i32 {
    const p = try tofile(L_, 1);
    const whence_s = lua.lua_tostring(L_, 2) orelse "cur";
    const offset = lua.lua_tointeger(L_, 3) orelse 0;
    const whence: c_int = if (std.mem.eql(u8, whence_s, "set")) 0 else if (std.mem.eql(u8, whence_s, "end")) 2 else 1;
    const result = std.c.lseek(p.fd, offset, whence);
    if (result >= 0) {
        lua.lua_pushinteger(L_, @intCast(result));
        return 1;
    }
    lua.lua_pushboolean(L_, 0);
    return 1;
}

fn f_setvbuf(L_: *L) !i32 {
    const p = try tofile(L_, 1);
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
        return lauxlib.luaL_fileresult(L_, false, null, 0);
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
    return lauxlib.luaL_fileresult(L_, ok, null, 0);
}

fn f_flush(L_: *L) !i32 {
    const p = try tofile(L_, 1);
    const ok = flushBuffer(p);
    return lauxlib.luaL_fileresult(L_, ok, null, 0);
}

fn io_readline(L_: *L) anyerror!i32 {
    const p = try tostream(L_, lua.lua_upvalueindex(1));
    const n = @as(i32, @intCast(lua.lua_tointeger(L_, lua.lua_upvalueindex(2)) orelse 0));
    if (isclosed(p)) {
        return lauxlib.luaL_error(L_, "file is already closed");
    }
    lua.lua_settop(L_, 1);
    if (lua.lua_checkstack(L_, n) == 0) {
        return lauxlib.luaL_error(L_, "too many arguments");
    }
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        lua.lua_pushvalue(L_, lua.lua_upvalueindex(3 + i));
    }
    const nread = try g_read(L_, p, 2);
    if (lua.lua_toboolean(L_, -nread) != 0) {
        return nread;
    } else {
        if (nread > 1) {
            return lauxlib.luaL_error(L_, lua.lua_tostring(L_, -nread + 1).?);
        }
        if (lua.lua_toboolean(L_, lua.lua_upvalueindex(3)) != 0) {
            lua.lua_settop(L_, 0);
            lua.lua_pushvalue(L_, lua.lua_upvalueindex(1));
            _ = try f_close(L_, p);
        }
        return 0;
    }
}

fn aux_lines(L_: *L, toclose: i32) !void {
    const top = lua.lua_gettop(L_);
    const n = top - 1;
    try lauxlib.luaL_argcheck(L_, n <= 250, 252, "too many arguments");
    lua.lua_pushvalue(L_, 1);
    lua.lua_pushinteger(L_, n);
    lua.lua_pushboolean(L_, toclose);
    lua.lua_rotate(L_, 2, 3);
    lua.lua_pushcclosure(L_, io_readline, 3 + n);
}

fn f_lines(L_: *L) !i32 {
    _ = try tofile(L_, 1);
    try aux_lines(L_, 0);
    return 1;
}

fn io_lines(L_: *L) !i32 {
    var toclose: i32 = 0;
    if (lua.lua_isnone(L_, 1) != 0) {
        lua.lua_pushnil(L_);
    }
    if (lua.lua_isnil(L_, 1) != 0) {
        _ = lua.lua_rawgetp(L_, lua.LUA_REGISTRYINDEX, @ptrCast(IO_INPUT.ptr));
        lua.lua_replace(L_, 1);
        _ = try tofile(L_, 1);
        toclose = 0;
    } else {
        const filename = try lauxlib.luaL_checkstring(L_, 1);
        var eno: i32 = 0;
        const f = fopen(filename, "r", &eno) orelse {
            return lauxlib.luaL_fileresult(L_, false, filename, eno);
        };
        const p = try newfile(L_);
        p.* = LStream{ .fd = f, .closef = io_fclose, .buf = null, .buf_len = 0, .buf_mode = 0, .unget = null };
        lua.lua_replace(L_, 1);
        toclose = 1;
    }
    try aux_lines(L_, toclose);
    if (toclose != 0) {
        lua.lua_pushnil(L_);
        lua.lua_pushnil(L_);
        lua.lua_pushvalue(L_, 1);
        return 4;
    } else {
        return 1;
    }
}

fn io_noclose(L_: *L) anyerror!i32 {
    const p = try tostream(L_, 1);
    p.closef = io_noclose;
    lua.lua_pushnil(L_);
    _ = lua.lua_pushstring(L_, "cannot close standard file");
    return 2;
}

fn createstdfile(L_: *L, fd: i32, k: ?[]const u8, fname: ?[]const u8, cf: ?lua.lua_CFunction) !void {
    const p = lua.lua_newuserdatauv(L_, @sizeOf(LStream), 0) orelse return error.OutOfMemory;
    const stream = @as(*LStream, @ptrCast(@alignCast(p)));
    stream.* = LStream{ .fd = fd, .closef = cf, .buf = null, .buf_len = 0, .buf_mode = 0, .unget = null };
    try lauxlib.luaL_setmetatable(L_, LUA_FILEHANDLE);
    if (k) |key| {
        lua.lua_pushvalue(L_, -1);
        try lua.lua_rawsetp(L_, lua.LUA_REGISTRYINDEX, @ptrCast(@constCast(key.ptr)));
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
    .{ .name = "close", .func = f_close_method },
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
