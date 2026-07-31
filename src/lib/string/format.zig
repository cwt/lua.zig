// $Id: format.zig $
// String formatting engine for Lua.zig
// See Copyright Notice in lua.h

const std = @import("std");
const lua = @import("../../lua.zig");
const lauxlib = @import("../../lauxlib.zig");
const libm = @import("../../libm.zig");

fn get2digits(s: []const u8, pos: usize) struct { val: i32, new_pos: usize } {
    var val: i32 = 0;
    var p = pos;
    if (p < s.len and std.ascii.isDigit(s[p])) {
        val = @as(i32, @intCast(s[p] - '0'));
        p += 1;
    }
    if (p < s.len and std.ascii.isDigit(s[p])) {
        val = val * 10 + @as(i32, @intCast(s[p] - '0'));
        p += 1;
    }
    return .{ .val = val, .new_pos = p };
}

fn intToString(comptime val: usize) []const u8 {
    if (val == 0) return "0";
    var res: []const u8 = "";
    var temp = val;
    while (temp > 0) {
        const digit_char = &[_]u8{ '0' + @as(u8, @intCast(temp % 10)) };
        res = digit_char ++ res;
        temp /= 10;
    }
    return res;
}

fn formatFloatF(buf: []u8, abs_val: f64, precision: usize) ![]const u8 {
    const fmts = comptime blk: {
        var arr: [101][]const u8 = undefined;
        for (0..101) |i| {
            arr[i] = "{d:." ++ intToString(i) ++ "}";
        }
        break :blk arr;
    };
    const prec = if (precision > 100) 100 else precision;
    inline for (0..101) |i| {
        if (prec == i) {
            return try std.fmt.bufPrint(buf, fmts[i], .{abs_val});
        }
    }
    return error.NoSpaceLeft;
}

fn formatFloatE(buf: []u8, abs_val: f64, spec: u8, precision: usize) ![]const u8 {
    const fmts = comptime blk: {
        var arr: [101][]const u8 = undefined;
        for (0..101) |i| {
            arr[i] = "{e:." ++ intToString(i) ++ "}";
        }
        break :blk arr;
    };
    const prec = if (precision > 100) 100 else precision;
    var raw: []const u8 = "";
    var raw_buf: [150]u8 = undefined;
    inline for (0..101) |i| {
        if (prec == i) {
            raw = try std.fmt.bufPrint(&raw_buf, fmts[i], .{abs_val});
        }
    }
    if (raw.len == 0) return error.NoSpaceLeft;
    
    var out_buf: [150]u8 = undefined;
    var len: usize = 0;
    var e_idx: ?usize = null;
    for (raw, 0..) |c, idx| {
        if (c == 'e') {
            e_idx = idx;
            break;
        }
    }
    
    if (e_idx) |ei| {
        @memcpy(out_buf[0..ei], raw[0..ei]);
        len = ei;
        out_buf[len] = if (spec == 'E' or spec == 'G') 'E' else 'e';
        len += 1;
        const exp_str = raw[ei+1..];
        var exp_sign: u8 = '+';
        var exp_val_str = exp_str;
        if (exp_str.len > 0 and (exp_str[0] == '-' or exp_str[0] == '+')) {
            exp_sign = exp_str[0];
            exp_val_str = exp_str[1..];
        }
        out_buf[len] = exp_sign;
        len += 1;
        if (exp_val_str.len == 1) {
            out_buf[len] = '0';
            out_buf[len+1] = exp_val_str[0];
            len += 2;
        } else {
            @memcpy(out_buf[len..][0..exp_val_str.len], exp_val_str);
            len += exp_val_str.len;
        }
    } else {
        @memcpy(out_buf[0..raw.len], raw);
        len = raw.len;
    }
    if (len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[0..len], out_buf[0..len]);
    return buf[0..len];
}

fn formatFloatG(buf: []u8, abs_val: f64, spec: u8, precision: usize, strip_zeros: bool) ![]const u8 {
    if (std.math.isNan(abs_val)) {
        return if (spec == 'G') "NAN" else "nan";
    }
    if (std.math.isInf(abs_val)) {
        return if (spec == 'G') "INF" else "inf";
    }
    if (abs_val == 0.0) {
        if (strip_zeros) return "0";
        return try formatFloatF(buf, 0.0, precision - 1);
    }
    const log10_val = libm.getLibm().log10(abs_val);
    const exponent = @as(i32, @intCast(@as(i64, @intFromFloat(std.math.floor(log10_val)))));
    const p = if (precision == 0) @as(usize, 1) else precision;
    var temp_buf: [150]u8 = undefined;
    var raw: []const u8 = "";
    if (exponent < -4 or exponent >= p) {
        const prec_e = p - 1;
        raw = try formatFloatE(&temp_buf, abs_val, spec, prec_e);
    } else {
        const dec_places = @as(i32, @intCast(p)) - 1 - exponent;
        if (dec_places > 0) {
            raw = try formatFloatF(&temp_buf, abs_val, @intCast(dec_places));
        } else {
            raw = try formatFloatF(&temp_buf, abs_val, 0);
        }
    }
    var out_buf: [150]u8 = undefined;
    @memcpy(out_buf[0..raw.len], raw);
    var len = raw.len;
    if (strip_zeros) {
        var exp_idx: ?usize = null;
        for (out_buf[0..len], 0..) |c, i| {
            if (c == 'e' or c == 'E') {
                exp_idx = i;
                break;
            }
        }
        const end_frac = exp_idx orelse len;
        var dot_idx: ?usize = null;
        for (out_buf[0..end_frac], 0..) |c, i| {
            if (c == '.') {
                dot_idx = i;
                break;
            }
        }
        if (dot_idx) |di| {
            var new_end_frac = end_frac;
            while (new_end_frac > di + 1 and out_buf[new_end_frac - 1] == '0') {
                new_end_frac -= 1;
            }
            if (new_end_frac == di + 1) {
                new_end_frac = di;
            }
            if (exp_idx) |ei| {
                const exp_len = len - ei;
                std.mem.copyForwards(u8, out_buf[new_end_frac..][0..exp_len], out_buf[ei..][0..exp_len]);
                len = new_end_frac + exp_len;
            } else {
                len = new_end_frac;
            }
        }
    }
    if (len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[0..len], out_buf[0..len]);
    return buf[0..len];
}

fn formatFloatA(buf: []u8, abs_val: f64, spec: u8, precision: ?usize) ![]const u8 {
    var raw: []const u8 = "";
    var temp_buf: [150]u8 = undefined;
    if (precision) |p| {
        const fmts = comptime blk: {
            var arr: [101][]const u8 = undefined;
            for (0..101) |i| {
                arr[i] = "{x:." ++ intToString(i) ++ "}";
            }
            break :blk arr;
        };
        const prec = if (p > 100) 100 else p;
        inline for (0..101) |i| {
            if (prec == i) {
                raw = try std.fmt.bufPrint(&temp_buf, fmts[i], .{abs_val});
            }
        }
    } else {
        raw = try std.fmt.bufPrint(&temp_buf, "{x}", .{abs_val});
    }
    if (raw.len == 0) return error.NoSpaceLeft;
    
    var out_buf: [150]u8 = undefined;
    var len: usize = 0;
    var p_idx: ?usize = null;
    for (raw, 0..) |c, i| {
        if (c == 'p' or c == 'P') {
            p_idx = i;
            break;
        }
    }
    
    if (p_idx) |pi| {
        @memcpy(out_buf[0..pi], raw[0..pi]);
        len = pi;
        out_buf[len] = if (spec == 'A') 'P' else 'p';
        len += 1;
        const exp_str = raw[pi+1..];
        if (exp_str.len > 0 and exp_str[0] != '+' and exp_str[0] != '-') {
            out_buf[len] = '+';
            len += 1;
        }
        @memcpy(out_buf[len..][0..exp_str.len], exp_str);
        len += exp_str.len;
    } else {
        @memcpy(out_buf[0..raw.len], raw);
        len = raw.len;
    }
    
    if (spec == 'A') {
        if (len >= 2 and out_buf[0] == '0' and out_buf[1] == 'x') {
            out_buf[1] = 'X';
        }
        const hex_end = p_idx orelse len;
        for (out_buf[2..hex_end]) |*c| {
            c.* = std.ascii.toUpper(c.*);
        }
    }
    
    if (len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[0..len], out_buf[0..len]);
    return buf[0..len];
}

fn formatFloat(buf: []u8, val: f64, spec: u8, flags: u8, precision: ?usize) ![]const u8 {
    var prefix: []const u8 = "";
    const is_neg = std.math.signbit(val);
    if (is_neg) {
        prefix = "-";
    } else {
        if ((flags & 2) != 0) { // '+'
            prefix = "+";
        } else if ((flags & 4) != 0) { // ' '
            prefix = " ";
        }
    }
    const abs_val = @abs(val);
    var val_buf: [150]u8 = undefined;
    var raw: []const u8 = "";
    const prec = precision orelse 6;
    switch (spec) {
        'f' => {
            raw = try formatFloatF(&val_buf, abs_val, prec);
        },
        'e', 'E' => {
            raw = try formatFloatE(&val_buf, abs_val, spec, prec);
        },
        'g', 'G' => {
            const strip_zeros = (flags & 8) == 0;
            raw = try formatFloatG(&val_buf, abs_val, spec, prec, strip_zeros);
        },
        'a', 'A' => {
            raw = try formatFloatA(&val_buf, abs_val, spec, precision);
        },
        else => unreachable,
    }
    const total_len = prefix.len + raw.len;
    if (total_len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[0..prefix.len], prefix);
    @memcpy(buf[prefix.len..][0..raw.len], raw);
    return buf[0..total_len];
}

fn formatInteger(buf: []u8, val: i64, spec: u8, flags: u8, precision: ?usize) ![]const u8 {
    var prefix: []const u8 = "";
    var abs_val: u64 = undefined;
    if (spec == 'd' or spec == 'i') {
        if (val < 0) {
            prefix = "-";
            abs_val = @as(u64, @bitCast(-%val));
        } else {
            if ((flags & 2) != 0) { // '+'
                prefix = "+";
            } else if ((flags & 4) != 0) { // ' '
                prefix = " ";
            }
            abs_val = @as(u64, @intCast(val));
        }
    } else {
        abs_val = @as(u64, @bitCast(val));
        if ((flags & 8) != 0 and abs_val != 0) { // '#'
            if (spec == 'x') {
                prefix = "0x";
            } else if (spec == 'X') {
                prefix = "0X";
            } else if (spec == 'o') {
                prefix = "0";
            }
        }
    }
    var digits_buf: [100]u8 = undefined;
    var digits: []const u8 = "";
    if (abs_val == 0 and precision == 0) {
        digits = "";
    } else {
        const base: u8 = switch (spec) {
            'o' => 8,
            'x', 'X' => 16,
            else => 10,
        };
        const case: std.fmt.Case = if (spec == 'X') .upper else .lower;
        const len = std.fmt.printInt(&digits_buf, abs_val, base, case, .{});
        digits = digits_buf[0..len];
    }
    var prec_digits_buf: [150]u8 = undefined;
    var prec_digits = digits;
    if (precision) |p| {
        if (digits.len < p) {
            const pad_len = p - digits.len;
            @memset(prec_digits_buf[0..pad_len], '0');
            @memcpy(prec_digits_buf[pad_len..][0..digits.len], digits);
            prec_digits = prec_digits_buf[0..p];
        }
    }
    const total_len = prefix.len + prec_digits.len;
    if (total_len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[0..prefix.len], prefix);
    @memcpy(buf[prefix.len..][0..prec_digits.len], prec_digits);
    return buf[0..total_len];
}

fn getPrefixLen(s: []const u8) usize {
    if (s.len >= 3) {
        const p3 = s[0..3];
        if (std.mem.eql(u8, p3, "-0x") or std.mem.eql(u8, p3, "-0X") or
            std.mem.eql(u8, p3, "+0x") or std.mem.eql(u8, p3, "+0X") or
            std.mem.eql(u8, p3, " 0x") or std.mem.eql(u8, p3, " 0X")) {
            return 3;
        }
    }
    if (s.len >= 2) {
        const p2 = s[0..2];
        if (std.mem.eql(u8, p2, "0x") or std.mem.eql(u8, p2, "0X")) {
            return 2;
        }
    }
    if (s.len >= 1) {
        const c = s[0];
        if (c == '-' or c == '+' or c == ' ') {
            return 1;
        }
    }
    return 0;
}

fn padAndAlign(L: *lua.lua_State, b: *lauxlib.luaL_Buffer, content: []const u8, flags: u8, width: ?usize, is_int: bool, has_precision: bool) !void {
    if (width) |w| {
        if (content.len < w) {
            const pad_len = w - content.len;
            const use_zero_pad = ((flags & 16) != 0) and ((flags & 1) == 0) and (!is_int or !has_precision);
            if (use_zero_pad) {
                const pl = getPrefixLen(content);
                try lauxlib.luaL_addlstring(L, b, content[0..pl]);
                var i: usize = 0;
                while (i < pad_len) : (i += 1) try lauxlib.luaL_addchar(L, b, '0');
                try lauxlib.luaL_addlstring(L, b, content[pl..]);
            } else {
                if ((flags & 1) != 0) { // left aligned
                    try lauxlib.luaL_addlstring(L, b, content);
                    var i: usize = 0;
                    while (i < pad_len) : (i += 1) try lauxlib.luaL_addchar(L, b, ' ');
                } else { // right aligned
                    var i: usize = 0;
                    while (i < pad_len) : (i += 1) try lauxlib.luaL_addchar(L, b, ' ');
                    try lauxlib.luaL_addlstring(L, b, content);
                }
            }
            return;
        }
    }
    try lauxlib.luaL_addlstring(L, b, content);
}

fn addquoted(L: *lua.lua_State, b: *lauxlib.luaL_Buffer, s: []const u8, len: usize) !void {
    try lauxlib.luaL_addchar(L, b, '"');
    var i: usize = 0;
    while (i < len) : (i += 1) {
        const c = s[i];
        if (c == '"' or c == '\\' or c == '\n') {
            try lauxlib.luaL_addchar(L, b, '\\');
            try lauxlib.luaL_addchar(L, b, c);
        } else if (std.ascii.isControl(c)) {
            var buff: [10]u8 = undefined;
            var nb: usize = 0;
            const next_is_digit = (i + 1 < len) and std.ascii.isDigit(s[i + 1]);
            if (!next_is_digit) {
                const slice = try std.fmt.bufPrint(&buff, "\\{d}", .{c});
                nb = slice.len;
            } else {
                const slice = try std.fmt.bufPrint(&buff, "\\{d:0>3}", .{c});
                nb = slice.len;
            }
            try lauxlib.luaL_addlstring(L, b, buff[0..nb]);
        } else {
            try lauxlib.luaL_addchar(L, b, c);
        }
    }
    try lauxlib.luaL_addchar(L, b, '"');
}

fn quotefloat(buf: []u8, n: f64) ![]const u8 {
    if (std.math.isInf(n)) {
        return if (n > 0) "1e9999" else "-1e9999";
    }
    if (std.math.isNan(n)) {
        return "(0/0)";
    }
    var temp_buf: [150]u8 = undefined;
    const hex_float = try formatFloatA(&temp_buf, @abs(n), 'a', null);
    
    var prefix: []const u8 = "";
    if (std.math.signbit(n)) {
        prefix = "-";
    }
    
    if (prefix.len + hex_float.len > buf.len) return error.NoSpaceLeft;
    @memcpy(buf[0..prefix.len], prefix);
    @memcpy(buf[prefix.len..][0..hex_float.len], hex_float);
    return buf[0..prefix.len + hex_float.len];
}

fn addliteral(L: *lua.lua_State, b: *lauxlib.luaL_Buffer, arg: i32) !void {
    switch (lua.lua_type(L, arg)) {
        lua.LUA_TNIL, lua.LUA_TBOOLEAN => {
            var len: usize = 0;
            _ = lauxlib.luaL_tolstring(L, arg, &len);
            try lauxlib.luaL_addvalue(L, b);
        },
        lua.LUA_TNUMBER => {
            if (lua.lua_isinteger(L, arg) != 0) {
                const n = lua.lua_tointeger(L, arg) orelse 0;
                var buf: [100]u8 = undefined;
                var s: []const u8 = "";
                if (n == std.math.minInt(i64)) {
                    s = try std.fmt.bufPrint(&buf, "0x{x}", .{@as(u64, @bitCast(n))});
                } else {
                    s = try std.fmt.bufPrint(&buf, "{d}", .{n});
                }
                try lauxlib.luaL_addlstring(L, b, s);
            } else {
                const n = lua.lua_tonumber(L, arg) orelse 0.0;
                var buf: [150]u8 = undefined;
                const s = try quotefloat(&buf, n);
                try lauxlib.luaL_addlstring(L, b, s);
            }
        },
        lua.LUA_TSTRING => {
            var len: usize = 0;
            const s = lua.lua_tolstring(L, arg, &len) orelse "";
            try addquoted(L, b, s, len);
        },
        else => {
            return lauxlib.luaL_argerror(L, arg, "value has no literal form");
        },
    }
}

pub fn str_format(L: *lua.lua_State) anyerror!i32 {
    var len: usize = 0;
    const raw_strfrmt = try lauxlib.luaL_checklstring(L, 1, &len);
    const strfrmt = try L.allocator.dupe(u8, raw_strfrmt);
    defer L.allocator.free(strfrmt);

    var pos: usize = 0;
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);

    errdefer b.buf.deinit(L.allocator);
    var argn: i32 = 2;
    const top = lua.lua_gettop(L);
    
    while (pos < len) {
        const start = pos;
        while (pos < len and strfrmt[pos] != '\x00' and strfrmt[pos] != '%') {
            pos += 1;
        }
        if (pos > start) {
            try lauxlib.luaL_addlstring(L, &b, strfrmt[start..pos]);
        }
        if (pos >= len) break;
        const c = strfrmt[pos];
        if (c == '\x00') {
            pos += 1;
            continue;
        }
        pos += 1;
        if (pos >= len) return lauxlib.luaL_error(L, "malformed format string");

        if (strfrmt[pos] == '%') {
            try lauxlib.luaL_addchar(L, &b, '%');
            pos += 1;
            continue;
        }

        if (argn > top) return lauxlib.luaL_error(L, "no value for format");

        var flags: u8 = 0;
        while (pos < len) {
            const fc = strfrmt[pos];
            switch (fc) {
                '-' => flags |= 1,
                '+' => flags |= 2,
                ' ' => flags |= 4,
                '#' => flags |= 8,
                '0' => flags |= 16,
                else => break,
            }
            pos += 1;
        }

        var width: i64 = -1;
        if (pos < len and std.ascii.isDigit(strfrmt[pos])) {
            const res = get2digits(strfrmt, pos);
            width = @intCast(res.val);
            pos = res.new_pos;
        }

        var precision: i64 = -1;
        if (pos < len and strfrmt[pos] == '.') {
            pos += 1;
            if (pos < len and std.ascii.isDigit(strfrmt[pos])) {
                const res = get2digits(strfrmt, pos);
                precision = @intCast(res.val);
                pos = res.new_pos;
            } else {
                precision = 0;
            }
        }

        if (pos >= len) return lauxlib.luaL_error(L, "malformed format string");

        const spec = strfrmt[pos];
        pos += 1;

        switch (spec) {
            'c' => {
                const c_val = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                if (c_val < 0 or c_val > 255) {
                    return lauxlib.luaL_argerror(L, argn - 1, "value out of range");
                }
                const cv = @as(u8, @intCast(c_val));
                const char_slice = &[1]u8{cv};
                const w = if (width >= 0) @as(usize, @intCast(width)) else null;
                try padAndAlign(L, &b, char_slice, flags, w, false, false);
            },
            'd', 'i' => {
                const n = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                var ibuf: [150]u8 = undefined;
                const prec_val = if (precision >= 0) @as(usize, @intCast(precision)) else null;
                const s_slice = try formatInteger(&ibuf, n, spec, flags, prec_val);
                const w = if (width >= 0) @as(usize, @intCast(width)) else null;
                try padAndAlign(L, &b, s_slice, flags, w, true, precision >= 0);
            },
            'o', 'u', 'x', 'X' => {
                const n = try lauxlib.luaL_checkinteger(L, argn);
                argn += 1;
                var ibuf: [150]u8 = undefined;
                const prec_val = if (precision >= 0) @as(usize, @intCast(precision)) else null;
                const s_slice = try formatInteger(&ibuf, n, spec, flags, prec_val);
                const w = if (width >= 0) @as(usize, @intCast(width)) else null;
                try padAndAlign(L, &b, s_slice, flags, w, true, precision >= 0);
            },
            'f', 'e', 'E', 'g', 'G', 'a', 'A' => {
                const n = try lauxlib.luaL_checknumber(L, argn);
                argn += 1;
                var fbuf: [250]u8 = undefined;
                const prec_val = if (precision >= 0) @as(usize, @intCast(precision)) else null;
                const s_slice = try formatFloat(&fbuf, n, spec, flags, prec_val);
                const w = if (width >= 0) @as(usize, @intCast(width)) else null;
                try padAndAlign(L, &b, s_slice, flags, w, false, false);
            },
            'p' => {
                const p = lua.lua_topointer(L, argn);
                argn += 1;
                var ibuf: [100]u8 = undefined;
                var s_slice: []const u8 = "";
                if (p) |ptr| {
                    s_slice = try std.fmt.bufPrint(&ibuf, "0x{x}", .{@intFromPtr(ptr)});
                } else {
                    s_slice = "(null)";
                }
                const w = if (width >= 0) @as(usize, @intCast(width)) else null;
                try padAndAlign(L, &b, s_slice, flags, w, false, false);
            },
            'q' => {
                if (flags != 0 or width >= 0 or precision >= 0) {
                    return lauxlib.luaL_error(L, "specifier '%q' cannot have modifiers");
                }
                try addliteral(L, &b, argn);
                argn += 1;
            },
            's' => {
                var sl: usize = 0;
                const s = lauxlib.luaL_tolstring(L, argn, &sl) orelse "";
                argn += 1;
                if (flags == 0 and width == -1 and precision == -1) {
                    try lauxlib.luaL_addvalue(L, &b);
                } else {
                    if (std.mem.indexOfScalar(u8, s, 0) != null) {
                        return lauxlib.luaL_argerror(L, argn - 1, "string contains zeros");
                    }
                    var actual_s = s;
                    if (precision >= 0) {
                        const p = @as(usize, @intCast(precision));
                        if (actual_s.len > p) {
                            actual_s = actual_s[0..p];
                        }
                    }
                    const w = if (width >= 0) @as(usize, @intCast(width)) else null;
                    try padAndAlign(L, &b, actual_s, flags, w, false, false);
                    lua.lua_pop(L, 1);
                }
            },
            else => {
                return lauxlib.luaL_error(L, "invalid conversion to 'format'");
            },
        }
    }
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}
