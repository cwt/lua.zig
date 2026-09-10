// $Id: lgc.zig $
//! Garbage-collector engine (port of lgc.c) - moved from lua.zig
//! (Refactor B2, pure move; re-exported by lua.zig for callers).

const std = @import("std");
const lua = @import("lua.zig");

pub fn registerGC(L: *lua.lua_State, val: anytype) !void {
    const g = L.l_G orelse return;
    const gc = try L.allocator.create(lua.VMGCObject);
    const union_val = switch (@TypeOf(val)) {
        *lua.lua_Table => lua.VMGCObject.ValUnion{ .table = val },
        *lua.lua_Closure => lua.VMGCObject.ValUnion{ .closure = val },
        *lua.UpVal => lua.VMGCObject.ValUnion{ .upval = val },
        *lua.lua_Proto => lua.VMGCObject.ValUnion{ .proto = val },
        *lua.lua_Udata => lua.VMGCObject.ValUnion{ .userdata = val },
        *lua.lua_TString => lua.VMGCObject.ValUnion{ .string = val },
        *lua.lua_State => lua.VMGCObject.ValUnion{ .thread = val },
        else => @compileError("Unsupported type for GC registration"),
    };
    gc.* = .{
        .next = g.allgc,
        .val = union_val,
        .color = if (g.gc_in_progress) .black else .white,
    };
    switch (union_val) {
        .table => |t| {
            t.gc = gc;
            t.g = g;
        },
        .closure => |cl| switch (cl.*) {
            .c => |cc| cc.gc = gc,
            .lua => |lc| lc.gc = gc,
        },
        .userdata => |ud| ud.gc = gc,
        .proto => |pr| pr.gc = gc,
        .string => |ts| ts.gc = gc,
        .upval => |uv| uv.gc = gc,
        .thread => |th| th.gc = gc,
    }
    g.allgc = gc;
    g.gc_count += 1;

    const sz: usize = switch (union_val) {
        .table => |t| @sizeOf(lua.lua_Table) + t.array.capacity * @sizeOf(lua.TValue) + t.node.capacity * @sizeOf(lua.Node),
        .string => |ts| @sizeOf(lua.lua_TString) + ts.s.len + 1,
        .closure => |cl| switch (cl.*) {
            .c => |cc| @sizeOf(lua.lua_Closure) + @sizeOf(lua.lua_CClosure) + cc.upvals.len * @sizeOf(lua.TValue),
            .lua => |lc| @sizeOf(lua.lua_Closure) + @sizeOf(lua.lua_LClosure) + lc.upvals.len * @sizeOf(?*lua.UpVal),
        },
        .userdata => |ud| @sizeOf(lua.lua_Udata) + ud.data.len + ud.uv.len * @sizeOf(lua.TValue),
        .proto => @sizeOf(lua.lua_Proto),
        .upval => @sizeOf(lua.UpVal),
        .thread => |th| @sizeOf(lua.lua_State) + th.stack.len * @sizeOf(lua.TValue),
    };
    g.totalbytes += sz + @sizeOf(lua.VMGCObject);
}

fn getGCObject(g: *lua.global_State, ptr: anytype) ?*lua.VMGCObject {
    _ = g;
    if (@typeInfo(@TypeOf(ptr)) != .pointer) return null;
    if (@intFromPtr(ptr) == 0) return null;
    const T = @TypeOf(ptr);
    if (T == *lua.lua_Table) {
        return ptr.gc;
    }
    if (T == *lua.lua_Closure) {
        return switch (ptr.*) {
            .c => |cc| cc.gc,
            .lua => |lc| lc.gc,
        };
    }
    if (T == *lua.lua_Udata) {
        return ptr.gc;
    }
    if (T == *lua.lua_Proto) {
        return ptr.gc;
    }
    if (T == *lua.lua_TString) {
        return ptr.gc;
    }
    if (T == *lua.UpVal) {
        return ptr.gc;
    }
    if (T == *lua.lua_State) {
        return ptr.gc;
    }
    return null;
}

fn markObject(L: *lua.lua_State, gc: *lua.VMGCObject, gray_list: *std.ArrayList(*lua.VMGCObject)) !void {
    if (gc.color == .white) {
        gc.color = .gray;
        try gray_list.append(L.allocator, gc);
    }
}

fn markString(L: *lua.lua_State, gray_list: *std.ArrayList(*lua.VMGCObject), str: *lua.lua_TString) !void {
    const g = lua.G(L);
    str.marked = true;
    if (getGCObject(g, str)) |gc| try markObject(L, gc, gray_list);
}

fn markValue(L: *lua.lua_State, gray_list: *std.ArrayList(*lua.VMGCObject), val: lua.TValue) !void {
    const g = lua.G(L);
    switch (val) {
        .string => |s| if (s) |str| {
            str.marked = true;
            // Strings on allgc (long / external) need their lua.VMGCObject
            // marked so the sweep keeps them alive while referenced.
            if (getGCObject(g, str)) |gc| try markObject(L, gc, gray_list);
        },
        .table => |t| if (t) |tbl| if (getGCObject(g, tbl)) |gc| try markObject(L, gc, gray_list),
        .function => |f| if (f) |cl| if (getGCObject(g, cl)) |gc| try markObject(L, gc, gray_list),
        .upval => |u| if (u) |uv| if (getGCObject(g, uv)) |gc| try markObject(L, gc, gray_list),
        .proto => |p| if (p) |pr| if (getGCObject(g, pr)) |gc| try markObject(L, gc, gray_list),
        .userdata => |u| if (u) |ud| if (getGCObject(g, ud)) |gc| try markObject(L, gc, gray_list),
        .thread => |t| if (t) |th| if (getGCObject(g, th)) |gc| try markObject(L, gc, gray_list),
        else => {},
    }
}

/// Mark a thread's stack slots (per its lua.CallInfo chain) and open upvalues.
fn markThreadStack(L: *lua.lua_State, gray_list: *std.ArrayList(*lua.VMGCObject), th: *lua.lua_State) !void {
    const g = lua.G(L);
    var opt_th_ci: ?*lua.CallInfo = th.ci;
    var next_th_ci_func: ?usize = null;
    var max_live: usize = th.top;
    while (opt_th_ci) |th_ci| {
        var s_idx = th_ci.func;
        const frame_top = if (lua.isLua(th_ci, th)) th_ci.top else th.top;
        const top_limit = if (next_th_ci_func) |nfunc| nfunc else @max(th.top, frame_top);
        const s_lim = @min(top_limit, th.stack.len);
        if (s_lim > max_live) max_live = s_lim;
        while (s_idx < s_lim) : (s_idx += 1) {
            try markValue(L, gray_list, th.stack[s_idx]);
        }
        next_th_ci_func = th_ci.func;
        opt_th_ci = th_ci.previous;
    }
    for (th.tbclist.items) |abs| {
        if (abs < th.stack.len) {
            try markValue(L, gray_list, th.stack[abs]);
            if (abs + 1 > max_live) max_live = abs + 1;
        }
    }
    var curr_uv = th.openupval;
    while (curr_uv) |uv| {
        if (getGCObject(g, uv)) |gc| {
            try markObject(L, gc, gray_list);
        }
        curr_uv = uv.next;
    }
    if (max_live < th.stack.len) {
        @memset(th.stack[max_live..], .{ .nil = {} });
    }
}

/// Traverse the outgoing references of a gray/black object, marking them.
/// Shared by the main collection and the pre-finalizer marking pass.
fn traverseGrayObject(L: *lua.lua_State, gray_list: *std.ArrayList(*lua.VMGCObject), gc: *lua.VMGCObject) !void {
    const g = lua.G(L);
    switch (gc.val) {
        .table => |t| {
            const mode = if (t.metatable) |mt| getWeakMode(L, mt) else WeakMode{ .keys = false, .vals = false };
            // Mark array part
            if (!mode.vals) {
                if (t.array.items.len > 0) {
                    for (t.array.items) |val| {
                        try markValue(L, gray_list, val);
                    }
                }
            }
            // Mark hash part
            for (t.node.items) |nd| {
                if (nd.val != .nil) {
                    if (!mode.keys) {
                        try markValue(L, gray_list, nd.key);
                    }
                    if (!mode.vals) {
                        try markValue(L, gray_list, nd.val);
                    }
                }
            }
            // Mark metatable
            if (t.metatable) |mt| {
                if (getGCObject(g, mt)) |mt_gc| {
                    try markObject(L, mt_gc, gray_list);
                }
            }
        },
        .closure => |cl| {
            switch (cl.*) {
                .c => |cc| {
                    for (cc.upvals) |uv| {
                        try markValue(L, gray_list, uv);
                    }
                },
                .lua => |lc| {
                    // Mark prototype
                    if (getGCObject(g, lc.p)) |proto_gc| {
                        try markObject(L, proto_gc, gray_list);
                    }
                    // Mark upvalues
                    for (lc.upvals) |opt_uv| {
                        if (opt_uv) |uv| {
                            if (getGCObject(g, uv)) |uv_gc| {
                                try markObject(L, uv_gc, gray_list);
                            }
                        }
                    }
                },
            }
        },
        .upval => |uv| {
            if (uv.v == &uv.value) {
                try markValue(L, gray_list, uv.value);
            } else {
                const addr = @intFromPtr(uv.v);
                var is_on_stack = false;
                var curr_th = lua.G(L).thread_list;
                while (curr_th) |th| : (curr_th = th.twups) {
                    const base = @intFromPtr(th.stack.ptr);
                    const top_addr = base + th.top * @sizeOf(lua.TValue);
                    if (addr >= base and addr < top_addr) {
                        is_on_stack = true;
                        break;
                    }
                }
                if (is_on_stack) {
                    try markValue(L, gray_list, uv.v.*);
                }
            }
        },
        .proto => |p| {
            if (p.source) |src| try markString(L, gray_list, src);
            // Mark upvalue names
            for (p.upvalues) |uvd| {
                if (uvd.name) |name| try markString(L, gray_list, name);
            }
            // Mark local variable names
            for (p.locvars) |lv| {
                if (lv.varname) |name| try markString(L, gray_list, name);
            }
            // Mark constants
            for (p.k) |val| {
                try markValue(L, gray_list, val);
            }
            // Mark nested prototypes
            for (p.p) |sub_p| {
                if (getGCObject(g, sub_p)) |sub_gc| {
                    try markObject(L, sub_gc, gray_list);
                }
            }
        },
        .userdata => |ud| {
            for (ud.uv) |val| {
                try markValue(L, gray_list, val);
            }
            if (ud.metatable) |mt| {
                if (getGCObject(g, mt)) |mt_gc| {
                    try markObject(L, mt_gc, gray_list);
                }
            }
        },
        .thread => |th| {
            try markThreadStack(L, gray_list, th);
        },
        // Strings (external) have no outgoing references to traverse.
        .string => {},
    }
}

pub fn freeGCObject(L: *lua.lua_State, gc: *lua.VMGCObject) void {
    const g = lua.G(L);
    const sz: usize = switch (gc.val) {
        .table => |t| @sizeOf(lua.lua_Table) + t.array.capacity * @sizeOf(lua.TValue) + t.node.capacity * @sizeOf(lua.Node),
        .string => |ts| @sizeOf(lua.lua_TString) + ts.s.len + 1,
        .closure => |cl| switch (cl.*) {
            .c => |cc| @sizeOf(lua.lua_Closure) + @sizeOf(lua.lua_CClosure) + cc.upvals.len * @sizeOf(lua.TValue),
            .lua => |lc| @sizeOf(lua.lua_Closure) + @sizeOf(lua.lua_LClosure) + lc.upvals.len * @sizeOf(?*lua.UpVal),
        },
        .userdata => |ud| @sizeOf(lua.lua_Udata) + ud.data.len + ud.uv.len * @sizeOf(lua.TValue),
        .proto => @sizeOf(lua.lua_Proto),
        .upval => @sizeOf(lua.UpVal),
        .thread => |th| @sizeOf(lua.lua_State) + th.stack.len * @sizeOf(lua.TValue),
    };
    if (g.totalbytes >= sz + @sizeOf(lua.VMGCObject)) {
        g.totalbytes -= sz + @sizeOf(lua.VMGCObject);
    } else {
        g.totalbytes = 0;
    }
    switch (gc.val) {
        .table => |t| {
            lua.ltable.deinit(t);
        },
        .closure => |cl| {
            switch (cl.*) {
                .c => |cc| {
                    L.allocator.free(cc.upvals);
                    L.allocator.destroy(cc);
                },
                .lua => |lc| {
                    L.allocator.free(lc.upvals);
                    L.allocator.destroy(lc);
                },
            }
            L.allocator.destroy(cl);
        },
        .upval => |uv| {
            L.allocator.destroy(uv);
        },
        .proto => |f| {
            lua.destroyProto(L.allocator, f);
        },
        .userdata => |u| {
            L.allocator.free(u.data);
            if (u.uv.len > 0) L.allocator.free(u.uv);
            L.allocator.destroy(u);
        },
        .string => |ts| {
            if (ts.falloc) |falloc| {
                _ = falloc(ts.ud, @constCast(ts.s.ptr), ts.len + 1, 0);
            } else if (!ts.externally_owned and ts.s.len > 0) {
                L.allocator.free(ts.s);
            }
            L.allocator.destroy(ts);
        },
        .thread => |th| {
            lua.luaF_closeupval(th, 0);
            if (g.thread_list == th) {
                g.thread_list = th.twups;
            } else {
                var prev_th = g.thread_list;
                while (prev_th) |p| {
                    if (p.twups == th) {
                        p.twups = th.twups;
                        break;
                    }
                    prev_th = p.twups;
                }
            }
            lua.freeAllCallInfos(th);
            th.tbclist.deinit(th.allocator);
            th.allocator.free(th.stack);
            th.allocator.destroy(th);
        },
    }
    L.allocator.destroy(gc);
}

const WeakMode = struct { keys: bool, vals: bool };

fn getWeakMode(L: *lua.lua_State, mt: *lua.lua_Table) WeakMode {
    var keys = false;
    var vals = false;
    const g = lua.G(L);
    const tm_mode_str = g.tmname[3] orelse return .{ .keys = false, .vals = false };
    const mode_val = lua.ltable.get(mt, .{ .string = tm_mode_str });
    switch (mode_val) {
        .string => |s| {
            if (s) |str| {
                for (str.s) |c| {
                    if (c == 'k') keys = true;
                    if (c == 'v') vals = true;
                }
            }
        },
        else => {},
    }
    return .{ .keys = keys, .vals = vals };
}

fn getGCObjectFromValue(g: *lua.global_State, val: lua.TValue) ?*lua.VMGCObject {
    return switch (val) {
        .table => |t| if (t) |p| getGCObject(g, p) else null,
        .string => |s| if (s) |p| getGCObject(g, p) else null,
        .function => |f| if (f) |p| getGCObject(g, p) else null,
        .userdata => |u| if (u) |p| getGCObject(g, p) else null,
        .thread => |t| if (t) |p| getGCObject(g, p) else null,
        .upval => |u| getGCObject(g, u),
        .proto => |p| if (p) |p_val| getGCObject(g, p_val) else null,
        else => null,
    };
}

fn isWhiteGCObject(g: *lua.global_State, val: lua.TValue) bool {
    if (getGCObjectFromValue(g, val)) |gc| {
        return gc.color == .white;
    }
    return false;
}

/// Port of the reference `iscleared` (lua/lgc.c:223): decides whether a weak
/// table entry's key/value must be removed during the weak sweep. Strings
/// are NEVER removed from weak tables ("strings behave as 'values', so are
/// never removed") — the reference marks them on sight, and so do we, so the
/// string sweep keeps them alive (BUG-172: unmarked short-string keys were
/// freed while still referenced by table nodes, corrupting the entries).
/// Non-collectable values are never cleared.
fn isClearedGCValue(g: *lua.global_State, val: lua.TValue) bool {
    switch (val) {
        .string => |s| {
            if (s) |str| {
                str.marked = true;
                // Long/external strings live in allgc; keep their GC object
                // alive across the sweep as well.
                if (getGCObject(g, str)) |gc| {
                    gc.color = .black;
                }
            }
            return false;
        },
        else => return isWhiteGCObject(g, val),
    }
}

fn luaS_clearcache(L: *lua.lua_State) void {
    const g = lua.G(L);
    for (&g.strcache) |*bucket| {
        for (bucket) |*slot| {
            if (slot.*) |ts| {
                var is_dead = false;
                if (getGCObject(g, ts)) |gc| {
                    if (gc.color == .white) {
                        is_dead = true;
                    }
                } else {
                    if (!ts.marked) {
                        is_dead = true;
                    }
                }
                if (is_dead) {
                    slot.* = null;
                }
            }
        }
    }
}

pub inline fn luaC_condGC(L: *lua.lua_State) void {
    const g = lua.G(L);
    // Compare the live-object count against the count-based threshold (the
    // same condition the VM loop used to check per instruction); comparing
    // totalbytes here would fire constantly, since a few large live objects
    // can exceed the threshold.
    // BUG-100: GC failure on condGC is reported, not silently swallowed.
    if (g.gc_running and !g.gc_in_progress and g.gc_count > g.gc_threshold) {
        luaC_collectgarbage(L) catch |err| {
            std.debug.print("luazig: conditional GC step failed: {t}\n", .{err});
        };
    }
}

/// Port of the reference `checkGC(L, c)` macro (lua/lvm.c:1184): a
/// conditional collection at an object-registration site, with `top` set
/// around the step so an emergency collection sees the right stack top
/// (the reference's `(savepc(ci), L->top.p = c)` pre-expression). Used at
/// the VM opcode sites (NEWTABLE/CONCAT/CLOSURE). Unlike `luaC_condGC`
/// (fire-and-forget, matching the reference's void `luaC_checkGC` at the
/// C-API sites), this propagates OOM, preserving the VM loop's previous
/// `try` semantics (a GC failure still surfaces as `lua.LUA_ERRMEM`).
pub inline fn luaC_checkGC(L: *lua.lua_State, top: usize) anyerror!void {
    const g = lua.G(L);
    if (g.gc_running and !g.gc_in_progress and g.gc_count > g.gc_threshold) {
        const old_top = L.top;
        L.top = top;
        defer L.top = old_top;
        try luaC_collectgarbage(L);
    }
}

pub fn luaC_collectgarbage(L: *lua.lua_State) !void {
    const g = lua.G(L);
    if (g.gc_in_progress) return;
    g.gc_in_progress = true;
    defer g.gc_in_progress = false;

    // 1. Reset/Clear gray list
    var gray_list = std.ArrayList(*lua.VMGCObject).empty;
    defer gray_list.deinit(L.allocator);

    // 2. Set all objects to white
    var curr = g.allgc;
    while (curr) |gc| {
        gc.color = .white;
        curr = gc.next;
    }
    var strt_it = g.strt.iterator();
    while (strt_it.next()) |entry| {
        entry.value_ptr.*.marked = false;
    }

    // 3. Mark roots
    // Root 1: Registry table
    try markValue(L, &gray_list, g.registry);

    // Root 2: Global metatables
    for (g.mt) |opt_mt| {
        if (opt_mt) |mt| {
            if (getGCObject(g, mt)) |gc| {
                try markObject(L, gc, &gray_list);
            }
        }
    }

    // Root 3: Metamethod names
    for (g.tmname) |opt_name| {
        if (opt_name) |name| {
            name.marked = true;
        }
    }

    // Root 3b: intentionally omitted. The string table is NOT a GC root:
    // interned strings are kept alive only when actually referenced (from the
    // stack, tables, protos, the metamethod-name table, or the API string
    // cache below). This matches the reference, which collects unreferenced
    // strings instead of pinning every interned literal.

    // Root 3c: intentionally omitted. The string cache is a weak reference
    // and is cleared of dead entries via luaS_clearcache before sweeping.

    // Root 4: The stack of all active states and call frames, plus the open
    // upvalues of the current thread. (The reference's traverseThread marks
    // open upvalues for every thread; ours were only marked for OTHER threads
    // in Root 4b, so a GC running on the current thread could collect an open
    // lua.UpVal still linked in L.openupval -> use-after-free in closeupvals.)
    var opt_ci: ?*lua.CallInfo = L.ci;
    var next_ci_func: ?usize = null;
    var max_live: usize = L.top;
    while (opt_ci) |ci| {
        var s_idx = ci.func;
        const frame_top = if (lua.isLua(ci, L)) ci.top else L.top;
        const top_limit = if (next_ci_func) |nfunc| nfunc else @max(L.top, frame_top);
        const s_lim = @min(top_limit, L.stack.len);
        if (s_lim > max_live) max_live = s_lim;
        while (s_idx < s_lim) : (s_idx += 1) {
            try markValue(L, &gray_list, L.stack[s_idx]);
        }
        next_ci_func = ci.func;
        opt_ci = ci.previous;
    }
    for (L.tbclist.items) |abs| {
        if (abs < L.stack.len) {
            try markValue(L, &gray_list, L.stack[abs]);
            if (abs + 1 > max_live) max_live = abs + 1;
        }
    }
    var curr_uv = L.openupval;
    while (curr_uv) |uv| {
        if (getGCObject(g, uv)) |gc| {
            try markObject(L, gc, &gray_list);
        }
        curr_uv = uv.next;
    }
    if (max_live < L.stack.len) {
        @memset(L.stack[max_live..], .{ .nil = {} });
    }

    // Root 4b: The stack and open upvalues of the main thread (which is not
    // on allgc, so it is an unconditional GC root).
    if (g.mainthread) |mt| {
        if (mt != L) {
            try markThreadStack(L, &gray_list, mt);
        }
    }

    // 4. Traverse gray list until empty
    while (gray_list.pop()) |gc| {
        if (gc.color == .black) continue;
        gc.color = .black;
        try traverseGrayObject(L, &gray_list, gc);
    }

    // 4.5 Clear weak tables
    var clear_curr = g.allgc;
    while (clear_curr) |gc| {
        if (gc.color == .black) {
            switch (gc.val) {
                .table => |t| {
                    if (t.metatable) |mt| {
                        const mode = getWeakMode(L, mt);
                        if (mode.keys or mode.vals) {
                            // Clear weak array part (only values can be weak)
                            if (mode.vals) {
                                for (t.array.items) |*val| {
                                    if (isClearedGCValue(g, val.*)) {
                                        val.* = .nil;
                                    }
                                }
                            }
                            // Clear weak hash part
                            for (t.node.items) |*nd| {
                                if (nd.key != .nil and nd.val != .nil) {
                                    const key_white = mode.keys and isClearedGCValue(g, nd.key);
                                    const val_white = mode.vals and isClearedGCValue(g, nd.val);
                                    if (key_white or val_white) {
                                        nd.val = .nil;
                                    }
                                }
                            }
                        }
                    }
                },
                else => {},
            }
        }
        clear_curr = gc.next;
    }

    luaS_clearcache(L);

    // 5. Sweep phase: free white objects
    // Pre-pass: identify objects with an unrun __gc finalizer and keep their
    // metatables alive (mark them gray and traverse), so the sweep can
    // safely inspect __gc and the finalizer call has a live metatable.
    var pending = std.ArrayList(*lua.VMGCObject).empty;
    defer pending.deinit(L.allocator);
    {
        var pp = g.allgc;
        while (pp) |gc| : (pp = gc.next) {
            if (gc.color != .white or gc.finalized) continue;
            const mt = metatableOf(L, gc);
            if (mt) |m| {
                if (getGCObject(g, m)) |mt_gc| {
                    const fin = rawHasFinalizer(L, m);
                    if (fin) {
                        try pending.append(L.allocator, gc);
                        gc.pending_fin = true;
                        if (mt_gc.color == .white) {
                            mt_gc.color = .gray;
                            try gray_list.append(L.allocator, mt_gc);
                        }
                    }
                }
            }
        }
        // Traverse the metatables just kept alive (so __gc and friends survive).
        while (gray_list.pop()) |gc| {
            if (gc.color == .black) continue;
            gc.color = .black;
            try traverseGrayObject(L, &gray_list, gc);
        }
    }

    var prev_gc: ?*lua.VMGCObject = null;
    var sweep_curr = g.allgc;
    g.gc_count = 0;
    while (sweep_curr) |gc| {
        const next_gc = gc.next;
        if (gc.color == .white) {
            if (gc.finalized) {
                // Finalizer already ran last cycle; now free it.
                if (prev_gc) |prev| {
                    prev.next = next_gc;
                } else {
                    g.allgc = next_gc;
                }
                freeGCObject(L, gc);
                sweep_curr = next_gc;
                continue;
            }
            // Objects with an unrun __gc finalizer (flagged by the pre-pass)
            // are kept for one cycle and finalized after the sweep; next
            // collection frees them.
            if (gc.pending_fin) {
                gc.pending_fin = false;
                // Unlink from allgc and link into the pending-finalization list.
                if (prev_gc) |prev| {
                    prev.next = next_gc;
                } else {
                    g.allgc = next_gc;
                }
                gc.next = g.finobj;
                g.finobj = gc;
                gc.color = .white;
                sweep_curr = next_gc;
                continue;
            }
            // Unlink from allgc
            if (prev_gc) |prev| {
                prev.next = next_gc;
            } else {
                g.allgc = next_gc;
            }

            // Free the object's resources
            freeGCObject(L, gc);
        } else {
            gc.color = .white; // Reset to white for next cycle
            prev_gc = gc;
            g.gc_count += 1;
        }
        sweep_curr = next_gc;
    }
    g.gc_threshold = @max(1000, g.gc_count * 2);

    // Sweep strings:
    // First, find all unmarked strings. Collect the `*lua.lua_TString` values
    // (whose `.s` bytes are stable and independent of the map's key array);
    // do NOT retain slices into the map itself, because `swapRemove` below
    // reorders that array and would invalidate them.
    var dead_strings = std.ArrayList(*lua.lua_TString).empty;
    defer dead_strings.deinit(L.allocator);

    var str_it = g.strt.iterator();
    while (str_it.next()) |entry| {
        const ts = entry.value_ptr.*;
        if (!ts.marked) {
            try dead_strings.append(L.allocator, ts);
        } else {
            ts.marked = false; // Reset for next GC cycle
        }
    }

    // Now remove from strt table and free the dead short strings. Short
    // strings are NOT registered in allgc (see lua.lstring.createString), so the
    // allgc sweep above never sees them; without this they would leak.
    for (dead_strings.items) |ts| {
        _ = g.strt.swapRemove(ts.s);
        if (ts.falloc) |falloc| {
            _ = falloc(ts.ud, @constCast(ts.s.ptr), ts.len + 1, 0);
        } else if (!ts.externally_owned and ts.s.len > 0) {
            L.allocator.free(ts.s);
        }
        L.allocator.destroy(ts);
    }

    // 6. Run pending finalizers. Each object's fields are marked (so the
    // objects they reference survive during the __gc call), the finalizer
    // runs, and the object is linked back into allgc as finalized so the next
    // collection frees it without re-running __gc.
    while (g.finobj) |fobj| {
        g.finobj = fobj.next;
        try callFinalizer(L, fobj);
    }
}

/// Check `__gc` in a metatable without any liveness guard (only safe before
/// the sweep frees anything).
fn rawHasFinalizer(L: *lua.lua_State, mt: *lua.lua_Table) bool {
    const g = lua.G(L);
    if (g.tmname[@intFromEnum(lua.ltm.TMS.GC)]) |gc_name| {
        const tm = lua.ltable.get(mt, lua.TValue{ .string = gc_name });
        if (tm == .function or tm == .table) return true;
    }
    return false;
}

/// Metatable of a table/userdata GC object, if any.
fn metatableOf(L: *lua.lua_State, gc: *lua.VMGCObject) ?*lua.lua_Table {
    _ = L;
    return switch (gc.val) {
        .table => |t| t.metatable,
        .userdata => |u| u.metatable,
        else => null,
    };
}

/// Mark an object's outgoing references, then invoke its `__gc` metamethod
/// with the object as argument. The object is relinked into allgc as
/// finalized so the next collection frees it.
fn callFinalizer(L: *lua.lua_State, gc: *lua.VMGCObject) !void {
    const g = lua.G(L);
    // Mark this object and its references so they survive the finalizer call.
    var gray_list = std.ArrayList(*lua.VMGCObject).empty;
    defer gray_list.deinit(L.allocator);
    gc.color = .gray;
    try gray_list.append(L.allocator, gc);
    while (gray_list.pop()) |c| {
        if (c.color == .black) continue;
        c.color = .black;
        try traverseGrayObject(L, &gray_list, c);
    }

    const obj_val: lua.TValue = switch (gc.val) {
        .table => |t| lua.TValue{ .table = t },
        .userdata => |u| lua.TValue{ .userdata = u },
        else => unreachable,
    };
    const mt: *lua.lua_Table = switch (gc.val) {
        .table => |t| t.metatable.?,
        .userdata => |u| u.metatable.?,
        else => unreachable,
    };
    const tm = lua.ltable.get(mt, lua.TValue{ .string = g.tmname[@intFromEnum(lua.ltm.TMS.GC)].? });
    if (tm == .function or tm == .table) {
        if (L.top + 2 < L.stack.len) {
            L.stack[L.top] = tm;
            L.stack[L.top + 1] = obj_val;
            L.top += 2;
            const old_allowhook = L.allowhook;
            L.allowhook = 0;
            const old_fin = if (L.ci) |ci| blk: {
                const o = ci.is_fin;
                ci.is_fin = true;
                break :blk o;
            } else null;
            _ = lua.lua_pcallk(L, 1, 0, 0, 0, null) catch {
                lua.luaE_warnerror(L, "__gc");
            };
            if (L.ci) |ci| {
                ci.is_fin = old_fin orelse false;
            }
            L.allowhook = old_allowhook;
        }
    }

    // Relink into allgc; the next collection frees it (finalizer already ran).
    gc.finalized = true;
    gc.color = .white;
    gc.next = g.allgc;
    g.allgc = gc;
}

pub const LUA_GCSTOP: i32 = 0;
pub const LUA_GCRESTART: i32 = 1;
pub const LUA_GCCOLLECT: i32 = 2;
pub const LUA_GCCOUNT: i32 = 3;
pub const LUA_GCCOUNTB: i32 = 4;
pub const LUA_GCSTEP: i32 = 5;
pub const LUA_GCISRUNNING: i32 = 6;
pub const LUA_GCGEN: i32 = 7;
pub const LUA_GCINC: i32 = 8;
pub const LUA_GCPARAM: i32 = 9;

// GC parameter indices (for LUA_GCPARAM)
pub const LUA_GCPMINORMUL: i32 = 0;
pub const LUA_GCPMAJORMINOR: i32 = 1;
pub const LUA_GCPMINORMAJOR: i32 = 2;
pub const LUA_GCPPAUSE: i32 = 3;
pub const LUA_GCPSTEPMUL: i32 = 4;
pub const LUA_GCPSTEPSIZE: i32 = 5;
pub const LUA_GCPN: usize = 6;

/// Lua GC control. `what` selects the operation; `arg` is operation-dependent.
/// For all options except `LUA_GCPARAM`, `value` is ignored (pass 0).
/// For `LUA_GCPARAM`, `arg` is the parameter index and `value` is the new
/// value to set (pass -1 to get the current parameter without setting).
pub fn lua_gc(L: *lua.lua_State, what: i32, arg: i32, value: i32) i32 {
    const g = lua.G(L);
    switch (what) {
        LUA_GCSTOP => {
            g.gc_running = false;
            return 0;
        },
        LUA_GCRESTART => {
            g.gc_running = true;
            return 0;
        },
        LUA_GCCOLLECT => {
            luaC_collectgarbage(L) catch return -1;
            g.gc_step_accum = 0;
            return 0;
        },
        LUA_GCCOUNT => {
            return @as(i32, @intCast(g.totalbytes / 1024));
        },
        LUA_GCCOUNTB => {
            return @as(i32, @intCast(g.totalbytes % 1024));
        },
        LUA_GCSTEP => {
            // Bounded stepping for explicit sizes (BUG-169): `arg > 0`
            // accumulates `arg` work units and runs a full mark-and-sweep
            // collection only when the accumulator reaches the step budget
            // (the `stepmul` GC parameter), returning 1 for a completed cycle
            // and 0 otherwise. This keeps `collectgarbage("step", n)`
            // proportional to `n`, so gc.lua's `dosteps(10) < dosteps(2)`
            // holds. A bare `collectgarbage("step")` (arg == 0) performs a
            // complete cycle in one call (what the generational-mode tests,
            // e.g. gengc.lua, rely on).
            if (arg > 0) {
                const budget = @as(usize, @intCast(g.gcparams[LUA_GCPSTEPMUL]));
                g.gc_step_accum += @as(usize, @intCast(arg));
                if (budget > 0 and g.gc_step_accum >= budget) {
                    luaC_collectgarbage(L) catch return -1;
                    g.gc_step_accum = 0;
                    return 1;
                }
                return 0;
            }
            luaC_collectgarbage(L) catch return -1;
            g.gc_step_accum = 0;
            return 1;
        },
        LUA_GCISRUNNING => {
            return if (g.gc_running) 1 else 0;
        },
        LUA_GCGEN => {
            const old = g.gc_mode;
            g.gc_mode = LUA_GCGEN;
            return old;
        },
        LUA_GCINC => {
            const old = g.gc_mode;
            g.gc_mode = LUA_GCINC;
            return old;
        },
        LUA_GCPARAM => {
            const param = @as(usize, @intCast(arg));
            if (param >= LUA_GCPN) return -1;
            if (value >= 0) {
                g.gcparams[param] = @as(u8, @intCast(@min(@as(u64, @intCast(value)), 255)));
            }
            return @as(i32, @intCast(g.gcparams[param]));
        },
        else => return -1,
    }
}
