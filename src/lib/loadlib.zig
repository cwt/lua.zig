const std = @import("std");
const lua = @import("../lua.zig");
const lauxlib = @import("../lauxlib.zig");
const luaconf = @import("../luaconf.zig");
const llimits = @import("../llimits.zig");

const CLIBS = "_CLIBS";
const LUA_POF = "luaopen_";
const LUA_OFSEP = "_";
const LIB_FAIL = "open";
const LUA_VERSUFFIX = "_5_5";

const ERRLIB = 1;
const ERRFUNC = 2;

fn pushliteral(L: *lua.lua_State, s: []const u8) void {
    _ = lua.lua_pushstring(L, s);
}

fn readable(L: *lua.lua_State, filename: []const u8) bool {
    const file = std.Io.Dir.cwd().openFile(L.l_G.?.io, filename, .{ .mode = .read_only }) catch return false;
    file.close(L.l_G.?.io);
    return true;
}

fn noenv(L: *lua.lua_State) !bool {
    _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "LUA_NOENV");
    const b = lua.lua_toboolean(L, -1) != 0;
    lua.lua_pop(L, 1);
    return b;
}

fn lsys_load(L: *lua.lua_State, path: []const u8, seeglb: bool) anyerror!?*std.DynLib {
    _ = seeglb;
    const path_z = try L.allocator.allocSentinel(u8, path.len, 0);
    defer L.allocator.free(path_z);
    @memcpy(path_z[0..path.len], path);

    const lib = try L.allocator.create(std.DynLib);
    errdefer L.allocator.destroy(lib);

    lib.* = std.DynLib.open(path_z) catch |err| {
        L.allocator.destroy(lib);
        const msg = std.fmt.allocPrint(L.allocator, "cannot open library: {}", .{err}) catch {
            pushliteral(L, "cannot open library");
            return null;
        };
        defer L.allocator.free(msg);
        _ = lua.lua_pushlstring(L, msg, msg.len);
        return null;
    };
    errdefer lib.close();

    if (L.l_G) |g| {
        try g.clibs.append(g.allocator, lib);
    }
    return lib;
}

fn lsys_sym(L: *lua.lua_State, lib: *std.DynLib, sym: []const u8) anyerror!?lua.lua_CFunction {
    const sym_z = try L.allocator.allocSentinel(u8, sym.len, 0);
    defer L.allocator.free(sym_z);
    @memcpy(sym_z[0..sym.len], sym);

    const ptr = lib.lookup(*anyopaque, sym_z) orelse {
        pushliteral(L, "symbol not found");
        return null;
    };
    return @ptrCast(@alignCast(ptr));
}

fn lsys_unloadlib(lib: *std.DynLib) void {
    lib.close();
}

fn checkclib(L: *lua.lua_State, path: []const u8) !?*std.DynLib {
    _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, CLIBS);
    defer lua.lua_pop(L, 1);
    if (lua.lua_type(L, -1) == lua.LUA_TNIL) return null;
    _ = try lua.lua_getfield(L, -1, path);
    defer lua.lua_pop(L, 1);
    const ud = lua.lua_touserdata(L, -1) orelse return null;
    return @ptrCast(@alignCast(ud));
}

fn addtoclib(L: *lua.lua_State, path: []const u8, plib: *std.DynLib) !void {
    _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, CLIBS);
    defer lua.lua_pop(L, 1);
    lua.lua_pushlightuserdata(L, @ptrCast(plib));
    try lua.lua_setfield(L, -2, path);
}

fn lookforfunc(L: *lua.lua_State, path: []const u8, sym: []const u8) anyerror!i32 {
    const reg = try checkclib(L, path);
    const lib = if (reg) |r| r else blk: {
        const loaded = try lsys_load(L, path, sym.len > 0 and sym[0] == '*');
        if (loaded) |l| {
            try addtoclib(L, path, l);
            break :blk l;
        }
        return ERRLIB;
    };
    if (sym.len > 0 and sym[0] == '*') {
        lua.lua_pushboolean(L, 1);
        return 0;
    } else {
        const f = (try lsys_sym(L, lib, sym)) orelse return ERRFUNC;
        lua.lua_pushcfunction(L, f);
        return 0;
    }
}

fn ll_loadlib(L: *lua.lua_State) anyerror!i32 {
    const path = try lauxlib.luaL_checkstring(L, 1);
    const init = try lauxlib.luaL_checkstring(L, 2);
    const stat = try lookforfunc(L, path, init);
    if (stat == 0) return 1;
    lauxlib.luaL_pushfail(L);
    lua.lua_insert(L, -2);
    const errtype = if (stat == ERRLIB) LIB_FAIL else "init";
    _ = lua.lua_pushstring(L, errtype);
    return 3;
}

fn getnextfilename(path: *[]u8) ?[]const u8 {
    if (path.*.len == 0) return null;
    if (path.*[0] == 0) {
        path.* = path.*[1..];
    }
    if (std.mem.indexOfScalar(u8, path.*, luaconf.LUA_PATH_SEP)) |pos| {
        const name = path.*[0..pos];
        path.* = path.*[pos + 1 ..];
        return name;
    } else {
        const name = path.*;
        path.* = path.*[0..0];
        return name;
    }
}

fn pusherrornotfound(L: *lua.lua_State, path_str: []const u8) void {
    var list = std.ArrayListUnmanaged(u8).empty;
    defer list.deinit(L.allocator);
    var parts = std.mem.splitScalar(u8, path_str, luaconf.LUA_PATH_SEP);
    var first = true;
    while (parts.next()) |part| {
        if (first) {
            list.appendSlice(L.allocator, "no file '") catch return;
            list.appendSlice(L.allocator, part) catch return;
            list.appendSlice(L.allocator, "'") catch return;
            first = false;
        } else {
            list.appendSlice(L.allocator, "\n\tno file '") catch return;
            list.appendSlice(L.allocator, part) catch return;
            list.appendSlice(L.allocator, "'") catch return;
        }
    }
    _ = lua.lua_pushlstring(L, list.items, list.items.len);
}

fn searchpath(L: *lua.lua_State, name: []const u8, path_str: []const u8, sep: []const u8, dirsep: []const u8) ?[]const u8 {
    // Ensure enough stack space for path search operations
    if (lua.lua_checkstack(L, 10) == 0) return null;
    const mark = luaconf.LUA_PATH_MARK;

    var modname = name;
    if (sep.len > 0 and std.mem.indexOf(u8, name, sep) != null) {
        modname = lauxlib.luaL_gsub(L, name, sep, dirsep) catch name;
    }

    const path = std.mem.replaceOwned(u8, L.allocator, path_str, mark, modname) catch {
        pushliteral(L, "path too long");
        return null;
    };
    defer L.allocator.free(path);

    var remaining = path;
    while (getnextfilename(&remaining)) |filename| {
        if (readable(L, filename)) {
            _ = lua.lua_pushstring(L, filename);
            return lua.lua_tostring(L, -1).?;
        }
    }
    pusherrornotfound(L, path);
    return null;
}

fn ll_searchpath(L: *lua.lua_State) anyerror!i32 {
    const name = try lauxlib.luaL_checkstring(L, 1);
    const path_str = try lauxlib.luaL_checkstring(L, 2);
    const sep = try lauxlib.luaL_optlstring(L, 3, ".", null) orelse ".";
    const dirsep = try lauxlib.luaL_optlstring(L, 4, luaconf.LUA_DIRSEP, null) orelse luaconf.LUA_DIRSEP;

    const f = searchpath(L, name, path_str, sep, dirsep);
    if (f != null) return 1;
    lauxlib.luaL_pushfail(L);
    lua.lua_insert(L, -2);
    return 2;
}

fn searcher_preload(L: *lua.lua_State) anyerror!i32 {
    const name = try lauxlib.luaL_checkstring(L, 1);
    _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "_PRELOAD");
    _ = try lua.lua_getfield(L, -1, name);
    if (lua.lua_type(L, -1) == lua.LUA_TNIL) {
        const msg = std.fmt.allocPrint(L.allocator, "no field package.preload['{s}']", .{name}) catch {
            pushliteral(L, "not found");
            return 1;
        };
        defer L.allocator.free(msg);
        _ = lua.lua_pushlstring(L, msg, msg.len);
        return 1;
    }
    pushliteral(L, ":preload:");
    return 2;
}

const FileReaderState = struct {
    data: []const u8,
    pos: usize,
};

fn fileReader(L: *lua.lua_State, data: ?*anyopaque, size: ?*usize) anyerror!?[]const u8 {
    _ = L;
    const state: *FileReaderState = @ptrCast(@alignCast(data.?));
    if (state.pos >= state.data.len) {
        if (size) |s| s.* = 0;
        return &.{};
    }
    const chunk = state.data[state.pos..];
    state.pos = state.data.len;
    if (size) |s| s.* = chunk.len;
    return chunk;
}

fn checkload(L: *lua.lua_State, stat: bool, filename: []const u8) !i32 {
    if (stat) {
        _ = lua.lua_pushstring(L, filename);
        return 2;
    }
    const name = lua.lua_tostring(L, 1) orelse "?";
    const err = lua.lua_tostring(L, -1) orelse "unknown";
    const msg = std.fmt.allocPrint(L.allocator, "error loading module '{s}' from file '{s}':\n\t{s}", .{ name, filename, err }) catch {
        pushliteral(L, "error loading module");
        return lauxlib.luaL_error(L, "error loading module");
    };
    defer L.allocator.free(msg);
    _ = lua.lua_pushlstring(L, msg, msg.len);
    return lauxlib.luaL_error(L, msg);
}

fn findfile(L: *lua.lua_State, name: []const u8, pname: []const u8, dirsep: []const u8) !?[]const u8 {
    _ = try lua.lua_getfield(L, lua.lua_upvalueindex(1), pname);
    const path = lua.lua_tostring(L, -1) orelse {
        const msg = std.fmt.allocPrint(L.allocator, "'package.{s}' must be a string", .{pname}) catch {
            return null;
        };
        defer L.allocator.free(msg);
        _ = lua.lua_pushlstring(L, msg, msg.len);
        return lauxlib.luaL_error(L, msg);
    };
    return searchpath(L, name, path, ".", dirsep);
}

fn loadfunc(L: *lua.lua_State, filename: []const u8, modname: []const u8) anyerror!i32 {
    var mname = modname;
    const gsub = try lauxlib.luaL_gsub(L, mname, ".", LUA_OFSEP);
    mname = gsub;

    if (std.mem.indexOf(u8, mname, luaconf.LUA_IGMARK)) |mark_pos| {
        const openfunc = mname[0..mark_pos];
        const pof_name = try std.fmt.allocPrint(L.allocator, "{s}{s}", .{ LUA_POF, openfunc });
        defer L.allocator.free(pof_name);
        const stat = try lookforfunc(L, filename, pof_name);
        if (stat != ERRFUNC) return stat;
        mname = mname[mark_pos + 1 ..];
    }
    const func_name = try std.fmt.allocPrint(L.allocator, "{s}{s}", .{ LUA_POF, mname });
    defer L.allocator.free(func_name);
    return try lookforfunc(L, filename, func_name);
}

fn searcher_Lua(L: *lua.lua_State) anyerror!i32 {
    const name = try lauxlib.luaL_checkstring(L, 1);
    const filename = try findfile(L, name, "path", luaconf.LUA_DIRSEP) orelse return 1;
    const file_content = std.Io.Dir.cwd().readFileAlloc(L.l_G.?.io, filename, L.allocator, .unlimited) catch {
        pushliteral(L, "cannot read file");
        return 1;
    };
    defer L.allocator.free(file_content);
    var state = FileReaderState{ .data = file_content, .pos = 0 };
    const load_status = lua.lua_load(L, fileReader, &state, filename, "bt");
    if (load_status != lua.LUA_OK) {
        const err = lua.lua_tostring(L, -1) orelse "load error";
        const msg = std.fmt.allocPrint(L.allocator, "error loading module '{s}' from file '{s}':\n\t{s}", .{ name, filename, err }) catch {
            return lauxlib.luaL_error(L, "error loading module");
        };
        defer L.allocator.free(msg);
        _ = lua.lua_pushlstring(L, msg, msg.len);
        return 1;
    }
    _ = lua.lua_pushstring(L, filename);
    return 2;
}

fn searcher_C(L: *lua.lua_State) anyerror!i32 {
    const name = try lauxlib.luaL_checkstring(L, 1);
    const filename = try findfile(L, name, "cpath", luaconf.LUA_DIRSEP) orelse return 1;
    return checkload(L, (try loadfunc(L, filename, name)) == 0, filename);
}

fn searcher_Croot(L: *lua.lua_State) anyerror!i32 {
    const name = try lauxlib.luaL_checkstring(L, 1);
    const p = std.mem.indexOfScalar(u8, name, '.') orelse return 0;
    const root_name = name[0..p];
    _ = lua.lua_pushlstring(L, root_name, root_name.len);
    const filename = try findfile(L, lua.lua_tostring(L, -1) orelse return 1, "cpath", luaconf.LUA_DIRSEP) orelse return 1;
    const stat = try loadfunc(L, filename, name);
    if (stat != 0) {
        if (stat != ERRFUNC) return checkload(L, false, filename);
        const msg = std.fmt.allocPrint(L.allocator, "no module '{s}' in file '{s}'", .{ name, filename }) catch {
            pushliteral(L, "not found");
            return 1;
        };
        defer L.allocator.free(msg);
        _ = lua.lua_pushlstring(L, msg, msg.len);
        return 1;
    }
    _ = lua.lua_pushstring(L, filename);
    return 2;
}

fn findloader(L: *lua.lua_State, name: []const u8) !void {
    _ = try lua.lua_getfield(L, lua.lua_upvalueindex(1), "searchers");
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        return lauxlib.luaL_error(L, "'package.searchers' must be a table");
    }
    const searchers_idx = lua.lua_gettop(L);

    var msg = std.ArrayListUnmanaged(u8).empty;
    defer msg.deinit(L.allocator);
    msg.appendSlice(L.allocator, "\n\t") catch return lauxlib.luaL_error(L, "out of memory");

    var i: i32 = 1;
    while (true) : (i += 1) {
        _ = lua.lua_rawgeti(L, searchers_idx, @intCast(i));
        if (lua.lua_type(L, -1) == lua.LUA_TNIL) {
            lua.lua_pop(L, 1);
            if (msg.items.len >= 2) {
                msg.shrinkRetainingCapacity(msg.items.len - 2);
            }
            const final_err = std.fmt.allocPrint(L.allocator, "module '{s}' not found:{s}", .{ name, msg.items }) catch {
                return lauxlib.luaL_error(L, "out of memory");
            };
            defer L.allocator.free(final_err);
            _ = lua.lua_pushlstring(L, final_err, final_err.len);
            return lauxlib.luaL_error(L, final_err);
        }
        _ = lua.lua_pushstring(L, name);
        try lua.lua_call(L, 1, 2);
        if (lua.lua_type(L, -2) == lua.LUA_TFUNCTION) {
            return;
        } else if (lua.lua_isstring(L, -2) != 0) {
            lua.lua_pop(L, 1);
            const searcher_err = lua.lua_tostring(L, -1).?;
            msg.appendSlice(L.allocator, searcher_err) catch return lauxlib.luaL_error(L, "out of memory");
            msg.appendSlice(L.allocator, "\n\t") catch return lauxlib.luaL_error(L, "out of memory");
            lua.lua_pop(L, 1);
        } else {
            lua.lua_pop(L, 2);
        }
    }
}

fn ll_require(L: *lua.lua_State) anyerror!i32 {
    const name = try lauxlib.luaL_checkstring(L, 1);
    lua.lua_settop(L, 1);
    _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "_LOADED");
    _ = try lua.lua_getfield(L, 2, name);
    if (lua.lua_toboolean(L, -1) != 0) return 1;
    lua.lua_pop(L, 1);
    try findloader(L, name);
    lua.lua_rotate(L, -2, 1);
    lua.lua_pushvalue(L, 1);
    lua.lua_pushvalue(L, -3);
    try lua.lua_call(L, 2, 1);
    if (lua.lua_isnil(L, -1) == 0) {
        try lua.lua_setfield(L, 2, name);
    } else {
        lua.lua_pop(L, 1);
    }
    _ = try lua.lua_getfield(L, 2, name);
    if (lua.lua_type(L, -1) == lua.LUA_TNIL) {
        lua.lua_pushboolean(L, 1);
        lua.lua_copy(L, -1, -2);
        try lua.lua_setfield(L, 2, name);
    }
    lua.lua_rotate(L, -2, 1);
    return 2;
}

fn setprogdir(_: *lua.lua_State) void {}

fn setpath(L: *lua.lua_State, fieldname: []const u8, envname: []const u8, dft: []const u8) !void {
    const nver = try std.fmt.allocPrint(L.allocator, "{s}{s}", .{ envname, LUA_VERSUFFIX });
    defer L.allocator.free(nver);

    var path_opt: ?[]const u8 = lauxlib.luaL_getenv(L, nver) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => null,
    };
    if (path_opt == null) {
        path_opt = lauxlib.luaL_getenv(L, envname) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => null,
        };
    }

    if (path_opt) |path| {
        defer L.allocator.free(path);
        if (try noenv(L)) {
            _ = lua.lua_pushstring(L, dft);
        } else {
            if (std.mem.indexOf(u8, path, ";;")) |dftmark_idx| {
                var b = lauxlib.luaL_Buffer{};
                lauxlib.luaL_buffinit(L, &b);
                errdefer b.buf.deinit(L.allocator);
                if (dftmark_idx > 0) {
                    try lauxlib.luaL_addlstring(L, &b, path[0..dftmark_idx]);
                    try lauxlib.luaL_addlstring(L, &b, ";");
                }
                try lauxlib.luaL_addlstring(L, &b, dft);
                if (dftmark_idx + 2 < path.len) {
                    try lauxlib.luaL_addlstring(L, &b, ";");
                    try lauxlib.luaL_addlstring(L, &b, path[dftmark_idx + 2 ..]);
                }
                lauxlib.luaL_pushresult(L, &b);
            } else {
                _ = lua.lua_pushstring(L, path);
            }
        }
    } else {
        _ = lua.lua_pushstring(L, dft);
    }

    setprogdir(L);
    try lua.lua_setfield(L, -2, fieldname);
}

fn createsearcherstable(L: *lua.lua_State) !void {
    const searchers = [_]lua.lua_CFunction{ searcher_preload, searcher_Lua, searcher_C, searcher_Croot };
    lua.lua_createtable(L, @intCast(searchers.len), 0);
    for (searchers, 1..) |s, i| {
        lua.lua_pushvalue(L, -2);
        lua.lua_pushcclosure(L, s, 1);
        lua.lua_rawseti(L, -2, @intCast(i));
    }
    try lua.lua_setfield(L, -2, "searchers");
}

pub fn openloadlib(L: *lua.lua_State) !void {
    _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, CLIBS);
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        lua.lua_pop(L, 1);
        lua.lua_createtable(L, 0, 1);
        try lua.lua_setfield(L, lua.LUA_REGISTRYINDEX, CLIBS);
    } else {
        lua.lua_pop(L, 1);
    }

    const pk_funcs = [_]lauxlib.luaL_Reg{
        .{ .name = "loadlib", .func = ll_loadlib },
        .{ .name = "searchpath", .func = ll_searchpath },
    };
    try lauxlib.luaL_newlib(L, &pk_funcs);

    try createsearcherstable(L);

    try setpath(L, "path", "LUA_PATH", luaconf.LUA_PATH_DEFAULT);
    try setpath(L, "cpath", "LUA_CPATH", luaconf.LUA_CPATH_DEFAULT);

    const config = try std.fmt.allocPrint(L.allocator, "{s}\n;\n?\n!\n-\n", .{luaconf.LUA_DIRSEP});
    defer L.allocator.free(config);
    _ = lua.lua_pushlstring(L, config, config.len);
    try lua.lua_setfield(L, -2, "config");

    _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "_LOADED");
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        lua.lua_pop(L, 1);
        lua.lua_createtable(L, 0, 1);
        try lua.lua_setfield(L, lua.LUA_REGISTRYINDEX, "_LOADED");
        _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "_LOADED");
    }
    try lua.lua_setfield(L, -2, "loaded");

    _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "_PRELOAD");
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        lua.lua_pop(L, 1);
        lua.lua_createtable(L, 0, 1);
        try lua.lua_setfield(L, lua.LUA_REGISTRYINDEX, "_PRELOAD");
        _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "_PRELOAD");
    }
    try lua.lua_setfield(L, -2, "preload");

    // Set _G["package"] = package
    lua.lua_pushvalue(L, -1);
    lua.lua_setglobal(L, "package");

    // Set _G["require"] = ll_require
    lua.lua_pushvalue(L, -1);
    lua.lua_pushcclosure(L, ll_require, 1);
    lua.lua_setglobal(L, "require");

    // Pop the package table to keep the stack balanced.
    lua.lua_pop(L, 1);
}
