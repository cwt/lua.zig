---
type: api_spec
title: Virtual Machine Design
description: Lua 5.5.1 instruction formats, opcode semantics, decode helpers, and the execution model in lvm.zig.
tags: [vm, opcodes, instructions, lvm]
timestamp: 2026-07-10T00:00:00Z
---

## Instruction Formats

Each instruction is a `u32` with the opcode in the low 7 bits:

```
        3 3 2 2 2 2 2 2 2 2 2 2 1 1 1 1 1 1 1 1 1 1 0 0 0 0 0 0 0 0 0 0
        1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0 9 8 7 6 5 4 3 2 1 0
iABC          C(8)     |      B(8)     |k|     A(8)      |   Op(7)     |
ivABC         vC(10)     |     vB(6)   |k|     A(8)      |   Op(7)     |
iABx                Bx(17)               |     A(8)      |   Op(7)     |
iAsBx              sBx (signed)(17)      |     A(8)      |   Op(7)     |
iAx                           Ax(25)                     |   Op(7)     |
isJ                           sJ (signed)(25)            |   Op(7)     |
```

## Decode Helpers (`src/lvm.zig`)

| Function | Extracts | Width | Signed? |
|----------|----------|-------|---------|
| `GETARG_A` | Register index A | 8 bits | No |
| `GETARG_B` | Register/constant B | 8 bits | No |
| `GETARG_C` | Register/constant C | 8 bits | No |
| `GETARG_vB` | Variant B | 6 bits | No |
| `GETARG_vC` | Variant C | 10 bits | No |
| `GETARG_sB` | Signed immediate B | 8 bits | Excess-128 |
| `GETARG_sC` | Signed immediate C | 8 bits | Excess-128 |
| `GETARG_Bx` | Extended constant index | 17 bits | No |
| `GETARG_sBx` | Signed offset | 17 bits | Excess-131072 |
| `GETARG_Ax` | Extended A | 25 bits | No |
| `GETARG_sJ` | Signed long jump | 25 bits | Excess-131072 |

SETARG_* helpers encode values back into an instruction.

## Opcode Enum

The `OpCode` enum mirrors `lua/lopcodes.h`:

```
MOVE, LOADI, LOADF, LOADK, LOADKX, LOADFALSE, LFALSESKIP, LOADTRUE, LOADNIL,
GETUPVAL, SETUPVAL, GETTABUP, GETTABLE, GETI, GETFIELD,
SETTABUP, SETTABLE, SETI, SETFIELD, NEWTABLE, SELF,
ADDI, ADDK, SUBK, MULK, MODK, POWK, DIVK, IDIVK,
BANDK, BORK, BXORK, SHLI, SHRI,
ADD, SUB, MUL, MOD, POW, DIV, IDIV, BAND, BOR, BXOR, SHL, SHR,
MMBIN, MMBINI, MMBINK,
UNM, BNOT, NOT, LEN, CONCAT, CLOSE, TBC, JMP,
EQ, LT, LE, EQK, EQI, LTI, LEI, GTI, GEI,
TEST, TESTSET, CALL, TAILCALL, RETURN, RETURN0, RETURN1,
FORLOOP, FORPREP, TFORPREP, TFORCALL, TFORLOOP,
SETLIST, CLOSURE, VARARG, GETVARG, ERRNNIL, VARARGPREP, EXTRAARG
```

## Execution Model

`lvm.run` takes `(*lua_State, ?*lua_Proto)` and executes instructions in a loop:

```zig
pub fn run(L: *lua.lua_State, proto: ?*lua.lua_Proto) !void {
    const code: []Instruction = proto.?.*.code;
    var pc: usize = 0;

    while (pc < code.len) {
        const instruction: Instruction = code[pc];
        const op = GET_OPCODE(instruction);

        switch (op) {
            .MOVE => { /* ... */ pc += 1; },
            // ... all other opcodes
        }
    }
}
```

### Current Status

All opcodes are defined. Most are no-ops (decode arguments but do nothing). The following have partial implementations:

| Opcode | Status | Behavior |
|--------|--------|----------|
| MOVE | Partially working | Copies value; ignores A register target |
| LOADI | Partially working | Pushes signed immediate to stack top |
| LOADF | Partially working | Copies register or pushes 0 |
| LOADK/LOADKX | Stub | Pushes 0 (no constant pool) |
| LOADFALSE/LFALSESKIP | Working | Pushes false |
| LOADTRUE | Working | Pushes true |
| LOADNIL | Partially working | Nil-fills range |
| ADDI | Partially working | Adds immediate to top value |
| UNM | Working | Negates top number |
| NOT | Working | Negates top boolean |
| JMP | Partially working | Jumps; A is additive offset |
| EQ/LT/LE + variants | Working | Comparison, pushes boolean |
| RETURN/RETURN0/RETURN1 | Partially working | Sets L.top to A |
| VARARGPREP | Partially working | Nil-fills A slots |
| ERRNNIL | Working | Pushes nil |

## Required Work for Phase D

1. **Constant pool access**: LOADK/LOADKX must read from `Proto.k[]`
2. **Register-based semantics**: most opcodes use A as destination register, not stack push
3. **Call management**: CALL/TAILCALL must invoke `lua_CFunction` or recurse into `run`
4. **Closure creation**: CLOSURE must create `lua_Closure.lua` from `Proto`
5. **Upvalue access**: GETUPVAL/SETUPVAL must use `CallInfo` upvalue array
6. **Table ops**: GETTABLE etc. depend on Phase B table implementation
7. **Metamethods**: MMBIN/MMBINI/MMBINK dispatch to `luaT_*` when types mismatch
8. **Varargs**: VARARG/GETVARG depend on call frame setup
