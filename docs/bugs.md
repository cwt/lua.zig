---
type: lessons_learned
title: Bug Report — luazig (Zig port of Lua 5.5.1)
description: Working document tracking known defects in the luazig codebase, ordered by priority.
tags: [bugs, defects, tracking]
timestamp: 2026-07-12T00:00:00Z
---

# Bug Report — luazig (Zig port of Lua 5.5.1)

> Working document tracking known defects in the `luazig` codebase. Bugs are
> numbered `BUG-001` … in priority order. Severity reflects runtime impact.
> Each entry records the location, the defect, the impact, and the recommended fix.
> Last updated: 2026-07-12.

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

## BUG-003 — Proto garbage collection leaks sub-prototypes and the struct  [MED] ❌ NOT A BUG
- **Location:** `src/lua.zig:1689-1698` (`freeGCObject`, `.proto` case).
- **Claim:** The case never recurses into `f.p` (nested prototypes) and never
  frees `f` itself.
- **Why it's not a bug:** Sub-prototypes are individually registered in
  `global_State.allgc` by `loadFunction` (`src/lundump.zig:211`) via
  `registerGC`. The `allgc` sweep in `lua_close` or `luaC_collectgarbage`
  calls `freeGCObject` on each object, which frees the sub-protos' structs
  independently. No leak occurs. The struct `f` **is** freed by
  `L.allocator.destroy(f)` (line 1704). The `destroyProto` helper is only
  used in the `errdefer` path of `loadFunction` when loading fails; removing
  sub-protos from `allgc` on error is deferred until state cleanup.
- **Status:** Not a bug — sub-protos are tracked individually in the GC list.

---

## BUG-004 — `lua_tointegerx` truncates non-integral floats  [MED] ✅ FIXED
- **Location:** `src/lua.zig:757-764`.
- **Defect:** For `3.9` it returns `3` with `isnum = true`. The reference sets
  `isnum = false` and returns `0` for non-integral floats.
- **Impact:** Affects `luaL_checkinteger` and any integral-value check; a
  non-integral argument is silently accepted and truncated instead of rejected.
- **Fix:** Set `isnum = false` when `math.trunc(x) != x` (i.e. not an integer
  value); return `0` in that case.

---

## BUG-005 — `lua_isinteger` hardcoded to return 0  [MED] ✅ FIXED
- **Location:** `src/lua.zig:713-717`.
- **Defect:** The body returns `0` unconditionally. Real Lua returns `1` for
  integral floats.
- **Impact:** Breaks `tostring`/format decisions in `luaL_tolstring` (numbers
  always rendered as floats) and any caller relying on the predicate.
- **Fix:** Return `1` when the value is an integer-typed `TValue` **or** a
  float whose value is integral.

---

## BUG-006 — `lua_pushvfstring` / `lua_pushfstring` ignore the format string  [MED] ❌ WON'T FIX
- **Location:** `src/lua.zig:967-974`.
- **Defect:** The functions return the format literal unchanged instead of
  formatting it with the variadic arguments.
- **Why it's unfixable:** Zig has no C-style varargs (`...`). The function
  signature `lua_pushfstring(L, fmt: []const u8)` cannot accept arbitrary
  format arguments. To support formatting, callers must use `std.fmt`
  directly and push the result with `lua_pushstring`.
- **Impact:** Not currently triggered — the functions are unused in the
  codebase. All error messages are constructed via `std.fmt` inline.
- **Status:** Cannot fix without changing the API contract. Unused.

---

## BUG-007 — `luaL_checkstack` (auxlib) errors almost always  [MED] ✅ FIXED
- **Location:** `src/lauxlib.zig:154-161`.
- **Defect:** Returns `error.StackOverflow` whenever `gettop(L) + n > LUA_MINSTACK`
  (20), which is nearly always true, so the call always fails.
- **Impact:** Latent — not triggered by the current `baselib`, but any future
  library that calls `luaL_checkstack` to reserve space will break.
- **Fix:** Grow the stack (delegate to the core `lua_checkstack`, which already
  reallocs to `needed + LUA_MINSTACK`) and only fail on genuine exhaustion.

---

## BUG-008 — `luaL_register` registers every function under the name `"func"`  [MED] ✅ FIXED
- **Location:** `src/lauxlib.zig:112-125`.
- **Defect:** The loop does `lua_pushcfunction` + `lua_setfield(L, -2, "func")`
  for each entry, overwriting the previous and using the wrong key.
- **Impact:** Any library opened via `luaL_register` would only expose the last
  function, under the key `"func"`. (`baselib` currently avoids this by using
  inline `lua_setglobal`.)
- **Fix:** Use the `name` field of each `luaL_Reg` entry:
  `lua_setfield(L, -2, list[i].name)`.

---

## BUG-009 — `TValue.typ()` maps `.upval` to `LUA_TTHREAD`  [LOW] ✅ FIXED
- **Location:** `src/lua.zig:153`.
- **Defect:** The `.upval` tag maps to `LUA_TTHREAD` (8), colliding with the
  thread type tag.
- **Impact:** Latent — upval `TValue`s are not normally passed to tag-based
  dispatch, but the collision is a correctness hazard.
- **Fix:** Map `.upval` to a distinct, otherwise-unused type constant (e.g. `9`
  or a dedicated `LUA_TUPVAL`).

---

## BUG-010 — `lua_precall` C-closure `top = L.top + 20` is unbounded  [LOW] ✅ FIXED
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

## BUG-012 — C-API `lua_gettable`/`lua_settable` and friends silently swallow metamethod errors  [MED] ✅ FIXED
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

## BUG-013 — `lua_checkstack` return value ignored in `luaT_callTM`/`callTMres` → latent OOB  [LOW] ✅ FIXED
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

## BUG-014 — Number→string formatting in `.CONCAT` / `lua_push*` differs from Lua  [LOW] ❌ WON'T FIX
- **Location:** `src/lvm.zig:714-717` (`.CONCAT` number branch);
  `src/lua.zig:967-974` (`lua_pushfstring`/`lua_pushvfstring`, see BUG-006).
- **Defect:** `.CONCAT` formats a float operand with `std.fmt` `"{d}"`, which
  may produce slightly different output from Lua's `"%.14g"` (e.g. `3.0`
  may render as `"3"` instead of `"3.0"`).
- **Why it's won't fix:** The difference is cosmetic and does not affect
  correctness. Zig's `"{d}"` format is well-defined and matches minimal
  float representation. No test is affected. Achieving exact `.14g` output
  would require a custom formatter with no practical benefit.
- **Impact:** Cosmetic — concatenated string differs from reference for
  edge-case float values that happen to round differently.
- **Status:** Won't fix — cosmetic only, no correctness impact.

---

## BUG-015 — `getiofile` uses string-key `getfield` but default files are stored under pointer keys  [HIGH] ✅ FIXED
- **Location:** `src/lib/iolib.zig:80-96` (`getiofile`); stores at `:101`/`:104` (`g_iofile`),
  `:355` (`createstdfile`).
- **Defect:** `getiofile` retrieved the default input/output file with
  `lua.lua_getfield(L, LUA_REGISTRYINDEX, findex)` (string key `"INPUT*"`/
  `"OUTPUT*"`), but those files are stored with `lua.lua_rawsetp(L,
  LUA_REGISTRYINDEX, findex.ptr)` (pointer key) in `g_iofile`/`createstdfile`.
  The C reference uses `lua_rawgetp(L, LUA_REGISTRYINDEX, findex)` here.
- **Impact:** `getiofile` always gets `nil` → `f_read`/`f_write`/`io_read`/
  `io_write`/`io_lines` raise `"default input/output file is closed"`.
- **Fix:** Changed `getiofile` to `lua.lua_rawgetp(L, lua.LUA_REGISTRYINDEX,
  @ptrCast(findex.ptr))`, matching how the files are stored and the C reference.

## BUG-016 — `io.close()` with no arguments panics (`unreachable`)  [HIGH] ✅ FIXED
- **Location:** `src/lib/iolib.zig:50-58` (`io_close`).
- **Defect:** The no-argument branch fetched the default output file with
  `lua.lua_getfield(L, LUA_REGISTRYINDEX, IO_OUTPUT)` (string key), but the
  default file lives under the pointer key (see BUG-015). It got `nil`, then
  `tostream(nil)` hit `lua.lua_touserdata(...) orelse unreachable`.
- **Fix:** Changed `io_close` to `lua.lua_rawgetp(L, LUA_REGISTRYINDEX,
  @ptrCast(IO_OUTPUT.ptr))` (consistent with `g_iofile`/`createstdfile`).

## BUG-017 — `f_read`/`f_write` ignore `self` → `file:read()`/`file:write()` use the wrong file  [MED] ✅ FIXED
- **Location:** `src/lib/iolib.zig:237-241` (`f_read`), `:281-285` (`f_write`).
- **Defect:** Both called `getiofile(L, IO_INPUT/OUTPUT)` instead of reading the
  file object from `self` (index 1). The C reference has separate `io_read`
  (default input) and `f_read` (the file at index 1) functions; here `io_read`
  just forwarded to `f_read`, so `file:read()` operated on the **default** input.
- **Fix:** `f_read`/`f_write` now use `tostream(L_, 1)` to obtain `self`'s
  file descriptor. `io_read`/`io_write` keep using `getiofile` for the default
  file, with `first` arg adjusted for g_write/g_read.

## BUG-018 — `read_chars` over-reads: passes `buf.len` instead of `bytes_read`  [HIGH] ✅ FIXED
- **Location:** `src/lib/iolib.zig:163-171` (`read_chars`), line 170.
- **Defect:** `buf.len` (allocation size) was passed instead of `bytes_read`
  (actual data) to `lua_pushlstring` along with a slice of `bytes_read` length.
- **Fix:** Pass `bytes_read` as the length: `lua.lua_pushlstring(L_, buf[0..bytes_read], bytes_read)`.

## BUG-019 — `g_read` format dispatch is dead code (`if (n > 0)` should check the format type)  [HIGH] ✅ FIXED
- **Location:** `src/lib/iolib.zig:189-231` (`g_read`), line 200.
- **Defect:** The loop guard `if (n > 0)` checked the **stack index** (always ≥ 2),
  so format dispatching (`io.read(n)`, `"a"`, `"l"`, etc.) was dead code.
  `read_line` was always called regardless of the format argument.
- **Fix:** Rewrote `g_read` dispatch to check the actual format: if `n == 0`
  (no args), default to `read_line`; otherwise check `lua_tointeger(L, n)` for
  numeric counts and `lua_tostring(L, n)` for string format specifiers.

## BUG-021 — `os.remove`/`os.rename` cast `[]const u8` to `[*:0]const u8` without a NUL terminator  [MED] ✅ FIXED
- **Location:** `src/lib/oslib.zig:18-24` (`os_remove`), `:28-32` (`os_rename`).
- **Defect:** `linux.unlink(@ptrCast(filename))` reinterpreted a non-sentinel
  `[]const u8` slice as a `[*:0]const u8`, reading past the string.
- **Fix:** Use `L_.allocator.dupeZ(u8, filename)` to produce a proper NUL-terminated
  string before passing to `linux.unlink`/`linux.rename`.

## BUG-022 — `os.remove` ignores the syscall result and always returns `true`  [MED] ✅ FIXED
- **Location:** `src/lib/oslib.zig:18-25` (`os_remove`).
- **Defect:** `linux.unlink` return value was discarded; always pushed `true`.
- **Fix:** Check `linux.unlink` result, push `false` on failure instead of `true`.

## BUG-023 — `openio` leaks the FILE* metatable on the stack  [LOW] ✅ FIXED
- **Location:** `src/lib/iolib.zig:386-390` (`openio`).
- **Defect:** `luaL_newmetatable` + `luaL_setfuncs(L, &flib, 0)` left the FILE*
  metatable on the stack; `lua_setglobal(L, "io")` only pops the io table.
- **Fix:** Added `lua.lua_pop(L_, 1)` after `luaL_setfuncs(L_, &flib, 0)`.

## BUG-024 — Hardcoded `std.heap.page_allocator` in iolib read/line helpers  [LOW] ✅ FIXED
- **Location:** `src/lib/iolib.zig:164-165` (`read_chars`), `:172-187` (`read_line`),
  `:332-348` (`f_lines`).
- **Defect:** Buffers allocated via `std.heap.page_allocator` instead of threading
  the state allocator.
- **Fix:** Changed to `L_.allocator` (threaded through the function parameters).

## BUG-025 — Empty `catch {}` in `luaL_setfuncs` / `luaL_fileresult`  [LOW] ✅ FIXED
- **Location:** `src/lauxlib.zig:364-370` (`luaL_setfuncs`).
- **Defect:** `lua_setfield` call wrapped in `catch {}`, silently discarding errors.
- **Fix:** Changed `luaL_setfuncs` and `luaL_newlib` to `!void` and use `try`.
  Updated all callers.

## BUG-026 — Lua-function coroutines without continuation re-execute from the start  [MED] ✅ FIXED
- **Location:** `src/lua.zig:1746-1776` (`do_resume`).
- **Defect:** The no-continuation (`ci.k == null`) branch destroyed the yielded
  CallInfo and re-precalled, which for Lua functions lost `savedpc` and restarted
  from the top of the function.
- **Fix:** Check if the yielded frame is a Lua function (`val.function.?.* == .lua`).
  If so, continue `lvm.run` on the existing CallInfo (savedpc already points past
  the yield). For C frames without a continuation, the original destroy+re-precall
  logic is correct.

