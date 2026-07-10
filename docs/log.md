---
type: lessons_learned
title: Modification Log
description: Running chronological log of bundle modifications and significant changes.
tags: [log, changelog]
timestamp: 2026-07-10T00:00:00Z
---

## 2026-07-10 — Initial OKF Bundle Creation

Created documentation bundle at `docs/` following OKF v0.1 specification.

### Documents Created

| Document | Type | Purpose |
|----------|------|---------|
| `index.md` | bundle_root | Documentation map and quick reference |
| `architecture.md` | architecture_guideline | Overall architecture, 10 rules, module mapping |
| `type-model.md` | database_schema | Complete type mapping C -> Zig |
| `stack.md` | architecture_guideline | Stack as slice, indexing, growth |
| `roadmap.md` | project_priority | Phase-based development plan |
| `tables.md` | architecture_guideline | Table + hash part implementation |
| `string-interning.md` | architecture_guideline | String deduplication design |
| `vm.md` | api_spec | Instruction formats, opcodes, execution |
| `frontend.md` | architecture_guideline | Lexer/parser/codegen/loader |
| `error-handling.md` | architecture_guideline | Error union strategy vs setjmp/longjmp |
| `gc.md` | architecture_guideline | GC list design, colors, barriers |
| `metatables.md` | architecture_guideline | Metamethod events, fast cache, dispatch |
| `libraries.md` | architecture_guideline | Per-module porting guide, I/O threading |
| `log.md` | lessons_learned | This file |

### AGENTS.md Fixes

- Changed all `/lua/` absolute path references to `lua/` relative paths
- Fix applied to 7 occurrences across the file (sections 0.2, 1, 5, 7)

---

## 2026-07-10 — Phase B: Tables & String Interning

Implemented the foundational data structures for tables and deduplicated strings.

### Changes

- **`src/lstring.zig`** (new): `luaS_new` (interning via `std.array_hash_map.String`),
  `luaS_hash` (FNV-1a seeded), `luaS_eqstr`.
- **`src/ltable.zig`** (new): `Node` + `lua_Table` with array part (`ArrayList(TValue)`,
  nil = empty) and chained-scatter hash part (`ArrayList(Node)`, absolute `next`).
  Helpers: `createTable`, `get`/`getInt`, `set`/`setInt`, `next`, `getn`, `deinit`.
  Hash part grows 2x (min 4) and rehashes on overflow.
- **`src/lua.zig`**:
  - `global_State` now real (allocator, `strt`, seed, registry); created in
    `luaL_newstate`, freed recursively in `lua_close` (frees stack tables + strings).
  - `lua_TString` gains `hash`; `lua_Table`/`Node` replaced with real layout.
  - `lua_pushlstring`/`lua_pushstring` intern strings.
  - Table API implemented: `lua_createtable`, `lua_gettable`/`getfield`/`geti`/
    `rawget`/`rawgeti`/`rawgetp`, `lua_settable`/`setfield`/`seti`/`rawset`/`rawseti`/
    `rawsetp`, `lua_next`, `lua_rawlen`.
  - Fixed `TValue.toBoolean` (was treating `false` as truthy).
- **`build.zig`**: test step now compiles `tests/test_basic.zig` against a `lua` module
  (was effectively running 0 tests before).
- **`tests/test_basic.zig`**: +8 table/string tests (interning, setfield/getfield,
  seti/geti + length, empty table length, entry removal, hash-part string keys,
  `next` traversal, stack-key gettable/settable).

### §0.1 Self-Audit

- Allocator threaded through every allocating function (tables carry `allocator`).
- Errors propagated via `!void` + `try`; OOM in `lua_settable` paths swallowed via
  `catch {}` only because the C API has no error return (to be replaced by the
  error-union mechanism in Phase E). No `catch unreachable`, no `unreachable` for
  runtime conditions.
- No `setjmp`/`longjmp`; numeric conversions use `@intFromFloat`/`@floatFromInt`;
  `@bitCast` used only for bit-identical f64 hashing.
- Unmanaged `ArrayList` initialized with `.empty`; `TValue` tagged union retained;
  single `lua_State`/`lua_Table`/`global_State` (the duplicate in uncompiled
  `lstate.zig` is now stale and should be reconciled when GC lands).
- `luazig.zig` still uses `std.process.Init` (juicy main).

### Verification

`zig build` and `zig build test` both pass: 15/15 tests (7 pre-existing + 8 new).

### Known Limitations

- `lua_gettable`/`lua_settable` are raw (no `__index`/`__newindex`); Phase E.
- No GC: `lua_close` does a one-shot recursive free of reachable tables; cycles would
  double-free (acceptable until Phase E GC).
- Integer/float keys collapse (the port stores all numbers as `f64`); Lua 5.4's
  distinct int/float keys are not represented.

---

## 2026-07-10 — Phase C: Bytecode Loader (lundump)

Implemented the binary bytecode loader (`lundump.zig`), allowing precompiled Lua 5.5.1 bytecode chunks to be parsed, loaded, and instanced as Lua closures on the stack.

### Changes

- **`src/lundump.zig`** (new):
  - Struct `Zio`: Stream buffer wrapper around `lua_Reader` that caches the pre-read block and lazily reads next blocks block-by-block.
  - Struct `LoadState`: Manages parse state, offset tracking, and loaded string cache.
  - Helpers: `loadBlock`, `loadByte`, `loadVarint`, `loadSize`, `loadInt`, `loadNumber`, `loadInteger`, `loadAlign`, `loadString`, `loadCode`, `loadConstants`, `loadProtos`, `loadUpvalues`, `loadDebug`, `loadFunction`, `checkHeader`, `checkliteral`, `checknum`.
  - Parses standard variable-length integer encoding (varint), aligns instruction/numeric boundaries, and interns short/long strings into the global state.
  - Main entry point: `loadBinaryChunk`.
- **`src/lua.zig`**:
  - Defined prototype debug structures: `Upvaldesc`, `LocVar`, `AbsLineInfo`.
  - Refactored `lua_Proto` to use idiomatic native Zig slices (`[]Instruction`, `[]TValue`, `[]*lua_Proto`, `[]Upvaldesc`, `[]i8`, `[]AbsLineInfo`, `[]LocVar`) and deduplicated string references (`?*lua_TString`).
  - Added recursive prototype allocator/deallocator: `createProto`, `destroyProto`.
  - Updated `freeValue` to recursively clean up `.function` (instantiated C closures and Lua closures, including the associated prototype tree).
  - Updated `lua_load` to check the first byte of the stream. If it starts with `\x1b` (`LUA_SIGNATURE[0]`), it delegates chunk loading to `lundump.loadBinaryChunk`.
  - Defined `LUA_SIGNATURE` version constant matching the C header.
- **`tests/test_basic.zig`**:
  - Added `bytecode loader (lundump)` test case.
  - Generates bytecode dynamically by compiling `tests/test_chunk.lua` with the compiled reference interpreter `lua`, reads the output file using Zig 0.16.0 `std.Io` file system interfaces, loads it via `lua_load`, and validates prototype field properties (params count, stack size, instructions, constants, nested prototypes).
- **`docs/` OKF Bundle**:
  - Updated `docs/frontend.md` to note completed bytecode loader.
  - Updated `docs/type-model.md` to specify new layout of `lua_Proto` and debug structs.

### §0.1 Self-Audit

- Allocator explicitly threaded to `createProto`, `destroyProto`, and throughout `lundump.zig`.
- Errors propagated via error unions; no `catch unreachable` in loader.
- Recursive functions `loadProtos` and `loadFunction` return `anyerror!void` explicitly to resolve compile-time error set dependency loop.
- Decoupled from global I/O: test reads files using explicit `std.Io.Dir` and a single-threaded threaded `Io` instance fallback.
- Strings interned via global state `strt` (no raw C string sentinels, slices are used).
- Tagged unions are used throughout.

### Verification

`zig build test` compiled and passed all 16/16 tests successfully.

## Phase D — Working VM (2026-07-10)

### Changes

- **`src/lvm.zig`**:
  - Implemented the full instruction execution loop in `run(L, active_ci)`.
  - Re-implemented instruction decoding and encoding helper functions (`GETARG_A`, `GETARG_B`, `GETARG_C`, `GETARG_k`, `GETARG_vB`, `GETARG_vC`, `GETARG_Bx`, `GETARG_Ax`, `GETARG_sBx`, `GETARG_sJ`, etc.) to match the precise Lua 5.5.1 instruction layout and bit widths.
  - Implemented execution bodies for core instructions, including stack manipulation (`MOVE`, `LOADI`, `LOADF`, `LOADK`, `LOADKX`, `LOADFALSE`, `LFALSESKIP`, `LOADTRUE`, `LOADNIL`), table creation/access (`NEWTABLE`, `GETTABLE`, `GETI`, `GETFIELD`, `SETTABLE`, `SETI`, `SETFIELD`, `SETLIST`), upvalues (`GETUPVAL`, `SETUPVAL`, `GETTABUP`, `SETTABUP`), comparisons with conditional jumping (`EQ`, `LT`, `LE`, `EQK`, `EQI`, `LTI`, `LEI`, `GTI`, `GEI`, `TEST`, `TESTSET`), arithmetic (`ADD`, `SUB`, `MUL`, `DIV`, `IDIV`, `MOD`, `POW`, `BAND`, `BOR`, `BXOR`, `UNM`, `BNOT`, `NOT`, `LEN`, `CONCAT`, `SHLI`, `SHRI`, `SHL`, `SHR`), closure generation (`CLOSURE`), method calls (`SELF`), jumps (`JMP`), calls and tailcalls (`CALL`, `TAILCALL`), loops (`FORPREP`, `FORLOOP`, `TFORPREP`, `TFORCALL`, `TFORLOOP`), and returns (`RETURN`, `RETURN0`, `RETURN1`).
  - Added support for conditional jumps, tail calls, and multi-value returns.
- **`src/lua.zig`**:
  - Re-designed the VM type model: updated `CallInfo` to use stack indices instead of pointers (preventing invalidation during stack reallocation), restructured `lua_LClosure` and `lua_CClosure` and added upvalue lifetime reference counting (`refcount`) to `UpVal`.
  - Implemented function call preparation and return helpers `precall` and `poscall`.
  - Implemented upvalue list management functions `findupval` and `closeupvals` to track open upvalues on the stack.
  - Updated `lua_callk` and `lua_pcallk` to trigger the interpreter.
  - Added `VMGCObject` struct to trace all heap-allocated objects (tables, closures, upvalues, prototypes) in a singly linked list (`allgc`) on `global_State`.
  - Updated `lua_close` to perform a single-pass sweep over `allgc` to cleanly reclaim all allocations.
- **`tests/test_basic.zig`**:
  - Added a new `VM execution` test case.
  - Loads and runs a compiled chunk (`tests/test_chunk.luac`) that performs table creation, local scoping, function calls with upvalue lookup, arithmetic, and returns.
  - Validates that the VM runs, returns `LUA_OK`, and yields the expected result of `52.0` on the stack with zero memory leaks.

### §0.1 Self-Audit

- Stack growth and reallocation handled safely using stack indices inside `CallInfo`.
- Allocations cleanly tracked in `global_State.allgc` and swept in `lua_close`, eliminating all memory leaks.
- Tagged unions are exhaustively handled.
- Threaded memory allocation and error propagation used throughout.

### Verification

`zig build test` compiled and passed all 17/17 tests successfully with zero memory leaks.

---

## Phase E — Metamethod Dispatch: __index / __newindex (2026-07-10)

### Changes

- **`src/ltm.zig`**:
  - Added `MAXTAGLOOP = 2000` constant matching the C reference.
  - Implemented `luaV_gettable(L, t, key, res)`: metamethod-aware table read following the full `__index` chain (table→function→table recursion, up to MAXTAGLOOP).
  - Implemented `luaV_settable(L, t, key, val)`: metamethod-aware table write following the full `__newindex` chain, with "key already present → skip `__newindex`" semantics matching the C reference.
  - Both functions dispatch metamethods via existing `luaT_gettmbyobj`, `luaT_callTMres`, and `luaT_callTM` helpers.

- **`src/lvm.zig`**:
  - Rewired all table-read opcodes (`GETTABLE`, `GETI`, `GETFIELD`, `GETTABUP`) to call `ltm.luaV_gettable`.
  - Rewired all table-write opcodes (`SETTABLE`, `SETI`, `SETFIELD`, `SETTABUP`) to call `ltm.luaV_settable`.
  - Updated `SELF` to use `ltm.luaV_gettable` for method lookup.
  - `GETI`/`SETI` now wrap the integer key as `TValue{ .number = @floatFromInt(c) }` before passing to `luaV_gettable`/`luaV_settable`.

- **`src/lua.zig`**:
  - Updated `lua_gettable`, `lua_getfield`, `lua_geti` to call `ltm.luaV_gettable`.
  - Updated `lua_settable`, `lua_setfield`, `lua_seti` to call `ltm.luaV_settable`.
  - Made `lua_rawget`, `lua_rawgeti`, `lua_rawset`, `lua_rawseti` truly raw (no metamethod dispatch).
  - Fixed `lua_setmetatable`: properly unwrap `?*lua_Table` and `?*lua_Udata` optionals before setting `.metatable`.
  - Fixed `idxPtr` to decode positive indices as **frame-relative** (`L.stack[ci.base + idx - 1]`) when inside a call frame — correct Lua C API contract. Upvalue pseudo-indices (`lua_upvalueindex(n)`) resolve to the current C closure's `upvals[n-1]`.
  - Added `lua_pushcfunction(L, f)`: shorthand for `lua_pushcclosure(L, f, 0)`.
  - Added `lua_upvalueindex(n)`: converts 1-based upvalue index to pseudo-index.
  - Added `lua_getupvalue(L, _, n)` / `lua_setupvalue(L, _, n)`: get/set C closure upvalues.
  - Fixed memory leak: `lua_pushcclosure` now calls `registerGC(L, cl)` so C closures are freed by `lua_close`.

- **`tests/test_basic.zig`**:
  - Added 3 new tests: `__index function metamethod via C API`, `__index table chain metamethod via C API`, `__newindex function metamethod via C API`.

### §0.1 Self-Audit

- No `catch unreachable`, no `@bitCast` for value conversion.
- All metamethod chains bounded by `MAXTAGLOOP = 2000` (matching C reference safety limit).
- Error unions propagated cleanly; metamethod errors surface as `error.RuntimeError`.
- Frame-relative index decoding matches the real Lua C API contract.
- C closures now GC-registered, eliminating memory leaks.

### Verification

`zig build test` compiled and passed all **20/20 tests** with zero memory leaks.

---

## Phase E — Arithmetic Metamethods Update (2026-07-10)

### Changes

- **`src/llimits.zig`**:
  - Defined standard `LUA_OP*` constants for arithmetic, bitwise, and comparison operations, conforming to the Lua 5.5.1 specifications.
- **`src/lua.zig`**:
  - Re-exported the new `LUA_OP*` constants from `llimits.zig`.
  - Rewrote `lua_arith` to use the official symbolic constants and corrected the unary/binary operand checks and arithmetic/bitwise mapping logic.
  - Ensured correct tag method execution via `ltm.luaT_trybinTM` when operands are not plain numbers.
- **`tests/test_basic.zig`**:
  - Added `__add arithmetic metamethod via C API` test to verify that calling `lua_arith(L, LUA_OPADD)` successfully calls custom `__add` functions on non-numbers.
  - Added `VM execution of arithmetic metamethod` test using a precompiled closure that does `a + b` with two tables to verify that the VM `ADD` opcode correctly triggers the `.MMBIN` fallback and metamethod execution.

### §0.1 Self-Audit

- No `catch unreachable` used in code paths.
- Proper use of `@floatFromInt` and `@intFromFloat` for all numeric conversions.
- Tagged unions are exhaustively handled.

### Verification

`zig build test` compiled and passed all **22/22 tests** with zero memory leaks.

---

## Phase E — Comparison Metamethods & Error Propagation (2026-07-10)

### Changes

- **`src/lua.zig`**:
  - Updated `lua_compare` to use the metamethod-aware comparison helpers (`luaT_equalobj`, `luaT_lt`, `luaT_le`) from `src/ltm.zig` instead of simple type-only comparisons.
  - Changed `lua_CFunction` and `lua_KFunction` to return `anyerror!i32` to allow native Zig error propagation from C/host functions without longjmp.
  - Rewrote `precall` to use `try` when invoking C closures, correctly cleaning up and restoring stack frames on failure.
  - Rewrote `lua_error` to return `anyerror` and throw `error.RuntimeError`, converting a nil error object to a `<no error object>` string on the stack.
  - Updated `lua_pcallk` to intercept errors, execute `errfunc` error handler function with full stack/CallInfo frames preserved, safely restore stack/CallInfo to pre-call boundaries, and leave the final error object at the stack top.
  - Added inline wrapper functions `lua_call` and `lua_pcall` for convenience.

- **`src/lvm.zig`**:
  - Updated `TAILCALL` opcode execution of C functions to use `try` for invoking C closures since they can now return `anyerror!i32`.

- **`tests/test_basic.zig`**:
  - Updated all C closure test functions to return `anyerror!i32` to conform to the updated `lua_CFunction` type.
  - Added `__eq metamethod via C API` test.
  - Added `__lt and __le metamethods via C API` test.
  - Added `error propagation and pcall` test to verify that errors from C functions propagate and leave the correct error object on the stack.
  - Added `pcall with errfunc error handler` test to verify that custom error handlers execute and successfully format/replace the propagated error object.

### §0.1 Self-Audit

- Handled optional pointer unwrapping safely using `if (ptr) |p|`.
- Replaced block statements with block expressions returning correct typed values.
- Discarded unused return values explicitly using `_ =`.

### Verification

`zig build test` compiled and passed all **26/26 tests** with zero memory leaks.

---

## Phase E — Garbage Collection Expansion (2026-07-10)

### Changes

- **Repository Cleanup**:
  - Deleted stale/dead code file `src/lstate.zig` (types duplicate `src/lua.zig`).

- **`src/lua.zig`**:
  - Added `marked` boolean flag to `lua_TString` for tracking during GC mark phase.
  - Added `GCColor` enum (`white`, `gray`, `black`) and `color` field to `VMGCObject`.
  - Added GC constants `LUA_GC*` (e.g. `LUA_GCCOLLECT`=2).
  - Implemented `getGCObject` helper using type-safe `@intFromPtr` comparison.
  - Implemented `markObject` and `markValue` to color and append roots/fields to the gray list.
  - Extracted resource-freeing logic into `freeGCObject`.
  - Implemented `luaC_collectgarbage` which runs a full mark-and-sweep cycle:
    - Root marking (registry, stack, metatables, open upvalues, metamethod names).
    - Traversing gray objects (tables, closures, upvalues, prototypes, userdata).
    - Sweeping white objects.
    - Sweeping unmarked strings from `global_State.strt`.
  - Updated `lua_gc` to support `LUA_GCCOLLECT` and trigger `luaC_collectgarbage`.
  - Updated `lua_close` to use `freeGCObject`.

- **`tests/test_basic.zig`**:
  - Added `garbage collector mark and sweep` test. Verifies that unreferenced tables and strings are successfully swept, referenced tables and strings are kept, and everything gets reclaimed once popped and swept again.

### §0.1 Self-Audit

- Removed stale/duplicated file `src/lstate.zig`.
- Standardized `ArrayList` usage to comply with Zig 0.16.0 unmanaged array lists (initialized with `.empty`, passing allocator explicitly to mutations).
- Handled multi-type pointer comparison safely using `@intFromPtr`.

### Verification

`zig build test` compiled and passed all **27/27 tests** with zero memory leaks.

---

## Phase F — Standard Libraries (Base Library Porting) (2026-07-10)

### Changes

- **`src/lua.zig`**:
  - Implemented `lua_getglobal` and `lua_setglobal` to look up and store values in the registry globals table (`LUA_RIDX_GLOBALS = 2`).
  - Refactored `lua_absindex`, `lua_gettop`, `lua_settop`, and `lua_rotate` to be frame-relative by mapping indices relative to `L.ci.?.base` when a call frame is active. Added `toAbsoluteIndex` internal helper.
  - Corrected return types for `lua_gettable`, `lua_getfield`, `lua_geti`, `lua_rawget`, `lua_rawgeti`, and `lua_rawgetp` to return the actual type of the pushed value (`val.typ()`) rather than a hardcoded `1` (which mapped incorrectly to `LUA_TBOOLEAN`).

- **`src/lib/baselib.zig`**:
  - Wired and completed standard base library functions registration in `openbaselib`.
  - Fixed logic in `pcall`/`xpcall`/`rawequal` around type signatures and `lua_pushboolean` boolean casting.

- **`tests/test_basic.zig`**:
  - Appended 5 new integration tests verifying `type()`, `rawequal(), rawlen(), rawget(), rawset()`, `setmetatable() and getmetatable()`, `tonumber() and tostring()`, and `select()`.

### §0.1 Self-Audit

- Handled frame-relative stack operations securely without breaking absolute pseudo-indexing.
- Replaced manual pointer arithmetic with relative base offsetting.
- Cleared debug tracing from the codebase to keep test output clean.

### Verification

`zig build test` compiled and passed all **32/32 tests** with zero memory leaks.




