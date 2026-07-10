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

pub const luaT_eventname = [_][]const u8{
    "__index", "__newindex",
    "__gc", "__mode", "__len", "__eq",
    "__add", "__sub", "__mul", "__mod", "__pow",
    "__div", "__idiv",
    "__band", "__bor", "__bxor", "__shl", "__shr",
    "__unm", "__bnot", "__lt", "__le",
    "__concat", "__call", "__close"
};

pub fn luaT_init(L: *lua.lua_State) !void {
    const g = L.l_G orelse return;
    var i: usize = 0;
    while (i < @intFromEnum(TMS.CLOSE) + 1) : (i += 1) {
        g.tmname[i] = try lstring.luaS_new(g.allocator, &g.strt, g.seed, luaT_eventname[i]);
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
    _ = lua.lua_checkstack(L, 4);
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
    _ = lua.lua_checkstack(L, 3);
    L.stack[L.top] = f;
    L.stack[L.top + 1] = p1;
    L.stack[L.top + 2] = p2;
    L.top += 3;
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

pub fn luaT_equalobj(L: *lua.lua_State, t1: lua.TValue, t2: lua.TValue) !bool {
    if (@as(std.meta.Tag(lua.TValue), t1) != @as(std.meta.Tag(lua.TValue), t2)) {
        return false;
    }
    return switch (t1) {
        .nil => true,
        .boolean => |b| b == t2.boolean,
        .number => |n| n == t2.number,
        .lightud => |p| p == t2.lightud,
        .string => |s| s == t2.string,
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
    if (t1 == .number and t2 == .number) {
        return t1.number < t2.number;
    }
    if (t1 == .string and t2 == .string) {
        return std.mem.order(u8, t1.string.?.s, t2.string.?.s) == .lt;
    }
    return try luaT_callorderTM(L, t1, t2, .LT);
}

pub fn luaT_le(L: *lua.lua_State, t1: lua.TValue, t2: lua.TValue) !bool {
    if (t1 == .number and t2 == .number) {
        return t1.number <= t2.number;
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
pub fn luaV_gettable(L: *lua.lua_State, t: lua.TValue, key: lua.TValue, res: usize) !void {
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
pub fn luaV_settable(L: *lua.lua_State, t: lua.TValue, key: lua.TValue, val: lua.TValue) !void {
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
