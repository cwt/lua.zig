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

fn trymt(L: *lua.lua_State, mtkey: []const u8, opname: []const u8) !i32 {
    lua.lua_settop(L, 2);
    if (lua.lua_type(L, 2) == lua.LUA_TSTRING or lauxlib.luaL_getmetafield(L, 2, mtkey) == 0) {
        var buf: [128]u8 = undefined;
        const tname1 = try lauxlib.luaL_typename(L, 1);
        const tname2 = try lauxlib.luaL_typename(L, 2);
        const msg = std.fmt.bufPrint(&buf, "attempt to {s} a '{s}' with a '{s}'", .{
            opname,
            tname1,
            tname2,
        }) catch "attempt to perform arithmetic";
        return lauxlib.luaL_error(L, msg);
    }
    lua.lua_insert(L, -3);
    try lua.lua_callk(L, 2, 1, 0, null);
    return 1;
}

fn tonum(L: *lua.lua_State, arg: i32) bool {
    const t = lua.lua_type(L, arg);
    if (t == lua.LUA_TNUMBER) {
        lua.lua_pushvalue(L, arg);
        return true;
    }
    if (t == lua.LUA_TSTRING) {
        const s = lua.lua_tostring(L, arg) orelse "";
        return lua.lua_stringtonumber(L, s) != 0;
    }
    return false;
}

fn arith(L: *lua.lua_State, op: i32, mtkey: []const u8, opname: []const u8) !i32 {
    if (tonum(L, 1) and tonum(L, 2)) {
        try lua.lua_arith(L, op);
        return 1;
    } else {
        return try trymt(L, mtkey, opname);
    }
}

fn arith_add(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPADD, "__add", "add");
}
fn arith_sub(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPSUB, "__sub", "sub");
}
fn arith_mul(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPMUL, "__mul", "mul");
}
fn arith_mod(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPMOD, "__mod", "perform arithmetic on");
}
fn arith_pow(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPPOW, "__pow", "perform arithmetic on");
}
fn arith_div(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPDIV, "__div", "perform arithmetic on");
}
fn arith_idiv(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPIDIV, "__idiv", "perform arithmetic on");
}
fn arith_unm(L: *lua.lua_State) anyerror!i32 {
    return arith(L, lua.LUA_OPUNM, "__unm", "perform arithmetic on");
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
