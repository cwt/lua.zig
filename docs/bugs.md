# Bug Report — luazig (Zig port of Lua 5.5.1)

> Working document tracking known defects in the `luazig` codebase. Bugs are
> numbered `BUG-001` … in priority order. Severity reflects runtime impact.
> Each entry records the location, the defect, the impact, and the recommended fix.
> Last updated: 2026-07-10.

Legend:
- **[HIGH]** crashes, wrong control flow, or incorrect results on ordinary programs.
- **[MED]** incorrect behavior in defined edge cases or latent breakage in untested paths.
- **[LOW]** latent / not currently triggered by the test suite.

---

## BUG-001 — Bitwise shifts panic on negative / large second operand  [HIGH]
- **Location:** `src/lua.zig:880-881` (`lua_arith`, `LUA_OPSHL`/`LUA_OPSHR`);
  `src/lvm.zig:612` (`.SHL`), `src/lvm.zig:624` (`.SHR`).
- **Defect:** The shift amount is produced by `@intCast` of a `lua_Number`-derived
  `i64` into an unsigned shift operand:
  ```zig
  @as(i64, @intFromFloat(p1.number)) << @intCast(@as(i64, @intFromFloat(p2.number)))
  // VM: const shift: u6 = @intCast(ic);
  ```
  - `@intCast` of a **negative** `p2` (e.g. `1 << -1`) into an unsigned type
    **panics at runtime**.
  - **Large** positive shifts (`1 << 70`) are undefined behavior.
- **Impact:** Any program using `<<`/`>>` with a non-small non-negative operand
  crashes. This is a common operator; the bug is trivially reachable.
- **Fix:** Add a `luaV_shift`-style helper matching the reference `lvm.c`:
  ```zig
  fn shift(i: i64, s: i64) i64 {
      if (s < 0) return @bitCast(@as(u64, @bitCast(i)) >> @intCast(-s & 0x3F));
      return @bitCast(@as(u64, @bitCast(i)) << @intCast(s & 0x3F));
  }
  ```
  Use it in both `lua_arith` and the `.SHL`/`.SHR` VM opcodes (operand masked to
  6 bits; negative means opposite direction).

---

## BUG-002 — `lua_callk` / `lua_call` swallow runtime errors  [HIGH]
- **Location:** `src/lua.zig:1413-1420`.
- **Defect:** `precall` / `lvm.run` errors are only passed to `std.debug.print`
  and swallowed, but `lua_callk` has a `void` return:
  ```zig
  try precall(...) catch |e| { print_error(...); return; };
  lvm.run(...) catch |e| { print_error(...); return; };
  ```
- **Impact:** In the C reference, `lua_call` performs a non-local jump on error.
  Here execution continues with the C function's stack inconsistent. Any library
  calling a function that can error is left in a corrupted state.
- **Fix:** Propagate the error. Either make `lua_callk` return `!void` (preferred,
  matches the §0.1 single-error-path rule) or store the error in the state and
  let the next API call surface it. Do **not** print-and-continue.

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

## BUG-011 — Numeric `for` loops are broken (wrong register layout)  [HIGH]
- **Location:** `src/lvm.zig:965-989` (`.FORPREP` and `.FORLOOP`).
- **Defect:** `FORPREP` scrambles the three control registers instead of leaving
  them in the canonical layout, and `FORLOOP` reads that same scrambled layout
  without ever writing the control value to the slot the loop body reads:
  ```zig
  // FORPREP else-branch:
  L.stack[ra_idx]     = limit;   // should stay = init
  L.stack[ra_idx + 1] = step;    // should stay = limit
  L.stack[ra_idx + 2] = init;    // should stay = step
  // FORLOOP:
  const step  = L.stack[ra_idx + 1].number;  // reads limit
  const limit = L.stack[ra_idx].number;      // reads limit+init mix
  ```
  In the reference (`lvm.c`), after `FORPREP` `R(a)=init`, `R(a+1)=limit`,
  `R(a+2)=step`, and `FORLOOP` writes the updated control to **both** `R(a)` and
  `R(a+3)` (the slot the loop body uses as the visible loop variable).
- **Impact:** `for i=1,3 do print(i) end` runs the correct number of times but
  prints `3` three times — the loop variable the body sees is the constant
  limit. Any numeric `for` produces wrong values. The test suite has no
  numeric-`for` test, so this passed undetected.
- **Fix:**
  ```zig
  .FORPREP => {
      const ra_idx = ci.base + A;
      const init  = L.stack[ra_idx].number;
      const limit = L.stack[ra_idx + 1].number;
      const step  = L.stack[ra_idx + 2].number;
      if (step == 0) return error.RuntimeError;
      if ((step > 0 and init > limit) or (step < 0 and init < limit)) {
          ci.savedpc += GETARG_Bx(instruction) + 1;
      }
      // registers already hold init/limit/step — do NOT rewrite them
  },
  .FORLOOP => {
      const ra_idx = ci.base + A;
      const step  = L.stack[ra_idx + 2].number;
      const limit = L.stack[ra_idx + 1].number;
      var idx = L.stack[ra_idx].number + step;
      if ((step > 0 and idx <= limit) or (step < 0 and limit <= idx)) {
          L.stack[ra_idx]         = .{ .number = idx };
          L.stack[ra_idx + 3]     = .{ .number = idx };  // visible loop var
          ci.savedpc -= GETARG_Bx(instruction);
      }
  },
  ```

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
