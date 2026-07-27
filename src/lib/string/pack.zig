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
    paddalign,
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
    const max_limit = (std.math.maxInt(usize) - 9) / 10;
    while (p < fmt.len and digit(fmt[p])) {
        a = a * 10 + @as(usize, @intCast(fmt[p] - '0'));
        p += 1;
        if (a > max_limit) break;
    }
    pos.* = p;
    return a;
}

fn getnumlimit(h: *Header, fmt: []const u8, df: usize, max_val: usize, pos: *usize) !usize {
    const a = getnum(fmt, df, pos);
    if (a > max_val or a == 0) {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "integral size ({d}) out of limits [1,{d}]", .{ a, max_val }) catch "size out of limits";
        return lauxlib.luaL_error(h.L, msg);
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
            size.* = getnum(fmt, std.math.maxInt(usize), pos);
            if (size.* == std.math.maxInt(usize)) {
                return lauxlib.luaL_error(h.L, "missing size for format option 'c'");
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
        'X' => return .paddalign,
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
    if (opt == .paddalign) {
        if (pos.* >= fmt.len) {
            return lauxlib.luaL_argerror(h.L, 1, "invalid next option for option 'X'");
        }
        var next_sz: usize = 0;
        const next_opt = try getoption(h, fmt, pos, &next_sz);
        if (next_opt == .char or next_opt == .max or next_sz == 0) {
            return lauxlib.luaL_argerror(h.L, 1, "invalid next option for option 'X'");
        }
        al = next_sz;
    }
    if (al <= 1 or opt == .char) {
        align_val.* = 1;
    } else {
        if (al > h.maxalign) {
            al = h.maxalign;
        }
        if ((al & (al - 1)) != 0) {
            return lauxlib.luaL_argerror(h.L, 1, "format asks for alignment not power of 2");
        }
        align_val.* = al;
    }
    return opt;
}

fn packint(L: *lua.lua_State, b: *lauxlib.luaL_Buffer, val: u64, islittle: bool, size: usize, issigned: bool) !void {
    const dest = try lauxlib.luaL_prepbuffsize(L, b, size);
    var v = val;
    const neg = issigned and (@as(i64, @bitCast(val)) < 0);
    const fill: u8 = if (neg) 0xFF else 0x00;
    var i: usize = 0;
    if (islittle) {
        while (i < size) : (i += 1) {
            if (i < 8) {
                dest[i] = @as(u8, @intCast(v & 0xFF));
                v >>= 8;
            } else {
                dest[i] = fill;
            }
        }
    } else {
        while (i < size) : (i += 1) {
            if (i < 8) {
                dest[size - 1 - i] = @as(u8, @intCast(v & 0xFF));
                v >>= 8;
            } else {
                dest[size - 1 - i] = fill;
            }
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

    errdefer b.buf.deinit(L.allocator);
    var argn: i32 = 2;
    var totalsize: usize = 0;
    var pos: usize = 0;
    while (pos < fmt.len) {
        var size: usize = 0;
        var align_val: usize = 0;
        const opt = try getdetails(&h, fmt, &pos, &size, &align_val);
        if (opt == .nop) continue;
        const pad_needed = (align_val - (totalsize % align_val)) % align_val;
        const max_allowed = @as(usize, @intCast(std.math.maxInt(i64)));
        try lauxlib.luaL_argcheck(L, pad_needed <= max_allowed -| totalsize and size <= (max_allowed -| totalsize) -| pad_needed, argn, "result too long");
        totalsize += pad_needed + size;
        if (pad_needed > 0) {
            const pad_dest = try lauxlib.luaL_prepbuffsize(L, &b, pad_needed);
            @memset(pad_dest[0..pad_needed], 0);
            lauxlib.luaL_addsize(&b, pad_needed);
        }
        if (opt == .paddalign) continue;
        if (opt == .padding) {
            if (size > 0) {
                const pad_dest = try lauxlib.luaL_prepbuffsize(L, &b, size);
                @memset(pad_dest[0..size], 0);
                lauxlib.luaL_addsize(&b, size);
            }
            continue;
        }
        switch (opt) {
            .signed => {
                const val = try lauxlib.luaL_checkinteger(L, argn);
                if (size < 8) {
                    const shift: u6 = @truncate(size * 8 - 1);
                    const lim = @as(i64, 1) << shift;
                    try lauxlib.luaL_argcheck(L, val >= -lim and val < lim, argn, "integer overflow");
                }
                argn += 1;
                try packint(L, &b, @as(u64, @bitCast(val)), h.islittle, size, val < 0);
            },
            .unsigned => {
                const val = try lauxlib.luaL_checkinteger(L, argn);
                if (size < 8) {
                    const max_u = (@as(u64, 1) << @as(u6, @truncate(size * 8)));
                    try lauxlib.luaL_argcheck(L, @as(u64, @bitCast(val)) < max_u and val >= 0, argn, "unsigned overflow");
                } else {
                    try lauxlib.luaL_argcheck(L, val >= 0, argn, "unsigned overflow");
                }
                argn += 1;
                try packint(L, &b, @as(u64, @bitCast(val)), h.islittle, size, false);
            },
            .float => {
                const val = try lauxlib.luaL_checknumber(L, argn);
                argn += 1;
                const dest = try lauxlib.luaL_prepbuffsize(L, &b, size);
                if (size == 4) {
                    const f = @as(f32, @floatCast(val));
                    copywithendian(dest[0..4], std.mem.asBytes(&f), 4, h.islittle);
                } else if (size == 8) {
                    const d = @as(f64, val);
                    copywithendian(dest[0..8], std.mem.asBytes(&d), 8, h.islittle);
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
                if (size < 8) {
                    const max_len = @as(usize, 1) << @as(u6, @truncate(size * 8));
                    try lauxlib.luaL_argcheck(L, sl < max_len, argn - 1, "string length does not fit in given size");
                }
                try packint(L, &b, sl, h.islittle, size, false);
                const dest = try lauxlib.luaL_prepbuffsize(L, &b, sl);
                @memcpy(dest[0..sl], s[0..sl]);
                lauxlib.luaL_addsize(&b, sl);
                totalsize += sl;
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
                totalsize += sl + 1;
            },
            .padding => {
                if (size > 0) {
                    const dest = try lauxlib.luaL_prepbuffsize(L, &b, size);
                    @memset(dest[0..size], 0);
                    lauxlib.luaL_addsize(&b, size);
                }
            },
            .max => break,
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
        const max_allowed = @as(usize, @intCast(std.math.maxInt(i64)));
        if (totalsize > max_allowed -| pad_needed or (totalsize + pad_needed) > max_allowed -| size) {
            return lauxlib.luaL_argerror(L, 1, "format result too large");
        }
        totalsize += pad_needed + size;
    }
    lua.lua_pushinteger(L, @as(i64, @intCast(totalsize)));
    return 1;
}

fn unpackint(L: *lua.lua_State, src: []const u8, size: usize, islittle: bool, issigned: bool) !i64 {
    var res: u64 = 0;
    const limit = @min(size, 8);
    var i: usize = 0;
    if (islittle) {
        while (i < limit) : (i += 1) {
            const shift: u6 = @truncate(i * 8);
            res |= @as(u64, src[i]) << shift;
        }
    } else {
        while (i < limit) : (i += 1) {
            res = (res << 8) | @as(u64, src[size - limit + i]);
        }
    }
    if (size < 8) {
        if (issigned) {
            const shift: u6 = @truncate(size * 8 - 1);
            const mask = @as(u64, 1) << shift;
            res = (res ^ mask) -% mask;
        }
    } else if (size > 8) {
        const res_i = @as(i64, @bitCast(res));
        const mask: u8 = if (!issigned or res_i >= 0) 0 else 0xFF;
        i = limit;
        while (i < size) : (i += 1) {
            const b = src[if (islittle) i else size - 1 - i];
            if (b != mask) {
                var buf: [128]u8 = undefined;
                const msg = std.fmt.bufPrint(&buf, "{d}-byte integer does not fit into Lua Integer", .{size}) catch "integer does not fit into Lua Integer";
                return lauxlib.luaL_error(L, msg);
            }
        }
    }
    return @as(i64, @bitCast(res));
}

pub fn str_unpack(L: *lua.lua_State) anyerror!i32 {
    var fmt_len: usize = 0;
    var data_len: usize = 0;
    const fmt = try lauxlib.luaL_checklstring(L, 1, &fmt_len);
    const data = try lauxlib.luaL_checklstring(L, 2, &data_len);
    const init_pos = posrelatI(lauxlib.luaL_optinteger(L, 3, 1), data_len);
    try lauxlib.luaL_argcheck(L, init_pos > 0 and init_pos <= data_len + 1, 3, "initial position out of string");
    var h: Header = undefined;
    initheader(L, &h);
    var data_offset: usize = @intCast(init_pos - 1);
    var n: i32 = 0;
    var pos: usize = 0;
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
            .signed, .unsigned => {
                const res = try unpackint(L, data[data_offset..], size, h.islittle, opt == .signed);
                lua.lua_pushinteger(L, res);
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
                const sl = try unpackint(L, data[data_offset..], size, h.islittle, false);
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
            .padding, .paddalign => {},
            .max => break,
            else => {},
        }
        data_offset += size;
    }

    lua.lua_pushinteger(L, @as(i64, @intCast(data_offset + 1)));
    return n + 1;
}
