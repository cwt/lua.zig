//
// ** $Id: lauxlib.zig
// ** Auxiliary library for Lua.zig (Zig port of Lua 5.5.0)
// ** See Copyright Notice in c_compat.zig
//

const std = @import("std");
const lua = @import("lua.zig");
const luaconf = @import("luaconf.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");
const lualib = @import("lualib.zig");
const ltm = @import("ltm.zig");

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
        return luaL_typeerror(L, idx, lua.lua_typename(t));
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

pub fn luaL_len(L: *lua.lua_State, idx: i32) !i64 {
    try lua.lua_len(L, idx);
    var isnum: i32 = 0;
    const iv = lua.lua_tointegerx(L, -1, &isnum);
    if (isnum == 0 or iv == null) {
        lua.lua_pop(L, 1);
        return luaL_error(L, "object length is not an integer");
    }
    const l = iv.?;
    lua.lua_pop(L, 1);
    return l;
}

pub fn luaL_checkinteger(L: *lua.lua_State, idx: i32) !i64 {
    const n = lua.lua_tointeger(L, idx);
    if (n == null) {
        if (lua.lua_isnumber(L, idx) != 0) {
            return luaL_argerror(L, idx, "number has no integer representation");
        }
        return luaL_typeerror(L, idx, "integer");
    }
    return n.?;
}

pub fn luaL_checklstring(L: *lua.lua_State, idx: i32, len: ?*usize) ![]const u8 {
    const s = lua.lua_tolstring(L, idx, len);
    if (s == null) {
        return luaL_typeerror(L, idx, "string");
    }
    return s.?;
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

pub fn luaL_checkoption(L: *lua.lua_State, idx: i32, def: ?[]const u8, opts: [][]const u8) !i32 {
    const s = blk: {
        if (lua.lua_isnoneornil(L, idx)) {
            if (def) |d| break :blk d else return luaL_argerror(L, idx, "value expected");
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
    luaL_where(L, 1);
    _ = lua.lua_pushstring(L, msg);
    lua.lua_concat(L, 2);
    return lua.lua_error(L);
}

fn findfield(L: *lua.lua_State, objidx: i32, level: i32) anyerror!bool {
    if (level == 0 or lua.lua_istable(L, -1) == 0) return false;
    lua.lua_pushnil(L);
    while ((try lua.lua_next(L, -2)) != 0) {
        if (lua.lua_type(L, -2) == lua.LUA_TSTRING) {
            if (lua.lua_rawequal(L, objidx, -1) != 0) {
                lua.lua_pop(L, 1);
                return true;
            } else if (try findfield(L, objidx, level - 1)) {
                _ = lua.lua_pushstring(L, ".");
                lua.lua_replace(L, -3);
                lua.lua_concat(L, 3);
                return true;
            }
        }
        lua.lua_pop(L, 1);
    }
    return false;
}

fn pushglobalfuncname(L: *lua.lua_State, ar: *lua.lua_Debug) bool {
    const top = lua.lua_gettop(L);
    _ = lua.lua_getinfo(L, "f", ar) catch return false;
    _ = lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, LUA_LOADED_TABLE) catch {
        lua.lua_settop(L, top);
        return false;
    };
    luaL_checkstack(L, 6, "not enough stack") catch {
        lua.lua_settop(L, top);
        return false;
    };
    const ok = findfield(L, top + 1, 2) catch {
        lua.lua_settop(L, top);
        return false;
    };
    if (ok) {
        const name = lua.lua_tostring(L, -1) orelse "";
        if (std.mem.startsWith(u8, name, "_G.")) {
            _ = lua.lua_pushstring(L, name[3..]);
            lua.lua_remove(L, -2);
        }
        lua.lua_copy(L, -1, top + 1);
        lua.lua_settop(L, top + 1);
        return true;
    } else {
        lua.lua_settop(L, top);
        return false;
    }
}

pub fn luaL_argerror(L: *lua.lua_State, arg: i32, extramsg: []const u8) anyerror {
    var ar: lua.lua_Debug = undefined;
    if (lua.lua_getstack(L, 0, &ar) == 0) {
        var buf: [256]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "bad argument #{d} ({s})", .{ arg, extramsg }) catch extramsg;
        return luaL_error(L, s);
    }
    _ = lua.lua_getinfo(L, "nt", &ar) catch 0;
    var actual_arg = arg;
    var argword: []const u8 = "argument";
    if (actual_arg <= ar.extraargs) {
        argword = "extra argument";
    } else {
        actual_arg -= ar.extraargs;
        if (ar.namewhat) |nw| {
            if (std.mem.eql(u8, nw, "method")) {
                actual_arg -= 1;
                if (actual_arg == 0) {
                    const fn_name = if (ar.name) |n| n else "?";
                    var buf: [256]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "calling '{s}' on bad self ({s})", .{ fn_name, extramsg }) catch extramsg;
                    return luaL_error(L, s);
                }
            }
        }
    }
    var fname: []const u8 = "?";
    var name_pushed = false;
    if (ar.name) |n| {
        fname = n;
    } else if (pushglobalfuncname(L, &ar)) {
        if (lua.lua_tostring(L, -1)) |s| {
            fname = s;
            name_pushed = true;
        }
    }
    var buf: [320]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "bad {s} #{d} to '{s}' ({s})", .{ argword, actual_arg, fname, extramsg }) catch extramsg;
    if (name_pushed) {
        lua.lua_pop(L, 1);
    }
    return luaL_error(L, s);
}

pub fn luaL_typeerror(L: *lua.lua_State, idx: i32, tname: []const u8) anyerror {
    var typearg: []const u8 = "userdata";
    if (luaL_getmetafield(L, idx, "__name") != 0) {
        if (lua.lua_tostring(L, -1)) |s| {
            typearg = s;
        }
        lua.lua_pop(L, 1);
    } else if (lua.lua_type(L, idx) == lua.LUA_TLIGHTUSERDATA) {
        typearg = "light userdata";
    } else if (lua.idxPtr(L, idx)) |ptr| {
        typearg = ltm.luaT_objtypename(L, ptr.*);
    } else {
        typearg = lua.lua_typename(lua.lua_type(L, idx));
    }
    var buf: [256]u8 = undefined;
    const s = std.fmt.bufPrint(&buf, "{s} expected, got {s}", .{ tname, typearg }) catch tname;
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

extern "c" fn snprintf(buf: [*]u8, size: usize, format: [*]const u8, ...) c_int;
extern "c" fn strtod(nptr: [*]const u8, endptr: ?*[*]const u8) f64;
extern "c" fn strspn(str1: [*]const u8, str2: [*]const u8) usize;

fn tostringbuffFloat(n: f64, buff: *[128]u8) usize {
    var len = snprintf(buff, 128, "%.15g", n);
    if (len < 0) return 0;
    buff[@intCast(len)] = 0;
    const check = strtod(buff, null);
    if (check != n) {
        len = snprintf(buff, 128, "%.17g", n);
        if (len < 0) return 0;
        buff[@intCast(len)] = 0;
    }
    const idx = strspn(buff, "-0123456789");
    if (buff[idx] == 0) {
        const ulen: usize = @intCast(len);
        buff[ulen] = '.';
        buff[ulen + 1] = '0';
        buff[ulen + 2] = 0;
        return ulen + 2;
    }
    return @intCast(len);
}

pub fn luaL_tolstring(L: *lua.lua_State, idx: i32, len: ?*usize) ?[]const u8 {
    const abs_idx = lua.lua_absindex(L, idx);
    if ((luaL_callmeta(L, abs_idx, "__tostring") catch 0) != 0) {
        if (lua.lua_isstring(L, -1) == 0) {
            _ = luaL_error(L, "'__tostring' must return a string") catch {};
        }
        return lua.lua_tolstring(L, -1, len);
    }
    const actual_type = lua.lua_type(L, abs_idx);
    switch (actual_type) {
        lua.LUA_TSTRING => {
            lua.lua_pushvalue(L, abs_idx);
        },
        lua.LUA_TNUMBER => {
            var buf: [128]u8 = undefined;
            if (lua.lua_isinteger(L, abs_idx) != 0) {
                if (lua.lua_tointeger(L, abs_idx)) |iv| {
                    const s = std.fmt.bufPrint(&buf, "{d}", .{iv}) catch return null;
                    _ = lua.lua_pushstring(L, s);
                }
            } else {
                const fv = lua.lua_tonumber(L, abs_idx) orelse 0.0;
                const slen = tostringbuffFloat(fv, &buf);
                _ = lua.lua_pushlstring(L, &buf, slen);
            }
        },
        lua.LUA_TBOOLEAN => {
            const b = lua.lua_toboolean(L, abs_idx);
            const s: []const u8 = if (b != 0) "true" else "false";
            _ = lua.lua_pushstring(L, s);
        },
        lua.LUA_TNIL => {
            _ = lua.lua_pushstring(L, "nil");
        },
        else => {
            var kind: []const u8 = lua.lua_typename(actual_type);
            var name_pushed = false;
            if (luaL_getmetafield(L, abs_idx, "__name") == lua.LUA_TSTRING) {
                if (lua.lua_tostring(L, -1)) |s| {
                    kind = s;
                    name_pushed = true;
                }
            }
            var buf: [128]u8 = undefined;
            const ptr = lua.lua_topointer(L, abs_idx);
            const s = std.fmt.bufPrint(&buf, "{s}: 0x{x:0>14}", .{ kind, @intFromPtr(ptr) }) catch return null;
            _ = lua.lua_pushstring(L, s);
            if (name_pushed) {
                lua.lua_remove(L, -2);
            }
        },
    }
    return lua.lua_tolstring(L, -1, len);
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
    } else if (pushglobalfuncname(L, @constCast(ar))) {
        const name_val = lua.lua_tostring(L, -1) orelse "?";
        const fmt_str = try std.fmt.allocPrint(L.allocator, "function '{s}'", .{name_val});
        defer L.allocator.free(fmt_str);
        _ = lua.lua_pushlstring(L, fmt_str, fmt_str.len);
        lua.lua_remove(L, -2);
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

    // When tracing a coroutine that died with an error, prepend the frame of
    // the C function that raised it (its name was recorded by luaG_errormsg),
    // e.g. "[C]: in global 'error'". Matches the reference, which keeps that
    // frame in the chain.
    if (L2.err_name != null and L2.err_namewhat != null) {
        var name_buf: [128]u8 = undefined;
        const nslice = try std.fmt.bufPrint(&name_buf, "\n\t[C]: in {s} '{s}'", .{ L2.err_namewhat.?, L2.err_name.? });
        try luaL_addlstring(L, &b, nslice);
    }

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
            const gres = lua.lua_getinfo(L2, "Slnt", &ar) catch {
                continue;
            };
            if (gres == 0) {
                continue;
            }
            
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
// Reference system (luaL_ref / luaL_unref)
// ===================================================================

pub const LUA_NOREF: i32 = -2;
pub const LUA_REFNIL: i32 = -1;

/// Creates a reference in table `t` for the value at the top of the stack.
/// Pops the value from the stack (unless it's nil, in which case LUA_REFNIL
/// is returned and the stack is still popped).
pub fn luaL_ref(L: *lua.lua_State, t: i32) i32 {
    // If the top value is nil, return the fixed nil reference.
    if (lua.lua_isnil(L, -1) != 0) {
        lua.lua_pop(L, 1);
        return LUA_REFNIL;
    }

    const abs_t = lua.lua_absindex(L, t);

    // t[1] stores the head of the free-list linked chain.
    // If t[1] is a number, it's the head of the free list.
    // Otherwise (first access), we need to initialize.
    const free_head: i64 = if (lua.lua_rawgeti(L, abs_t, 1) == lua.LUA_TNUMBER)
        lua.lua_tointeger(L, -1) orelse 0
    else blk: {
        // First access: initialize empty free list (t[1] = 0).
        lua.lua_pushinteger(L, 0);
        lua.lua_rawseti(L, abs_t, 1);
        break :blk 0;
    };
    lua.lua_pop(L, 1); // Remove t[1] from the stack.

    const ref: i64 = if (free_head != 0) blk: {
        // Pop the next free slot from the list.
        // t[ref] holds the next free index; move it to t[1].
        _ = lua.lua_rawgeti(L, abs_t, free_head);
        lua.lua_rawseti(L, abs_t, 1); // t[1] = t[ref]
        break :blk free_head;
    } else blk: {
        // No free slots: allocate a new one past the end of the table.
        const raw_len = lua.lua_rawlen(L, abs_t);
        break :blk @as(i64, @intCast(raw_len)) + 1;
    };

    // Store the value (currently on top of stack) at the reference slot.
    lua.lua_rawseti(L, abs_t, ref);

    return @as(i32, @intCast(ref));
}

/// Releases a reference previously created by `luaL_ref`.
/// The freed slot is added to the free list and will be reused.
pub fn luaL_unref(L: *lua.lua_State, t: i32, ref: i32) void {
    if (ref < 0) return;
    const abs_t = lua.lua_absindex(L, t);
    // Push the current free-list head (t[1]) and link the freed slot.
    _ = lua.lua_rawgeti(L, abs_t, 1); // push t[1] (old head)
    lua.lua_rawseti(L, abs_t, @intCast(ref)); // t[ref] = old head
    lua.lua_pushinteger(L, @intCast(ref));
    lua.lua_rawseti(L, abs_t, 1); // t[1] = ref (new head)
}

// ===================================================================
// Version check, callmeta, allocator
// ===================================================================

pub const LUAL_NUMSIZES: usize = @sizeOf(lua.lua_Integer) * 16 + @sizeOf(lua.lua_Number);
pub const LUA_ERRFILE: i32 = 5;
pub const LUA_GNAME: []const u8 = "_G";
pub const LUA_LOADED_TABLE: []const u8 = "_LOADED";
pub const LUA_PRELOAD_TABLE: []const u8 = "_PRELOAD";

/// Version/ABI check called by every library `open_` function.
pub fn luaL_checkversion_(L: *lua.lua_State, ver: lua.lua_Number, sz: usize) !void {
    const v = lua.lua_version(L);
    if (sz != LUAL_NUMSIZES)
        return luaL_error(L, "core and library have incompatible numeric types");
    if (v != ver)
        return luaL_error(L, "version mismatch");
}

/// Convenience wrapper around `luaL_checkversion_` with the default version
/// and numeric-sizes constants.
pub fn luaL_checkversion(L: *lua.lua_State) !void {
    return luaL_checkversion_(L, lua.LUA_VERSION_NUM, LUAL_NUMSIZES);
}

/// Calls a metamethod by name. Returns 1 if the metamethod was found and
/// called, 0 otherwise.
pub fn luaL_callmeta(L: *lua.lua_State, obj: i32, event: []const u8) !i32 {
    const abs_obj = lua.lua_absindex(L, obj);
    if (luaL_getmetafield(L, abs_obj, event) == lua.LUA_TNIL) return 0;
    lua.lua_pushvalue(L, abs_obj);
    try lua.lua_call(L, 1, 1);
    return 1;
}

/// Default C-ABI allocator compatible with `lua_Alloc` typedef.
pub fn luaL_alloc(ud: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) ?*anyopaque {
    _ = ud;
    _ = osize;
    if (nsize == 0) {
        std.c.free(ptr);
        return null;
    }
    return std.c.realloc(ptr, nsize);
}

// ===================================================================
// Load functions (luaL_loadfilex, luaL_loadbufferx, luaL_loadstring)
// ===================================================================

const LoadS = struct {
    s: []const u8,
    done: bool = false,
};

fn getS(L: *lua.lua_State, ud: ?*anyopaque, size: ?*usize) anyerror!?[]const u8 {
    _ = L;
    const ls = @as(?*LoadS, @ptrCast(@alignCast(ud))) orelse return null;
    if (ls.done) return null;
    ls.done = true;
    if (size) |s| s.* = ls.s.len;
    return ls.s;
}

/// Load file as Lua chunk (with mode). If `filename` is null, reads from
/// stdin (not yet implemented — use named files).
pub fn luaL_loadfilex(L: *lua.lua_State, filename: ?[]const u8, mode: []const u8) i32 {
    const g = L.l_G orelse return lua.LUA_ERRERR;

    const chunkname = if (filename) |fn_| blk: {
        var buf: [512]u8 = undefined;
        const s = std.fmt.bufPrint(&buf, "@{s}", .{fn_}) catch "=stdin";
        break :blk s;
    } else "=stdin";

    if (filename) |fn_| {
        const content = std.Io.Dir.cwd().readFileAlloc(g.io, fn_, L.allocator, .unlimited) catch {
            _ = lua.lua_pushstring(L, "cannot open file") orelse {};
            return lua.LUA_ERRERR;
        };
        defer L.allocator.free(content);

        // Skip an optional UTF-8 BOM at the start, then skip an optional
        // shebang line (Unix exec. file starting with '#'). This matches the
        // `skipcomment` function in Lua's `lauxlib.c`.
        const start = blk: {
            var start_idx: usize = 0;
            // Skip UTF-8 BOM (0xEF 0xBB 0xBF)
            if (content.len >= 3 and content[0] == 0xEF and content[1] == 0xBB and content[2] == 0xBF) {
                start_idx = 3;
            }
            // Skip shebang line if present
            if (start_idx < content.len and content[start_idx] == '#') {
                if (std.mem.indexOfScalar(u8, content[start_idx..], '\n')) |nl| {
                    start_idx = start_idx + nl + 1;
                } else {
                    start_idx = content.len; // no newline: rest of file is the shebang
                }
            }
            break :blk start_idx;
        };
        const adjusted = content[start..];

        var ls = LoadS{ .s = adjusted, .done = false };
        return lua.lua_load(L, getS, @as(?*anyopaque, @ptrCast(&ls)), chunkname, mode);
    }

    // stdin: not yet supported via reader (would need a streaming reader).
    _ = lua.lua_pushstring(L, "stdin not supported") orelse {};
    return lua.LUA_ERRERR;
}

/// Load buffer as Lua chunk (with mode).
pub fn luaL_loadbufferx(L: *lua.lua_State, buff: []const u8, name: []const u8, mode: []const u8) i32 {
    var ls = LoadS{ .s = buff, .done = false };
    return lua.lua_load(L, getS, @as(?*anyopaque, @ptrCast(&ls)), name, mode);
}

/// Load string as Lua chunk.
pub fn luaL_loadstring(L: *lua.lua_State, s: []const u8) i32 {
    return luaL_loadbufferx(L, s, s, "t");
}

// ===================================================================
// Subtable, require, dofile
// ===================================================================

/// Get or create subtable in registry (or any table at `idx`).
pub fn luaL_getsubtable(L: *lua.lua_State, idx: i32, fname: []const u8) !i32 {
    if (try lua.lua_getfield(L, idx, fname) == lua.LUA_TTABLE) return 1;
    lua.lua_pop(L, 1);
    const abs_idx = lua.lua_absindex(L, idx);
    lua.lua_createtable(L, 0, 0);
    lua.lua_pushvalue(L, -1);
    try lua.lua_setfield(L, abs_idx, fname);
    return 0;
}

/// Require library with C open function. Registers the module in
/// `package.loaded` and optionally in the global table.
pub fn luaL_requiref(L: *lua.lua_State, modname: []const u8, openf: lua.lua_CFunction, glb: i32) !void {
    _ = try luaL_getsubtable(L, lua.LUA_REGISTRYINDEX, LUA_LOADED_TABLE);
    _ = lua.lua_getfield(L, -1, modname);
    if (lua.lua_toboolean(L, -1) == 0) {
        lua.lua_pop(L, 1);
        lua.lua_pushcfunction(L, openf);
        _ = lua.lua_pushstring(L, modname);
        try lua.lua_call(L, 1, 1);
        lua.lua_pushvalue(L, -1);
        lua.lua_setfield(L, -3, modname);
    }
    lua.lua_remove(L, -2);
    if (glb != 0) {
        lua.lua_pushvalue(L, -1);
        lua.lua_setglobal(L, modname);
    }
}

/// Load and run a file.
pub fn luaL_dofile(L: *lua.lua_State, filename: ?[]const u8) i32 {
    const status = luaL_loadfilex(L, filename, "t");
    if (status != lua.LUA_OK) return status;
    return lua.lua_pcallk(L, 0, lua.LUA_MULTRET, 0, 0, null) catch |e| {
        return if (e == error.Yield) lua.LUA_YIELD else lua.LUA_ERRRUN;
    };
}

/// Generate a random seed for hashing.
pub fn luaL_makeseed(L: *lua.lua_State) u32 {
    // Use the address of the state and the address of a local variable as
    // entropy (the C reference uses *(unsigned int*)(&L) plus extra mixing).
    var local: usize = undefined;
    const addr_seed = @intFromPtr(L) ^ @intFromPtr(&local);
    return @truncate(addr_seed);
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

pub fn luaL_addstring(L: *lua.lua_State, b: *luaL_Buffer, s: []const u8) !void {
    try luaL_addlstring(L, b, s);
}

pub fn luaL_buffinitsize(L: *lua.lua_State, b: *luaL_Buffer, sz: usize) ![]u8 {
    b.* = .{};
    return luaL_prepbuffsize(L, b, sz);
}

pub fn luaL_prepbuffer(L: *lua.lua_State, b: *luaL_Buffer) ![]u8 {
    return luaL_prepbuffsize(L, b, luaconf.LUAL_BUFFERSIZE);
}

pub fn luaL_bufflen(b: *const luaL_Buffer) usize {
    return b.buf.items.len;
}

pub fn luaL_buffaddr(b: *const luaL_Buffer) []const u8 {
    return b.buf.items;
}

pub fn luaL_buffsub(b: *luaL_Buffer, s: usize) void {
    b.buf.items.len -= s;
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
        return 0;  // already exists
    }
    lua.lua_pop(L, 1);
    lua.lua_createtable(L, 0, 2);
    _ = lua.lua_pushstring(L, tname);
    try lua.lua_setfield(L, -2, "__name");
    lua.lua_pushvalue(L, -1);
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

