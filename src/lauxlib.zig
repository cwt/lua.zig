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
    lua.lua_createtable(L, 0, 0);
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

pub fn luaL_argexpected(L: *lua.lua_State, cond: bool, arg: i32, tname: []const u8) !void {
    if (!cond) {
        const actual_type = lua.lua_type(L, arg);
        const actual_name = lua.lua_typename(actual_type);
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "{s} expected, got {s}", .{ tname, actual_name }) catch "type mismatch";
        return luaL_argerror(L, arg, msg);
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
    try lua.lua_len(L, idx);
    const isnum = lua.lua_isinteger(L, -1);
    const iv = lua.lua_tointegerx(L, -1, null);
    if (iv == null or (iv.? == 0 and isnum == 0)) {
        lua.lua_pop(L, 1);
        return error.LuaTypeError;
    }
    const l = iv.?;
    lua.lua_pop(L, 1);
    return @as(usize, @intCast(l));
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

pub fn luaL_checkstring(L: *lua.lua_State, idx: i32) ![]const u8 {
    return luaL_checklstring(L, idx, null);
}

pub fn luaL_optstring(L: *lua.lua_State, idx: i32, def: ?[]const u8) ?[]const u8 {
    if (lua.lua_isnoneornil(L, idx)) return def;
    return lua.lua_tostring(L, idx);
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
                if (lua.lua_tointeger(L, idx)) |iv| {
                    const s = std.fmt.bufPrint(&buf, "{d}", .{iv}) catch return null;
                    _ = lua.lua_pushstring(L, s);
                } else {
                    // Integral value outside the i64 range (e.g. 2^100): there is
                    // no integer TValue type in this f64-only port, so format it as
                    // a (scientific) float instead of collapsing to 0.
                    const fv = lua.lua_tonumber(L, idx) orelse 0.0;
                    const s = std.fmt.bufPrint(&buf, "{e}", .{fv}) catch return null;
                    _ = lua.lua_pushstring(L, s);
                }
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

pub fn luaL_where(L: *lua.lua_State, level: i32) void {
    var ar: lua.lua_Debug = undefined;
    if (lua.lua_getstack(L, level, &ar) != 0) {
        _ = lua.lua_getinfo(L, "Sl", &ar) catch {};
        if (ar.currentline > 0) {
            const src = std.mem.sliceTo(&ar.short_src, 0);
            var buf: [256]u8 = undefined;
            const s = std.fmt.bufPrint(&buf, "{s}:{d}: ", .{ src, ar.currentline }) catch "? ";
            _ = lua.lua_pushstring(L, s);
            return;
        }
    }
    _ = lua.lua_pushstring(L, "");
}

const LEVELS1 = 12;
const LEVELS2 = 10;

fn pushfuncname(L: *lua.lua_State, ar: *const lua.lua_Debug) !void {
    if (ar.namewhat != null and ar.namewhat.?.len > 0) {
        const name = ar.name orelse "?";
        const fmt_str = try std.fmt.allocPrint(L.allocator, "{s} '{s}'", .{ar.namewhat.?, name});
        defer L.allocator.free(fmt_str);
        _ = lua.lua_pushlstring(L, fmt_str, fmt_str.len);
    } else if (ar.what != null and ar.what.?.len > 0 and ar.what.?[0] == 'm') {
        _ = lua.lua_pushstring(L, "main chunk");
    } else if (ar.what != null and ar.what.?.len > 0 and !std.mem.eql(u8, ar.what.?, "C")) {
        const src = ar.source orelse "?";
        var short_src: [lua.LUA_IDSIZE]u8 = undefined;
        lua.luaO_chunkid(&short_src, src);
        const fmt_str = try std.fmt.allocPrint(L.allocator, "function <{s}:{}>", .{std.mem.sliceTo(&short_src, 0), ar.linedefined});
        defer L.allocator.free(fmt_str);
        _ = lua.lua_pushlstring(L, fmt_str, fmt_str.len);
    } else {
        _ = lua.lua_pushstring(L, "?");
    }
}

pub fn luaL_traceback(L: *lua.lua_State, L2: *lua.lua_State, msg: []const u8, level: i32) !void {
    var b = luaL_Buffer{};
    luaL_buffinit(L, &b);
    errdefer b.buf.deinit(L.allocator);

    if (msg.len > 0) {
        try luaL_addlstring(L, &b, msg);
        try luaL_addchar(L, &b, '\n');
    }
    try luaL_addlstring(L, &b, "stack traceback:");

    var ar: lua.lua_Debug = undefined;
    var last: i32 = 0;
    while (lua.lua_getstack(L2, last, &ar) != 0) {
        last += 1;
    }

    var lvl = level;
    var limit2show: i32 = if (last - lvl > LEVELS1 + LEVELS2) LEVELS1 else -1;

    while (lua.lua_getstack(L2, lvl, &ar) != 0) {
        lvl += 1;
        if (limit2show == 0) {
            const n = last - lvl - LEVELS2 + 1;
            const fmt_str = try std.fmt.allocPrint(L.allocator, "\n\t...\t(skipping {} levels)", .{n});
            defer L.allocator.free(fmt_str);
            try luaL_addlstring(L, &b, fmt_str);
            lvl += n;
            limit2show = -1;
        } else {
            if (limit2show > 0) {
                limit2show -= 1;
            }
            _ = try lua.lua_getinfo(L2, "Slnt", &ar);
            
            const src = if (ar.source) |s| s else "?";
            var short_src: [lua.LUA_IDSIZE]u8 = undefined;
            lua.luaO_chunkid(&short_src, src);
            const short_src_slice = std.mem.sliceTo(&short_src, 0);

            var line_buf: [128]u8 = undefined;
            const line_str = if (ar.currentline <= 0)
                try std.fmt.bufPrint(&line_buf, "\n\t{s}: in ", .{short_src_slice})
            else
                try std.fmt.bufPrint(&line_buf, "\n\t{s}:{}: in ", .{short_src_slice, ar.currentline});
            try luaL_addlstring(L, &b, line_str);

            try pushfuncname(L, &ar);
            const funcname_val = lua.lua_tostring(L, -1) orelse "?";
            try luaL_addlstring(L, &b, funcname_val);
            lua.lua_pop(L, 1);

            if (ar.istailcall) {
                try luaL_addlstring(L, &b, "\n\t(...tail calls...)");
            }
        }
    }
    luaL_pushresult(L, &b);
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
    errdefer b.buf.deinit(L.allocator);
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

pub fn luaL_newmetatable(L: *lua.lua_State, tname: []const u8) !i32 {
    _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, tname);
    if (lua.lua_type(L, -1) != lua.LUA_TNIL) {
        lua.lua_pop(L, 1);
        return 0;  // already exists
    }
    lua.lua_pop(L, 1);
    lua.lua_createtable(L, 0, 0);
    try lua.lua_setfield(L, lua.LUA_REGISTRYINDEX, tname);
    return 1;
}

pub fn luaL_setmetatable(L: *lua.lua_State, tname: []const u8) !void {
    _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, tname);
    _ = lua.lua_setmetatable(L, -2);
}

pub fn luaL_testudata(L: *lua.lua_State, idx: i32, tname: []const u8) ?*anyopaque {
    const p = lua.lua_touserdata(L, idx) orelse return null;
    if (lua.lua_getmetatable(L, idx) == 0) return null;
    _ = lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, tname) catch return null;
    const same = lua.lua_rawequal(L, -1, -2);
    lua.lua_pop(L, 2);
    return if (same != 0) p else null;
}

pub fn luaL_checkudata(L: *lua.lua_State, idx: i32, tname: []const u8) !*anyopaque {
    const p = luaL_testudata(L, idx, tname) orelse {
        return luaL_typeerror(L, idx, tname);
    };
    return p;
}

pub fn luaL_setfuncs(L: *lua.lua_State, reg: []const luaL_Reg, nup: i32) !void {
    _ = nup;
    for (reg) |r| {
        if (r.name.len == 0) continue;
        lua.lua_pushcfunction(L, r.func);
        try lua.lua_setfield(L, -2, r.name);
    }
}

pub fn luaL_newlib(L: *lua.lua_State, reg: []const luaL_Reg) !void {
    lua.lua_createtable(L, 0, @intCast(reg.len));
    try luaL_setfuncs(L, reg, 0);
}

pub fn luaL_fileresult(L: *lua.lua_State, stat: bool, fname: ?[]const u8) i32 {
    if (stat) {
        lua.lua_pushboolean(L, 1);
        return 1;
    } else {
        lua.lua_pushnil(L);
        if (fname) |fn_| {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{s}: error", .{fn_}) catch "error";
            _ = lua.lua_pushstring(L, msg);
        } else {
            _ = lua.lua_pushstring(L, "error");
        }
        return 2;
    }
}

pub fn luaL_execresult(L: *lua.lua_State, stat: i32) i32 {
    if (stat == 0) {
        lua.lua_pushboolean(L, 1);
        return 1;
    } else {
        lua.lua_pushnil(L);
        _ = lua.lua_pushstring(L, "exit");
        lua.lua_pushinteger(L, stat);
        return 3;
    }
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

pub fn luaL_getenv(L: *lua.lua_State, name: []const u8) anyerror!?[]const u8 {
    const g = L.l_G orelse return null;
    const file = std.Io.Dir.cwd().openFile(g.io, "/proc/self/environ", .{ .mode = .read_only }) catch |err| {
        if (err == error.FileNotFound) return null;
        return err;
    };
    defer file.close(g.io);

    var list = std.ArrayList(u8).empty;
    defer list.deinit(L.allocator);
    var buf: [4096]u8 = undefined;
    var slices = [_][]u8{&buf};
    while (true) {
        const n = file.readStreaming(g.io, &slices) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (n == 0) break;
        try list.appendSlice(L.allocator, buf[0..n]);
    }

    var it = std.mem.splitScalar(u8, list.items, 0);
    while (it.next()) |var_str| {
        if (var_str.len == 0) continue;
        if (std.mem.indexOfScalar(u8, var_str, '=')) |eq_idx| {
            const var_name = var_str[0..eq_idx];
            if (std.mem.eql(u8, var_name, name)) {
                const var_val = var_str[eq_idx + 1 ..];
                return try L.allocator.dupe(u8, var_val);
            }
        }
    }
    return null;
}

