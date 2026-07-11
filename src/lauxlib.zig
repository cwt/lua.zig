//
// ** $Id: lauxlib.zig
// ** Auxiliary library for Lua.zig (Zig port of Lua 5.5.1)
// ** See Copyright Notice in c_compat.zig
//

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");
const lualib = @import("lualib.zig");

// ===================================================================
// Table operations
// ===================================================================

pub fn luaL_newtable(L: *lua.lua_State) !void {
    _ = L;
}

pub fn luaL_setn(L: *lua.lua_State) !void {
    _ = L;
}

pub fn luaL_checktype(L: *lua.lua_State, idx: i32, t: i32) !void {
    const actual = lua.lua_type(L, idx);
    if (actual != t) {
        return error.WrongType;
    }
}

pub fn luaL_typename(L: *lua.lua_State, idx: i32) ![]const u8 {
    const actual_type = lua.lua_type(L, idx);
    return switch (actual_type) {
        lua.LUA_TNONE => "none",
        lua.LUA_TNIL => "nil",
        lua.LUA_TBOOLEAN => "boolean",
        lua.LUA_TLIGHTUSERDATA => "light userdata",
        lua.LUA_TNUMBER => "number",
        lua.LUA_TSTRING => "string",
        lua.LUA_TTABLE => "table",
        lua.LUA_TFUNCTION => "function",
        lua.LUA_TUSERDATA => "userdata",
        lua.LUA_TTHREAD => "thread",
        else => return error.UnknownType,
    };
}

pub fn luaL_len(L: *lua.lua_State, idx: i32) !usize {
    _ = L;
    _ = idx;
    return 0;
}

pub fn luaL_checkinteger(L: *lua.lua_State, idx: i32) !i64 {
    const n = lua.lua_tointeger(L, idx);
    if (n == null) return error.InvalidType;
    return n.?;
}

pub fn luaL_checklstring(L: *lua.lua_State, idx: i32, len: ?*usize) ![]const u8 {
    const s = lua.lua_tolstring(L, idx, len);
    return s orelse error.InvalidType;
}

pub fn luaL_checkany(L: *lua.lua_State, idx: i32) !void {
    if (lua.lua_type(L, idx) == lua.LUA_TNONE) {
        return luaL_argerror(L, idx, "value expected");
    }
}

pub fn luaL_optinteger(L: *lua.lua_State, idx: i32, def: i64) i64 {
    if (lua.lua_isnoneornil(L, idx)) return def;
    return luaL_checkinteger(L, idx) catch def;
}

pub fn luaL_checknumber(L: *lua.lua_State, idx: i32) !lua.lua_Number {
    const n = lua.lua_tonumber(L, idx);
    if (n == null) {
        if (lua.lua_type(L, idx) == lua.LUA_TNONE) {
            return luaL_argerror(L, idx, "value expected");
        }
        return luaL_typeerror(L, idx, "number");
    }
    return n.?;
}

pub fn luaL_optnumber(L: *lua.lua_State, idx: i32, def: lua.lua_Number) lua.lua_Number {
    if (lua.lua_isnoneornil(L, idx)) return def;
    return luaL_checknumber(L, idx) catch def;
}

pub fn luaL_pushfail(L: *lua.lua_State) void {
    lua.lua_pushnil(L);
}

pub fn luaL_argcheck(L: *lua.lua_State, cond: bool, arg: i32, msg: []const u8) !void {
    if (!cond) {
        return luaL_argerror(L, arg, msg);
    }
}

pub fn luaL_optlstring(L: *lua.lua_State, idx: i32, def: ?[]const u8, len: ?*usize) !?[]const u8 {
    if (lua.lua_isnoneornil(L, idx)) {
        if (len) |l| {
            l.* = if (def) |d| d.len else 0;
        }
        return def;
    }
    return try luaL_checklstring(L, idx, len);
}

pub fn luaL_getmetafield(L: *lua.lua_State, idx: i32, field: []const u8) i32 {
    if (lua.lua_getmetatable(L, idx) == 0) return lua.LUA_TNIL;
    _ = lua.lua_pushstring(L, field);
    const tt = lua.lua_rawget(L, -2);
    if (tt == lua.LUA_TNIL) {
        lua.lua_pop(L, 2);
        return lua.LUA_TNIL;
    }
    lua.lua_remove(L, -2);
    return tt;
}

pub fn luaL_checkoption(L: *lua.lua_State, idx: i32, def: []const u8, opts: [][]const u8) !i32 {
    const s = blk: {
        if (lua.lua_isnoneornil(L, idx)) {
            break :blk def;
        }
        break :blk try luaL_checklstring(L, idx, null);
    };
    for (opts, 0..) |opt, i| {
        if (std.mem.eql(u8, s, opt)) return @intCast(i);
    }
    return luaL_argerror(L, idx, "invalid option");
}

pub const luaL_Reg = struct {
    name: []const u8,
    func: lua.lua_CFunction,
};

pub fn luaL_register(L: *lua.lua_State, libname: []const u8, l: ?[]const luaL_Reg) !void {
    if (lua.lua_getglobal(L, libname) == 0) {
        lua.lua_newtable(L);
    }
    if (l) |funcs| {
        for (funcs) |reg| {
            lua.lua_pushcfunction(L, reg.func);
            lua.lua_setfield(L, -2, reg.name);
        }
    }
    lua.lua_setglobal(L, libname);
}

// ===================================================================
// Error handling
// ===================================================================

pub fn luaL_error(L: *lua.lua_State, msg: []const u8) anyerror {
    _ = lua.lua_pushstring(L, msg);
    return lua.lua_error(L);
}

pub fn luaL_argerror(L: *lua.lua_State, arg: i32, msg: []const u8) anyerror {
    var buf: [256]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "bad argument #{d} ({s})", .{ arg, msg }) catch msg;
    _ = lua.lua_pushstring(L, s);
    return lua.lua_error(L);
}

pub fn luaL_typeerror(L: *lua.lua_State, idx: i32, tname: []const u8) anyerror {
    const actual = lua.lua_typename(lua.lua_type(L, idx));
    var buf: [256]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{s} expected, got {s}", .{ tname, actual }) catch tname;
    return luaL_argerror(L, idx, s);
}

// ===================================================================
// Utility functions
// ===================================================================

pub fn luaL_checkstack(L: *lua.lua_State, n: i32, msg: []const u8) !void {
    _ = msg;
    if (lua.lua_checkstack(L, n) == 0) {
        return error.StackOverflow;
    }
}

pub fn luaL_tolstring(L: *lua.lua_State, idx: i32, len: ?*usize) ?[]const u8 {
    const actual_type = lua.lua_type(L, idx);
    switch (actual_type) {
        lua.LUA_TSTRING => return lua.lua_tolstring(L, idx, len),
        lua.LUA_TNUMBER => {
            var buf: [128]u8 = undefined;
            if (lua.lua_isinteger(L, idx) != 0) {
                const iv = lua.lua_tointeger(L, idx) orelse 0;
                const s = std.fmt.bufPrint(&buf, "{d}", .{iv}) catch return null;
                _ = lua.lua_pushstring(L, s);
            } else {
                const fv = lua.lua_tonumber(L, idx) orelse 0.0;
                const s = std.fmt.bufPrint(&buf, "{d}", .{fv}) catch return null;
                _ = lua.lua_pushstring(L, s);
            }
            return lua.lua_tolstring(L, -1, len);
        },
        lua.LUA_TBOOLEAN => {
            const b = lua.lua_toboolean(L, idx);
            const s: []const u8 = if (b != 0) "true" else "false";
            _ = lua.lua_pushstring(L, s);
            return lua.lua_tolstring(L, -1, len);
        },
        lua.LUA_TNIL => {
            _ = lua.lua_pushstring(L, "nil");
            return lua.lua_tolstring(L, -1, len);
        },
        else => {
            // For tables, functions, etc. push a pointer string
            var buf: [128]u8 = undefined;
            const ptr = lua.lua_topointer(L, idx);
            const tname = lua.lua_typename(actual_type);
            const s = std.fmt.bufPrint(&buf, "{s}: 0x{x:0>14}", .{ tname, @intFromPtr(ptr) }) catch return null;
            _ = lua.lua_pushstring(L, s);
            return lua.lua_tolstring(L, -1, len);
        },
    }
}

pub fn luaL_traceback(L: *lua.lua_State, L2: *lua.lua_State, msg: []const u8, level: i32) !void {
    _ = L;
    _ = L2;
    _ = msg;
    _ = level;
    return error.NotImplemented;
}

// ===================================================================
// String buffer (luaL_Buffer)
// ===================================================================

pub const luaL_Buffer = struct {
    buf: std.ArrayList(u8) = .empty,
};

pub fn luaL_buffinit(_: *lua.lua_State, b: *luaL_Buffer) void {
    b.* = .{};
}

pub fn luaL_addlstring(L: *lua.lua_State, b: *luaL_Buffer, s: []const u8) !void {
    try b.buf.appendSlice(L.allocator, s);
}

pub fn luaL_addchar(L: *lua.lua_State, b: *luaL_Buffer, c: u8) !void {
    try b.buf.append(L.allocator, c);
}

pub fn luaL_addsize(b: *luaL_Buffer, n: usize) void {
    b.buf.items.len += n;
}

pub fn luaL_prepbuffsize(L: *lua.lua_State, b: *luaL_Buffer, sz: usize) ![]u8 {
    const old_len = b.buf.items.len;
    // Reserve capacity for `sz` bytes without committing them: the logical
    // length stays at `old_len` until luaL_addsize is called. This matches
    // the C luaL_prepbuffsize / luaL_addsize contract (prepbuffsize only
    // guarantees free space; addsize commits it).
    try b.buf.ensureTotalCapacity(L.allocator, old_len + sz);
    return b.buf.items.ptr[old_len .. old_len + sz];
}

pub fn luaL_addvalue(L: *lua.lua_State, b: *luaL_Buffer) !void {
    const s = lua.lua_tolstring(L, -1, null) orelse return error.NotAString;
    try luaL_addlstring(L, b, s);
    lua.lua_pop(L, 1);
}

pub fn luaL_pushresult(L: *lua.lua_State, b: *luaL_Buffer) void {
    _ = lua.lua_pushlstring(L, b.buf.items, b.buf.items.len);
    b.buf.deinit(L.allocator);
}

pub fn luaL_pushresultsize(L: *lua.lua_State, b: *luaL_Buffer, sz: usize) void {
    _ = lua.lua_pushlstring(L, b.buf.items[0..sz], sz);
    b.buf.deinit(L.allocator);
}

// ===================================================================
// Utility functions (continued)
// ===================================================================

pub fn luaL_gsub(L: *lua.lua_State, s: []const u8, p: []const u8, r: []const u8) ![]const u8 {
    var b = luaL_Buffer{};
    luaL_buffinit(L, &b);
    var rest = s;
    while (std.mem.indexOf(u8, rest, p)) |idx| {
        try luaL_addlstring(L, &b, rest[0..idx]);
        try luaL_addlstring(L, &b, r);
        rest = rest[idx + p.len ..];
    }
    try luaL_addlstring(L, &b, rest);
    _ = lua.lua_pushlstring(L, b.buf.items, b.buf.items.len);
    const result = lua.lua_tolstring(L, -1, null) orelse return error.NotAString;
    b.buf.deinit(L.allocator);
    return result;
}

// ===================================================================
// Library opening functions
// ===================================================================

pub fn luaL_openlibs(L: *lua.lua_State) !void {
    try luaL_openselectedlibs(L, ~@as(i32, 0), 0);
}

pub fn luaL_openselectedlibs(L: *lua.lua_State, openmask: i32, closedmask: i32) !void {
    _ = closedmask;
    if ((openmask & lua.LUA_BASELIB) != 0) {
        try lualib.openbaselib(L);
    }
    if ((openmask & lua.LUA_COROLIB) != 0) {
        try lualib.opencorolib(L);
    }
    if ((openmask & lua.LUA_TABLIB) != 0) {
        try lualib.opentablib(L);
    }
    if ((openmask & lua.LUA_STRLIB) != 0) {
        try lualib.openstringlib(L);
    }
    if ((openmask & lua.LUA_MATHLIB) != 0) {
        try lualib.openmathlib(L);
    }
    if ((openmask & lua.LUA_OSLIB) != 0) {
        try lualib.openoslib(L);
    }
    if ((openmask & lua.LUA_IOLIB) != 0) {
        try lualib.openio(L);
    }
    if ((openmask & lua.LUA_LOADLIB) != 0) {
        try lualib.openloadlib(L);
    }
    if ((openmask & lua.LUA_DBLIB) != 0) {
        try lualib.opendbalib(L);
    }
    if ((openmask & lua.LUA_BITLIB) != 0) {
        try lualib.openbit32(L);
    }
    if ((openmask & lua.LUA_UTF8LIB) != 0) {
        try lualib.openutf8lib(L);
    }
}
