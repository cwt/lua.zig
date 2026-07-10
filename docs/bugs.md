# Bug Report — luazig (Zig port of Lua 5.5.1)

> Working document tracking known defects in the `luazig` codebase. Bugs are
> numbered `BUG-001` … in priority order. Severity reflects runtime impact.
> Each entry records the location, the defect, the impact, and the recommended fix.
> Last updated: 2026-07-11.

Legend:
- **[HIGH]** crashes, wrong control flow, or incorrect results on ordinary programs.
- **[MED]** incorrect behavior in defined edge cases or latent breakage in untested paths.
- **[LOW]** latent / not currently triggered by the test suite.

---

## BUG-001 — Bitwise shifts panic on negative / large second operand  [HIGH] ✅ FIXED
- **Location:** `src/lua.zig:843-849` (`luaV_shift` helper); used in `lua_arith`
  and `src/lvm.zig` `.SHL`/`.SHR`.
- **Defect:** The shift amount was `@intCast` of a negative or large `i64` into
  `u6`, which panics at runtime or produces undefined behavior.
- **Impact:** Any program using `<<`/`>>` with a non-small non-negative operand
  would crash.
- **Fix:** Added `luaV_shift` helper that uses `@bitCast` to treat the operand as
  `u64` for the shift operation, masking the shift amount to 6 bits. Negative
  shift amounts shift in the opposite direction (matching Lua `lvm.c` reference).
  Applied in both `lua_arith` and the VM `.SHL`/`.SHR` opcodes. Added unit test
  `"bitwise shift operations with negative and large shift"`.

---

## BUG-002 — `lua_callk` / `lua_call` swallow runtime errors  [HIGH] ✅ FIXED
- **Location:** `src/lua.zig:1415-1427` (`lua_callk`/`lua_call`).
- **Defect:** `precall` / `lvm.run` errors were swallowed with `catch { print(); return; }`
  instead of propagating, leaving the stack in an inconsistent state.
- **Impact:** Any library calling a function that can error would be left corrupted.
- **Fix:** Changed `lua_callk` and `lua_call` return type from `void` to `!void`.
  Errors now propagate via `try` instead of being caught and silently discarded.
  Added `try` to all call sites in tests and base library.

---

## BUG-003 — Proto garbage collection leaks sub-prototypes and the struct  [MED]
- **Location:** `src/lua.zig:1689-1698` (`freeGCObject`, `.proto` case).
- **Defect:** The case frees only the top-level slices (`code`, `k`, `p`,
  `upvalues`, `lineinfo`, `locvars`, `upvals`, `source`) but **never recurses
  into `f.p`** (nested prototypes) and **never frees the `lua_Proto` struct `f`
  itself**, unlike the dedicated `destroyProto`.
- **Impact:** Every `lua_close` or GC sweep of a loaded chunk leaks all nested
  `lua_Proto` objects. No double-free risk (only one of `destroyProto`/
  `freeGCObject` runs per object), but the leak grows with chunk complexity.
- **Fix:** In the `.proto` case of `freeGCObject`, free `f` and recursively
  traverse `f.p` (or route the generic path through `destroyProto`). Ensure
  `f.*` is freed last.

---

## BUG-004 — `lua_tointegerx` truncates non-integral floats  [MED]
- **Location:** `src/lua.zig:757-764`.
- **Defect:** For `3.9` it returns `3` with `isnum = true`. The reference sets
  `isnum = false` and returns `0` for non-integral floats.
- **Impact:** Affects `luaL_checkinteger` and any integral-value check; a
  non-integral argument is silently accepted and truncated instead of rejected.
- **Fix:** Set `isnum = false` when `math.trunc(x) != x` (i.e. not an integer
  value); return `0` in that case.

---

## BUG-005 — `lua_isinteger` hardcoded to return 0  [MED]
- **Location:** `src/lua.zig:713-717`.
- **Defect:** The body returns `0` unconditionally. Real Lua returns `1` for
  integral floats.
- **Impact:** Breaks `tostring`/format decisions in `luaL_tolstring` (numbers
  always rendered as floats) and any caller relying on the predicate.
- **Fix:** Return `1` when the value is an integer-typed `TValue` **or** a
  float whose value is integral.

---

## BUG-006 — `lua_pushvfstring` / `lua_pushfstring` ignore the format string  [MED]
- **Location:** `src/lua.zig:967-974`.
- **Defect:** The functions return the format literal unchanged instead of
  formatting it with the variadic arguments.
- **Impact:** All error/diagnostic messages built through these helpers are
  wrong, hampering debugging and user-facing output.
- **Fix:** Use `std.fmt` (`allocPrint` with the threaded allocator) to format
  into a heap string, push it, and free on GC. Thread the allocator already
  available via `L.g()`.

---

## BUG-007 — `luaL_checkstack` (auxlib) errors almost always  [MED]
- **Location:** `src/lauxlib.zig:154-161`.
- **Defect:** Returns `error.StackOverflow` whenever `gettop(L) + n > LUA_MINSTACK`
  (20), which is nearly always true, so the call always fails.
- **Impact:** Latent — not triggered by the current `baselib`, but any future
  library that calls `luaL_checkstack` to reserve space will break.
- **Fix:** Grow the stack (delegate to the core `lua_checkstack`, which already
  reallocs to `needed + LUA_MINSTACK`) and only fail on genuine exhaustion.

---

## BUG-008 — `luaL_register` registers every function under the name `"func"`  [MED]
- **Location:** `src/lauxlib.zig:112-125`.
- **Defect:** The loop does `lua_pushcfunction` + `lua_setfield(L, -2, "func")`
  for each entry, overwriting the previous and using the wrong key.
- **Impact:** Any library opened via `luaL_register` would only expose the last
  function, under the key `"func"`. (`baselib` currently avoids this by using
  inline `lua_setglobal`.)
- **Fix:** Use the `name` field of each `luaL_Reg` entry:
  `lua_setfield(L, -2, list[i].name)`.

---

## BUG-009 — `TValue.typ()` maps `.upval` to `LUA_TTHREAD`  [LOW]
- **Location:** `src/lua.zig:153`.
- **Defect:** The `.upval` tag maps to `LUA_TTHREAD` (8), colliding with the
  thread type tag.
- **Impact:** Latent — upval `TValue`s are not normally passed to tag-based
  dispatch, but the collision is a correctness hazard.
- **Fix:** Map `.upval` to a distinct, otherwise-unused type constant (e.g. `9`
  or a dedicated `LUA_TUPVAL`).

---

## BUG-010 — `lua_precall` C-closure `top = L.top + 20` is unbounded  [LOW]
- **Location:** `src/lua.zig:348`.
- **Defect:** For C closures the new `CallInfo.top` is set to `L.top + 20` with
  no guarantee that the C function's pushes stay within the stack, and no stack
  growth is triggered on the C path.
- **Impact:** Latent — a C function pushing more than 20 slots past `top` can
  write out of bounds of `L.stack`.
- **Fix:** Have C functions call `lua_checkstack`; alternatively size `top` to
  the real stack capacity rather than `L.top + 20`.

---

## BUG-011 — Numeric `for` loops are broken (wrong register layout)  [HIGH] ✅ FIXED
- **Location:** `src/lvm.zig:965-989` (`.FORPREP` and `.FORLOOP`).
- **Defect:** `FORPREP` scrambled the three control registers while `FORLOOP` read
  the scrambled layout but never updated the slot the loop body reads as the loop
  variable. The original SCRAMBLE+READ layout was correct (matching the C reference
  float path), but the `savedpc` skip offset was computed without the `+1` that the
  C reference specifies (`pc += GETARG_Bx(i) + 1`).
- **Impact:** Any numeric `for` loop would terminate one iteration early and the
  loop body saw the constant limit. The test suite had no numeric-`for` test.
- **Fix:** Restored the C reference float-path implementation:
  - `FORPREP` scrambles: `R(a)=limit`, `R(a+1)=step`, `R(a+2)=init` (control var).
    Skip condition: `(step > 0 and limit < init) or (step < 0 and init < limit)`.
    Skip offset: `savedpc += Bx + 1` (the `+1` was missing).
  - `FORLOOP` reads: `step=R(a+1)`, `limit=R(a)`, `idx=R(a+2)+step`.
    Loop-back offset: `savedpc -= Bx`.
  - Write the updated `idx` to `R(a+2)` (the control/loop-variable register).
  - Added unit test `"numeric for loop register layout"`.
  - Fix applied at `src/lvm.zig:963-985` (`.FORPREP` and `.FORLOOP`).

---

## BUG-012 — C-API `lua_gettable`/`lua_settable` and friends silently swallow metamethod errors  [MED]
- **Location:** `src/lua.zig:1133-1137` (`lua_gettable`), `:1154` (`lua_getfield`),
  `:1170` (`lua_geti`), `:1302` (`lua_settable`), `:1318` (`lua_setfield`),
  `:1329` (`lua_seti`); `lua_pcallk` error path `:1417-1419`/`BUG-002`.
- **Defect:** Every C-API table accessor/mutator wraps the metamethod-aware call
  in `catch {}`, dropping any error:
  ```zig
  ltm.luaV_gettable(L, obj, key, res) catch {
      L.stack[res] = .{ .nil = {} };
  };
  ```
- **Impact:** Violates §0.1 (error propagation via `!T`). Concretely,
  `t.x = 1` on a table whose `__newindex` raises, or `t.x` on a table whose
  `__index` raises, silently does nothing / returns nil instead of propagating
  the error. State becomes inconsistent with no signal.
- **Fix:** Make these functions `!void`/`!i32` and `try` the metamethod call so
  the error propagates to the caller (or thread it into `lua_pcall` like the
  reference's longjmp path).

---

## BUG-013 — `lua_checkstack` return value ignored in `luaT_callTM`/`callTMres` → latent OOB  [LOW]
- **Location:** `src/ltm.zig:103` (`luaT_callTM`), `:115` (`luaT_callTMres`);
  helper `src/lua.zig:648` (`lua_checkstack`).
- **Defect:** Both helpers do `_ = lua.lua_checkstack(L, 4/3)` and then write
  `L.stack[L.top + 3] = ...` (or `+2`). If `lua_checkstack` fails to grow the
  stack (it returns `0` / `false` on allocation failure), the subsequent writes
  are out of bounds of `L.stack`.
- **Impact:** Latent — under normal allocation it grows successfully, but a
  low-memory condition or an already-full stack corrupts/panics.
- **Fix:** Check the result of `lua_checkstack` and return `error.OutOfMemory`
  (or propagate) when it fails, before touching `L.stack`.

---

## BUG-014 — Number→string formatting in `.CONCAT` / `lua_push*` differs from Lua  [LOW]
- **Location:** `src/lvm.zig:714-717` (`.CONCAT` number branch);
  `src/lua.zig:967-974` (`lua_pushfstring`/`lua_pushvfstring`, see BUG-006).
- **Defect:** `.CONCAT` formats a float operand with `std.fmt` `"{d}"`, which
  renders `3.0` as `"3"` (Lua renders `"3.0"`) and uses different exponent
  formatting than Lua's `"%.14g"`.
- **Impact:** String concatenation of numbers produces strings that differ
  textually from reference Lua (e.g. `"x" .. 3.0` → `"x3"` instead of
  `"x3.0"`). Affects `tostring`/concat semantics for floats.
- **Fix:** Use a Lua-compatible formatter (`%.14g`-equivalent via `std.fmt` with
  explicit precision) for float→string conversion.
