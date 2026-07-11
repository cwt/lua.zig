// $Id: pack.zig $
// String binary packing and unpacking engine for Lua.zig
// See Copyright Notice in lua.h

const std = @import("std");
const lua = @import("../../lua.zig");
const lauxlib = @import("../../lauxlib.zig");
const pattern = @import("pattern.zig");
const posrelatI = pattern.posrelatI;

const KOption = enum {
    signed,
    unsigned,
    float,
    char,
    string,
    zstring,
    padding,
    nop,
    max,
};

const Header = struct {
    L: *lua.lua_State,
    islittle: bool,
    maxalign: usize,
};

fn digit(c: u8) bool {
    return std.ascii.isDigit(c);
}

fn getnum(fmt: []const u8, df: usize, pos: *usize) usize {
    var p = pos.*;
    if (p >= fmt.len or !digit(fmt[p])) {
        return df;
    }
    var a: usize = 0;
    while (p < fmt.len and digit(fmt[p])) {
        a = a * 10 + @as(usize, @intCast(fmt[p] - '0'));
        p += 1;
    }
    pos.* = p;
    return a;
}

fn getnumlimit(h: *Header, fmt: []const u8, df: usize, max_val: usize, pos: *usize) !usize {
    const a = getnum(fmt, df, pos);
    if (a > max_val or a == 0) {
        return lauxlib.luaL_error(h.L, "size out of limits");
    }
    return a;
}

fn initheader(L: *lua.lua_State, h: *Header) void {
    h.L = L;
    const native_endian = @import("builtin").cpu.arch.endian();
    h.islittle = (native_endian == .little);
    h.maxalign = 1;
}

fn getoption(h: *Header, fmt: []const u8, pos: *usize, size: *usize) !KOption {
    var p = pos.*;
    if (p >= fmt.len) return .max;
    const opt = fmt[p];
    p += 1;
    pos.* = p;
    size.* = 0;
    switch (opt) {
        'b' => {
            size.* = 1;
            return .signed;
        },
        'B' => {
            size.* = 1;
            return .unsigned;
        },
        'h' => {
            size.* = 2;
            return .signed;
        },
        'H' => {
            size.* = 2;
            return .unsigned;
        },
        'l' => {
            size.* = 8;
            return .signed;
        },
        'L' => {
            size.* = 8;
            return .unsigned;
        },
        'j' => {
            size.* = 8;
            return .signed;
        },
        'J' => {
            size.* = 8;
            return .unsigned;
        },
        'T' => {
            size.* = 8;
            return .unsigned;
        },
        'f' => {
            size.* = 4;
            return .float;
        },
        'd' => {
            size.* = 8;
            return .float;
        },
        'n' => {
            size.* = 8;
            return .float;
        },
        'i' => {
            size.* = try getnumlimit(h, fmt, 4, 16, pos);
            return .signed;
        },
        'I' => {
            size.* = try getnumlimit(h, fmt, 4, 16, pos);
            return .unsigned;
        },
        'c' => {
            size.* = getnum(fmt, 0, pos);
            if (size.* == 0) {
                return lauxlib.luaL_error(h.L, "missing size for option 'c'");
            }
            return .char;
        },
        's' => {
            size.* = try getnumlimit(h, fmt, 8, 16, pos);
            return .string;
        },
        'z' => return .zstring,
        'x' => {
            size.* = 1;
            return .padding;
        },
        'X' => return .padding,
        ' ' => return .nop,
        '<' => {
            h.islittle = true;
            return .nop;
        },
        '>' => {
            h.islittle = false;
            return .nop;
        },
        '=' => {
            const native_endian = @import("builtin").cpu.arch.endian();
            h.islittle = (native_endian == .little);
            return .nop;
        },
        '!' => {
            h.maxalign = try getnumlimit(h, fmt, 8, 16, pos);
            return .nop;
        },
        else => {
            var temp_buf: [30]u8 = undefined;
            const msg = try std.fmt.bufPrint(&temp_buf, "invalid format option '{c}'", .{opt});
            return lauxlib.luaL_error(h.L, msg);
        },
    }
}

fn getdetails(h: *Header, fmt: []const u8, pos: *usize, size: *usize, align_val: *usize) !KOption {
    const opt = try getoption(h, fmt, pos, size);
    var al = size.*;
    if (opt == .padding) {
        if (pos.* >= fmt.len) {
            al = 1;
        } else {
            const next_c = fmt[pos.*];
            var temp_sz: usize = 0;
            var temp_h = h.*;
            var temp_pos = pos.*;
            const next_opt = getoption(&temp_h, fmt, &temp_pos, &temp_sz) catch .max;
            if (next_opt == .max or temp_sz == 0) {
                al = 1;
            } else {
                al = temp_sz;
            }
            _ = next_c;
        }
    }
    if (al > h.maxalign) {
        al = h.maxalign;
    }
    if ((al & (al - 1)) != 0) {
        al = 1;
    }
    align_val.* = al;
    return opt;
}

fn packint(L: *lua.lua_State, b: *lauxlib.luaL_Buffer, val: u64, islittle: bool, size: usize) !void {
    const dest = try lauxlib.luaL_prepbuffsize(L, b, size);
    var v = val;
    var i: usize = 0;
    if (islittle) {
        while (i < size) : (i += 1) {
            dest[i] = @as(u8, @intCast(v & 0xFF));
            v >>= 8;
        }
    } else {
        while (i < size) : (i += 1) {
            dest[size - 1 - i] = @as(u8, @intCast(v & 0xFF));
            v >>= 8;
        }
    }
    lauxlib.luaL_addsize(b, size);
}

fn copywithendian(dest: []u8, src: []const u8, size: usize, islittle: bool) void {
    const native_endian = @import("builtin").cpu.arch.endian();
    const native_is_little = (native_endian == .little);
    if (islittle == native_is_little) {
        @memcpy(dest[0..size], src[0..size]);
    } else {
        var i: usize = 0;
        while (i < size) : (i += 1) {
            dest[size - 1 - i] = src[i];
        }
    }
}

pub fn str_pack(L: *lua.lua_State) anyerror!i32 {
    var fmt_len: usize = 0;
    const fmt = try lauxlib.luaL_checklstring(L, 1, &fmt_len);
    var h: Header = undefined;
    initheader(L, &h);
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);
    var argn: i32 = 2;
    var pos: usize = 0;
    while (pos < fmt.len) {
        var size: usize = 0;
        var align_val: usize = 0;
        const opt = try getdetails(&h, fmt, &pos, &size, &align_val);
        if (opt == .nop) continue;
        const current_len = b.buf.items.len;
        const pad_needed = (align_val - (current_len % align_val)) % align_val;
        if (pad_needed > 0) {
            const pad_dest = try lauxlib.luaL_prepbuffsize(L, &b, pad_needed);
            @memset(pad_dest[0..pad_needed], 0);
            lauxlib.luaL_addsize(&b, pad_needed);
        }
        switch (opt) {
            .signed => {
                const val = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                try packint(L, &b, @as(u64, @bitCast(val)), h.islittle, size);
            },
            .unsigned => {
                const val = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                try packint(L, &b, @as(u64, @bitCast(val)), h.islittle, size);
            },
            .float => {
                const val = try lauxlib.luaL_checknumber(L, argn);
                argn += 1;
                const dest = try lauxlib.luaL_prepbuffsize(L, &b, size);
                if (size == 4) {
                    const f = @as(f32, @floatCast(val));
                    const bytes = std.mem.asBytes(&f);
                    copywithendian(dest, bytes, 4, h.islittle);
                } else if (size == 8) {
                    const d = @as(f64, val);
                    const bytes = std.mem.asBytes(&d);
                    copywithendian(dest, bytes, 8, h.islittle);
                }
                lauxlib.luaL_addsize(&b, size);
            },
            .char => {
                var sl: usize = 0;
                const s = try lauxlib.luaL_checklstring(L, argn, &sl);
                argn += 1;
                try lauxlib.luaL_argcheck(L, sl <= size, argn - 1, "string longer than given size");
                const dest = try lauxlib.luaL_prepbuffsize(L, &b, size);
                @memcpy(dest[0..sl], s[0..sl]);
                if (sl < size) {
                    @memset(dest[sl..size], 0);
                }
                lauxlib.luaL_addsize(&b, size);
            },
            .string => {
                var sl: usize = 0;
                const s = try lauxlib.luaL_checklstring(L, argn, &sl);
                argn += 1;
                try packint(L, &b, sl, h.islittle, size);
                const dest = try lauxlib.luaL_prepbuffsize(L, &b, sl);
                @memcpy(dest[0..sl], s[0..sl]);
                lauxlib.luaL_addsize(&b, sl);
            },
            .zstring => {
                var sl: usize = 0;
                const s = try lauxlib.luaL_checklstring(L, argn, &sl);
                argn += 1;
                try lauxlib.luaL_argcheck(L, std.mem.indexOfScalar(u8, s, 0) == null, argn - 1, "string contains zeros");
                const dest = try lauxlib.luaL_prepbuffsize(L, &b, sl + 1);
                @memcpy(dest[0..sl], s[0..sl]);
                dest[sl] = 0;
                lauxlib.luaL_addsize(&b, sl + 1);
            },
            .padding => {
                if (size > 0) {
                    const dest = try lauxlib.luaL_prepbuffsize(L, &b, size);
                    @memset(dest[0..size], 0);
                    lauxlib.luaL_addsize(&b, size);
                }
            },
            else => unreachable,
        }
    }
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

pub fn str_packsize(L: *lua.lua_State) anyerror!i32 {
    var fmt_len: usize = 0;
    const fmt = try lauxlib.luaL_checklstring(L, 1, &fmt_len);
    var h: Header = undefined;
    initheader(L, &h);
    var totalsize: usize = 0;
    var pos: usize = 0;
    while (pos < fmt.len) {
        var size: usize = 0;
        var align_val: usize = 0;
        const opt = try getdetails(&h, fmt, &pos, &size, &align_val);
        if (opt == .nop) continue;
        if (opt == .string or opt == .zstring) {
            return lauxlib.luaL_error(L, "variable-length format in 'packsize'");
        }
        const pad_needed = (align_val - (totalsize % align_val)) % align_val;
        totalsize += pad_needed;
        totalsize += size;
    }
    lua.lua_pushinteger(L, @as(i64, @intCast(totalsize)));
    return 1;
}

fn unpackint(src: []const u8, size: usize, islittle: bool) u64 {
    var v: u64 = 0;
    var i: usize = 0;
    if (islittle) {
        while (i < size) : (i += 1) {
            v |= @as(u64, src[i]) << @as(u6, @intCast(i * 8));
        }
    } else {
        while (i < size) : (i += 1) {
            v = (v << 8) | @as(u64, src[i]);
        }
    }
    return v;
}

pub fn str_unpack(L: *lua.lua_State) anyerror!i32 {
    var fmt_len: usize = 0;
    var data_len: usize = 0;
    const fmt = try lauxlib.luaL_checklstring(L, 1, &fmt_len);
    const data = try lauxlib.luaL_checklstring(L, 2, &data_len);
    const init_pos = posrelatI(lauxlib.luaL_optinteger(L, 3, 1), data_len);
    try lauxlib.luaL_argcheck(L, init_pos > 0 and init_pos <= data_len + 1, 3, "position out of limits");
    var data_offset = init_pos - 1;
    var h: Header = undefined;
    initheader(L, &h);
    var pos: usize = 0;
    var n: i32 = 0;
    while (pos < fmt.len) {
        var size: usize = 0;
        var align_val: usize = 0;
        const opt = try getdetails(&h, fmt, &pos, &size, &align_val);
        if (opt == .nop) continue;
        const pad_needed = (align_val - (data_offset % align_val)) % align_val;
        data_offset += pad_needed;
        if (data_offset + size > data_len) {
            return lauxlib.luaL_argerror(L, 2, "data string too short");
        }
        switch (opt) {
            .signed => {
                const uv = unpackint(data[data_offset..], size, h.islittle);
                var iv = @as(i64, @bitCast(uv));
                // Sign extend if size < 8
                if (size < 8) {
                    const mask = (@as(u64, 1) << @as(u6, @intCast(size * 8 - 1)));
                    const uv_se = (uv ^ mask) -% mask;
                    iv = @as(i64, @bitCast(uv_se));
                }
                lua.lua_pushinteger(L, iv);
                n += 1;
            },
            .unsigned => {
                const uv = unpackint(data[data_offset..], size, h.islittle);
                lua.lua_pushinteger(L, @as(i64, @bitCast(uv)));
                n += 1;
            },
            .float => {
                var f_val: f64 = 0;
                var bytes_buf: [8]u8 = undefined;
                copywithendian(&bytes_buf, data[data_offset..], size, h.islittle);
                if (size == 4) {
                    var f: f32 = undefined;
                    std.mem.copyForwards(u8, std.mem.asBytes(&f), bytes_buf[0..4]);
                    f_val = f;
                } else if (size == 8) {
                    var d: f64 = undefined;
                    std.mem.copyForwards(u8, std.mem.asBytes(&d), bytes_buf[0..8]);
                    f_val = d;
                }
                lua.lua_pushnumber(L, f_val);
                n += 1;
            },
            .char => {
                _ = lua.lua_pushlstring(L, data[data_offset..][0..size], size);
                n += 1;
            },
            .string => {
                const sl = unpackint(data[data_offset..], size, h.islittle);
                const sl_u = @as(usize, @intCast(sl));
                data_offset += size;
                if (data_offset + sl_u > data_len) {
                    return lauxlib.luaL_argerror(L, 2, "data string too short");
                }
                _ = lua.lua_pushlstring(L, data[data_offset..][0..sl_u], sl_u);
                data_offset += sl_u;
                size = 0; // already advanced
                n += 1;
            },
            .zstring => {
                const rest = data[data_offset..];
                if (std.mem.indexOfScalar(u8, rest, 0)) |zero_pos| {
                    _ = lua.lua_pushlstring(L, rest[0..zero_pos], zero_pos);
                    data_offset += zero_pos + 1;
                    size = 0; // already advanced
                    n += 1;
                } else {
                    return lauxlib.luaL_argerror(L, 2, "unfinished string in data");
                }
            },
            .padding => {},
            else => unreachable,
        }
        data_offset += size;
    }

    lua.lua_pushinteger(L, @as(i64, @intCast(data_offset + 1)));
    return n + 1;
}
