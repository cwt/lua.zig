// $Id: ldo.zig $
//! Call/continuation mechanics (port of ldo.c + upvalue-close glue) -
//! moved from lua.zig (Refactor B4, pure move; re-exported by lua.zig).

const std = @import("std");
const lua = @import("lua.zig");
const lvm = @import("lvm.zig");
const ltm = @import("ltm.zig");
const llimits = @import("llimits.zig");
const lstring = @import("lstring.zig");

pub fn close_one_slot(L: *lua.lua_State, abs: usize, err_val: ?lua.TValue) anyerror!?lua.TValue {
    if (abs >= L.stack.len) return null;
    const v = L.stack[abs];
    if (v == .nil) return null;
    if (v == .boolean and v.boolean == false) return null;
    const mt = switch (v) {
        .table => |t| if (t) |x| x.metatable else null,
        .userdata => |u| if (u) |x| x.metatable else null,
        else => null,
    };
    const tm = if (mt) |m| ltm.luaT_gettm(m, .CLOSE, lua.G(L).tmname[@intFromEnum(ltm.TMS.CLOSE)].?) else null;
    if (tm == null) {
        const msg = "attempt to call a nil value (metamethod 'close')";
        const ts = lstring.luaS_new(L, msg) catch {
            return lua.TValue{ .nil = {} };
        };
        return lua.TValue{ .string = ts };
    }
    const old_top = L.top;
    if (err_val) |err| {
        ltm.luaT_callTM2(L, tm.?, &v, &err) catch |e| {
            return lua.closeCallFailed(L, e, tm.?, old_top);
        };
    } else {
        ltm.luaT_callTM1(L, tm.?, &v) catch |e| {
            return lua.closeCallFailed(L, e, tm.?, old_top);
        };
    }
    return null;
}

pub fn luaF_closeupval(L: *lua.lua_State, limit: usize) void {
    const lim = if (limit < L.stack.len) limit else L.stack.len;
    const limit_addr = @intFromPtr(&L.stack[lim]);
    while (L.openupval) |uv| {
        const addr = @intFromPtr(uv.v);
        if (addr >= limit_addr) {
            const base = @intFromPtr(L.stack.ptr);
            const end = base + L.stack.len * @sizeOf(lua.TValue);
            if (addr >= base and addr < end) {
                uv.value = uv.v.*;
            } else {
                uv.value = .{ .nil = {} };
            }
            uv.v = &uv.value;
            L.openupval = uv.next;
        } else {
            break;
        }
    }
}

pub fn closeupvals(L: *lua.lua_State, limit: usize, err_val: ?lua.TValue) !void {
    luaF_closeupval(L, limit);

    var has_err = (err_val != null);
    var close_raised = false;
    var needs_err_push = (err_val != null);
    var err_idx: usize = 0;
    if (needs_err_push and L.top > 0) {
        err_idx = L.top - 1;
    }

    while (L.tbclist.items.len > 0) {
        const last_idx = L.tbclist.items.len - 1;
        const abs = L.tbclist.items[last_idx];
        if (abs >= limit) {
            _ = L.tbclist.pop();
            const current_err = if (has_err and err_idx < L.stack.len) L.stack[err_idx] else null;
            // Extend L.top past this and all remaining TBC entries so GC
            // (triggered by a __close handler calling collectgarbage()) can
            // trace them. poscall sets L.top below the function's locals,
            // leaving TBC variables invisible to the GC collector.
            const gc_safe_top = @max(L.top, abs + 1);
            if (gc_safe_top >= L.stack.len) {
                try lua.growStack(L, gc_safe_top + 10);
            }
            const old_top = L.top;
            L.top = gc_safe_top;
            const close_res = close_one_slot(L, abs, current_err) catch |e| {
                if (e == error.ThreadClosed) {
                    // A `__close` handler closed the thread itself (a
                    // `coroutine.close` self-close; the reference models this
                    // as a non-local `luaD_throwbaselevel`). This is a clean
                    // self-close, not a close error: stop closing the
                    // remaining TBC slots on this thread and finish normally
                    // (BUG-168).
                    L.top = old_top;
                    L.tbclist.clearRetainingCapacity();
                    return;
                }
                // error.Yield and any other close error propagate to the
                // caller of `closeupvals`.
                return e;
            };
            L.top = old_top;
            if (close_res) |ne| {
                if (needs_err_push) {
                    if (err_idx < L.stack.len) {
                        L.stack[err_idx] = ne;
                    }
                } else {
                    if (L.top >= L.stack.len) {
                        try lua.growStack(L, L.top + 5);
                    }
                    L.stack[L.top] = ne;
                    err_idx = L.top;
                    L.top += 1;
                    needs_err_push = true;
                }
                has_err = true;
                close_raised = true;
            }
        } else {
            break;
        }
    }
    if (close_raised) {
        if (err_idx >= L.stack.len) {
            try lua.growStack(L, err_idx + 2);
        }
        const final_err = L.stack[err_idx];
        L.top = err_idx + 1;
        L.stack[err_idx] = final_err;
        // A __close metamethod raised (or the value was not closable): record
        // the error object so the surrounding protected call reports it (this
        // path does not go through luaG_errormsg, which is what normally sets
        // L.err_obj).
        L.err_obj = final_err;
        return error.RuntimeError;
    }
}
pub fn luaD_hook(L: *lua.lua_State, event: i32, line: i32, ftransfer: i32, ntransfer: i32) void {
    const hook = L.hook;
    if (hook != null and L.allowhook != 0) {
        const old_oldpc = L.oldpc;
        defer L.oldpc = old_oldpc;
        const old_top = L.top;
        const ci = L.ci.?;
        const old_is_hooked = ci.is_hooked;
        ci.is_hooked = true;
        defer ci.is_hooked = old_is_hooked;
        const old_ci_top = ci.top;
        var ar = lua.lua_Debug{
            .event = event,
            .name = null,
            .namewhat = null,
            .what = null,
            .source = null,
            .srclen = 0,
            .currentline = line,
            .linedefined = 0,
            .lastlinedefined = 0,
            .nups = 0,
            .nparams = 0,
            .isvararg = false,
            .extraargs = 0,
            .istailcall = false,
            .ftransfer = ftransfer,
            .ntransfer = ntransfer,
            .short_src = std.mem.zeroes([lua.LUA_IDSIZE]u8),
            .i_ci = ci,
        };
        L.transferinfo = .{
            .ftransfer = ftransfer,
            .ntransfer = ntransfer,
        };
        const val = L.stack[ci.func];
        if (val == .function and val.function.?.* == .lua) {
            if (L.top < ci.top) {
                L.top = ci.top;
            }
        }
        if (lua.lua_checkstack(L, 20) != 0) {
            if (ci.top < L.top + 20) {
                ci.top = L.top + 20;
            }
        }
        L.allowhook = 0;
        hook.?(L, &ar);
        L.allowhook = 1;
        ci.top = old_ci_top;
        L.top = old_top;
    }
}

pub fn luaG_traceexec(L: *lua.lua_State) void {
    if (L.hookmask == 0) return;
    const ci = L.ci orelse return;
    if (!lua.isLua(ci, L)) return;
    const val = L.stack[ci.func];
    if (val != .function or val.function == null or val.function.?.* != .lua) return;
    const p = val.function.?.lua.p;
    const mask = L.hookmask;
    const pc: i32 = lua.currentpc(ci);
    if (pc >= 0 and @as(usize, @intCast(pc)) < p.code.len) {
        const op = @as(lvm.OpCode, @enumFromInt(p.code[@intCast(pc)] & 0x7F));
        if (op == .VARARGPREP) {
            L.oldpc = -1;
            return;
        }
    }

    var counthook = false;
    if ((mask & llimits.LUA_MASKCOUNT) != 0) {
        if (L.hookcount > 0) {
            L.hookcount -= 1;
        }
        if (L.hookcount == 0) {
            counthook = true;
            L.hookcount = L.basehookcount;
        }
    }

    if (counthook) {
        luaD_hook(L, lua.LUA_HOOKCOUNT, -1, 0, 0);
    }

    if ((mask & llimits.LUA_MASKLINE) != 0) {
        const oldpc: i32 = @intCast(L.oldpc);
        if (oldpc == -1 or pc < oldpc or changedline(p, oldpc, pc)) {
            // Mirror the reference: always call the line hook on a line
            // change. For stripped code (no debug info) luaG_getfuncline
            // returns -1, which the debug-lib hook converts to nil.
            const newline = lua.luaG_getfuncline(p, pc);
            luaD_hook(L, lua.LUA_HOOKLINE, newline, 0, 0);
        }
        L.oldpc = @intCast(pc);
    }
}

fn changedline(p: *const lua.lua_Proto, oldpc: i32, newpc: i32) bool {
    const line1 = lua.luaG_getfuncline(p, oldpc);
    const line2 = lua.luaG_getfuncline(p, newpc);
    return line1 != line2;
}

pub fn poscall(L: *lua.lua_State, ci: *lua.CallInfo, first_result_idx: usize, n: usize) !void {
    L.top = first_result_idx + n;
    try closeupvals(L, ci.base, null);

    if (L.hookmask & llimits.LUA_MASKRET != 0) {
        // Mirror the reference rethook: by the time poscall runs, ci.func has
        // already been restored (OP_RETURN* / tail call undo the PF_VAHID
        // relocation), so ftransfer is just firstres - ci.func.
        const firstres = first_result_idx;
        const ftransfer = @as(i32, @intCast(firstres)) - @as(i32, @intCast(ci.func));
        luaD_hook(L, lua.LUA_HOOKRET, -1, ftransfer, @as(i32, @intCast(n)));
    }
    const func_idx = ci.func;
    const nresults = ci.nresults;
    const old_top = L.top;
    var new_top: usize = undefined;
    if (nresults >= 0) {
        const copy_count = @min(@as(usize, @intCast(nresults)), n);
        var i: usize = 0;
        while (i < copy_count) : (i += 1) {
            L.stack[func_idx + i] = L.stack[first_result_idx + i];
        }
        while (i < @as(usize, @intCast(nresults))) : (i += 1) {
            L.stack[func_idx + i] = .{ .nil = {} };
        }
        new_top = func_idx + @as(usize, @intCast(nresults));
    } else {
        var i: usize = 0;
        while (i < n) : (i += 1) {
            L.stack[func_idx + i] = L.stack[first_result_idx + i];
        }
        new_top = func_idx + n;
    }
    if (new_top < old_top) {
        @memset(L.stack[new_top..@min(old_top, L.stack.len)], .{ .nil = {} });
    }
    L.top = new_top;
    if (ci.previous) |prev| {
        if (lua.isLua(prev, L)) {
            L.oldpc = lua.currentpc(prev);
        }
    }
}

/// Recycle a lua.CallInfo from the freelist, or allocate a fresh one. Mirrors
/// C Lua's pre-grown call stack: a lua.CallInfo is only allocated when the pool is
/// empty, never on every call.
pub fn allocCallInfo(L: *lua.lua_State) !*lua.CallInfo {
    if (L.ci_free) |free| {
        L.ci_free = free.freenext;
        return free;
    }
    return try L.allocator.create(lua.CallInfo);
}

/// Return a lua.CallInfo to the freelist for reuse (instead of freeing it).
pub fn freeCallInfo(L: *lua.lua_State, ci: *lua.CallInfo) void {
    ci.freenext = L.ci_free;
    L.ci_free = ci;
}

/// Free every lua.CallInfo owned by `L`: the active call chain above `base_ci`
/// and all recycled CallInfos in the freelist. Used when a coroutine finishes
/// or is explicitly closed, mirroring C Lua discarding a dead thread's stack.
pub fn freeAllCallInfos(L: *lua.lua_State) void {
    var curr = L.ci;
    while (curr) |ci| {
        const prev = ci.previous;
        if (ci != &L.base_ci) L.allocator.destroy(ci);
        curr = prev;
    }
    var f = L.ci_free;
    while (f) |ci| {
        const nextf = ci.freenext;
        L.allocator.destroy(ci);
        f = nextf;
    }
    L.ci_free = null;
    L.ci = &L.base_ci;
    L.base_ci.next = null;
}

/// Recycle the active lua.CallInfo chain into the freelist WITHOUT destroying it
/// (BUG-168). Used for a self-close (`coroutine.close()` from the coroutine
/// itself): the lua.CallInfo structs may still be referenced by live C frames that
/// are mid-unwind, so destroying them would be a use-after-free. Instead we
/// detach the chain and link it onto `L.ci_free` for later reuse; the owning
/// `lua_close`/`lua_closethread` frees them. `L.ci` is reset to the base CI
/// so the thread is logically terminated (and `lua_resume` computes a zero
/// result count).
pub fn recycleCallInfos(L: *lua.lua_State) void {
    var curr = L.ci;
    while (curr) |ci| {
        const prev = ci.previous;
        if (ci != &L.base_ci) {
            ci.previous = null;
            ci.next = null;
            ci.freenext = L.ci_free;
            L.ci_free = ci;
        }
        curr = prev;
    }
    L.ci = &L.base_ci;
    L.base_ci.next = null;
}

/// A2 (docs/refactor.md): destroy the CallInfos on the active chain strictly
/// above `up_to` (walking from `L.ci` down; the embedded `base_ci` is never
/// destroyed), set `L.ci = up_to` and clear `up_to.next`. Replaces the six
/// copy-pasted walk loops (precall / lua_pcallk / precover in this file and
/// luaD_call / luaT_callTM1 / luaT_callTM2 in ltm.zig). A site that must
/// ALSO sever the parent link (precover) does that after calling this.
pub fn unwindCis(L: *lua.lua_State, up_to: ?*lua.CallInfo) void {
    var curr = L.ci;
    while (curr) |c| {
        if (c == up_to) break;
        const prev = c.previous;
        if (c != &L.base_ci) {
            L.allocator.destroy(c);
        }
        curr = prev;
    }
    L.ci = up_to;
    if (up_to) |u| {
        u.next = null;
    }
}

// Proto flag bits (mirror lua/ldo.h PF_*). A Lua function is vararg when its
// 'flag' carries PF_VAHID (hidden vararg args) or PF_VATAB (vararg table);
// such functions begin with OP_VARARGPREP, which relocates the frame and must
// read the real argument count from 'L->top'.
const PF_VAHID: u8 = 1; // function has hidden vararg arguments
const PF_VATAB: u8 = 2; // function has a vararg table

pub fn precall(L: *lua.lua_State, func_idx: usize, nresults: i32) !?*lua.CallInfo {
    var ccmt: usize = 0;
    while (L.stack[func_idx] != .function) {
        const val = L.stack[func_idx];
        const tm = ltm.luaT_gettmbyobj(L, val, .CALL);
        if (tm == .nil) {
            try lua.luaG_callerror(L, val);
        }
        ccmt += 1;
        if (ccmt > 15) {
            try lua.luaG_runerror(L, "'__call' chain too long");
        }
        if (lua.lua_checkstack(L, 1) == 0) return error.StackOverflow;
        var p = L.top;
        while (p > func_idx) : (p -= 1) {
            L.stack[p] = L.stack[p - 1];
        }
        L.top += 1;
        L.stack[func_idx] = tm;
    }
    const val = L.stack[func_idx];
    const cl = val.function.?;
    const needed = switch (cl.*) {
        .c => L.top + 20,
        .lua => |lc| func_idx + 1 + @as(usize, lc.p.maxStackSize) + 20,
    };
    if (needed > L.stack.len) {
        if (L.stack.len > llimits.LUAI_MAXSTACK) {
            // The stack is already at ERRORSTACKSIZE: we are handling a stack
            // error (inside its error handler). A further growth request here
            // must report "error in error handling" (mirrors luaD_growstack's
            // `size > MAXSTACK` branch -> luaD_errerr).
            try lua.luaG_runerror(L, "error in error handling");
        }
        if (needed > llimits.ERRORSTACKSIZE) {
            return error.StackOverflow;
        }
        if (needed > llimits.LUAI_MAXSTACK) {
            lua.reserveErrorStack(L) catch return error.StackOverflow;
            try lua.luaG_runerror(L, "stack overflow");
        }
        const extra = if (needed > L.top) needed - L.top else 20;
        if (lua.lua_checkstack(L, @intCast(extra)) == 0) {
            return error.StackOverflow;
        }
    }
    if (func_idx >= 2) {
        // nothing
    }
    switch (cl.*) {
        .c => |cc| {
            L.nCcalls += 1;
            defer L.nCcalls -= 1;
            if (lua.lua_checkstack(L, 20) == 0) return error.StackOverflow;
            const old_ci = L.ci;
            const new_ci = try allocCallInfo(L);
            new_ci.* = .{
                .func = func_idx,
                .base = func_idx + 1,
                .top = L.top + 20,
                .nresults = nresults,
                .savedpc = 0,
                .previous = old_ci,
                .next = null,
                .nextraargs = @intCast(ccmt),
            };
            if (old_ci) |prev| {
                prev.next = new_ci;
            }
            L.ci = new_ci;
            // Check the C-call limit only after L.ci points at the new C frame
            // (mirrors precallC): luaG_runerror then reports no source:line,
            // so the message is exactly "C stack overflow".
            if (L.nCcalls == llimits.LUAI_MAXCCALLS) {
                try lua.luaG_runerror(L, "C stack overflow");
            } else if (L.nCcalls >= llimits.LUAI_MAXCCALLS * 11 / 10) {
                // We are already handling a stack overflow (the error handler
                // itself keeps raising). Raise DIRECTLY without re-invoking the
                // handler, mirroring luaD_errerr -> LUA_ERRERR; this is what
                // terminates the error-handler recursion.
                return lua.luaD_errerr(L);
            }
            if (L.hookmask & llimits.LUA_MASKCALL != 0) {
                const narg = L.top - func_idx - 1;
                luaD_hook(L, lua.LUA_HOOKCALL, -1, 1, @intCast(narg));
            }
            const n = cc.f(L) catch |e| {
                if (e == error.ThreadClosed) {
                    return error.ThreadClosed;
                }
                if (e == error.Yield) {
                    return error.Yield;
                }
                unwindCis(L, old_ci);
                return e;
            };
            if (n < 0) {
                L.ci = old_ci;
                if (old_ci) |prev| {
                    prev.next = null;
                }
                freeCallInfo(L, new_ci);
                return error.RuntimeError;
            }
            const num_returned = @as(usize, @intCast(n));
            const first_result = L.top - num_returned;
            try poscall(L, new_ci, first_result, num_returned);
            L.ci = old_ci;
            if (old_ci) |prev| {
                prev.next = null;
            }
            freeCallInfo(L, new_ci);
            return null;
        },
        .lua => |lc| {
            const proto = lc.p;
            const num_params = proto.numParams;
            const base_idx = func_idx + 1;
            const frame_top = base_idx + proto.maxStackSize;
            const is_vararg = (proto.flag & (PF_VAHID | PF_VATAB)) != 0;
            try lua.growStack(L, frame_top + 1);
            const num_args_passed = L.top - base_idx;
            if (num_args_passed < num_params) {
                var i = num_args_passed;
                while (i < num_params) : (i += 1) {
                    L.stack[base_idx + i] = .{ .nil = {} };
                }
                L.top = base_idx + num_params;
            }
            const clear_start = base_idx + @max(num_args_passed, num_params);
            if (clear_start < frame_top and clear_start < L.stack.len) {
                @memset(L.stack[clear_start..@min(frame_top, L.stack.len)], .{ .nil = {} });
            }
            const new_ci = try allocCallInfo(L);
            new_ci.* = .{
                .func = func_idx,
                .base = base_idx,
                .top = frame_top,
                .nresults = nresults,
                .savedpc = 0,
                .previous = L.ci,
                .next = null,
                .nextraargs = @intCast(ccmt),
                .is_lua = true,
                .is_hooked = (L.allowhook == 0),
            };
            if (L.ci) |prev| {
                prev.next = new_ci;
            }
            L.oldpc = -1;
            // For non-vararg Lua functions, lift 'L->top' to the frame top so
            // that auxiliary calls (e.g. metamethod invocations via
            // luaT_callTMres) are placed above all live registers, matching the
            // reference behaviour (L->top = ci->top). Vararg functions are left
            // at the caller's top: their first instruction (OP_VARARGPREP)
            // calls luaT_adjustvarargs, which relies on 'L->top' still being the
            // caller's top (the real argument count) to compute the number of
            // varargs; buildhiddenargs then re-establishes 'L->top = ci->top'.
            if (!is_vararg) {
                L.top = frame_top;
            }
            L.ci = new_ci;
            if (L.hookmask & llimits.LUA_MASKCALL != 0) {
                luaD_hook(L, lua.LUA_HOOKCALL, -1, 1, proto.numParams);
            }
            return new_ci;
        },
    }
}

pub fn lua_yieldk(L: *lua.lua_State, nresults: i32, ctx: lua.lua_KContext, k: ?lua.lua_KFunction) anyerror!i32 {
    const ci = L.ci orelse return error.RuntimeError;
    if (lua_isyieldable(L) == 0) {
        // Mirror the reference: report a different message depending on
        // whether this is the main thread or a coroutine stuck in a
        // non-yieldable context.
        if (lua.G(L).mainthread != L) {
            try lua.luaG_runerror(L, "attempt to yield across a C-call boundary");
        } else {
            try lua.luaG_runerror(L, "attempt to yield from outside a coroutine");
        }
    }
    L.status = lua.LUA_YIELD;
    ci.nyield = nresults;
    ci.k = k;
    ci.ctx = ctx;
    return error.Yield;
}

pub fn lua_yield(L: *lua.lua_State, nresults: i32) anyerror!i32 {
    return lua_yieldk(L, nresults, 0, null);
}

/// Port of the C reference `resume_error` (lua/ldo.c): remove the resume
/// arguments from the target thread's stack and push the error message
/// there, so callers (`auxresume`/`auxwrap`) can move it to their own stack.
fn resume_error(L: *lua.lua_State, msg: []const u8, narg: i32) i32 {
    L.top -= @as(usize, @intCast(narg));
    if (lstring.luaS_new(L, msg)) |ts| {
        L.stack[L.top] = lua.TValue{ .string = ts };
    } else |_| {
        L.stack[L.top] = lua.TValue{ .nil = {} };
    }
    L.top += 1;
    return lua.LUA_ERRRUN;
}

/// Complete an interrupted protected-call error recovery: close any remaining
/// to-be-closed variables with the saved error and finish the pcall via its
/// continuation. The caller (unroll) sets L.ci to the pcall's caller.
fn completePcallRecovery(L: *lua.lua_State, ci: *lua.CallInfo) !void {
    var err_obj = ci.recover_err;
    const pcall_func = ci.pcall_func;
    // The error must be at L.top-1 for closeupvals to pass it to each
    // remaining __close (it reads current_err from there).
    if (L.top < L.stack.len) {
        L.stack[L.top] = err_obj;
        L.top += 1;
    }
    // Close any remaining to-be-closed variables (a resumed __close may
    // itself raise, replacing the error, or yield, interrupting the recovery).
    closeupvals(L, pcall_func, err_obj) catch |ce| {
        if (ce == error.Yield) {
            ci.recovering = true;
            ci.recover_err = err_obj;
            return error.Yield;
        }
        if (L.err_obj != .nil) {
            err_obj = L.err_obj;
        } else if (L.top > 0) {
            err_obj = L.stack[L.top - 1];
        }
    };
    ci.ypcall = false;
    ci.recovering = false;
    if (pcall_func < L.stack.len) {
        L.stack[pcall_func] = err_obj;
    }
    L.top = pcall_func + 1;
    if (ci.k) |kf| {
        const nres = try kf(L, lua.LUA_ERRRUN, ci.ctx);
        const u_nres = @as(usize, @intCast(nres));
        try poscall(L, ci, L.top - u_nres, u_nres);
    }
    const prev = ci.previous;
    L.ci = prev;
    if (prev) |p| {
        p.next = null;
    }
    freeCallInfo(L, ci);
}

/// Route an error raised by a resumed coroutine frame back to the nearest
/// protected call (the CIST_YPCALL equivalent): unwind the frames above it,
/// close its remaining to-be-closed variables with the error (a __close may
/// raise or yield), and complete the pcall via its continuation.
/// Returns true if the error was handled (the coroutine may continue), false
/// if there is no recoverable protected call, or error.Yield if a __close
/// yielded during the recovery (the recovery resumes later).
fn precover(L: *lua.lua_State) !bool {
    var opt: ?*lua.CallInfo = L.ci;
    var target: ?*lua.CallInfo = null;
    while (opt) |c| : (opt = c.previous) {
        if (c.ypcall) {
            target = c;
            break;
        }
    }
    const target_ci = target orelse return false;

    // Unwind the frames above the protected call.
    unwindCis(L, target_ci);
    if (target_ci.previous) |prev| {
        prev.next = null;
    }

    // The error object from the erroring frame is on the stack top. Move it
    // past any remaining TBC variables, then close them.
    const pcall_func = target_ci.pcall_func;
    var err_obj = if (L.top > 0) L.stack[L.top - 1] else lua.TValue{ .nil = {} };
    closeupvals(L, pcall_func, err_obj) catch |ce| {
        if (ce == error.Yield) {
            // A __close metamethod yielded while closing with the error: save
            // the pending error and let the coroutine yield; on resume the
            // recovery completes (completePcallRecovery).
            target_ci.recovering = true;
            target_ci.recover_err = err_obj;
            return error.Yield;
        }
        if (L.err_obj != .nil) {
            err_obj = L.err_obj;
        } else if (L.top > 0) {
            err_obj = L.stack[L.top - 1];
        }
    };
    target_ci.recover_err = err_obj;
    try completePcallRecovery(L, target_ci);
    return true;
}

fn unroll(L: *lua.lua_State) !void {
    while (L.ci) |ci| {
        if (ci == &L.base_ci) break;
        const val = L.stack[ci.func];
        if (val == .function and val.function.?.* == .lua) {
            // The frame was interrupted by a yield: complete the interrupted
            // instruction before resuming (mirrors luaV_finishOp in unroll).
            lvm.finishOp(L, ci) catch |e| {
                if (e == error.Yield or e == error.ThreadClosed) return e;
                const handled = precover(L) catch |pe| {
                    if (pe == error.Yield) return pe;
                    return e;
                };
                if (!handled) return e;
                continue;
            };
            lvm.run(L, ci) catch |e| {
                if (e == error.Yield or e == error.ThreadClosed) return e;
                const handled = precover(L) catch |pe| {
                    if (pe == error.Yield) return pe;
                    return e;
                };
                if (!handled) return e;
                // Handled: the protected call completed; continue the loop
                // with the (unwound) call chain.
            };
        } else if (val == .function and val.function.?.* == .c) {
            if (ci.k) |kf| {
                if (ci.recovering) {
                    // Finish an error recovery that was interrupted by a
                    // yielding __close metamethod.
                    try completePcallRecovery(L, ci);
                } else {
                    const prev = ci.previous;
                    const nres = try kf(L, lua.LUA_YIELD, ci.ctx);
                    const u_nres = @as(usize, @intCast(nres));
                    try poscall(L, ci, L.top - u_nres, u_nres);
                    L.ci = prev;
                    freeCallInfo(L, ci);
                }
            } else {
                const prev = ci.previous;
                try poscall(L, ci, L.top, 0);
                L.ci = prev;
                freeCallInfo(L, ci);
            }
        } else {
            return error.RuntimeError;
        }
    }
}

fn do_resume(L: *lua.lua_State, narg: i32) !void {
    const n = @as(usize, @intCast(narg));
    const firstArg = L.top - n;

    if (L.status == lua.LUA_OK) {
        if (try precall(L, firstArg - 1, lua.LUA_MULTRET)) |ci| {
            try lvm.run(L, ci);
        }
    } else {
        L.status = lua.LUA_OK;
        if (L.ci) |ci| {
            if (ci.k) |kf| {
                const prev = ci.previous;
                const nres = try kf(L, lua.LUA_YIELD, ci.ctx);
                const u_nres = @as(usize, @intCast(nres));
                try poscall(L, ci, L.top - u_nres, u_nres);
                L.ci = prev;
                freeCallInfo(L, ci);
            } else {
                const val = L.stack[ci.func];
                if (val == .function and val.function.?.* == .lua) {
                    L.ci = ci;
                    lvm.finishOp(L, ci) catch |e| {
                        if (e == error.Yield or e == error.ThreadClosed) return e;
                        const handled = precover(L) catch |pe| {
                            if (pe == error.Yield) return pe;
                            return e;
                        };
                        if (!handled) return e;
                    };
                    lvm.run(L, ci) catch |e| {
                        if (e == error.Yield or e == error.ThreadClosed) return e;
                        const handled = precover(L) catch |pe| {
                            if (pe == error.Yield) return pe;
                            return e;
                        };
                        if (!handled) return e;
                    };
                } else {
                    const prev = ci.previous;
                    try poscall(L, ci, firstArg, n);
                    L.ci = prev;
                    freeCallInfo(L, ci);
                }
            }
        } else {
            return error.RuntimeError;
        }
        try unroll(L);
    }
}

pub fn lua_resume(L: *lua.lua_State, from: ?*lua.lua_State, narg: i32, nresults: ?*i32) i32 {
    if (L.status == lua.LUA_OK) {
        if (L.ci != &L.base_ci) return resume_error(L, "cannot resume non-suspended coroutine", narg);
    } else if (L.status != lua.LUA_YIELD) {
        return resume_error(L, "cannot resume dead coroutine", narg);
    }
    // Port of the reference dead-coordinator check (lua/ldo.c): after the
    // caller has moved narg arguments onto this thread, a dead thread holds
    // exactly those arguments on its stack, while a fresh thread additionally
    // keeps its function in the slot above base_ci.func.
    if (L.top - @as(usize, @intCast(narg)) == 1) return resume_error(L, "cannot resume dead coroutine", narg);

    L.nCcalls = if (from) |f| f.nCcalls else 0;
    L.nCcalls += 1;

    do_resume(L, narg) catch |e| {
        if (e == error.Yield or e == error.ThreadClosed) {} else {
            const status = switch (e) {
                error.OutOfMemory => b: {
                    if (lstring.luaS_new(L, "not enough memory")) |ts| {
                        L.stack[L.top] = lua.TValue{ .string = ts };
                        L.top += 1;
                    } else |_| {
                        L.stack[L.top] = lua.TValue{ .nil = {} };
                        L.top += 1;
                    }
                    break :b lua.LUA_ERRMEM;
                },
                error.StackOverflow, error.StackError => b: {
                    if (lstring.luaS_new(L, "stack overflow")) |ts| {
                        L.stack[L.top] = lua.TValue{ .string = ts };
                        L.top += 1;
                    } else |_| {
                        L.stack[L.top] = lua.TValue{ .nil = {} };
                        L.top += 1;
                    }
                    break :b lua.LUA_ERRRUN;
                },
                else => lua.LUA_ERRRUN,
            };
            L.status = @intCast(status);
        }
    };

    if (nresults) |nr| {
        if (L.status == lua.LUA_YIELD) {
            nr.* = if (L.ci) |ci| ci.nyield else 0;
        } else if (L.status == lua.LUA_OK) {
            if (L.ci) |ci| {
                nr.* = @as(i32, @intCast(L.top)) - @as(i32, @intCast(ci.func + 1));
            } else {
                nr.* = 0;
            }
        } else {
            nr.* = 0;
        }
    }

    if (L.status == lua.LUA_YIELD) return lua.LUA_YIELD;
    if (L.status == lua.LUA_OK) {
        // Coroutine completed normally: its call frames were already popped
        // back to base_ci, so only recycled CallInfos remain. Discard them
        // (they would otherwise linger in the freelist until the thread is
        // explicitly closed, which the caller may never do).
        freeAllCallInfos(L);
    }
    // Otherwise the coroutine died with an error: keep its lua.CallInfo chain so
    // that debug.traceback(co) can still report the frames where it failed
    // (mirrors the reference, which frees them at lua_closethread / lua_close).
    return L.status;
}

pub fn lua_status(L: *lua.lua_State) i32 {
    return L.status;
}

pub fn lua_isyieldable(L: *lua.lua_State) i32 {
    return if (L.noyield == 0) 1 else 0;
}

pub fn luaG_errormsg(L: *lua.lua_State) anyerror {
    if (L.top > 0) {
        L.err_obj = L.stack[L.top - 1];
    }
    if (L.errfunc != 0) {
        if (lua.lua_checkstack(L, 2) == 0 or L.top + 2 >= L.stack.len) {
            if (lstring.luaS_new(L, "error in error handling")) |ts| {
                L.stack[L.top - 1] = lua.TValue{ .string = ts };
                L.err_obj = L.stack[L.top - 1];
            } else |_| {}
            return error.StackError;
        }
        const errfunc = @as(usize, @intCast(L.errfunc - 1));
        const err_obj = L.stack[L.top - 1];

        L.stack[L.top] = err_obj;
        L.stack[L.top - 1] = L.stack[errfunc];
        L.top += 1;

        // Invoke the error handler. We deliberately do NOT clear L.errfunc
        // (mirroring the reference): if the handler raises, luaG_errormsg is
        // re-entered and invokes the handler again, so a bounded handler
        // recursion (e.g. xpcall(error, err, n) where err eventually returns
        // "END") resolves normally, while an unbounded one (xpcall(error,
        // error)) terminates via the C-call limit in precall -> luaD_errerr,
        // yielding "error in error handling".
        var handler_returned = true;
        const err_ci = precall(L, L.top - 2, 1) catch |e| b: {
            handler_returned = false;
            if (e == error.StackError or e == error.StackOverflow) {
                // The handler could not run at all (stack exhausted).
                if (lstring.luaS_new(L, "error in error handling")) |ts| {
                    L.err_obj = lua.TValue{ .string = ts };
                } else |_| {}
            }
            // For RuntimeError, L.err_obj already holds the propagated error
            // (e.g. from a nested luaD_errerr), which we keep.
            break :b @as(?*lua.CallInfo, null);
        };
        if (err_ci) |eci| {
            lvm.run(L, eci) catch |e| {
                handler_returned = false;
                if (e == error.StackOverflow or e == error.StackError) {
                    if (lstring.luaS_new(L, "error in error handling")) |ts| {
                        L.err_obj = lua.TValue{ .string = ts };
                    } else |_| {}
                }
            };
        }
        if (handler_returned) {
            // Handler succeeded: its result is at L.top-1.
            if (L.top > 0) {
                L.err_obj = L.stack[L.top - 1];
            }
        } else if (L.top > 0) {
            // Handler raised: place the propagated error object on the stack.
            L.stack[L.top - 1] = L.err_obj;
        }
    }
    // Record the name of the erroring function (and how it was called), so a
    // dead coroutine's debug.traceback can report where it failed even though
    // the C frame is unwound during error propagation.
    if (L.ci) |eci| {
        var fname: ?[]const u8 = null;
        const kind = lua.getfuncname(L, eci, &fname);
        if (kind) |k| {
            L.err_name = fname;
            L.err_namewhat = k;
        }
    }
    return error.RuntimeError;
}

pub fn lua_error(L: *lua.lua_State) anyerror {
    const err_obj = L.stack[L.top - 1];
    if (err_obj == .nil) {
        const ts = try lstring.luaS_new(L, "<no error object>");
        L.stack[L.top - 1] = lua.TValue{ .string = ts };
    }
    return luaG_errormsg(L);
}


/// Raise "error in error handling" WITHOUT invoking the error handler
/// (mirrors luaD_errerr -> LUA_ERRERR). Used to terminate the error-handler
/// recursion when the C-call stack is exhausted: calling luaG_runerror here
/// would re-invoke the handler and recurse forever.
pub fn luaD_errerr(L: *lua.lua_State) anyerror {
    const ts = lstring.luaS_new(L, "error in error handling") catch null;
    if (ts) |t| {
        L.err_obj = lua.TValue{ .string = t };
        if (L.top < L.stack.len) {
            L.stack[L.top] = L.err_obj;
            L.top += 1;
        }
    }
    return error.RuntimeError;
}
