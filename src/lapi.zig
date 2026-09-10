// $Id: lapi.zig $
//! The C API proper (port of lapi.c) - moved from lua.zig
//! (Refactor B6, pure move; re-exported by lua.zig for callers).

const std = @import("std");
const lua = @import("lua.zig");
const llimits = @import("llimits.zig");
const ltable = @import("ltable.zig");
const lstring = @import("lstring.zig");
const ltm = @import("ltm.zig");
const lvm = @import("lvm.zig");
const lundump = @import("lundump.zig");
const ldump = @import("ldump.zig");
const libm = @import("libm.zig");
const lparser = @import("lparser.zig");

pub fn idxPtr(L: *lua.lua_State, idx: i32) ?*lua.TValue {
    if (idx > 0) {
        // Positive indices are frame-relative: 1 = ci.base, 2 = ci.base+1, etc.
        // If there is no active call frame, treat as 1-based absolute index.
        const base: usize = if (L.ci) |ci| ci.base else 0;
        const u = base + @as(usize, @intCast(idx - 1));
        if (u < L.top) return &L.stack[u];
    } else if (idx == lua.LUA_REGISTRYINDEX) {
        return &lua.G(L).registry;
    } else if (idx < lua.LUA_REGISTRYINDEX) {
        // Upvalue pseudo-index: lua_upvalueindex(n) = lua.LUA_REGISTRYINDEX - n
        // Decode n-1 (0-based) from the index.
        const upn: usize = @intCast(lua.LUA_REGISTRYINDEX - idx - 1);
        if (L.ci) |ci| {
            const func_val = L.stack[ci.func];
            if (func_val == .function) {
                if (func_val.function) |cl| {
                    if (cl.* == .c and upn < cl.c.upvals.len) {
                        return &cl.c.upvals[upn];
                    }
                }
            }
        }
        return null;
    } else if (idx < 0) {
        const abs = @as(usize, @intCast(-idx));
        if (abs <= L.top) return &L.stack[L.top - abs];
    }
    return null;
}

pub fn toAbsoluteIndex(L: *lua.lua_State, idx: i32) usize {
    if (idx > 0) {
        const base: usize = if (L.ci) |ci| ci.base else 0;
        return base + @as(usize, @intCast(idx - 1));
    } else if (idx < 0) {
        const abs = @as(usize, @intCast(-idx));
        if (abs <= L.top) {
            return L.top - abs;
        }
        return 0;
    }
    return 0;
}

pub fn lua_absindex(L: *lua.lua_State, idx: i32) i32 {
    if (idx > 0 or idx <= lua.LUA_REGISTRYINDEX) return idx;
    return lua_gettop(L) + idx + 1;
}

pub fn lua_gettop(L: *lua.lua_State) i32 {
    const base: usize = if (L.ci) |ci| ci.base else 0;
    return @as(i32, @intCast(L.top - base));
}

pub fn lua_settop(L: *lua.lua_State, idx: i32) void {
    const base: usize = if (L.ci) |ci| ci.base else 0;
    if (idx >= 0) {
        const n = base + @as(usize, @intCast(idx));
        if (n < L.top) {
            @memset(L.stack[n..L.top], lua.TValue{ .nil = {} });
        } else if (n > L.top) {
            @memset(L.stack[L.top..n], lua.TValue{ .nil = {} });
        }
        L.top = n;
    } else {
        const abs_top = @as(i32, @intCast(L.top));
        const n = abs_top + 1 + idx;
        if (n >= @as(i32, @intCast(base))) {
            const un = @as(usize, @intCast(n));
            if (un < L.top) {
                @memset(L.stack[un..L.top], lua.TValue{ .nil = {} });
            }
            L.top = un;
        }
    }
}

pub fn lua_pushvalue(L: *lua.lua_State, idx: i32) void {
    lua.growStack(L, L.top + 1) catch return;
    const src = lua.idxPtr(L, idx) orelse return;
    L.stack[L.top] = src.*;
    L.top += 1;
}

pub fn lua_rotate(L: *lua.lua_State, idx: i32, n: i32) void {
    const base: usize = if (L.ci) |ci| ci.base else 0;
    const abs_idx = lua.toAbsoluteIndex(L, idx);
    if (abs_idx < base or abs_idx >= L.top) return;
    const len: i32 = @as(i32, @intCast(L.top - abs_idx));
    if (len <= 0) return;
    const rot: usize = @intCast(@mod(@mod(n, len) + len, len));
    if (rot == 0) return;
    const top_idx: usize = L.top - 1;
    // Reverse full range
    var i: usize = abs_idx;
    var j: usize = top_idx;
    while (i < j) : ({
        i += 1;
        j -= 1;
    }) {
        const t = L.stack[i];
        L.stack[i] = L.stack[j];
        L.stack[j] = t;
    }
    // Reverse first rot elements
    i = abs_idx;
    j = abs_idx + rot - 1;
    while (i < j) : ({
        i += 1;
        j -= 1;
    }) {
        const t = L.stack[i];
        L.stack[i] = L.stack[j];
        L.stack[j] = t;
    }
    // Reverse remaining elements
    i = abs_idx + rot;
    j = top_idx;
    while (i < j) : ({
        i += 1;
        j -= 1;
    }) {
        const t = L.stack[i];
        L.stack[i] = L.stack[j];
        L.stack[j] = t;
    }
}

pub inline fn lua_insert(L: *lua.lua_State, idx: i32) void {
    lua_rotate(L, idx, 1);
}

pub inline fn lua_remove(L: *lua.lua_State, idx: i32) void {
    lua_rotate(L, idx, -1);
    L.top -= 1;
}

pub inline fn lua_newtable(L: *lua.lua_State) void {
    lua_createtable(L, 0, 0);
}

pub fn lua_copy(L: *lua.lua_State, fromidx: i32, toidx: i32) void {
    const src = lua.idxPtr(L, fromidx) orelse return;
    const dst = lua.idxPtr(L, toidx) orelse return;
    dst.* = src.*;
}




pub fn stackAt(L: *lua.lua_State, idx: i32) lua.TValue {
    const ptr = lua.idxPtr(L, idx) orelse return lua.TValue{ .nil = {} };
    return ptr.*;
}

pub inline fn lua_isnoneornil(L: *lua.lua_State, idx: i32) bool {
    return lua_type(L, idx) <= 0;
}

// ===================================================================
// H.7 — Convenience macros (port of lua.h macro definitions)
// ===================================================================

/// Register a C function as a global. Equivalent to
/// `lua_pushcfunction(L, f); lua_setglobal(L, n)`.
pub inline fn lua_register(L: *lua.lua_State, name: []const u8, func: lua.lua_CFunction) !void {
    lua_pushcfunction(L, func);
    try lua_setglobal(L, name);
}

/// Push the global environment table onto the stack. Equivalent to
/// `lua_rawgeti(L, lua.LUA_REGISTRYINDEX, lua.LUA_RIDX_GLOBALS)`.
pub inline fn lua_pushglobaltable(L: *lua.lua_State) void {
    _ = lua_rawgeti(L, lua.LUA_REGISTRYINDEX, llimits.LUA_RIDX_GLOBALS);
}

/// Push a string literal (or any `[]const u8`) onto the stack.
pub inline fn lua_pushliteral(L: *lua.lua_State, s: []const u8) ?[]const u8 {
    return lua_pushstring(L, s);
}

/// Return true if the value at `idx` is a function.
pub inline fn lua_isfunction(L: *lua.lua_State, n: i32) bool {
    return lua_type(L, n) == lua.LUA_TFUNCTION;
}

/// Return true if the value at `idx` is a thread (coroutine).
pub inline fn lua_isthread(L: *lua.lua_State, n: i32) bool {
    return lua_type(L, n) == lua.LUA_TTHREAD;
}

/// Return true if the value at `idx` is light userdata.
pub inline fn lua_islightuserdata(L: *lua.lua_State, n: i32) bool {
    return lua_type(L, n) == lua.LUA_TLIGHTUSERDATA;
}

pub fn lua_isnone(L: *lua.lua_State, idx: i32) i32 {
    return if (lua_type(L, idx) == lua.LUA_TNONE) 1 else 0;
}

pub fn lua_isnil(L: *lua.lua_State, idx: i32) i32 {
    return if (lua_type(L, idx) == lua.LUA_TNIL) 1 else 0;
}

pub fn lua_isboolean(L: *lua.lua_State, idx: i32) i32 {
    return if (lua_type(L, idx) == lua.LUA_TBOOLEAN) 1 else 0;
}

pub fn lua_istable(L: *lua.lua_State, idx: i32) i32 {
    return if (lua_type(L, idx) == lua.LUA_TTABLE) 1 else 0;
}

pub fn lua_isnumber(L: *lua.lua_State, idx: i32) i32 {
    const v = lua.stackAt(L, idx);
    return switch (v) {
        .number => 1,
        .integer => 1,
        else => 0,
    };
}

pub fn lua_isstring(L: *lua.lua_State, idx: i32) i32 {
    const v = lua.stackAt(L, idx);
    return switch (v) {
        .string => 1,
        .number => 1,
        .integer => 1,
        else => 0,
    };
}

pub fn lua_iscfunction(L: *lua.lua_State, idx: i32) i32 {
    const v = lua.stackAt(L, idx);
    if (v != .function) return 0;
    const cl = v.function orelse return 0;
    return switch (cl.*) {
        .c => 1,
        .lua => 0,
    };
}

pub fn lua_isinteger(L: *lua.lua_State, idx: i32) i32 {
    const v = lua.stackAt(L, idx);
    return switch (v) {
        .integer => 1,
        else => 0,
    };
}

pub fn lua_isuserdata(L: *lua.lua_State, idx: i32) i32 {
    const v = lua.stackAt(L, idx);
    return switch (v) {
        .userdata => 1,
        .lightud => 1,
        else => 0,
    };
}

pub fn lua_type(L: *lua.lua_State, idx: i32) i32 {
    // Match the reference lua_type: an invalid (out-of-range) index yields
    // lua.LUA_TNONE, not lua.LUA_TNIL. This is what luaL_checkany/checktype/checknumber
    // rely on to validate argument presence.
    const ptr = lua.idxPtr(L, idx) orelse return lua.LUA_TNONE;
    return ptr.typ();
}

pub fn lua_typename(tp: i32) []const u8 {
    return switch (tp) {
        lua.LUA_TNONE => "no value",
        lua.LUA_TNIL => "nil",
        lua.LUA_TBOOLEAN => "boolean",
        lua.LUA_TLIGHTUSERDATA => "light userdata",
        lua.LUA_TNUMBER => "number",
        lua.LUA_TSTRING => "string",
        lua.LUA_TTABLE => "table",
        lua.LUA_TFUNCTION => "function",
        lua.LUA_TUSERDATA => "userdata",
        lua.LUA_TTHREAD => "thread",
        else => "unknown",
    };
}

pub fn lua_tonumberx(L: *lua.lua_State, idx: i32, isnum: ?*i32) ?f64 {
    const v = lua.stackAt(L, idx);
    const num = lua.toNumeric(v);
    if (num) |val| {
        if (isnum) |p| p.* = 1;
        return switch (val) {
            .integer => |n| @as(f64, @floatFromInt(n)),
            .number => |n| n,
            else => unreachable,
        };
    }
    if (isnum) |p| p.* = 0;
    return null;
}

pub fn lua_tointegerx(L: *lua.lua_State, idx: i32, isnum: ?*i32) ?i64 {
    const v = lua.stackAt(L, idx);
    const num = lua.toNumeric(v);
    const min_f64 = @as(f64, -9223372036854775808.0);
    const max_exclusive_f64 = @as(f64, 9223372036854775808.0);
    if (num) |val| {
        switch (val) {
            .integer => |n| {
                if (isnum) |p| p.* = 1;
                return n;
            },
            .number => |n| {
                const f = @floor(n);
                if (n == f and f >= min_f64 and f < max_exclusive_f64) {
                    if (isnum) |p| p.* = 1;
                    return @as(i64, @intFromFloat(f));
                }
            },
            else => unreachable,
        }
    }
    if (isnum) |p| p.* = 0;
    return null;
}

pub fn lua_tonumber(L: *lua.lua_State, idx: i32) ?f64 {
    return lua_tonumberx(L, idx, null);
}

pub fn lua_tointeger(L: *lua.lua_State, idx: i32) ?i64 {
    return lua_tointegerx(L, idx, null);
}

pub fn lua_toboolean(L: *lua.lua_State, idx: i32) i32 {
    const v = lua.stackAt(L, idx);
    return if (v.toBoolean()) 1 else 0;
}

pub fn lua_tolstring(L: *lua.lua_State, idx: i32, len: ?*usize) ?[]const u8 {
    const ptr = lua.idxPtr(L, idx) orelse return null;
    switch (ptr.*) {
        .string => |s| {
            if (len) |p| p.* = s.?.len;
            return s.?.s;
        },
        .integer, .number => {
            var buf: [128]u8 = undefined;
            const s = lua.luaO_tostringbuff(ptr.*, &buf);
            const ts = lstring.luaS_new(L, s) catch return null;
            ptr.* = lua.TValue{ .string = ts };
            lua.luaC_condGC(L);
            if (len) |p| p.* = ts.len;
            return ts.s;
        },
        else => return null,
    }
}

pub fn lua_rawlen(L: *lua.lua_State, idx: i32) usize {
    const v = lua.stackAt(L, idx);
    return switch (v) {
        .string => |s| s.?.len,
        .table => |t| {
            if (t) |tp| return ltable.getn(tp);
            return 0;
        },
        else => 0,
    };
}

pub fn lua_tocfunction(L: *lua.lua_State, idx: i32) lua.lua_CFunction {
    const v = lua.stackAt(L, idx);
    return switch (v) {
        .function => |f| if (f) |cl| switch (cl.*) {
            .c => |cc| cc.f,
            else => undefined,
        } else undefined,
        else => undefined,
    };
}

pub fn lua_touserdata(L: *lua.lua_State, idx: i32) ?*anyopaque {
    const v = lua.stackAt(L, idx);
    return switch (v) {
        .userdata => |u| if (u) |p| @as(*anyopaque, @ptrCast(p.data.ptr)) else null,
        .lightud => |u| u,
        else => null,
    };
}

pub fn lua_tothread(L: *lua.lua_State, idx: i32) ?*lua.lua_State {
    const v = lua.stackAt(L, idx);
    return switch (v) {
        .thread => |t| t,
        else => null,
    };
}

pub fn lua_topointer(L: *lua.lua_State, idx: i32) ?*anyopaque {
    const v = lua.stackAt(L, idx);
    return switch (v) {
        .string => |s| if (s) |p| @as(*anyopaque, @ptrCast(p)) else null,
        .table => |t| if (t) |p| @as(*anyopaque, @ptrCast(p)) else null,
        .function => |f| if (f) |p| @as(*anyopaque, @ptrCast(p)) else null,
        .userdata => |u| if (u) |p| @as(*anyopaque, @ptrCast(p)) else null,
        .lightud => |u| u,
        .thread => |t| if (t) |p| @as(*anyopaque, @ptrCast(p)) else null,
        else => null,
    };
}

pub fn numMod(a: f64, b: f64) f64 {
    var m = libm.getLibm().fmod(a, b);
    if (if (m > 0) b < 0 else (m < 0 and b > 0)) {
        m += b;
    }
    return m;
}

pub fn luaV_shift(x: i64, s: i64) i64 {
    const ux = @as(u64, @bitCast(x));
    const nbits: i64 = 64;
    if (s < 0) {
        // Arithmetic shift right by -s.
        if (s <= -nbits) return 0;
        return @as(i64, @bitCast(ux >> @as(u6, @intCast(-s))));
    }
    // Logical shift left by s.
    if (s >= nbits) return 0;
    return @as(i64, @bitCast(ux << @as(u6, @intCast(s))));
}

/// Try to convert a lua.TValue to a numeric lua.TValue (integer or float).
/// For strings, attempts number parsing. Returns null if not numeric.

pub fn lua_arith(L: *lua.lua_State, op: i32) !void {
    if (op < 0 or op > 13) return;
    const is_unary = (op == lua.LUA_OPUNM or op == lua.LUA_OPBNOT);
    if (is_unary) {
        if (L.top < 1) return;
        const p1 = L.stack[L.top - 1];
        if (p1 == .integer) {
            const result = switch (op) {
                lua.LUA_OPUNM => @as(lua.TValue, .{ .integer = 0 -% p1.integer }),
                lua.LUA_OPBNOT => @as(lua.TValue, .{ .integer = ~p1.integer }),
                else => unreachable,
            };
            L.stack[L.top - 1] = result;
        } else if (p1 == .number) {
            const result = switch (op) {
                lua.LUA_OPUNM => @as(lua.TValue, .{ .number = -p1.number }),
                lua.LUA_OPBNOT => @as(lua.TValue, .{ .number = @floatFromInt(~@as(i64, @intFromFloat(p1.number))) }),
                else => unreachable,
            };
            L.stack[L.top - 1] = result;
        } else {
            const event: ltm.TMS = switch (op) {
                lua.LUA_OPUNM => .UNM,
                lua.LUA_OPBNOT => .BNOT,
                else => unreachable,
            };
            try ltm.luaT_trybinTM(L, &p1, &p1, L.top - 1, event);
        }
    } else {
        if (L.top < 2) return;
        const p1 = L.stack[L.top - 2];
        const p2 = L.stack[L.top - 1];
        const num1 = lua.toNumeric(p1);
        const num2 = lua.toNumeric(p2);
        if (num1) |n1| {
            if (num2) |n2| {
                if (n1 == .integer and n2 == .integer) {
                    const result = switch (op) {
                        lua.LUA_OPADD => @as(lua.TValue, .{ .integer = n1.integer +% n2.integer }),
                        lua.LUA_OPSUB => @as(lua.TValue, .{ .integer = n1.integer -% n2.integer }),
                        lua.LUA_OPMUL => @as(lua.TValue, .{ .integer = n1.integer *% n2.integer }),
                        lua.LUA_OPMOD => blk: {
                            const ib = n1.integer;
                            const ic = n2.integer;
                            const r = if (ic == 0 or ic == -1) @as(i64, 0) else @rem(ib, ic);
                            break :blk lua.TValue{ .integer = if (r != 0 and (r ^ ic) < 0) r +% ic else r };
                        },
                        lua.LUA_OPPOW => @as(lua.TValue, .{ .number = libm.getLibm().pow(@as(f64, @floatFromInt(n1.integer)), @as(f64, @floatFromInt(n2.integer))) }),
                        lua.LUA_OPDIV => @as(lua.TValue, .{ .number = @as(f64, @floatFromInt(n1.integer)) / @as(f64, @floatFromInt(n2.integer)) }),
                        lua.LUA_OPIDIV => blk: {
                            const ib = n1.integer;
                            const ic = n2.integer;
                            // Handle minint / -1 (overflows as wrapping) and /0
                            const q: i64 = if (ic == 0) 0 else if (ic == -1) 0 -% ib else @divTrunc(ib, ic);
                            const r: i64 = if (ic == 0 or ic == -1) 0 else @rem(ib, ic);
                            break :blk lua.TValue{ .integer = if (r == 0 or (ib >= 0) == (ic >= 0)) q else q - 1 };
                        },
                        lua.LUA_OPBAND => @as(lua.TValue, .{ .integer = n1.integer & n2.integer }),
                        lua.LUA_OPBOR => @as(lua.TValue, .{ .integer = n1.integer | n2.integer }),
                        lua.LUA_OPBXOR => @as(lua.TValue, .{ .integer = n1.integer ^ n2.integer }),
                        lua.LUA_OPSHL => @as(lua.TValue, .{ .integer = lua.luaV_shift(n1.integer, n2.integer) }),
                        lua.LUA_OPSHR => @as(lua.TValue, .{ .integer = lua.luaV_shift(n1.integer, -%n2.integer) }),
                        else => unreachable,
                    };
                    L.top -= 1;
                    L.stack[L.top - 1] = result;
                } else if (n1.isNumberValue() and n2.isNumberValue()) {
                    const f1 = n1.toFloat();
                    const f2 = n2.toFloat();
                    const result: f64 = switch (op) {
                        lua.LUA_OPADD => f1 + f2,
                        lua.LUA_OPSUB => f1 - f2,
                        lua.LUA_OPMUL => f1 * f2,
                        lua.LUA_OPMOD => lua.numMod(f1, f2),
                        lua.LUA_OPPOW => libm.getLibm().pow(f1, f2),
                        lua.LUA_OPDIV => f1 / f2,
                        lua.LUA_OPIDIV => @floor(f1 / f2),
                        lua.LUA_OPBAND => blk: {
                            const ival1 = n1.toIntegerExactOpt() orelse return lua.luaG_runerror(L, "number has no integer representation");
                            const ival2 = n2.toIntegerExactOpt() orelse return lua.luaG_runerror(L, "number has no integer representation");
                            break :blk @floatFromInt(ival1 & ival2);
                        },
                        lua.LUA_OPBOR => blk: {
                            const ival1 = n1.toIntegerExactOpt() orelse return lua.luaG_runerror(L, "number has no integer representation");
                            const ival2 = n2.toIntegerExactOpt() orelse return lua.luaG_runerror(L, "number has no integer representation");
                            break :blk @floatFromInt(ival1 | ival2);
                        },
                        lua.LUA_OPBXOR => blk: {
                            const ival1 = n1.toIntegerExactOpt() orelse return lua.luaG_runerror(L, "number has no integer representation");
                            const ival2 = n2.toIntegerExactOpt() orelse return lua.luaG_runerror(L, "number has no integer representation");
                            break :blk @floatFromInt(ival1 ^ ival2);
                        },
                        lua.LUA_OPSHL => blk: {
                            const ival1 = n1.toIntegerExactOpt() orelse return lua.luaG_runerror(L, "number has no integer representation");
                            const ival2 = n2.toIntegerExactOpt() orelse return lua.luaG_runerror(L, "number has no integer representation");
                            break :blk @floatFromInt(lua.luaV_shift(ival1, ival2));
                        },
                        lua.LUA_OPSHR => blk: {
                            const ival1 = n1.toIntegerExactOpt() orelse return lua.luaG_runerror(L, "number has no integer representation");
                            const ival2 = n2.toIntegerExactOpt() orelse return lua.luaG_runerror(L, "number has no integer representation");
                            break :blk @floatFromInt(lua.luaV_shift(ival1, -%ival2));
                        },
                        else => unreachable,
                    };
                    L.top -= 1;
                    L.stack[L.top - 1] = lua.TValue{ .number = result };
                }
            }
        } else {
            const event: ltm.TMS = switch (op) {
                lua.LUA_OPADD => .ADD,
                lua.LUA_OPSUB => .SUB,
                lua.LUA_OPMUL => .MUL,
                lua.LUA_OPMOD => .MOD,
                lua.LUA_OPPOW => .POW,
                lua.LUA_OPDIV => .DIV,
                lua.LUA_OPIDIV => .IDIV,
                lua.LUA_OPBAND => .BAND,
                lua.LUA_OPBOR => .BOR,
                lua.LUA_OPBXOR => .BXOR,
                lua.LUA_OPSHL => .SHL,
                lua.LUA_OPSHR => .SHR,
                else => unreachable,
            };
            try ltm.luaT_trybinTM(L, &p1, &p2, L.top - 2, event);
            L.top -= 1;
        }
    }
}


pub fn lua_rawequal(L: *lua.lua_State, idx1: i32, idx2: i32) i32 {
    const a = lua.stackAt(L, idx1);
    const b = lua.stackAt(L, idx2);
    return if (lua.luaV_rawequalobj(a, b)) 1 else 0;
}

pub fn lua_compare(L: *lua.lua_State, idx1: i32, idx2: i32, op: i32) i32 {
    const a = lua.stackAt(L, idx1);
    const b = lua.stackAt(L, idx2);
    const res = switch (op) {
        lua.LUA_OPEQ => ltm.luaT_equalobj(L, a, b) catch false,
        lua.LUA_OPLT => ltm.luaT_lt(L, a, b) catch false,
        lua.LUA_OPLE => ltm.luaT_le(L, a, b) catch false,
        else => false,
    };
    return if (res) 1 else 0;
}

pub fn lua_pushnil(L: *lua.lua_State) void {
    if (L.top + 1 >= L.stack.len) _ = lua.lua_checkstack(L, 2);
    L.stack[L.top] = lua.TValue{ .nil = {} };
    L.top += 1;
}

pub fn lua_pushnumber(L: *lua.lua_State, n: lua.lua_Number) void {
    if (L.top + 1 >= L.stack.len) _ = lua.lua_checkstack(L, 2);
    L.stack[L.top] = lua.TValue{ .number = n };
    L.top += 1;
}

pub fn lua_pushinteger(L: *lua.lua_State, n: lua.lua_Integer) void {
    if (L.top + 1 >= L.stack.len) _ = lua.lua_checkstack(L, 2);
    L.stack[L.top] = lua.TValue{ .integer = n };
    L.top += 1;
}

pub fn lua_pushlstring(L: *lua.lua_State, s: []const u8, len: usize) ?[]const u8 {
    if (L.top >= L.stack.len) {
        if (lua.lua_checkstack(L, 1) == 0) return null;
    }
    const ts = lstring.luaS_new(L, s[0..len]) catch return null;
    L.stack[L.top] = lua.TValue{ .string = ts };
    L.top += 1;
    lua.luaC_condGC(L);
    return ts.s;
}

pub fn lua_pushstring(L: *lua.lua_State, s: []const u8) ?[]const u8 {
    return lua_pushlstring(L, s, s.len);
}

/// Lua 5.5 `lua_pushexternalstring`: push a string whose bytes are owned by a
/// caller-provided allocator rather than copied by Lua. `s[0..len]` is the
/// string content (the C contract requires `s[len] == 0`); `falloc`/`ud` are
/// the external `lua.lua_Alloc` and its user data. When `falloc` is non-null
/// (LSTRMEM) Lua takes ownership of the bytes and frees them via `falloc` when
/// the string is collected; when `falloc` is null (LSTRFIX) the bytes are
/// static and never freed. External strings are never interned, so equal
/// content yields distinct `lua.lua_TString` objects. Returns the string content
/// pointer, or `null` on out-of-memory (in which case an LSTRMEM external
/// buffer is freed back to `falloc`).
pub fn lua_pushexternalstring(
    L: *lua.lua_State,
    s: []const u8,
    len: usize,
    falloc: ?lua.lua_Alloc,
    ud: ?*anyopaque,
) ?[]const u8 {
    lua.growStack(L, L.top + 1) catch {
        if (falloc) |f| _ = f(ud, @constCast(s.ptr), len + 1, 0);
        return null;
    };
    const g = lua.G(L);
    const ts = L.allocator.create(lua.lua_TString) catch {
        // Could not allocate the header; an LSTRMEM buffer we were meant to
        // own must be returned to its allocator.
        if (falloc) |f| _ = f(ud, @constCast(s.ptr), len + 1, 0);
        return null;
    };
    ts.* = .{
        .s = s[0..len],
        .len = len,
        // External strings share a constant hash (the C reference uses the
        // global seed), so they never collide with interned (content-hashed)
        // strings of equal content.
        .hash = @as(u32, @truncate(g.seed)),
        .externally_owned = true,
        .falloc = falloc,
        .ud = ud,
    };
    lua.registerGC(L, ts) catch {
        if (falloc) |f| _ = f(ud, @constCast(ts.s.ptr), ts.len + 1, 0);
        L.allocator.destroy(ts);
        return null;
    };
    L.stack[L.top] = lua.TValue{ .string = ts };
    L.top += 1;
    lua.luaC_condGC(L);
    return ts.s;
}

pub fn lua_pushvfstring(L: *lua.lua_State, fmt: []const u8, argp: ?*anyopaque) ?[]const u8 {
    _ = argp;
    const s = lua_pushstring(L, fmt);
    lua.luaC_condGC(L);
    return s;
}

pub fn lua_pushfstring(L: *lua.lua_State, fmt: []const u8) ?[]const u8 {
    const s = lua_pushstring(L, fmt);
    lua.luaC_condGC(L);
    return s;
}

pub fn lua_pushcclosure(L: *lua.lua_State, cfunc: lua.lua_CFunction, n: i32) void {
    if (n == 0) {
        // No upvalues: reuse the cached closure for this C function (the
        // reference pushes a light function value here, which does not
        // allocate either). Root the closure in the registry so it survives.
        if (L.l_G) |g| {
            if (g.cfunc_cache.get(cfunc)) |cached| {
                lua.growStack(L, L.top + 1) catch return;
                L.stack[L.top] = lua.TValue{ .function = cached };
                L.top += 1;
                lua.luaC_condGC(L);
                return;
            }
        }
        const cc = L.allocator.create(lua.lua_CClosure) catch return;
        cc.* = .{ .f = cfunc, .upvals = &.{} };
        const cl = L.allocator.create(lua.lua_Closure) catch {
            L.allocator.destroy(cc);
            return;
        };
        cl.* = lua.lua_Closure{ .c = cc };
        lua.registerGC(L, cl) catch {
            L.allocator.destroy(cc);
            L.allocator.destroy(cl);
            return;
        };
        // Root in the registry: registry[cfunc-as-lightuserdata] = closure.
        if (L.l_G) |g| {
            const reg = g.registry.table orelse return;
            ltable.set(reg, lua.TValue{ .lightud = @ptrCast(@constCast(cfunc)) }, lua.TValue{ .function = cl }) catch {};
            g.cfunc_cache.put(L.allocator, cfunc, cl) catch {};
        }
        lua.growStack(L, L.top + 1) catch return;
        L.stack[L.top] = lua.TValue{ .function = cl };
        L.top += 1;
        lua.luaC_condGC(L);
        return;
    }
    const upvals = L.allocator.alloc(lua.TValue, @intCast(n)) catch return;
    var i: usize = 0;
    while (i < @as(usize, @intCast(n))) : (i += 1) {
        const stack_idx = L.top - @as(usize, @intCast(n)) + i;
        upvals[i] = L.stack[stack_idx];
    }
    L.top -= @as(usize, @intCast(n));

    const cc = L.allocator.create(lua.lua_CClosure) catch {
        L.allocator.free(upvals);
        return;
    };
    cc.* = .{ .f = cfunc, .upvals = upvals };
    const cl = L.allocator.create(lua.lua_Closure) catch {
        L.allocator.free(upvals);
        L.allocator.destroy(cc);
        return;
    };
    cl.* = lua.lua_Closure{ .c = cc };
    lua.registerGC(L, cl) catch {
        L.allocator.free(upvals);
        L.allocator.destroy(cc);
        L.allocator.destroy(cl);
        return;
    };
    L.stack[L.top] = lua.TValue{ .function = cl };
    L.top += 1;
    lua.luaC_condGC(L);
}

/// Shorthand: push a C function with no upvalues.
pub fn lua_pushcfunction(L: *lua.lua_State, cfunc: lua.lua_CFunction) void {
    lua_pushcclosure(L, cfunc, 0);
}

/// Convert an upvalue index (1-based) to a pseudo-index.
/// Mirrors the C macro: #define lua_upvalueindex(i) (lua.LUA_REGISTRYINDEX - (i))
pub fn lua_upvalueindex(i: i32) i32 {
    return lua.LUA_REGISTRYINDEX - i;
}

/// Get the value of upvalue `n` (1-based) of the C closure at the top of the
/// current call frame.  Returns nil if `n` is out of range.
pub fn lua_getupvalue(L: *lua.lua_State, funcindex: i32, n: i32) ?[]const u8 {
    if (funcindex <= lua.LUA_REGISTRYINDEX) return null;
    const abs = lua.toAbsoluteIndex(L, funcindex);
    if (abs >= L.top) return null;
    const func_val = L.stack[abs];
    if (func_val != .function) return null;
    const cl = func_val.function orelse return null;

    const upn = n - 1;
    if (upn < 0) return null;
    switch (cl.*) {
        .c => |ccl| {
            if (upn >= ccl.upvals.len) return null;
            L.stack[L.top] = ccl.upvals[@intCast(upn)];
            L.top += 1;
            return ""; // unnamed
        },
        .lua => |lcl| {
            if (upn >= lcl.upvals.len) return null;
            const uv = lcl.upvals[@intCast(upn)] orelse return null;
            L.stack[L.top] = uv.v.*;
            L.top += 1;
            if (upn < lcl.p.upvalues.len) {
                if (lcl.p.upvalues[@intCast(upn)].name) |name_ts| {
                    return name_ts.s;
                }
            }
            return "(no name)";
        },
    }
}

pub fn lua_setupvalue(L: *lua.lua_State, funcindex: i32, n: i32) ?[]const u8 {
    if (L.top == 0) return null;
    if (funcindex <= lua.LUA_REGISTRYINDEX) return null;
    const abs = lua.toAbsoluteIndex(L, funcindex);
    if (abs >= L.top) return null;
    const func_val = L.stack[abs];
    if (func_val != .function) return null;
    const cl = func_val.function orelse return null;

    const upn = n - 1;
    if (upn < 0) return null;
    switch (cl.*) {
        .c => |ccl| {
            if (upn >= ccl.upvals.len) return null;
            ccl.upvals[@intCast(upn)] = L.stack[L.top - 1];
            L.top -= 1;
            return ""; // unnamed
        },
        .lua => |lcl| {
            if (upn >= lcl.upvals.len) return null;
            const uv = lcl.upvals[@intCast(upn)] orelse return null;
            uv.v.* = L.stack[L.top - 1];
            L.top -= 1;
            if (upn < lcl.p.upvalues.len) {
                if (lcl.p.upvalues[@intCast(upn)].name) |name_ts| {
                    return name_ts.s;
                }
            }
            return "(no name)";
        },
    }
}

pub fn lua_upvalueid(L: *lua.lua_State, fidx: i32, n: i32) ?*anyopaque {
    if (fidx <= lua.LUA_REGISTRYINDEX) return null;
    const abs = lua.toAbsoluteIndex(L, fidx);
    if (abs >= L.top) return null;
    const func_val = L.stack[abs];
    if (func_val != .function) return null;
    const cl = func_val.function orelse return null;

    const upn = n - 1;
    if (upn < 0) return null;
    switch (cl.*) {
        .c => |ccl| {
            if (upn >= ccl.upvals.len) return null;
            return @ptrCast(&ccl.upvals[@intCast(upn)]);
        },
        .lua => |lcl| {
            if (upn >= lcl.upvals.len) return null;
            return @ptrCast(lcl.upvals[@intCast(upn)] orelse return null);
        },
    }
}

pub fn lua_upvaluejoin(L: *lua.lua_State, fidx1: i32, n1: i32, fidx2: i32, n2: i32) void {
    if (fidx1 <= lua.LUA_REGISTRYINDEX or fidx2 <= lua.LUA_REGISTRYINDEX) return;
    const abs1 = lua.toAbsoluteIndex(L, fidx1);
    const abs2 = lua.toAbsoluteIndex(L, fidx2);
    if (abs1 >= L.top or abs2 >= L.top) return;

    const func_val1 = L.stack[abs1];
    const func_val2 = L.stack[abs2];
    if (func_val1 != .function or func_val2 != .function) return;

    const cl1 = func_val1.function orelse return;
    const cl2 = func_val2.function orelse return;

    const upn1 = n1 - 1;
    const upn2 = n2 - 1;
    if (upn1 < 0 or upn2 < 0) return;

    switch (cl1.*) {
        .lua => |lcl1| {
            switch (cl2.*) {
                .lua => |lcl2| {
                    if (upn1 < lcl1.upvals.len and upn2 < lcl2.upvals.len) {
                        lcl1.upvals[@intCast(upn1)] = lcl2.upvals[@intCast(upn2)];
                    }
                },
                else => {},
            }
        },
        else => {},
    }
}

pub fn lua_pushboolean(L: *lua.lua_State, b: i32) void {
    if (L.top + 1 >= L.stack.len) _ = lua.lua_checkstack(L, 2);
    L.stack[L.top] = lua.TValue{ .boolean = b != 0 };
    L.top += 1;
}

pub fn lua_pushlightuserdata(L: *lua.lua_State, p: ?*anyopaque) void {
    if (L.top + 1 >= L.stack.len) _ = lua.lua_checkstack(L, 2);
    L.stack[L.top] = lua.TValue{ .lightud = p };
    L.top += 1;
}


/// Deprecated alias for `lua.lua_closethread(L, null)`.
pub inline fn lua_resetthread(L: *lua.lua_State) i32 {
    return lua.lua_closethread(L, null);
}


pub fn lua_pushthread(L: *lua.lua_State) i32 {
    L.stack[L.top] = lua.TValue{ .thread = L };
    L.top += 1;
    const g = lua.G(L);
    return if (g.mainthread == L) 1 else 0;
}

pub fn lua_pop(L: *lua.lua_State, n: i32) void {
    if (n > 0) {
        const nn = @as(usize, @intCast(n));
        if (nn <= L.top) {
            L.top -= nn;
        }
    }
}

pub fn lua_replace(L: *lua.lua_State, idx: i32) void {
    const abs = lua.toAbsoluteIndex(L, idx);
    if (abs < L.top) {
        L.stack[abs] = L.stack[L.top - 1];
        L.top -= 1;
    }
}

pub fn lua_getglobal(L: *lua.lua_State, name: []const u8) i32 {
    const g = lua.G(L);
    // Extract the registry table from g.registry (a lua.TValue)
    const registry: *lua.lua_Table = switch (g.registry) {
        .table => |t_opt| t_opt orelse {
            lua_pushnil(L);
            return lua.LUA_TNIL;
        },
        else => {
            lua_pushnil(L);
            return lua.LUA_TNIL;
        },
    };
    // lua.LUA_RIDX_GLOBALS == 2: globals table stored at registry[2]
    const globals_val = ltable.getInt(registry, 2);
    const globals: *lua.lua_Table = switch (globals_val) {
        .table => |t_opt| t_opt orelse {
            lua_pushnil(L);
            return lua.LUA_TNIL;
        },
        else => {
            lua_pushnil(L);
            return lua.LUA_TNIL;
        },
    };
    const key = lua.TValue{ .string = lstring.luaS_new(L, name) catch null };
    const val = ltable.get(globals, key);
    L.stack[L.top] = val;
    L.top += 1;
    return val.typ();
}

pub fn getTable(L: *lua.lua_State, idx: i32) ?*lua.lua_Table {
    const ptr = lua.idxPtr(L, idx) orelse return null;
    if (ptr.* == .table) return ptr.table;
    return null;
}

pub fn lua_gettable(L: *lua.lua_State, idx: i32) !i32 {
    const obj_ptr = lua.idxPtr(L, idx) orelse {
        lua_pushnil(L);
        return lua.LUA_TNIL;
    };
    if (obj_ptr.* == .nil) {
        lua_pushnil(L);
        return lua.LUA_TNIL;
    }
    const key = L.stack[L.top - 1];
    const res = L.top - 1;
    try ltm.luaV_gettable(L, obj_ptr, key, res);
    L.top = res + 1;
    return L.stack[res].typ();
}

pub fn lua_getfield(L: *lua.lua_State, idx: i32, k: []const u8) !i32 {
    lua.growStack(L, L.top + 1) catch return lua.LUA_TNIL;
    const obj_ptr = lua.idxPtr(L, idx) orelse {
        lua_pushnil(L);
        return lua.LUA_TNIL;
    };
    if (obj_ptr.* == .nil) {
        lua_pushnil(L);
        return lua.LUA_TNIL;
    }
    const ts = try lstring.luaS_new(L, k);
    const key = lua.TValue{ .string = ts };
    const res = L.top;
    L.stack[L.top] = .{ .nil = {} };
    L.top += 1;
    try ltm.luaV_gettable(L, obj_ptr, key, res);
    L.top = res + 1;
    return L.stack[res].typ();
}

pub fn lua_geti(L: *lua.lua_State, idx: i32, n: lua.lua_Integer) !i32 {
    lua.growStack(L, L.top + 1) catch return lua.LUA_TNIL;
    const obj_ptr = lua.idxPtr(L, idx) orelse {
        lua_pushnil(L);
        return lua.LUA_TNIL;
    };
    if (obj_ptr.* == .nil) {
        lua_pushnil(L);
        return lua.LUA_TNIL;
    }
    const key = lua.TValue{ .integer = n };
    const res = L.top;
    L.stack[L.top] = .{ .nil = {} };
    L.top += 1;
    try ltm.luaV_gettable(L, obj_ptr, key, res);
    L.top = res + 1;
    return L.stack[res].typ();
}

/// Raw (no metamethod) get — key is on top of stack.
pub fn lua_rawget(L: *lua.lua_State, idx: i32) i32 {
    const t = lua.getTable(L, idx) orelse {
        lua_pushnil(L);
        return lua.LUA_TNIL;
    };
    const key = L.stack[L.top - 1];
    const val = ltable.get(t, key);
    L.top -= 1;
    L.stack[L.top] = val;
    L.top += 1;
    return val.typ();
}

/// Raw (no metamethod) integer-key get.
pub fn lua_rawgeti(L: *lua.lua_State, idx: i32, n: lua.lua_Integer) i32 {
    const t = lua.getTable(L, idx) orelse {
        lua_pushnil(L);
        return lua.LUA_TNIL;
    };
    const val = ltable.getInt(t, n);
    L.stack[L.top] = val;
    L.top += 1;
    return val.typ();
}

pub fn lua_rawgetp(L: *lua.lua_State, idx: i32, p: ?*const anyopaque) i32 {
    const t = lua.getTable(L, idx) orelse {
        lua_pushnil(L);
        return lua.LUA_TNIL;
    };
    const val = ltable.get(t, lua.TValue{ .lightud = @constCast(p) });
    L.stack[L.top] = val;
    L.top += 1;
    return val.typ();
}

pub fn lua_createtable(L: *lua.lua_State, narr: i32, nrec: i32) void {
    const t = ltable.createTable(L.allocator, @intCast(narr), @intCast(nrec)) catch return;
    lua.registerGC(L, t) catch return;
    L.stack[L.top] = lua.TValue{ .table = t };
    L.top += 1;
    lua.luaC_condGC(L);
}

pub fn lua_newuserdatauv(L: *lua.lua_State, sz: usize, nuvalue: i32) ?*anyopaque {
    var uv: []lua.TValue = &.{};
    if (nuvalue > 0) {
        uv = L.allocator.alloc(lua.TValue, @intCast(nuvalue)) catch return null;
        for (uv) |*slot| slot.* = .{ .nil = {} };
    }
    const data = L.allocator.alloc(u8, sz) catch {
        if (uv.len > 0) L.allocator.free(uv);
        return null;
    };
    const u = L.allocator.create(lua.lua_Udata) catch {
        L.allocator.free(data);
        if (uv.len > 0) L.allocator.free(uv);
        return null;
    };
    u.* = .{ .metatable = null, .data = data, .uv = uv };
    lua.registerGC(L, u) catch {
        L.allocator.free(data);
        if (uv.len > 0) L.allocator.free(uv);
        L.allocator.destroy(u);
        return null;
    };
    L.stack[L.top] = lua.TValue{ .userdata = u };
    L.top += 1;
    return @as(*anyopaque, @ptrCast(data.ptr));
}

/// Deprecated alias for `lua_newuserdatauv(L, s, 1)`.
pub inline fn lua_newuserdata(L: *lua.lua_State, s: usize) ?*anyopaque {
    return lua_newuserdatauv(L, s, 1);
}

pub fn lua_getmetatable(L: *lua.lua_State, objindex: i32) i32 {
    const val = lua.idxPtr(L, objindex) orelse return 0;
    const mt: ?*lua.lua_Table = switch (val.*) {
        .table => |t_opt| if (t_opt) |t| t.metatable else null,
        .userdata => |u_opt| if (u_opt) |u| u.metatable else null,
        else => {
            const t = val.typ();
            if (t >= 0 and t < 9) {
                if (lua.G(L).mt[@intCast(t)]) |m| {
                    L.stack[L.top] = lua.TValue{ .table = m };
                    L.top += 1;
                    return 1;
                }
            }
            return 0;
        },
    };
    if (mt) |m| {
        L.stack[L.top] = lua.TValue{ .table = m };
        L.top += 1;
        return 1;
    }
    return 0;
}

pub fn lua_getiuservalue(L: *lua.lua_State, idx: i32, n: i32) i32 {
    const val = lua.idxPtr(L, idx) orelse {
        lua_pushnil(L);
        return lua.LUA_TNONE;
    };
    const ud = switch (val.*) {
        .userdata => |u| u,
        else => null,
    };
    if (ud) |u| {
        if (n >= 1 and @as(usize, @intCast(n)) <= u.uv.len) {
            const v = u.uv[@as(usize, @intCast(n - 1))];
            L.stack[L.top] = v;
            L.top += 1;
            return v.typ();
        }
    }
    lua_pushnil(L);
    return lua.LUA_TNONE;
}

/// Deprecated alias for `lua_getiuservalue(L, idx, 1)`.
pub inline fn lua_getuservalue(L: *lua.lua_State, idx: i32) i32 {
    return lua_getiuservalue(L, idx, 1);
}

pub fn lua_setglobal(L: *lua.lua_State, name: []const u8) !void {
    const g = lua.G(L);
    // Extract the registry table from g.registry (a lua.TValue)
    const registry: *lua.lua_Table = switch (g.registry) {
        .table => |t_opt| t_opt orelse {
            L.top -= 1;
            return;
        },
        else => {
            L.top -= 1;
            return;
        },
    };
    const globals_val = ltable.getInt(registry, 2);
    const globals: *lua.lua_Table = switch (globals_val) {
        .table => |t_opt| t_opt orelse {
            L.top -= 1;
            return;
        },
        else => {
            L.top -= 1;
            return;
        },
    };
    const s = lstring.luaS_new(L, name) catch null;
    if (s == null) {
        L.top -= 1;
        return error.OutOfMemory;
    }
    // BUG-100: propagate the error from the table set instead of swallowing it.
    try ltable.set(globals, lua.TValue{ .string = s }, L.stack[L.top - 1]);
    L.top -= 1;
}

pub fn lua_settable(L: *lua.lua_State, idx: i32) !void {
    const obj_ptr = lua.idxPtr(L, idx) orelse {
        L.top -= 2;
        return;
    };
    if (obj_ptr.* == .nil) {
        L.top -= 2;
        return;
    }
    const key = L.stack[L.top - 2];
    const val = L.stack[L.top - 1];
    L.top -= 2;
    try ltm.luaV_settable(L, obj_ptr, key, val);
}

pub fn lua_setfield(L: *lua.lua_State, idx: i32, k: []const u8) !void {
    const obj_ptr = lua.idxPtr(L, idx) orelse {
        L.top -= 1;
        return;
    };
    if (obj_ptr.* == .nil) {
        L.top -= 1;
        return;
    }
    const ts = try lstring.luaS_new(L, k);
    const val = L.stack[L.top - 1];
    L.top -= 1;
    try ltm.luaV_settable(L, obj_ptr, lua.TValue{ .string = ts }, val);
}

pub fn lua_seti(L: *lua.lua_State, idx: i32, n: lua.lua_Integer) !void {
    const obj_ptr = lua.idxPtr(L, idx) orelse {
        L.top -= 1;
        return;
    };
    if (obj_ptr.* == .nil) {
        L.top -= 1;
        return;
    }
    const val = L.stack[L.top - 1];
    L.top -= 1;
    try ltm.luaV_settable(L, obj_ptr, lua.TValue{ .integer = n }, val);
}

/// Raw (no metamethod) set — key and value are on top of stack.
pub fn lua_rawset(L: *lua.lua_State, idx: i32) !void {
    const t = lua.getTable(L, idx) orelse {
        L.top -= 2;
        return;
    };
    const key = L.stack[L.top - 2];
    const val = L.stack[L.top - 1];
    ltable.set(t, key, val) catch |err| {
        if (err == error.TableIndexIsNil) {
            try lua.luaG_runerror(L, "table index is nil");
        } else if (err == error.TableIndexIsNaN) {
            try lua.luaG_runerror(L, "table index is NaN");
        }
        return err;
    };
    L.top -= 2;
}

/// Raw (no metamethod) integer-key set.
pub fn lua_rawseti(L: *lua.lua_State, idx: i32, n: lua.lua_Integer) !void {
    const t = lua.getTable(L, idx) orelse {
        L.top -= 1;
        return;
    };
    const val = L.stack[L.top - 1];
    try ltable.setInt(t, n, val);
    L.top -= 1;
}

pub fn lua_rawsetp(L: *lua.lua_State, idx: i32, p: ?*anyopaque) !void {
    const t = lua.getTable(L, idx) orelse {
        L.top -= 1;
        return;
    };
    const val = L.stack[L.top - 1];
    try ltable.set(t, lua.TValue{ .lightud = @constCast(p) }, val);
    L.top -= 1;
}

pub fn lua_setmetatable(L: *lua.lua_State, objindex: i32) i32 {
    if (L.top == 0) return 0;

    // Resolve idx before popping — negative indices shift after L.top changes.
    const abs_idx = lua.lua_absindex(L, objindex);

    const mt_val = L.stack[L.top - 1];
    const mt: ?*lua.lua_Table = switch (mt_val) {
        .nil => null,
        .table => |t| t,
        else => return 0,
    };
    L.top -= 1;

    const val = lua.idxPtr(L, abs_idx) orelse return 0;
    switch (val.*) {
        .table => |t| {
            const tbl = t orelse return 0;
            tbl.metatable = mt;
            tbl.flags = 0;
        },
        .userdata => |u| {
            const ud = u orelse return 0;
            ud.metatable = mt;
        },
        else => {
            const t = val.typ();
            if (t >= 0 and t < 9) {
                lua.G(L).mt[@intCast(t)] = mt;
            } else {
                return 0;
            }
        },
    }
    return 1;
}

pub fn lua_setiuservalue(L: *lua.lua_State, idx: i32, n: i32) i32 {
    if (L.top == 0) return 0;
    const val = lua.idxPtr(L, idx) orelse {
        L.top -= 1;
        return 0;
    };
    const ud = switch (val.*) {
        .userdata => |u| u,
        else => null,
    };
    var res: i32 = 0;
    if (ud) |u| {
        if (n >= 1 and @as(usize, @intCast(n)) <= u.uv.len) {
            u.uv[@as(usize, @intCast(n - 1))] = L.stack[L.top - 1];
            res = 1;
        }
    }
    L.top -= 1;
    return res;
}

/// Deprecated alias for `lua_setiuservalue(L, idx, 1)`.
pub inline fn lua_setuservalue(L: *lua.lua_State, idx: i32) i32 {
    return lua_setiuservalue(L, idx, 1);
}

pub fn lua_callk(L: *lua.lua_State, nargs: i32, nresults: i32, ctx: lua.lua_KContext, k: ?lua.lua_KFunction) !void {
    const yieldable_call = (k != null and lua.lua_isyieldable(L) != 0);
    if (yieldable_call) {
        if (L.ci) |ci| {
            ci.k = k;
            ci.ctx = ctx;
        }
    }
    if (!yieldable_call) {
        // Non-yieldable call (no continuation): mirror luaD_callnoyield so
        // nested yields report "attempt to yield across a C-call boundary".
        // NOTE: the defer MUST be at function scope (Zig runs a block-scoped
        // defer at the end of the `if` block, reverting it too early).
        L.noyield += 1;
    }
    defer {
        if (!yieldable_call) L.noyield -= 1;
    }
    const func_idx = L.top - @as(usize, @intCast(nargs)) - 1;
    if (try lua.precall(L, func_idx, nresults)) |new_ci| {
        L.nCcalls += 1;
        defer L.nCcalls -= 1;
        if (L.nCcalls >= llimits.LUAI_MAXCCALLS) {
            return error.StackOverflow;
        }
        try lvm.run(L, new_ci);
    }
}

pub fn lua_call(L: *lua.lua_State, nargs: i32, nresults: i32) !void {
    try lua_callk(L, nargs, nresults, 0, null);
}

pub fn lua_pcallk(L: *lua.lua_State, nargs: i32, nresults: i32, errfunc: i32, ctx: lua.lua_KContext, k: ?lua.lua_KFunction) anyerror!i32 {
    const yieldable_call = (k != null and lua.lua_isyieldable(L) != 0);
    const old_ci = L.ci;
    if (yieldable_call) {
        if (old_ci) |ci| {
            ci.k = k;
            ci.ctx = ctx;
        }
    }
    const func_idx = L.top - @as(usize, @intCast(nargs)) - 1;
    if (yieldable_call) {
        // Mark the caller's frame as a protected call so a coroutine resume
        // that errors in this call's callee can route the error back here
        // (mirrors the reference's CIST_YPCALL).
        if (old_ci) |ci| {
            ci.ypcall = true;
            ci.pcall_func = func_idx;
        }
    }
    if (!yieldable_call) {
        // Non-yieldable protected call (no continuation): mirror the reference
        // (luaD_pcall -> f_call -> luaD_callnoyield). Kept until the call
        // finishes (including any error unwinding).
        L.noyield += 1;
    }
    defer {
        if (!yieldable_call) L.noyield -= 1;
    }

    // Resolve the error-function index to an *absolute* stack index up front.
    // At error time L.ci is no longer the caller's frame, so resolving the
    // (frame-relative) C-API index then would be wrong (mirrors the reference
    // lua_pcallk, which saves 'errfunc' as a stack offset before running).
    const errfunc_abs: ?usize = if (errfunc != 0) blk: {
        const base: usize = if (L.ci) |ci| ci.base else 0;
        const u = base + @as(usize, @intCast(errfunc - 1));
        if (u < L.top) break :blk u;
        break :blk null;
    } else null;
    const old_errfunc = L.errfunc;
    L.errfunc = if (errfunc_abs) |efi| @as(isize, @intCast(efi + 1)) else 0;
    defer L.errfunc = old_errfunc;

    var err_occurred = false;
    const new_ci = lua.precall(L, func_idx, nresults) catch |err| b: {
        if (err == error.Yield or err == error.ThreadClosed) {
            return err;
        }
        err_occurred = true;
        if (err == error.NotAFunction) {
            const msg = "attempt to call a non-function value";
            if (lstring.luaS_new(L, msg)) |ts| {
                L.stack[L.top] = lua.TValue{ .string = ts };
                L.top += 1;
            } else |_| {
                L.stack[L.top] = lua.TValue{ .nil = {} };
                L.top += 1;
            }
            // luaG_errormsg dispatches to the error handler and saves the result in L.err_obj;
            // catching the returned error union keeps L.err_obj populated for the pcall recovery path.
            _ = lua.luaG_errormsg(L) catch {};
        } else if (err == error.StackOverflow) {
            const msg = "stack overflow";
            if (lstring.luaS_new(L, msg)) |ts| {
                L.stack[L.top] = lua.TValue{ .string = ts };
                L.top += 1;
            } else |_| {
                L.stack[L.top] = lua.TValue{ .nil = {} };
                L.top += 1;
            }
            // luaG_errormsg dispatches to the error handler and saves the result in L.err_obj;
            // catching the returned error union keeps L.err_obj populated for the pcall recovery path.
            _ = lua.luaG_errormsg(L) catch {};
        } else if (err == error.RuntimeError) {
            // Error object already in L.err_obj (captured by luaG_errormsg at origin)
        } else {
            if (lstring.luaS_new(L, "error")) |ts| {
                L.stack[L.top] = lua.TValue{ .string = ts };
                L.top += 1;
            } else |_| {}
            // luaG_errormsg dispatches to the error handler and saves the result in L.err_obj;
            // catching the returned error union keeps L.err_obj populated for the pcall recovery path.
            _ = lua.luaG_errormsg(L) catch {};
        }
        break :b @as(?*lua.CallInfo, null);
    };

    if (!err_occurred) {
        if (new_ci) |ci| {
            L.nCcalls += 1;
            defer L.nCcalls -= 1;
            if (L.nCcalls >= llimits.LUAI_MAXCCALLS) {
                err_occurred = true;
                const msg = "stack overflow";
                if (lstring.luaS_new(L, msg)) |ts| {
                    L.stack[L.top] = lua.TValue{ .string = ts };
                    L.top += 1;
                } else |_| {
                    L.stack[L.top] = lua.TValue{ .nil = {} };
                    L.top += 1;
                }
            } else {
                lvm.run(L, ci) catch |err| {
                    if (err == error.Yield or err == error.ThreadClosed) {
                        return err;
                    }
                    err_occurred = true;
                    if (err == error.StackOverflow) {
                        const msg = "stack overflow";
                        if (lstring.luaS_new(L, msg)) |ts| {
                            L.stack[L.top] = lua.TValue{ .string = ts };
                            L.top += 1;
                        } else |_| {
                            L.stack[L.top] = lua.TValue{ .nil = {} };
                            L.top += 1;
                        }
                        // luaG_errormsg dispatches to the error handler and saves the result in L.err_obj;
                        // catching the returned error union keeps L.err_obj populated for the pcall recovery path.
                        _ = lua.luaG_errormsg(L) catch {};
                    }
                };
            }
        }
    }

    if (err_occurred) {
        // Save the error object (captured in L.err_obj during luaG_errormsg).
        var err_obj = L.err_obj;

        // Clean up stale lua.CallInfo frames (overflow frames from Lua recursion).
        lua.unwindCis(L, old_ci);

        // Restore L.top to its pre-call level (func_idx + nargs + 1), making
        // room for the error handler to execute (the handler's precall checks
        // lua.LUAI_MAXSTACK, and an inflated L.top would trigger StackError).
        const base_top = func_idx + @as(usize, @intCast(nargs)) + 1;

        // Push the error at a position past all TBC <close> variables,
        // so we don't overwrite them before closeupvals can process them.
        var err_push_pos = base_top;
        for (L.tbclist.items) |item| {
            if (item >= err_push_pos) err_push_pos = item + 1;
        }
        L.top = err_push_pos;
        L.stack[L.top] = err_obj;
        L.top += 1;

        lua.closeupvals(L, func_idx, err_obj) catch |ce| {
            if (ce == error.Yield) {
                // A __close metamethod yielded during the error unwind: save
                // the recovery state and let the coroutine yield;
                // completePcallRecovery finishes the pcall on resume.
                if (old_ci) |oci| {
                    oci.recovering = true;
                    oci.recover_err = err_obj;
                }
                return error.Yield;
            }
            // A __close metamethod raised while unwinding; its error object
            // (left on the stack top by closeupvals) becomes the new error.
            if (L.err_obj != .nil) {
                err_obj = L.err_obj;
            } else if (L.top > 0) {
                err_obj = L.stack[L.top - 1];
            }
        };

        // Place the error object where the first result would go, so the
        // surrounding C pcall wrapper can prepend the status boolean.
        L.stack[func_idx] = err_obj;
        L.top = func_idx + 1;
        // After a stack overflow the stack was overgrown (lua.ERRORSTACKSIZE);
        // shrink it back so subsequent calls don't inherit the overflow
        // headroom as their working limit (mirrors luaD_shrinkstack).
        lua.shrinkStack(L);
        L.err_name = null;
        L.err_namewhat = null;
        if (old_ci) |ci| ci.ypcall = false;
        return lua.LUA_ERRRUN;
    }

    L.err_name = null;
    L.err_namewhat = null;
    if (old_ci) |ci| ci.ypcall = false;
    return lua.LUA_OK;
}

pub inline fn lua_pcall(L: *lua.lua_State, nargs: i32, nresults: i32, errfunc: i32) i32 {
    return lua_pcallk(L, nargs, nresults, errfunc, 0, null) catch |e| {
        return switch (e) {
            error.Yield => lua.LUA_YIELD,
            error.OutOfMemory => lua.LUA_ERRMEM,
            error.ErrorError => lua.LUA_ERRERR,
            else => lua.LUA_ERRRUN,
        };
    };
}

/// Push a runtime-error message onto the stack and return `error.RuntimeError`
/// so the surrounding protected call reports it. Mirrors PUC-Rio's
/// `luaG_runerror`. Returns `!lua.lua.TValue` so it can be used as a function's
/// error return regardless of the function's success payload type.

pub fn lua_load(L: *lua.lua_State, reader: lua.lua_Reader, dt: ?*anyopaque, chunkname: []const u8, mode: []const u8) i32 {
    lua.luaC_condGC(L);
    const initial_top = L.top;
    var size: usize = 0;
    const first_slice = (reader(L, dt, &size) catch |e| {
        if (e == error.SyntaxError or e == error.RuntimeError) {
            if (L.top > initial_top) {
                const err_val = L.stack[L.top - 1];
                L.stack[initial_top] = err_val;
                L.top = initial_top + 1;
            }
            return lua.LUA_ERRSYNTAX;
        }
        return lua.LUA_ERRSYNTAX;
    });
    if (first_slice == null or size == 0 or first_slice.?.len == 0) {
        if (std.mem.indexOfScalar(u8, mode, 't') == null) {
            var msg: [128]u8 = undefined;
            const m = lua.fmtMsg(&msg, "attempt to load a text chunk", "attempt to load a text chunk (mode is '{s}')", .{mode});
            _ = lua_pushstring(L, m);
            if (L.top > initial_top) {
                const err_val = L.stack[L.top - 1];
                L.stack[initial_top] = err_val;
                L.top = initial_top + 1;
            }
            return lua.LUA_ERRSYNTAX;
        }
        const proto = lparser.luaD_protectedparser(L, reader, dt, chunkname, "", true) catch |e| {
            if (e == error.SyntaxError or e == error.RuntimeError) {
                if (L.top > initial_top) {
                    const err_val = L.stack[L.top - 1];
                    L.stack[initial_top] = err_val;
                    L.top = initial_top + 1;
                }
                return lua.LUA_ERRSYNTAX;
            }
            return lua.LUA_ERRMEM;
        };
        return lua.finishLoad(L, proto);
    }
    const c = first_slice.?[0];
    if (c == '\x1b') {
        if (std.mem.indexOfScalar(u8, mode, 'b') == null and std.mem.indexOfScalar(u8, mode, 'B') == null) {
            var msg: [128]u8 = undefined;
            const m = lua.fmtMsg(&msg, "attempt to load a binary chunk", "attempt to load a binary chunk (mode is '{s}')", .{mode});
            _ = lua_pushstring(L, m);
            if (L.top > initial_top) {
                const err_val = L.stack[L.top - 1];
                L.stack[initial_top] = err_val;
                L.top = initial_top + 1;
            }
            return lua.LUA_ERRSYNTAX;
        }
        const proto = lundump.loadBinaryChunk(L, reader, dt, first_slice.?, chunkname) catch |e| {
            if (e == error.OutOfMemory) return lua.LUA_ERRMEM;
            var msg_buf: [256]u8 = undefined;
            const msg = switch (e) {
                error.TruncatedChunk => lua.fmtMsg(&msg_buf, "truncated chunk", "{s}: truncated chunk", .{chunkname}),
                error.IntegerOverflow => lua.fmtMsg(&msg_buf, "integer overflow", "{s}: integer overflow", .{chunkname}),
                error.VersionMismatch => lua.fmtMsg(&msg_buf, "bad binary format (version mismatch)", "{s}: bad binary format (version mismatch)", .{chunkname}),
                error.FormatMismatch => lua.fmtMsg(&msg_buf, "bad binary format (format mismatch)", "{s}: bad binary format (format mismatch)", .{chunkname}),
                error.BadHeader, error.CorruptedChunk => lua.fmtMsg(&msg_buf, "bad binary format (corrupted chunk)", "{s}: bad binary format (corrupted chunk)", .{chunkname}),
                error.TypeSizeMismatch, error.TypeFormatMismatch => lua.fmtMsg(&msg_buf, "bad binary format (size mismatch)", "{s}: bad binary format (size mismatch)", .{chunkname}),
                else => lua.fmtMsg(&msg_buf, "corrupted chunk", "{s}: corrupted chunk", .{chunkname}),
            };
            _ = lua_pushstring(L, msg);
            if (L.top > initial_top) {
                const err_val = L.stack[L.top - 1];
                L.stack[initial_top] = err_val;
                L.top = initial_top + 1;
            }
            return lua.LUA_ERRSYNTAX;
        };
        _ = lua.lua_checkstack(L, 1);
        L.stack[L.top] = .{ .proto = proto };
        L.top += 1;
        const status = lua.finishLoad(L, proto);
        if (status == lua.LUA_OK) {
            L.stack[L.top - 2] = L.stack[L.top - 1];
            L.top -= 1;
            return lua.LUA_OK;
        } else {
            L.top = initial_top + 1;
            return status;
        }
    } else {
        if (std.mem.indexOfScalar(u8, mode, 't') == null) {
            var msg: [128]u8 = undefined;
            const m = lua.fmtMsg(&msg, "attempt to load a text chunk", "attempt to load a text chunk (mode is '{s}')", .{mode});
            _ = lua_pushstring(L, m);
            if (L.top > initial_top) {
                const err_val = L.stack[L.top - 1];
                L.stack[initial_top] = err_val;
                L.top = initial_top + 1;
            }
            return lua.LUA_ERRSYNTAX;
        }
        const proto = lparser.luaD_protectedparser(L, reader, dt, chunkname, first_slice.?, false) catch |e| {
            if (e == error.SyntaxError or e == error.RuntimeError) {
                if (L.top > initial_top) {
                    const err_val = L.stack[L.top - 1];
                    L.stack[initial_top] = err_val;
                    L.top = initial_top + 1;
                }
                return lua.LUA_ERRSYNTAX;
            }
            return lua.LUA_ERRMEM;
        };
        _ = lua.lua_checkstack(L, 1);
        L.stack[L.top] = .{ .proto = proto };
        L.top += 1;
        const status = lua.finishLoad(L, proto);
        if (status == lua.LUA_OK) {
            L.stack[L.top - 2] = L.stack[L.top - 1];
            L.top -= 1;
            return lua.LUA_OK;
        } else {
            L.top = initial_top + 1;
            return status;
        }
    }
}

// Instantiate a top-level closure for `proto` (wiring its _ENV upvalue to the
// global table) and push it onto the stack, ready to be called. Used by both
// the binary-chunk loader and the source-text parser paths.
pub fn finishLoad(L: *lua.lua_State, proto: *lua.lua_Proto) i32 {
    const lc = L.allocator.create(lua.lua_LClosure) catch {
        return lua.LUA_ERRMEM;
    };
    const upvals = L.allocator.alloc(?*lua.UpVal, proto.upvalues.len) catch {
        L.allocator.destroy(lc);
        return lua.LUA_ERRMEM;
    };
    @memset(upvals, null);
    lc.* = .{
        .p = proto,
        .upvals = upvals,
    };

    const cl = L.allocator.create(lua.lua_Closure) catch {
        L.allocator.free(upvals);
        L.allocator.destroy(lc);
        return lua.LUA_ERRMEM;
    };
    cl.* = .{ .lua = lc };
    lua.registerGC(L, cl) catch {
        L.allocator.free(upvals);
        L.allocator.destroy(lc);
        L.allocator.destroy(cl);
        return lua.LUA_ERRMEM;
    };

    // Ensure stack capacity and anchor cl on the stack immediately so it and its upvalues are tracked by GC roots
    lua.growStack(L, L.top + 1) catch {
        return lua.LUA_ERRMEM;
    };
    L.stack[L.top] = lua.TValue{ .function = cl };
    L.top += 1;

    // Initialize upvalues for top-level closure (matching PUC-Rio ldo.c)
    if (proto.upvalues.len > 0) {
        const registry = lua.G(L).registry.table orelse {
            L.top -= 1;
            return lua.LUA_ERRMEM;
        };
        const globals = ltable.getInt(registry, 2); // RIDX_GLOBALS is 2
        const is_env = if (proto.upvalues[0].name) |name| std.mem.eql(u8, name.s, "_ENV") else true;
        for (0..proto.upvalues.len) |i| {
            const uv = L.allocator.create(lua.UpVal) catch {
                L.top -= 1;
                return lua.LUA_ERRMEM;
            };
            const val: lua.TValue = if (i == 0 and is_env) globals else .{ .nil = {} };
            uv.* = .{
                .value = val,
                .v = &uv.value,
                .next = null,
                .refcount = 1,
            };
            lua.registerGC(L, uv) catch {
                L.allocator.destroy(uv);
                L.top -= 1;
                return lua.LUA_ERRMEM;
            };
            upvals[i] = uv;
        }
    }

    return lua.LUA_OK;
}

pub fn lua_dump(L: *lua.lua_State, writer: lua.lua_Writer, data: ?*anyopaque, strip: i32) i32 {
    return ldump.lua_dump(L, writer, data, strip);
}





pub fn lua_next(L: *lua.lua_State, idx: i32) anyerror!i32 {
    const t = lua.getTable(L, idx) orelse return 0;
    const key = lua.stackAt(L, -1);
    const r = ltable.next(t, key) catch |err| switch (err) {
        error.InvalidKeyToNext => {
            try lua.luaG_runerror(L, "invalid key to 'next'");
            return 0;
        },
        else => return err,
    };
    L.top -= 1;
    if (r) |kv| {
        L.stack[L.top] = kv.key;
        L.top += 1;
        L.stack[L.top] = kv.val;
        L.top += 1;
        return 1;
    }
    return 0;
}

pub inline fn isStringish(v: lua.TValue) bool {
    return switch (v) {
        .string, .number, .integer => true,
        else => false,
    };
}

pub fn luaV_concat(L: *lua.lua_State, total: usize, ra_idx: usize) !void {
    if (total <= 1) return;
    var list = std.ArrayListUnmanaged(u8).empty;
    defer list.deinit(L.allocator);
    var k: usize = total;
    while (k > 1) {
        const lhs_idx = ra_idx + k - 2;
        const rhs_idx = ra_idx + k - 1;
        const lhs = L.stack[lhs_idx];
        const rhs = L.stack[rhs_idx];
        if (lua.isStringish(lhs) and lua.isStringish(rhs)) {
            var start = k - 2;
            while (start > 0 and lua.isStringish(L.stack[ra_idx + start - 1])) : (start -= 1) {}
            list.clearRetainingCapacity();
            var j = start;
            while (j < k) : (j += 1) {
                switch (L.stack[ra_idx + j]) {
                    .string => |s| try list.appendSlice(L.allocator, s.?.s),
                    .number, .integer => {
                        var b: [128]u8 = undefined;
                        try list.appendSlice(L.allocator, lua.luaO_tostringbuff(L.stack[ra_idx + j], &b));
                    },
                    else => unreachable,
                }
            }
            const ts = try lstring.luaS_new(L, list.items);
            L.stack[ra_idx + start] = .{ .string = ts };
            k = start + 1;
        } else {
            if (L.ci) |ci| {
                ci.concat_k = k;
            }
            try ltm.luaT_trybinTM(L, &lhs, &rhs, lhs_idx, .CONCAT);
            k -= 1;
        }
    }
}

pub fn lua_concat(L: *lua.lua_State, n: i32) !void {
    if (n <= 0) {
        _ = lua_pushstring(L, "");
        return;
    }
    if (n == 1) return;
    const count = @as(usize, @intCast(n));
    if (count > L.top) return error.RuntimeError;
    const start = L.top - count;
    try lua.luaV_concat(L, count, start);
    L.top = start + 1;
}

pub fn lua_len(L: *lua.lua_State, idx: i32) !void {
    if (lua.lua_checkstack(L, 1) == 0) return error.OutOfMemory;
    const v = lua.stackAt(L, idx);
    switch (v) {
        .string => |s| {
            lua_pushinteger(L, @as(i64, @intCast(s.?.s.len)));
        },
        .table => |t| {
            const tm = if (t.?.metatable) |mt| ltm.luaT_gettm(mt, .LEN, lua.G(L).tmname[@intFromEnum(ltm.TMS.LEN)].?) else null;
            if (tm) |tm_val| {
                const res_val = try ltm.luaT_callTMres(L, tm_val, &v, &v, L.stack.len);
                L.stack[L.top] = res_val;
                L.top += 1;
            } else {
                lua_pushinteger(L, @as(i64, @intCast(ltable.getn(t.?))));
            }
        },
        else => {
            const tm = ltm.luaT_gettmbyobj(L, v, .LEN);
            if (tm == .nil) {
                return error.RuntimeError;
            }
            const res_val = try ltm.luaT_callTMres(L, tm, &v, &v, L.stack.len);
            L.stack[L.top] = res_val;
            L.top += 1;
        },
    }
}


pub fn lua_atpanic(L: *lua.lua_State, panicf: ?lua.lua_CFunction) ?lua.lua_CFunction {
    const g = lua.G(L);
    const old = g.panic;
    g.panic = panicf;
    return old;
}

pub fn lua_version(L: *lua.lua_State) lua.lua_Number {
    _ = L;
    return lua.LUA_VERSION_NUM;
}

pub fn lua_getallocf(L: *lua.lua_State, ud: ?*?*anyopaque) lua.lua_Alloc {
    const g = lua.G(L);
    if (ud) |p| p.* = g.alloc_ud;
    return g.allocf;
}

pub fn lua_setallocf(L: *lua.lua_State, f: lua.lua_Alloc, ud: ?*anyopaque) void {
    const g = lua.G(L);
    g.allocf = f;
    g.alloc_ud = ud;
}

pub fn checkclosemth(L: *lua.lua_State, abs: usize) !void {
    const v = L.stack[abs];
    if (v == .nil or (v == .boolean and v.boolean == false)) {
        return;
    }
    const mt = switch (v) {
        .table => |t| if (t) |x| x.metatable else null,
        .userdata => |u| if (u) |x| x.metatable else null,
        else => null,
    };
    const tm = if (mt) |m| ltm.luaT_gettm(m, .CLOSE, lua.G(L).tmname[@intFromEnum(ltm.TMS.CLOSE)].?) else null;
    if (tm == null or tm.? == .nil) {
        const ci = L.ci.?;
        const idx = @as(i32, @intCast(abs)) - @as(i32, @intCast(ci.base));
        var vname: ?[]const u8 = null;
        if (ci.func != 0) {
            const val = L.stack[ci.func];
            if (val == .function and val.function.?.* == .lua) {
                const proto = val.function.?.lua.p;
                vname = lua.luaF_getlocalname(proto, idx + 1, @intCast(lua.currentpc(ci)));
            }
        }
        const name = vname orelse "?";
        const msg = try std.fmt.allocPrint(L.allocator, "variable '{s}' got a non-closable value", .{name});
        defer L.allocator.free(msg);
        const ts = try lstring.luaS_new(L, msg);
        L.stack[L.top] = lua.TValue{ .string = ts };
        L.top += 1;
        return lua.luaG_errormsg(L);
    }
}

pub fn lua_toclose(L: *lua.lua_State, idx: i32) !void {
    const abs = @as(usize, @intCast(lua.lua_absindex(L, idx))) - 1;
    try checkclosemth(L, abs);
    const v = L.stack[abs];
    if (v != .nil and (v != .boolean or v.boolean != false)) {
        try L.tbclist.append(L.allocator, abs);
    }
}

pub fn lua_closeslot(L: *lua.lua_State, idx: i32) void {
    const abs = @as(usize, @intCast(lua.lua_absindex(L, idx))) - 1;
    if (L.tbclist.items.len > 0) {
        var i: usize = L.tbclist.items.len;
        while (i > 0) {
            i -= 1;
            if (L.tbclist.items[i] == abs) {
                _ = L.tbclist.swapRemove(i);
                break;
            }
        }
    }
    _ = lua.close_one_slot(L, abs, null) catch null;
    lua.luaC_condGC(L);
}


pub fn luaL_dostring(L: *lua.lua_State, s: []const u8, name: []const u8) !i32 {
    var data = s;
    const status = lua.lua_load(L, luaL_dostringReader, @as(?*anyopaque, @ptrCast(&data)), name, "bt");
    if (status != lua.LUA_OK) {
        return status;
    }
    return lua_pcall(L, 0, lua.LUA_MULTRET, 0);
}

pub fn luaL_dostringReader(L: *lua.lua_State, data: ?*anyopaque, size: ?*usize) anyerror!?[]const u8 {
    _ = L;
    const slice_ptr = @as(?*[]const u8, @ptrCast(@alignCast(data))) orelse return null;
    if (slice_ptr.*.len == 0) {
        if (size) |s| s.* = 0;
        return null;
    }
    const chunk = slice_ptr.*;
    slice_ptr.* = &[_]u8{};
    if (size) |s| s.* = chunk.len;
    return chunk;
}


/// Deprecated H.5 alias for `lua_tolstring` (null len).
pub fn lua_tostring(L: *lua.lua_State, idx: i32) ?[]const u8 {
    return lua_tolstring(L, idx, null);
}
