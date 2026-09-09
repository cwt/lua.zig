---
type: api_spec
title: Virtual Machine Design
description: Lua 5.5.x instruction formats, opcode semantics, decode helpers, and execution fast-paths in lvm.zig.
tags: [vm, opcodes, instructions, lvm]
timestamp: 2026-08-07T23:40:00Z
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

`lvm.run` takes `(*lua_State, *CallInfo)` and executes instructions using a stack-based call frame interpreter loop.

```zig
pub fn run(L: *lua.lua_State, active_ci: *lua.CallInfo) anyerror!void {
    var ci = active_ci;
    var cl = L.stack[ci.func].function.?.lua;
    var proto = cl.p;
    var code = proto.code;

    while (ci.savedpc < code.len) {
        const instruction: Instruction = code[ci.savedpc];
        const op = GET_OPCODE(instruction);
        ci.savedpc += 1;

        switch (op) {
            .MOVE => { /* ... */ },
            // ... all other opcodes
        }
    }
}
```

### Zig 0.16.0 VM Optimizations

1. **Inline `asFloat` Pattern-Matching Unboxing**:
   `asFloat(v)` performs direct float extraction without repeating `isNumberValue()` and `toFloat()` tag switches on hot arithmetic opcodes (`.ADD`, `.SUB`, `.MUL`, `.DIV`, `.MOD`, `.POW`).

2. **Direct Integer Comparison Fast-Paths**:
   `.EQI`, `.LTI`, `.LEI`, `.GTI`, and `.GEI` execute direct `ra.integer` vs `sb` integer comparisons when operands are `.integer`, bypassing metamethod dispatch functions (`ltm.luaT_lt`/`luaT_le`) for non-float comparisons.

3. **`@branchHint(.unlikely)` Pipeline Branch Hints**:
   Applied `@branchHint(.unlikely)` to error checks and fallback branches, guiding LLVM code generation to keep hot loop instructions linearly contiguous in CPU $I$-cache.

### Performance

The interpreter loop head carries per-instruction overhead that the C
reference does not: a per-instruction GC check (`src/lvm.zig:727`, absent
from `lua/lvm.c`) plus `ci.savedpc` read+store and `L.hookmask` loads
through a ~4.7KB stack frame (C keeps a 104B frame with the loop state
pinned in callee-saved registers). This is the root cause of the ~2x
instruction-count gap on VM-bound workloads — see [Performance](performance.md)
(root causes RC1–RC5, fix plan P1–P4) and [BUG-174](bugs/174.md).

## Current Status

Phase D is **complete**. The VM runs Lua 5.5.1 compiled bytecode chunks with 100% upstream test suite pass rate.

| Feature / Opcode | Status | Behavior |
|--------|--------|----------|
| Stack Ops | Complete | `MOVE`, `LOADI`, `LOADF`, `LOADK`, `LOADKX`, `LOADFALSE`, `LFALSESKIP`, `LOADTRUE`, `LOADNIL` fully functional |
| Table Access | Complete | `NEWTABLE`, `GETTABLE`, `GETI`, `GETFIELD`, `SETTABLE`, `SETI`, `SETFIELD`, `SETLIST` fully functional |
| Upvalues | Complete | `GETUPVAL`, `SETUPVAL`, `GETTABUP`, `SETTABUP` fully functional; upvalues closed/open reference count tracked |
| Arithmetic & Bitwise | Complete | `ADD`, `SUB`, `MUL`, `DIV`, `IDIV`, `MOD`, `POW`, `BAND`, `BOR`, `BXOR`, `UNM`, `BNOT`, `NOT`, `LEN`, `CONCAT`, `SHLI`, `SHRI`, `SHL`, `SHR` fully functional |
| Comparisons | Complete | `EQ`, `LT`, `LE`, `EQK`, `EQI`, `LTI`, `LEI`, `GTI`, `GEI`, `TEST`, `TESTSET` with conditional jumping |
| Control Flow & Jumps | Complete | `JMP`, `FORPREP`, `FORLOOP`, `TFORPREP`, `TFORCALL`, `TFORLOOP` fully functional |
| Function Calls | Complete | `CALL`, `TAILCALL` support Lua closures, C closures, argument preparation, and multi-value returns |
| Closure Creation | Complete | `CLOSURE` instantiates sub-prototypes into closures, capturing upvalues |
| Returns | Complete | `RETURN`, `RETURN0`, `RETURN1` restore caller frames and copy results |
| Varargs | Complete | `VARARG` and `GETVARG` prepare dummy vararg structures |
| Cleanup & Leak Tracking | Complete | State deallocation runs a single-pass sweep over `allgc` to free all memory without leaks |
