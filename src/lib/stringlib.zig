// $Id: stringlib.zig $
// String library entrypoint for Lua.zig
// See Copyright Notice in lua.h

const std = @import("std");
const lua = @import("../lua.zig");
const lauxlib = @import("../lauxlib.zig");
const libm = @import("../libm.zig");

const format = @import("string/format.zig");
const pattern = @import("string/pattern.zig");
const pack = @import("string/pack.zig");

// Re-expose posrelatI and getendpos from pattern for internal use or local consistency
const posrelatI = pattern.posrelatI;
const getendpos = pattern.getendpos;

fn str_len(L: *lua.lua_State) anyerror!i32 {
    var l: usize = 0;
    _ = try lauxlib.luaL_checklstring(L, 1, &l);
    lua.lua_pushinteger(L, @as(i64, @intCast(l)));
    return 1;
}

fn str_sub(L: *lua.lua_State) anyerror!i32 {
    var l: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &l);
    const start = posrelatI(try lauxlib.luaL_checkinteger(L, 2), l);
    const end = getendpos(L, 3, -1, l);
    if (start <= end) {
        _ = lua.lua_pushlstring(L, s[start - 1 .. end], end - start + 1);
    } else {
        _ = lua.lua_pushlstring(L, "", 0);
    }
    return 1;
}

fn str_reverse(L: *lua.lua_State) anyerror!i32 {
    var l: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &l);
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);

    errdefer b.buf.deinit(L.allocator);
    const p = try lauxlib.luaL_prepbuffsize(L, &b, l);
    var i: usize = 0;
    while (i < l) : (i += 1) {
        p[i] = s[l - i - 1];
    }
    lauxlib.luaL_addsize(&b, l);
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

fn str_lower(L: *lua.lua_State) anyerror!i32 {
    var l: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &l);
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);

    errdefer b.buf.deinit(L.allocator);
    const p = try lauxlib.luaL_prepbuffsize(L, &b, l);
    var i: usize = 0;
    while (i < l) : (i += 1) {
        p[i] = std.ascii.toLower(s[i]);
    }
    lauxlib.luaL_addsize(&b, l);
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

fn str_upper(L: *lua.lua_State) anyerror!i32 {
    var l: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &l);
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);

    errdefer b.buf.deinit(L.allocator);
    const p = try lauxlib.luaL_prepbuffsize(L, &b, l);
    var i: usize = 0;
    while (i < l) : (i += 1) {
        p[i] = std.ascii.toUpper(s[i]);
    }
    lauxlib.luaL_addsize(&b, l);
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

fn str_rep(L: *lua.lua_State) anyerror!i32 {
    var len: usize = 0;
    var lsep: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &len);
    const n = try lauxlib.luaL_checkinteger(L, 2);
    const sep = (try lauxlib.luaL_optlstring(L, 3, "", &lsep)) orelse "";
    if (n <= 0 or (len | lsep) == 0) {
        _ = lua.lua_pushlstring(L, "", 0);
        return 1;
    }
    const MAX_SIZE = @min(std.math.maxInt(usize) / 2, @as(usize, @intCast(std.math.maxInt(i64))));
    const un = @as(u64, @intCast(n));
    if (len > MAX_SIZE -| lsep or (len + lsep) > MAX_SIZE / un) {
        return lauxlib.luaL_error(L, "resulting string too large");
    }
    const totallen = un * (@as(u64, @intCast(len)) + @as(u64, @intCast(lsep))) - @as(u64, @intCast(lsep));
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);

    errdefer b.buf.deinit(L.allocator);
    const p = try lauxlib.luaL_prepbuffsize(L, &b, @intCast(totallen));
    var pos: usize = 0;
    var remaining = n;
    while (remaining > 1) : (remaining -= 1) {
        @memcpy(p[pos..][0..len], s);
        pos += len;
        if (lsep > 0) {
            @memcpy(p[pos..][0..lsep], sep);
            pos += lsep;
        }
    }
    @memcpy(p[pos..][0..len], s);
    lauxlib.luaL_addsize(&b, @intCast(totallen));
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

fn str_byte(L: *lua.lua_State) anyerror!i32 {
    var l: usize = 0;
    const s = try lauxlib.luaL_checklstring(L, 1, &l);
    const pi = lauxlib.luaL_optinteger(L, 2, 1);
    const posi = posrelatI(pi, l);
    const pose = getendpos(L, 3, pi, l);
    if (posi > pose) return 0;
    if (pose - posi >= @as(usize, @intCast(std.math.maxInt(i32)))) {
        return lauxlib.luaL_error(L, "string slice too long");
    }
    const n = pose - posi + 1;
    try lauxlib.luaL_checkstack(L, @as(i32, @intCast(n)), "string slice too long");
    var i: usize = 0;
    while (i < n) : (i += 1) {
        lua.lua_pushinteger(L, @as(i64, @intCast(s[posi + i - 1])));
    }
    return @as(i32, @intCast(n));
}

fn str_char(L: *lua.lua_State) anyerror!i32 {
    const n = lua.lua_gettop(L);
    var b = lauxlib.luaL_Buffer{};
    lauxlib.luaL_buffinit(L, &b);

    errdefer b.buf.deinit(L.allocator);
    const p = try lauxlib.luaL_prepbuffsize(L, &b, @as(usize, @intCast(n)));
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        const c = try lauxlib.luaL_checkinteger(L, i);
        if (c < 0 or c > 255) {
            return lauxlib.luaL_argerror(L, i, "value out of range");
        }
        p[@as(usize, @intCast(i - 1))] = @as(u8, @intCast(c));
    }
    lauxlib.luaL_addsize(&b, @as(usize, @intCast(n)));
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

fn dump_writer(L: *lua.lua_State, p: ?*anyopaque, size: usize, ud: ?*anyopaque) i32 {
    const b = @as(*lauxlib.luaL_Buffer, @ptrCast(@alignCast(ud)));
    const buf = @as([*]const u8, @ptrCast(p))[0..size];
    lauxlib.luaL_addlstring(L, b, buf) catch return 1;
    return 0;
}

fn str_dump(L: *lua.lua_State) anyerror!i32 {
    const strip = lua.lua_toboolean(L, 2);
    if (lua.lua_type(L, 1) != lua.LUA_TFUNCTION or lua.lua_iscfunction(L, 1) != 0) {
        return lauxlib.luaL_argerror(L, 1, "Lua function expected");
    }
    var b: lauxlib.luaL_Buffer = undefined;
    lauxlib.luaL_buffinit(L, &b);
    // Ensure the function is on top of the stack (lua_dump reads top-1).
    lua.lua_pushvalue(L, 1);
    const status = lua.lua_dump(L, dump_writer, &b, strip);
    if (status != lua.LUA_OK) {
        // A writer error (or a non-dumpable value) occurred. Propagate.
        return lauxlib.luaL_error(L, "cannot dump given function");
    }
    lua.lua_settop(L, 1);
    lauxlib.luaL_pushresult(L, &b);
    return 1;
}

const strlib = [_]struct {
    name: []const u8,
    func: lua.lua_CFunction,
}{
    .{ .name = "byte", .func = str_byte },
    .{ .name = "char", .func = str_char },
    .{ .name = "dump", .func = str_dump },
    .{ .name = "find", .func = pattern.str_find },
    .{ .name = "format", .func = format.str_format },
    .{ .name = "gmatch", .func = pattern.gmatch },
    .{ .name = "gsub", .func = pattern.str_gsub },
    .{ .name = "len", .func = str_len },
    .{ .name = "lower", .func = str_lower },
    .{ .name = "match", .func = pattern.str_match },
    .{ .name = "rep", .func = str_rep },
    .{ .name = "reverse", .func = str_reverse },
    .{ .name = "sub", .func = str_sub },
    .{ .name = "upper", .func = str_upper },
    .{ .name = "pack", .func = pack.str_pack },
    .{ .name = "packsize", .func = pack.str_packsize },
    .{ .name = "unpack", .func = pack.str_unpack },
};

fn arith(L: *lua.lua_State, op: i32) anyerror!i32 {
    // Convert both operands to numbers if they are strings, pushing the
    // converted values on top WITHOUT mutating the original slots (the
    // reference 'tonum' pushes a copy and leaves the caller's variables
    // untouched). The two top slots are then the operands for arithmetic.
    // Helper: push a numeric copy of the operand at `arg` on top, without
    // mutating the original slot (string → converted number; number → copy).
    const numMod = struct {
        fn call(a: f64, b: f64) f64 {
            var m = libm.getLibm().fmod(a, b);
            if (if (m > 0) b < 0 else (m < 0 and b > 0)) {
                m += b;
            }
            return m;
        }
    }.call;
    const pushOperand = struct {
        fn call(l: *lua.lua_State, arg: i32) !void {
            const t = lua.lua_type(l, arg);
            if (t == lua.LUA_TSTRING) {
                const s = lua.lua_tostring(l, arg) orelse "";
                if (lua.lua_stringtonumber(l, s) == 0) {
                    return lauxlib.luaL_error(l, "attempt to perform arithmetic on a string value");
                }
            } else if (t != lua.LUA_TNUMBER) {
                return lauxlib.luaL_error(l, "attempt to perform arithmetic on a string value");
            } else {
                lua.lua_pushvalue(l, arg);
            }
        }
    }.call;
    try pushOperand(L, 1);
    try pushOperand(L, 2);
    // Slots -2 and -1 now hold numeric copies of the operands.
    const top = lua.lua_gettop(L);
    const is_int1 = lua.lua_isinteger(L, top - 1);
    const is_int2 = lua.lua_isinteger(L, top);
    if (is_int1 != 0 and is_int2 != 0) {
        const iv1 = lua.lua_tointeger(L, top - 1) orelse 0;
        const iv2 = lua.lua_tointeger(L, top) orelse 0;
        const result = switch (op) {
            lua.LUA_OPADD => iv1 +% iv2,
            lua.LUA_OPSUB => iv1 -% iv2,
            lua.LUA_OPMUL => iv1 *% iv2,
            lua.LUA_OPMOD => blk: {
                if (iv2 == 0) return lauxlib.luaL_error(L, "attempt to divide by zero");
                const r = if (iv2 == -1) @as(i64, 0) else @rem(iv1, iv2);
                break :blk if (r != 0 and (r ^ iv2) < 0) r + iv2 else r;
            },
            lua.LUA_OPPOW => @as(i64, @intFromFloat(@floor(@as(f64, @floatFromInt(iv1)) / @as(f64, @floatFromInt(iv2))))),
            lua.LUA_OPDIV => @as(i64, @intFromFloat(@as(f64, @floatFromInt(iv1)) / @as(f64, @floatFromInt(iv2)))),
            lua.LUA_OPIDIV => blk: {
                const ib = iv1;
                const ic = iv2;
                if (ic == 0) return lauxlib.luaL_error(L, "attempt to divide by zero");
                const q: i64 = if (ic == -1) 0 -% ib else @divTrunc(ib, ic);
                const r: i64 = if (ic == -1) 0 else @rem(ib, ic);
                break :blk if (r == 0 or (ib >= 0) == (ic >= 0)) q else q - 1;
            },
            lua.LUA_OPBAND => iv1 & iv2,
            lua.LUA_OPBOR => iv1 | iv2,
            lua.LUA_OPBXOR => iv1 ^ iv2,
            lua.LUA_OPSHL => lua.luaV_shift(iv1, iv2),
            lua.LUA_OPSHR => lua.luaV_shift(iv1, -%iv2),
            lua.LUA_OPUNM => -iv1,
            else => return lauxlib.luaL_error(L, "unsupported arithmetic operation"),
        };
        lua.lua_pushinteger(L, result);
    } else {
        const fv1 = lua.lua_tonumber(L, top - 1) orelse 0.0;
        const fv2 = lua.lua_tonumber(L, top) orelse 0.0;
        const result = switch (op) {
            lua.LUA_OPADD => fv1 + fv2,
            lua.LUA_OPSUB => fv1 - fv2,
            lua.LUA_OPMUL => fv1 * fv2,
            lua.LUA_OPMOD => blk: {
                break :blk numMod(fv1, fv2);
            },
            lua.LUA_OPPOW => std.math.pow(f64, fv1, fv2),
            lua.LUA_OPDIV => fv1 / fv2,
            lua.LUA_OPIDIV => blk: {
                break :blk @floor(fv1 / fv2);
            },
            lua.LUA_OPUNM => -fv1,
            else => return lauxlib.luaL_error(L, "unsupported arithmetic operation"),
        };
        lua.lua_pushnumber(L, result);
    }
    // `top` holds the second operand copy; the result was just pushed on top
    // (slot top+1). Move the result down onto the second operand's slot and
    // truncate, leaving exactly one value (the result) on top for the caller.
    lua.lua_replace(L, top);
    lua.lua_settop(L, top);
    return 1;
}

fn arith_add(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPADD);
}
fn arith_sub(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPSUB);
}
fn arith_mul(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPMUL);
}
fn arith_mod(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPMOD);
}
fn arith_pow(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPPOW);
}
fn arith_div(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPDIV);
}
fn arith_idiv(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPIDIV);
}
fn arith_unm(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPUNM);
}

const stringmetamethods = [_]lauxlib.luaL_Reg{
    .{ .name = "__add", .func = arith_add },
    .{ .name = "__sub", .func = arith_sub },
    .{ .name = "__mul", .func = arith_mul },
    .{ .name = "__mod", .func = arith_mod },
    .{ .name = "__pow", .func = arith_pow },
    .{ .name = "__div", .func = arith_div },
    .{ .name = "__idiv", .func = arith_idiv },
    .{ .name = "__unm", .func = arith_unm },
};

fn createmetatable(L: *lua.lua_State) !void {
    lua.lua_createtable(L, 0, @as(i32, @intCast(stringmetamethods.len + 1)));
    for (&stringmetamethods) |reg| {
        lua.lua_pushcfunction(L, reg.func);
        try lua.lua_setfield(L, -2, reg.name);
    }
    lua.lua_pushvalue(L, -2);
    try lua.lua_setfield(L, -2, "__index");
    _ = lua.lua_pushlstring(L, "", 0);
    lua.lua_pushvalue(L, -2);
    _ = lua.lua_setmetatable(L, -2);
    lua.lua_pop(L, 2);
}

pub fn openstringlib(L: *lua.lua_State) anyerror!i32 {
    lua.lua_createtable(L, 0, @as(i32, @intCast(strlib.len)));
    for (&strlib) |reg| {
        lua.lua_pushcfunction(L, reg.func);
        try lua.lua_setfield(L, -2, reg.name);
    }
    try createmetatable(L);
    return 1;
}
