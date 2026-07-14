// $Id: lvm.zig $
// Virtual Machine for Lua.zig (Zig port of Lua 5.5.1)
// See Copyright Notice in c_compat.zig

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");
const ltm = @import("ltm.zig");
const libm = @import("libm.zig");

const PF_VAHID = 1; // function has hidden vararg arguments

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
// Lua 5.5.1 instruction format (u32):
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

pub fn GETARG_sB(i: Instruction) i32 { return GETARG_B(i) - 127; }
pub fn SETARG_sB(i: *Instruction, v: i32) void { SETARG_B(i, v + 127); }

pub fn GETARG_sC(i: Instruction) i32 { return GETARG_C(i) - 127; }
pub fn SETARG_sC(i: *Instruction, v: i32) void { SETARG_C(i, v + 127); }

pub fn GETARG_Bx(i: Instruction) i32 { return @as(i32, @intCast((i >> 15) & 0x1FFFF)); }
pub fn SETARG_Bx(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0x1FFFF << 15)) | (@as(u32, @intCast(v & 0x1FFFF)) << 15);
}

pub fn GETARG_Ax(i: Instruction) i32 { return @as(i32, @intCast((i >> 7) & 0x1FFFFFF)); }
pub fn SETARG_Ax(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0x1FFFFFF << 7)) | (@as(u32, @intCast(v & 0x1FFFFFF)) << 7);
}

pub fn GETARG_sBx(i: Instruction) i32 { return GETARG_Bx(i) - 65535; }
pub fn SETARG_sBx(i: *Instruction, v: i32) void { SETARG_Bx(i, v + 65535); }

pub fn GETARG_sJ(i: Instruction) i32 {
    const val = (i >> 7) & 0x1FFFFFF;
    return @as(i32, @intCast(val)) - 16777215;
}
pub fn SETARG_sJ(i: *Instruction, v: i32) void {
    const val = @as(u32, @intCast(v + 16777215)) & 0x1FFFFFF;
    i.* = (i.* & ~@as(u32, 0x1FFFFFF << 7)) | (val << 7);
}

// -------------------------------------------------------------------
// Argument-limit constants (consistent with the encoding above)
// -------------------------------------------------------------------
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
pub const MAX_FSTACK = 250;
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

    while (ci.savedpc < code.len) {
        const instruction: Instruction = code[ci.savedpc];
        const op = GET_OPCODE(instruction);
        ci.savedpc += 1;

        switch (op) {
            .MOVE => {
                const a = GETARG_A(instruction);
                const b = GETARG_B(instruction);
                L.stack[ci.base + @as(usize, @intCast(a))] = L.stack[ci.base + @as(usize, @intCast(b))];
            },
            .LOADI => {
                const a = GETARG_A(instruction);
                const sbx = GETARG_sBx(instruction);
                L.stack[ci.base + @as(usize, @intCast(a))] = .{ .number = @as(f64, @floatFromInt(sbx)) };
            },
            .LOADF => {
                const a = GETARG_A(instruction);
                const sbx = GETARG_sBx(instruction);
                L.stack[ci.base + @as(usize, @intCast(a))] = .{ .number = @as(f64, @floatFromInt(sbx)) };
            },
            .LOADK => {
                const a = GETARG_A(instruction);
                const bx = GETARG_Bx(instruction);
                L.stack[ci.base + @as(usize, @intCast(a))] = proto.k[@as(usize, @intCast(bx))];
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
                L.stack[ci.base + a] = if (uv.index) |idx| L.stack[idx] else uv.value;
            },
            .SETUPVAL => {
                const a = @as(usize, @intCast(GETARG_A(instruction)));
                const b = @as(usize, @intCast(GETARG_B(instruction)));
                const uv = cl.upvals[b].?;
                const val = L.stack[ci.base + a];
                if (uv.index) |idx| {
                    L.stack[idx] = val;
                } else {
                    uv.value = val;
                }
            },
            .GETTABUP => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = @as(usize, @intCast(GETARG_B(instruction)));
                const c = @as(usize, @intCast(GETARG_C(instruction)));
                const uv = cl.upvals[b].?;
                const table_val = if (uv.index) |idx| L.stack[idx] else uv.value;
                const key = proto.k[c];
                try ltm.luaV_gettable(L, table_val, key, a);
            },
            .GETTABLE => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const c = ci.base + @as(usize, @intCast(GETARG_C(instruction)));
                const table_val = L.stack[b];
                const key = L.stack[c];
                try ltm.luaV_gettable(L, table_val, key, a);
            },
            .GETI => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const c = GETARG_C(instruction);
                const table_val = L.stack[b];
                const int_key = lua.TValue{ .number = @floatFromInt(c) };
                try ltm.luaV_gettable(L, table_val, int_key, a);
            },
            .GETFIELD => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const c = @as(usize, @intCast(GETARG_C(instruction)));
                const table_val = L.stack[b];
                const key = proto.k[c];
                try ltm.luaV_gettable(L, table_val, key, a);
            },
            .SETTABUP => {
                const a = @as(usize, @intCast(GETARG_A(instruction)));
                const b = @as(usize, @intCast(GETARG_B(instruction)));
                const c = @as(usize, @intCast(GETARG_C(instruction)));
                const uv = cl.upvals[a].?;
                const table_val = if (uv.index) |idx| L.stack[idx] else uv.value;
                const key = proto.k[b];
                const val = if (GETARG_k(instruction) != 0) proto.k[c] else L.stack[ci.base + c];
                try ltm.luaV_settable(L, table_val, key, val);
            },
            .SETTABLE => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const c = @as(usize, @intCast(GETARG_C(instruction)));
                const table_val = L.stack[a];
                const key = L.stack[b];
                const val = if (GETARG_k(instruction) != 0) proto.k[c] else L.stack[ci.base + c];
                try ltm.luaV_settable(L, table_val, key, val);
            },
            .SETI => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = GETARG_B(instruction);
                const c = @as(usize, @intCast(GETARG_C(instruction)));
                const table_val = L.stack[a];
                const val = if (GETARG_k(instruction) != 0) proto.k[c] else L.stack[ci.base + c];
                const int_key = lua.TValue{ .number = @floatFromInt(b) };
                try ltm.luaV_settable(L, table_val, int_key, val);
            },
            .SETFIELD => {
                const a = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const b = @as(usize, @intCast(GETARG_B(instruction)));
                const c = @as(usize, @intCast(GETARG_C(instruction)));
                const table_val = L.stack[a];
                const key = proto.k[b];
                const val = if (GETARG_k(instruction) != 0) proto.k[c] else L.stack[ci.base + c];
                try ltm.luaV_settable(L, table_val, key, val);
            },
            .NEWTABLE => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const vB = @as(usize, @intCast(GETARG_vB(instruction)));
                const vC = @as(usize, @intCast(GETARG_vC(instruction)));
                var narr = vC;
                if (GETARG_k(instruction) != 0) {
                    const extra = code[ci.savedpc];
                    ci.savedpc += 1;
                    narr += @as(usize, @intCast(GETARG_Ax(extra))) * 1024;
                }
                const nrec = if (vB > 0) @as(usize, 1) << @as(u5, @intCast(vB - 1)) else 0;
                const tab = try ltable.createTable(L.allocator, narr, nrec);
                try lua.registerGC(L, tab);
                L.stack[ra_idx] = .{ .table = tab };
            },
            .SELF => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const key = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                L.stack[ra_idx + 1] = rb;
                try ltm.luaV_gettable(L, rb, key, ra_idx);
            },
            .ADDI => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const sc = GETARG_sC(instruction);
                if (rb == .number) {
                    L.stack[ra] = .{ .number = rb.number + @as(f64, @floatFromInt(sc)) };
                    ci.savedpc += 1;
                }
            },
            .ADDK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = rb.number + rc.number };
                    ci.savedpc += 1;
                }
            },
            .SUBK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = rb.number - rc.number };
                    ci.savedpc += 1;
                }
            },
            .MULK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = rb.number * rc.number };
                    ci.savedpc += 1;
                }
            },
            .MODK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = rb.number - @floor(rb.number / rc.number) * rc.number };
                    ci.savedpc += 1;
                }
            },
            .POWK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = libm.getLibm().pow(rb.number, rc.number) };
                    ci.savedpc += 1;
                }
            },
            .DIVK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = rb.number / rc.number };
                    ci.savedpc += 1;
                }
            },
            .IDIVK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = @floor(rb.number / rc.number) };
                    ci.savedpc += 1;
                }
            },
            .BANDK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    const ib = @as(i64, @intFromFloat(rb.number));
                    const ic = @as(i64, @intFromFloat(rc.number));
                    L.stack[ra] = .{ .number = @floatFromInt(ib & ic) };
                    ci.savedpc += 1;
                }
            },
            .BORK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    const ib = @as(i64, @intFromFloat(rb.number));
                    const ic = @as(i64, @intFromFloat(rc.number));
                    L.stack[ra] = .{ .number = @floatFromInt(ib | ic) };
                    ci.savedpc += 1;
                }
            },
            .BXORK => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = proto.k[@as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    const ib = @as(i64, @intFromFloat(rb.number));
                    const ic = @as(i64, @intFromFloat(rc.number));
                    L.stack[ra] = .{ .number = @floatFromInt(ib ^ ic) };
                    ci.savedpc += 1;
                }
            },
            .SHLI => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const sc = GETARG_sC(instruction);
                const shift: u6 = @intCast(sc);
                if (rb == .number) {
                    const ib = @as(i64, @intFromFloat(rb.number));
                    L.stack[ra] = .{ .number = @floatFromInt(ib << shift) };
                    ci.savedpc += 1;
                }
            },
            .SHRI => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const sc = GETARG_sC(instruction);
                const shift: u6 = @intCast(sc);
                if (rb == .number) {
                    const ib = @as(i64, @intFromFloat(rb.number));
                    L.stack[ra] = .{ .number = @floatFromInt(ib >> shift) };
                    ci.savedpc += 1;
                }
            },
            .ADD => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = rb.number + rc.number };
                    ci.savedpc += 1;
                }
            },
            .SUB => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = rb.number - rc.number };
                    ci.savedpc += 1;
                }
            },
            .MUL => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = rb.number * rc.number };
                    ci.savedpc += 1;
                }
            },
            .MOD => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = rb.number - @floor(rb.number / rc.number) * rc.number };
                    ci.savedpc += 1;
                }
            },
            .POW => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = libm.getLibm().pow(rb.number, rc.number) };
                    ci.savedpc += 1;
                }
            },
            .DIV => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = rb.number / rc.number };
                    ci.savedpc += 1;
                }
            },
            .IDIV => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    L.stack[ra] = .{ .number = @floor(rb.number / rc.number) };
                    ci.savedpc += 1;
                }
            },
            .BAND => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    const ib = @as(i64, @intFromFloat(rb.number));
                    const ic = @as(i64, @intFromFloat(rc.number));
                    L.stack[ra] = .{ .number = @floatFromInt(ib & ic) };
                    ci.savedpc += 1;
                }
            },
            .BOR => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    const ib = @as(i64, @intFromFloat(rb.number));
                    const ic = @as(i64, @intFromFloat(rc.number));
                    L.stack[ra] = .{ .number = @floatFromInt(ib | ic) };
                    ci.savedpc += 1;
                }
            },
            .BXOR => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    const ib = @as(i64, @intFromFloat(rb.number));
                    const ic = @as(i64, @intFromFloat(rc.number));
                    L.stack[ra] = .{ .number = @floatFromInt(ib ^ ic) };
                    ci.savedpc += 1;
                }
            },
            .SHL => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    const ib = @as(i64, @intFromFloat(rb.number));
                    const ic = @as(i64, @intFromFloat(rc.number));
                    L.stack[ra] = .{ .number = @floatFromInt(lua.luaV_shift(ib, ic)) };
                    ci.savedpc += 1;
                }
            },
            .SHR => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                const rc = L.stack[ci.base + @as(usize, @intCast(GETARG_C(instruction)))];
                if (rb == .number and rc == .number) {
                    const ib = @as(i64, @intFromFloat(rb.number));
                    const ic = @as(i64, @intFromFloat(rc.number));
                    L.stack[ra] = .{ .number = @floatFromInt(lua.luaV_shift(ib, -ic)) };
                    ci.savedpc += 1;
                }
            },
            .MMBIN => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb_idx = ci.base + @as(usize, @intCast(GETARG_B(instruction)));
                const tm = @as(ltm.TMS, @enumFromInt(GETARG_C(instruction)));
                const prev_inst = code[ci.savedpc - 2];
                const dest_idx = ci.base + @as(usize, @intCast(GETARG_A(prev_inst)));
                try ltm.luaT_trybinTM(L, L.stack[ra_idx], L.stack[rb_idx], dest_idx, tm);
            },
            .MMBINI => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const imm = GETARG_sB(instruction);
                const tm = @as(ltm.TMS, @enumFromInt(GETARG_C(instruction)));
                const flip = GETARG_k(instruction) != 0;
                const prev_inst = code[ci.savedpc - 2];
                const dest_idx = ci.base + @as(usize, @intCast(GETARG_A(prev_inst)));
                const aux_val = lua.TValue{ .number = @floatFromInt(imm) };
                const p1 = if (flip) aux_val else L.stack[ra_idx];
                const p2 = if (flip) L.stack[ra_idx] else aux_val;
                try ltm.luaT_trybinTM(L, p1, p2, dest_idx, tm);
            },
            .MMBINK => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const imm = proto.k[@as(usize, @intCast(GETARG_B(instruction)))];
                const tm = @as(ltm.TMS, @enumFromInt(GETARG_C(instruction)));
                const flip = GETARG_k(instruction) != 0;
                const prev_inst = code[ci.savedpc - 2];
                const dest_idx = ci.base + @as(usize, @intCast(GETARG_A(prev_inst)));
                const p1 = if (flip) imm else L.stack[ra_idx];
                const p2 = if (flip) L.stack[ra_idx] else imm;
                try ltm.luaT_trybinTM(L, p1, p2, dest_idx, tm);
            },
            .UNM => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                if (rb == .number) {
                    L.stack[ra] = .{ .number = -rb.number };
                } else {
                    try ltm.luaT_trybinTM(L, rb, rb, ra, .UNM);
                }
            },
            .BNOT => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                if (rb == .number) {
                    const ib = @as(i64, @intFromFloat(rb.number));
                    L.stack[ra] = .{ .number = @floatFromInt(~ib) };
                } else {
                    try ltm.luaT_trybinTM(L, rb, rb, ra, .BNOT);
                }
            },
            .NOT => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                L.stack[ra] = .{ .boolean = isFalse(rb) };
            },
            .LEN => {
                const ra = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const rb = L.stack[ci.base + @as(usize, @intCast(GETARG_B(instruction)))];
                switch (rb) {
                    .table => |t| {
                        const tm = if (t.?.metatable) |mt| ltm.luaT_gettm(mt, .LEN, L.l_G.?.tmname[@intFromEnum(ltm.TMS.LEN)].?) else null;
                        if (tm) |tm_val| {
                            _ = try ltm.luaT_callTMres(L, tm_val, rb, rb, ra);
                        } else {
                            L.stack[ra] = .{ .number = @floatFromInt(ltable.getn(t.?)) };
                        }
                    },
                    .string => |s| {
                        L.stack[ra] = .{ .number = @floatFromInt(s.?.s.len) };
                    },
                    else => {
                        try ltm.luaT_trybinTM(L, rb, rb, ra, .LEN);
                    },
                }
            },
            .CONCAT => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const n = @as(usize, @intCast(GETARG_B(instruction)));
                var list = std.ArrayListUnmanaged(u8).empty;
                defer list.deinit(L.allocator);
                var k: usize = 0;
                while (k < n) : (k += 1) {
                    const val = L.stack[ra_idx + k];
                    switch (val) {
                        .string => |s| try list.appendSlice(L.allocator, s.?.s),
                        .number => |num| {
                            var buf: [64]u8 = undefined;
                            const slice = std.fmt.bufPrint(&buf, "{d}", .{num}) catch "";
                            try list.appendSlice(L.allocator, slice);
                        },
                        else => return error.RuntimeError,
                    }
                }
                const g = L.l_G orelse return error.NoGlobalState;
                const ts = try lstring.luaS_new(g.allocator, &g.strt, g.seed, list.items);
                L.stack[ra_idx] = .{ .string = ts };
            },
            .CLOSE => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                lua.closeupvals(L, ra_idx);
            },
            .TBC => {},
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
                const aux_val = lua.TValue{ .number = @floatFromInt(sb) };
                const cond = try ltm.luaT_equalobj(L, ra, aux_val);
                docondjump(L, ci, cond, code);
            },
            .LTI => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const sb = GETARG_sB(instruction);
                const aux_val = lua.TValue{ .number = @floatFromInt(sb) };
                const cond = try ltm.luaT_lt(L, ra, aux_val);
                docondjump(L, ci, cond, code);
            },
            .LEI => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const sb = GETARG_sB(instruction);
                const aux_val = lua.TValue{ .number = @floatFromInt(sb) };
                const cond = try ltm.luaT_le(L, ra, aux_val);
                docondjump(L, ci, cond, code);
            },
            .GTI => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const sb = GETARG_sB(instruction);
                const aux_val = lua.TValue{ .number = @floatFromInt(sb) };
                const cond = try ltm.luaT_lt(L, aux_val, ra);
                docondjump(L, ci, cond, code);
            },
            .GEI => {
                const ra = L.stack[ci.base + @as(usize, @intCast(GETARG_A(instruction)))];
                const sb = GETARG_sB(instruction);
                const aux_val = lua.TValue{ .number = @floatFromInt(sb) };
                const cond = try ltm.luaT_le(L, aux_val, ra);
                docondjump(L, ci, cond, code);
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
                const val = L.stack[ra_idx];
                if (val != .function) return error.NotAFunction;
                const cl_call = val.function.?;
                switch (cl_call.*) {
                    .c => |cc| {
                        // Tail call to a C function reuses the current CallInfo.
                        // Move the called function and its arguments down to the
                        // frame base (mirroring the `.lua` branch below and PUC-Rio's
                        // memmove of `ra` into `ci->func`). This discards the
                        // tail-calling function's own frame so the C function's
                        // results land exactly where the caller expects them
                        // (`func_idx`), instead of above the discarded frame.
                        const nparams1 = GETARG_C(instruction);
                        if (nparams1 != 0) {
                            // Caller is PF_VAHID: buildhiddenargs relocated the
                            // frame; undo it before re-pointing ci at ra_idx.
                            ci.func -= @as(usize, @intCast(@as(i32, @intCast(ci.nextraargs)) + nparams1));
                        }
                        var k2: usize = 0;
                        while (k2 < @as(usize, @intCast(b))) : (k2 += 1) {
                            L.stack[ci.func + k2] = L.stack[ra_idx + k2];
                        }
                        ci.base = ci.func + 1;
                        L.top = ci.func + @as(usize, @intCast(b));
                        ci.top = L.top + 20;
                        const n = try cc.f(L);
                        const num_returned = @as(usize, @intCast(n));
                        const first_result = L.top - num_returned;
                        lua.poscall(L, ci, first_result, num_returned);
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
                        lua.closeupvals(L, ci.base);
                        const count = @as(usize, @intCast(b));
                        // Correct 'ci.func' for PF_VAHID functions: buildhiddenargs
                        // relocated the frame, so restore it before reusing the ci.
                        const nparams1 = GETARG_C(instruction);
                        if (nparams1 != 0) {
                            ci.func -= @as(usize, @intCast(@as(i32, @intCast(ci.nextraargs)) + nparams1));
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
                        if (frame_top >= L.stack.len) {
                            const old_len = L.stack.len;
                            const new_len = @max(L.stack.len * 2, frame_top + 10);
                            L.stack = try L.allocator.realloc(L.stack, new_len);
                            @memset(L.stack[old_len..], .{ .nil = {} });
                            L.stack_last = L.stack.len - 1;
                        }
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
                        cl = lc;
                        proto = lc.p;
                        code = proto.code;
                    },
                }
            },
            .RETURN => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                var n = GETARG_B(instruction) - 1;
                if (n < 0) {
                    n = @intCast(L.top - ra_idx);
                }
                const nparams1 = GETARG_C(instruction);
                if (nparams1 != 0) {
                    ci.func -= @as(usize, @intCast(@as(i32, @intCast(ci.nextraargs)) + nparams1));
                    ci.base = ci.func + 1;
                }
                const old_ci = ci;
                lua.poscall(L, old_ci, ra_idx, @intCast(n));
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
                lua.poscall(L, old_ci, ra_idx, 0);
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
                lua.poscall(L, old_ci, ra_idx, 1);
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
                const init_val = L.stack[ra_idx].number;
                const limit_val = L.stack[ra_idx + 1].number;
                const step_val = L.stack[ra_idx + 2].number;
                if (step_val == 0.0) return error.RuntimeError;
                if ((step_val > 0.0 and limit_val < init_val) or (step_val < 0.0 and init_val < limit_val)) {
                    ci.savedpc += @as(usize, @intCast(GETARG_Bx(instruction) + 1));
                } else {
                    L.stack[ra_idx] = .{ .number = limit_val };
                    L.stack[ra_idx + 1] = .{ .number = step_val };
                    L.stack[ra_idx + 2] = .{ .number = init_val };
                }
            },
            .FORLOOP => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const step_val = L.stack[ra_idx + 1].number;
                const limit_val = L.stack[ra_idx].number;
                const idx = L.stack[ra_idx + 2].number + step_val;
                if ((step_val > 0.0 and idx <= limit_val) or (step_val < 0.0 and limit_val <= idx)) {
                    L.stack[ra_idx + 2] = .{ .number = idx };
                    ci.savedpc -= @as(usize, @intCast(GETARG_Bx(instruction)));
                }
            },
            .TFORPREP => {
                const ra_idx = ci.base + @as(usize, @intCast(GETARG_A(instruction)));
                const temp = L.stack[ra_idx + 2];
                L.stack[ra_idx + 2] = L.stack[ra_idx + 3];
                L.stack[ra_idx + 3] = temp;
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
                if (L.stack[ra_idx] != .nil) {
                    return error.RuntimeError;
                }
            },
            .VARARGPREP => {
                try ltm.luaT_adjustvarargs(L, ci, cl);
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
