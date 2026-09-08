const std = @import("std");
const lua = @import("lua.zig");
const lauxlib = lua.lauxlib;
const build_options = @import("build_options");

/// Action resulting from -e, -l, -W options.
const OptionAction = union(enum) {
    eval: []const u8,
    lib: []const u8,
    warn_on,
};

/// Result of parsing command-line arguments. Mirrors reference lua.c collectargs.
const ParsedArgs = struct {
    interactive: bool = false,
    show_version: bool = false,
    ignore_env: bool = false,
    has_e: bool = false,
    script_idx: i32 = 0,
    actions: []const OptionAction = &[_]OptionAction{},
};

fn parseArgs(allocator: std.mem.Allocator, args: []const [:0]const u8) !ParsedArgs {
    var result: ParsedArgs = .{};
    var actions = std.ArrayList(OptionAction).empty;

    if (args.len <= 1) {
        result.script_idx = 0;
        return result;
    }

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg.len == 0 or arg[0] != '-') {
            // First non-option is the script
            result.script_idx = @intCast(i);
            break;
        }
        if (std.mem.eql(u8, arg, "--")) {
            // Stop option parsing; next arg is script (or 0 if none)
            if (i + 1 < args.len) {
                result.script_idx = @intCast(i + 1);
            } else {
                result.script_idx = 0;
            }
            break;
        } else if (std.mem.eql(u8, arg, "-")) {
            // Script name is "-"
            result.script_idx = @intCast(i);
            break;
        }

        switch (arg[1]) {
            'E' => {
                if (arg.len != 2) return error.UnrecognizedOption;
                result.ignore_env = true;
            },
            'W' => {
                if (arg.len != 2) return error.UnrecognizedOption;
                try actions.append(allocator, .warn_on);
            },
            'i' => {
                if (arg.len != 2) return error.UnrecognizedOption;
                result.interactive = true;
                result.show_version = true;
            },
            'v' => {
                if (arg.len != 2) return error.UnrecognizedOption;
                result.show_version = true;
            },
            'e' => {
                result.has_e = true;
                const chunk = if (arg.len > 2)
                    arg[2..]
                else blk: {
                    i += 1;
                    if (i >= args.len or (args[i].len > 0 and args[i][0] == '-')) {
                        return error.MissingOptionArgument;
                    }
                    break :blk args[i];
                };
                try actions.append(allocator, .{ .eval = chunk });
            },
            'l' => {
                const lib = if (arg.len > 2)
                    arg[2..]
                else blk: {
                    i += 1;
                    if (i >= args.len or (args[i].len > 0 and args[i][0] == '-')) {
                        return error.MissingOptionArgument;
                    }
                    break :blk args[i];
                };
                try actions.append(allocator, .{ .lib = lib });
            },
            else => return error.UnrecognizedOption,
        }
    }

    result.actions = try actions.toOwnedSlice(allocator);
    return result;
}

fn stderrWrite(io: std.Io, msg: []const u8) !void {
    try std.Io.File.stderr().writeStreamingAll(io, msg);
}

fn stdoutWrite(io: std.Io, msg: []const u8) !void {
    try std.Io.File.stdout().writeStreamingAll(io, msg);
}

/// Error handler used for all protected top-level calls (mirrors lua.c's
/// `msghandler`). Builds a traceback while the call frames are still intact
/// and returns the combined "message\nstack traceback:..." string.
fn msghandler(L: *lua.lua_State) anyerror!i32 {
    const msg = lua.lua_tostring(L, 1);
    if (msg == null) {
        // Non-string error object: try its __tostring metamethod first.
        const has_meta = (lauxlib.luaL_callmeta(L, 1, "__tostring") catch 0) != 0;
        if (has_meta and lua.lua_type(L, -1) == lua.LUA_TSTRING) {
            return 1; // __tostring produced a string; return it as-is.
        }
        if (lua.lua_tostring(L, -1)) |_| {
            lua.lua_pop(L, 1); // discard a non-string __tostring result
        }
        const tname = lauxlib.luaL_typename(L, 1) catch "?";
        const buf = std.fmt.allocPrint(L.allocator, "(error object is a {s} value)", .{tname}) catch null;
        if (buf) |b| {
            defer L.allocator.free(b);
            try lauxlib.luaL_traceback(L, L, b, 1);
        } else {
            try lauxlib.luaL_traceback(L, L, "(error)", 1);
        }
    } else {
        try lauxlib.luaL_traceback(L, L, msg.?, 1);
    }
    return 1;
}

/// Protected call wrapper (mirrors lua.c's `docall`): push `msghandler` under
/// the function+args and run it as the error function so uncaught errors get
/// a full stack traceback. Returns the pcall status.
fn pcallWithHandler(L: *lua.lua_State, nargs: i32) i32 {
    const base = lua.lua_gettop(L) - nargs; // index of the target function
    lua.lua_pushcfunction(L, msghandler);
    lua.lua_insert(L, base); // insert msghandler immediately before function
    const status = lua.lua_pcallk(L, nargs, lua.LUA_MULTRET, base, 0, null) catch |e| {
        return if (e == error.Yield) lua.LUA_YIELD else lua.LUA_ERRRUN;
    };
    lua.lua_remove(L, base);
    return status;
}

/// Run a chunk already loaded at the top of the stack (with `nargs` extra
/// arguments just below it). Returns true if an error occurred.
fn runLoadedChunk(L: *lua.lua_State, io: std.Io, progname: ?[]const u8, nargs: i32) !bool {
    const status = pcallWithHandler(L, nargs);
    if (status != lua.LUA_OK) {
        printError(L, io, progname);
        return true;
    }
    lua.lua_settop(L, 0);
    return false;
}

/// Print a top-level error message to stderr, prefixed by progname if present.
fn printError(L: *lua.lua_State, io: std.Io, progname: ?[]const u8) void {
    if (progname) |pname| {
        if (pname.len > 0) {
            stderrWrite(io, pname) catch {};
            stderrWrite(io, ": ") catch {};
        }
    }
    if (lua.lua_tostring(L, -1)) |msg| {
        stderrWrite(io, msg) catch {};
        stderrWrite(io, "\n") catch {};
    } else {
        stderrWrite(io, "(error object is not a string)\n") catch {};
        stderrWrite(io, "type: ") catch {};
        stderrWrite(io, lua.lua_typename(lua.lua_type(L, -1))) catch {};
        stderrWrite(io, "\n") catch {};
        _ = lauxlib.luaL_traceback(L, L, "", 1) catch {};
        if (lua.lua_tostring(L, -1)) |tb| {
            stderrWrite(io, tb) catch {};
            stderrWrite(io, "\n") catch {};
        }
    }
    lua.lua_pop(L, 1);
}

/// Pretty-print a stack value. Tables are expanded (shallow, with a depth cap)
/// so the REPL shows their contents instead of just "table: 0x...".
fn printValue(L: *lua.lua_State, io: std.Io, index: i32, depth: usize) !void {
    const abs = lua.lua_absindex(L, index);
    const t = lua.lua_type(L, abs);
    if (t == lua.LUA_TTABLE) {
        if (depth >= 3) {
            const s = (try lauxlib.luaL_tolstring(L, abs, null)) orelse "table";
            try stdoutWrite(io, s);
            lua.lua_pop(L, 1);
            return;
        }
        try stdoutWrite(io, "{");
        lua.lua_pushnil(L);
        var first = true;
        while ((try lua.lua_next(L, abs)) != 0) {
            if (!first) try stdoutWrite(io, ", ");
            first = false;
            try printValue(L, io, -2, depth + 1); // key
            try stdoutWrite(io, "=");
            try printValue(L, io, -1, depth + 1); // value
            lua.lua_pop(L, 1); // pop value, keep key for next iteration
        }
        try stdoutWrite(io, "}");
    } else {
        const s = (try lauxlib.luaL_tolstring(L, abs, null)) orelse "nil";
        try stdoutWrite(io, s);
        lua.lua_pop(L, 1); // pop the string pushed by luaL_tolstring
    }
}

fn printResults(L: *lua.lua_State, io: std.Io) !void {
    const top = lua.lua_gettop(L);
    if (top == 0) return;
    var i: i32 = 1;
    while (i <= top) : (i += 1) {
        try printValue(L, io, i, 0);
        if (i < top) try stdoutWrite(io, "\t");
    }
    try stdoutWrite(io, "\n");
    lua.lua_settop(L, 0);
}

fn runString(L: *lua.lua_State, io: std.Io, progname: ?[]const u8, s: []const u8, name: []const u8) !bool {
    const load_status = lauxlib.luaL_loadbufferx(L, s, name, "t");
    if (load_status != lua.LUA_OK) {
        printError(L, io, progname);
        return true;
    }
    return try runLoadedChunk(L, io, progname, 0);
}

/// Require a library by name: 'globname[=modname]' -> globname = require(modname).
fn doLibrary(L: *lua.lua_State, io: std.Io, progname: ?[]const u8, name: []const u8) !bool {
    var globname = name;
    var modname = name;
    if (std.mem.indexOfScalar(u8, name, '=')) |eq_idx| {
        globname = name[0..eq_idx];
        modname = name[eq_idx + 1 ..];
    } else if (std.mem.indexOfScalar(u8, name, '-')) |dash_idx| {
        globname = name[0..dash_idx];
    }

    _ = lua.lua_getglobal(L, "require");
    if (lua.lua_type(L, -1) != lua.LUA_TFUNCTION) {
        lua.lua_pop(L, 1);
        return false;
    }
    _ = lua.lua_pushstring(L, modname);
    const status = pcallWithHandler(L, 1);
    if (status == lua.LUA_OK) {
        try lua.lua_setglobal(L, globname);
        return false;
    }
    printError(L, io, progname);
    return true;
}

fn handleLuainit(L: *lua.lua_State, io: std.Io, progname: []const u8) !bool {
    const vinit = try lauxlib.luaL_getenv(L, "LUA_INIT_5_5");
    var init_str = vinit;
    var name: []const u8 = "=LUA_INIT_5_5";
    if (init_str == null) {
        init_str = try lauxlib.luaL_getenv(L, "LUA_INIT");
        name = "=LUA_INIT";
    }
    if (init_str) |s| {
        defer L.allocator.free(s);
        if (s.len > 0 and s[0] == '@') {
            const fname = s[1..];
            const load_status = lauxlib.luaL_loadfilex(L, fname, "bt");
            if (load_status != lua.LUA_OK) {
                printError(L, io, progname);
                return true;
            }
            return try runLoadedChunk(L, io, progname, 0);
        } else {
            return try runString(L, io, progname, s, name);
        }
    }
    return false;
}

/// Push script arguments from table 'arg' (1 to #arg) onto the stack.
fn pushargs(L: *lua.lua_State) !i32 {
    _ = lua.lua_getglobal(L, "arg");
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        lua.lua_pop(L, 1);
        return 0;
    }
    const n: i32 = @intCast(try lauxlib.luaL_len(L, -1));
    _ = lua.lua_checkstack(L, n + 3);
    var i: i32 = 1;
    while (i <= n) : (i += 1) {
        _ = lua.lua_rawgeti(L, -i, i);
    }
    lua.lua_remove(L, -(n + 1)); // remove arg table from the stack
    return n;
}

fn readAllStdin(io: std.Io, gpa: std.mem.Allocator) ![]u8 {
    var list = std.ArrayList(u8).empty;
    errdefer list.deinit(gpa);
    var chunk: [4096]u8 = undefined;
    while (true) {
        const n = std.Io.File.stdin().readStreaming(io, &.{&chunk}) catch |err| {
            if (err == error.EndOfStream) break;
            return err;
        };
        if (n == 0) break;
        try list.appendSlice(gpa, chunk[0..n]);
    }
    return list.toOwnedSlice(gpa);
}

fn runRepl(L: *lua.lua_State, io: std.Io, gpa: std.mem.Allocator, print_banner: bool) !void {
    if (print_banner) {
        try stdoutWrite(io, lua.LUA_COPYRIGHT);
        try stdoutWrite(io, "\n");
        try stdoutWrite(io, lua.LUA_PORT_COPYRIGHT);
        try stdoutWrite(io, "\n");
    }
    var accum = std.ArrayList(u8).empty;
    defer accum.deinit(gpa);
    // Buffer stdin through std.Io's reader so a single read does not consume
    // more than one line (which would discard the rest of multi-line input).
    var read_buf: [4096]u8 = undefined;
    var file_reader = std.Io.File.Reader.init(std.Io.File.stdin(), io, &read_buf);
    const reader = &file_reader.interface;

    while (true) {
        try stdoutWrite(io, if (accum.items.len == 0) "> " else ">> ");
        const line = reader.takeDelimiter('\n') catch |err| {
            return err;
        } orelse break;

        if (accum.items.len == 0) {
            if (line.len == 0) continue;
            if (std.mem.eql(u8, line, "exit") or std.mem.eql(u8, line, "quit")) break;
        }

        try accum.appendSlice(gpa, line);
        try accum.append(gpa, '\n');

        // Try to compile the accumulated input.
        const status = lauxlib.luaL_loadstring(L, accum.items);
        if (status == lua.LUA_OK) {
            const call_status = pcallWithHandler(L, 0);
            if (call_status != lua.LUA_OK) {
                printError(L, io, null);
            } else {
                try printResults(L, io);
            }
            accum.clearRetainingCapacity();
        } else if (status == lua.LUA_ERRSYNTAX) {
            const incomplete = blk: {
                if (lua.lua_tostring(L, -1)) |msg| {
                    if (std.mem.indexOf(u8, msg, "<eof>") != null or
                        std.mem.indexOf(u8, msg, "<EOF>") != null)
                    {
                        break :blk true;
                    }
                }
                break :blk false;
            };
            if (incomplete) {
                lua.lua_pop(L, 1); // discard the incomplete-input error
                continue;
            }
            printError(L, io, null);
            accum.clearRetainingCapacity();
        } else {
            printError(L, io, null);
            accum.clearRetainingCapacity();
        }
    }
}

pub fn main(init: std.process.Init) !u8 {
    var dbg_alloc = std.heap.DebugAllocator(.{ .safety = true }).init;
    var gpa: std.mem.Allocator = if (build_options.asan or build_options.debug_alloc)
        dbg_alloc.allocator()
    else
        init.gpa;
    defer _ = dbg_alloc.deinit();
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    const progname = if (args.len > 0) args[0] else "luazig";

    const L = try gpa.create(lua.lua_State);
    defer gpa.destroy(L);
    try lua.luaL_newstate_io(L, gpa, io);
    defer lua.lua_close(L);

    const parsed = parseArgs(arena, args) catch |err| {
        switch (err) {
            error.MissingOptionArgument => try stderrWrite(io, "luazig: option requires an argument\n"),
            error.UnrecognizedOption => try stderrWrite(io, "luazig: unrecognized option\n"),
            else => try stderrWrite(io, "luazig: invalid arguments\n"),
        }
        return 1;
    };

    if (parsed.show_version) {
        try stdoutWrite(io, lua.LUA_COPYRIGHT);
        try stdoutWrite(io, "\n");
        try stdoutWrite(io, lua.LUA_PORT_COPYRIGHT);
        try stdoutWrite(io, "\n");
    }

    if (parsed.ignore_env) {
        _ = lua.lua_pushboolean(L, 1);
        try lua.lua_setfield(L, lua.LUA_REGISTRYINDEX, "LUA_NOENV");
    }

    try lua.luaL_openlibs(L);

    // Build the `arg` table with negative, zero, and positive indices.
    var argv_list = std.ArrayList([]const u8).empty;
    for (args) |a| try argv_list.append(arena, a);
    try lua.createargtable(L, argv_list.items, parsed.script_idx);

    var had_error = false;

    if (!parsed.ignore_env) {
        if (try handleLuainit(L, io, progname)) {
            had_error = true;
        }
    }

    if (!had_error) {
        for (parsed.actions) |act| {
            switch (act) {
                .eval => |chunk| {
                    if (try runString(L, io, progname, chunk, "=(command line)")) {
                        had_error = true;
                        break;
                    }
                },
                .lib => |lib| {
                    if (try doLibrary(L, io, progname, lib)) {
                        had_error = true;
                        break;
                    }
                },
                .warn_on => {
                    lua.lua_warning(L, "@on", 0);
                },
            }
        }
    }

    if (!had_error and parsed.script_idx > 0) {
        const s = args[@as(usize, @intCast(parsed.script_idx))];
        const is_stdin = std.mem.eql(u8, s, "-") and
            !(parsed.script_idx > 1 and std.mem.eql(u8, args[@as(usize, @intCast(parsed.script_idx - 1))], "--"));
        if (is_stdin) {
            const content = try readAllStdin(io, gpa);
            defer gpa.free(content);
            const load_status = lauxlib.luaL_loadbufferx(L, content, "=stdin", "bt");
            if (load_status != lua.LUA_OK) {
                printError(L, io, progname);
                had_error = true;
            } else {
                const nparams = try pushargs(L);
                had_error = (try runLoadedChunk(L, io, progname, nparams)) or had_error;
            }
        } else {
            const load_status = lauxlib.luaL_loadfilex(L, s, "bt");
            if (load_status != lua.LUA_OK) {
                printError(L, io, progname);
                had_error = true;
            } else {
                const nparams = try pushargs(L);
                had_error = (try runLoadedChunk(L, io, progname, nparams)) or had_error;
            }
        }
    }

    if (!had_error) {
        if (parsed.interactive) {
            try runRepl(L, io, gpa, false);
        } else if (parsed.script_idx < 1 and !parsed.has_e and !parsed.show_version) {
            if (std.c.isatty(0) != 0) {
                try stdoutWrite(io, lua.LUA_COPYRIGHT);
                try stdoutWrite(io, "\n");
                try stdoutWrite(io, lua.LUA_PORT_COPYRIGHT);
                try stdoutWrite(io, "\n");
                try runRepl(L, io, gpa, false);
            } else {
                const content = try readAllStdin(io, gpa);
                defer gpa.free(content);
                const load_status = lauxlib.luaL_loadbufferx(L, content, "=stdin", "bt");
                if (load_status != lua.LUA_OK) {
                    printError(L, io, progname);
                    had_error = true;
                } else {
                    had_error = (try runLoadedChunk(L, io, progname, 0)) or had_error;
                }
            }
        }
    }

    if (had_error) {
        return 1;
    }
    return 0;
}
