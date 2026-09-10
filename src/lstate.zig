// $Id: lstate.zig $
//! State lifecycle (port of lstate.c) - moved from lua.zig
//! (Refactor B5, pure move; re-exported by lua.zig for callers).
//! NOTE: this filename previously hosted a stale duplicate that was
//! deleted; this module is the real state-lifecycle block.

const std = @import("std");
const lua = @import("lua.zig");
const llimits = @import("llimits.zig");
const lstring = @import("lstring.zig");
const ltable = @import("ltable.zig");
const ltm = @import("ltm.zig");
const lauxlib = @import("lauxlib.zig");

pub fn growStack(L: *lua.lua_State, needed: usize) !void {
    if (needed <= L.stack.len) return;
    // Normal stack growth never crosses the working limit; the llimits.ERRORSTACKSIZE
    // headroom is reserved separately (see reserveErrorStack) only when a
    // stack overflow is about to be raised, mirroring luaD_growstack.
    if (needed > llimits.LUAI_MAXSTACK) return error.StackOverflow;
    const new_cap = @min(@max(L.stack.len * 2, needed + llimits.LUA_MINSTACK + 20), llimits.LUAI_MAXSTACK);
    try reallocStack(L, new_cap);
}

/// Reserve the error-handling headroom: grow the stack to llimits.ERRORSTACKSIZE so
/// the error handler (e.g. debug.traceback) can run after a stack overflow.
pub fn reserveErrorStack(L: *lua.lua_State) !void {
    if (L.stack.len >= llimits.ERRORSTACKSIZE) return;
    try reallocStack(L, llimits.ERRORSTACKSIZE);
}


/// Shrink the stack back to a reasonable size after it was overgrown (e.g. by
/// a stack overflow). Mirrors luaD_shrinkstack: notably, it does NOT shrink
/// when the stack is still being used at/over the working limit (inuse >
/// llimits.MAXSTACK), because that is the error-handling recursion, which must keep
/// the llimits.ERRORSTACKSIZE headroom for nested handler invocations.
pub fn shrinkStack(L: *lua.lua_State) void {
    var lim = L.top;
    var ci = L.ci;
    while (ci) |c| {
        if (lim < c.top) lim = c.top;
        ci = c.previous;
    }
    const inuse = @max(lim, @as(usize, @intCast(llimits.LUA_MINSTACK))) + 1;
    const max = if (inuse > llimits.LUAI_MAXSTACK / 3) llimits.LUAI_MAXSTACK else inuse * 3;
    if (inuse <= llimits.LUAI_MAXSTACK and L.stack.len > max) {
        _ = reallocStack(L, @max(max, @as(usize, @intCast(llimits.LUA_MINSTACK)))) catch {}; // stack shrinking is a best-effort optimization
    }
}

pub fn reallocStack(L: *lua.lua_State, new_cap: usize) !void {
    const old_ptr = L.stack.ptr;
    const old_len = L.stack.len;
    const old_base = @intFromPtr(old_ptr);
    const old_end = old_base + old_len * @sizeOf(lua.TValue);
    L.stack = try L.allocator.realloc(L.stack, new_cap);
    var curr = L.openupval;
    while (curr) |uv| {
        const uv_addr = @intFromPtr(uv.v);
        if (uv_addr >= old_base and uv_addr < old_end) {
            const uv_idx = (uv_addr -| old_base) / @sizeOf(lua.TValue);
            uv.v = &L.stack[uv_idx];
        }
        curr = uv.next;
    }
    // BUG-088: Also fix up open upvalue pointers of all other threads in the
    // same state.  An upvalue on a suspended coroutine may point into this
    // thread's stack; if we only update L.openupval the secondary thread
    // retains dangling pointers after reallocation.
    if (L.l_G) |g| {
        var th: ?*lua.lua_State = g.thread_list;
        while (th) |t| {
            if (t != L) {
                var uv2 = t.openupval;
                while (uv2) |uv2_| {
                    const uv_addr2 = @intFromPtr(uv2_.v);
                    if (uv_addr2 >= old_base and uv_addr2 < old_end) {
                        const uv_idx2 = (uv_addr2 -| old_base) / @sizeOf(lua.TValue);
                        uv2_.v = &L.stack[uv_idx2];
                    }
                    uv2 = uv2_.next;
                }
            }
            th = t.twups;
        }
    }
    if (new_cap > old_len) {
        @memset(L.stack[old_len..new_cap], .{ .nil = {} });
    }
    L.stack_last = L.stack.len - 1;
}

pub fn lua_checkstack(L: *lua.lua_State, n: i32) i32 {
    if (n <= 0) return 1;
    const extra = @as(usize, @intCast(n));
    if (extra > llimits.LUAI_MAXSTACK) return 0;
    const needed = L.top + extra;
    // The stack may grow past llimits.LUAI_MAXSTACK up to llimits.ERRORSTACKSIZE: that
    // headroom is what lets the error handler (debug.traceback) run after a
    // stack overflow (mirrors luaD_growstack's 'llimits.ERRORSTACKSIZE' branch).
    if (needed > llimits.ERRORSTACKSIZE) return 0;
    growStack(L, needed) catch return 0;
    return 1;
}

pub fn lua_xmove(from: *lua.lua_State, to: *lua.lua_State, n: i32) void {
    if (from == to or n <= 0) return;
    const nn = @as(usize, @intCast(n));
    if (from.l_G != to.l_G) return;
    if (nn > from.top) return;
    _ = lua_checkstack(to, n);
    if (to.top + nn > to.stack.len) return;
    @memcpy(to.stack[to.top..][0..nn], from.stack[from.top - nn .. from.top]);
    from.top -= nn;
    to.top += nn;
}

pub fn lua_newthread(L: *lua.lua_State) !*lua.lua_State {
    const g = lua.G(L);
    const L1 = try L.allocator.create(lua.lua_State);
    errdefer L.allocator.destroy(L1);
    const stack = try L.allocator.alloc(lua.TValue, llimits.LUA_MINSTACK + 1);
    for (stack) |*item| {
        item.* = .{ .nil = {} };
    }
    errdefer L.allocator.free(stack);
    L1.* = .{
        .tt = 0,
        .marked = 0,
        .gch = 0,
        .allowhook = 1,
        .status = 0,
        .top = 1,
        .l_G = g,
        .ci = null,
        .stack = stack,
        .stack_last = stack.len - 1,
        .openupval = null,
        .tbclist = .empty,
        .gclist = null,
        .twups = null,
        .errorJmp = null,
        .base_ci = .{ .func = 0, .base = 1, .top = llimits.LUA_MINSTACK, .nresults = 0, .savedpc = 0, .previous = null, .next = null, .k = null, .ctx = 0, .nyield = 0 },
        .hook = null,
        .errfunc = 0,
        .nCcalls = 0,
        .oldpc = 0,
        .nci = 0,
        .basehookcount = 0,
        .hookcount = 0,
        .hookmask = 0,
        .transferinfo = .{ .ftransfer = 0, .ntransfer = 0 },
        .allocator = L.allocator,
    };
    L1.ci = &L1.base_ci;
    L1.twups = g.thread_list;
    g.thread_list = L1;
    try lua.registerGC(L, L1);
    try growStack(L, L.top + 1);
    L.stack[L.top] = lua.TValue{ .thread = L1 };
    L.top += 1;
    lua.luaC_condGC(L);
    return L1;
}

pub fn lua_closethread(L: *lua.lua_State, from: ?*lua.lua_State) i32 {
    L.nCcalls = if (from) |f| f.nCcalls else 0;
    const old_status = L.status;

    // Re-entrancy guard (BUG-168): a `__close` metamethod may call
    // `coroutine.close(co)` on the very thread being closed. The outer
    // `lua_closethread` set `close_in_progress` before running `closeupvals`,
    // so this nested call must NOT re-run the destructive teardown —
    // `closeupvals` would re-enter the still-active TBC loop and
    // `freeAllCallInfos` would free the live lua.CallInfo chain that the outer
    // close (and its `__close` C frames, whose `luaT_callTM*` handlers keep a
    // pointer to `old_ci`) still use. Just finalize the status and return;
    // the outer close performs the real teardown.
    if (L.close_in_progress) {
        L.top = 1;
        if (L.top < L.stack.len) {
            @memset(L.stack[L.top..], .{ .nil = {} });
        }
        L.status = lua.LUA_OK;
        return lua.LUA_OK;
    }
    L.close_in_progress = true;
    defer L.close_in_progress = false;

    var err_val: ?lua.TValue = if (old_status != 0 and old_status != lua.LUA_YIELD)
        (if (L.err_obj != .nil) L.err_obj else if (L.top > 0) L.stack[L.top - 1] else null)
    else
        null;

    // Close all upvalues and TBC variables on the thread stack.
    // Index 1 corresponds to stack[1], since stack[0] is the thread function.
    var close_err = false;
    lua.closeupvals(L, 1, err_val) catch {
        // A __close metamethod raised while closing; its error replaces the
        // thread's error (mirrors luaE_resetthread -> luaF_close).
        close_err = true;
        if (L.err_obj != .nil) {
            err_val = L.err_obj;
        } else if (L.top > 0) {
            err_val = L.stack[L.top - 1];
        }
    };

    // A self-close (L == from, e.g. `coroutine.close()` inside the coroutine
    // it is closing) must NOT destroy the lua.CallInfo chain here: the thread
    // still has active frames (the running `__close` / pcall machinery) that
    // the `error.ThreadClosed` unwind traverses, and destroying them would be
    // a use-after-free. Instead recycle them into the freelist and reset
    // `L.ci` to the base CI so the thread is logically terminated (BUG-168).
    // An external close (from a different thread, or `from == null`) does the
    // real teardown.
    if (from == null or from != L) {
        lua.freeAllCallInfos(L);
    } else {
        lua.recycleCallInfos(L);
    }

    if (close_err) {
        if (L.stack.len > 1) {
            L.stack[1] = err_val.?;
            L.top = 2;
        } else {
            L.top = 1;
        }
        if (L.top < L.stack.len) {
            @memset(L.stack[L.top..], .{ .nil = {} });
        }
        L.status = lua.LUA_ERRRUN;
        L.close_err_consumed = true;
        return lua.LUA_ERRRUN;
    }

    if (old_status != 0 and old_status != lua.LUA_YIELD) {
        if (L.close_err_consumed) {
            // This thread's close error was already reported by a previous
            // close; a re-close is clean (coroutine.lua: "after closing, no
            // more errors").
            L.top = 1;
            if (L.top < L.stack.len) {
                @memset(L.stack[L.top..], .{ .nil = {} });
            }
            L.status = lua.LUA_OK;
            return lua.LUA_OK;
        }
        if (err_val) |ev| {
            if (L.stack.len > 1) {
                L.stack[1] = ev;
                L.top = 2;
            } else {
                L.top = 1;
            }
        } else {
            L.top = 1;
        }
        if (L.top < L.stack.len) {
            @memset(L.stack[L.top..], .{ .nil = {} });
        }
        L.status = old_status;
        L.close_err_consumed = true;
        return old_status;
    } else {
        L.top = 1;
        if (L.top < L.stack.len) {
            @memset(L.stack[L.top..], .{ .nil = {} });
        }
        L.status = lua.LUA_OK;
        L.close_err_consumed = false;
        return lua.LUA_OK;
    }
}

pub fn luaE_warning(L: *lua.lua_State, msg: []const u8, tocont: i32) void {
    if (L.l_G) |g| {
        if (g.warnf) |wf| {
            wf(g.ud_warn, msg, tocont);
        }
    }
}

pub fn luaE_warnerror(L: *lua.lua_State, where: []const u8) void {
    const errobj = if (L.top > 0) L.stack[L.top - 1] else lua.TValue{ .nil = {} };
    const msg: []const u8 = switch (errobj) {
        .string => |ts| if (ts) |s| s.s else "error object is not a string",
        else => "error object is not a string",
    };
    luaE_warning(L, "error in ", 1);
    luaE_warning(L, where, 1);
    luaE_warning(L, " (", 1);
    luaE_warning(L, msg, 1);
    luaE_warning(L, ")", 0);
}

pub fn lua_setwarnf(L: *lua.lua_State, f: ?lua.lua_WarnFunction, ud: ?*anyopaque) void {
    if (L.l_G) |g| {
        g.warnf = f;
        g.ud_warn = ud;
    }
}

pub fn lua_warning(L: *lua.lua_State, msg: []const u8, tocont: i32) void {
    luaE_warning(L, msg, tocont);
    lua.luaC_condGC(L);
}

pub fn luaL_newstate_io(L: *lua.lua_State, gpa: std.mem.Allocator, io: std.Io) !void {
    const g = try gpa.create(lua.global_State);
    g.* = .{
        .allocator = gpa,
        .allocf = &lua.l_alloc,
        .alloc_ud = null,
        .alloc_wrapper = .{ .alloc = gpa },
        .strt = std.array_hash_map.String(*lua.lua_TString).empty,
        .seed = @intFromPtr(L) ^ 0x9e3779b97f4a7c15,
        .registry = lua.TValue{ .nil = {} },
        .mt = [_]?*lua.lua_Table{null} ** 9,
        .tmname = [_]?*lua.lua_TString{null} ** 25,
        .io_backend = null,
        .io = io,
        .prng_state = [_]u64{ 0, 0, 0, 0 },
        .clibs = .empty,
    };
    g.prng_state[0] = g.seed;
    g.prng_state[1] = 0xff;
    g.prng_state[2] = 0;
    g.prng_state[3] = 0;
    {
        var i: i32 = 0;
        while (i < 16) : (i += 1) {
            const s0 = g.prng_state[0];
            const s1 = g.prng_state[1];
            const s2 = g.prng_state[2] ^ s0;
            const s3 = g.prng_state[3] ^ s1;
            g.prng_state[0] = s0 ^ s3;
            g.prng_state[1] = s1 ^ s2;
            g.prng_state[2] = s2 ^ (s1 << 17);
            g.prng_state[3] = (s3 << 45) | (s3 >> 19);
        }
    }
    g.alloc_ud = @ptrCast(&g.alloc_wrapper);
    // Initialize the API string cache to empty (all slots null).
    for (&g.strcache) |*bucket| {
        for (bucket) |*slot| slot.* = null;
    }
    const stack = try gpa.alloc(lua.TValue, llimits.LUA_MINSTACK + 1);
    for (stack) |*item| {
        item.* = .{ .nil = {} };
    }
    L.* = .{
        .tt = 0,
        .marked = 0,
        .gch = 0,
        .allowhook = 1,
        .status = 0,
        .top = 0,
        .l_G = g,
        .ci = null,
        .stack = stack,
        .stack_last = stack.len - 1,
        .openupval = null,
        .tbclist = .empty,
        .gclist = null,
        .twups = null,
        .errorJmp = null,
        .base_ci = .{ .func = 0, .base = 0, .top = llimits.LUA_MINSTACK, .nresults = 0, .savedpc = 0, .previous = null, .next = null, .k = null, .ctx = 0, .nyield = 0 },
        .hook = null,
        .errfunc = 0,
        .nCcalls = 0,
        .noyield = 1, // main thread is always non-yieldable
        .oldpc = 0,
        .nci = 0,
        .basehookcount = 0,
        .hookcount = 0,
        .hookmask = 0,
        .transferinfo = .{ .ftransfer = 0, .ntransfer = 0 },
        .allocator = gpa,
    };
    L.ci = &L.base_ci;

    // Initialize registry and globals tables
    const registry_tab = try ltable.createTable(gpa, 3, 0);
    try lua.registerGC(L, registry_tab);
    g.registry = lua.TValue{ .table = registry_tab };
    g.mainthread = L;
    try ltable.setInt(registry_tab, llimits.LUA_RIDX_MAINTHREAD, lua.TValue{ .thread = L });
    const globals_tab = try ltable.createTable(gpa, 0, 0);
    try lua.registerGC(L, globals_tab);
    try ltable.setInt(registry_tab, 2, lua.TValue{ .table = globals_tab });
    try ltm.luaT_init(L);
    // Install the default warning handler (port of the reference
    // luaL_newstate: `lua_setwarnf(L, warnfon, L)`), so warnings start ON
    // and are turned off by the stand-alone driver's `@off` control message.
    lua_setwarnf(L, lauxlib.warnfon, L);
}

pub fn luaL_newstate(L: *lua.lua_State, gpa: std.mem.Allocator) !void {
    if (@import("builtin").is_test) {
        var threaded: std.Io.Threaded = .init_single_threaded;
        threaded.allocator = gpa;
        try luaL_newstate_io(L, gpa, threaded.io());
        L.l_G.?.io_backend = threaded;
        L.l_G.?.io = L.l_G.?.io_backend.?.io();
    } else {
        var threaded = std.Io.Threaded.init(gpa, .{});
        errdefer threaded.deinit();
        try luaL_newstate_io(L, gpa, threaded.io());
        L.l_G.?.io_backend = threaded;
        L.l_G.?.io = L.l_G.?.io_backend.?.io();
    }
}

pub fn createargtable(L: *lua.lua_State, argv: []const []const u8, script: i32) !void {
    // Build the `arg` table matching reference createargtable in lua.c:
    // arg[0] = script name (argv[script]).
    // arg[1..] = arguments after script (positive indices).
    // arg[-1..] = options/arguments before script (negative indices).
    // When there is no script name, script is 0 (referring to interpreter argv[0]).
    const argc = argv.len;
    const narg: usize = if (script >= 0 and @as(usize, @intCast(script)) + 1 <= argc)
        argc - (@as(usize, @intCast(script)) + 1)
    else
        0;
    const nhash: usize = if (script >= 0) @as(usize, @intCast(script)) + 1 else 0;
    lua.lua_createtable(L, @as(i32, @intCast(narg)), @as(i32, @intCast(nhash)));
    for (argv, 0..) |arg, i| {
        _ = lua.lua_pushstring(L, arg);
        const idx: i64 = @as(i64, @intCast(i)) - @as(i64, script);
        try lua.lua_rawseti(L, -2, idx);
    }
    try lua.lua_setglobal(L, "arg");
}

pub fn lua_close(L: *lua.lua_State) void {
    if (L.l_G) |g| {
        L.openupval = null;

        // Free lua.CallInfo structs still on the active call chain.
        var curr_ci = L.ci;
        while (curr_ci) |ci| {
            const prev = ci.previous;
            if (ci != &L.base_ci) {
                L.allocator.destroy(ci);
            }
            curr_ci = prev;
        }
        L.ci = null;

        // Free recycled lua.CallInfo structs held in the freelist.
        var free_ci = L.ci_free;
        while (free_ci) |ci| {
            const nextf = ci.freenext;
            L.allocator.destroy(ci);
            free_ci = nextf;
        }
        L.ci_free = null;

        // Free all GC objects registered in allgc
        var curr_gc = g.allgc;
        while (curr_gc) |gc| {
            const next_gc = gc.next;
            lua.freeGCObject(L, gc);
            curr_gc = next_gc;
        }
        g.allgc = null;

        // BUG-090: Also free objects on the finobj list (objects whose __gc
        // finalizer ran but were deferred to the next sweep).
        var curr_fin = g.finobj;
        while (curr_fin) |gc| {
            const next_fin = gc.next;
            lua.freeGCObject(L, gc);
            curr_fin = next_fin;
        }
        g.finobj = null;

        // Free string table entries
        var it = g.strt.iterator();
        while (it.next()) |entry| {
            const key = entry.key_ptr.*;
            g.allocator.destroy(entry.value_ptr.*);
            g.allocator.free(key);
        }
        g.strt.deinit(g.allocator);
        if (g.io_backend) |*threaded| {
            threaded.deinit();
        }
        // Free all created threads
        var curr_thread = g.thread_list;
        while (curr_thread) |t| {
            const next_thread = t.twups;
            lua.freeAllCallInfos(t);
            t.tbclist.deinit(t.allocator);
            t.allocator.free(t.stack);
            t.allocator.destroy(t);
            curr_thread = next_thread;
        }

        // Free all opened dynamic libraries in g.clibs
        for (g.clibs.items) |lib| {
            lib.close();
            g.allocator.destroy(lib);
        }
        g.clibs.deinit(g.allocator);
        g.thread_list = null;
        g.cfunc_cache.deinit(g.allocator);

        L.allocator.destroy(g);
    }
    L.tbclist.deinit(L.allocator);
    L.allocator.free(L.stack);
}
