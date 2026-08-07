const std = @import("std");
const lua = @import("lua.zig");
const lauxlib = lua.lauxlib;
const build_options = @import("build_options");

/// Result of parsing the command-line arguments (everything after the
/// program name). Mirrors the reference standalone interpreter:
///   luazig [options] [script [args]]
/// Options: -e chunk, -l name, -i, -v, -- (stop options), - (stdin script).
const ParsedArgs = struct {
    interactive: bool = false,
    show_version: bool = false,
    script: ?[]const u8 = null,
    extra_args: []const [:0]const u8 = &[_][:0]const u8{},
    e_chunks: [][]const u8 = &[_][]const u8{},
    l_libs: [][]const u8 = &[_][]const u8{},
};

fn parseArgs(allocator: std.mem.Allocator, args: []const [:0]const u8) !ParsedArgs {
    var result: ParsedArgs = .{};
    var e_list = std.ArrayList([]const u8).empty;
    var l_list = std.ArrayList([]const u8).empty;

    var i: usize = 1; // args[0] is the program name
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            // Stop option parsing; the next argument (if any) is the script.
            i += 1;
            if (i < args.len) {
                result.script = args[i];
                i += 1;
            }
            break;
        } else if (std.mem.eql(u8, arg, "-")) {
            // Read the script from stdin.
            result.script = "-";
            i += 1;
            break;
        } else if (arg.len >= 2 and arg[0] == '-') {
            switch (arg[1]) {
                'e' => {
                    if (i + 1 >= args.len) {
                        return error.MissingOptionArgument;
                    }
                    try e_list.append(allocator, args[i + 1]);
                    i += 1;
                },
                'l' => {
                    if (i + 1 >= args.len) {
                        return error.MissingOptionArgument;
                    }
                    try l_list.append(allocator, args[i + 1]);
                    i += 1;
                },
                'i' => result.interactive = true,
                'v' => result.show_version = true,
                else => return error.UnrecognizedOption,
            }
        } else {
            // First non-option argument is the script file.
            result.script = arg;
            i += 1;
            break;
        }
    }

    result.extra_args = if (result.script != null) args[i..] else &[_][:0]const u8{};
    result.e_chunks = try e_list.toOwnedSlice(allocator);
    result.l_libs = try l_list.toOwnedSlice(allocator);
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
fn runLoadedChunk(L: *lua.lua_State, io: std.Io, nargs: i32) !bool {
    const status = pcallWithHandler(L, nargs);
    if (status != lua.LUA_OK) {
        printError(L, io);
        return true;
    }
    lua.lua_settop(L, 0);
    return false;
}

/// Print a top-level error message (already carrying a traceback, courtesy of
/// `msghandler`) to stderr.
fn printError(L: *lua.lua_State, io: std.Io) void {
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
            const s = lauxlib.luaL_tolstring(L, abs, null) orelse "table";
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
        const s = lauxlib.luaL_tolstring(L, abs, null) orelse "nil";
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

fn runString(L: *lua.lua_State, io: std.Io, s: []const u8, name: []const u8) !bool {
    const load_status = lauxlib.luaL_loadbufferx(L, s, name, "t");
    if (load_status != lua.LUA_OK) {
        printError(L, io);
        return true;
    }
    return try runLoadedChunk(L, io, 0);
}

/// Require a library by name. Built-in libraries are already globals after
/// luaL_openlibs, so we register them in package.loaded; otherwise we defer to
/// require().
fn doLibrary(L: *lua.lua_State, io: std.Io, name: []const u8) !bool {
    _ = lua.lua_getglobal(L, name);
    if (lua.lua_isnil(L, -1) == 0) {
        // Already a global: register it in package.loaded[name].
        _ = try lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, lauxlib.LUA_LOADED_TABLE);
        lua.lua_pushvalue(L, -2);
        try lua.lua_setfield(L, -2, name);
        lua.lua_pop(L, 2);
        return false;
    }
    lua.lua_pop(L, 1);

    // Not a global: try require(name).
    _ = lua.lua_getglobal(L, "require");
    if (lua.lua_type(L, -1) != lua.LUA_TFUNCTION) {
        lua.lua_pop(L, 1);
        return false;
    }
    _ = lua.lua_pushstring(L, name);
    const status = pcallWithHandler(L, 1);
    if (status == lua.LUA_OK) {
        try lua.lua_setglobal(L, name);
        return false;
    }
    printError(L, io);
    return true;
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
    // Keep the Io.Reader as a pointer into file_reader: its vtable uses
    // fieldParentPtr("interface", ...) to recover the owning Io.File.Reader,
    // which only works while the reader lives inside the struct instance.
    const reader = &file_reader.interface;

    while (true) {
        try stdoutWrite(io, if (accum.items.len == 0) "> " else ">> ");
        // Read one line (excluding the trailing newline). A trailing line
        // without a newline, or EOF, ends the REPL.
        const line = reader.takeDelimiter('\n') catch |err| {
            return err;
        } orelse break;

        if (accum.items.len == 0) {
            if (line.len == 0) continue;
            if (std.mem.eql(u8, line, "exit") or std.mem.eql(u8, line, "quit")) break;
        }

        try accum.appendSlice(gpa, line);
        try accum.append(gpa, '\n');

        // Try to compile the accumulated input. A successful compile means the
        // statement(s) are complete; a syntax error mentioning <eof> means we
        // need to keep reading (multi-line input).
        const status = lauxlib.luaL_loadstring(L, accum.items);
        if (status == lua.LUA_OK) {
            const call_status = pcallWithHandler(L, 0);
            if (call_status != lua.LUA_OK) {
                printError(L, io);
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
            printError(L, io);
            accum.clearRetainingCapacity();
        } else {
            printError(L, io);
            accum.clearRetainingCapacity();
        }
    }
}

pub fn main(init: std.process.Init) !void {
    // Memory-safety allocator selection (mirror talyn's asan/debug-alloc):
    //  - asan: build with sanitize_c = .full (the C sanitizer / UBSan), which
    //    instruments the binary for undefined-behaviour checks, and use a
    //    safety-checked DebugAllocator so heap double-free / use-after-free are
    //    also caught at runtime.
    //  - debug-alloc: use a safety-checked DebugAllocator so heap double-free /
    //    use-after-free / leaks are caught at runtime. Zig 0.16 has no
    //    first-class AddressSanitizer for Zig heaps (only -fsanitize-c / UBSan
    //    and -fsanitize-thread / TSan), so this is the Zig-native equivalent.
    //  - default: the process-provided general-purpose allocator.
    var dbg_alloc = std.heap.DebugAllocator(.{ .safety = true }).init;
    var gpa: std.mem.Allocator = if (build_options.asan or build_options.debug_alloc)
        dbg_alloc.allocator()
    else
        init.gpa;
    defer _ = dbg_alloc.deinit();
    const io = init.io;
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    const L = try gpa.create(lua.lua_State);
    defer gpa.destroy(L);
    try lua.luaL_newstate_io(L, gpa, io);
    try lua.luaL_openlibs(L);
    // Close on every exit path (including option-parse errors) so the Lua
    // state and all its allocations are released.
    defer lua.lua_close(L);

    const parsed = parseArgs(arena, args) catch |err| {
        switch (err) {
            error.MissingOptionArgument => try stderrWrite(io, "lua: option requires an argument\n"),
            error.UnrecognizedOption => try stderrWrite(io, "lua: unrecognized option\n"),
            else => try stderrWrite(io, "lua: invalid arguments\n"),
        }
        return err;
    };

    // Build the `arg` table. createargtable expects args[0]=prog, args[1]=script,
    // args[2..]=extra args. When there is no script the table is left empty.
    var effective = std.ArrayList([]const u8).empty;
    try effective.append(arena, args[0]);
    if (parsed.script) |s| try effective.append(arena, s);
    for (parsed.extra_args) |ea| try effective.append(arena, ea);
    try lua.createargtable(L, effective.items);

    if (parsed.show_version) {
        try stdoutWrite(io, lua.LUA_COPYRIGHT);
        try stdoutWrite(io, "\n");
        try stdoutWrite(io, lua.LUA_PORT_COPYRIGHT);
        try stdoutWrite(io, "\n");
    }

    var had_error = false;

    for (parsed.e_chunks) |chunk| {
        had_error = (try runString(L, io, chunk, "=(command line)")) or had_error;
    }

    for (parsed.l_libs) |lib| {
        had_error = (try doLibrary(L, io, lib)) or had_error;
    }

    if (parsed.script) |s| {
        if (std.mem.eql(u8, s, "-")) {
            const content = try readAllStdin(io, gpa);
            defer gpa.free(content);
            had_error = (try runString(L, io, content, "=stdin")) or had_error;
        } else {
            const load_status = lauxlib.luaL_loadfilex(L, s, "bt");
            if (load_status != lua.LUA_OK) {
                printError(L, io);
                had_error = true;
            } else {
                had_error = (try runLoadedChunk(L, io, 0)) or had_error;
            }
        }
    }

    // Enter the REPL when -i is given, or when there is no script and no -e.
    // REPL errors do not affect the process exit code (mirrors lua.c).
    if (parsed.interactive or (parsed.script == null and parsed.e_chunks.len == 0)) {
        try runRepl(L, io, gpa, !parsed.show_version);
    }

    if (had_error) {
        std.process.exit(1);
    }
}
