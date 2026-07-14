# AGENTS.md — Lua.zig (Zig 0.16.0 port of the Lua reference)

> **Purpose of this file:** Instruct coding agents (and future sessions) on the
> current state of the `luazig` codebase and the concrete work required for the
> next phase of development. Read it fully before making changes.

---

## 0. MANDATORY — Code it right from the start (highest priority)

> **This is the first priority, above features and above "making it compile."**
> We are porting Lua to Zig **to get a better language implementation**, not to
> transliterate C line-by-line. Every function you write MUST follow Zig 0.16.0
> idioms from the first keystroke. We will NOT ship a C-shaped port and "fix it
> later".
>
> **Rule of thumb:** if your code looks like the C reference with `zig` keywords
> swapped in (status `i32` returns, `lua_Alloc` callbacks, `page_allocator`
> globals, `[*:0]` strings, `catch unreachable`, `unreachable` for runtime
> errors), you are doing it wrong. Rewrite it.

### 0.1 Non-negotiable rules (violations are rejected)

These are hard requirements. Do not deviate without an explicit, written
justification in your commit message, and even then prefer the Zig way.

1. **Thread the allocator. Never hardcode `std.heap.page_allocator`.**
   Every function that allocates takes an explicit `allocator: std.mem.Allocator`
   parameter (capability-as-parameter, skill §4.1). The C `lua_Alloc`
   function-pointer typedef is **retired** — use Zig's `std.mem.Allocator`
   interface instead.

2. **Propagate errors with `!T` + `try`/`catch`. Never `catch unreachable` on
   allocation, and never use `unreachable` for a real runtime condition.**
   `catch unreachable` panics on OOM; Lua must return `LUA_ERRMEM` via the error
   path. `unreachable` is only for provably-impossible states (e.g. an exhausted
   `switch`).

3. **Replace Lua's `setjmp`/`longjmp` with Zig error unions — completely.**
   There is no `lua_longjmp` control-flow hack in correct Zig code. Use `!T`
   returns and `try`; let the compiler's error propagation replace the C
   non-local jump. Do not port `luaD_rawrunprotected`/`lua_longjmp` mechanics.

4. **Use `@intFromFloat` / `@floatFromInt` / `@intCast` for numeric
   conversions. Never `@bitCast` between `i64`/`f64`/`usize` to convert a value.**
   `@bitCast` is only for *bit-identical* reinterpretation (same bit width, same
   meaning). Value conversion is a different operation and `@bitCast` produces
   silently wrong numbers.

5. **Use bounded `[]const u8` / `[]u8` slices, not C null-terminated
   `?[*:0]const u8`.** Only the C ABI boundary (if any) uses sentinels, and even
   then prefer slices.

6. **No C-style varargs `...` in signatures** — they are not valid Zig and will
   break the build. Use explicit parameters, `anytype`, or a `std.fmt`-style
   approach.

7. **Use unmanaged containers correctly.** Growable state (tables' array/hash
   parts, string tables) uses `std.ArrayList`/`std.array_hash_map.*` initialized
   with `.empty` and an explicit allocator (skill §3.3). Never call `.append` on
   a slice — slices have no `append`.

8. **Use the `TValue = union(enum)` tagged union** for values — this is the
   correct Zig replacement for Lua's C NaN-boxing. Do not regress to raw `f64`
   bit-tagging or `@bitCast` tricks to distinguish types.

9. **Single, consistent type model.** One `lua_State`, one `lua_CFunction`, one
   `global_State` (see §4.1). No `*anyopaque` shortcuts for Lua objects. Nullable
   references are Zig optionals (`?*T`), checked with `if (opt) |v|` / `orelse`.

10. **Adopt juicy-main + `std.Io` threading** (skill §3.1–3.2). All user-facing
    and file I/O flows through the `io: std.Io` from `std.process.Init`, not
    `std.debug.print` or raw C file APIs. `iolib`/`oslib` must take `io`.

11. **Check boundary conditions on dynamic bitwise shifts.** Bitwise shift counts in Zig must be unsigned integers (e.g. `u5` or `u6`), and shifting by equal to or greater than the bit width of the type will panic at runtime. Always mask or bounds-check the shift amount beforehand (e.g. mask with 63/31 or check limits).

12. **Never swallow runtime errors with empty or dummy `catch` blocks.** Discarding errors silently (e.g. `catch {}` or `catch |e| {}`) is strictly prohibited. All error conditions (including table accessors/mutators triggering metamethods) must either be explicitly propagated via `try`, handled with a fallback, or cleanly reported.

13. **Validate stack capacity growth before writing.** When reserving stack slots using `lua_checkstack` or similar functions, verify the return boolean/status to ensure memory was successfully allocated before writing to indices past the current top.

14. **Ensure type-check and conversion predicates are precise.** Never use stub/dummy return values for standard API functions (like `lua_isinteger` or `lua_tointegerx`). Ensure float-to-integer conversion checks have logic for fractional parts (e.g. `math.trunc(x) == x`).

### 0.2 How to work

- Before writing any function, ask: *"What would a native Zig programmer write
  here?"* — then write that. Diff against `lua/` only for **semantics** (opcode
  behavior, algorithm), never for **structure**.
- **OKF documentation mandate.** The project uses a Google OKF v0.1 knowledge
  bundle at `docs/`. Every time you complete a phase, add a feature, or change
  architecture, update the relevant `docs/*.md` files and append an entry to
  `docs/log.md`. The bundle must reflect the current state of the project at
  all times.
- Prefer `defer`/`errdefer` for cleanup over manual `free`.
- Prefer `anytype` + `comptime` for generic helpers (skill §4.4) over void
  pointers or `@ptrCast`.
- Keep `switch` exhaustive; let the compiler prove completeness.
- If a C macro expands to a non-trivial expression, make it an `inline fn` or
  `comptime` fn, not a textual copy.

### 0.3 Gate

A module is not "done" until it (a) compiles, (b) is exercised by a passing test,
**and (c) passes every rule in §0.1.** Agents must self-audit each change
against §0.1 before reporting completion.

---

## 1. What this project is

`luazig` is a from-scratch port of the Lua reference implementation (the C tree at
`lua/`, which is **Lua 5.5.1** per `lua.h`) to **Zig 0.16.0**. The goal is a
working Lua interpreter that follows the reference semantics while adopting the
Zig 0.16.0 idioms described in the `zig-0.16.0-development` skill
(`std.process.Init` juicy main, explicit `std.Io`, unmanaged containers, no
`@cImport`).

The reference C sources live in `lua/` (the sibling directory) and are the
**authoritative source of truth** for opcodes, data layouts, and semantics.
Always diff against `lua/` when implementing a module.

---

## 2. Current status — honest assessment

**The project is past initial setup.** The foundational §0.1 rules are enforced
throughout the codebase. The executable and library compile, tests pass, and the
repo is initialized with bookmark `main`. The upstream Lua reference C sources
are available as a Git subrepo.

### What is genuinely done
- **Module layout exists.** Files mirror the C modules: `lua.zig` (core API),
  `lvm.zig` (opcodes + VM stub), `llimits.zig`, `luaconf.zig`, `lauxlib.zig`,
  and `src/lib/*` for the standard libraries (`lstate.zig` deleted — contents
  merged into `lua.zig`).
- **Single type model (§4.1).** One `lua_State` (struct in `lua.zig`), one
  `lua_CFunction`, one `global_State`. No `*anyopaque` shortcuts. No duplicate
  structs.
- **Real stack (§4.2).** `lua_State.stack` is a `[]TValue` slice, allocated in
  `luaL_newstate`. All stack ops use direct slice indexing — no `@ptrCast` abuse.
- **Correct instruction decode (§4.3).** `GETARG_*`/`SETARG_*` use proper bit
  shifts and masks. No `i.ptr[...]` on `u32`.
- **Version constants match the C reference (§4.4).** Set to Lua 5.5.1.
- **No violations of §0.1 rules 1–8** in the active codebase. `page_allocator`,
  `catch unreachable`, varargs, `@bitCast` for value conversion, and C strings
  have all been removed.
- **juicy-main entry point** is in `src/luazig.zig` using `std.process.Init`.
- **`build.zig`** builds exe (`luazig`) + library (`lua`). Test step works.
- **92+ passing tests** in `tests/test_basic.zig` covering nil/boolean/number/integer/
   string/table type checks, stack push/pop round-trip, string interning,
   table setfield/getfield, seti/geti + length, empty/remove length, hash-part
   string keys, `next` traversal, stack-key gettable/settable, bytecode loader,
   VM execution, **8 metamethod tests** (`__index`, `__newindex`, `__add`, `__eq`, `__lt`/`__le`),
   error propagation/pcall, GC, all Phase F libraries, coroutine yield/resume,
   io library registration + type check, os library registration + time/clock/difftime
   + os.date/*t, os.execute, os.setlocale, io buffering, file:read("*n"), debug lib.
- **Phase B complete — Tables & string interning.**
   Real `lua_Table` (array part + chained-scatter hash part) in `src/ltable.zig`;
   string interning in `global_State.strt` (`std.array_hash_map.String`) in
   `src/lstring.zig`. Table API fully wired: `lua_createtable`, `lua_gettable`/
   `getfield`/`geti`/`rawget`/`rawgetp`, `lua_settable`/`setfield`/`seti`/
   `rawset`/`rawseti`/`rawsetp`, `lua_next`, `lua_rawlen`.
- **Phase C complete — Bytecode loader.**
   Precompiled Lua 5.5.1 bytecode loader in `src/lundump.zig`. Stream buffer `Zio`
   implemented on top of `lua_Reader`. Recursively parses headers, varints, strings,
   instructions, constant pool, upvalues, sub-prototypes, and debug info. `lua_load`
   fully wired to detect binary chunk signature (`\x1b`) and load it onto the stack.
- **Phase D complete — Working VM.**
   Implemented the VM interpreter loop in `src/lvm.zig` executing all core opcodes, resolving nested closures, upvalues, and supporting `CallInfo` stack frame pushes/returns. Wired `lua_callk` and `lua_pcallk`. Added state-specific sweep list `allgc` on `global_State`, verifying everything with an integration test and zero leaks.
- **`global_State` is now real** (allocator, `strt`, seed, registry, `allgc`), created in
   `luaL_newstate` and freed recursively in `lua_close`.
- **Google OKF v0.1 knowledge bundle** lives in `docs/` and is kept current with
   every phase (architecture, log, glossary). See `docs/README.md`.
- **`lua/` is a Git subrepo** tracked via `.hgsub` (`[git]git@github.com:lua/lua.git`),
   providing the authoritative Lua 5.5.1 C reference for porting.
- **Repository initialized** with `.hgignore`, `.hgsub`, `LICENSE`, `AGENTS.md`.

- **Phase E complete — Metamethods, Error handling, and GC.**
   All Phase E items fully implemented: `__index`/`__newindex` chains (up to MAXTAGLOOP=2000), arithmetic and comparison metamethods, native error propagation (longjmp-free `anyerror`/`try` continuation path), protected calls with custom `errfunc` handlers on active stack frames, and a complete mark-and-sweep garbage collection engine for unreferenced tables and interned strings. Stale duplicated `src/lstate.zig` has been removed. Verified by passing tests with zero memory leaks.

- **Phase F complete — All standard libraries implemented (2026-07-12).**
   All 10 libraries fully implemented and tested. The `debug` library (`src/lib/debug.zig`) adds 16 functions matching the C `dblib[]` table exactly: `getinfo`, `traceback`, `getupvalue`/`setupvalue`, `getlocal`/`setlocal`, `sethook`/`gethook`, `upvalueid`/`upvaluejoin`, `getregistry`, `getmetatable`/`setmetatable`, `getuservalue`/`setuservalue`, plus `debug`. Supporting infrastructure (`luaO_chunkid`, `luaG_getfuncline`, `luaF_getlocalname`, `lua_getinfo`, `lua_getlocal`, `lua_setlocal`, `lua_sethook`/gethook, `luaL_traceback`) fully ported. **92+ tests pass, zero memory leaks.**

- **Phase D fix — VM vararg execution (BUG-036 FIXED, 2026-07-13).**
   Ported `luaT_adjustvarargs`/`luaT_getvarargs`/`luaT_getvararg` into `src/ltm.zig` and wired `OP_VARARGPREP`/`OP_VARARG`/`OP_GETVARG` in `src/lvm.zig`. Vararg functions (`function f(a, ...) ... end`, `f(...)`, `select`, `{...}`) now execute correctly. Added `lua_Proto.flag` and `CallInfo.nextraargs`. The hidden-vararg frame is relocated by `buildhiddenargs` (matching the C reference) and restored on every return path: `.RETURN`, `.RETURN0`, `.RETURN1`, and `.TAILCALL` (`.lua`/`.c`) now correct `ci.func`/`ci.base`, and `luaK_finish` sets `SETARG_C(pc, numParams + 1)` on the `RETURN0`/`RETURN1` → `RETURN` conversion for `PF_VAHID` functions. Verified against the Lua 5.5.1 reference binary. **92+ tests pass.**

### What is NOT done (future phases)
Phase H remaining items — see §8 and the Phase H section below.

### Phase H partial status

Items from Phase H have been addressed incrementally during earlier bug-fix work.
See §8 for the complete, up-to-date status of each H.x sub-phase.

---

## 3. Architecture constraints (Zig 0.16.0)

Follow the `zig-0.16.0-development` skill strictly:
- `main` MUST take `std.process.Init` (already done in `src/luazig.zig`).
- All I/O goes through the `io: std.Io` from `init.io` (used for `print`, file
  I/O in `iolib`, `oslib`). Do **not** use `std.debug.print` for user-facing
  output in the final libraries — thread `io` down.
- Unmanaged containers only; initialize with `.empty` (not `.{}`).
- `@cImport` is forbidden. If any C interop is ever needed (it should not be for
  a pure port), use `addTranslateC` in `build.zig`.
- Prefer `@intFromPtr`/`@intFromEnum` bit tricks consistent with the C source,
  but keep types honest (a `u32` instruction is a `u32`, not a pointer).

---

## 4. DONE — Foundational work (initial commit)

All four prerequisites from the original §4 list are complete:

### 4.1 ~~Reconcile the type model~~ ✅
- Single `lua_State` struct in `lua.zig`. `llimits.zig` stripped of type
   definitions. `lua_CFunction`/`lua_KFunction`/etc. defined in `lua.zig`.
- Duplicate `lua_State` in `main.zig` deleted. `main.zig` itself deleted.
- `global_State` is now real in `lua.zig` (allocator, `strt`, seed, registry),
   created/freed in `luaL_newstate`/`lua_close`. `lstate.zig` still carries a
   stale duplicate and is not compiled.

### 4.2 ~~Give the state a real stack~~ ✅
- `stack: usize` → `stack: []TValue`. Allocated in `luaL_newstate` via `gpa`.
- `lua_checkstack` uses `gpa.realloc` to grow. `stack_last` tracks capacity.
- All `@ptrCast(@alignCast(&L.stack))` replaced with `L.stack[idx]`.

### 4.3 ~~Fix instruction decode/encode helpers~~ ✅
- All `i.ptr[...]` replaced with `(i.* & ~mask) | (value << shift)` operations.

### 4.4 ~~Reconcile version constants~~ ✅
- `LUA_VERSION_*` → 5, 5, 1. `LUA_VDIR` → `"5.5"`.

---

## 5. Recommended next-phase roadmap

Work **top-down from the foundation**, validating each layer with a real test
before moving on. Do not parallelize layers that depend on each other.

### Phase B — Tables & values ✅ DONE (2026-07-10)
Implemented `lua_Table` (array part + chained-scatter hash part) in `src/ltable.zig`
and string interning in `global_State.strt` (`std.array_hash_map.String`) in
`src/lstring.zig`. Full table API wired (`lua_createtable`, `lua_gettable`/
`getfield`/`geti`/`rawget*`/`rawset*`, `lua_next`, `lua_rawlen`). `gettable`/
`settable` are raw for now (no `__index`/`__newindex` — Phase E). 15/15 tests pass.

### Phase C — Front-end (lexer/parser/compiler) or loader ✅ DONE (2026-07-10)
7. Implemented Option (b) bytecode loader (`lundump.zig`).
8. Produces fully populated recursive `lua_Proto` structures that `lua_State`/`lvm` can execute.

### Phase D — A working VM ✅ DONE (2026-07-10)
9. Implemented VM execution loop `lvm.run` supporting all core opcodes, closure capture, upvalue resolution.
10. Supported function calls, tail calls, managing `CallInfo` stack frames, and returns.

### Phase E — Error handling, GC, metatables ✅ DONE (2026-07-10)
11. ✅ `__index`/`__newindex` metamethod dispatch via `luaV_gettable`/`luaV_settable` in `src/ltm.zig`. All table opcodes and C API wired. 3 tests pass.
12. ✅ Arithmetic metamethods (`__add`, `__sub`, etc.) fully implemented in `lua_arith` and VM execution with fallback.
13. ✅ Error propagation (`lua_error`, `lua_pcall`/`lua_pcallk` with custom error handler `errfunc`, longjmp-free Zig `error`/`try` continuations).
14. ✅ Expand garbage collector (reconcile stale state, build mark/sweep on top of VMGCObject).


### Phase F — Standard libraries ✅ DONE (2026-07-12)
 15. Port library *bodies* in `src/lib/*`. Go module by module and back each with tests.
    - ✅ `baselib`: Registered standard functions, implemented all helper structures, tested with 5 new integration tests.
    - ✅ `mathlib`: All 26 functions + constants, PRNG via Xoshiro256 seeded in global_State.
    - ✅ `stringlib`: All 17 functions, modular sub-modules (format, pattern, pack), full pattern matcher.
    - ✅ `tablelib`: All 8 functions (create, insert, remove, pack, unpack, concat, move, sort).
    - ✅ `utf8lib`: All 6 functions (char, codepoint, len, offset, codes) + charpattern.
    - ✅ `corolib`: All 8 functions (create, resume, running, status, wrap, yield, isyieldable, close).
    - ✅ `bit32`: All 12 functions (band, bor, bxor, bnot, btest, shifts, rotates, extract, remove).
    - ✅ `iolib`: Full `io` library using `std.posix.openat`/`std.os.linux` syscalls; wires stdin/stdout in registry.
    - ✅ `oslib`: Full `os` library using `std.os.linux.clock_gettime`/`rename`/`unlink`/`getrandom`.
    - ✅ `debug`: All 16 functions fully implemented (2026-07-12), matching the C `dblib[]` table.
    - ✅ `loadlib`: Implemented; dynamic loading functional; `require()` chain minimal.
16. Stale `src/lib/io.zig` removed (superseded by `src/lib/iolib.zig`).

---

## 6. File-by-file guidance

| File | Status | Next action |
|------|--------|-------------|
| `build.zig` | ✅ exe+lib build OK; test step works | Expand when adding deps or test targets. |
| `src/luazig.zig` | ✅ entry point, juicy-main, basic CLI (script + REPL), `arg` table | Phase H — add `-e`, `-l`, `-i`, `-v` flags, multi-line REPL. |
| `src/lua.zig` | ✅ type model, stack, global_State, table API, binary loader, source compiler, error propagation, `luaL_dostring` (real impl), GC, all C API functions | Phase H — missing C API functions, constants. |
| `src/lundump.zig` | ✅ `loadBinaryChunk` bytecode loader, alignment, varint, string intern | Keep as-is; test coverage is complete. |
| `src/llimits.zig` | ✅ constants only, no types | Keep as-is. |
| `src/luaconf.zig` | ✅ version/layout config | Fix `LUA_VDIR` if reference changes. |
| `src/lstate.zig` | ❌ Deleted | Stale/dead code removed from the repository. |
| `src/ltm.zig` | ✅ `luaV_gettable`/`luaV_settable`, `luaT_trybinTM`, comparison helpers, all metamethod dispatch | Keep as-is; test coverage complete. |
| `src/ltable.zig` | ✅ `lua_Table` array+hash, `get`/`set`/`getInt`/`setInt`/`next`/`getn`/`deinit` | `__index`/`__newindex` dispatch now done in `ltm.zig`; keep as raw. |
| `src/lstring.zig` | ✅ `luaS_new`/`luaS_hash`/`luaS_eqstr`, interning in `global_State.strt`, GC sweep | Keep as-is; short/long string split deferred. |
| `src/lvm.zig` | ✅ run execution loop, all table opcodes via metamethods, arithmetic metamethods, vararg handling | Keep as-is. |
| `src/lauxlib.zig` | ✅ aux helpers, frame-relative getmetafield, checked option/checklstring, string buffer, traceback | Phase H — add reference system (luaL_ref/unref), missing auxlib functions. |
| `src/lualib.zig` | ✅ inline helpers for all libraries (openlibs dispatch) | Keep as-is. |
| `src/lib/*.zig` | ✅ All 10 libraries fully implemented and tested (`baselib`, `mathlib`, `stringlib`, `tablelib`, `utf8lib`, `corolib`, `bit32`, `iolib`, `oslib`, `debug`, `loadlib`) | Keep as-is; `loadlib` `require()` chain still minimal. |
| `tests/test_basic.zig` | ✅ 92+ passing tests | Add focused tests for Phase H items. |
| `docs/` | ✅ OKF v0.1 bundle (architecture, log, glossary) | Update after every phase; see `docs/README.md`. |
| `lua/` | ✅ Git subrepo tracking git@github.com:lua/lua.git | Reference source; update with `git pull` when needed. |
| `.hgsub` | ✅ defines `lua = [git]git@github.com:lua/lua.git` | Add more subrepos if needed. |

---

## 7. Verification rules for agents

- After each phase, run `zig build` AND `zig build test`. Both must succeed.
- Add a focused unit test for every function you implement (stack ops, table
  ops, each opcode). Mirror the reference `lua/testes/` suite where practical.
- Diff your data layouts and opcode semantics against `lua/` (the C reference)
  rather than inventing representations.
- Keep the single-type-model invariant: one `lua_State`, one `lua_CFunction`,
  one `global_State`. No `*anyopaque` shortcuts for Lua objects.
- Never reintroduce `@ptrCast(@alignCast(&L.stack))` as a fake stack; use a real
  slice.
- Run `zig build test` with `--test-timeout-scale=X` if a test is slow (the
  default is 1s); do not disable tests to make the build green.
- After every phase or significant change, update the OKF bundle in `docs/`
  before reporting completion. Run `docs/check_readiness.py` if it exists.
- Commit messages must include the §0.1 self-audit result.

---

### Phase G — Source-text compiler (lexer / parser / codegen)

Phases A–F are **complete**: the port runs precompiled Lua 5.5.1 bytecode through the full VM with all 10 standard libraries. The one remaining core gap is that **text source cannot yet be compiled end-to-end** — the lexer is done, but the parser and code generator are not. `luaL_dostring`/`luaL_loadstring` already delegate to `lua_load`, which only detects the `\x1b` binary signature; the source path is partially built.

**Status:** G.1–G.4 ✅ DONE (2026-07-13).

**Scope (port of `lua/llex.c`, `lua/lparser.c`, `lua/lcode.c`, + `lua/ldo.c` parser glue):**

17. **Lexer** (`src/llex.zig`) ✅ DONE: `LexState`, `luaX_init` (reserved words), `luaX_next`, `luaX_lookahead`, `luaX_newstring` (token → interned `lua_TString`), full number scanner (`str2num`/`l_str2int`/`lua_strx2number`/`l_str2d`), strings/long strings/escapes, comments, `luaX_syntaxerror`, `token2str`. Threads the allocator; no C globals. 5 unit tests in `tests/test_basic.zig` (73/73 pass).
18. **Parser** (`src/lparser.zig`) ✅ DONE: `FuncState`, `expdesc`, `luaY_parser`, `luaD_protectedparser` (the `lua_load` text branch). Recursive descent for blocks, `if`/`while`/`repeat`/`for`, `local`/`global`, functions, varargs. Replaced `luaD_throw`/`longjmp` with `!T` error returns.
19. **Code generator** (`src/lcode.zig`) ✅ DONE: `expdesc`→instruction emission, register allocation (`luaK_dischargevars`, `luaK_storevar`), jump/patch lists (`luaK_concat`, `luaK_patchtohere`) for `and`/`or`/`goto`, upvalue handling. Produces the same `lua_Proto` shapes `lundump.zig` already builds, so the VM is **untouched**.
20. Wire `lua_load` ✅ DONE: when the first byte is not `\x1b`, call `luaD_protectedparser` instead of `lundump`.
21. **Verification** ✅ DONE: compile `"return 42"` → `Proto` identical (when dumped) to the Lua 5.5.1 reference `lua/` binary; round-trip a source string through `luaL_dostring`; test count is 73/73 passing.

**Effort**: ~4,700 lines of C (llex 604 / lparser 2202 / lcode 1970 / lzio 89 / ldo glue). Moderate, well-specified, testable against the in-repo `lua/` oracle. See `docs/frontend.md` for the architecture decision and `docs/roadmap.md` §Phase G for the layer-by-layer plan.

## 8. What to work on next

All phases A–G are **done** (VM, runtime, compiler, and all 10 standard libraries, 73/73 tests passing, zero leaks). The port is fully functional and can run Lua source text directly.

The next work is **Phase H — Drop-in replacement gap closure**. See the Phase H section below for the full breakdown.

---

## Phase H — Drop-in replacement gap closure

Phases A–G built a working, self-hosting Lua interpreter. Phase H closes the gap between "working" and "drop-in replacement for Lua 5.5.1". The gaps were identified by a systematic audit comparing `luazig` against `lua/lua.h`, `lua/lauxlib.h`, and the standard library C sources.

**Status:** Partially done. H.1, H.2, H.3, H.4, and most of H.5 are complete (2026-07-14).
`lua_pushexternalstring` (H.5) is deferred — it requires a new `lua_TString` variant for
external-allocator-backed strings. H.6–H.10 remain NOT STARTED.
Updated 2026-07-14 with H.4 reference system and H.5 missing C API functions.

**Scope (portability, API completeness, stub elimination):**

### H.1 — C API stubs → implementations ✅ DONE (revs 65–69)

| Function | File | Status |
|----------|------|--------|
| `lua_concat` | `src/lua.zig:2972` | ✅ real impl — concatenates n values from stack top |
| `lua_len` | `src/lua.zig:3012` | ✅ real impl — pushes `#obj` with `__len` metamethod dispatch |
| `lua_getallocf` | `src/lua.zig:3152` | ✅ real impl — returns current allocator and user data |
| `lua_setallocf` | `src/lua.zig:3158` | ✅ real impl — sets new allocator |
| `lua_toclose` | `src/lua.zig:3164` | ✅ real impl — records to-be-closed slot |
| `lua_closeslot` | `src/lua.zig:3172` | ✅ real impl — runs `__close` metamethod on slot |
| `createargtable` | `src/lua.zig:3258` | ✅ real impl — populates `arg` table from CLI args |
| `luaL_newtable` | `src/lauxlib.zig:17` | ✅ real impl — calls `lua_createtable(L, 0, 0)` |
| `luaL_where` | `src/lauxlib.zig:263` | ✅ real impl — pushes source location string |
| `luaL_len` | `src/lauxlib.zig:59` | ✅ real impl — invokes `lua_len` with `__len` metamethod |

### H.2 — oslib stubs ✅ DONE (revs 65, 69)

| Function | Status |
|----------|--------|
| `os.date` | ✅ real impl — `*t` returns full table (9 fields), formats via `strftime` |
| `os.execute` | ✅ real impl — subprocess via `std.process.spawn`, 3-value return |
| `os.exit` | ✅ real impl — conditional `lua_close` per second argument (BUG-043 fixed) |
| `os.setlocale` | ✅ real impl — delegates to `std.c.setlocale` |

### H.3 — iolib stubs ✅ DONE (revs 66, 67)

| Function | Status |
|----------|--------|
| `io.flush` / `file:flush` | ✅ real flush (rev 66) |
| `file:setvbuf` | ✅ real buffering (rev 66) |
| `file:read("*n")` | ✅ ported PUC-Rio `read_number`; `LStream.unget` pushback (rev 67) |

### H.4 — Reference system (MEDIUM priority) — ✅ DONE (2026-07-14)

The Lua C API reference system (`luaL_ref`/`luaL_unref`) is implemented in `src/lauxlib.zig`:

- `luaL_ref(L, t)` — creates a reference in table `t` using a free-list chain (t[1] = head, freed slots link via t[slot])
- `luaL_unref(L, t, ref)` — releases a reference back to the free list; no-op for negative refs
- `LUA_NOREF` (= -2) and `LUA_REFNIL` (= -1) constants exported
- 6 tests in `tests/test_basic.zig` cover the ref sequence, nil ref, free-list reuse, rawgeti retrieval, negative-ref no-op, and Lua-level interaction

Port from `lua/lauxlib.c`. Needed by any C extension that persists Lua values.

### H.5 — Missing C API functions (MEDIUM priority)

**Core API (`lua.h`):** — ✅ DONE except `lua_pushexternalstring` (2026-07-14)

| Function | Why needed | Status |
|----------|------------|--------|
| `lua_atpanic` | C API consumers need a panic handler for unprotected errors | ✅ real impl — `global_State.panic` field added; returns previous handler |
| `lua_version` | Version number query (returns `lua_Number`) | ✅ real impl — returns `LUA_VERSION_NUM` (505.0) |
| `lua_pushexternalstring` | Lua 5.5 new feature — push string backed by external allocator | ❌ deferred — requires new `lua_TString` variant + external-allocator lifetime management |
| `lua_numbertocstring` | Convert number to C string buffer (`LUA_N2SBUFFSZ`-sized) | ✅ real impl — formats via `std.fmt.bufPrint` into caller slice |

**Auxlib (`lauxlib.h`):** — ✅ DONE (2026-07-14)

| Function | Why needed | Status |
|----------|------------|--------|
| `luaL_checkversion_` / `luaL_checkversion` | Version/ABI check called by every library `open` function | ✅ real impl — errors via `luaL_error` on mismatch |
| `luaL_callmeta` | Calls a metamethod by name | ✅ real impl — returns 1 if called, 0 if absent |
| `luaL_alloc` | Default allocator compatible with `lua_Alloc` typedef | ✅ real impl — C-ABI wrapper over `std.c.realloc`/`std.c.free` |
| `luaL_loadfilex` | Load file as Lua chunk (with mode) | ✅ real impl — reads file via `std.Io`, `@`-prefixed chunk name |
| `luaL_loadbufferx` | Load buffer as Lua chunk (with mode) | ✅ real impl — one-shot reader over the buffer slice |
| `luaL_loadstring` | Load string as Lua chunk | ✅ real impl — delegates to `luaL_loadbufferx` with `"t"` mode |
| `luaL_makeseed` | Generate random seed for hashing | ✅ real impl — mixes `L` and local-var addresses |
| `luaL_getsubtable` | Get or create subtable in registry | ✅ real impl — returns 1 if found, 0 if created |
| `luaL_requiref` | Require library with C open function | ✅ real impl — registers in `package.loaded`, optional global |
| `luaL_dofile` | Load and run file (macro in C) | ✅ real impl — `luaL_loadfilex` + `lua_pcallk` |

**Buffer auxlib functions:** — ✅ DONE (2026-07-14)

| Function | Why needed | Status |
|----------|------------|--------|
| `luaL_addstring` | Add null-terminated string to buffer | ✅ real impl — delegates to `luaL_addlstring` |
| `luaL_buffinitsize` | Init buffer with preallocated size | ✅ real impl — inits + reserves `sz` bytes |
| `luaL_prepbuffer` | Shortcut for `luaL_prepbuffsize(B, LUAL_BUFFERSIZE)` | ✅ real impl — see `luaL_prepbuffsize` |
| `luaL_bufflen` | Return current buffer length | ✅ real impl — `b.buf.items.len` |
| `luaL_buffaddr` | Return current buffer address | ✅ real impl — `b.buf.items` slice |
| `luaL_buffsub` | Subtract from buffer length | ✅ real impl — trims `b.buf.items.len` |

Note: `luaL_buffinit`, `luaL_addlstring`, `luaL_addchar`, `luaL_addsize`, `luaL_prepbuffsize`,
`luaL_addvalue`, `luaL_pushresult`, `luaL_pushresultsize` were already implemented in `lauxlib.zig`.

### H.6 — CLI/REPL improvements (MEDIUM priority) — NOT STARTED

The current CLI supports `luazig [script]` and a bare REPL. Missing:

- `-e <chunk>` — execute inline Lua chunk
- `-l <name>` — require library before running
- `-i` — interactive mode after running script
- `-v` — print version banner
- Multi-line input in REPL (line-continuation detection for unfinished statements)
- Readline/history/line-editing
- REPL formatting for complex return values (expand tables via `pairs()`)
- `arg` table creation from CLI args (already implemented via `createargtable`)
- `--` argument separator handling

### H.7 — Convenience macros (LOW priority) — NOT STARTED

The C `lua.h` defines macros that are convenient but not strictly necessary (callers can inline them):

| Macro | Expansion |
|-------|-----------|
| `lua_insert(L, idx)` | `lua_rotate(L, idx, 1)` |
| `lua_remove(L, idx)` | `lua_rotate(L, idx, -1); lua_pop(L, 1)` |
| `lua_newtable(L)` | `lua_createtable(L, 0, 0)` |
| `lua_register(L, n, f)` | `lua_pushcfunction(L, f); lua_setglobal(L, n)` |
| `lua_pushglobaltable(L)` | `lua_rawgeti(L, LUA_REGISTRYINDEX, LUA_RIDX_GLOBALS)` |
| `lua_pushliteral(L, s)` | string literal push |
| `lua_isnoneornil(L, n)` | composite type check |
| `lua_isfunction(L, n)` | type predicate |
| `lua_isthread(L, n)` | type predicate |
| `lua_islightuserdata(L, n)` | type predicate |

### H.8 — Deprecated compatibility aliases (LOW priority) — NOT STARTED

The Lua 5.5.1 `lua.h` retains these for backward compatibility:

| Macro | Modern equivalent |
|-------|-------------------|
| `lua_newuserdata(L, s)` | `lua_newuserdatauv(L, s, 1)` |
| `lua_getuservalue(L, idx)` | `lua_getiuservalue(L, idx, 1)` |
| `lua_setuservalue(L, idx)` | `lua_setiuservalue(L, idx, 1)` |
| `lua_resetthread(L)` | `lua_closethread(L, null)` |

### H.9 — Missing constants and exports (LOW priority)

| Constant | Description | Status |
|----------|-------------|--------|
| `LUA_GNAME` | `"_G"` — global environment name | ❌ missing |
| `LUA_ERRFILE` | Error code for file-level errors | ❌ missing |
| `LUA_LOADED_TABLE` | `"_LOADED"` — registry key for loaded modules | ❌ missing |
| `LUA_PRELOAD_TABLE` | `"_PRELOAD"` — registry key for preload cache | ❌ missing |
| `LUA_NOREF` | Sentinel for `luaL_ref` (requires H.4) | ❌ missing |
| `LUA_REFNIL` | Special ref for `nil` (requires H.4) | ❌ missing |
| `LUAL_NUMSIZES` | Size of `luaL_Reg` struct | ❌ missing |
| `LUA_COPYRIGHT` | Copyright banner string | ✅ present |
| `LUA_AUTHORS` | Authors string | ✅ present |
| `lua_ident` | Identification string array | ❌ missing |

### H.10 — GC completeness (LOW priority) — NOT STARTED

- `lua_gc` option `LUA_GCPARAM` (9) — not handled
- GC parameter get/set (`LUA_GCPMINORMUL`, `LUA_GCPSTEPMUL`, etc.)

### Verification

Each H.x sub-phase must compile, pass all existing tests, and add focused tests for the new functionality. After Phase H is complete, `luazig` should pass all Lua 5.5.1 `lua/testes/` test files without modification (modulo `os.execute` platform dependency and `os.date` localization).

**§0.1 gate applies to all Phase H work.**

