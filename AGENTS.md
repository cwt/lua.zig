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
  `lstate.zig`, and `src/lib/*` for the standard libraries.
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
- **24 passing tests** in `tests/test_basic.zig`: nil, boolean, number, integer,
   string, table type checks, stack push/pop round-trip, string interning,
   table setfield/getfield, seti/geti + length, empty/remove length, hash-part
   string keys, `next` traversal, stack-key gettable/settable, bytecode loader,
   VM execution, and **8 metamethod tests** (`__index` function, `__index` table
   chain, `__newindex` function, `__add` via C API, `__add` via VM execution, `__eq` via C API, `__lt`/`__le` via C API).
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

- **Phase E partially complete — Metamethod dispatch for __index/__newindex, Arithmetic, and Comparison Metamethods.**
   `luaV_gettable` and `luaV_settable` in `src/ltm.zig` follow `__index`/`__newindex`
   chains (up to MAXTAGLOOP=2000). All table-access opcodes in `src/lvm.zig` and all
   C API table functions (`lua_gettable`, `lua_getfield`, `lua_geti`, `lua_settable`,
   `lua_setfield`, `lua_seti`) now dispatch through these. Raw variants (`lua_rawget*`,
   `lua_rawset*`) remain raw. `idxPtr` now frame-relative for positive indices.
   `lua_pushcfunction`, `lua_upvalueindex`, `lua_getupvalue`, `lua_setupvalue` added.
   Arithmetic and comparison metamethods (`__add`, `__eq`, `__lt`, `__le`, etc.) fully implemented in C API and VM execution with fallback.
   C closures now GC-registered (no memory leaks). **8 metamethod tests pass.**

### What is NOT done (blocking next phase)
1. **No source text compilation.** Lexer (`llex.c`), parser (`lparser.c`), and code generator (`lcode.c`) are not implemented (we rely on precompiled bytecode). `luaL_dostring` is still a stub.
2. **No coroutines, no debug API.** Memory allocations are tracked in a flat sweep list `allgc` for leak-free teardowns, but there is no real garbage collector sweep phase yet.
3. **`src/lib/*.zig` library bodies are stubs.**
4. **`src/lstate.zig` is stale/dead code** — its `global_State`/`CallInfo`/
   `GCUnion` duplicate `lua.zig`'s types and it is NOT in the build graph. It
   must be reconciled (or deleted) when GC lands.

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

### Phase E — Error handling, GC, metatables (IN PROGRESS)
11. ✅ `__index`/`__newindex` metamethod dispatch via `luaV_gettable`/`luaV_settable` in `src/ltm.zig`. All table opcodes and C API wired. 3 tests pass.
12. ✅ Arithmetic metamethods (`__add`, `__sub`, etc.) fully implemented in `lua_arith` and VM execution with fallback.
13. ✅ Error propagation (`lua_error`, `lua_pcall`/`lua_pcallk` with custom error handler `errfunc`, longjmp-free Zig `error`/`try` continuations).
14. Expand garbage collector (reconcile stale state, build mark/sweep on top of VMGCObject).

### Phase F — Standard libraries
15. Implement library *bodies* in `src/lib/*`. Go module by module
    (`baselib`, `mathlib`, `stringlib`, `tablelib`, `utf8lib`, `oslib`,
    `iolib`, `corolib`, `debug`, `loadlib`, `bit32`) and back each with tests.
16. Wire `iolib`/`oslib` to `std.Io`/`init.io` instead of raw C file APIs.

---

## 6. File-by-file guidance

| File | Status | Next action |
|------|--------|-------------|
| `build.zig` | ✅ exe+lib build OK; test step works | Expand when adding deps or test targets. |
| `src/luazig.zig` | ✅ entry point, juicy-main | Thread `io` down to `iolib`/`oslib` when those are implemented. |
| `src/lua.zig` | ✅ type model, real stack, real `global_State`, table API, binary `lua_load`, VMGCObject sweep | Phase E — error handling, metatable support. |
| `src/lundump.zig` | ✅ `loadBinaryChunk` bytecode loader, alignment, varint, string intern | Keep as-is; test coverage is complete. |
| `src/llimits.zig` | ✅ constants only, no types | Keep as-is. |
| `src/luaconf.zig` | ✅ version/layout config | Fix `LUA_VDIR` if reference changes. |
| `src/lstate.zig` | full `global_State`/`CallInfo`/`GCUnion` | Stale/dead — reconcile with `lua.zig` (or delete) when GC lands. |
| `src/ltm.zig` | ✅ `luaV_gettable`/`luaV_settable`, `luaT_trybinTM`, comparison helpers | Complete arithmetic metamethods; add `__len`/`__concat`/`__call` tests. |
| `src/ltable.zig` | ✅ `lua_Table` array+hash, `get`/`set`/`getInt`/`setInt`/`next`/`getn`/`deinit` | `__index`/`__newindex` dispatch now done in `ltm.zig`; keep as raw. |
| `src/lstring.zig` | ✅ `luaS_new`/`luaS_hash`/`luaS_eqstr`, interning in `global_State.strt` | Add short/long string split with GC. |
| `src/lvm.zig` | ✅ run execution loop, all table opcodes via metamethods | Phase E — arithmetic metamethods via `luaT_trybinTM`. |
| `src/lauxlib.zig` | aux helpers, §0.1-clean stubs | Implement real `luaL_check*`/`luaL_error`/`luaL_ref` once core works. |
| `src/lualib.zig` | inline stubs for all libraries | Phase F — move to `src/lib/*.zig` bodies. |
| `src/lib/*.zig` | library bodies present but broken | Phase F — rewrite per module with tests. |
| `tests/test_basic.zig` | ✅ 24 passing tests | Expand with more metamethod tests (arithmetic, __len, error handling). |
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

## 8. What to work on next

Phase D (working VM) is **done**. The immediate next task is
**Phase E — Error handling, GC, metatables**: implement metatables, metamethod dispatching, error propagation, and full garbage collection.
This includes implementing metamethod lookups for comparisons, arithmetic operations, and raw table accesses (dispatching to `__index`/`__newindex`/etc.), handling protected/unprotected calls and longjmp-free error continuations, and expanding the heap-allocation sweeper into a real GC.

After Phase E, do **Phase F — Standard libraries** to compile and run standard Lua files.
