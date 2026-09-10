const std = @import("std");
const lua = @import("lua.zig");
const lstring = @import("lstring.zig");
const ltable = @import("ltable.zig");
const lvm = @import("lvm.zig");
const llimits = @import("llimits.zig");

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

pub fn luaT_objtypename(L: *lua.lua_State, o: lua.TValue) []const u8 {
    const mt: ?*lua.lua_Table = switch (o) {
        .table => |t_opt| if (t_opt) |t| t.metatable else null,
        .userdata => |u_opt| if (u_opt) |u| u.metatable else null,
        else => null,
    };
    if (mt) |m| {
        if (lstring.luaS_new(L, "__name")) |name_ts| {
            const name_val = ltable.get(m, lua.TValue{ .string = name_ts });
            if (name_val == .string) {
                if (name_val.string) |s| return s.s;
            }
        } else |_| {}
    }
    return lua.lua_typename(o.typ());
}

pub inline fn checknoTM(mt: ?*lua.lua_Table, event: TMS) bool {
    if (mt) |m| {
        if (@intFromEnum(event) <= @intFromEnum(TMS.EQ)) {
            return (m.flags & (@as(u8, 1) << @intCast(@intFromEnum(event)))) != 0;
        }
        return false;
    }
    return true;
}

pub inline fn fasttm(L: *lua.lua_State, mt: ?*lua.lua_Table, event: TMS) ?lua.TValue {
    if (checknoTM(mt, event)) return null;
    const g = L.l_G orelse return null;
    return luaT_gettm(mt.?, event, g.tmname[@intFromEnum(event)].?);
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
                    if (g.mt[@intCast(t)]) |m| {
                        if (checknoTM(m, event)) return lua.TValue{ .nil = {} };
                        return luaT_gettm(m, event, g.tmname[@intFromEnum(event)].?) orelse lua.TValue{ .nil = {} };
                    }
                }
            }
            return lua.TValue{ .nil = {} };
        },
    };
    if (mt) |m| {
        if (checknoTM(m, event)) return lua.TValue{ .nil = {} };
        if (L.l_G) |g| {
            return luaT_gettm(m, event, g.tmname[@intFromEnum(event)].?) orelse lua.TValue{ .nil = {} };
        }
    }
    return lua.TValue{ .nil = {} };
}

pub fn savestate(L: *lua.lua_State) void {
    if (L.ci) |ci| {
        // Only RAISE the top to cover the frame; never lower it. Lowering
        // clobbers live values above ci.top (e.g. return values placed by
        // poscall, which sits above the frame's register top) before a
        // metamethod call runs.
        if (L.top < ci.top) {
            L.top = ci.top;
        }
    }
}

pub fn luaD_call(L: *lua.lua_State, func_idx: usize, nresults: i32) !void {
    const old_ci = L.ci;
    if (try lua.precall(L, func_idx, nresults)) |new_ci| {
        L.nCcalls += 1;
        defer L.nCcalls -= 1;
        if (L.nCcalls == llimits.LUAI_MAXCCALLS) {
            try lua.luaG_runerror(L, "C stack overflow");
        } else if (L.nCcalls >= llimits.LUAI_MAXCCALLS * 11 / 10) {
            return lua.luaD_errerr(L);
        }
        lvm.run(L, new_ci) catch |e| {
            if (e == error.Yield) return e;
            lua.unwindCis(L, old_ci);
            return e;
        };
    }
}

pub fn luaT_callTM(L: *lua.lua_State, f: lua.TValue, p1: *const lua.TValue, p2: *const lua.TValue, p3: *const lua.TValue) !void {
    const saved_top = L.top;
    savestate(L);
    if (lua.lua_checkstack(L, 4) == 0) return error.OutOfMemory;
    const old_top = L.top;
    L.stack[old_top] = f;
    L.stack[old_top + 1] = p1.*;
    L.stack[old_top + 2] = p2.*;
    L.stack[old_top + 3] = p3.*;
    L.top = old_top + 4;
    try luaD_call(L, old_top, 0);
    L.top = saved_top;
}

pub fn luaT_callTM1(L: *lua.lua_State, f: lua.TValue, p1: *const lua.TValue) !void {
    const saved_top = L.top;
    savestate(L);
    if (lua.lua_checkstack(L, 2) == 0) return error.OutOfMemory;
    const old_top = L.top;
    const old_ci = L.ci;
    L.stack[old_top] = f;
    L.stack[old_top + 1] = p1.*;
    L.top = old_top + 2;
    luaD_call(L, old_top, 0) catch |e| {
        if (e == error.Yield) return e;
        lua.unwindCis(L, old_ci);
        // Leave the error object on the stack (at L.top-1) so close_one_slot
        // can propagate a __close error to the next handler.
        return e;
    };
    L.top = saved_top;
}

pub fn luaT_callTM2(L: *lua.lua_State, f: lua.TValue, p1: *const lua.TValue, p2: *const lua.TValue) !void {
    const saved_top = L.top;
    savestate(L);
    if (lua.lua_checkstack(L, 3) == 0) return error.OutOfMemory;
    const old_top = L.top;
    const old_ci = L.ci;
    L.stack[old_top] = f;
    L.stack[old_top + 1] = p1.*;
    L.stack[old_top + 2] = p2.*;
    L.top = old_top + 3;
    luaD_call(L, old_top, 0) catch |e| {
        if (e == error.Yield) return e;
        lua.unwindCis(L, old_ci);
        // Leave the error object on the stack (at L.top-1) so close_one_slot
        // can propagate a __close error to the next handler.
        return e;
    };
    L.top = saved_top;
}

pub fn luaT_callTMres(L: *lua.lua_State, f: lua.TValue, p1: *const lua.TValue, p2: *const lua.TValue, res: usize) !lua.TValue {
    const saved_top = L.top;
    savestate(L);
    if (lua.lua_checkstack(L, 3) == 0) return error.OutOfMemory;
    const old_top = L.top;
    const old_ci = L.ci;
    L.stack[old_top] = f;
    L.stack[old_top + 1] = p1.*;
    L.stack[old_top + 2] = p2.*;
    L.top = old_top + 3;
    luaD_call(L, old_top, 1) catch |e| {
        if (e == error.Yield) return e;
        lua.unwindCis(L, old_ci);
        L.top = saved_top;
        return e;
    };
    const result = L.stack[old_top];
    if (res < L.stack.len) {
        L.stack[res] = result;
    }
    L.top = saved_top;
    return result;
}

pub fn luaT_trybinTM(L: *lua.lua_State, p1: *const lua.TValue, p2: *const lua.TValue, res: usize, event: TMS) !void {
    var tm = luaT_gettmbyobj(L, p1.*, event);
    if (tm == .nil) {
        tm = luaT_gettmbyobj(L, p2.*, event);
    }
    if (tm == .nil) {
        switch (event) {
            .BAND, .BOR, .BXOR, .SHL, .SHR, .BNOT => {
                if (p1.isNumberValue() and p2.isNumberValue()) {
                    return lua.luaG_tointerror(L, p1.*);
                } else {
                    return lua.luaG_opinterror(L, p1, p2, "perform bitwise operation on");
                }
            },
            .LEN => {
                return lua.luaG_typeerrorPtr(L, p1, "get length of");
            },
            .CONCAT => {
                return lua.luaG_concaterror(L, p1, p2);
            },
            else => {
                return lua.luaG_opinterror(L, p1, p2, "perform arithmetic on");
            },
        }
    }
    _ = try luaT_callTMres(L, tm, p1, p2, res);
}

pub fn luaT_callorderTM(L: *lua.lua_State, p1: *const lua.TValue, p2: *const lua.TValue, event: TMS) !bool {
    var tm = luaT_gettmbyobj(L, p1.*, event);
    if (tm == .nil) {
        tm = luaT_gettmbyobj(L, p2.*, event);
    }
    if (tm == .nil) {
        try lua.luaG_ordererror(L, p1.*, p2.*);
    }
    const res_val = try luaT_callTMres(L, tm, p1, p2, L.stack.len);
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
    // Cross-type numeric: integer vs number. Match luaV_equalobj: an integer
    // i equals a float f iff BOTH f == cast(float, i) AND cast(integer, f) == i
    // (so precision-losing conversions do not report false equality).
    if (t1 == .integer and t2 == .number) {
        const i = t1.integer;
        const f = t2.number;
        return f == @as(f64, @floatFromInt(i)) and i == @as(i64, @intFromFloat(f));
    }
    if (t1 == .number and t2 == .integer) {
        const f = t1.number;
        const i = t2.integer;
        return f == @as(f64, @floatFromInt(i)) and i == @as(i64, @intFromFloat(f));
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
                savestate(L);
                const res = try luaT_callTMres(L, tm_val, &t1, &t2, L.top);
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
                savestate(L);
                const res = try luaT_callTMres(L, tm_val, &t1, &t2, L.top);
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

// Cross-type ordering helpers, mirroring PUC-Rio's LTintfloat/LEintfloat/
// LTfloatint/LEfloatint in lvm.c. Comparing via f64 loses precision for
// integers that do not fit exactly in a float, so the reference compares as
// integers whenever possible and otherwise decides by the sign of the float.

// Cast a float to an integer if it is within [minint, 2^63); returns null
// otherwise (matches lua_numbertointeger: n >= MININTEGER && n < -MININTEGER).
fn numToInteger(n: f64) ?i64 {
    if (n >= -9223372036854775808.0 and n < 9223372036854775808.0) {
        return @intFromFloat(n);
    }
    return null;
}

// Whether the integer 'i' converts to a float without rounding.
const MAXINTFITSF: u64 = 1 << 53; // 2^MANT_DIG for f64
fn l_intfitsf(i: i64) bool {
    return (MAXINTFITSF +% @as(u64, @bitCast(i))) <= (2 * MAXINTFITSF);
}

fn LTintfloat(i: i64, f: f64) bool {
    if (l_intfitsf(i)) return @as(f64, @floatFromInt(i)) < f;
    if (numToInteger(f)) |fi| return i < fi;
    return f > 0;
}

fn LEintfloat(i: i64, f: f64) bool {
    if (l_intfitsf(i)) return @as(f64, @floatFromInt(i)) <= f;
    if (numToInteger(f)) |fi| return i <= fi;
    return f > 0;
}

fn LTfloatint(f: f64, i: i64) bool {
    if (l_intfitsf(i)) return f < @as(f64, @floatFromInt(i));
    if (numToInteger(f)) |fi| return fi < i;
    return f < 0;
}

fn LEfloatint(f: f64, i: i64) bool {
    if (l_intfitsf(i)) return f <= @as(f64, @floatFromInt(i));
    if (numToInteger(f)) |fi| return fi <= i;
    return f < 0;
}

pub fn luaT_lt(L: *lua.lua_State, t1: lua.TValue, t2: lua.TValue) !bool {
    // Same-type numeric
    if (t1 == .number and t2 == .number) {
        return t1.number < t2.number;
    }
    if (t1 == .integer and t2 == .integer) {
        return t1.integer < t2.integer;
    }
    // Cross-type numeric: compare without f64 precision loss.
    if (t1 == .number and t2 == .integer) {
        return LTfloatint(t1.number, t2.integer);
    }
    if (t1 == .integer and t2 == .number) {
        return LTintfloat(t1.integer, t2.number);
    }
    if (t1 == .string and t2 == .string) {
        return std.mem.order(u8, t1.string.?.s, t2.string.?.s) == .lt;
    }
    return try luaT_callorderTM(L, &t1, &t2, .LT);
}

pub fn luaT_le(L: *lua.lua_State, t1: lua.TValue, t2: lua.TValue) !bool {
    // Same-type numeric
    if (t1 == .number and t2 == .number) {
        return t1.number <= t2.number;
    }
    if (t1 == .integer and t2 == .integer) {
        return t1.integer <= t2.integer;
    }
    // Cross-type numeric: compare without f64 precision loss.
    if (t1 == .number and t2 == .integer) {
        return LEfloatint(t1.number, t2.integer);
    }
    if (t1 == .integer and t2 == .number) {
        return LEintfloat(t1.integer, t2.number);
    }
    if (t1 == .string and t2 == .string) {
        return std.mem.order(u8, t1.string.?.s, t2.string.?.s) != .gt;
    }
    return try luaT_callorderTM(L, &t1, &t2, .LE);
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
pub inline fn luaV_gettable(L: *lua.lua_State, t_ptr: *const lua.TValue, key: lua.TValue, res: usize) !void {
    const t = t_ptr.*;
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
                _ = try luaT_callTMres(L, tm, &current, &key, res);
                return;
            }
            // __index is a value — recurse into it
            current = tm;
        } else {
            // Not a table — try __index metamethod on this type
            const tm = luaT_gettmbyobj(L, current, .INDEX);
            if (tm == .nil) {
                if (loop == 0) {
                    return lua.luaG_typeerrorPtr(L, t_ptr, "index");
                } else {
                    return lua.luaG_typeerror(L, current, "index");
                }
            }
            if (tm == .function) {
                _ = try luaT_callTMres(L, tm, &current, &key, res);
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
pub inline fn luaV_settable(L: *lua.lua_State, t_ptr: *const lua.TValue, key: lua.TValue, val: lua.TValue) !void {
    const t = t_ptr.*;
    if (t == .table) {
        if (t.table) |tbl| {
            if (tbl.metatable == null) {
                ltable.set(tbl, key, val) catch |err| {
                    if (err == error.TableIndexIsNil) {
                        try lua.luaG_runerror(L, "table index is nil");
                    } else if (err == error.TableIndexIsNaN) {
                        try lua.luaG_runerror(L, "table index is NaN");
                    }
                    return err;
                };
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
                ltable.set(tbl, key, val) catch |err| {
                    if (err == error.TableIndexIsNil) {
                        try lua.luaG_runerror(L, "table index is nil");
                    } else if (err == error.TableIndexIsNaN) {
                        try lua.luaG_runerror(L, "table index is NaN");
                    }
                    return err;
                };
                return;
            }
            // Key absent — look for __newindex
            const tm = luaT_gettmbyobj(L, current, .NEWINDEX);
            if (tm == .nil) {
                // No __newindex: raw insert
                ltable.set(tbl, key, val) catch |err| {
                    if (err == error.TableIndexIsNil) {
                        try lua.luaG_runerror(L, "table index is nil");
                    } else if (err == error.TableIndexIsNaN) {
                        try lua.luaG_runerror(L, "table index is NaN");
                    }
                    return err;
                };
                return;
            }
            if (tm == .function) {
                try luaT_callTM(L, tm, &current, &key, &val);
                return;
            }
            // __newindex is a table — recurse
            current = tm;
        } else {
            const tm = luaT_gettmbyobj(L, current, .NEWINDEX);
            if (tm == .nil) {
                if (loop == 0) {
                    return lua.luaG_typeerrorPtr(L, t_ptr, "index");
                } else {
                    return lua.luaG_typeerror(L, current, "index");
                }
            }
            if (tm == .function) {
                try luaT_callTM(L, tm, &current, &key, &val);
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
    try ltable.set(t, nkey, lua.TValue{ .integer = @as(i64, @intCast(n)) });
    return t;
}

fn getnumargs(L: *lua.lua_State, ci: *lua.CallInfo, h: ?*lua.lua_Table) !i32 {
    if (h == null) return ci.nextraargs;
    const nkey = lua.TValue{ .string = try lstring.luaS_new(L, "n") };
    const res = ltable.get(h.?, nkey);
    if (res != .integer) {
        _ = lua.lua_pushstring(L, "vararg table has no proper 'n'");
        return lua.lua_error(L);
    }
    const val = res.integer;
    if (val < 0 or val > @as(i64, @intCast(std.math.maxInt(i32) / 2))) {
        _ = lua.lua_pushstring(L, "vararg table has no proper 'n'");
        return lua.lua_error(L);
    }
    return @intCast(val);
}

// lua/ltm.c luaT_adjustvarargs
pub fn luaT_adjustvarargs(L: *lua.lua_State, ci: *lua.CallInfo, cl: *lua.lua_LClosure) !void {
    const p = cl.p;
    const totalargs = @as(i32, @intCast(L.top)) - @as(i32, @intCast(ci.func)) - 1;
    const nfixparams: usize = p.numParams;
    const nextra = totalargs - @as(i32, @intCast(nfixparams));
    if ((p.flag & PF_VATAB) != 0) {
        const actual_nextra: usize = if (nextra > 0) @intCast(nextra) else 0;
        const t = try createVarargTable(L, ci.func + nfixparams + 1, actual_nextra);
        L.stack[ci.func + nfixparams + 1] = lua.TValue{ .table = t };
        // Clear stale stack values in the local-variable area (above the
        // last argument/vararg-table slot) so the GC does not try to mark
        // freed/dangling objects left over from previous frames.
        const local_start = ci.func + nfixparams + 2;
        L.top = ci.top;
        if (local_start < L.top) {
            @memset(L.stack[local_start..L.top], .{ .nil = {} });
        }
        lua.luaC_condGC(L);
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
        if (lua.lua_checkstack(L, @intCast(need - L.top)) == 0) return error.OutOfMemory;
    }
    const old_func_idx = ci.func;
    const new_func_idx = L.top;
    L.stack[new_func_idx] = L.stack[old_func_idx];
    L.top += 1;
    var curr_f = L.openupval;
    while (curr_f) |uv| {
        if (uv.v == &L.stack[old_func_idx]) {
            uv.v = &L.stack[new_func_idx];
        }
        curr_f = uv.next;
    }
    var i: usize = 1;
    while (i <= nfixparams) : (i += 1) {
        const old_idx = ci.func + i;
        const new_idx = L.top;
        L.stack[new_idx] = L.stack[old_idx];
        L.stack[old_idx] = .{ .nil = {} };
        var curr = L.openupval;
        while (curr) |uv| {
            if (uv.v == &L.stack[old_idx]) {
                uv.v = &L.stack[new_idx];
            }
            curr = uv.next;
        }
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
    const local_start = ci.func + nfixparams + 1;
    if (local_start < ci.top) {
        @memset(L.stack[local_start..ci.top], .{ .nil = {} });
    }
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
        try lua.growStack(L, need);
        L.top = where_idx + @as(usize, @intCast(nargs));
    } else {
        touse = if (nargs > wanted) wanted else nargs;
    }
    if (h == null) {
        var i: i32 = 0;
        const nextra: usize = if (ci.nextraargs > 0) @intCast(ci.nextraargs) else 0;
        while (i < touse) : (i += 1) {
            L.stack[where_idx + @as(usize, @intCast(i))] = L.stack[ci.func - nextra + @as(usize, @intCast(i))];
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
                L.stack[ra_idx] = lua.TValue{ .integer = @as(i64, @intCast(nextra)) };
                return;
            }
        }
    }
    L.stack[ra_idx] = .{ .nil = {} };
}
