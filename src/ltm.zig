const std = @import("std");
const lua = @import("lua.zig");
const lstring = @import("lstring.zig");
const ltable = @import("ltable.zig");
const lvm = @import("lvm.zig");

pub const TMS = enum(u5) {
    INDEX = 0,
    NEWINDEX = 1,
    GC = 2,
    MODE = 3,
    LEN = 4,
    EQ = 5, // last tag method with fast access
    ADD = 6,
    SUB = 7,
    MUL = 8,
    MOD = 9,
    POW = 10,
    DIV = 11,
    IDIV = 12,
    BAND = 13,
    BOR = 14,
    BXOR = 15,
    SHL = 16,
    SHR = 17,
    UNM = 18,
    BNOT = 19,
    LT = 20,
    LE = 21,
    CONCAT = 22,
    CALL = 23,
    CLOSE = 24,

    pub const N = 25;
};

pub const luaT_eventname = [_][]const u8{ "__index", "__newindex", "__gc", "__mode", "__len", "__eq", "__add", "__sub", "__mul", "__mod", "__pow", "__div", "__idiv", "__band", "__bor", "__bxor", "__shl", "__shr", "__unm", "__bnot", "__lt", "__le", "__concat", "__call", "__close" };

pub fn luaT_init(L: *lua.lua_State) !void {
    const g = L.l_G orelse return;
    var i: usize = 0;
    while (i < @intFromEnum(TMS.CLOSE) + 1) : (i += 1) {
        g.tmname[i] = try lstring.luaS_new(L, luaT_eventname[i]);
    }
}

pub inline fn checknoTM(mt: ?*lua.lua_Table, event: TMS) bool {
    if (mt) |m| {
        return (m.flags & (@as(u8, 1) << @intCast(@intFromEnum(event)))) != 0;
    }
    return true;
}

pub fn luaT_gettm(events: *lua.lua_Table, event: TMS, ename: *lua.lua_TString) ?lua.TValue {
    const tm = ltable.get(events, lua.TValue{ .string = ename });
    if (tm == .nil) {
        if (@intFromEnum(event) <= @intFromEnum(TMS.EQ)) {
            events.flags |= @as(u8, 1) << @intCast(@intFromEnum(event));
        }
        return null;
    }
    return tm;
}

pub fn luaT_gettmbyobj(L: *lua.lua_State, o: lua.TValue, event: TMS) lua.TValue {
    const mt: ?*lua.lua_Table = switch (o) {
        .table => |t| if (t) |tbl| tbl.metatable else null,
        .userdata => |u| if (u) |ud| ud.metatable else null,
        else => {
            const t = o.typ();
            if (t >= 0 and t < 9) {
                if (L.l_G) |g| {
                    return if (g.mt[@intCast(t)]) |m| luaT_gettm(m, event, g.tmname[@intFromEnum(event)].?) orelse lua.TValue{ .nil = {} } else lua.TValue{ .nil = {} };
                }
            }
            return lua.TValue{ .nil = {} };
        },
    };
    if (mt) |m| {
        if (L.l_G) |g| {
            return luaT_gettm(m, event, g.tmname[@intFromEnum(event)].?) orelse lua.TValue{ .nil = {} };
        }
    }
    return lua.TValue{ .nil = {} };
}

pub fn luaD_call(L: *lua.lua_State, func_idx: usize, nresults: i32) !void {
    if (try lua.precall(L, func_idx, nresults)) |new_ci| {
        try lvm.run(L, new_ci);
    }
}

pub fn luaT_callTM(L: *lua.lua_State, f: lua.TValue, p1: lua.TValue, p2: lua.TValue, p3: lua.TValue) !void {
    const old_top = L.top;
    if (lua.lua_checkstack(L, 4) == 0) return error.OutOfMemory;
    L.stack[L.top] = f;
    L.stack[L.top + 1] = p1;
    L.stack[L.top + 2] = p2;
    L.stack[L.top + 3] = p3;
    L.top += 4;
    try luaD_call(L, old_top, 0);
    L.top = old_top;
}

pub fn luaT_callTMres(L: *lua.lua_State, f: lua.TValue, p1: lua.TValue, p2: lua.TValue, res: usize) !lua.TValue {
    const old_top = L.top;
    if (lua.lua_checkstack(L, 3) == 0) return error.OutOfMemory;
    L.stack[old_top] = f;
    L.stack[old_top + 1] = p1;
    L.stack[old_top + 2] = p2;
    L.top = old_top + 3;
    try luaD_call(L, old_top, 1);
    const result = L.stack[old_top];
    L.stack[res] = result;
    L.top = old_top;
    return result;
}

pub fn luaT_trybinTM(L: *lua.lua_State, p1: lua.TValue, p2: lua.TValue, res: usize, event: TMS) !void {
    var tm = luaT_gettmbyobj(L, p1, event);
    if (tm == .nil) {
        tm = luaT_gettmbyobj(L, p2, event);
    }
    if (tm == .nil) {
        return error.RuntimeError;
    }
    _ = try luaT_callTMres(L, tm, p1, p2, res);
}

pub fn luaT_callorderTM(L: *lua.lua_State, p1: lua.TValue, p2: lua.TValue, event: TMS) !bool {
    var tm = luaT_gettmbyobj(L, p1, event);
    if (tm == .nil) {
        tm = luaT_gettmbyobj(L, p2, event);
    }
    if (tm == .nil) {
        return error.RuntimeError;
    }
    const res_val = try luaT_callTMres(L, tm, p1, p2, L.top);
    return switch (res_val) {
        .nil => false,
        .boolean => |b| b,
        else => true,
    };
}

inline fn G(L: *lua.lua_State) *lua.global_State {
    return L.l_G orelse @panic("global state not initialized");
}

pub inline fn luaT_equalobj(L: *lua.lua_State, t1: lua.TValue, t2: lua.TValue) !bool {
    // Fast path: both values are numbers (f64-only model) — direct compare,
    // Fast path: both are the same numeric variant.
    if (t1 == .number and t2 == .number) {
        return t1.number == t2.number;
    }
    if (t1 == .integer and t2 == .integer) {
        return t1.integer == t2.integer;
    }
    // Cross-type numeric: integer vs number — compare by converting to f64.
    if (t1 == .integer and t2 == .number) {
        return @as(f64, @floatFromInt(t1.integer)) == t2.number;
    }
    if (t1 == .number and t2 == .integer) {
        return t1.number == @as(f64, @floatFromInt(t2.integer));
    }
    if (@as(std.meta.Tag(lua.TValue), t1) != @as(std.meta.Tag(lua.TValue), t2)) {
        return false;
    }
    return switch (t1) {
        .nil => true,
        .boolean => |b| b == t2.boolean,
        .number => |n| n == t2.number,
        .integer => |n| n == t2.integer,
        .lightud => |p| p == t2.lightud,
        .string => |s| blk: {
            const t2s = t2.string;
            if (s == null and t2s == null) break :blk true;
            if (s == null or t2s == null) break :blk false;
            break :blk lstring.luaS_eqstr(s.?, t2s.?);
        },
        .function => |f| f == t2.function,
        .thread => |t| t == t2.thread,
        .upval => |u| u == t2.upval,
        .proto => |p| p == t2.proto,
        .table => |h1| {
            const h2 = t2.table.?;
            if (h1 == h2) return true;
            var tm = if (h1.?.metatable) |mt| luaT_gettm(mt, .EQ, G(L).tmname[@intFromEnum(TMS.EQ)].?) else null;
            if (tm == null) {
                tm = if (h2.metatable) |mt| luaT_gettm(mt, .EQ, G(L).tmname[@intFromEnum(TMS.EQ)].?) else null;
            }
            if (tm) |tm_val| {
                const res = try luaT_callTMres(L, tm_val, t1, t2, L.top);
                return switch (res) {
                    .nil => false,
                    .boolean => |b| b,
                    else => true,
                };
            }
            return false;
        },
        .userdata => |ud1| {
            const ud2 = t2.userdata.?;
            if (ud1 == ud2) return true;
            const mt1 = if (ud1) |u| u.metatable else null;
            const mt2 = ud2.metatable;
            var tm = if (mt1) |mt| luaT_gettm(mt, .EQ, G(L).tmname[@intFromEnum(TMS.EQ)].?) else null;
            if (tm == null) {
                tm = if (mt2) |mt| luaT_gettm(mt, .EQ, G(L).tmname[@intFromEnum(TMS.EQ)].?) else null;
            }
            if (tm) |tm_val| {
                const res = try luaT_callTMres(L, tm_val, t1, t2, L.top);
                return switch (res) {
                    .nil => false,
                    .boolean => |b| b,
                    else => true,
                };
            }
            return false;
        },
    };
}

pub fn luaT_lt(L: *lua.lua_State, t1: lua.TValue, t2: lua.TValue) !bool {
    // Same-type numeric
    if (t1 == .number and t2 == .number) {
        return t1.number < t2.number;
    }
    if (t1 == .integer and t2 == .integer) {
        return t1.integer < t2.integer;
    }
    // Cross-type numeric: convert integer to f64 for comparison
    if (t1 == .number and t2 == .integer) {
        return t1.number < @as(f64, @floatFromInt(t2.integer));
    }
    if (t1 == .integer and t2 == .number) {
        return @as(f64, @floatFromInt(t1.integer)) < t2.number;
    }
    if (t1 == .string and t2 == .string) {
        return std.mem.order(u8, t1.string.?.s, t2.string.?.s) == .lt;
    }
    return try luaT_callorderTM(L, t1, t2, .LT);
}

pub fn luaT_le(L: *lua.lua_State, t1: lua.TValue, t2: lua.TValue) !bool {
    // Same-type numeric
    if (t1 == .number and t2 == .number) {
        return t1.number <= t2.number;
    }
    if (t1 == .integer and t2 == .integer) {
        return t1.integer <= t2.integer;
    }
    // Cross-type numeric: convert integer to f64 for comparison
    if (t1 == .number and t2 == .integer) {
        return t1.number <= @as(f64, @floatFromInt(t2.integer));
    }
    if (t1 == .integer and t2 == .number) {
        return @as(f64, @floatFromInt(t1.integer)) <= t2.number;
    }
    if (t1 == .string and t2 == .string) {
        return std.mem.order(u8, t1.string.?.s, t2.string.?.s) != .gt;
    }
    return try luaT_callorderTM(L, t1, t2, .LE);
}

// Maximum metamethod chain length (mirrors MAXTAGLOOP in C reference).
const MAXTAGLOOP: usize = 2000;

/// Metamethod-aware table read: `result = t[key]`.
///
/// If `t` is a table and `key` is present, returns the value directly.
/// Otherwise follows the `__index` chain:
///   - If `__index` is a function, calls it and returns the result.
///   - If `__index` is a table, recurses into that table.
/// Errors with `error.RuntimeError` when no metamethod exists.
pub inline fn luaV_gettable(L: *lua.lua_State, t: lua.TValue, key: lua.TValue, res: usize) !void {
    // Fast path: a plain table with no metatable cannot have an __index, so a
    // hit returns the value and a miss returns nil — no metamethod machinery.
    if (t == .table) {
        if (t.table) |tbl| {
            if (tbl.metatable == null) {
                L.stack[res] = ltable.get(tbl, key);
                return;
            }
        } else {
            L.stack[res] = .{ .nil = {} };
            return;
        }
    }
    var current = t;
    var loop: usize = 0;
    while (loop < MAXTAGLOOP) : (loop += 1) {
        if (current == .table) {
            const tbl = current.table orelse {
                L.stack[res] = .{ .nil = {} };
                return;
            };
            const val = ltable.get(tbl, key);
            if (val != .nil) {
                L.stack[res] = val;
                return;
            }
            // Key not found — look for __index
            const tm = luaT_gettmbyobj(L, current, .INDEX);
            if (tm == .nil) {
                // No __index: result is nil
                L.stack[res] = .{ .nil = {} };
                return;
            }
            if (tm == .function) {
                // __index is a function: call it
                _ = try luaT_callTMres(L, tm, current, key, res);
                return;
            }
            // __index is a value — recurse into it
            current = tm;
        } else {
            // Not a table — try __index metamethod on this type
            const tm = luaT_gettmbyobj(L, current, .INDEX);
            if (tm == .nil) {
                return error.RuntimeError; // no __index, type error
            }
            if (tm == .function) {
                _ = try luaT_callTMres(L, tm, current, key, res);
                return;
            }
            current = tm;
        }
    }
    return error.RuntimeError; // __index chain too long
}

/// Metamethod-aware table write: `t[key] = val`.
///
/// If `t` is a table and `key` is already present (or the table has no
/// `__newindex`), writes directly.  Otherwise follows the `__newindex` chain:
///   - If `__newindex` is a function, calls it.
///   - If `__newindex` is a table, recurses into that table.
/// Errors with `error.RuntimeError` when no metamethod exists.
pub inline fn luaV_settable(L: *lua.lua_State, t: lua.TValue, key: lua.TValue, val: lua.TValue) !void {
    // Fast path: a plain table with no metatable cannot have a __newindex, so a
    // raw write is always correct.
    if (t == .table) {
        if (t.table) |tbl| {
            if (tbl.metatable == null) {
                try ltable.set(tbl, key, val);
                return;
            }
        } else {
            return error.RuntimeError;
        }
    }
    var current = t;
    var loop: usize = 0;
    while (loop < MAXTAGLOOP) : (loop += 1) {
        if (current == .table) {
            const tbl = current.table orelse return error.RuntimeError;
            // Check whether the key already exists in the raw table.
            const existing = ltable.get(tbl, key);
            if (existing != .nil) {
                // Key already present: write directly (raw), no __newindex.
                try ltable.set(tbl, key, val);
                return;
            }
            // Key absent — look for __newindex
            const tm = luaT_gettmbyobj(L, current, .NEWINDEX);
            if (tm == .nil) {
                // No __newindex: raw insert
                try ltable.set(tbl, key, val);
                return;
            }
            if (tm == .function) {
                try luaT_callTM(L, tm, current, key, val);
                return;
            }
            // __newindex is a table — recurse
            current = tm;
        } else {
            const tm = luaT_gettmbyobj(L, current, .NEWINDEX);
            if (tm == .nil) {
                return error.RuntimeError;
            }
            if (tm == .function) {
                try luaT_callTM(L, tm, current, key, val);
                return;
            }
            current = tm;
        }
    }
    return error.RuntimeError; // __newindex chain too long
}

// ===================================================================
// Vararg support (port of lua/ltm.c luaT_adjustvarargs / luaT_getvarargs /
// luaT_getvararg). The C reference relocates the call frame for the
// "hidden vararg" (PF_VAHID) case; this port keeps the frame in place and
// reads hidden arguments directly from the stack just above the fixed
// parameters, which is layout-equivalent and avoids frame surgery.
// ===================================================================

// Prototype flag bits (lua/lobject.h).
const PF_VAHID = 1; // function has hidden vararg arguments
const PF_VATAB = 2; // function has vararg table
const PF_FIXED = 4; // prototype has parts in fixed memory

fn currentNumParams(L: *lua.lua_State, ci: *lua.CallInfo) usize {
    const fv = L.stack[ci.func];
    if (fv == .function) {
        if (fv.function) |clo| switch (clo.*) {
            .lua => |lc| return lc.p.numParams,
            else => {},
        };
    }
    return 0;
}

fn varargTableAt(L: *lua.lua_State, ci: *lua.CallInfo, np: usize) ?*lua.lua_Table {
    const tv = L.stack[ci.func + np + 1];
    if (tv == .table) return tv.table;
    return null;
}

fn createVarargTable(L: *lua.lua_State, first_extra: usize, n: usize) !*lua.lua_Table {
    const t = ltable.createTable(L.allocator, n, 1) catch return error.OutOfMemory;
    try lua.registerGC(L, t);
    var i: usize = 0;
    while (i < n) : (i += 1) {
        try ltable.setInt(t, @intCast(i + 1), L.stack[first_extra + i]);
    }
    const nkey = lua.TValue{ .string = try lstring.luaS_new(L, "n") };
    try ltable.set(t, nkey, lua.TValue{ .number = @as(f64, @floatFromInt(@as(i64, @intCast(n)))) });
    return t;
}

fn getnumargs(L: *lua.lua_State, ci: *lua.CallInfo, h: ?*lua.lua_Table) !i32 {
    if (h == null) return ci.nextraargs;
    const nkey = lua.TValue{ .string = try lstring.luaS_new(L, "n") };
    const res = ltable.get(h.?, nkey);
    // Mirror lua/ltm.c getnumargs: the vararg table's 'n' field must be a
    // proper non-negative integer not larger than INT_MAX/2. (luazig unifies
    // integers and floats into a single number type, so "proper integer"
    // here means an integral value, matching lua.lua_isinteger.)
    if (res != .number and res != .integer) {
        _ = lua.lua_pushstring(L, "vararg table has no proper 'n'");
        return lua.lua_error(L);
    }
    const nval = if (res == .integer) @as(f64, @floatFromInt(res.integer)) else res.number;
    if (@trunc(nval) != nval or
        nval < 0 or
        nval > @as(f64, @floatFromInt(std.math.maxInt(i32) / 2)))
    {
        _ = lua.lua_pushstring(L, "vararg table has no proper 'n'");
        return lua.lua_error(L);
    }
    return @intFromFloat(res.number);
}

// lua/ltm.c luaT_adjustvarargs
pub fn luaT_adjustvarargs(L: *lua.lua_State, ci: *lua.CallInfo, cl: *lua.lua_LClosure) !void {
    const p = cl.p;
    const totalargs = @as(i32, @intCast(L.top)) - @as(i32, @intCast(ci.func)) - 1;
    const nfixparams: usize = p.numParams;
    const nextra = totalargs - @as(i32, @intCast(nfixparams));
    if ((p.flag & PF_VATAB) != 0) {
        const t = try createVarargTable(L, ci.func + nfixparams + 1, @intCast(nextra));
        L.stack[ci.func + nfixparams + 1] = lua.TValue{ .table = t };
    } else {
        try buildhiddenargs(L, ci, totalargs, nfixparams, nextra, p.maxStackSize);
    }
}

/// Port of lua/ltm.c buildhiddenargs (PF_VAHID path).
/// Relocates the call frame above all arguments so that the function's
/// register space does not overlap with the hidden vararg area.
fn buildhiddenargs(L: *lua.lua_State, ci: *lua.CallInfo, totalargs: i32, nfixparams: usize, nextra: i32, maxstacksize: u8) !void {
    ci.nextraargs = nextra;
    // Mirrors the reference luaD_checkstack(L, p->maxstacksize + 1): the frame
    // is about to be relocated up by 'totalargs + 1', so reserve room for all
    // of the (relocated) function's registers above the current top.
    const need = L.top + @as(usize, @intCast(maxstacksize)) + 1;
    if (need > L.stack.len) {
        const old_len = L.stack.len;
        const new_len = @max(L.stack.len * 2, need);
        L.stack = try L.allocator.realloc(L.stack, new_len);
        @memset(L.stack[old_len..], .{ .nil = {} });
        L.stack_last = L.stack.len - 1;
    }
    L.stack[L.top] = L.stack[ci.func];
    L.top += 1;
    var i: usize = 1;
    while (i <= nfixparams) : (i += 1) {
        L.stack[L.top] = L.stack[ci.func + i];
        L.stack[ci.func + i] = .{ .nil = {} };
        L.top += 1;
    }
    ci.func += @as(usize, @intCast(totalargs)) + 1;
    ci.base = ci.func + 1;
    ci.top += @as(usize, @intCast(totalargs)) + 1;
    // The reference (luaD_precall) re-establishes 'L->top = ci->top' after
    // adjustvarargs relocates the frame. Mirror that here so the top covers
    // all live registers of the relocated frame (otherwise auxiliary calls
    // such as metamethod invocations clobber them).
    L.top = ci.top;
}

// lua/ltm.c luaT_getvarargs
pub fn luaT_getvarargs(L: *lua.lua_State, ci: *lua.CallInfo, where_idx: usize, wanted_in: i32, vatab: i32) !void {
    var wanted = wanted_in;
    const h: ?*lua.lua_Table = if (vatab >= 0) varargTableAt(L, ci, @intCast(vatab)) else null;
    const nargs = try getnumargs(L, ci, h);
    var touse: i32 = 0;
    if (wanted < 0) {
        touse = nargs;
        wanted = nargs;
        const need = where_idx + @as(usize, @intCast(nargs)) + 1;
        if (need > L.stack.len) {
            const old_len = L.stack.len;
            const new_len = @max(L.stack.len * 2, need);
            L.stack = try L.allocator.realloc(L.stack, new_len);
            @memset(L.stack[old_len..], .{ .nil = {} });
            L.stack_last = L.stack.len - 1;
        }
        L.top = where_idx + @as(usize, @intCast(nargs));
    } else {
        touse = if (nargs > wanted) wanted else nargs;
    }
    if (h == null) {
        var i: i32 = 0;
        while (i < touse) : (i += 1) {
            L.stack[where_idx + @as(usize, @intCast(i))] = L.stack[ci.func - @as(usize, @intCast(ci.nextraargs)) + @as(usize, @intCast(i))];
        }
    } else {
        var i: i32 = 0;
        while (i < touse) : (i += 1) {
            L.stack[where_idx + @as(usize, @intCast(i))] = ltable.getInt(h.?, @intCast(i + 1));
        }
    }
    var j = touse;
    while (j < wanted) : (j += 1) {
        L.stack[where_idx + @as(usize, @intCast(j))] = .{ .nil = {} };
    }
}

fn hasVatabFlag(L: *lua.lua_State, ci: *lua.CallInfo) bool {
    const fv = L.stack[ci.func];
    if (fv == .function) {
        if (fv.function) |clo| switch (clo.*) {
            .lua => |lc| return (lc.p.flag & PF_VATAB) != 0,
            else => {},
        };
    }
    return false;
}

// lua/ltm.c luaT_getvararg (single vararg: select('#', ...) or ...[k])
pub fn luaT_getvararg(L: *lua.lua_State, ci: *lua.CallInfo, ra_idx: usize, rc_idx: usize) !void {
    const rc = L.stack[rc_idx];
    const is_vatab = hasVatabFlag(L, ci);
    const np = if (is_vatab) currentNumParams(L, ci) else 0;
    if (rc.typ() == lua.LUA_TNUMBER) {
        const n = if (rc == .integer) @as(f64, @floatFromInt(rc.integer)) else rc.number;
        const n_int: i64 = if (rc == .integer) rc.integer else @as(i64, @intFromFloat(n));
        if (@as(f64, @floatFromInt(n_int)) == n and n_int >= 1) {
            const nextra = if (is_vatab) (try getnumargs(L, ci, varargTableAt(L, ci, np))) else ci.nextraargs;
            if (n_int - 1 < @as(i64, nextra)) {
                if (is_vatab) {
                    const t = varargTableAt(L, ci, np).?;
                    L.stack[ra_idx] = ltable.getInt(t, n_int);
                } else {
                    L.stack[ra_idx] = L.stack[ci.func - @as(usize, @intCast(nextra)) + @as(usize, @intCast(n_int - 1))];
                }
                return;
            }
        }
    } else if (rc.typ() == lua.LUA_TSTRING) {
        if (rc.string) |ts| {
            if (ts.s.len == 1 and ts.s[0] == 'n') {
                const nextra = if (is_vatab) (try getnumargs(L, ci, varargTableAt(L, ci, np))) else ci.nextraargs;
                L.stack[ra_idx] = lua.TValue{ .number = @as(f64, @floatFromInt(@as(i64, nextra))) };
                return;
            }
        }
    }
    L.stack[ra_idx] = .{ .nil = {} };
}
