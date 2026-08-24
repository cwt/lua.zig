// $Id: lvm.zig $
// Virtual Machine for Lua.zig (Zig port of Lua 5.5.0)
// See Copyright Notice in c_compat.zig

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");
const ltm = @import("ltm.zig");
const libm = @import("libm.zig");

const PF_VAHID = 1; // function has hidden vararg arguments

/// Try to convert a value to a numeric TValue (integer or float).
/// For strings, uses the locale-aware tonumberValue (mirrors lua_stringtonumber).
fn toNumeric(v: lua.TValue) ?lua.TValue {
    return switch (v) {
        .integer => v,
        .number => v,
        .string => |s| {
            const str = s orelse return null;
            return lua.tonumberValue(str.s);
        },
        else => null,
    };
}

inline fn asFloat(v: lua.TValue) f64 {
    return switch (v) {
        .number => |n| n,
        .integer => |n| @as(f64, @floatFromInt(n)),
        else => unreachable,
    };
}

/// Propagate a "number has no integer representation" error from a bitwise/shift
/// operand `o`, returning a `!TValue` so it can be used inside `arithCompute`.
fn tointerr(L: *lua.lua_State, o: lua.TValue) !lua.TValue {
    lua.luaG_tointerror(L, o) catch return error.RuntimeError;
    unreachable;
}

fn numMod(a: f64, b: f64) f64 {
    var m = libm.getLibm().fmod(a, b);
    if (if (m > 0) b < 0 else (m < 0 and b > 0)) {
        m += b;
    }
    return m;
}

fn forlimit(L: *lua.lua_State, init: i64, lim: lua.TValue, p: *i64, step: i64) !bool {
    const min_f64 = @as(f64, -9223372036854775808.0);
    const max_exclusive_f64 = @as(f64, 9223372036854775808.0);

    var converted = false;
    var val: i64 = 0;
    const num = toNumeric(lim);
    if (num) |nv| {
        switch (nv) {
            .integer => |n| {
                val = n;
                converted = true;
            },
            .number => |n| {
                const f = if (step < 0) @ceil(n) else @floor(n);
                if (f >= min_f64 and f < max_exclusive_f64) {
                    val = @as(i64, @intFromFloat(f));
                    converted = true;
                }
            },
            else => unreachable,
        }
    }
    if (converted) {
        p.* = val;
        return if (step > 0) init > val else init < val;
    }

    var flim: f64 = 0.0;
    if (num) |nv| {
        flim = switch (nv) {
            .integer => |n| @as(f64, @floatFromInt(n)),
            .number => |n| n,
            else => unreachable,
        };
    } else {
        try lua.luaG_forerror(L, lim, "limit");
        return true;
    }

    if (0.0 < flim) {
        if (step < 0) return true;
        p.* = std.math.maxInt(i64);
    } else {
        if (step > 0) return true;
        p.* = std.math.minInt(i64);
    }
    return false;
}

fn forprep(L: *lua.lua_State, ra_idx: usize) !bool {
    const pinit = L.stack[ra_idx];
    const plimit = L.stack[ra_idx + 1];
    const pstep = L.stack[ra_idx + 2];

    if (pinit == .integer and pstep == .integer) {
        const init = pinit.integer;
        const step = pstep.integer;
        var limit: i64 = 0;
        if (step == 0) {
            try lua.luaG_runerror(L, "'for' step is zero");
        }
        if (try forlimit(L, init, plimit, &limit, step)) {
            return true;
        } else {
            var count: u64 = 0;
            if (step > 0) {
                count = @as(u64, @bitCast(limit)) -% @as(u64, @bitCast(init));
                if (step != 1) {
                    count /= @as(u64, @bitCast(step));
                }
            } else {
                count = @as(u64, @bitCast(init)) -% @as(u64, @bitCast(limit));
                count /= @as(u64, @bitCast(-(step +% 1))) +% 1;
            }
            L.stack[ra_idx] = .{ .integer = @bitCast(count) };
            L.stack[ra_idx + 1] = .{ .integer = step };
            L.stack[ra_idx + 2] = .{ .integer = init };
        }
    } else {
        var init: f64 = 0.0;
        var limit: f64 = 0.0;
        var step: f64 = 0.0;

        const num_limit = toNumeric(plimit);
        if (num_limit == null) {
            try lua.luaG_forerror(L, plimit, "limit");
        }
        limit = switch (num_limit.?) {
            .integer => |n| @as(f64, @floatFromInt(n)),
            .number => |n| n,
            else => unreachable,
        };

        const num_step = toNumeric(pstep);
        if (num_step == null) {
            try lua.luaG_forerror(L, pstep, "step");
        }
        step = switch (num_step.?) {
            .integer => |n| @as(f64, @floatFromInt(n)),
            .number => |n| n,
            else => unreachable,
        };
        if (step == 0.0) {
            try lua.luaG_runerror(L, "'for' step is zero");
        }

        const num_init = toNumeric(pinit);
        if (num_init == null) {
            try lua.luaG_forerror(L, pinit, "initial value");
        }
        init = switch (num_init.?) {
            .integer => |n| @as(f64, @floatFromInt(n)),
            .number => |n| n,
            else => unreachable,
        };

        if (if (0.0 < step) limit < init else init < limit) {
            return true;
        } else {
            L.stack[ra_idx] = .{ .number = limit };
            L.stack[ra_idx + 1] = .{ .number = step };
            L.stack[ra_idx + 2] = .{ .number = init };
        }
    }
    return false;
}

fn floatforloop(ra_idx: usize, L: *lua.lua_State) bool {
    const step = L.stack[ra_idx + 1].number;
    const limit = L.stack[ra_idx].number;
    const idx = L.stack[ra_idx + 2].number + step;
    if (if (0.0 < step) idx <= limit else limit <= idx) {
        L.stack[ra_idx + 2] = .{ .number = idx };
        return true;
    }
    return false;
}

/// Compute the result of a binary arithmetic operation on two numeric values.
/// Errors with "attempt to divide by zero" on integer/float // or % by zero,
/// mirroring the reference (which throws rather than returning 0).
fn arithCompute(L: *lua.lua_State, op: i32, n1: lua.TValue, n2: lua.TValue) !lua.TValue {
    if (n1 == .integer and n2 == .integer) {
        if ((op == lua.LUA_OPIDIV) and n2.integer == 0) {
            // BUG-100: the error function itself must not swallow its own
            // error; propagate it so the caller handles it properly.
            try lua.luaG_runerror(L, "attempt to divide by zero");
            return error.RuntimeError;
        }
        return switch (op) {
            lua.LUA_OPADD => .{ .integer = n1.integer +% n2.integer },
            lua.LUA_OPSUB => .{ .integer = n1.integer -% n2.integer },
            lua.LUA_OPMUL => .{ .integer = n1.integer *% n2.integer },
            lua.LUA_OPMOD => blk: {
                const ib = n1.integer;
                const ic = n2.integer;
                if (ic == 0) {
                    // BUG-100: propagate instead of swallowing.
                    try lua.luaG_runerror(L, "attempt to perform 'n%0'");
                    return error.RuntimeError;
                }
                const r: i64 = if (ic == -1) 0 else @rem(ib, ic);
                break :blk lua.TValue{ .integer = if (r != 0 and (r ^ ic) < 0) r + ic else r };
            },
            lua.LUA_OPPOW => .{ .number = libm.getLibm().pow(@as(f64, @floatFromInt(n1.integer)), @as(f64, @floatFromInt(n2.integer))) },
            lua.LUA_OPDIV => .{ .number = @as(f64, @floatFromInt(n1.integer)) / @as(f64, @floatFromInt(n2.integer)) },
            lua.LUA_OPIDIV => blk: {
                const ib = n1.integer;
                const ic = n2.integer;
                const q: i64 = if (ic == -1) 0 -% ib else @divTrunc(ib, ic);
                const r: i64 = if (ic == -1) 0 else @rem(ib, ic);
                break :blk lua.TValue{ .integer = if (r == 0 or (ib >= 0) == (ic >= 0)) q else q - 1 };
            },
            lua.LUA_OPBAND => .{ .integer = n1.integer & n2.integer },
            lua.LUA_OPBOR => .{ .integer = n1.integer | n2.integer },
            lua.LUA_OPBXOR => .{ .integer = n1.integer ^ n2.integer },
            lua.LUA_OPSHL => .{ .integer = lua.luaV_shift(n1.integer, n2.integer) },
            lua.LUA_OPSHR => .{ .integer = lua.luaV_shift(n1.integer, -%n2.integer) },
            else => unreachable,
        };
    }
    const f1 = n1.toFloat();
    const f2 = n2.toFloat();
    return switch (op) {
        lua.LUA_OPADD => .{ .number = f1 + f2 },
        lua.LUA_OPSUB => .{ .number = f1 - f2 },
        lua.LUA_OPMUL => .{ .number = f1 * f2 },
        lua.LUA_OPMOD => .{ .number = numMod(f1, f2) },
        lua.LUA_OPPOW => .{ .number = libm.getLibm().pow(f1, f2) },
        lua.LUA_OPDIV => .{ .number = f1 / f2 },
        lua.LUA_OPIDIV => .{ .number = @floor(f1 / f2) },
        lua.LUA_OPBAND => blk: {
            const ib1 = n1.toIntegerExactOpt() orelse return tointerr(L, n1);
            const ic1 = n2.toIntegerExactOpt() orelse return tointerr(L, n2);
            break :blk .{ .integer = ib1 & ic1 };
        },
        lua.LUA_OPBOR => blk: {
            const ib1 = n1.toIntegerExactOpt() orelse return tointerr(L, n1);
            const ic1 = n2.toIntegerExactOpt() orelse return tointerr(L, n2);
            break :blk .{ .integer = ib1 | ic1 };
        },
        lua.LUA_OPBXOR => blk: {
            const ib1 = n1.toIntegerExactOpt() orelse return tointerr(L, n1);
            const ic1 = n2.toIntegerExactOpt() orelse return tointerr(L, n2);
            break :blk .{ .integer = ib1 ^ ic1 };
        },
        lua.LUA_OPSHL => blk: {
            const ib1 = n1.toIntegerExactOpt() orelse return tointerr(L, n1);
            const ic1 = n2.toIntegerExactOpt() orelse return tointerr(L, n2);
            break :blk .{ .integer = lua.luaV_shift(ib1, ic1) };
        },
        lua.LUA_OPSHR => blk: {
            const ib1 = n1.toIntegerExactOpt() orelse return tointerr(L, n1);
            const ic1 = n2.toIntegerExactOpt() orelse return tointerr(L, n2);
            break :blk .{ .integer = lua.luaV_shift(ib1, -%ic1) };
        },
        else => unreachable,
    };
}

/// Binary arithmetic fallback for the VM: coerce operands to numbers, compute
/// the result, or invoke the corresponding metamethod. Returns the result in
/// L.stack[ra]; raises a RuntimeError if neither coercion nor a metamethod apply.
fn luaV_doarith(L: *lua.lua_State, op: i32, ra: usize, rb: lua.TValue, rc: lua.TValue) !void {
    const n1 = toNumeric(rb);
    const n2 = toNumeric(rc);
    if (n1 != null and n2 != null) {
        L.stack[ra] = try arithCompute(L, op, n1.?, n2.?);
        return;
    }
    const event: ltm.TMS = switch (op) {
        lua.LUA_OPADD => .ADD,
        lua.LUA_OPSUB => .SUB,
        lua.LUA_OPMUL => .MUL,
        lua.LUA_OPDIV => .DIV,
        lua.LUA_OPIDIV => .IDIV,
        lua.LUA_OPMOD => .MOD,
        lua.LUA_OPPOW => .POW,
        lua.LUA_OPBAND => .BAND,
        lua.LUA_OPBOR => .BOR,
        lua.LUA_OPBXOR => .BXOR,
        lua.LUA_OPSHL => .SHL,
        lua.LUA_OPSHR => .SHR,
        else => unreachable,
    };
    try ltm.luaT_trybinTM(L, &rb, &rc, ra, event);
}

// True if the closure currently executing in 'ci' uses hidden vararg
// arguments (and therefore had its frame relocated by buildhiddenargs).
fn isVarargFunc(L: *lua.lua_State, ci: *lua.CallInfo) bool {
    const fv = L.stack[ci.func];
    if (fv == .function) {
        if (fv.function) |clo| switch (clo.*) {
            .lua => |lc| return (lc.p.flag & PF_VAHID) != 0,
            else => {},
        };
    }
    return false;
}

// Number of fixed parameters of the closure executing in 'ci'.
fn numParamsOf(L: *lua.lua_State, ci: *lua.CallInfo) usize {
    const fv = L.stack[ci.func];
    if (fv == .function) {
        if (fv.function) |clo| switch (clo.*) {
            .lua => |lc| return lc.p.numParams,
            else => {},
        };
    }
    return 0;
}

// ===================================================================
// Opcodes
// ===================================================================

pub const OpCode = enum {
    MOVE,
    LOADI,
    LOADF,
    LOADK,
    LOADKX,
    LOADFALSE,
    LFALSESKIP,
    LOADTRUE,
    LOADNIL,
    GETUPVAL,
    SETUPVAL,
    GETTABUP,
    GETTABLE,
    GETI,
    GETFIELD,
    SETTABUP,
    SETTABLE,
    SETI,
    SETFIELD,
    NEWTABLE,
    SELF,
    ADDI,
    ADDK,
    SUBK,
    MULK,
    MODK,
    POWK,
    DIVK,
    IDIVK,
    BANDK,
    BORK,
    BXORK,
    SHLI,
    SHRI,
    ADD,
    SUB,
    MUL,
    MOD,
    POW,
    DIV,
    IDIV,
    BAND,
    BOR,
    BXOR,
    SHL,
    SHR,
    MMBIN,
    MMBINI,
    MMBINK,
    UNM,
    BNOT,
    NOT,
    LEN,
    CONCAT,
    CLOSE,
    TBC,
    JMP,
    EQ,
    LT,
    LE,
    EQK,
    EQI,
    LTI,
    LEI,
    GTI,
    GEI,
    TEST,
    TESTSET,
    CALL,
    TAILCALL,
    RETURN,
    RETURN0,
    RETURN1,
    FORLOOP,
    FORPREP,
    TFORPREP,
    TFORCALL,
    TFORLOOP,
    SETLIST,
    CLOSURE,
    VARARG,
    GETVARG,
    ERRNNIL,
    VARARGPREP,
    EXTRAARG,
};

// ===================================================================
// Instruction helpers
//
// Lua 5.5.0 instruction format (u32):
//   OPCODE: bits 0-6   (7 bits)
//   A:      bits 24-31 (8 bits)
//   B:      bits 16-23 (8 bits)
//   C:      bits 8-15  (8 bits)
//   vB:     bits 22-27 (6 bits, signed extension of B)
//   vC:     bits 0-7   (8 bits)
//   Bx:     bits 16-31 (16 bits)
//   Ax:     bits 8-31  (24 bits)
// ===================================================================

pub const Instruction = u32;

pub fn getOpMode(_: Instruction) i8 {
    return 0;
}

pub fn GET_OPCODE(i: Instruction) OpCode {
    return @as(OpCode, @enumFromInt(@as(u7, @truncate(i & 0x7F))));
}

pub fn SET_OPCODE(i: *Instruction, o: OpCode) void {
    i.* = (i.* & ~@as(u32, 0x7F)) | @as(u32, @intFromEnum(o));
}

pub fn GETARG_A(i: Instruction) i32 {
    return @as(i32, @intCast((i >> 7) & 0xFF));
}
pub fn SETARG_A(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0xFF << 7)) | (@as(u32, @intCast(v & 0xFF)) << 7);
}

pub fn GETARG_B(i: Instruction) i32 {
    return @as(i32, @intCast((i >> 16) & 0xFF));
}
pub fn SETARG_B(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0xFF << 16)) | (@as(u32, @intCast(v & 0xFF)) << 16);
}

pub fn GETARG_vB(i: Instruction) i32 {
    return @as(i32, @intCast((i >> 16) & 0x3F));
}
pub fn SETARG_vB(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0x3F << 16)) | (@as(u32, @intCast(v & 0x3F)) << 16);
}

pub fn GETARG_C(i: Instruction) i32 {
    return @as(i32, @intCast((i >> 24) & 0xFF));
}
pub fn SETARG_C(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0xFF << 24)) | (@as(u32, @intCast(v & 0xFF)) << 24);
}

pub fn GETARG_vC(i: Instruction) i32 {
    return @as(i32, @intCast((i >> 22) & 0x3FF));
}
pub fn SETARG_vC(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0x3FF << 22)) | (@as(u32, @intCast(v & 0x3FF)) << 22);
}

pub fn GETARG_k(i: Instruction) i32 {
    return @as(i32, @intCast((i >> 15) & 1));
}
pub fn SETARG_k(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 1 << 15)) | (@as(u32, @intCast(v & 1)) << 15);
}

pub fn GETARG_sB(i: Instruction) i32 {
    return GETARG_B(i) - 127;
}
pub fn SETARG_sB(i: *Instruction, v: i32) void {
    SETARG_B(i, v + 127);
}

pub fn GETARG_sC(i: Instruction) i32 {
    return GETARG_C(i) - 127;
}
pub fn SETARG_sC(i: *Instruction, v: i32) void {
    SETARG_C(i, v + 127);
}

pub fn GETARG_Bx(i: Instruction) i32 {
    return @as(i32, @intCast((i >> 15) & 0x1FFFF));
}
pub fn SETARG_Bx(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0x1FFFF << 15)) | (@as(u32, @intCast(v & 0x1FFFF)) << 15);
}

pub fn GETARG_Ax(i: Instruction) i32 {
    return @as(i32, @intCast((i >> 7) & 0x1FFFFFF));
}
pub fn SETARG_Ax(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0x1FFFFFF << 7)) | (@as(u32, @intCast(v & 0x1FFFFFF)) << 7);
}

pub fn GETARG_sBx(i: Instruction) i32 {
    return GETARG_Bx(i) - 65535;
}
pub fn SETARG_sBx(i: *Instruction, v: i32) void {
    SETARG_Bx(i, v + 65535);
}

pub fn GETARG_sJ(i: Instruction) i32 {
    const val = (i >> 7) & 0x1FFFFFF;
    return @as(i32, @intCast(val)) - 16777215;
}
pub fn SETARG_sJ(i: *Instruction, v: i32) void {
    const val = @as(u32, @intCast(v + 16777215)) & 0x1FFFFFF;
    i.* = (i.* & ~@as(u32, 0x1FFFFFF << 7)) | (val << 7);
}

/// Complete the execution of an instruction interrupted by a yield, before
/// resuming the frame (port of the reference `luaV_finishOp`). The metamethod
/// call's result is on the stack top; move it to the instruction's destination
/// register (or apply the instruction's specific completion logic).
pub fn finishOp(L: *lua.lua_State, ci: *lua.CallInfo) void {
    if (ci.savedpc < 1) return;
    const code = L.stack[ci.func].function.?.lua.p.code;
    const inst = code[@as(usize, @intCast(ci.savedpc - 1))];
    switch (GET_OPCODE(inst)) {
        .MMBIN, .MMBINI, .MMBINK => {
            if (ci.savedpc < 2) return;
            const prev = code[@as(usize, @intCast(ci.savedpc - 2))];
            const dest = ci.base + @as(usize, @intCast(GETARG_A(prev)));
            if (L.top > 0) {
                L.stack[dest] = L.stack[L.top - 1];
                L.top -= 1;
            }
        },
        .UNM, .BNOT, .LEN, .GETTABUP, .GETTABLE, .GETI, .GETFIELD, .SELF => {
            const dest = ci.base + @as(usize, @intCast(GETARG_A(inst)));
            if (L.top > 0) {
                L.stack[dest] = L.stack[L.top - 1];
                L.top -= 1;
            }
        },
        .CLOSE => {
            // A __close metamethod yielded while closing; repeat the
            // instruction to close the remaining variables.
            ci.savedpc -= 1;
        },
        .RETURN => {
            // A __close metamethod yielded during this return; restore the
            // correct top and repeat the instruction to complete the return.
            const ra = ci.base + @as(usize, @intCast(GETARG_A(inst)));
            L.top = ra + @as(usize, @intCast(ci.nres_saved));
            ci.savedpc -= 1;
        },
        else => {},
    }
}

// -------------------------------------------------------------------
// Argument-limit constants (consistent with the encoding above)
// -------------------------------------------------------------------
pub inline fn getStack(L: *lua.lua_State, idx: usize) lua.TValue {
    if (idx < L.stack.len) {
        return L.stack[idx];
    }
    return .{ .nil = {} };
}

pub inline fn setStack(L: *lua.lua_State, idx: usize, val: lua.TValue) void {
    if (idx >= L.stack.len) {
        _ = lua.lua_checkstack(L, @intCast(idx + 1 - L.top));
    }
    if (idx < L.stack.len) {
        L.stack[idx] = val;
    }
}

pub const MAXARG_A = 0xFF;
pub const MAXARG_B = 0xFF;
pub const MAXARG_C = 0xFF;
pub const MAXARG_vB = 0x3F;
pub const MAXARG_vC = 0x3FF;
pub const MAXARG_Bx = 0x1FFFF;
pub const MAXARG_Ax = 0x1FFFFFF;
pub const MAXARG_sJ = 0x1FFFFFF;
pub const MAXARG_sC = 0xFF;
pub const OFFSET_sBx = 65535;
pub const OFFSET_sJ = 16777215;
pub const OFFSET_sC = 127;
pub const NO_REG: i32 = -1;
pub const MAXINDEXRK = MAXARG_C;
pub const MAX_FSTACK = 255;
pub const MAXIWTHABS = 128;
pub const LIMLINEDIFF = 0x80;
pub const ABSLINEINFO: i32 = -0x80;

// -------------------------------------------------------------------
// Instruction construction macros
// -------------------------------------------------------------------
pub fn CREATE_ABCk(o: OpCode, a: i32, b: i32, c: i32, k: i32) Instruction {
    var i: Instruction = 0;
    SET_OPCODE(&i, o);
    SETARG_A(&i, a);
    SETARG_B(&i, b);
    SETARG_C(&i, c);
    SETARG_k(&i, k);
    return i;
}

pub fn CREATE_vABCk(o: OpCode, a: i32, b: i32, c: i32, k: i32) Instruction {
    var i: Instruction = 0;
    SET_OPCODE(&i, o);
    SETARG_A(&i, a);
    SETARG_vB(&i, b);
    SETARG_vC(&i, c);
    SETARG_k(&i, k);
    return i;
}

pub fn CREATE_ABx(o: OpCode, a: i32, bx: i32) Instruction {
    var i: Instruction = 0;
    SET_OPCODE(&i, o);
    SETARG_A(&i, a);
    SETARG_Bx(&i, bx);
    return i;
}

pub fn CREATE_Ax(o: OpCode, ax: i32) Instruction {
    var i: Instruction = 0;
    SET_OPCODE(&i, o);
    SETARG_Ax(&i, ax);
    return i;
}

pub fn CREATE_sJ(o: OpCode, sj: i32, k: i32) Instruction {
    var i: Instruction = 0;
    SET_OPCODE(&i, o);
    // 'k' for J-format is always 0 in practice (ignored); sJ occupies bits 7-31.
    _ = k;
    SETARG_sJ(&i, sj);
    return i;
}

// -------------------------------------------------------------------
// Opcode "test" mode: true for comparison/test opcodes that are
// always followed by a jump instruction.
// -------------------------------------------------------------------
pub fn testTMode(o: OpCode) bool {
    return switch (o) {
        .EQ, .LT, .LE, .EQK, .EQI, .LTI, .LEI, .GTI, .GEI, .TEST, .TESTSET => true,
        else => false,
    };
}

// ===================================================================
// Value representation
// ===================================================================

// ===================================================================
// VM Execution
// ===================================================================

pub fn run(L: *lua.lua_State, active_ci: *lua.CallInfo) anyerror!void {
    const ltable = @import("ltable.zig");
    const lstring = @import("lstring.zig");

    var ci = active_ci;
    var cl = L.stack[ci.func].function.?.lua;
    var proto = cl.p;
    var code = proto.code;
    // Hoist the global state out of the per-instruction path (the reference's
    // luaV_execute keeps GC state in locals). The hook mask is re-read each
    // instruction: a nested call (e.g. debug.sethook) can change it, and a
    // hoisted copy would go stale across frame boundaries.
    const g = L.l_G orelse return error.NoGlobalState;

    while (ci.savedpc < code.len) {
        if (g.gc_running and g.gc_count > g.gc_threshold) {
            const old_top = L.top;
            L.top = ci.top;
            try lua.luaC_collectgarbage(L);
            L.top = old_top;
        }
        const instruction: Instruction = code[ci.savedpc];
        const op = GET_OPCODE(instruction);
        ci.savedpc += 1;
        // The hook check must run after `savedpc` advances: luaG_traceexec
        // reads the current pc as savedpc-1.
        if (L.hookmask != 0) {
            lua.luaG_traceexec(L);
        }
        switch (op) {
            .MOVE => {
                const a = GETARG_A(instruction);
                const b = GETARG_B(instruction);
                L.stack[ci.base + @as(usize, @intCast(a))] = L.stack[ci.base + @as(usize, @intCast(b))];
            },
            .LOADI => {
                const a = GETARG_A(instruction);
                const sbx = GETARG_sBx(instruction);
                L.stack[ci.base + @as(usize, @intCast(a))] = .{ .integer = sbx };
            },
            .LOADF => {
                const a = GETARG_A(instruction);
                const sbx = GETARG_sBx(instruction);
                L.stack[ci.base + @as(usize, @intCast(a))] = .{ .number = @as(f64, @floatFromInt(sbx)) };
            },
            .LOADK => {
                const a = GETARG_A(instruction);
                const bx = GETARG_Bx(instruction);
                const kval = proto.k[@as(usize, @intCast(bx))];
                L.stack[ci.base + @as(usize, @intCast(a))] = kval;
            },
            .LOADKX => {
                const a = GETARG_A(instruction);
                const extra = code[ci.savedpc];
                ci.savedpc += 1;
                const ax = GETARG_Ax(extra);
                L.stack[ci.base + @as(usize, @intCast(a))] = proto.k[@as(usize, @intCast(ax))];
            },
            .LOADFALSE => {
                const a = GETARG_A(instruction);
                L.stack[ci.base + @as(usize, @intCast(a))] = .{ .boolean = false };
            },
            .LFALSESKIP => {
                const a = GETARG_A(instruction);
                L.stack[ci.base + @as(usize, @intCast(a))] = .{ .boolean = false };
                ci.savedpc += 1;
            },
            .LOADTRUE => {
                const a = GETARG_A(instruction);
                L.stack[ci.base + @as(usize, @intCast(a))] = .{ .boolean = true };
            },
            .LOADNIL => {
                const a = @as(usize, @intCast(GETARG_A(instruction)));
                var b = GETARG_B(instruction);
                var idx = ci.base + a;
                while (b >= 0) : (b -= 1) {
                    L.stack[idx] = .{ .nil = {} };
                    idx += 1;
                }
            },
            .GETUPVAL => {
                const a = @as(usize, @intCast(GETARG_A(instruction)));
                const b = @as(usize, @intCast(GETARG_B(instruction)));
                const uv = cl.upvals[b].?;
                L.stack[ci.base + a] = uv.v.*;
            },
            .SETUPVAL => {
                const a = @as(usize, @intCast(GETARG_A(instruction)));
                const b = @as(usize, @intCast(GETARG_B(instruction)));
                const uv = cl.upvals[b].?;
                uv.v.* = L.stack[ci.base + a];
            },
            .GETTABUP => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = @as(usize, @intCast(GETARG_B(instruction)));
                const c = @as(usize, @intCast(GETARG_C(instruction)));
                const uv = cl.upvals[b].?;
                const key = proto.k[c];
                try ltm.luaV_gettable(L, uv.v, key, a);
            },
            .GETTABLE => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const c = ci.base + @as(usize, @intCast(GETARG_C(instruction)));
                const key = L.stack[c];
                try ltm.luaV_gettable(L, &L.stack[b], key, a);
            },
            .GETI => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const c = GETARG_C(instruction);
                const int_key = lua.TValue{ .integer = c };
                try ltm.luaV_gettable(L, &L.stack[b], int_key, a);
            },
            .GETFIELD => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const c = @as(usize, @intCast(GETARG_C(instruction)));
                const key = proto.k[c];
                try ltm.luaV_gettable(L, &L.stack[b], key, a);
            },
            .SETTABUP => {
                const a = @as(usize, @intCast(GETARG_A(instruction)));
                const b = @as(usize, @intCast(GETARG_B(instruction)));
                const c = @as(usize, @intCast(GETARG_C(instruction)));
                const uv = cl.upvals[a].?;
                const key = proto.k[b];
                const val = if (GETARG_k(instruction) != 0) proto.k[c] else L.stack[ci.base + c];
                try ltm.luaV_settable(L, uv.v, key, val);
            },
            .SETTABLE => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const c = @as(usize, @intCast(GETARG_C(instruction)));
                const key = L.stack[b];
                const val = if (GETARG_k(instruction) != 0) proto.k[c] else L.stack[ci.base + c];
                try ltm.luaV_settable(L, &L.stack[a], key, val);
            },
            .SETI => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = GETARG_B(instruction);
                const c = @as(usize, @intCast(GETARG_C(instruction)));
                const val = if (GETARG_k(instruction) != 0) proto.k[c] else L.stack[ci.base + c];
                const int_key = lua.TValue{ .integer = b };
                try ltm.luaV_settable(L, &L.stack[a], int_key, val);
            },
            .SETFIELD => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = @as(usize, @intCast(GETARG_B(instruction)));
                const c = @as(usize, @intCast(GETARG_C(instruction)));
                const key = proto.k[b];
                const val = if (GETARG_k(instruction) != 0) proto.k[c] else L.stack[ci.base + c];
                try ltm.luaV_settable(L, &L.stack[a], key, val);
            },
            .NEWTABLE => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const vB = @as(usize, @intCast(GETARG_vB(instruction)));
                const vC = @as(usize, @intCast(GETARG_vC(instruction)));
                var narr = vC;
                if (GETARG_k(instruction) != 0) {
                    const extra = @as(usize, @intCast(GETARG_Ax(code[ci.savedpc])));
                    ci.savedpc += 1;
                    narr += extra * (MAXARG_vC + 1);
                }
                const shift = @as(u6, @intCast(@min(vB - 1, 63)));
                const nrec = if (vB > 0) @as(usize, 1) << shift else 0;
                const tab = try ltable.createTable(L.allocator, narr, nrec);
                try lua.registerGC(L, tab);
                L.stack[ra_idx] = .{ .table = tab };
            },
            .SELF => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb_idx = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const key = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                L.stack[ra_idx + 1] = L.stack[rb_idx];
                try ltm.luaV_gettable(L, &L.stack[rb_idx], key, ra_idx);
            },
            .ADDI => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const sc = GETARG_sC(instruction);
                if (toNumeric(rb)) |nv| {
                    if (nv == .integer) {
                        L.stack[ra] = .{ .integer = nv.integer +% sc };
                    } else {
                        L.stack[ra] = .{ .number = nv.number + @as(f64, @floatFromInt(sc)) };
                    }
                    ci.savedpc += 1;
                }
            },
            .ADDK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (toNumeric(rb)) |nv| {
                    if (nv == .integer and rc == .integer) {
                        L.stack[ra] = .{ .integer = nv.integer +% rc.integer };
                    } else if (nv.isNumberValue() and rc.isNumberValue()) {
                        L.stack[ra] = .{ .number = nv.toFloat() + rc.toFloat() };
                    }
                    ci.savedpc += 1;
                }
            },
            .SUBK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (toNumeric(rb)) |nv| {
                    if (nv == .integer and rc == .integer) {
                        L.stack[ra] = .{ .integer = nv.integer -% rc.integer };
                    } else if (nv.isNumberValue() and rc.isNumberValue()) {
                        L.stack[ra] = .{ .number = nv.toFloat() - rc.toFloat() };
                    }
                    ci.savedpc += 1;
                }
            },
            .MULK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (toNumeric(rb)) |nv| {
                    if (nv == .integer and rc == .integer) {
                        L.stack[ra] = .{ .integer = nv.integer *% rc.integer };
                    } else if (nv.isNumberValue() and rc.isNumberValue()) {
                        L.stack[ra] = .{ .number = nv.toFloat() * rc.toFloat() };
                    }
                    ci.savedpc += 1;
                }
            },
            .MODK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (toNumeric(rb)) |nv| {
                    if (nv == .integer and rc == .integer) {
                        if (rc.integer == 0) return lua.luaG_runerror(L, "attempt to perform 'n%0'");
                        const r: i64 = if (rc.integer == -1) 0 else @rem(nv.integer, rc.integer);
                        L.stack[ra] = .{ .integer = if (r != 0 and (r ^ rc.integer) < 0) r + rc.integer else r };
                        ci.savedpc += 1;
                    } else if (nv.isNumberValue() and rc.isNumberValue()) {
                        L.stack[ra] = .{ .number = numMod(nv.toFloat(), rc.toFloat()) };
                        ci.savedpc += 1;
                    }
                }
            },
            .POWK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (toNumeric(rb)) |nv| {
                    if (nv.isNumberValue() and rc.isNumberValue()) {
                        L.stack[ra] = .{ .number = libm.getLibm().pow(nv.toFloat(), rc.toFloat()) };
                        ci.savedpc += 1;
                    }
                }
            },
            .DIVK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (toNumeric(rb)) |nv| {
                    if (nv.isNumberValue() and rc.isNumberValue()) {
                        L.stack[ra] = .{ .number = nv.toFloat() / rc.toFloat() };
                        ci.savedpc += 1;
                    }
                }
            },
            .IDIVK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (toNumeric(rb)) |nv| {
                    if (nv == .integer and rc == .integer) {
                        const ib = nv.integer;
                        const ic = rc.integer;
                        if (ic == 0) return lua.luaG_runerror(L, "attempt to divide by zero");
                        const q: i64 = if (ic == -1) 0 -% ib else @divTrunc(ib, ic);
                        const r: i64 = if (ic == -1) 0 else @rem(ib, ic);
                        L.stack[ra] = .{ .integer = if (r == 0 or (ib >= 0) == (ic >= 0)) q else q - 1 };
                        ci.savedpc += 1;
                    } else if (nv.isNumberValue() and rc.isNumberValue()) {
                        L.stack[ra] = .{ .number = @floor(nv.toFloat() / rc.toFloat()) };
                        ci.savedpc += 1;
                    }
                }
            },
            .BANDK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (toNumeric(rb)) |nv| {
                    if (nv.isNumberValue() and rc.isNumberValue()) {
                        const ib = nv.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, nv);
                        const ic = rc.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rc);
                        L.stack[ra] = .{ .integer = ib & ic };
                        ci.savedpc += 1;
                    }
                }
            },
            .BORK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (toNumeric(rb)) |nv| {
                    if (nv.isNumberValue() and rc.isNumberValue()) {
                        const ib = nv.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, nv);
                        const ic = rc.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rc);
                        L.stack[ra] = .{ .integer = ib | ic };
                        ci.savedpc += 1;
                    }
                }
            },
            .BXORK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (toNumeric(rb)) |nv| {
                    if (nv.isNumberValue() and rc.isNumberValue()) {
                        const ib = nv.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, nv);
                        const ic = rc.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rc);
                        L.stack[ra] = .{ .integer = ib ^ ic };
                        ci.savedpc += 1;
                    }
                }
            },
            .SHLI => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const sc = GETARG_sC(instruction);
                if (toNumeric(rb)) |nv| {
                    if (nv.isNumberValue()) {
                        const ib = nv.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, nv);
                        L.stack[ra] = .{ .integer = lua.luaV_shift(sc, ib) };
                        ci.savedpc += 1;
                    }
                }
            },
            .SHRI => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const sc = GETARG_sC(instruction);
                if (toNumeric(rb)) |nv| {
                    if (nv.isNumberValue()) {
                        const ib = nv.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, nv);
                        L.stack[ra] = .{ .integer = lua.luaV_shift(ib, -%sc) };
                        ci.savedpc += 1;
                    }
                }
            },
            .ADD => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .integer and rc == .integer) {
                    L.stack[ra] = .{ .integer = rb.integer +% rc.integer };
                    ci.savedpc += 1;
                } else if (toNumeric(rb)) |n1| {
                    if (toNumeric(rc)) |n2| {
                        if (n1 == .integer and n2 == .integer) {
                            L.stack[ra] = .{ .integer = n1.integer +% n2.integer };
                        } else {
                            L.stack[ra] = .{ .number = asFloat(n1) + asFloat(n2) };
                        }
                        ci.savedpc += 1;
                    }
                }
            },
            .SUB => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .integer and rc == .integer) {
                    L.stack[ra] = .{ .integer = rb.integer -% rc.integer };
                    ci.savedpc += 1;
                } else if (toNumeric(rb)) |n1| {
                    if (toNumeric(rc)) |n2| {
                        if (n1 == .integer and n2 == .integer) {
                            L.stack[ra] = .{ .integer = n1.integer -% n2.integer };
                        } else {
                            L.stack[ra] = .{ .number = asFloat(n1) - asFloat(n2) };
                        }
                        ci.savedpc += 1;
                    }
                }
            },
            .MUL => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .integer and rc == .integer) {
                    L.stack[ra] = .{ .integer = rb.integer *% rc.integer };
                    ci.savedpc += 1;
                } else if (toNumeric(rb)) |n1| {
                    if (toNumeric(rc)) |n2| {
                        if (n1 == .integer and n2 == .integer) {
                            L.stack[ra] = .{ .integer = n1.integer *% n2.integer };
                        } else {
                            L.stack[ra] = .{ .number = asFloat(n1) * asFloat(n2) };
                        }
                        ci.savedpc += 1;
                    }
                }
            },
            .MOD => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .integer and rc == .integer) {
                    if (rc.integer == 0) {
                        @branchHint(.unlikely);
                        return lua.luaG_runerror(L, "attempt to perform 'n%0'");
                    }
                    const r: i64 = if (rc.integer == -1) 0 else @rem(rb.integer, rc.integer);
                    L.stack[ra] = .{ .integer = if (r != 0 and (r ^ rc.integer) < 0) r + rc.integer else r };
                    ci.savedpc += 1;
                } else if (toNumeric(rb)) |n1| {
                    if (toNumeric(rc)) |n2| {
                        if (n1 == .integer and n2 == .integer) {
                            if (n2.integer == 0) return lua.luaG_runerror(L, "attempt to perform 'n%0'");
                            const r: i64 = if (n2.integer == -1) 0 else @rem(n1.integer, n2.integer);
                            L.stack[ra] = .{ .integer = if (r != 0 and (r ^ n2.integer) < 0) r + n2.integer else r };
                            ci.savedpc += 1;
                        } else {
                            L.stack[ra] = .{ .number = numMod(asFloat(n1), asFloat(n2)) };
                            ci.savedpc += 1;
                        }
                    }
                }
            },
            .POW => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (toNumeric(rb)) |n1| {
                    if (toNumeric(rc)) |n2| {
                        L.stack[ra] = .{ .number = libm.getLibm().pow(asFloat(n1), asFloat(n2)) };
                        ci.savedpc += 1;
                    }
                }
            },
            .DIV => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (toNumeric(rb)) |n1| {
                    if (toNumeric(rc)) |n2| {
                        L.stack[ra] = .{ .number = asFloat(n1) / asFloat(n2) };
                        ci.savedpc += 1;
                    }
                }
            },
            .IDIV => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .integer and rc == .integer) {
                    const ib = rb.integer;
                    const ic = rc.integer;
                    if (ic == 0) return lua.luaG_runerror(L, "attempt to divide by zero");
                    const q: i64 = if (ic == -1) 0 -% ib else @divTrunc(ib, ic);
                    const r: i64 = if (ic == -1) 0 else @rem(ib, ic);
                    L.stack[ra] = .{ .integer = if (r == 0 or (ib >= 0) == (ic >= 0)) q else q - 1 };
                    ci.savedpc += 1;
                } else if (rb.isNumberValue() and rc.isNumberValue()) {
                    L.stack[ra] = .{ .number = @floor(rb.toFloat() / rc.toFloat()) };
                    ci.savedpc += 1;
                } else if (toNumeric(rb)) |n1| {
                    if (toNumeric(rc)) |n2| {
                        if (n1 == .integer and n2 == .integer) {
                            const ib = n1.integer;
                            const ic = n2.integer;
                            if (ic == 0) return lua.luaG_runerror(L, "attempt to divide by zero");
                            const q: i64 = if (ic == -1) 0 -% ib else @divTrunc(ib, ic);
                            const r: i64 = if (ic == -1) 0 else @rem(ib, ic);
                            L.stack[ra] = .{ .integer = if (r == 0 or (ib >= 0) == (ic >= 0)) q else q - 1 };
                            ci.savedpc += 1;
                        } else {
                            L.stack[ra] = .{ .number = @floor(n1.toFloat() / n2.toFloat()) };
                            ci.savedpc += 1;
                        }
                    }
                }
            },
            .BAND => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb.isNumberValue() and rc.isNumberValue()) {
                    const ib = rb.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rb);
                    const ic = rc.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rc);
                    L.stack[ra] = .{ .integer = ib & ic };
                    ci.savedpc += 1;
                } else if (toNumeric(rb)) |n1| {
                    if (toNumeric(rc)) |n2| {
                        const ib = n1.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, n1);
                        const ic = n2.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, n2);
                        L.stack[ra] = .{ .integer = ib & ic };
                        ci.savedpc += 1;
                    }
                }
            },
            .BOR => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb.isNumberValue() and rc.isNumberValue()) {
                    const ib = rb.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rb);
                    const ic = rc.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rc);
                    L.stack[ra] = .{ .integer = ib | ic };
                    ci.savedpc += 1;
                } else if (toNumeric(rb)) |n1| {
                    if (toNumeric(rc)) |n2| {
                        const ib = n1.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, n1);
                        const ic = n2.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, n2);
                        L.stack[ra] = .{ .integer = ib | ic };
                        ci.savedpc += 1;
                    }
                }
            },
            .BXOR => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb.isNumberValue() and rc.isNumberValue()) {
                    const ib = rb.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rb);
                    const ic = rc.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rc);
                    L.stack[ra] = .{ .integer = ib ^ ic };
                    ci.savedpc += 1;
                } else if (toNumeric(rb)) |n1| {
                    if (toNumeric(rc)) |n2| {
                        const ib = n1.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, n1);
                        const ic = n2.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, n2);
                        L.stack[ra] = .{ .integer = ib ^ ic };
                        ci.savedpc += 1;
                    }
                }
            },
            .SHL => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb.isNumberValue() and rc.isNumberValue()) {
                    const ib = rb.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rb);
                    const ic = rc.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rc);
                    L.stack[ra] = .{ .integer = lua.luaV_shift(ib, ic) };
                    ci.savedpc += 1;
                } else if (toNumeric(rb)) |n1| {
                    if (toNumeric(rc)) |n2| {
                        const ib = n1.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, n1);
                        const ic = n2.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, n2);
                        L.stack[ra] = .{ .integer = lua.luaV_shift(ib, ic) };
                        ci.savedpc += 1;
                    }
                }
            },
            .SHR => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb.isNumberValue() and rc.isNumberValue()) {
                    const ib = rb.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rb);
                    const ic = rc.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rc);
                    L.stack[ra] = .{ .integer = lua.luaV_shift(ib, -%ic) };
                    ci.savedpc += 1;
                } else if (toNumeric(rb)) |n1| {
                    if (toNumeric(rc)) |n2| {
                        const ib = n1.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, n1);
                        const ic = n2.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, n2);
                        L.stack[ra] = .{ .integer = lua.luaV_shift(ib, -%ic) };
                        ci.savedpc += 1;
                    }
                }
            },
            .MMBIN => {
                if (ci.savedpc < 2) return error.BadBytecode;
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb_idx = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const tm = @as(ltm.TMS, @enumFromInt(GETARG_C(instruction)));
                const prev_inst = code[ci.savedpc - 2];
                const dest_idx = ci.base + @as(usize, @intCast(GETARG_A(prev_inst)));
                try ltm.luaT_trybinTM(L, &L.stack[ra_idx], &L.stack[rb_idx], dest_idx, tm);
            },
            .MMBINI => {
                if (ci.savedpc < 2) return error.BadBytecode;
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const imm = GETARG_sB(instruction);
                const tm = @as(ltm.TMS, @enumFromInt(GETARG_C(instruction)));
                const flip = GETARG_k(instruction) != 0;
                const prev_inst = code[ci.savedpc - 2];
                const dest_idx = ci.base + @as(usize, @intCast(GETARG_A(prev_inst)));
                const aux_val = lua.TValue{ .integer = imm };
                if (flip) {
                    try ltm.luaT_trybinTM(L, &aux_val, &L.stack[ra_idx], dest_idx, tm);
                } else {
                    try ltm.luaT_trybinTM(L, &L.stack[ra_idx], &aux_val, dest_idx, tm);
                }
            },
            .MMBINK => {
                if (ci.savedpc < 2) return error.BadBytecode;
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const imm = proto.k[@as(usize, @intCast(GETARG_B(instruction)))];
                const tm = @as(ltm.TMS, @enumFromInt(GETARG_C(instruction)));
                const flip = GETARG_k(instruction) != 0;
                const prev_inst = code[ci.savedpc - 2];
                const dest_idx = ci.base + @as(usize, @intCast(GETARG_A(prev_inst)));
                if (flip) {
                    try ltm.luaT_trybinTM(L, &imm, &L.stack[ra_idx], dest_idx, tm);
                } else {
                    try ltm.luaT_trybinTM(L, &L.stack[ra_idx], &imm, dest_idx, tm);
                }
            },
            .UNM => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb_idx = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const rb = L.stack[rb_idx];
                if (rb == .integer) {
                    L.stack[ra] = .{ .integer = -%rb.integer };
                } else if (rb == .number) {
                    L.stack[ra] = .{ .number = -rb.number };
                } else if (toNumeric(rb)) |nv| {
                    if (nv == .integer) {
                        L.stack[ra] = .{ .integer = -%nv.integer };
                    } else {
                        L.stack[ra] = .{ .number = -nv.number };
                    }
                } else {
                    try ltm.luaT_trybinTM(L, &L.stack[rb_idx], &L.stack[rb_idx], ra, .UNM);
                }
            },
            .BNOT => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb_idx = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const rb = L.stack[rb_idx];
                if (rb.isNumberValue()) {
                    const ib = rb.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, rb);
                    L.stack[ra] = .{ .integer = ~ib };
                } else if (toNumeric(rb)) |nv| {
                    const ib = nv.toIntegerExactOpt() orelse return lua.luaG_tointerror(L, nv);
                    L.stack[ra] = .{ .integer = ~ib };
                } else {
                    try ltm.luaT_trybinTM(L, &L.stack[rb_idx], &L.stack[rb_idx], ra, .BNOT);
                }
            },
            .NOT => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                L.stack[ra] = .{ .boolean = isFalse(rb) };
            },
            .LEN => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb_idx = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const rb = L.stack[rb_idx];
                switch (rb) {
                    .table => |t| {
                        const tm = if (t.?.metatable) |mt| ltm.luaT_gettm(mt, .LEN, L.l_G.?.tmname[@intFromEnum(ltm.TMS.LEN)].?) else null;
                        if (tm) |tm_val| {
                            _ = try ltm.luaT_callTMres(L, tm_val, &L.stack[rb_idx], &L.stack[rb_idx], ra);
                        } else {
                            L.stack[ra] = .{ .integer = @as(i64, @intCast(ltable.getn(t.?))) };
                        }
                    },
                    .string => |s| {
                        L.stack[ra] = .{ .integer = @as(i64, @intCast(s.?.s.len)) };
                    },
                    else => {
                        try ltm.luaT_trybinTM(L, &L.stack[rb_idx], &L.stack[rb_idx], ra, .LEN);
                    },
                }
            },
            .CONCAT => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const n = @as(usize, @intCast(GETARG_B(instruction)));
                if (n >= 2) {
                    var list = std.ArrayListUnmanaged(u8).empty;
                    defer list.deinit(L.allocator);
                    // Right-to-left fold mirroring luaV_concat: at each step
                    // consider the two rightmost operands; if both are (or
                    // convert to) strings, merge a maximal run of consecutive
                    // stringish operands; otherwise invoke the __concat
                    // metamethod on the pair (left operand's metatable wins).
                    // The metamethod is therefore called once per non-string
                    // group, with the correct operand pair (the original
                    // left-to-right loop wrongly paired a leading non-string
                    // operand with itself, e.g. `c..d` -> "ccd").
                    var k: usize = n;
                    while (k > 1) {
                        const lhs_idx = ra_idx + k - 2;
                        const rhs_idx = ra_idx + k - 1;
                        const lhs = L.stack[lhs_idx];
                        const rhs = L.stack[rhs_idx];
                        if (isStringish(lhs) and isStringish(rhs)) {
                            var start = k - 2;
                            while (start > 0 and isStringish(L.stack[ra_idx + start - 1])) : (start -= 1) {}
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
                            try ltm.luaT_trybinTM(L, &lhs, &rhs, lhs_idx, .CONCAT);
                            k -= 1;
                        }
                    }
                }
            },
            .CLOSE => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                try lua.closeupvals(L, ra_idx, null);
            },
            .TBC => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                try lua.checkclosemth(L, ra_idx);
                const v = L.stack[ra_idx];
                if (v != .nil and (v != .boolean or v.boolean != false)) {
                    try L.tbclist.append(L.allocator, ra_idx);
                }
            },
            .JMP => {
                const sJ = GETARG_sJ(instruction);
                ci.savedpc = @intCast(@as(i64, @intCast(ci.savedpc)) + sJ);
            },
            .EQ => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const cond = try ltm.luaT_equalobj(L, ra, rb);
                docondjump(L, ci, cond, code);
            },
            .LT => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const cond = try ltm.luaT_lt(L, ra, rb);
                docondjump(L, ci, cond, code);
            },
            .LE => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const cond = try ltm.luaT_le(L, ra, rb);
                docondjump(L, ci, cond, code);
            },
            .EQK => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const rb = proto.k[@as(usize, @intCast(GETARG_B(instruction)))];
                const cond = try ltm.luaT_equalobj(L, ra, rb);
                docondjump(L, ci, cond, code);
            },
            .EQI => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const sb = GETARG_sB(instruction);
                if (ra == .integer) {
                    docondjump(L, ci, ra.integer == sb, code);
                } else {
                    const aux_val = lua.TValue{ .integer = sb };
                    const cond = try ltm.luaT_equalobj(L, ra, aux_val);
                    docondjump(L, ci, cond, code);
                }
            },
            .LTI => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const sb = GETARG_sB(instruction);
                if (ra == .integer and GETARG_C(instruction) == 0) {
                    docondjump(L, ci, ra.integer < sb, code);
                } else {
                    const is_float = GETARG_C(instruction) != 0;
                    const aux_val = if (is_float) lua.TValue{ .number = @floatFromInt(sb) } else lua.TValue{ .integer = sb };
                    const cond = try ltm.luaT_lt(L, ra, aux_val);
                    docondjump(L, ci, cond, code);
                }
            },
            .LEI => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const sb = GETARG_sB(instruction);
                if (ra == .integer and GETARG_C(instruction) == 0) {
                    docondjump(L, ci, ra.integer <= sb, code);
                } else {
                    const is_float = GETARG_C(instruction) != 0;
                    const aux_val = if (is_float) lua.TValue{ .number = @floatFromInt(sb) } else lua.TValue{ .integer = sb };
                    const cond = try ltm.luaT_le(L, ra, aux_val);
                    docondjump(L, ci, cond, code);
                }
            },
            .GTI => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const sb = GETARG_sB(instruction);
                if (ra == .integer and GETARG_C(instruction) == 0) {
                    docondjump(L, ci, ra.integer > sb, code);
                } else {
                    const is_float = GETARG_C(instruction) != 0;
                    const aux_val = if (is_float) lua.TValue{ .number = @floatFromInt(sb) } else lua.TValue{ .integer = sb };
                    const cond = try ltm.luaT_lt(L, aux_val, ra);
                    docondjump(L, ci, cond, code);
                }
            },
            .GEI => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const sb = GETARG_sB(instruction);
                if (ra == .integer and GETARG_C(instruction) == 0) {
                    docondjump(L, ci, ra.integer >= sb, code);
                } else {
                    const is_float = GETARG_C(instruction) != 0;
                    const aux_val = if (is_float) lua.TValue{ .number = @floatFromInt(sb) } else lua.TValue{ .integer = sb };
                    const cond = try ltm.luaT_le(L, aux_val, ra);
                    docondjump(L, ci, cond, code);
                }
            },
            .TEST => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                docondjump(L, ci, !isFalse(ra), code);
            },
            .TESTSET => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const k = GETARG_k(instruction) != 0;
                if (isFalse(rb) == k) {
                    ci.savedpc += 1;
                } else {
                    L.stack[ra_idx] = rb;
                    const jmp_inst = code[ci.savedpc];
                    const sJ = GETARG_sJ(jmp_inst);
                    ci.savedpc = @intCast(@as(i64, @intCast(ci.savedpc)) + sJ + 1);
                }
            },
            .CALL => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                if (GETARG_C(instruction) == 0) {}
                const b = GETARG_B(instruction);
                const nresults = GETARG_C(instruction) - 1;
                if (b != 0) {
                    L.top = ra_idx + @as(usize, @intCast(b));
                }
                if (try lua.precall(L, ra_idx, nresults)) |new_ci| {
                    ci = new_ci;
                    cl = L.stack[ci.func].function.?.lua;
                    proto = cl.p;
                    code = proto.code;
                }
            },
            .TAILCALL => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                var b = GETARG_B(instruction);
                if (b != 0) {
                    L.top = ra_idx + @as(usize, @intCast(b));
                } else {
                    b = @intCast(L.top - ra_idx);
                }
                if (GETARG_k(instruction) != 0) {
                    try lua.closeupvals(L, ci.base, null);
                }
                var val = L.stack[ra_idx];
                var ccmt: usize = 0;
                while (val != .function) {
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
                    while (p > ra_idx) : (p -= 1) {
                        L.stack[p] = L.stack[p - 1];
                    }
                    L.top += 1;
                    L.stack[ra_idx] = tm;
                    b += 1;
                    val = L.stack[ra_idx];
                }
                ci.nextraargs += @intCast(ccmt);
                // The PF_VAHID undo delta must be computed from the frame's
                // own extra args (set by buildhiddenargs), NOT including the
                // metamethods just inserted here (the reference computes delta
                // before luaD_pretailcall). Using the inflated value makes the
                // relocated frame land one slot too low, so the tail-called
                // function's results miss the caller's expected position.
                const nextraargs_before: i32 = ci.nextraargs - @as(i32, @intCast(ccmt));
                const cl_call = val.function.?;
                switch (cl_call.*) {
                    .c => {
                        // Tail call to a C function. Unlike the `.lua` branch,
                        // we do NOT reuse the current CallInfo; instead we push
                        // a fresh frame for the C function whose `previous` is
                        // the tail-calling frame (mirroring PUC-Rio's `precallC`
                        // inside `luaD_pretailcall`). This keeps
                        // `L.ci->previous` pointing at the frame that contains
                        // the TAILCALL instruction, so error name resolution
                        // (e.g. "bad argument #1 to 'sin'") can find the called
                        // function via `funcnamefromcall`.
                        const nparams1 = GETARG_C(instruction);
                        // Run the C function via `precall`, which allocates a
                        // fresh CallInfo, handles stack growth, `__call`, and
                        // error unwinding. Its results are placed at `ra_idx`
                        // (with L.top = ra_idx + nresults).
                        _ = try lua.precall(L, ra_idx, -1);
                        const num_returned = L.top - ra_idx;
                        // Undo the PF_VAHID frame relocation before the final
                        // poscall, so the results land at the original caller's
                        // expected position (mirrors `ci->func.p -= delta`).
                        if (nparams1 != 0) {
                            ci.func -= @as(usize, @intCast(nextraargs_before + nparams1));
                            ci.base = ci.func + 1;
                        }
                        try lua.poscall(L, ci, ra_idx, num_returned);
                        const old_ci = ci;
                        if (old_ci == active_ci) {
                            L.ci = old_ci.previous;
                            lua.freeCallInfo(L, old_ci);
                            return;
                        }
                        if (old_ci.previous) |prev| {
                            ci = prev;
                            L.ci = prev;
                            lua.freeCallInfo(L, old_ci);
                            cl = L.stack[ci.func].function.?.lua;
                            proto = cl.p;
                            code = proto.code;
                        } else {
                            L.ci = null;
                            lua.freeCallInfo(L, old_ci);
                            return;
                        }
                    },
                    .lua => |lc| {
                        const count = @as(usize, @intCast(b));
                        // Correct 'ci.func' for PF_VAHID functions: buildhiddenargs
                        // relocated the frame, so restore it before reusing the ci.
                        const nparams1 = GETARG_C(instruction);
                        if (nparams1 != 0) {
                            ci.func -= @as(usize, @intCast(nextraargs_before + nparams1));
                            ci.base = ci.func + 1;
                        }
                        var k: usize = 0;
                        while (k < count) : (k += 1) {
                            L.stack[ci.func + k] = L.stack[ra_idx + k];
                        }
                        L.top = ci.func + count;
                        const num_params = lc.p.numParams;
                        const base_idx = ci.func + 1;
                        const frame_top = base_idx + lc.p.maxStackSize;
                        try lua.growStack(L, frame_top + 1);
                        const num_args_passed = L.top - base_idx;
                        if (num_args_passed < num_params) {
                            var i_arg = num_args_passed;
                            while (i_arg < num_params) : (i_arg += 1) {
                                L.stack[base_idx + i_arg] = .{ .nil = {} };
                            }
                            L.top = base_idx + num_params;
                        }
                        ci.base = base_idx;
                        ci.top = frame_top;
                        ci.savedpc = 0;
                        ci.is_tailcall = true;
                        cl = lc;
                        proto = lc.p;
                        code = proto.code;
                        // Fire the call hook for the tail-called Lua function
                        // (mirrors the reference's `startfunc` -> `luaD_hookcall`,
                        // which reports a tail call when CIST_TAIL is set).
                        if (L.hookmask & llimits.LUA_MASKCALL != 0) {
                            lua.luaD_hook(L, lua.LUA_HOOKTAILCALL, -1, 1, proto.numParams);
                        }
                    },
                }
            },
            .RETURN => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                var n: i32 = undefined;
                if (ci.clsret) {
                    // Re-execution after a __close metamethod yielded: reuse
                    // the return count saved before the interrupted poscall.
                    // Keep clsret set (it is cleared when poscall completes).
                    n = ci.nres_saved;
                } else {
                    n = GETARG_B(instruction) - 1;
                    if (n < 0) {
                        n = @intCast(L.top - ra_idx);
                    }
                    if (L.tbclist.items.len > 0) {
                        // poscall's closeupvals may yield (a __close metamethod
                        // can yield); save the return count so a re-executed
                        // RETURN can complete the pending poscall (mirrors the
                        // reference's ci->u2.nres / CIST_CLSRET).
                        ci.nres_saved = n;
                        ci.clsret = true;
                    }
                }
                const nparams1 = GETARG_C(instruction);
                if (nparams1 != 0) {
                    ci.func -= @as(usize, @intCast(@as(i32, @intCast(ci.nextraargs)) + nparams1));
                    ci.base = ci.func + 1;
                }
                const old_ci = ci;
                lua.poscall(L, old_ci, ra_idx, @intCast(n)) catch |e| {
                    if (e == error.Yield) {
                        // A __close metamethod yielded during this return. On
                        // resume the VM continues the metamethod; when it
                        // returns, this RETURN must run again to complete the
                        // poscall, so rewind savedpc to point at it.
                        ci.savedpc = @intCast(ci.savedpc - 1);
                        return error.Yield;
                    }
                    return e;
                };
                ci.clsret = false;
                if (old_ci == active_ci) {
                    L.ci = old_ci.previous;
                    lua.freeCallInfo(L, old_ci);
                    return;
                }
                if (old_ci.previous) |prev| {
                    ci = prev;
                    L.ci = prev;
                    lua.freeCallInfo(L, old_ci);
                    cl = L.stack[ci.func].function.?.lua;
                    proto = cl.p;
                    code = proto.code;
                } else {
                    L.ci = null;
                    lua.freeCallInfo(L, old_ci);
                    return;
                }
            },
            .RETURN0 => {
                const ra_idx = ci.base;
                if (isVarargFunc(L, ci)) {
                    const nparams1: i32 = @intCast(numParamsOf(L, ci) + 1);
                    ci.func -= @as(usize, @intCast(@as(i32, @intCast(ci.nextraargs)) + nparams1));
                    ci.base = ci.func + 1;
                }
                const old_ci = ci;
                try lua.poscall(L, old_ci, ra_idx, 0);
                if (old_ci == active_ci) {
                    L.ci = old_ci.previous;
                    lua.freeCallInfo(L, old_ci);
                    return;
                }
                if (old_ci.previous) |prev| {
                    ci = prev;
                    L.ci = prev;
                    lua.freeCallInfo(L, old_ci);
                    cl = L.stack[ci.func].function.?.lua;
                    proto = cl.p;
                    code = proto.code;
                } else {
                    L.ci = null;
                    lua.freeCallInfo(L, old_ci);
                    return;
                }
            },
            .RETURN1 => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                if (isVarargFunc(L, ci)) {
                    const nparams1: i32 = @intCast(numParamsOf(L, ci) + 1);
                    ci.func -= @as(usize, @intCast(@as(i32, @intCast(ci.nextraargs)) + nparams1));
                    ci.base = ci.func + 1;
                }
                const old_ci = ci;
                try lua.poscall(L, old_ci, ra_idx, 1);
                if (old_ci == active_ci) {
                    L.ci = old_ci.previous;
                    lua.freeCallInfo(L, old_ci);
                    return;
                }
                if (old_ci.previous) |prev| {
                    ci = prev;
                    L.ci = prev;
                    lua.freeCallInfo(L, old_ci);
                    cl = L.stack[ci.func].function.?.lua;
                    proto = cl.p;
                    code = proto.code;
                } else {
                    L.ci = null;
                    lua.freeCallInfo(L, old_ci);
                    return;
                }
            },
            .FORPREP => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                if (try forprep(L, ra_idx)) {
                    ci.savedpc += @as(usize, @intCast(GETARG_Bx(instruction) + 1));
                }
            },
            .FORLOOP => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                if (L.stack[ra_idx + 2] == .integer) {
                    const count = @as(u64, @bitCast(L.stack[ra_idx].integer));
                    if (count > 0) {
                        const step = L.stack[ra_idx + 1].integer;
                        const idx = L.stack[ra_idx + 2].integer;
                        L.stack[ra_idx] = .{ .integer = @bitCast(count - 1) };
                        L.stack[ra_idx + 2] = .{ .integer = idx +% step };
                        ci.savedpc -= @as(usize, @intCast(GETARG_Bx(instruction)));
                    }
                } else {
                    if (floatforloop(ra_idx, L)) {
                        ci.savedpc -= @as(usize, @intCast(GETARG_Bx(instruction)));
                    }
                }
            },
            .TFORPREP => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const temp = L.stack[ra_idx + 2];
                L.stack[ra_idx + 2] = L.stack[ra_idx + 3];
                L.stack[ra_idx + 3] = temp;
                const v = L.stack[ra_idx + 2];
                if (v != .nil and (v != .boolean or v.boolean != false)) {
                    try lua.checkclosemth(L, ra_idx + 2);
                    try L.tbclist.append(L.allocator, ra_idx + 2);
                }
                ci.savedpc = @intCast(@as(i64, @intCast(ci.savedpc)) + GETARG_Bx(instruction));
            },
            .TFORCALL => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                L.stack[ra_idx + 5] = L.stack[ra_idx + 3];
                L.stack[ra_idx + 4] = L.stack[ra_idx + 1];
                L.stack[ra_idx + 3] = L.stack[ra_idx];
                L.top = ra_idx + 6;
                const nresults = GETARG_C(instruction);
                if (try lua.precall(L, ra_idx + 3, @intCast(nresults))) |new_ci| {
                    ci = new_ci;
                    cl = L.stack[ci.func].function.?.lua;
                    proto = cl.p;
                    code = proto.code;
                }
            },
            .TFORLOOP => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                if (L.stack[ra_idx + 3] != .nil) {
                    ci.savedpc = @intCast(@as(i64, @intCast(ci.savedpc)) - GETARG_Bx(instruction));
                } else {
                    try lua.closeupvals(L, ra_idx + 2, null);
                }
            },
            .SETLIST => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const h = L.stack[ra_idx].table.?;
                var n = @as(usize, @intCast(GETARG_vB(instruction)));
                var last = @as(usize, @intCast(GETARG_vC(instruction)));
                if (n == 0) {
                    n = L.top - ra_idx - 1;
                }
                if (GETARG_k(instruction) != 0) {
                    const extra = code[ci.savedpc];
                    ci.savedpc += 1;
                    last += @as(usize, @intCast(GETARG_Ax(extra))) * 1024;
                }
                var idx = last + n;
                var k: usize = n;
                while (k > 0) : (k -= 1) {
                    const val = L.stack[ra_idx + k];
                    try ltable.setInt(h, @intCast(idx), val);
                    idx -= 1;
                }
            },
            .CLOSURE => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const bx = @as(usize, @intCast(GETARG_Bx(instruction)));
                const sub_proto = proto.p[bx];
                try pushclosure(L, sub_proto, cl.upvals, ci.base, ra_idx);
            },
            .VARARG => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const c = GETARG_C(instruction);
                const k = GETARG_k(instruction);
                const vatab: i32 = if (k != 0) GETARG_B(instruction) else -1;
                const wanted: i32 = c - 1;
                try ltm.luaT_getvarargs(L, ci, ra_idx, wanted, vatab);
            },
            .GETVARG => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rc_idx = ci.base + @as(usize, @intCast(GETARG_C(instruction)));
                try ltm.luaT_getvararg(L, ci, ra_idx, rc_idx);
            },
            .ERRNNIL => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                if (getStack(L, ra_idx) != .nil) {
                    try lua.luaG_errnnil(L, proto, GETARG_Bx(instruction));
                }
            },
            .VARARGPREP => {
                try ltm.luaT_adjustvarargs(L, ci, cl);
                // buildhiddenargs may relocate ci.func; refresh the cached
                // closure/proto/code so the loop reads the correct frame.
                cl = L.stack[ci.func].function.?.lua;
                proto = cl.p;
                code = proto.code;
            },
            .EXTRAARG => {},
        }
    }
}

fn docondjump(L: *lua.lua_State, ci: *lua.CallInfo, cond: bool, code: []Instruction) void {
    _ = L;
    const i = code[ci.savedpc - 1];
    const k = GETARG_k(i) != 0;
    if (cond != k) {
        ci.savedpc += 1;
    } else {
        const jmp_inst = code[ci.savedpc];
        const sJ = GETARG_sJ(jmp_inst);
        ci.savedpc = @intCast(@as(i64, @intCast(ci.savedpc)) + sJ + 1);
    }
}

/// True if a value can participate in string concatenation directly (string)
/// or after numeric coercion (number/integer) without a metamethod.
fn isStringish(v: lua.TValue) bool {
    return switch (v) {
        .string, .number, .integer => true,
        else => false,
    };
}

fn isFalse(val: lua.TValue) bool {
    return switch (val) {
        .nil => true,
        .boolean => |b| !b,
        else => false,
    };
}

fn pushclosure(L: *lua.lua_State, p: *lua.lua_Proto, encup: []?*lua.UpVal, base: usize, dest_idx: usize) !void {
    const lc = try L.allocator.create(lua.lua_LClosure);
    const upvals = try L.allocator.alloc(?*lua.UpVal, p.upvalues.len);
    @memset(upvals, null);
    lc.* = .{
        .p = p,
        .upvals = upvals,
    };
    for (p.upvalues, 0..) |uv_desc, k| {
        if (uv_desc.instack != 0) {
            lc.upvals[k] = try lua.findupval(L, base + uv_desc.idx);
        } else {
            lc.upvals[k] = encup[uv_desc.idx];
        }
        if (lc.upvals[k]) |uv| {
            uv.refcount += 1;
        }
    }
    const cl = try L.allocator.create(lua.lua_Closure);
    cl.* = .{ .lua = lc };
    try lua.registerGC(L, cl);
    L.stack[dest_idx] = .{ .function = cl };
}
