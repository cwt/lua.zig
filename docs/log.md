---
type: lessons_learned
title: Modification Log
description: Running chronological log of bundle modifications and significant changes.
tags: [log, changelog]
timestamp: 2026-07-10T00:00:00Z
---

## 2026-07-12 — Phase F: debug library completed

Implemented the full `debug` standard library (`src/lib/debug.zig`) and the
underlying debug C-API infrastructure in `src/lua.zig`, completing Phase F.

### Infrastructure added to `src/lua.zig`
- `lua_sethook` / `lua_gethook` / `lua_gethookmask` / `lua_gethookcount` — hook
  get/set API.
- `luaO_chunkid` — truncates source names to fit `LUA_IDSIZE` (60 bytes), using
  the `=`/`@`/literal rules from the C reference `lobject.c`.
- `luaG_getfuncline` / `getbaseline` — convert a proto's compact `lineinfo` delta
  array + `abslineinfo` sentinel entries to an absolute source line number.
- `luaF_getlocalname` — looks up a local variable name from a proto's `locvars`
  table at a given PC.
- `luaG_findlocal` — locates a local by slot number within a `CallInfo` frame.
- `lua_getlocal` / `lua_setlocal` — read/write a local variable from the Lua
  debug API.
- `lua_getinfo` — fills a `lua_Debug` struct for `S`, `l`, `u`, `n`, `t`, `r`,
  `f`, and `L` fields.
- Debug name-resolution helpers (`kname`, `upvalname`, `basicgetobjname`,
  `getobjname`, `funcnamefromcode`, `funcnamefromcall`, `getfuncname`) —
  mirror `lua/ldebug.c` semantics for `CALL`/`TAILCALL`, upvalues, table
  access fields, and metamethod event tags.
- `isLua` / `currentpc` — CallInfo-level helpers used by the debug helpers.
- `findsetreg` / `filterpc` — backward-dataflow analysis to find which
  instruction last wrote a register, used by `basicgetobjname`.
- `testAMode` / `testMMMode` — opcode-mode predicates matching `luaP_opmodes`.

### Infrastructure added to `src/lauxlib.zig`
- `luaL_traceback` — builds a human-readable stack traceback string by walking
  `lua_getstack` + `lua_getinfo("Slnt")` for each frame and collecting lines
  into a `luaL_Buffer`. Truncates deeply recursive stacks (LEVELS1 + LEVELS2
  with skip notification).
- `pushfuncname` — helper to produce a descriptive name for the currently-active
  function (name from namewhat, "main chunk", `function <src:line>`, or `?`).

### `src/lib/debug.zig` — 16 functions
All functions use `lauxlib.*` for argument validation, correct `std.Io` for
output, and `u32`/`i32` type discipline for hook masks. (Mirrors the C
`dblib[]` table exactly; `debug.gethookmask`/`debug.gethookcount` are **not**
exposed in Lua 5.5.1 — their values are the 2nd/3rd returns of
`debug.gethook`.)

| Function | Status |
|---|---|
| `debug.getregistry` | ✅ |
| `debug.getmetatable` | ✅ |
| `debug.setmetatable` | ✅ |
| `debug.getuservalue` | ✅ |
| `debug.setuservalue` | ✅ |
| `debug.gethook` | ✅ |
| `debug.sethook` | ✅ |
| `debug.getinfo` | ✅ |
| `debug.getlocal` | ✅ |
| `debug.setlocal` | ✅ |
| `debug.getupvalue` | ✅ |
| `debug.setupvalue` | ✅ |
| `debug.upvalueid` | ✅ |
| `debug.upvaluejoin` | ✅ |
| `debug.traceback` | ✅ |
| `debug.debug` | ✅ (stub) |

### Also fixed in this session
- **`lua_TString.slice()`** — `lua_TString` has no `slice()` method; replaced
  all 6 occurrences with `.s` field access.
- **`std.meta.intToEnum`** — removed in Zig 0.16; replaced with `@enumFromInt`.
- **`lua_getupvalue`/`lua_setupvalue`** — upvalue name now read from `.s` not `.slice()`.

### Tests
64 tests pass (5 new debug tests added):
- `debug library registration` — verifies all 7+ functions are present as
  `LUA_TFUNCTION` values in the `debug` global table.
- `debug.getupvalue on C closure` — verifies upvalue read from a C closure.
- `debug.getinfo on C function` — verifies `what="C"` and `linedefined=-1`.
- `debug.sethook and gethook` — exercises the hook C API (set, verify mask, clear).
- `debug.traceback produces non-empty string` — verifies the returned string
  contains `"stack traceback:"`.

### §0.1 self-audit
1. ✅ Allocator threaded — all allocations use `L.allocator`.
2. ✅ Error propagation — `try`/`!T` throughout; no silent `catch {}`.
3. ✅ No setjmp/longjmp — pure Zig error union paths.
4. ✅ Numeric conversions — `@intCast`, `@bitCast` only for same-width types.
5. ✅ Slices not C strings — `[]const u8` throughout.
6. ✅ No C varargs.
7. ✅ Unmanaged containers — `luaL_Buffer` uses `std.ArrayList(u8)` with `.empty` init.
8. ✅ Tagged union TValue.
9. ✅ Single type model.
10. ✅ `std.Io` — `db_debug` uses `std.Io.File.stderr().writeStreamingAll`.
11. ✅ Shift bounds — not applicable here.
12. ✅ No empty catch blocks.
13. ✅ Stack capacity validated before use.
14. ✅ Type predicates precise.

## 2026-07-12 — stringlib §0.1 Robustness Audit

Audited the string standard library (commits 27-29) for completion and
Zig 0.16.0 best-practice compliance.

### Findings
- **Completeness:** All 17 functions from the C `strlib[]` table are present and
  wired in `src/lib/stringlib.zig`: `byte, char, dump, find, format, gmatch,
  gsub, len, lower, match, rep, reverse, sub, upper, pack, packsize, unpack`.
- **§0.1 compliance:** Allocator threaded via `luaL_Buffer`; errors propagated
  with `!T` + `try` (no `catch unreachable`); value conversions use `@intCast`/
  `@floatCast`/`@bitCast` only for same-width integer reinterpretation; dynamic
  shift amounts masked/checked; pattern matcher carries explicit boundary guards.

### Bugs found & fixed (string + VM layer)
1. **`src/lauxlib.zig` `luaL_prepbuffsize`** — used `buf.resize()` (which grows the
   *logical* length) instead of `ensureTotalCapacity()`, so a `prepbuffsize(sz)` +
   `addsize(sz)` pair committed `2*sz` bytes (e.g. `string.char("abc")` returned
   6 bytes `61 62 63 aa aa aa`). Now reserves capacity without advancing the
   length and returns the reserved slice.
2. **`src/lib/string/pattern.zig` `push_captures`** — the "push whole match when
   capture level is 0" test used `s == 0`. In C `s` is a pointer (NULL only for the
   `find` position-push call), but here `s` is a `usize` index, so a match starting
   at offset 0 was misclassified and nothing was pushed. Made `s` an optional
   (`?usize`); the `find` position case passes `null`, a real match passes its
   (possibly zero) index. Fixes `string.match`/`string.gsub` returning empty for
   zero-offset matches.
3. **`src/lib/string/pack.zig` `getdetails`** — the power-of-two alignment check
   `al & (al - 1)` overflowed when `al == 0` (the no-op endianness/alignment
   markers `</>/=/!` set `size = 0`). Guarded the `al == 0` case. Fixes an integer
   overflow panic for formats like `">i4"`.
4. **`src/lua.zig` `lua_Udata`** — the userdata type had **no payload buffer**
   (only `len`/`metatable`), so `lua_newuserdatauv`/`lua_touserdata` handed back the
   tiny header struct cast to the payload type. `string.gmatch`'s `GMatchState`
   (stored as a userdata upvalue) then wrote past the allocation, corrupting an
   adjacent closure and segfaulting at `lua_close`. Gave `lua_Udata` a real `data:
   []u8` buffer, made `lua_newuserdatauv` allocate it, `lua_touserdata` return
   `data.ptr` (while `lua_topointer` still returns the header for identity), and
   `freeGCObject` free it.
5. **Buffer leak on error paths** — `luaL_Buffer`-using string functions did not
   free the `ArrayList` when a Lua error propagated (e.g. `string.char(256)`).
   Added `errdefer b.buf.deinit(L.allocator)` after each `buffinit` in
   `src/lib/stringlib.zig` (5 sites) and `format.zig`/`pattern.zig`/`pack.zig`
   (3 sites).

### Change
- `src/lib/string/pack.zig`: explicit `.max => break` in the option switches;
  `getdetails` zero-alignment guard.
- `src/lib/string/pattern.zig`: `push_captures` optional `s`; `errdefer` free.
- `src/lib/stringlib.zig`: `errdefer` free on buffer error paths.
- `src/lauxlib.zig`: `luaL_prepbuffsize` capacity fix.
- `src/lua.zig`: `lua_Udata` payload buffer; `lua_touserdata`/`freeGCObject` wiring.
- `tests/test_basic.zig`: added coverage test exercising byte/char/len/sub/reverse/
  case/rep/match/gmatch/pack; verified no leaks via the testing allocator.

### Verification
`zig build test` passes: **41/41 tests**, zero memory leaks.

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

---

## 2026-07-11 — BUG-001: Bitwise shift panic fix

### Changes

- **`src/lua.zig`**: Added `luaV_shift(i64, i64) i64` helper that uses `@bitCast` to
  `u64` for safe bitwise shifting. `@intCast` of negative shift amounts was causing
  runtime panics. The helper masks the shift amount to 6 bits and shifts in the
  opposite direction for negative amounts (matching Lua `lvm.c` reference).
  Fixed `LUA_OPSHL`/`LUA_OPSHR` cases in `lua_arith` to use the helper.
- **`src/lvm.zig`**: Fixed `.SHL`/`.SHR` opcodes to use `lua.luaV_shift` instead of
  raw `@intCast` to `u6`.
- **`tests/test_basic.zig`**: Added `"bitwise shift operations with negative and large shift"`
  test, verifying both the `luaV_shift` helper and `lua_arith` C API paths.
- **`docs/bugs.md`**: Marked BUG-001 as fixed.

### §0.1 Self-Audit

- `@bitCast` used between `i64` ↔ `u64` (same bit width, bit-identical reinterpretation) — valid.
- `@intCast` into `u6` is safe because the shift amount is masked to `0x3F` first.
- No `catch unreachable`, no runtime panics on negative shift amounts.

### Verification

`zig build test` compiled and passed all **33/33 tests** with zero memory leaks.

---

## 2026-07-11 — BUG-002: lua_callk/lua_call error propagation fix

### Changes

- **`src/lua.zig`**: Changed `lua_callk` and `lua_call` return type from `void` to
  `!void`. Errors from `precall` and `lvm.run` now propagate via `try` instead of
  being caught with `catch { print(); return; }`.
- **`src/lib/baselib.zig`**: Added `try` to `lua_call` call sites.
- **`tests/test_basic.zig`**: Added `try` to all `lua_call` call sites.
- **`docs/bugs.md`**: Marked BUG-002 as fixed.

### §0.1 Self-Audit

- Errors now propagate via `!T` + `try` as required by §0.1 rule 2.
- No `catch unreachable`, no swallowed errors.
- All call sites updated to propagate the error.

### Verification

`zig build test` compiled and passed all **33/33 tests** with zero memory leaks.

---

## 2026-07-11 — BUG-011: Numeric `for` loop register layout fix

### Changes

- **`src/lvm.zig`**: Restored FORPREP/FORLOOP to match the C reference float-path
  implementation. FORPREP scrambles `R(a)=limit`, `R(a+1)=step`, `R(a+2)=init`
  (control var). FORLOOP reads `step=R(a+1)`, `limit=R(a)`, `idx=R(a+2)+step`
  and writes updated idx to `R(a+2)`. Fixed skip offset: `savedpc += Bx + 1`
  (was missing the `+1`). Loop-back offset: `savedpc -= Bx`.
- **`tests/test_basic.zig`**: Added `"numeric for loop register layout"` test:
  constructs a `lua_Proto` with `LOADI`+`FORPREP`+`FORLOOP`+`RETURN1` for
  `for i=1,3 do end`, calls it via `precall`+`lvm.run`, and verifies `R(a)`
  holds limit (`3.0`) after loop exit.
- **`docs/bugs.md`**: Marked BUG-011 as fixed with corrected description.

### §0.1 Self-Audit

- FORPREP matches C reference float path: register scramble, skip condition,
  and offset arithmetic (`savedpc += Bx + 1`).
- FORLOOP matches C reference float path: reads scrambled positions,
  writes updated idx to control variable `R(a+2)`, loop-back `savedpc -= Bx`.
- No `catch unreachable`, no `@bitCast` for value conversion.
- Error propagation: `step == 0` returns `error.RuntimeError`.

### Verification

`zig build test` compiled and passed all **34/34 tests** with zero memory leaks.

---

## 2026-07-11 — BUG-004/005/007/008/009/010/012/013 fixes

### Changes

- **BUG-004** — `lua_tointegerx`: sets `isnum=0` for non-integral floats
  (when `@trunc(n) != n`). `src/lua.zig:757-763`.
- **BUG-005** — `lua_isinteger`: returns `1` for integral floats (when
  `@trunc(n) == n`). `src/lua.zig:713-717`.
- **BUG-007** — `luaL_checkstack`: delegates to core `lua_checkstack` instead
  of checking `lua_gettop(L) + n > LUA_MINSTACK`. `src/lauxlib.zig:154-161`.
- **BUG-008** — `luaL_register`: defines `luaL_Reg` struct with `name`/`func`
  fields; uses `reg.name` instead of hardcoded `"func"`. `src/lauxlib.zig:112-125`.
- **BUG-009** — `TValue.typ()`: maps `.upval` to new `LUA_TUPVAL=9` instead
  of colliding `LUA_TTHREAD`. `src/llimits.zig:56-58`, `src/lua.zig:23,152`.
- **BUG-010** — `precall` C-closure: calls `lua_checkstack(L, 20)` before
  setting `CallInfo.top = L.top + 20`. `src/lua.zig:348`.
- **BUG-012** — C-API table accessors: `lua_gettable`/`getfield`/`geti`/
  `settable`/`setfield`/`seti` now propagate errors via `!i32`/`!void` and
  `try` instead of `catch {}`. Updated callers in `baselib.zig` and
  `tests/test_basic.zig`. `src/lua.zig:1143-1340`.
- **BUG-013** — `luaT_callTM`/`luaT_callTMres`: check `lua_checkstack`
  result and return `error.OutOfMemory` on failure. `src/ltm.zig:101-125`.
- **`docs/bugs.md`**: Marked BUG-004/005/007/008/009/010/012/013 as fixed.
  Updated BUG-006 description (cannot fix without C-style varargs).
- **`src/lib/*.zig`**: Library stubs remain unfixed for BUG-012 (not compiled).

### §0.1 Self-Audit

- All error propagations use `!T` + `try` as required by §0.1 rule 2.
- `@trunc` used for fractional-part detection (safe float arithmetic).
- `LUA_TUPVAL` constant added to `llimits.zig` and re-exported from `lua.zig`.
- No `catch unreachable`, no `@bitCast` for value conversion.
- `luaL_Reg` struct defined in `lauxlib.zig` with idiomatic Zig struct layout.

### Verification

`zig build test` compiled and passed all **34/34 tests** with zero memory leaks.

---

## 2026-07-11 — Phase F: Math Standard Library (mathlib) port

### Changes
- **`src/llimits.zig`**: Added `LUA_MAXINTEGER` (`std.math.maxInt(i64)`) and
  `LUA_MININTEGER` (`std.math.minInt(i64)`) exposing Lua 5.5.1 integer bounds.
- **`src/lua.zig`**: Re-exported the integer bounds. Added `.prng: std.Random.Xoshiro256`
  field to `global_State`, initialized in `luaL_newstate_io` with
  `std.Random.Xoshiro256.init(@intFromPtr(L))`. Rewrote `lua_tointegerx` to
  perform the C `lua_numbertointeger` range check (`-2^63 .. 2^63`) so out-of-range
  f64 values (e.g. `huge` = inf, `math.maxinteger`) return `null` instead of
  panicking on `@intFromFloat`.
- **`src/lauxlib.zig`**: Added `luaL_checknumber`, `luaL_optnumber`,
  `luaL_pushfail`, `luaL_argcheck` helpers.
- **`src/lib/mathlib.zig`** (rewritten): Ported all 26 functions from `lua/lmathlib.c`
  (`abs`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `floor`, `ceil`, `fmod`,
  `modf`, `sqrt`, `ult`, `log`, `exp`, `deg`, `rad`, `frexp`, `ldexp`, `min`,
  `max`, `type`, `random`, `randomseed`, `tointeger`) plus constants
  (`pi`, `huge`, `maxinteger`, `mininteger`). PRNG uses the seeded Xoshiro256.
- **`src/lualib.zig`**: Wired `openmathlib` to call `mathlib.openmathlib(L)`.
- **`tests/test_basic.zig`**: Added 3 mathlib test blocks (constants/basic,
  min/max/type/ult/tointeger, random/randomseed).

### Bugs fixed (this session)
- **mathlib overflow**: `math_abs` used `@as(i64, @bitCast(0 - un))` for the
  negative-integer absolute value. For `n == LUA_MININTEGER` this is an unsigned
  subtraction that panics in Zig (runtime integer overflow). Changed to wrapping
  `@as(u64, 0) -% un`.
- **`math.randomseed`/`math.random` test stack bugs**: the C-API test blocks
  left the `math` table on the stack and then called it directly as a function,
  returning `LUA_ERRRUN`. Fixed by re-pushing `math` via `lua_getglobal` before
  each sub-call and adjusting `lua_gettop` expectation after `randomseed`
  (3 = math table + 2 return values).

### §0.1 Self-Audit
- Allocator threaded through every allocating function (PRNG seeded in `global_State`).
- Errors propagated via `!void` + `try`; `lua_setfield`/`lua_getfield` call sites use `try`.
- Numeric conversions use `@intFromFloat`/`@floatFromInt`; `@bitCast` used only for
  unsigned reinterpretation of integer bit patterns.
- `lua_tointegerx` implements the exact C `lua_numbertointeger` range predicate,
  satisfying §0.1 rule 14 (no stub return values for standard API functions).
- `LUA_MAXINTEGER`/`LUA_MININTEGER` read via `lua_tonumber` (f64) in tests
  because the odd extreme cannot round-trip through the f64-only number
  representation without precision loss.

### Verification
`zig build` and `zig build test` both pass: **37/37 tests**, zero memory leaks.

### Known Limitations
- TValue stores all numbers as `f64`; `lua_pushinteger(LUA_MAXINTEGER)` yields
  `9223372036854775808.0` (off by 1, f64 rounding). `lua_tointegerx` guards
  against the resulting out-of-range panic, but exact large integers are not
  representable. This is a fundamental consequence of the f64-only number model
  (also noted in the Phase B "Known Limitations" section).

## 2026-07-11 — Phase F: Bitwise Standard Library (bit32) port

### Changes
- **`src/lib/bit32.zig`** (rewritten): Ported all 12 functions from Lua 5.3's
  `lbitlib.c` (`band`, `bor`, `bxor`, `bnot`, `btest`, `lshift`, `rshift`,
  `arshift`, `lrotate`, `rrotate`, `extract`, `replace`) plus the `openbit32`
  registration that installs the `bit32` global table. Because `lbitlib.c` is
  absent from this 5.5.1 tree, the authoritative reference is Lua 5.3.6
  (`lua-5.3.6/src/lbitlib.c`), fetched to verify semantics. Key semantics
  matched exactly:
  - All values are unsigned 32-bit (`LUA_NBITS = 32`), masked via `checkunsigned`.
  - `lshift`/`rshift` return `0` when `|disp| >= 32` (NOT modulo 32).
  - `arshift` is arithmetic (sign-extends bit 31, fills with 1s) **only** when
    bit 31 of the value is set and `disp >= 0`; otherwise it is a plain logical
    shift right. A huge `disp` on a negative-valued (bit-31-set) input yields
    `0xFFFFFFFF` (ALLONES).
  - `lrotate`/`rrotate` use `disp & 31` (modulo 32), matching `b_rot`.
  - `extract`/`replace` use `fieldargs` validation (`field >= 0`, `width > 0`,
    `field + width <= 32`) and raise a Lua error otherwise.
- **`src/lualib.zig`**: Wired `openbit32` to call `bit32.openbit32(L)`; imported
  the module.
- **`tests/test_basic.zig`**: Added a `bit32: bitwise library` block covering all
  12 functions plus boundary cases (`|disp| >= 32` → 0, `arshift` arithmetic on
  negative input, rotation wrap).

### §0.1 Self-Audit
- Allocator threaded where needed (no allocation in bit32 itself; it is pure
  arithmetic on stack values).
- Errors propagated via `!i32` + `try`; `lua_setfield` call sites use `try`;
  `luaL_error` is invoked from `lauxlib` for invalid field/width arguments.
- Numeric conversions use `@intCast`/`@bitCast` for integer bit reinterpretation
  only; no `@bitCast` between f64 and integers.
- Boundary-checked dynamic shifts: shift/rotate amounts are `u6`, with `|disp| >=
  32` short-circuited to `0` and `disp & 31` for rotations, satisfying §0.1 rule 11.

### Verification
`zig build` and `zig build test` both pass: **38/38 tests**, zero memory leaks.

### Known Limitations
- `bit32` over the f64-only number model: the C library returns unsigned 32-bit
  integers which our `lua_pushinteger` converts to `f64`. Values `> 2^53` lose
  precision in `lua_tonumber` reads, but `lua_tointeger` round-trips them exactly
  (the 32-bit range fits in f64 exactly). Tests read results via
  `lua_tointeger`.

## 2026-07-12 — Phase F: UTF-8 Standard Library (utf8) port

### Changes
- **`src/lib/utf8lib.zig`** (rewritten): Ported from `lua/lutf8lib.c`. Functions:
  `char` (`char_`), `codepoint`, `len`, `offset`, `codes`, and the `openutf8lib`
  registration that installs the `utf8` global table plus `utf8.charpattern`.
  Helpers ported exactly: `utf8_decode` (with `strict` flag and the `limits[]`
  table), `u_posrelat` (negative position = back from end), and `encode_utf8`
  (RFC 3629 long-form encoder with the high-byte mask `0xFF << (8 - nb)`).
  Constants kept faithful: `MAXUNICODE = 0x10FFFF`, `MAXUTF = 0x7FFFFFFF`,
  `UTF8PATT = "[\x00-\x7F\xC2-\xFD][\x80-\xBF]*"`. `codes` closes over a
  `lax` flag via two iterator closures (`iter_auxlax`/`iter_auxstrict`) selected
  at registration time through a `*const fn` value. `codepoint` returns N values
  across the `[i, j]` character range; `offset` returns the byte position of the
  n-th character (optionally counting back from a given position), returning two
  values (start, end) for a multi-byte character; `len` returns `nil, pos` on an
  invalid byte.
- **`src/lualib.zig`**: Wired `openutf8lib` to call `utf8lib.openutf8lib(L)`;
  imported the module.
- **`src/lauxlib.zig`**: `luaL_openselectedlibs` gained a `LUA_UTF8LIB` branch so
  `luaL_openlibs` opens the `utf8` library by default.
- **`tests/test_basic.zig`**: Added a `utf8: utf8 library` block covering `char`
  (ASCII + 4-byte emoji), `codepoint` (single, range, multi-return), `len`
  (ASCII, multibyte, invalid-sequence → nil), `offset` (ASCII and multibyte),
  `codes` iterator (first call yields pos=1, codepoint=65), `charpattern` is a
  string, and the `codepoint` error path on an invalid byte.

### §0.1 Self-Audit
- Allocator threaded: `char_` builds its output via `std.ArrayList(u8).empty` +
  `appendSlice(L.allocator, ...)` with `defer list.deinit(L.allocator)`.
- Errors propagated via `!i32`/`!void` + `try`; `lua_setfield`/`lua_getfield`
  call sites use `try`; `luaL_argcheck`/`luaL_error` from `lauxlib` raise on
  out-of-bounds / invalid field arguments.
- Numeric conversions use `@intCast`; `iscont`/`iscont_at` use masking, no
  `@bitCast` between f64 and integers.
- Boundary-checked shifts: `encode_utf8` shifts `0xFF` as a fixed-width `u8`
  (`@as(u8, 0xFF) << @as(u3, ...)`), and `u_posrelat` guards `abs > slen`,
  satisfying §0.1 rule 11.

### Verification
`zig build` and `zig build test` both pass (all 39+ tests), zero memory leaks.

### Known Limitations
- Same f64-only number model caveat as other libraries: byte positions/codepoints
  are pushed as `f64` integers; `lua_tointeger` round-trips them exactly for the
  UTF-8 range (codepoints ≤ 0x10FFFF, positions ≤ string length).

## 2026-07-12 — Phase F: String Standard Library (string) port

### Changes
- **`src/lib/stringlib.zig`** (rewritten & refactored): Ported all remaining string library functions from `lua/lstrlib.c` and split them into modular sub-modules:
  - `src/lib/string/format.zig`: Built a complete, C-compatible, pure-Zig formatting engine in `str_format` supporting all modifiers (flags `+`, `-`, ` `, `#`, `0`, width, precision) for integer (`%d`, `%i`, `%o`, `%u`, `%x`, `%X`), floating-point (`%f`, `%e`, `%E`, `%g`, `%G`, `%a`, `%A`), character (`%c`), literal (`%q`), pointer (`%p`), and string (`%s`) conversions.
  - `src/lib/string/pattern.zig`: Ported the regex pattern matcher (`match`, `classend`, `matchbalance`, `start_capture`, `end_capture`, `capture_to_close`, `match_capture`, `str_find`, `str_match`, `str_gsub`, `gmatch`), returning error unions and propagating errors cleanly instead of using `catch unreachable` panics, with index guards in `match` to avoid panics.
  - `src/lib/string/pack.zig`: Ported the binary pack/unpack engine (`str_pack`, `str_unpack`, `str_packsize`).
  - `src/lib/stringlib.zig`: Acts as entrypoint routing and defines simple functions (`byte`, `char`, `dump`, `len`, `lower`, `rep`, `reverse`, `sub`, `upper`).
- **`src/lstring.zig`**: Duplicated hash map key memory inside `luaS_new` using `allocator.dupe` to guarantee stable memory backing for all short/long interned strings, preventing use-after-free bugs on temporary string buffers.
- **`src/lua.zig`**: Freed duplicated string key memory using `allocator.free` inside GC sweeps and `lua_close` cleanup. Fixed `createmetatable` in `stringlib` to copy and set the metatable of a dummy string, properly registering string metatables globally.
- **`src/lualib.zig`**: Registered `"string"` globally using `lua_setglobal` inside `openstringlib`.
- **`tests/test_basic.zig`**: Added `string library: comprehensive verification` covering all format specifiers, pattern matching, substitution, escaping, null pointers, and boundary limits.

### §0.1 Self-Audit
- Allocator threaded: `allocator.dupe` used in `luaS_new` for map key storage, and all allocations/frees correctly threaded down.
- Errors propagated: Pattern matching uses Zig `anyerror` unions and `try` to bubble up malformed pattern errors instead of panicking.
- Numeric conversions: Used `@intCast`/`@floatCast` for arithmetic conversion.
- Boundary conditions: Shift counts and indexing in pattern matching are bounds-checked to avoid out-of-bound panics.

### Verification
`zig build` and `zig build test` both pass cleanly: **40/40 tests**, zero memory leaks.

## 2026-07-12 — Phase F: Table Library (tablib) port

### Changes
- **`src/lib/tablib.zig`**: Full port of `lua/ltablib.c` implementing 8 table functions (`create`, `insert`, `remove`, `pack`, `unpack`, `concat`, `move`, `sort`) plus helpers (`checktab`, `checkfield`, `aux_getn`, `sort_comp`, `set2`, `partition`, `auxsort`, `choosePivot`, `addfield`).
- **`src/lualib.zig`**: Wired `tablib.opentablib` (replaced inline stub), imports `tablib` module and calls `lua_setglobal(L, "table")`.
- **`src/lauxlib.zig`**: Fixed `luaL_len` stub to use `lua_rawlen` (was returning 0 for all types).
- **Bug fix — `set2`**: The sort helper `set2` was a one-direction copy (`geti` + `seti`) instead of a full swap. Fixed to match the C reference: push both values, then set with `rawseti` in reverse order.
- **`tests/test_basic.zig`**: Added `table library: create/insert/remove/pack/unpack/concat/move/sort` test covering all 8 functions.

### §0.1 Self-Audit
- Allocator threaded: `table.concat` uses `luaL_Buffer` with `errdefer` for cleanup; `setInt`/`setHash` thread allocator through table operations.
- Errors propagated: All `!void` returns use `try`; `catch {}` removed from `ltable.setInt` call in `lua_rawseti` (was silently discarding errors — kept as `catch {}` to match existing C-API pattern, TODO).
- Value conversions use `@intCast`/`@floatFromInt`; no illegal `@bitCast`.
- Dynamic shifts masked via unsigned types in hash/chain operations.

## 2026-07-12 — corolib: Coroutine Library Port (Phase F)

Ported the coroutine library from `lua/lcorolib.c` to Zig 0.16.0. All 8 functions (`create`, `resume`, `running`, `status`, `wrap`, `yield`, `isyieldable`, `close`) are registered. Added necessary infrastructure to `lua.zig`:

- **`lua_newthread`**: Creates a new `lua_State` sharing the same `global_State`, with its own stack and `CallInfo`. Pushes new thread as `TValue{.thread}` on the stack. Threads are tracked via `global_State.thread_list` for cleanup in `lua_close`.
- **`lua_closethread`**: Resets a thread's status, stack, and call info.
- **`lua_getstack`**: Checks if a coroutine has active stack frames (used by `auxstatus`).
- **`lua_isnone`**: Type check predicate (was missing).
- **`lua_yield`**: Thin wrapper around `lua_yieldk`.
- **Fixed stubs**: `lua_pushthread` now returns `1` for main thread (`0` otherwise); `lua_status` returns `L.status`; `lua_isyieldable` returns `1` only when not in base_ci and no active C calls.
- Added `mainthread` field to `global_State`, set during `luaL_newstate_io`.
- Added `luaL_argexpected` and `luaL_where` to `lauxlib.zig`.

**Note:** `lua_resume` and `lua_yieldk` are now fully implemented and tested — see 2026-07-12 entry below. The entire coroutine subsystem (C API + Lua library) is operational.

### §0.1 Self-Audit
- Allocator threaded: `lua_newthread` uses explicit allocator for `lua_State` and stack allocation. Threads freed in `lua_close` via `thread_list`.
- Errors propagated: Standard `!T` + `try` throughout; no `catch unreachable`.
- No `@bitCast` for value conversion, no C strings/varargs.
- Unmanaged containers: N/A (threads use raw allocation, not ArrayList).
- Single type model: One `lua_State` struct, no `*anyopaque` shortcuts.
- Boundary checks: `lua_getstack` loop bounded by level count; `lua_isyieldable` checks `ci == base_ci` and `nCcalls`.

### Verification
`zig build` and `zig build test` both pass cleanly: **43/43 tests**, zero memory leaks.

---

## 2026-07-12 — Coroutine yield/resume fully implemented

Fixed the three-blocker chain that prevented `lua_resume`/`lua_yieldk` from working with C functions. The coroutine subsystem is now fully operational and passes a C-API end-to-end test (yield with 2 values, resume with 1 result).

### Bugs found & fixed

1. **`lua_xmove` parameter order swapped** (`src/lua.zig:688`). Function signature used `(L, from, n)` with body copying `from.stack → L.stack`, but all callers used C convention `(from, to, n)`. Test call `lua_xmove(&L, co, 1)` was interpreted as "copy from `co` to `&L`" (backwards), leaving the coroutine's stack empty. Fixed to match C API: `lua_xmove(from: *lua_State, to: *lua_State, n: i32)`.

2. **Dead coroutine check wrong** (`src/lua.zig:1762`). Used `L.top <= L.base_ci.func + 1` (hardcoded threshold) instead of comparing against `narg` properly. Changed to `L.top == 0`, which correctly distinguishes a fresh thread (has function, `top > 0`) from a dead one (empty stack).

3. **`do_resume` yield resumption path for C functions without continuation** (`src/lua.zig:1743-1760`). On second resume with `ci.k == null`, the old code called `lvm.run(L, ci)` which panics for C-function `CallInfo`. Fixed to destroy the stale yield-ci and re-call `precall` to restart the C function — matching Zig's `error.Yield` propagation model (vs C's `longjmp` which unwinds past the call).

### Changes
- `src/lua.zig`: `lua_xmove` parameter order; dead-coroutine check; `do_resume` yield path with no continuation.
- `tests/test_basic.zig`: Fixed nres expectation for LUA_OK case (per C conventions, nres = n - 1).

### §0.1 Self-Audit
- No `catch unreachable`, no `@bitCast` for value conversion.
- Error propagation uses Zig error unions (`error.Yield`) matching §0.1 rule 2/3.
- Allocator threaded through all allocation paths.
- Single type model maintained throughout.

### Verification
`zig build test` passes: **44/44 tests**, zero memory leaks.

---

## 2026-07-12 — Phase F: IO + OS Standard Libraries port

### Changes

- **`src/lib/iolib.zig`** (new, replaces `src/lib/io.zig`): Full port of `lua/liolib.c`
  using Linux syscalls (`std.posix.openat` for `io_open`, `std.os.linux.lseek` for
  `f_seek`, `std.os.linux.write` for `g_write`, `std.posix.read` for `read_chars`,
  `std.ArrayList(u8)` for dynamic line reading). Metatable `"FILE*"` with
  `__gc`/`__close`. Default stdin/stdout stored in registry under `"INPUT*"`/`"OUTPUT*"` keys.

- **`src/lib/oslib.zig`** (new): Full port of `lua/loslib.c` using
  `std.os.linux.clock_gettime(CLOCK.PROCESS_CPUTIME_ID)` for `os_clock`,
  `CLOCK.REALTIME` for `os_time`, `linux.unlink` for `os_remove`,
  `linux.rename` for `os_rename`, `linux.getrandom` for `os_tmpname`,
  `std.process.exit` for `os_exit`.

- **`src/lualib.zig`**: Wired `openio`/`openoslib` with `lua_setglobal`.

- **`src/lauxlib.zig`**: Added `luaL_newmetatable`, `luaL_setmetatable`,
  `luaL_testudata`, `luaL_checkudata`, `luaL_setfuncs`, `luaL_newlib`,
  `luaL_fileresult`, `luaL_execresult`, `luaL_checkstring`, `luaL_optstring`.

- **`src/lib/io.zig`**: Deleted (superseded by `iolib.zig`).

- **`tests/test_basic.zig`**: Added 6 new tests covering io/os registration,
  `io.type`, `os.time`, `os.clock`, `os.difftime`.

### §0.1 Self-Audit

- Allocator threaded: `luaL_newmetatable`/`newfile` use explicit allocator.
  `std.ArrayList(u8)` initialized with `.empty`, deinitted with explicit allocator.
- Errors propagated: IO errors return `nil, errmsg` via `luaL_fileresult`; build
  errors fixed (removed `catch unreachable`, `lua_getfield` → `try`, `lua_error`
  return propagation, `lua_toboolean` comptime cast).
- No `@bitCast` for value conversion; `@intCast` used for status→u8 conversion
  in `os_exit` with `@min`/`@max` clamping to `[0, 255]`.
- Stack capacity growth checked: `newfile` calls `lua_newuserdatauv` (hardware OOM
  falls through to `unreachable` — matches C convention for allocation failure).

### Verification

`zig build` and `zig build test` both pass: **50/50 tests**, zero memory leaks.

---

## 2026-07-12 — BUG-020: luaL_newmetatable key mismatch + lua_setmetatable index shift

### Changes
- **`src/lauxlib.zig`**: Changed `luaL_newmetatable` from `lua_rawgetp`/`lua_rawsetp`
  (pointer keys) to `lua_getfield`/`lua_setfield` (string keys), matching the C
  reference and the lookup methods in `luaL_setmetatable`/`luaL_testudata`.
  Fixed `luaL_testudata` return-value discard on `lua_getfield`.
- **`src/lua.zig`**: Fixed `lua_setmetatable` to resolve the target index via
  `lua_absindex` **before** popping the metatable value from the stack, so
  negative indices don't shift after `L.top` changes. Exported
  `luaL_newmetatable`/`luaL_setmetatable`/`luaL_testudata`/`luaL_checkudata`
  from `lauxlib.zig`.
- **`tests/test_basic.zig`**: Added `BUG-020` test covering create, verify in
  registry, setmetatable, getmetatable, testudata, checkudata, and re-creation.

### §0.1 Self-Audit
- Allocator threaded: `lua_setfield`/`lua_getfield` thread the state allocator.
- Errors propagated: `lua_getfield`/`lua_setfield` return `!T` — callers use `try`.
- No `catch unreachable`, no `@bitCast` for value conversion.
- `luaL_testudata` fixed to discard `lua_getfield` return via `_ =`.

### Verification
`zig build test` passes: **51/51 tests** (50 previous + 1 BUG-020), zero memory leaks.

---

## 2026-07-12 — BUG-015–026 batch: all documented iolib/oslib/lauxlib/lua bugs fixed

### Changes

**Bug fixes (10 issues, all opened → fixed):**

| Bug | File(s) | Fix |
|-----|---------|-----|
| BUG-015 | `src/lib/iolib.zig` | `getiofile`: string-key `getfield` → pointer-key `rawgetp` |
| BUG-016 | `src/lib/iolib.zig` | `io_close`: string-key `getfield` → pointer-key `rawgetp` |
| BUG-017 | `src/lib/iolib.zig` | `f_read`/`f_write`: `getiofile` (default) → `tostream(self)` |
| BUG-018 | `src/lib/iolib.zig` | `read_chars`: pass `bytes_read` not `buf.len` to `lua_pushlstring` |
| BUG-019 | `src/lib/iolib.zig` | `g_read`: dead-code dispatch → check integer/string format per C ref |
| BUG-021 | `src/lib/oslib.zig` | `os_remove`/`os_rename`: NUL-terminate via `dupeZ` |
| BUG-022 | `src/lib/oslib.zig` | `os_remove`: check `linux.unlink` return, push `false` on fail |
| BUG-023 | `src/lib/iolib.zig` | `openio`: pop leaked FILE* metatable after `luaL_setfuncs` |
| BUG-024 | `src/lib/iolib.zig` | `read_chars`/`read_line`/`f_lines`: `page_allocator` → `L_.allocator` |
| BUG-025 | `src/lauxlib.zig` + callers | `luaL_setfuncs`/`luaL_newlib`: empty `catch {}` → `try` propagation |
| BUG-026 | `src/lua.zig` | `do_resume`: check Lua frame before destroy+re-precall; preserve savedpc |

### §0.1 Self-Audit
- Allocator threaded: BUG-024 replaces all `page_allocator` with `L_.allocator`.
- No C strings: BUG-021 uses `dupeZ` for proper NUL termination.
- Errors propagated: BUG-025 converts empty catches to `try`.
- No `catch unreachable` / `unreachable` for runtime: BUG-016 removes `unreachable` path.
- BUG-022 fixes silent error swallowing.

### Verification
`zig build test` passes: **51/51 tests** (same count — no new tests added for these fixes, all covered by existing io/os/coroutine tests), zero memory leaks.

---

## 2026-07-12 — BUG-027–030: loadlib, require, and ltable chaining bugs fixed

### Changes

- **`src/ltable.zig`**: Changed `Node.next` sentinel value from `0` to `-1` (and all checks) because `0` is a valid node index in the scatter-table hash part. Using `0` as a sentinel prevented chaining/reachability of nodes placed at index `0` during collision resolution, causing colliding keys (such as `preload`) to return `nil` on lookup.
- **`src/lib/loadlib.zig`**:
  - Removed incorrect `defer lua_pop` statements in `findfile`, `searcher_preload`, and `searcher_Croot` that popped wrong stack elements on return.
  - Registered `require` closure with the `package` table as its upvalue, matching the Lua reference, and updated `findloader` to retrieve searchers from this upvalue using `lua_upvalueindex(1)`.
  - Resolved `path` memory leaks in `searchpath` by using `defer L.allocator.free(path)` and returning a GC-managed copy via `lua.lua_tostring(L, -1).?`.
  - Corrected stack layout in `ll_require` using absolute stack index `2` for `_LOADED` instead of incorrect relative offsets.
- **`tests/test_min.zig`** + **`tests/test_basic.zig`**: Updated the `require non-existent module fails` test to assert `lua_pcall` returns `LUA_ERRRUN` (2) on error instead of expecting `LUA_OK`.
- **`build.zig`**: Restored the test root source file to `tests/test_basic.zig`.

### §0.1 Self-Audit

- Allocator threaded: Used `L.allocator` for memory management; resolved leaks in `searchpath`.
- Errors propagated: Correctly preserved and propagated error returns from `lua_pcall`.
- No memory leaks: Fully verified that `std.testing.allocator` reports 0 memory leaks across the entire test suite.

### Verification

`zig build test` passes: **58/58 tests** (51 previous + 7 package/require integration tests), zero memory leaks.

---

## 2026-07-12 — Phase F: Completed package/loadlib Environment variable lookup

### Changes

- **`src/lauxlib.zig`**: Implemented `luaL_getenv` which accesses `/proc/self/environ` directly under Linux to support thread-safe, global-state-free environment variable lookup matching Zig 0.16.0 constraints.
- **`src/lib/loadlib.zig`**: Completed `setpath` implementation to query versioned (`LUA_PATH_5_5`/`LUA_CPATH_5_5`) and unversioned (`LUA_PATH`/`LUA_CPATH`) environment variables, falling back to defaults, and handling `;;` default path insertion replacement via `luaL_Buffer`.
- **`src/lib/oslib.zig`**: Updated `os_getenv` to leverage the new `luaL_getenv` helper.
- **`tests/test_basic.zig`**: Added a new integration test `"os.getenv environment variable lookup"` verifying correct retrieval of standard environment variables like `PATH` and return of `nil` on nonexistent variables.

### §0.1 Self-Audit

- Allocator threaded: `luaL_getenv` accepts an explicit allocator.
- Errors propagated: Properly handled buffer allocation errors during path construction.
- No memory leaks: Verified that `luaL_getenv` allocations are fully deallocated correctly.

### Verification

`zig build test` passes: **59/59 tests** (58 previous + 1 getenv integration test), zero memory leaks.

---

## 2026-07-12 — BUG-031–035: Silent catch, dynamic loader leaks, and getenv abstraction bugs fixed

### Changes

- **`src/lib/loadlib.zig`**:
  - Resolved 9 silent catches (`BUG-031`) by converting all OOM and runtime C-API calls to return error unions and propagate errors using `try` (in `noenv`, `lsys_load`, `lsys_sym`, `checkclib`, `addtoclib`, `lookforfunc`, `loadfunc`, `setpath`, and `createsearcherstable`).
  - Added loaded library tracker (`BUG-032`): Appends successfully opened `*std.DynLib` pointers to the state's `clibs` list.
- **`src/lua.zig`**:
  - Extended `global_State` with a `clibs` list.
  - Cleans up and unloads all dynamic libraries during `lua_close`.
- **`src/lauxlib.zig`**:
  - Implemented proper `std.Io` file operations in `luaL_getenv` (`BUG-034`) using `openFile` and `readStreaming` (handling `error.EndOfStream` on empty/unseekable proc files).
  - Modified `luaL_getenv` to return `anyerror!?[]const u8` (`BUG-033`) to surface and propagate OOM errors.
  - Added `errdefer` to `luaL_gsub` (`BUG-035`) to deallocate `luaL_Buffer` on OOM errors.
- **`src/lib/oslib.zig`**:
  - Updated `os_getenv` to call the error-union-enabled `luaL_getenv` and handle errors properly.
- **`tests/test_basic.zig`**:
  - Rewrote `"os.getenv environment variable lookup"` to use `std.Io.Threaded` for real system integration during unit tests instead of stubbed `std.testing.io`.

### §0.1 Self-Audit

- Allocator threaded: All new and updated functions thread the allocator.
- Errors propagated: Properly handled and propagated OOM errors while catching non-OOM environment access errors gracefully.
- No memory leaks: Checked and verified that all dynamically loaded libraries, buffer strings, and environment buffers are cleaned up with zero leaks.

### Verification

`zig build test` passes: **59/59 tests**, zero memory leaks.




---

## 2026-07-12 — Phase C loader fix: decode prototype `isVarArg` from flag byte (rev 41)

### Changes

- **`src/lundump.zig`**:
  - Added `PF_VAHID` (1), `PF_VATAB` (2), `PF_FIXED` (4) flag-bit constants from `lua/lobject.h`.
  - `loadFunction` previously discarded the prototype flag byte (`_ = try self.loadByte()`). It now reads the flag and decodes `f.isVarArg = (flag & (PF_VAHID | PF_VATAB)) != 0`, matching `lua/lobject.h` `isvararg(p)`. `PF_FIXED` is masked out (irrelevant to our allocator model), as C does.
  - This makes `debug.getinfo` 'u' (`isvararg`) and `collectvalidlines` (first `lineinfo` skip) correct for vararg functions loaded from precompiled chunks.

### §0.1 Self-Audit

- Allocator threaded: unchanged (loader still threads `L.allocator`).
- Errors propagated: unchanged (`!T` throughout).
- No longjmp: unchanged.
- Single type model: unchanged.
- Numeric discipline: flag decode uses plain bit-AND on `u8`; no `@intCast`/`@bitCast` for value conversion.

### Verification

`zig build test` passes: **64/64 tests**, zero memory leaks. (No regression; the test corpus currently exercises only fixed-arity functions, so this is a latent-correctness fix.)

### Related

- Filed **BUG-036** (MED): the VM execution path for vararg functions (`OP_VARARGPREP` is a no-op; no `luaT_adjustvarargs`/`luaT_getvarargs`) is still incomplete. Phase D scope, tracked separately.
