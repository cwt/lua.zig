// $Id: lvm.zig $
// Virtual Machine for Lua.zig (Zig port of Lua 5.5.1)
// See Copyright Notice in c_compat.zig

const std = @import("std");
const lua = @import("lua.zig");
const lprefix = @import("lprefix.zig");
const llimits = @import("llimits.zig");

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
    return @as(OpCode, @enumFromInt(@as(u7, @truncate(i))));
}

pub fn SET_OPCODE(i: *Instruction, o: OpCode) void {
    i.* = (i.* & ~@as(u32, 0x7F)) | @as(u32, @intFromEnum(o));
}

pub fn GETARG_A(i: Instruction) i32 {
    return @as(i32, @intCast((i >> 24) & 0xFF));
}
pub fn SETARG_A(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0xFF << 24)) | (@as(u32, @intCast(v & 0xFF)) << 24);
}

pub fn GETARG_B(i: Instruction) i32 {
    return @as(i32, @intCast((i >> 16) & 0xFF));
}
pub fn SETARG_B(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0xFF << 16)) | (@as(u32, @intCast(v & 0xFF)) << 16);
}

pub fn GETARG_vB(i: Instruction) i32 {
    return @as(i32, @intCast((i >> 22) & 0x3F));
}
pub fn SETARG_vB(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0x3F << 22)) | (@as(u32, @intCast(v & 0x3F)) << 22);
}

pub fn GETARG_C(i: Instruction) i32 {
    return @as(i32, @intCast((i >> 8) & 0xFF));
}
pub fn SETARG_C(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0xFF << 8)) | (@as(u32, @intCast(v & 0xFF)) << 8);
}

pub fn GETARG_vC(i: Instruction) i32 {
    return @as(i32, @intCast(i & 0xFF));
}
pub fn SETARG_vC(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0xFF)) | @as(u32, @intCast(v & 0xFF));
}

pub fn GETARG_sB(i: Instruction) i32 { return GETARG_B(i) - 128; }
pub fn SETARG_sB(i: *Instruction, v: i32) void { SETARG_B(i, v + 128); }

pub fn GETARG_sC(i: Instruction) i32 { return GETARG_C(i) - 128; }
pub fn SETARG_sC(i: *Instruction, v: i32) void { SETARG_C(i, v + 128); }

pub fn GETARG_Bx(i: Instruction) i32 { return @as(i32, @intCast((i >> 16) & 0xFFFF)); }
pub fn SETARG_Bx(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0xFFFF << 16)) | (@as(u32, @intCast(v & 0xFFFF)) << 16);
}

pub fn GETARG_Ax(i: Instruction) i32 { return @as(i32, @intCast((i >> 8) & 0xFFFFFF)); }
pub fn SETARG_Ax(i: *Instruction, v: i32) void {
    i.* = (i.* & ~@as(u32, 0xFFFFFF << 8)) | (@as(u32, @intCast(v & 0xFFFFFF)) << 8);
}

pub fn GETARG_sBx(i: Instruction) i32 { return GETARG_Bx(i) - 131072; }
pub fn SETARG_sBx(i: *Instruction, v: i32) void { SETARG_Bx(i, v + 131072); }

pub fn GETARG_sJ(i: Instruction) i32 { return GETARG_Bx(i) - 131072; }
pub fn SETARG_sJ(i: *Instruction, v: i32) void { SETARG_Bx(i, v + 131072); }

// ===================================================================
// Value representation
// ===================================================================

// ===================================================================
// VM Execution
// ===================================================================

pub fn run(L: *lua.lua_State, proto: ?*lua.lua_Proto) !void {
    const ci = &L.base_ci;
    ci.func = proto;
    ci.top = 0;

    const code: []Instruction = proto.?.*.code;
    var pc: usize = 0;

    while (pc < code.len) {
        const instruction: Instruction = code[pc];
        const op = GET_OPCODE(instruction);

        switch (op) {
            .MOVE => {
                const a = GETARG_A(instruction);
                _ = a;
                const b = GETARG_B(instruction);
                if (b >= 1 and @as(usize, @intCast(b)) <= L.top) {
                    L.stack[L.top] = L.stack[@as(usize, @intCast(b - 1))];
                }
                pc += 1;
            },
            .LOADI => {
                const a = GETARG_A(instruction);
                _ = a;
                const sb = GETARG_sB(instruction);
                L.stack[L.top] = .{ .number = @as(f64, @floatFromInt(sb)) };
                L.top = L.top + 1;
                pc += 1;
            },
            .LOADF => {
                _ = GETARG_A(instruction);
                const b = GETARG_B(instruction);
                if (b >= 1 and @as(usize, @intCast(b)) <= L.top) {
                    L.stack[L.top] = L.stack[@as(usize, @intCast(b - 1))];
                } else {
                    L.stack[L.top] = .{ .number = 0 };
                }
                L.top = L.top + 1;
                pc += 1;
            },
            .LOADK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                L.stack[L.top] = .{ .number = 0 };
                L.top = L.top + 1;
                pc += 1;
            },
            .LOADKX => {
                _ = GETARG_A(instruction);
                L.stack[L.top] = .{ .number = 0 };
                L.top = L.top + 1;
                pc += 1;
            },
            .LOADFALSE => {
                _ = GETARG_A(instruction);
                L.stack[L.top] = .{ .boolean = false };
                L.top = L.top + 1;
                pc += 1;
            },
            .LFALSESKIP => {
                _ = GETARG_A(instruction);
                L.stack[L.top] = .{ .boolean = false };
                L.top = L.top + 1;
                pc += 1;
            },
            .LOADTRUE => {
                _ = GETARG_A(instruction);
                L.stack[L.top] = .{ .boolean = true };
                L.top = L.top + 1;
                pc += 1;
            },
            .LOADNIL => {
                const a = GETARG_A(instruction);
                const b = GETARG_B(instruction);
                const start = @as(usize, @intCast(a - 1));
                const end = @as(usize, @intCast(b));
                @memset(L.stack[start..end], .{ .nil = {} });
                L.top = L.top + @as(usize, @intCast(b - a + 1));
                pc += 1;
            },
            .GETUPVAL => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .SETUPVAL => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .GETTABUP => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .GETTABLE => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .GETI => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .GETFIELD => {
                _ = GETARG_A(instruction);
                _ = GETARG_C(instruction);
                pc += 1;
            },
            .SETTABUP => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .SETTABLE => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .SETI => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .SETFIELD => {
                _ = GETARG_A(instruction);
                _ = GETARG_C(instruction);
                pc += 1;
            },
            .NEWTABLE => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                _ = GETARG_C(instruction);
                L.stack[L.top] = .{ .nil = {} };
                L.top = L.top + 1;
                pc += 1;
            },
            .SELF => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .ADDI => {
                _ = GETARG_A(instruction);
                const sb = GETARG_sB(instruction);
                if (L.stack[L.top - 1] == .number) {
                    L.stack[L.top - 1] = .{ .number = L.stack[L.top - 1].number + @as(f64, @floatFromInt(sb)) };
                }
                pc += 1;
            },
            .ADDK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .SUBK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .MULK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .MODK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .POWK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .DIVK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .IDIVK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .BANDK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .BORK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .BXORK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .SHLI => {
                _ = GETARG_A(instruction);
                _ = GETARG_sB(instruction);
                pc += 1;
            },
            .SHRI => {
                _ = GETARG_A(instruction);
                _ = GETARG_sB(instruction);
                pc += 1;
            },
            .ADD => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .SUB => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .MUL => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .MOD => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .POW => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .DIV => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .IDIV => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .BAND => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .BOR => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .BXOR => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .SHL => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .SHR => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .MMBIN => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .MMBINI => {
                _ = GETARG_A(instruction);
                _ = GETARG_sB(instruction);
                pc += 1;
            },
            .MMBINK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .UNM => {
                _ = GETARG_A(instruction);
                if (L.stack[L.top - 1] == .number) {
                    L.stack[L.top - 1] = .{ .number = -(L.stack[L.top - 1].number) };
                }
                pc += 1;
            },
            .BNOT => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .NOT => {
                _ = GETARG_A(instruction);
                if (L.stack[L.top - 1] == .boolean) {
                    L.stack[L.top - 1] = .{ .boolean = !L.stack[L.top - 1].boolean };
                } else {
                    L.stack[L.top - 1] = .{ .boolean = false };
                }
                pc += 1;
            },
            .LEN => {
                _ = GETARG_A(instruction);
                pc += 1;
            },
            .CONCAT => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .CLOSE => {
                _ = GETARG_A(instruction);
                pc += 1;
            },
            .TBC => {
                _ = GETARG_A(instruction);
                pc += 1;
            },
            .JMP => {
                const a = GETARG_A(instruction);
                const jump = GETARG_sBx(instruction);
                pc = @as(usize, @intCast(@as(i64, @as(i64, a) + jump)));
            },
            .EQ => {
                const a = GETARG_A(instruction);
                const b = GETARG_B(instruction);
                const result = lua.lua_compare(L, a, b, 0);
                L.stack[L.top] = .{ .boolean = result == 1 };
                L.top = L.top + 1;
                pc += 1;
            },
            .LT => {
                const a = GETARG_A(instruction);
                const b = GETARG_B(instruction);
                const result = lua.lua_compare(L, a, b, 1);
                L.stack[L.top] = .{ .boolean = result == 1 };
                L.top = L.top + 1;
                pc += 1;
            },
            .LE => {
                const a = GETARG_A(instruction);
                const b = GETARG_B(instruction);
                const result = lua.lua_compare(L, a, b, 2);
                L.stack[L.top] = .{ .boolean = result == 1 };
                L.top = L.top + 1;
                pc += 1;
            },
            .EQK => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .EQI => {
                const a = GETARG_A(instruction);
                const sb = GETARG_sB(instruction);
                const result = lua.lua_compare(L, a, @as(i32, sb), 0);
                L.stack[L.top] = .{ .boolean = result == 1 };
                L.top = L.top + 1;
                pc += 1;
            },
            .LTI => {
                const a = GETARG_A(instruction);
                const sb = GETARG_sB(instruction);
                const result = lua.lua_compare(L, a, @as(i32, sb), 1);
                L.stack[L.top] = .{ .boolean = result == 1 };
                L.top = L.top + 1;
                pc += 1;
            },
            .LEI => {
                const a = GETARG_A(instruction);
                const sb = GETARG_sB(instruction);
                const result = lua.lua_compare(L, a, @as(i32, sb), 2);
                L.stack[L.top] = .{ .boolean = result == 1 };
                L.top = L.top + 1;
                pc += 1;
            },
            .GTI => {
                const a = GETARG_A(instruction);
                const sb = GETARG_sB(instruction);
                const result = lua.lua_compare(L, a, @as(i32, sb), 1);
                L.stack[L.top] = .{ .boolean = result == 1 };
                L.top = L.top + 1;
                pc += 1;
            },
            .GEI => {
                const a = GETARG_A(instruction);
                const sb = GETARG_sB(instruction);
                const result = lua.lua_compare(L, a, @as(i32, sb), 2);
                L.stack[L.top] = .{ .boolean = result == 1 };
                L.top = L.top + 1;
                pc += 1;
            },
            .TEST => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .TESTSET => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .CALL => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                _ = GETARG_C(instruction);
                pc += 1;
            },
            .TAILCALL => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                _ = GETARG_C(instruction);
                pc += 1;
            },
            .RETURN => {
                const a = GETARG_A(instruction);
                L.top = @as(usize, @intCast(a));
                pc += 1;
            },
            .RETURN0 => {
                const a = GETARG_A(instruction);
                L.top = @as(usize, @intCast(a));
                pc += 1;
            },
            .RETURN1 => {
                const a = GETARG_A(instruction);
                L.top = @as(usize, @intCast(a));
                pc += 1;
            },
            .FORLOOP => {
                _ = GETARG_A(instruction);
                _ = GETARG_sB(instruction);
                pc += 1;
            },
            .FORPREP => {
                _ = GETARG_A(instruction);
                _ = GETARG_sB(instruction);
                pc += 1;
            },
            .TFORPREP => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                _ = GETARG_C(instruction);
                pc += 1;
            },
            .TFORCALL => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                _ = GETARG_C(instruction);
                pc += 1;
            },
            .TFORLOOP => {
                _ = GETARG_A(instruction);
                _ = GETARG_sB(instruction);
                _ = GETARG_sC(instruction);
                pc += 1;
            },
            .SETLIST => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                _ = GETARG_C(instruction);
                pc += 1;
            },
            .CLOSURE => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .VARARG => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .GETVARG => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
            .ERRNNIL => {
                _ = GETARG_A(instruction);
                L.stack[L.top] = .{ .nil = {} };
                L.top = L.top + 1;
                pc += 1;
            },
            .VARARGPREP => {
                const a = GETARG_A(instruction);
                @memset(L.stack[L.top..], .{ .nil = {} });
                L.top = L.top + @as(usize, @intCast(a));
                pc += 1;
            },
            .EXTRAARG => {
                _ = GETARG_A(instruction);
                _ = GETARG_B(instruction);
                pc += 1;
            },
        }
    }

    if (L.top > 0) {
        L.top = 0;
    }
}
