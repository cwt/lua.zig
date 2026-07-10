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
> later" — that path produces the bugs currently in this tree (catalogued in §0.1 and §6). If you
> are about to copy a C pattern, STOP and rewrite it the Zig way.
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
   - *Current violation:* 13 hardcoded `page_allocator` sites
     (`src/lua.zig:1028,1043,1101,1114`, `src/zua.zig:18`, `src/lauxlib.zig`
     throughout). Do not add more.

2. **Propagate errors with `!T` + `try`/`catch`. Never `catch unreachable` on
   allocation, and never use `unreachable` for a real runtime condition.**
   `catch unreachable` panics on OOM; Lua must return `LUA_ERRMEM` via the error
   path. `unreachable` is only for provably-impossible states (e.g. an exhausted
   `switch`).
   - *Current violation:* `catch unreachable` at `src/lua.zig:1028,1043,1101,
     1114`; `unreachable` as error handling at `src/lua.zig:482-483`,
     `src/lauxlib.zig:49`.

3. **Replace Lua's `setjmp`/`longjmp` with Zig error unions — completely.**
   There is no `lua_longjmp` control-flow hack in correct Zig code. Use `!T`
   returns and `try`; let the compiler's error propagation replace the C
   non-local jump. Do not port `luaD_rawrunprotected`/`lua_longjmp` mechanics.

4. **Use `@intFromFloat` / `@floatFromInt` / `@intCast` for numeric
   conversions. Never `@bitCast` between `i64`/`f64`/`usize` to convert a value.**
   `@bitCast` is only for *bit-identical* reinterpretation (same bit width, same
   meaning). Value conversion is a different operation and `@bitCast` produces
   silently wrong numbers.
   - *Current violation:* `src/lib/baselib.zig:306`, `src/lib/mathlib.zig:164,
     203,295,337,362`, `src/lib/oslib.zig:67,92,161`, `src/lib/tablib.zig:91`,
     `src/lib/utf8lib.zig:59,73`.

5. **Use bounded `[]const u8` / `[]u8` slices, not C null-terminated
   `?[*:0]const u8`.** Only the C ABI boundary (if any) uses sentinels, and even
   then prefer slices. Replace `lua_pushstring(L, ?[*:0]const u8)` with
   `lua_pushstring(L, []const u8)`.

6. **No C-style varargs `...` in signatures** — they are not valid Zig and will
   break the build. Use explicit parameters, `anytype`, or a `std.fmt`-style
   approach. Fix the existing stubs `luaL_error` (`src/lauxlib.zig:100`),
   `lua_pushfstring` (`src/lua.zig:742`), `lua_gc` (`src/lua.zig:1197`).

7. **Use unmanaged containers correctly.** Growable state (tables' array/hash
   parts, string tables) uses `std.ArrayList`/`std.array_hash_map.*` initialized
   with `.empty` and an explicit allocator (skill §3.3). Never call `.append` on
   a slice — slices have no `append`.
   - *Current violation:* `t_ptr.harray.append(...)` on `?[]lua_TString` at
     `src/lua.zig:1047,1118`.

8. **Use the `TValue = union(enum)` tagged union** (already in place at
   `src/lua.zig:27`) for values — this is the correct Zig replacement for Lua's
   C NaN-boxing. Do not regress to raw `f64` bit-tagging or `@bitCast` tricks to
   distinguish types.

9. **Single, consistent type model.** One `lua_State`, one `lua_CFunction`, one
   `global_State` (see §4.1). No `*anyopaque` shortcuts for Lua objects. Nullable
   references are Zig optionals (`?*T`), checked with `if (opt) |v|` / `orelse`.

10. **Adopt juicy-main + `std.Io` threading** (skill §3.1–3.2). All user-facing
    and file I/O flows through the `io: std.Io` from `std.process.Init`, not
    `std.debug.print` or raw C file APIs. `iolib`/`oslib` must take `io`.

### 0.2 How to work

- Before writing any function, ask: *"What would a native Zig programmer write
  here?"* — then write that. Diff against `/lua/` only for **semantics** (opcode
  behavior, algorithm), never for **structure**.
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

### 0.4 Bootstrap version control — only after the existing code is correct

**Stubs are fine. Wrong code is not.** It is completely acceptable that most of
the API remains unimplemented/stubbed for now. But the moment the code we
*already have* conforms to §0.1 (the stack, the type model, the tables we have,
the library registrations, the entry point, `build.zig`), the agent MUST
establish the repository and make the **initial commit** — and that commit must
contain **only code that already complies with §0.1**, nothing sloppy.

Procedure (use the `hg-mcp` tools; this is a Mercurial project):

1. **`hg init` inside `zua/`** (the repository root is `/home/cwt/Projects/l/zua`,
   not the parent `l/`). Do not initialize in a parent directory.
2. **Create project scaffolding that belongs in version control:**
   - `build.zig` and `build.zig.zon` (already present — verify they build).
   - `.hgignore` covering build artifacts: `.zig-cache/`, `zig-out/`, and any
     local editor/temp files. **Never commit `.zig-cache/` or `zig-out/`.**
   - `LICENSE` / copyright notice (the C reference carries one; preserve it).
   - This `AGENTS.md`.
3. **Tidy before committing:** delete or quarantine any file/function that
   violates §0.1 and that you are not yet fixing (e.g. the duplicate
   `src/main.zig` `lua_State`, the broken `...` varargs stubs) so the initial
   tree is internally consistent. Stubs that *are* written correctly (proper
   signatures, `!T` returns, allocator-injected, no `catch unreachable`) may
   stay — being unimplemented is not a §0.1 violation.
4. **Make the initial commit** with a clear message stating this is the
   Zig-0.16.0-conformant baseline. Use a bookmark (e.g. `main`) per the hg-mcp
   workflow; the initial changeset is the immutable foundation everything else
   builds on.
5. **Do not pile features onto a non-conformant tree first.** The initial commit
   is the contract that "from here on, every line follows §0.1." New work after
   the initial commit continues under the same §0.3 gate, one bookmark/topic at a
   time.

> Rationale: we would rather have a small, *correct* initial commit (stack +
> types + a few real functions) than a large commit that bakes in C-shaped
> mistakes. Correctness of what exists now is the precondition for the initial
> commit, not completeness.

---

## 1. What this project is

`luazig` is a from-scratch port of the Lua reference implementation (the C tree at
`/lua/`, which is **Lua 5.5.1** per `lua.h`) to **Zig 0.16.0**. The goal is a
working Lua interpreter that follows the reference semantics while adopting the
Zig 0.16.0 idioms described in the `zig-0.16.0-development` skill
(`std.process.Init` juicy main, explicit `std.Io`, unmanaged containers, no
`@cImport`).

The reference C sources live in `/lua/` (the sibling directory) and are the
**authoritative source of truth** for opcodes, data layouts, and semantics.
Always diff against `/lua/` when implementing a module.

---

## 2. Current status — honest assessment

**The project is at the SCAFFOLD / SKELETON stage.** Roughly 5,100 lines are
written across ~22 files, the executable and library *compile*, but **almost
nothing actually works at runtime.** Treat the existing code as a structure
sketch, not a working interpreter.

### What is genuinely done
- **Module layout exists.** Files mirror the C modules: `lua.zig` (core API),
  `lvm.zig` (opcodes + VM stub), `llimits.zig`, `luaconf.zig`, `lauxlib.zig`,
  `lstate.zig`, and `src/lib/*` for the standard libraries.
- **Public C API surface is sketched.** Most `lua_*` / `luaL_*` function
  signatures are declared with correct C signatures (push/get/set/call family).
- **juicy-main entry point** is in place (`src/zua.zig` and `main.zig`) using
  `std.process.Init`, and `build.zig` builds an exe + a library + a (broken)
  test step.
- **Library registration scaffolding** exists: `luaL_openlibs` dispatches to
  `openbaselib`, `openmathlib`, etc.

### What is NOT done (blocking)
1. **No front-end at all.** `luaL_dostring`, `lua_load`, `lua_dump` are empty
   stubs (`src/lua.zig:1166-1170`). There is **no lexer, no parser, no
   compiler, no bytecode loader**. You cannot run a single line of Lua source.
2. **The VM does not function.** `lvm.run` (`src/lvm.zig:183`) is a skeleton:
   instruction decode helpers (`GETARG_*`, `SET_OPCODE`) reference
   `i.ptr[...]` on a `u32` and will **not type-check** when actually called;
   most opcodes are no-ops (`_ = GETARG_A(...)`); there is no constant-pool
   loading, no function calls, no closures, no upvalues, no loops, no `SETLIST`.
3. **The stack is fundamentally broken.** `lua_State.stack` is a `usize`, and
   stack ops do `@ptrCast(@alignCast(&L.stack))` then index it — this writes
   into the *`usize` field itself*, not an allocated array. There is no real
   stack buffer anywhere. Every stack operation in `src/lua.zig` is therefore
   incorrect.
4. **Broken / conflicting type model** (see §4). `lua_State`, `lua_CFunction`,
   and `global_State` are each defined inconsistently across files.
5. **Tables do not work.** `lua_Table` mixes `larray: ?[]?TValue`,
   `harray: ?[]lua_TString`, and raw `i_array`/`h_array` fields inconsistently.
   `lua_settable`/`lua_rawset` attempt `t_ptr.harray.append(...)` on a slice
   (impossible) and grow with `std.heap.page_allocator`. There is no real
   hash part.
6. **No real metatables / metamethods.** `lua_setmetatable`/`lua_getmetatable`
   are stubs; `lua_arith` does not consult `__add` etc.
7. **No garbage collector, no string interning, no registry, no upvalues, no
   error longjmp/setjmp, no coroutines, no debug API.**
8. **The test step is broken.** `build.zig` passes `tests/test_basic.zig` as a
   CLI arg to the test runner (wrong), and `test_basic.zig` calls
   `lua.lua_isnil` / `lua.lua_isboolean` which **do not exist** (only
   `lua_isnumber`/`lua_isstring`/`lua_toboolean` exist). Tests do not run.

> **Critical caveat for agents:** the build currently succeeds *only* because the
> broken execution paths are **unreferenced dead code** that Zig does not
> type-check. As soon as you wire `lvm.run`, the instruction decoders, or the
> real stack ops into a code path, the build will break until they are fixed.
> Do not be lulled into thinking "it compiles" means "it works."

---

## 3. Architecture constraints (Zig 0.16.0)

Follow the `zig-0.16.0-development` skill strictly:
- `main` MUST take `std.process.Init` (already done in `src/zua.zig`).
- All I/O goes through the `io: std.Io` from `init.io` (used for `print`, file
  I/O in `iolib`, `oslib`). Do **not** use `std.debug.print` for user-facing
  output in the final libraries — thread `io` down.
- Unmanaged containers only; initialize with `.empty` (not `.{}`).
- `@cImport` is forbidden. If any C interop is ever needed (it should not be for
  a pure port), use `addTranslateC` in `build.zig`.
- Prefer `@intFromPtr`/`@intFromEnum` bit tricks consistent with the C source,
  but keep types honest (a `u32` instruction is a `u32`, not a pointer).

---

## 4. MUST-FIX FOUNDATIONAL WORK (do this before new features)

These are prerequisites. Until they are done, nothing else can be validated.

### 4.1 Reconcile the type model (single source of truth)
Today there are three conflicting `lua_State` definitions:
- `src/llimits.zig:10` → `lua_State = *anyopaque`
- `src/lua.zig:167` → `pub const lua_State = struct { ... }`
- `src/main.zig:13` → a **separate** `lua_State` struct

And `lua_CFunction` is `fn(*anyopaque) i32` in `llimits.zig:27` but
`fn(llimits.lua_State) i32` (also effectively `*anyopaque`) in `lua.zig:104`,
while the stack is typed with `lua.lua_State` (the struct). `global_State` is a
placeholder in `lua.zig:148` but a full struct in `lstate.zig:55`.

**Action:** Define the **one true** full `lua_State` and `global_State` structs
in a single module (recommended: keep them in `lua.zig`, and make `llimits.zig`
re-export `lua.lua_State` as an alias — never `*anyopaque`). Make every
`lua_CFunction` / `lua_KFunction` use the real struct pointer. Delete the
duplicate `lua_State` in `main.zig` (the entry point should import `lua.zig`).

### 4.2 Give the state a real stack
`lua_State` needs an actual stack buffer:
```zig
stack: []TValue,        // or [*]TValue with an allocator-owned slice
stack_last: usize,
```
Allocate it in `luaL_newstate` with the provided allocator and grow it in
`lua_checkstack`. Replace every `@ptrCast(@alignCast(&L.stack))` pattern with a
direct slice index `L.stack[idx]`. Keep `top` as an index into this slice.

### 4.3 Fix the instruction decode/encode helpers
`Instruction = u32`. The `GETARG_*`/`SETARG_*` family in `lvm.zig:117-172`
currently writes `i.ptr[24]` etc. `u32` has no `ptr` field. Replace with shifts
and masks derived from `/lua/lopcodes.h` (Lua 5.5.1 field widths: opcode 7 bits
at position 0, A 8 bits, B/C 8 bits, etc.). Verify against `lopcodes.c`'s
`luaP_decode`/`luaP_encode` if present, or `lvm.c`.

### 4.4 Reconcile version constants
Comments say "Lua 5.5.1" but `src/lua.zig:210-212` set version 5.1 and
`src/luaconf.zig:39` sets `LUA_VDIR = "5.1"`. Match the reference (`/lua/lua.h`
says 5.5.1). Set `LUA_VERSION_*` and `LUA_VDIR` consistently.

---

## 5. Recommended next-phase roadmap (in order)

Work **top-down from the foundation**, validating each layer with a real test
before moving on. Do not parallelize layers that depend on each other.

### Phase A — Buildable core (deps: §4)
1. Single type model (§4.1), real stack (§4.2), correct instruction helpers (§4.3).
2. Implement the full **stack API** in `lua.zig` for real:
   `lua_absindex`, `lua_gettop/settop`, `lua_pushvalue`, `lua_rotate`,
   `lua_copy`, `lua_checkstack`, `lua_pop`, and all `lua_push*`/`lua_to*`.
   Each must operate on the real `L.stack` slice and round-trip correctly.
3. Fix `lua_equal`/`lua_compare`/`lua_rawequal` on actual values (today they
   compare typed union tags, not Lua equality semantics — e.g. `1.0 == 1`).
4. **Fix the test harness**: remove the bogus `addArgs` in `build.zig` test step,
   add the missing `lua_isnil`/`lua_isboolean` (or rename to `lua_type(...) ==
   LUA_TNIL`), and make `tests/test_basic.zig` actually run and pass.

### Phase B — Tables & values
5. Implement `lua_Table` properly: array part (`?[]?TValue`) + hash part
   (open-addressing or chained nodes, modeled on `/lua/ltable.c`). Provide
   `lua_createtable`, `lua_settable`/`lua_gettable`, `lua_rawset`/`lua_rawget`,
   `lua_seti`/`lua_geti`, `lua_next`, `lua_rawlen` with real hashing.
6. Real `lua_TString` with interning in `global_State.strt` (dedupe equal
   strings) — needed for table keys and `lua_pushstring` correctness.

### Phase C — Front-end (lexer/parser/compiler) or loader
7. **Decision:** either (a) port the lexer+parser+codegen from `/lua/llex.c`,
   `lparser.c`, `lcode.c`, or (b) implement a Lua chunk **loader** (`lundump.c`)
   plus a way to obtain bytecode. Option (a) is required to run source scripts
   via `luaL_dostring`/`lua_load`. This is the largest single piece of work.
8. Produce `lua_Proto` structures that `lua_State`/`lvm` can execute.

### Phase D — A working VM
9. Implement `lvm.run` for real: every opcode from §C output, including
   `MOVE`, `LOADK/LOADI/LOADF`, arithmetic/logic (`ADD/SUB/.../BAND/...`),
   `GETTABLE/SETTABLE/GETI/SETI/GETFIELD/SETFIELD`, `NEWTABLE`, `SELF`,
   `CONCAT`, `LEN`, `JMP`, `EQ/LT/LE` and the `EQI/LTI/...` variants, `TEST/
   TESTSET`, `CALL`/`TAILCALL`/`RETURN`, `CLOSURE`, `VARARG`/`VARARGPREP`,
   `FORPREP`/`FORLOOP`, `TFOR*`, `SETLIST`, `UPVAL*` (with real upvalue
   capture), and `EXTRAARG`.
10. Function calls: dispatch to C closures (`lua_CFunction`) and Lua closures
    (`lua_Proto`), manage `CallInfo` chains, varargs, returns.

### Phase E — Error handling, GC, metatables
11. Error propagation (`lua_error`, `lua_pcall`, longjmp-equivalent via
    Zig `error`/`try` or a setjmp-free continuation design).
12. Metatables + metamethod dispatch in `lua_arith`/`lua_compare`/`lua_get*/set*`
    (mirror `/lua/ltm.c`).
13. Minimal garbage collector (start with mark-and-sweep on the `GCObject`
    union in `lstate.zig`), or at minimum correct ownership/arenas.

### Phase F — Standard libraries (only after E)
14. Implement library *bodies* in `src/lib/*`. They currently register
    functions but the function bodies are stubs. Go module by module
    (`baselib`, `mathlib`, `stringlib`, `tablelib`, `utf8lib`, `oslib`,
    `iolib`, `corolib`, `debug`, `loadlib`, `bit32`) and back each with tests.
15. Wire `iolib`/`oslib` to `std.Io`/`init.io` instead of raw C file APIs.

---

## 6. File-by-file guidance

| File | Status | Next action |
|------|--------|-------------|
| `build.zig` | exe+lib build OK; test step broken | Drop the `run_tests.addArgs(&.{"tests/..."})` line; rely on `addTest` test fns. |
| `src/zua.zig` | entry point OK | Keep `std.process.Init`; thread `io`/`gpa` down correctly. |
| `src/main.zig` | **unused duplicate** `lua_State` | Delete; it shadows `lua.zig`. (Or fold into `zua.zig`.) |
| `src/lua.zig` | API signatures present, bodies stub/broken | Phase A+B. This is the heart; fix stack + tables here. |
| `src/llimits.zig` | defines conflicting `lua_State = *anyopaque` | Make `lua_State` an alias to `lua.lua_State`; keep only types/constants. |
| `src/luaconf.zig` | config OK, version mismatch | Fix `LUA_VDIR`/version to 5.5.1. |
| `src/lstate.zig` | full `global_State`/`CallInfo`/`GCUnion` structs | Use as the canonical state structs; merge with `lua.zig` definitions. |
| `src/lvm.zig` | opcode enum OK; decode broken; `run` skeleton | Phase A (decode) then Phase D (`run`). |
| `src/lauxlib.zig` | aux helpers, many stubs | Implement real `luaL_check*`/`luaL_error`/`luaL_ref` once core works. |
| `src/lib/*.zig` | files present; registration only, bodies stub | Phase F, per module, with tests. |
| `tests/test_basic.zig` | references nonexistent API | Fix to use real API; expand with stack/table/VM tests. |

---

## 7. Verification rules for agents

- After each phase, run `zig build` AND make the test step actually execute.
  Do not claim progress if `zig build test` is still failing.
- Add a focused unit test for every function you implement (stack ops, table
  ops, each opcode). Mirror the reference `lua/testes/` suite where practical.
- Diff your data layouts and opcode semantics against `/lua/` (the C reference)
  rather than inventing representations.
- Keep the single-type-model invariant: one `lua_State`, one `lua_CFunction`,
  one `global_State`. No `*anyopaque` shortcuts for Lua objects.
- Never reintroduce `@ptrCast(@alignCast(&L.stack))` as a fake stack; use a real
  slice.
- Run `zig build test` with `--test-timeout-scale=X` if a test is slow (the
  default is 1s); do not disable tests to make the build green.

---

## 8. Suggested first commit for a new agent

If starting fresh, the highest-value first task is **Phase A.1 + A.2 + A.4**:
unify the type model, give `lua_State` a real stack, fix the test harness, and
make `tests/test_basic.zig` (stack push/pop/type checks) actually pass. That
establishes a foundation every later phase depends on and gives a green
baseline to build on.
