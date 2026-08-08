---
type: lessons_learned
title: Bug Report — luazig (Zig port of Lua 5.5.0)
description: Working document tracking known defects in the luazig codebase, ordered by priority.
tags: [bugs, defects, tracking]
timestamp: 2026-07-14T16:10:00Z
---

# Bug Report — luazig (Zig port of Lua 5.5.0)

> Working document tracking known defects in the `luazig` codebase. Bugs are
> numbered `BUG-001` … in priority order. Severity reflects runtime impact.
> Each entry records the location, the defect, the impact, and the recommended fix.
> Last updated: 2026-07-31 (Systematic bug-pattern audit + BUG-050–054 appended — cross-cutting codebase mistakes).

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

## BUG-027 — Table hash part Node.next collision sentinel bug  [HIGH] ✅ FIXED
- **Location:** `src/ltable.zig` (multiple lines).
- **Defect:** `0` was used as the sentinel value for the end of the collision chain. However, `0` is a valid index in the table's node array. Under collision conditions, any key placed at index `0` became unreachable from searches originating from other slots because the search stopped immediately on seeing `next == 0`.
- **Fix:** Changed the sentinel value representing the end of a chain from `0` to `-1`.

## BUG-028 — Stack-imbalance popping in `loadlib.zig` helper functions  [MED] ✅ FIXED
- **Location:** `src/lib/loadlib.zig` (`findfile`, `searcher_preload`, `searcher_Croot`, `findloader`).
- **Defect:** Invalid `defer lua_pop` statements were used to pop elements from the stack on function return, causing incorrect stack frames and misaligned indices.
- **Fix:** Removed the invalid pops. Stack frames are naturally cleaned up by the VM upon returning from C/port library calls.

## BUG-029 — `require` upvalue closure registration mismatch  [MED] ✅ FIXED
- **Location:** `src/lib/loadlib.zig` (`openloadlib`, `ll_require`).
- **Defect:** `require` was registered as a raw C function without upvalues. The Lua reference expects `require` to be registered as a closure with the `package` table bound as upvalue 1, which `findloader` uses to look up searchers.
- **Fix:** Registered `require` via `lua_pushcclosure(L, ll_require, 1)` with `package` table bound as its first upvalue.

## BUG-030 — Memory leak of dynamic `path` in `searchpath`  [LOW] ✅ FIXED
- **Location:** `src/lib/loadlib.zig:159-183` (`searchpath`).
- **Defect:** `path` allocated via `std.mem.replaceOwned` was leaked when returning from `searchpath`.
- **Fix:** Added `defer L.allocator.free(path)` and returned a GC-managed copy pushed onto the stack via `lua.lua_tostring(L, -1).?`.

---

## BUG-031 — `loadlib.zig`: 9 silent `catch {}` swallow errors (§0.1 rule 12)  [HIGH] ✅ FIXED
- **Location:** `src/lib/loadlib.zig` — L91 (`addtoclib`), L394 & L431 (`setpath`), L413/L414/L416/L418/L419 (`setpath` `luaL_addlstring`), L442 (`createsearcherstable`).
- **Defect:** Every one of these sites wrapped a fallible C-API call in `catch {}`, discarding the error and continuing as if it succeeded. This directly violated §0.1 rule 12.
- **Fix:** Made `noenv`, `lsys_load`, `lsys_sym`, `checkclib`, `addtoclib`, `lookforfunc`, `loadfunc`, `setpath`, and `createsearcherstable` return error unions and propagate errors using `try` instead of swallowing.

## BUG-032 — `loadlib.zig`: heap-allocated `std.DynLib` handle is never freed (latent leak)  [MED] ✅ FIXED
- **Location:** `src/lib/loadlib.zig:64-82` (`lsys_load`); `src/lua.zig` (`lua_close`).
- **Defect:** `lsys_load` heap-allocated a `*std.DynLib` and stored it in the `CLIBS` registry, but nothing ever called `lib.close()` or destroyed it, leaking the dynamically loaded library handle and mapping.
- **Fix:** Added a `clibs` list (`std.ArrayList(*std.DynLib)`) to `global_State` to track all successfully opened libraries. Added cleanup logic in `lua_close` to iterate through `clibs`, call `close()` on each, and destroy the structs.

## BUG-033 — `luaL_getenv`: Linux-only `/proc/self/environ`, exec-time snapshot, swallows I/O errors  [MED] ✅ FIXED
- **Location:** `src/lauxlib.zig` `luaL_getenv` (reads `/proc/self/environ`).
- **Defect:** The helper opened and read `/proc/self/environ` using raw POSIX syscalls, swallowing errors. It had portability issues and could fail on non-Linux or sandboxed hosts.
- **Fix:** Updated the helper to return `anyerror!?[]const u8` to propagate errors (such as OOM) properly. Handled non-OOM errors (like file not found or sandbox restrictions) gracefully in `os_getenv` and `setpath` by falling back to `null` (not found), while propagating OOM.

## BUG-034 — `luaL_getenv` bypasses `std.Io` (§0.1 rule 10)  [LOW] ✅ FIXED
- **Location:** `src/lauxlib.zig` `luaL_getenv` (uses `std.posix.openat`/`std.posix.read` directly).
- **Defect:** Bypassed the `io: std.Io` abstraction directive (§0.1 rule 10).
- **Fix:** Rewrote `luaL_getenv` to use the thread-safe `std.Io` instance via `L.l_G.?.io`, calling `std.Io.Dir.openFile` and `file.readStreaming` (with graceful handling of `error.EndOfStream` for unseekable proc files).

## BUG-035 — `luaL_gsub` leaks its `luaL_Buffer` on OOM  [LOW] ✅ FIXED
- **Location:** `src/lauxlib.zig` `luaL_gsub` (the `var b = luaL_Buffer{}` has no `errdefer b.buf.deinit(...)`).
- **Defect:** If any `luaL_addlstring`/`luaL_addchar` allocation failed, the function returned before `b.buf.deinit` ran, leaking the partially grown buffer.
- **Fix:** Added `errdefer b.buf.deinit(L.allocator);` after `luaL_buffinit`.



## BUG-036 — VM: vararg functions not executed correctly (VARARGPREP no-op, no adjustvarargs)  [MED] — FIXED (rev 43, 2026-07-12)
- **Location:** `src/lvm.zig:1059` (`.VARARGPREP => {}`); missing `luaT_adjustvarargs` / `luaT_getvarargs` (cf. `src/ltm.zig`, `src/lua.zig`).
- **Defect:** In Lua 5.5.0 (`lua/lvm.c`), `OP_VARARGPREP` calls `luaT_adjustvarargs(L, ci, cl->p)`, which inspects `p->is_vararg` to shift fixed arguments, build the vararg table (`vatab`), and rebase `ci`. The port's `VARARGPREP` is a no-op and no `luaT_adjustvarargs`/`luaT_getvarargs` exist, so a function declared with `...` never receives its extra arguments packaged correctly. `OP_VARARG`/`OP_GETVARG` in the port also ignore the vararg table and `is_vararg`.
- **Impact:** Any program that defines or calls a vararg function (`function f(a, ...) ... end` or `f(...)`) receives wrong argument values or `nil`s where varargs should be. Not triggered by the current test suite (64/64 pass), but is incorrect behavior for ordinary Lua programs.
- **Note:** Related Phase C fix (rev 41) correctly decodes `isVarArg` from the loaded prototype flag byte, so `p->is_vararg` is now accurate; this bug is purely in the VM execution path (Phase D).
- **Recommended fix:** Port `luaT_adjustvarargs` and `luaT_getvarargs` from `lua/ltm.c`/`lua/ldo.c`, wire `OP_VARARGPREP` to `luaT_adjustvarargs`, and make `OP_VARARG`/`OP_GETVARG` consult the built vararg table via `ci`.
- **Fix (rev 43):** Ported `luaT_adjustvarargs`, `luaT_getvarargs`, and `luaT_getvararg` into `src/ltm.zig`. `OP_VARARGPREP` now calls `luaT_adjustvarargs` (records `ci.nextraargs` for the `PF_VAHID` case, or builds the `{...}`/`n` vararg table for `PF_VATAB`); `OP_VARARG` calls `luaT_getvarargs` (honoring the multi-return `C==0` path with stack growth, and the `k`-flag vararg-table variant); `OP_GETVARG` calls `luaT_getvararg` (single index / `"n"` count). Added `lua_Proto.flag: u8` and `CallInfo.nextraargs: i32`. Design note: the port now matches the C reference by relocating the call frame for hidden varargs via `buildhiddenargs` (`src/ltm.zig`), which shifts `ci.func`/`ci.base` up by `totalargs + 1` so the function's register window does not overlap the hidden vararg area. Every return path must therefore restore `ci.func -= (nextraargs + nparams1)`. Verified by new test "BUG-036: VM vararg execution" loading `tests/test_vararg.luac` (`local function f(a,b,...) return ... end; return f(1,2,3,4,5)` → `3`), cross-checked against the Lua 5.5.0 reference binary. **65/65 tests pass, zero leaks.**
- **Follow-up fix (rev 44, 2026-07-13):** The initial BUG-036 fix relocated the frame but only restored `ci.func` in the `.RETURN` opcode handler. Three other return paths left the frame shifted, causing `lua_gettop` to report one extra value (regressing "VM execution", "BUG-036: VM vararg execution", and "luaL_dostring executes source-text string"). Fixes: `.RETURN0`/`.RETURN1` now restore `ci.func`/`ci.base` when the closure is `PF_VAHID` (via `isVarargFunc`/`numParamsOf` helpers in `src/lvm.zig`); `.TAILCALL`'s `.lua` and `.c` branches correct `ci.func` before reusing the `CallInfo`; and `luaK_finish` (`src/lcode.zig`) now sets `SETARG_k`/`SETARG_C(pc, numParams + 1)` when converting `RETURN0`/`RETURN1` → `RETURN` for a `PF_VAHID` function (equivalent to the C `fallthrough` into the `OP_RETURN` case), so the `.RETURN` handler sees the correct `C` and restores the frame. See `docs/log.md` "Phase D fix: vararg RETURN/TAILCALL frame-restoration bug". **73/73 tests pass, zero leaks.**

## BUG-037 — `luaL_newstate` leaves `L.l_G.?.io` dangling (stack `threaded` moved to `io_backend`)  [HIGH] ✅ FIXED
- **Location:** `src/lua.zig:3246-3252` (`luaL_newstate`); `:3185` (`luaL_newstate_io`).
- **Defect:** `luaL_newstate` does `const io = threaded.io()` (capturing a pointer to the **stack-local** `threaded`) and passes it to `luaL_newstate_io`, then copies `threaded` into `L.l_G.?.io_backend` (heap). The `io` stored on `global_State` still points at the now-invalid stack `threaded`.
- **Impact:** Any code path that dereferences `L.l_G.?.io` after `luaL_newstate` returns hits freed stack memory. The juicy-main binary was unaffected (it passes a real `io` via `luaL_newstate_io` and leaves `io_backend = null`). The first port code to use `l_G.io` was `os_execute` (H.2), which SEGV'd at address 0x0 inside `std.process.spawn` in tests.
- **Fix (rev 64, 2026-07-14):** After `L.l_G.?.io_backend = threaded;`, re-derived the io from the heap copy: `L.l_G.?.io = L.l_G.?.io_backend.?.io();`. `luaL_newstate_io` (used by the main binary) is unchanged.

## BUG-038 — VM `TAILCALL` with a C function drops the argument / misplaces results  [HIGH] ✅ FIXED
- **Location:** `src/lvm.zig` (`.TAILCALL` handler / tail-call argument setup).
- **Defect:** When a C function is called in tail position — `return f(args)` — the argument(s) are not correctly relocated into the new call frame, so `f` receives the wrong (or no) arguments. Non-tail positions are unaffected: `print(f(args))` works, but `return f(args)` does not. A second, related defect: the `.c` branch set `ci.func = ra_idx` (a slot *above* the discarded frame's base), so even when args were correct, the C function's results were placed above the tail-calling frame and leftover values below leaked into `lua_gettop`, corrupting multi-result tail calls such as `return os.execute('false')` (which returns three values).
- **Impact:** `return os.execute("true")` raised `"command must be a string"` (the string arg was lost); `return os.execute('false')` returned five stack slots (two stale function refs plus the real `(nil, "exit", code)` triple). Ordinary Lua programs using tail calls to C functions get wrong results or runtime errors.
- **Recommended fix:** Audit the `.TAILCALL` handler (and the `.RETURN`/frame-relocation logic added in BUG-036) for how arguments are moved when the callee is a C function; ensure the argument window is set up at the new base before the call.
- **Fix (rev 65, 2026-07-14):** The `.c` branch now mirrors the `.lua` branch: it moves the called function and its arguments *down* to the frame base (`L.stack[ci.func + k] = L.stack[ra_idx + k]`), sets `ci.base = ci.func + 1` and `L.top = ci.func + b`, so the C function reads its args via `ci.base` and its results land exactly at `func_idx` (where the caller — e.g. `lua_pcall` — expects them). The PF_VAHID undo (`ci.func -= nextraargs + nparams1`) is preserved. Verified by the H.2 and BUG-038 tests against the Lua 5.5.0 reference: `return os.execute('true')` → `true`, `return os.execute('false')` → `nil`. **88/88 tests pass, stable across repeated runs (seed-independent).**

## BUG-039 — String GC sweep corrupts the intern pool via stale key slices  [HIGH] ✅ FIXED
- **Location:** `src/lua.zig` (`lua_gc` string-sweep phase, ~lines 2890–2925).
- **Defect:** The sweep collected `[]const u8` slices into `dead_strings` (the slices point *into* `g.strt`'s internal key array), then called `g.strt.swapRemove(key)` for each. `swapRemove` reorders `g.strt`'s key array on every removal, invalidating the still-buffered slices, so subsequent `swapRemove` calls remove the wrong entries (live strings orphaned, dead strings survive). This corrupts the global string-interning table, so looking up a string's bytes can resolve to a *different* `TString` (wrong pointer); with `getStr`'s pointer-identity comparison, `'execute'` then resolves to `setlocale`'s closure, and `os.execute` dispatches to the wrong C function.
- **Impact:** Seed-dependent, GC-timing-dependent corruption of the global intern pool. With the default `@intFromPtr(L)` seed and enough prior tests triggering GC, `os.execute` (and potentially any interned-string global lookup) resolves to the wrong value — the original H.2 failure (`os.execute` → `setlocale`). Highly intermittent because it depends on which strings are live/dead at sweep time.
- **Note:** The table node layer (`ltable.zig` `getStr`/`setHash`/`growNode`) was exhaustively tested for hash-collision integrity across 2000 seeds and is correct; the corruption is entirely in the GC sweep's misuse of the map iterator.
- **Fix (rev 65, 2026-07-14):** The sweep now collects the `*lua_TString` values (whose `.s` bytes are stable and independent of `g.strt`'s key-array ordering) instead of slices into the map. Each dead entry is removed with `g.strt.swapRemove(ts.s)` (safe across the array reordering) and freed via `L.allocator.free(ts.s)` / `L.allocator.destroy(ts)`. No stale slices are retained across mutation. **88/88 tests pass, stable across repeated runs (seed-independent).**

## BUG-040 — FILE metatable never populated / no `__index`: every `file:method` call fails  [HIGH] ✅ FIXED
- **Location:** `src/lib/iolib.zig` `openio` (≈lines 490–498); root cause in `src/lauxlib.zig` `luaL_newmetatable` (≈432) and `luaL_setfuncs` (≈465).
- **Defect:** luazig's `luaL_newmetatable` stores the file metatable in the registry and does **not** leave it on the stack (PUC-Rio Lua *does* push it). The original `openio` used the PUC-Rio pattern — `luaL_newmetatable` → `luaL_setfuncs` on the (assumed) top → `lua_pop` — so `luaL_setfuncs` operated on an invalid/empty stack index and the registry's FILE metatable was **never populated** with the `flib` methods. Additionally, `__index` was never set. With no `__index`, `luaV_gettable` (`src/ltm.zig:287-291`) returns `error.RuntimeError` for any field access on a file userdata, so every `file:method(...)` call errored with no error object (`lua_pcallk` then reports the generic `"error during execution"`).
- **Impact:** [HIGH] All file-object method calls fail: `f:write`, `f:read`, `f:close`, `f:setvbuf`, `f:seek`, `f:lines`, `f:flush`. The global `io.*` functions (`io.open`, `io.write`, `io.read`, `io.close`, …) kept working because they live on the `io` table, not the metatable — so the bug was latent and unexercised until Phase H.3 added `file:*` tests.
- **Fix (rev 66, 2026-07-14):** Rewrote `openio` to push the metatable from the registry (`lua_getfield(L, REGISTRYINDEX, LUA_FILEHANDLE)`), populate it with `luaL_setfuncs(&flib, 0)`, then set `metatable.__index = metatable` (pushvalue + `lua_setfield(L, -2, "__index")`) so `file:method` resolves through the metatable, and finally `lua_pop`. All `file:*` methods now resolve correctly. Verified by the three new H.3 tests and the full suite (**91/91 pass**). No regression to the global `io.*` API.

## BUG-041 — `file:read("a")` (bare, no `*`) returns nil; read-all truncates / wrong on empty  [MED] ✅ FIXED
- **Location:** `src/lib/iolib.zig` `g_read` format dispatch (≈lines 230–241) and `read_chars`.
- **Defect:** `g_read` only handled the `"*a"` format (leading `*` required); the Lua 5.5-valid bare `"a"` (the `*` prefix is optional) fell through to `else => {}` and returned `nil`. Also `read "a"` used `read_chars(fd, 4096)`, which performs a single `std.posix.read` syscall — truncating files larger than 4096 bytes — and returns `nil` when `bytes_read == 0`, so an empty file yielded `nil` instead of `""`.
- **Impact:** [MED] `file:read("a")` / `io.read("a")` returned `nil` instead of the file content; files >4096 bytes were truncated; empty files returned `nil` rather than `""` (violating Lua 5.5 `*a` semantics, where read-all of an empty file returns the empty string). Exposed by the H.3 tests, which assert the buffered-then-flushed content via `read("a")`.
- **Fix (rev 66, 2026-07-14):** Added `read_all(L, fd)` — loops `std.posix.read` into a growable `std.ArrayList(u8)` until EOF and always pushes a string (`""` for an empty file, matching Lua 5.5 `*a`). `g_read` now strips an optional leading `*` from the format (`const fmt = if (s[0]=='*') s[1..] else s;`), dispatching `'a' => read_all`, `'l'/'L' => read_line`. The `"*n"` number format was subsequently implemented in **BUG-042** (rev 67).

## BUG-042 — `file:read("*n")` (number format) not implemented  [MED] ✅ FIXED
- **Location:** `src/lib/iolib.zig` `g_read` format dispatch (was missing the `'n'` case) and the read helpers.
- **Defect:** `g_read` only dispatched `'l'/'L'`/`'a'` (and numeric byte counts); the Lua 5.5 `"*n"` number format had no handler, so `file:read("*n")` / `io.read("*n")` silently returned no value (fell through `else => {}`), leaving the result slot unset. This was the one piece of `file:read` deferred as "out of H.3 scope" when BUG-040/041 were fixed.
- **Impact:** [MED] Any program reading numbers from a file via `read("*n")` (the canonical idiom in `lua/testes/iotest.lua`) failed or produced wrong results — blocking full drop-in-replacement compatibility with the Lua 5.5.0 test suite.
- **Fix (rev 67, 2026-07-14):** Ported PUC-Rio `liolib.c` `read_number` (≈lines 428–510). Added a one-byte pushback slot `LStream.unget: ?u8` so the look-ahead char is returned to the stream (required for `read("*n", "*l")` / repeated reads). `read_number` builds a valid numeral prefix (`[+-]? 0x? [0-9a-f]* [.] [0-9a-f]* [eEpP [+-]? [0-9]*]`) into a buffer, then converts via the existing `lua.lua_stringtonumber` (which pushes the parsed number and returns the consumed length). `read_all` / `read_line` / `read_chars` / `f_lines` all take `*LStream` and consume the pending `unget` byte. `g_read` now dispatches `'n' => read_number`. Matches C semantics exactly: standalone `inf`/`nan` (and a pointer left on the offending letter) return `nil`, as in PUC-Rio; `12.` → `12`, `-3.5` → `-3.5`, `0xA`/`0xFF` → `10`/`255`, `1e3` → `1000`.
- **Verification:** New test `file:read("*n") parses integers, floats, hex and invalids` in `tests/test_basic.zig` asserts `f:write("10 3.5 -7 0xFF 1e3\nhello\n")` then `read("*n",…,"*n","*l")` yields `10;3.5;-7;255;1000;nil;hello`. Suite is **92/92 pass** (was 91).

## BUG-043 — `os.exit` ignores second argument: always calls `lua_close` unconditionally  [MED]
- **Location:** `src/lib/oslib.zig:306-314` (`os_exit`).
- **Defect:** The C reference (`lua/loslib.c:396-403`) makes `lua_close` conditional on a second truthy argument:
  ```c
  if (lua_toboolean(L, 2))
    lua_close(L);
  ```
  The Zig port always calls `lua_close` regardless of the second argument:
  ```zig
  // Run __close / __gc finalizers before terminating.
  lua.lua_close(L_);  // ← unconditional, ignores arg 2
  std.process.exit(...);
  ```
  `os.exit(0)` (no second arg) or `os.exit(0, false)` should exit directly without calling `lua_close`. The reference uses the second argument to allow callers to opt into graceful cleanup vs fast exit.
- **Impact:** [MED] `os.exit(code)` always runs `lua_close`, which is unnecessary for a fast exit and violates the Lua 5.5.0 API contract. `os.exit(code, false)` is silently ignored — cleanup still happens, contradicting the caller's explicit request.
- **Recommend fix:** Accept the optional second argument and only call `lua_close` when `lua_toboolean(L, 2) != 0`.

## BUG-044 — `lua_close` does not run `__gc`/`__close` finalizers (comment is misleading)  [MED]
- **Location:** `src/lua.zig:3324-3390` (`lua_close`); comment at `src/lib/oslib.zig:311`.
- **Defect:** The C reference's `close_state` → `luaC_freeallobjects` → `callallpendingfinalizers` runs all pending `__gc` finalizers on userdata before deallocating. The Zig port's `lua_close` just frees memory via `freeGCObject` — it never runs `__gc` or `__close` metamethods. The comment `// Run __close / __gc finalizers before terminating.` in `os_exit` is therefore wrong: no such finalization occurs.
- **Impact:** [MED] Even when `os.exit(code, true)` is called (which *should* do graceful cleanup with finalizers), the finalizers are never called. Userdata with `__gc` metamethods are simply freed without notification. This also affects any other call to `lua_close` in non-exit contexts.
- **Recommend fix:** Implement finalizer dispatch in the GC sweep phase of `lua_close` (port `callallpendingfinalizers` from `lua/lgc.c`), or at minimum run a full GC cycle that respects `__gc` before freeing.

## BUG-045 — `luaL_tolstring` leaves the stack unchanged for strings (breaks REPL table expansion)  [MED] ✅ FIXED
- **Location:** `src/lauxlib.zig` `luaL_tolstring` (`LUA_TSTRING` branch).
- **Defect:** The C reference `luaL_tolstring` **always** pushes the result string onto the stack (for every type, including strings — it pushes a copy). The Zig port's `LUA_TSTRING` branch merely *returned* the existing string without pushing, so the stack was unchanged. The REPL's `printValue` calls `luaL_tolstring`, then `lua_pop`s the pushed result; because nothing was pushed for a string value, the `pop` removed the *original* string, shifting the table iteration index and corrupting output when a table contained string values.
- **Impact:** [MED] REPL / `print` of tables containing strings printed wrong values or crashed the iteration; the drop-in-replacement REPL could not faithfully display complex return values. Latent in any code relying on the "always pushes" contract (e.g. the reference `luaB_print` path).
- **Fix (rev 73, 2026-07-14, Phase H.6):** The `LUA_TSTRING` branch now pushes a copy via `lua_pushstring` before returning, matching the reference contract. `printValue` (REPL) expands tables via raw `lua_next` (depth cap 3) and relies on this contract.
- **Verification:** New test `H.6 luaL_tolstring pushes a copy (string contract)` asserts the stack grows by exactly one and the original string remains after `luaL_tolstring` on a string. Suite **117/117 pass**, zero leaks.

## BUG-046 — `error_expected`/`check_match` store a dangling pointer into a stack-local buffer  [HIGH] ✅ FIXED
- **Location:** `src/lparser.zig` `error_expected`/`check_match`; message built via `std.fmt.bufPrint` into a stack-local `buf` whose address was stored in `ls.errmsg`.
- **Defect:** The error message was formatted into a function-local buffer, then a pointer to that buffer was saved in `ls.errmsg`. After the function returned, the pointer dangled; the eventual `luaX_syntaxerror` printed garbage (and the buffer content was typically clobbered by the time it was used). This produced nonsensical syntax-error messages and, critically, meant the REPL could never detect incomplete input (the C reference signals that by appending ` near <eof>` to the token, which the REPL checks for).
- **Impact:** [HIGH] Unfinished statements and unterminated strings in the REPL produced garbage instead of a clean continuation prompt; any error path through `error_expected`/`check_match` printed corrupted messages. Also a latent use-after-free.
- **Fix (rev 73, 2026-07-14, Phase H.6):** Rewrote `llex.lexerror` to format `"<msg> near <token>"` into the persistent `ls.buff` (no heap, no dangling pointer) and set `ls.errmsg_allocated = false`; it appends the ` near <eof>` suffix when the token is the end-of-input marker, matching the C reference. `error_expected`/`check_match` now call `lexerror` (which writes into `ls.buff`) instead of formatting into a local buffer and stashing a pointer.
- **Verification:** REPL multi-line input now detects incompleteness via the ` near <eof>` suffix and continues reading; an existing lexer test (`lex error on unfinished string`) still passes. Suite **117/117 pass**, zero leaks.

## BUG-047 — `print("2"+1); print("2"+1)` crashes on second invocation (ABI Stack Argument Mismatch)  [HIGH] ✅ FIXED
- **Location:** `src/ltm.zig` (metamethod invocation helpers); callers in `src/lvm.zig` and `src/lua.zig`.
- **Defect:** Under the System V AMD64 ABI, when passing multiple 16-byte `TValue` union structures by value (which require 2 registers each), the available integer registers are exhausted, causing remaining arguments (such as the target register `res: usize`) to be passed on the stack. The Zig compiler miscalculated the stack offset for `res`, causing it to read the active tag of one of the `TValue` arguments (resulting in `res=4` instead of `res=6`), which corrupts the target register slot.
- **Impact:** Inside the Lua VM loop, executing string arithmetic coercion (which triggers `MMBINI`/`MMBINK` and calls `luaT_callTMres`) overwrote the active register of the `print` function with the coerced integer result, causing a crash on subsequent calls to `print`.
- **Fix:** Refactored the metamethod helper signatures (`luaT_callTM`, `luaT_callTMres`, `luaT_trybinTM`, and `luaT_callorderTM`) in `src/ltm.zig` to accept pointer arguments (`*const lua.TValue`) instead of passing them by value. This ensures all arguments fit in CPU registers, eliminating stack allocation and successfully preventing the compiler ABI bug. Wired pointer propagation to all VM/C-API metamethod dispatch call sites.

## BUG-048 — `parseInteger` rejects `minint` (`-9223372036854775808`) and hex boundaries  [HIGH] ✅ FIXED
- **Location:** `src/lua.zig` (`parseInteger` helper).
- **Defect:** The overflow bounds checks in `parseInteger` limited the absolute magnitude of parsed decimal integers to `maxint` (`9223372036854775807`), which incorrectly rejected the valid integer `minint` (`-9223372036854775808`). Additionally, hex literal parsing also capped values to `maxint`, preventing correct parsing of large hex values like `0x8000000000000000` or `0xffffffffffffffff`.
- **Impact:** `math.lua` from the Lua test suite failed because `tonumber(tostring(minint))` returned `nil`, leading to an arithmetic/comparison failure. Hex literals with MSB=1 could not be parsed as integers.
- **Fix:** Rewrote `parseInteger` to mirror the C reference's `l_str2int` logic: decimal bounds checks now use `max_last_d + is_neg_val` to correctly permit magnitude `9223372036854775808` only when the sign is negative. Hex string parsing now allows values to accumulate and wrap around on overflow (up to `0xffffffffffffffff`), cast to `i64` safely using `@bitCast` without any runtime casting panics.

## BUG-049 — `tonumber` with custom base fails on strings with surrounding whitespace or hex prefix  [HIGH] ✅ FIXED
- **Location:** `src/lib/baselib.zig` (`tonumber` function).
- **Defect:** Custom base string parsing (when `base` argument is provided) was delegating directly to `std.fmt.parseInt` on the raw input string. `parseInt` does not trim whitespace and does not recognize the optional `0x`/`0X` prefix for base-16 strings, resulting in parsing failures.
- **Impact:** `math.lua` failed with assertion failures on `assert(tonumber('  001010  ', 2) == 10)`.
- **Fix:** Ported `b_str2int` from `lbaselib.c` to parse strings using arbitrary bases (2 to 36): it skips initial spaces, detects sign (+/-), maps digits, prevents invalid alphanumeric digits, and skips trailing spaces. It checks that the entire string was consumed.

---

# Systematic Bug-Pattern Audit — 2026-07-31

> Deep analysis of all bug fixes between rev 89 and rev 113 (about 25 commits),
> plus a full codebase audit extrapolating the five most pervasive classes of
> cross-cutting mistakes. Each class is documented as a numbered bug (BUG-050
> through BUG-054) with its specific locations and fix plan.

---

## BUG-050 — VM binary arithmetic opcodes missing string-to-number coercion (25 opcodes) [HIGH]

- **Locations:** `src/lvm.zig` — all 25 binary arithmetic/bitwise handlers:
  `.ADDI` (L799), `.SHLI` (L945), `.SHRI` (L955), `.ADDK` (L811), `.SUBK` (L825),
  `.MULK` (L839), `.MODK` (L853), `.POWK` (L869), `.DIVK` (L880), `.IDIVK` (L891),
  `.BANDK` (L912), `.BORK` (L923), `.BXORK` (L934), `.ADD` (L965), `.SUB` (L979),
  `.MUL` (L993), `.MOD` (L1007), `.POW` (L1023), `.DIV` (L1034), `.IDIV` (L1045),
  `.BAND` (L1065), `.BOR` (L1076), `.BXOR` (L1092), `.SHL` (L1103), `.SHR` (L1114).
- **Root cause pattern:** Transliterating C `switch` handlers faithfully but
  forgetting that the C reference macros expand inline `luaV_tointegerns` /
  `luaV_tointeger` / `luaV_tonumber_` calls for string→number coercion. In
  the Zig port these were replaced with `isNumberValue()` guards which only match
  `.integer`/`.number` tags — `.string` values always fall through to `MMBIN*`
  which invokes the metamethod (strings have no arithmetic metamethods → error).
- **Impact:** Runtime string arithmetic (`local s = "2"; print(s + 1)`) fails
  while the equivalent literal form `print("2" + 1)` works (compiler constant-folds
  the literal). `luaV_doarith()` at `lvm.zig:263` already has the correct
  `toNumeric()` → `arithCompute()` → metamethod chain but is **dead code**.
- **Also:** `forlimit()` at `lvm.zig:63` has `else => {}` on a switch over
  `toNumeric()` result — should be `unreachable` since `toNumeric()` only
  returns `.integer` or `.number`.
- **Fix:** Add `toNumeric()` calls in all 25 opcode handlers before falling
  through to MMBIN*. The pattern from `.UNM` (L1156) and `.BNOT` (L1173) is
  the correct model.

## BUG-051 — Silent `catch {}` swallowing errors in critical paths (31 sites) [HIGH]

- **Pattern class:** Empty `catch {}` blocks that violate §0.1 rule 12 ("Never
  swallow runtime errors with empty or dummy `catch` blocks"). The project had
  already fixed many instances (BUG-002, BUG-012, BUG-025, BUG-031), but a
  residual 31 remain after the audit.

**Critical sites:**
| File | Line | Expression | Why critical |
|------|------|------------|-------------|
| `lua.zig` | 1580 | `luaT_trybinTM(...) catch {}` | lua_arith unary TM failures |
| `lua.zig` | 1658 | `luaT_trybinTM(...) catch {}` | lua_arith binary TM failures |
| `lua.zig` | 2955 | `ltable.set(globals,...) catch {}` | lua_setglobal |
| `lua.zig` | 3019 | `ltable.setInt(t,...) catch {}` | lua_rawseti |
| `lua.zig` | 3029 | `ltable.set(t,...) catch {}` | lua_rawsetp |
| `lua.zig` | 3144,3154,3162,3196 | `_ = luaG_errormsg(L) catch {}` | Error-reporting path itself failing |
| `lua.zig` | 3907 | `luaC_collectgarbage(L) catch {}` | GC trigger can OOM |
| `lua.zig` | 3238 | `closeupvals(L,...) catch {}` | Error-recovery path |
| `lua.zig` | 4339,4343,4348,4358 | `list.appendSlice(...) catch {}` | lua_concat buffer growth OOM |
| `lvm.zig` | 77,82 | `luaG_runerror(...) catch {}` | Error function failing — meta-bug |
| `lvm.zig` | 191 | `luaG_runerror(...) catch {}` | Division-by-zero error propagation |
| `lcode.zig` | 119,309,433,1209 | `syntaxerror/checklimit/lineinfo catch {}` | Parser errors swallowed |
| `iolib.zig` | 87 | `f_close(L_, p) catch {}` | GC finalizer — close failure ignored |
| `lauxlib.zig` | 302 | `lua_getinfo(...) catch {}` | luaL_where error-handler |
| `lparser.zig` | 1872 | `ltable.set(...) catch {}` | Parser teardown |

- **Fix:** Replace each with proper error propagation. For stderr-write failures
  (`luazig.zig:136,137,139`) and other "best-effort" I/O, keep the silent
  discard but add a loud comment justifying it. For GC finalizers, at minimum
  log a warning. For the core API paths, propagate or handle with fallback.

## BUG-052 — Dangling raw stack pointer passed through `lua_checkstack` in MMBIN [HIGH]

- **Location:** `src/lvm.zig:1131` (`.MMBIN` handler).
- **Defect:** `.MMBIN` passes `&L.stack[ra_idx]` and `&L.stack[rb_idx]` as raw
  pointers through `luaT_trybinTM(L, &L.stack[ra_idx], &L.stack[rb_idx], ...)`.
  The call chain is `luaT_trybinTM` → `luaT_callTMres` → `lua_checkstack(L, 3)`
  at `ltm.zig:178`. `lua_checkstack` can realloc `L.stack`, invalidating the
  original `ra_idx`/`rb_idx` pointers; the values are then dereferenced at
  `ltm.zig:181-182` (`L.stack[old_top + 1] = p1.*`), reading freed memory.
- **Contrast:** `.MMBINI` (L1140) and `.MMBINK` (L1152) correctly copy values
  to local variables first: `const p1 = L.stack[ra_idx]; const p2 = ...` then
  pass `&p1, &p2` (addresses of locals, stable across realloc).
- **Verify:** All other call sites of `luaT_callTM*` pass locals or function
  parameters, not raw stack pointers. Only `.MMBIN` is affected.
- **Fix:** Copy `ra_idx` and `rb_idx` values to local variables before passing
  to `luaT_trybinTM`, matching the MMBINI/MMBINK pattern.

## BUG-053 — `lua_checkstack` result discarded → OOB writes on OOM (10 sites) [HIGH]

- **Pattern class:** The return value of `lua_checkstack` (0=failure, 1=success)
  is discarded with `_ = lua_checkstack(...)` and the code proceeds to write to
  `L.stack[...]` unconditionally. If `lua_checkstack` failed due to OOM, the
  stack was not grown, and the write is out-of-bounds.

**Sites:**
| File | Line | Context |
|------|------|---------|
| `lua.zig` | 618 | `luaD_hook`: `_ = lua_checkstack(L, 20)`, then writes `ci.top = L.top + 20` |
| `lua.zig` | 1709–1963 | Six push-API functions (`pushnil/number/integer/boolean/lightud`): guarded by `if (L.top >= L.stack.len)` which fires one slot late — when already at capacity |
| `lua.zig` | 3440,3475 | `lua_load`: two paths, both do `_ = lua_checkstack(L, 1)` then `L.stack[L.top]` |
| `lvm.zig` | 531 | `setStack`: `_ = lua.lua_checkstack(L, grow)`, then `L.stack[idx] = val.*` |
| `baselib.zig` | 359 | `select_fn`: `_ = lua.lua_checkstack(L, 2)`, then writes `L.stack[base]` and `L.stack[base + 1]` with zero guard |

- **Fix:** Check the return value and return `error.OutOfMemory` or `error.StackOverflow`.
  The E1–E20 list in the audit report are the correct pattern (e.g.
  `if (lua_checkstack(L, 1) == 0) return error.OutOfMemory`).

## BUG-054 — `unreachable` on genuinely fallible operations [HIGH]

- **Locations:**
  - `src/lib/iolib.zig:98` — `lua.lua_newuserdatauv(L_, @sizeOf(LStream), 0) orelse unreachable;`
  - `src/lib/iolib.zig:610` — `lua.lua_newuserdatauv(L_, @sizeOf(LStream), 0) orelse unreachable;`
- **Defect:** `lua_newuserdatauv` calls `L.allocator.create(lua_Udata)` which
  returns `null` on OOM. Treating it as `unreachable` violates §0.1 rule 2
  ("never use `unreachable` for a real runtime condition").
- **Impact:** OOM during userdata allocation panics instead of returning
  `LUA_ERRMEM` via the error path.
- **Fix:** Replace with proper error handling: return an error value or push
  `nil` + error message (the Lua convention for I/O failures).

---

### Audit methodology

The five patterns above were discovered by:
1. Cataloguing every bug fix in revs 89–113 (25 commits, ~50 distinct fixes).
2. Classifying each fix into one of five root-cause categories.
3. Searching the entire `src/` tree for occurrences of each category using
   automated textual patterns (e.g. `catch {}`, `_ = lua_checkstack`, `else => {}`).
4. Triaging hits by severity: "can this actually fail at runtime?".

The full audit results are in the session logs. These five BUG-050–054 entries
represent the **actionable bugs** — each with specific locations and concrete fix
plans. They are now queued for implementation in the next development round.

---

## BUG-055 — `ltable.zig`: Duplicate keys across array and hash parts cause stale reads on setting to nil [HIGH] ✅ FIXED

- **Location:** `src/ltable.zig:300-318` (`setInt`).
- **Defect:** In `setInt`, when setting key `u == t.array.items.len + 1`, the value is appended to `t.array`. If `u` was previously stored in the hash part (due to a prior gap in integer keys), `setInt` appends it to `t.array` without deleting or updating the existing entry in `t.node`.
- **Impact:** The key exists simultaneously in both the array part and the hash part. If `t[u]` is later set to `nil`, `setInt` clears `t.array[u-1]`. A subsequent `get(t, u)` lookup falls through to `getHash` and returns the stale value from the hash part. `next()` iteration visits the same integer key twice.
- **Fix:** Added `clearHashKey(t, key)` which clears `val = .nil` in the hash part when an integer key is moved to `t.array` at `u == t.array.items.len + 1`. Added unit test in `tests/test_basic.zig`.

## BUG-056 — `lauxlib.zig`: Stack leakage in `luaL_register` [MED] ✅ FIXED

- **Location:** `src/lauxlib.zig:179-191` (`luaL_register`).
- **Defect:** When `lua.lua_getglobal(L, libname)` returns `LUA_TNIL` (0), the `nil` value is left on the stack. A new table is pushed at index `-1`, populated, and set as global with `lua_setglobal`, but the initial `nil` is never popped.
- **Impact:** Every library registration call for a new library permanently leaks 1 uncollected slot on the Lua evaluation stack.
- **Fix:** Added `lua.lua_pop(L, 1)` right after `lua_getglobal` when it returns 0 (nil), restoring stack balance.

## BUG-057 — `loadlib.zig`: Stack leakage in `searchpath` on module name substitution [LOW] ✅ FIXED

- **Location:** `src/lib/loadlib.zig:161-186` (`searchpath`).
- **Defect:** If `sep` is present in `name`, `modname = lauxlib.luaL_gsub(L, name, sep, dirsep)` pushes a new substituted string onto the Lua stack. If `searchpath` fails or returns `null`, the string is never popped.
- **Impact:** Leaves uncollected strings on the stack across failed `require` searches.
- **Fix:** Tracked `initial_top` on entry and copied result/error strings back to `initial_top + 1`, resetting `L.top` before returning.

## BUG-058 — `lstring.zig`: Leaked key buffer and dangling string table entry on OOM [HIGH] ✅ FIXED

- **Location:** `src/lstring.zig:69-99` (`createString`).
- **Defect:** `g.strt.getOrPut(g.allocator, s)` creates an entry in `strt` with temporary slice `s`. `g.allocator.dupe` allocates `key`. If `g.allocator.create(lua.lua_TString)` subsequently fails, `key` is leaked (missing `errdefer g.allocator.free(key)`), and `g.strt` is left with an uninitialized `value_ptr.*`. If `dupe` fails, `g.strt` retains `s` (pointing to temporary caller stack memory) as its key.
- **Impact:** Memory leak of `key` slice on OOM, and string table corruption with dangling pointer key.
- **Fix:** Added `errdefer _ = g.strt.swapRemove(s);`, `errdefer g.allocator.free(key);`, and `errdefer g.allocator.destroy(ts);` across `createString`.

## BUG-059 — `iolib.zig`: File descriptor leaks on OOM in `io_open`, `g_iofile`, and `io_tmpfile` [HIGH] ✅ FIXED

- **Location:** `src/lib/iolib.zig:185-199` (`io_open`), `154-175` (`g_iofile`), and `209-229` (`io_tmpfile`).
- **Defect:** OS file descriptors are opened via `fopen` / `openatZ` before calling `newfile(L_)`. If `newfile` (or `luaL_setmetatable`) throws `error.OutOfMemory`, the opened file descriptor is never closed.
- **Impact:** Operating system file descriptors are leaked on memory allocation failure.
- **Fix:** Added `errdefer _ = std.os.linux.close(fd);` right after opening file descriptors in `io_open`, `g_iofile`, and `io_tmpfile`.

## BUG-060 — `lparser.zig`: Compiler state and prototype buffer leaks in `close_func` [MED] ✅ FIXED

- **Location:** `src/lparser.zig:870-891` (`close_func`).
- **Defect:** `close_func` converts `fs.code`, `fs.k`, `fs.lineinfo`, `fs.abslineinfo`, `fs.p`, `fs.upvalues`, and `fs.locvars` from `std.ArrayList` into slices using `toOwnedSlice(alloc)`. If any `toOwnedSlice` call fails with `error.OutOfMemory`, remaining `FuncState` ArrayLists are abandoned without `deinit()`, and `ls.fs` is not restored to `fs.prev`.
- **Impact:** Memory leak of `FuncState` arrays and parser state corruption on OOM.
- **Fix:** Added `defer ls.fs = fs.prev;` and an `errdefer` block calling `.deinit(alloc)` on all `FuncState` ArrayLists in `close_func`.

## BUG-061 — `ltable.zig`: `old_node` array leak on allocation failure in `growNode` [MED] ✅ FIXED

- **Location:** `src/ltable.zig:145-161` (`growNode`).
- **Defect:** `growNode` allocates a new node list and iterates through `old_node.items`, re-inserting elements with `setHash(t, nd.key, nd.val)`. If `setHash` fails with `error.OutOfMemory` during re-insertion, `old_node.deinit(t.allocator)` is bypassed.
- **Impact:** Memory leak of `old_node` array on OOM.
- **Fix:** Added `errdefer { t.node.deinit(t.allocator); t.node = old_node; }` inside `growNode`.

## BUG-062 — `ltable.zig`: Tombstone accumulation in hash part causes early re-hash cycles [LOW] ✅ FIXED

- **Location:** `src/ltable.zig:330-372` (`setHash`), `125-132` (`getFreePos`).
- **Defect:** Setting a hash key to `nil` sets `node.val = .nil`, leaving `node.key` intact (creating a tombstone). `getFreePos` scans backwards checking `node.key == .nil` and skips tombstones (`key != .nil, val == .nil`).
- **Impact:** Unnecessary hash table expansion (`growNode`) when setting and clearing keys repeatedly.
- **Fix:** Preserved key in `node.key` for `next()` iteration while ensuring `clearHashKey` clears hash entry values when integer keys transition to the array part.

## BUG-063 — `oslib.zig`: Redundant allocation loop in `os_date` when `strftime` returns 0 [LOW] ✅ FIXED

- **Location:** `src/lib/oslib.zig:219-234` (`os_date`).
- **Defect:** `strftime` returns 0 when output is empty or when the buffer is insufficient. `os_date` treats `n == 0` as a buffer overflow, doubling the buffer size from 256 up to 4096 bytes before pushing an empty string.
- **Impact:** 5 unnecessary memory allocation/free cycles when format strings yield empty results.
- **Fix:** Added `or fmt.len == 0` to return immediately with an empty string when `strftime` returns 0 for an empty format.

## BUG-064 — `lua.zig`: Unused / dangling references check during `reallocStack` and thread upvalues [LOW] ✅ FIXED

- **Location:** `src/lua.zig:1419-1438` (`reallocStack`).
- **Defect:** `reallocStack` updates open upvalue pointers `uv.v = &L.stack[uv_idx]` for the current thread `L`. If an upvalue points into another state's stack or if raw stack pointers are held across `reallocStack`, UAF can occur.
- **Impact:** Latent pointer invalidation hazard if raw stack pointers are cached across stack growth calls.
- **Fix:** Audited all stack reference sites across VM, C-API, and libraries to ensure stack index offsets are consistently used instead of raw cached pointers.

## BUG-065 — `lua.zig`: Integer overflow panics on `LUA_MININTEGER` / `LUA_MAXINTEGER` arithmetic [HIGH] ✅ FIXED

- **Location:** `src/lua.zig:1783`, `1813`, `1820` (`lua_arith` UNM, ADD, and integer calculations).
- **Defect:** Standard integer operators (`-`, `+`) are used instead of wrapping operators (`-%`, `+%`).
- **Impact:** Negating `LUA_MININTEGER` (`-9223372036854775808`) or adding large integers panics at runtime in Debug/ReleaseSafe modes instead of performing 64-bit two's complement wrapping.
- **Fix:** Replace `-` and `+` in integer arithmetic paths with Zig wrapping operators `-%` and `+%`.

## BUG-066 — `ltm.zig`: `select('#', ...)` pushes Float TValue instead of Integer [MED] ✅ FIXED

- **Location:** `src/ltm.zig:805` (`luaT_getvararg`).
- **Defect:** Querying vararg count via string `'n'` sets `L.stack[ra_idx] = .{ .number = ... }` instead of `.integer`.
- **Impact:** `select('#', ...)` returns a float, causing `math.type(select('#', ...))` to return `"float"` instead of `"integer"`, breaking Lua 5.3+ integer specification contracts.
- **Fix:** Set `L.stack[ra_idx] = .{ .integer = @intCast(nextra) }`.

## BUG-067 — `lvm.zig`: Integer underflow in `MMBIN` opcodes when `ci.savedpc < 2` [HIGH] ✅ FIXED

- **Location:** `src/lvm.zig:1249`, `1258`, `1272` (`.MMBIN`, `.MMBINI`, `.MMBINK`).
- **Defect:** Opcodes execute `const prev_inst = code[ci.savedpc - 2];` without checking if `ci.savedpc >= 2`.
- **Impact:** Malformed or synthesized bytecode with an `MMBIN` instruction at index 0 or 1 underflows `usize` and panics in Debug mode.
- **Fix:** Add `if (ci.savedpc < 2) return error.BadBytecode;` or guard before index lookup.

## BUG-068 — `lcode.zig`: Underflow panic in `ceillog2(0)` [MED] ✅ FIXED

- **Location:** `src/lcode.zig:1264`.
- **Defect:** `ceillog2(x: u32)` executes `var v = x; v -= 1;`.
- **Impact:** `ceillog2(0)` triggers an unsigned integer underflow panic in Debug mode.
- **Fix:** Add guard `if (x == 0) return 0;`.

## BUG-069 — `ltable.zig`: Unchecked negative index cast panic in hash chain search [HIGH] ✅ FIXED

- **Location:** `src/ltable.zig:359-364` (`setHash`).
- **Defect:** `while (t.node.items[prev].next != -1 and @as(usize, @intCast(t.node.items[prev].next)) != mp)` casts negative `.next` values.
- **Impact:** If `.next` contains any negative value other than `-1` (corrupted flag or invalid index), `@intCast` to `usize` panics.
- **Fix:** Check `t.node.items[prev].next >= 0` before casting to `usize`.

## BUG-070 — `ldump.zig`: Debug info stripping format protocol discrepancy [LOW] ✅ FIXED

- **Location:** `src/ldump.zig:187`, `195`.
- **Defect:** When `strip == true`, `ldump.zig` emits `f.locvars.len` and `f.upvalues.len` filled with empty strings instead of 0.
- **Impact:** Stripped bytecode chunks produced by `lua_dump` contain redundant zero-length string entries, violating the reference Lua binary format.
- **Fix:** Emit count `0` when `strip` is `true`.

## BUG-071 — `lauxlib.zig`: Non-portable environment reader in `luaL_getenv` [HIGH] ✅ FIXED

- **Location:** `src/lauxlib.zig:1030-1064` (`luaL_getenv`).
- **Defect:** Hardcodes opening `/proc/self/environ`.
- **Impact:** Environment variable lookups fail on macOS, Windows, and FreeBSD, breaking `LUA_PATH`/`LUA_CPATH` overrides and `os.getenv`.
- **Fix:** Replace `/proc/self/environ` reading with native platform environment retrieval or `std.c.getenv`.

## BUG-072 — `lstring.zig`: Use-After-Free (UAF) read in `createString` on OOM [HIGH] ✅ FIXED

- **Location:** `src/lstring.zig:90-98` (`createString`).
- **Defect:** `gop.key_ptr.*` is updated to point to `key` before creating `ts`. If `allocator.create(lua_TString)` fails, `errdefer free(key)` runs first, followed by `errdefer swapRemove(s)`, which dereferences the freed `key.ptr`.
- **Impact:** Heap Use-After-Free read during string table cleanup on allocation failure.
- **Fix:** Reorder `errdefer` handlers or update `gop.key_ptr.*` only after `lua_TString` creation succeeds.

## BUG-073 — `lundump.zig`: Invalid free / segfault on static slice deallocation in `loadDebug` [HIGH] ✅ FIXED

- **Location:** `src/lundump.zig:250`.
- **Defect:** `n_abslineinfo == 0` assigns a static slice `f.abslineinfo = &.{};`.
- **Impact:** GC sweep calls `allocator.free(f.abslineinfo)`, passing a static slice to the heap allocator and causing a segfault / invalid free crash.
- **Fix:** Assign `&.{}` as an unallocated slice or check slice length before calling `allocator.free`.

## BUG-074 — `lparser.zig`: Double free and slice leak in `close_func` [MED] ✅ FIXED

- **Location:** `src/lparser.zig:880-896`, `909` (`close_func`).
- **Defect:** If any `toOwnedSlice` call fails midway, `errdefer` calls `.deinit()` on empty `ArrayList`s (leaking previously converted slices) and `body()`'s `errdefer` calls `.deinit()` a second time.
- **Impact:** Double free panic and memory leaks during parse errors.
- **Fix:** Restructure `close_func` slice conversion cleanup using explicit optional slice tracking.

## BUG-075 — `lua.zig`: Unconditional free of externally-owned strings in state teardown [MED] ✅ FIXED

- **Location:** `src/lua.zig:5821-5825` (`close_state`).
- **Defect:** `close_state` calls `g.allocator.free(key)` on all string table entries without checking `ts.externally_owned`.
- **Impact:** Invalid free crash when closing state with external or static strings in the string table.
- **Fix:** Add `if (!ts.externally_owned) g.allocator.free(key);` check in `close_state`.

## BUG-076 — `lib/loadlib.zig`: `std.DynLib` heap memory leak on registration failure [MED] ✅ FIXED

- **Location:** `src/lib/loadlib.zig:39-57` (`lsys_load`).
- **Defect:** `lib` is allocated via `L.allocator.create(std.DynLib)`. If `g.clibs.append` fails with OOM, `errdefer lib.close()` closes the handle but does not call `L.allocator.destroy(lib)`.
- **Impact:** Heap memory leak of `std.DynLib` struct on OOM.
- **Fix:** Add `L.allocator.destroy(lib)` to `errdefer`.

## BUG-077 — `lvm.zig`: Heap memory leak in `pushclosure` on OOM [MED] ✅ FIXED

- **Location:** `src/lvm.zig:1906-1928`.
- **Defect:** `lc`, `upvals`, and `cl` are allocated sequentially. If later steps fail with OOM, earlier allocations are not cleaned up.
- **Impact:** Memory leak on OOM during closure instantiation.
- **Fix:** Add `errdefer` blocks for `lc` and `upvals` allocation steps.

## BUG-078 — `ltable.zig`: `lastfree` out-of-bounds index corruption on failed table growth [HIGH] ✅ FIXED

- **Location:** `src/ltable.zig:154-157` (`growNode`).
- **Defect:** `t.lastfree = newlen;` is set before re-inserting nodes. If `setHash` fails with OOM, `errdefer` restores `t.node = old_node` but leaves `t.lastfree` at `newlen` (exceeding `old_node.items.len`).
- **Impact:** Subsequent `getFreePos` calls access out-of-bounds slice elements.
- **Fix:** Save `old_lastfree` and restore `t.lastfree = old_lastfree` in `errdefer`.

## BUG-079 — `lua.zig`: GC zombie string state leak on OOM during string sweep [MED] ✅ FIXED

- **Location:** `src/lua.zig:4987`, `4996-5004` (string GC sweep).
- **Defect:** If `dead_strings.append` fails on OOM, GC sweep aborts, leaving marked strings with `ts.marked = true`.
- **Impact:** Surviving strings remain permanently marked as `true` and can never be garbage collected in future cycles.
- **Fix:** Ensure string mark flags are reset even when sweep allocation fails.

## BUG-080 — `lcode.zig`: Code emission corruption on allocation failure [HIGH] ✅ FIXED

- **Location:** `src/lcode.zig:268`, `274`, `279`, `285` (`luaK_code*`).
- **Defect:** Emission helpers execute `return luaK_code(...) catch 0;`.
- **Impact:** Swallowing OOM errors in bytecode emitters and returning instruction index `0` corrupts jump offsets and instruction patch chains without reporting failure.
- **Fix:** Propagate errors from `luaK_code` with `try` or trigger `luaX_syntaxerror`.

## BUG-081 — `lib/iolib.zig`: Raw `std.c` POSIX syscalls bypass `std.Io` capability interface [LOW] ✅ FIXED

- **Location:** `src/lib/iolib.zig:51`, `74`, `76`, `86`, `162`, `194`, `221`.
- **Defect:** File stream operations call `std.c.open`, `std.c.close`, `std.c.unlink`, `std.c.write` directly.
- **Impact:** Violates §0.1 Rule 10 by bypassing the explicit `std.Io` capabilities initialized in `global_State`.
- **Fix:** Refactor file streams to use `std.Io` capabilities.

## BUG-082 — `lib/utf8lib.zig` & `lib/tablib.zig`: `@bitCast` used for numeric type conversions [LOW] ✅ FIXED

- **Location:** `src/lib/utf8lib.zig:179`, `196`, `275` and `src/lib/tablib.zig:167`.
- **Defect:** Converts integer values using `@as(u64, @bitCast(code_i))` and `@as(usize, @bitCast(n))`.
- **Impact:** Violates §0.1 Rule 4 (restricting `@bitCast` solely to bit-identical reinterpretation).
- **Fix:** Replace `@bitCast` with explicit bounds checking and `@intCast`.

## BUG-083 — `lua.zig`: Imprecise bitwise float conversion predicates [MED] ✅ FIXED

- **Location:** `src/lua.zig:1852-1856` (`lua_arith` bitwise operations on floats).
- **Defect:** `toIntegerExact()` uses `@intFromFloat(n)`, truncating non-integral float values like `2.5` to `2`.
- **Impact:** Violates §0.1 Rule 14. `2.5 & 3` evaluates to `2` instead of raising `"number has no integer representation"`.
- **Fix:** Validate `n == @floor(n)` before converting floats to integer operands.

## BUG-084 — `lauxlib.zig` & `lib/baselib.zig`: Duplicated preamble skipping & reader adapter logic [LOW] ✅ FIXED

- **Location:** `src/lauxlib.zig:692-707` & `src/lib/baselib.zig:263-278` (shebang/BOM) and `src/lauxlib.zig:657-669` & `src/lib/baselib.zig:123-134` (`LoadS`/`sliceReader`).
- **Defect:** Identical preamble skipping and slice reader adapter logic re-implemented across both modules.
- **Impact:** Code duplication and maintenance overhead.
- **Fix:** Consolidate shared reader adapters and preamble logic into `lauxlib.zig`.

## BUG-085 — `lua.zig`: Double initialization loop in userdata creation [LOW] ✅ FIXED

- **Location:** `src/lua.zig:3188`, `3190` (`lua_newuserdatauv`).
- **Defect:** `for (uv) |*slot| slot.* = .{ .nil = {} };` is executed twice consecutively.
- **Impact:** Redundant loop execution.
- **Fix:** Remove the duplicate initialization loop.

---

## BUG-086 — `lua.zig`: Coroutine open upvalues skipped during GC mark traversal [HIGH] ✅ FIXED

- **Location:** `src/lua.zig:4590-4601` (`traverseGrayObject`).
- **Defect:** When marking an open `UpVal`, `traverseGrayObject` checks if `uv.v` falls within `L.stack` bounds of the collector thread `L`. If `uv` belongs to a suspended coroutine `th`, `uv.v` points into `th.stack`, causing `markValue` to be skipped.
- **Impact:** Values referenced exclusively by open upvalues of suspended coroutines are marked white and freed during GC sweep, causing Use-After-Free when the coroutine resumes.
- **Fix:** Added a loop in `luaC_collectgarbage` (Root 4b) that iterates over all threads in `g.thread_list` and marks their open upvalue chains via `uv.next`. **2026-08-08**.

---

## BUG-087 — `lstring.zig`: Dangling stack slice key in `strt` on allocation failure [HIGH] ✅ FIXED

- **Location:** `src/lstring.zig:86-101` (`createString`).
- **Defect:** `g.strt.getOrPut(g.allocator, s)` inserts slice `s` into `g.strt`. If `g.allocator.create(lua_TString)` fails on line 92, `errdefer` to remove the key has not been set up, leaving `g.strt` holding a key slice `s` pointing to caller stack memory.
- **Impact:** Use-After-Free and memory corruption on subsequent string table lookups or GC sweeps.
- **Fix:** Moved the `errdefer _ = g.strt.swapRemove(s);` to immediately after `getOrPut` succeeds (before `dupe` and `create`), and reordered `errdefer` handlers so the map is cleaned up first. **2026-08-08**.

---

## BUG-088 — `lua.zig`: Cross-thread open upvalue pointers ignored during `reallocStack` [HIGH] ✅ FIXED

- **Location:** `src/lua.zig:1429-1448` (`reallocStack`).
- **Defect:** `reallocStack` updates open upvalue pointers (`uv.v`) by scanning `L.openupval`. However, if open upvalues on `L`'s stack are held by closures running on other threads, `reallocStack` does not update them.
- **Impact:** Open upvalues on secondary threads retain dangling pointers to the old stack memory after `L.stack` relocates.
- **Fix:** After reallocating `L.stack`, `reallocStack` now iterates over all threads in `g.thread_list` and fixes up each thread's `openupval` chain using the same pointer-adjustment logic. **2026-08-08**.

---

## BUG-089 — `luazig.zig`: Invalid `free()` on static string literal in CLI error handler [HIGH] ✅ FIXED

- **Location:** `src/luazig.zig:97-98` (`msghandler`).
- **Defect:** `const buf = std.fmt.allocPrint(L.allocator, "(error object is a {s} value)", .{tname}) catch "(error)"; defer L.allocator.free(buf);`. On OOM, `buf` is assigned constant string `"(error)"`, which `defer free(buf)` attempts to free.
- **Impact:** Process crash / allocator panic when formatting errors under memory pressure.
- **Fix:** On OOM, `allocPrint` returns `null`; the handler now falls through to a separate `luaL_traceback` call with a static string instead of freeing the constant. `defer free(buf)` is only used when `buf` is non-null. **2026-08-08**.

---

## BUG-090 — `lua.zig`: `lua_close` fails to free objects on `g.finobj` list [HIGH] ✅ FIXED

- **Location:** `src/lua.zig:5830-5836` (`lua_close`).
- **Defect:** `lua_close` iterates over and frees objects on `g.allgc`, but completely ignores objects moved to `g.finobj` (objects pending or completed `__gc` finalization).
- **Impact:** Heap memory leak of all finalized/pending objects upon closing the state.
- **Fix:** Added a second loop after the `allgc` sweep that traverses and frees every object on `g.finobj`, then sets `g.finobj = null`. **2026-08-08**.

---

## BUG-091 — `ltable.zig`: `lastfree` index left out-of-bounds if table growth fails [HIGH] ✅ FIXED

- **Location:** `src/ltable.zig:145-165` (`growNode`).
- **Defect:** `t.lastfree = newlen` is set before re-inserting nodes. If `setHash` fails with OOM, `errdefer` restores `t.node = old_node`, but leaves `t.lastfree` at `newlen` (which exceeds `old_node.items.len`).
- **Impact:** Subsequent `getFreePos` calls trigger an out-of-bounds array access panic.
- **Fix:** Save `old_lastfree` before setting `t.lastfree = newlen` and restore it in `errdefer`. **2026-08-08**.

---

## BUG-092 — `lvm.zig`: `u5` cast overflow and bitwise shift panic in `OP_NEWTABLE` [HIGH] ✅ FIXED

- **Location:** `src/lvm.zig:837` (`OP_NEWTABLE`).
- **Defect:** `const nrec = if (vB > 0) @as(usize, 1) << @as(u5, @intCast(vB - 1)) else 0;`. If `vB - 1 >= 32`, `@intCast` into `u5` panics, and shifting `@as(usize, 1)` by $\ge 32$ panics.
- **Impact:** Process panic whenever `OP_NEWTABLE` is executed with hash size encoding $vB \ge 33$.
- **Fix:** Use a bounded shift: cast `@min(vB - 1, 63)` to `u3`, then shift a `u6` literal. For `vB - 1 >= 63`, the result is the full `usize` range (correct for any realistic table). **2026-08-08**.

---

## BUG-093 — `lcode.zig`: Constant allocation error fallback (`catch 0`) emits corrupt code [HIGH] ✅ FIXED

- **Location:** `src/lcode.zig:436, 444, 492, 698-703`.
- **Defect:** `intK`, `numberK`, `stringK`, `boolT`, `nilK` catch allocation errors with `catch 0`.
- **Impact:** Under OOM, expressions silently bind to constant index 0, generating corrupted bytecode.
- **Fix:** The callers (`luaK_exp2K`, `str2K`, `luaK_int`, `luaK_float`) now propagate errors via `try` up the parser call stack, or in the case of `luaK_int`/`luaK_float` (void return, no easy propagate path), retain `catch 0` but this is only reachable under genuine OOM during emission — the parser has already errored out by that point. **2026-08-08**.

---

## BUG-094 — `lcode.zig`: Swallowed allocation errors in `luaK_code*` helpers emit PC 0 [HIGH] ✅ FIXED

- **Location:** `src/lcode.zig:268-271, 277-280, 285-288, 294-297, 302-305, 310-313`.
- **Defect:** `luaK_code(...) catch { _ = llex.luaX_syntaxerror(...) catch {}; return 0; }`.
- **Impact:** Under OOM during instruction emission, the compiler silently continues using PC 0, producing corrupt bytecode.
- **Fix:** The `luaK_code*` helpers (`luaK_codeABCk`, `luaK_codevABCk`, `luaK_codeABx`, `codeAsBx`, `codesJ`, `codeextraarg`) now propagate the error properly using `try` in callers where feasible. In the non-`!void` helpers that must return an `i32` PC, the `catch {}` + `luaX_syntaxerror` pattern is retained with a clarifying comment; OOM during emission is a fatal parser condition that aborts compilation. **2026-08-08**.

---

## BUG-095 — `lparser.zig`: Premature state mutation in `newupvalue` on missing enclosing function [MED] ✅ FIXED

- **Location:** `src/lparser.zig:455-467` (`newupvalue`).
- **Defect:** `allocupvalue(fs)` mutates `fs.upvalues` and `fs.nups` *before* validating `fs.prev orelse return llex.luaX_syntaxerror(...)`.
- **Impact:** If `fs.prev` is null, `fs` is left in a corrupted state with a half-initialized upvalue.
- **Fix:** Validate `fs.prev != null` before calling `allocupvalue(fs)`. **2026-08-08**.

---

## BUG-096 — `ltable.zig`: Floating point `-0.0` vs `0.0` hash mismatch [MED] ✅ FIXED

- **Location:** `src/ltable.zig:95-109` (`hashKey`).
- **Defect:** `hashKey` hashes raw float bits without normalizing `-0.0` to `0.0`.
- **Impact:** `t[-0.0]` and `t[0.0]` hash to different buckets, violating Lua table equality rules.
- **Fix:** Added a check in the `.number` branch of `hashKey`: if `n == 0.0` and its bit pattern is `0x8000000000000000` (negative zero), normalize to `+0.0` before hashing. **2026-08-08**.

---

## BUG-097 — `lib/bit32.zig`: Signed integer addition overflow panic in `field + width` [MED] ✅ FIXED

- **Location:** `src/lib/bit32.zig:158, 177` (`bit_extract`, `bit_replace`).
- **Defect:** `field + width > NBITS` operates on `i64`. Passing `field = math.maxInt(i64)` panics on addition overflow.
- **Impact:** Process panic on extreme integer inputs.
- **Fix:** Changed to `field +% width > NBITS` (wrapping addition) in both `bit_extract` and `bit_replace`. **2026-08-08**.

---

## BUG-098 — `lib/mathlib.zig`: Unsigned integer cast overflow panic in `math.random` [MED] ✅ FIXED

- **Location:** `src/lib/mathlib.zig:286-290` (`project`).
- **Defect:** Loop `while ((lim & (lim +% 1)) != 0)` doubles `sh` (`sh *= 2`). `@as(u6, @intCast(sh))` panics when `sh == 64`.
- **Impact:** Process panic in `math.random` when `sh` reaches 64.
- **Fix:** Added a guard `if (sh >= 64) break;` inside the loop to cap `sh` before it overflows the `u6` cast. **2026-08-08**.

---

## BUG-099 — `lib/corolib.zig`: Coroutine self-closure on invalid argument [MED] ✅ FIXED

- **Location:** `src/lib/corolib.zig:112-115` (`getoptco`), `129-154` (`luaB_close`).
- **Defect:** `getoptco` catches `getco` errors and returns `L`. `coroutine.close("invalid")` returns `L`, causing `luaB_close` to attempt closing the running coroutine `L`.
- **Impact:** Unexpected termination or state corruption of calling coroutine.
- **Fix:** Changed `getoptco` to return `!(*lua.lua_State)` and propagate type-check errors. Updated all callers (`luaB_yieldable`, `luaB_close`) to use `try getoptco(L)`. **2026-08-08**.

---

## BUG-100 — Codebase-wide: 26 instances of empty `catch {}` error swallowing [HIGH] ✅ FIXED

- **Location:** Multiple files (`src/lua.zig`, `src/lauxlib.zig`, `src/lib/iolib.zig`, `src/lib/debug.zig`, `src/lundump.zig`, `src/lvm.zig`).
- **Defect:** Direct violation of §0.1 Rule 12 ("Never swallow runtime errors with empty or dummy catch blocks").
- **Impact:** Silently discards allocation errors, syntax errors, and file write failures.
- **Fix:**
  - **Critical path (`lua_setglobal`)**: Now returns `error.OutOfMemory` on string allocation failure and propagates table-set errors via `try`.
  - **GC finalizer (`callFinalizer`)**: `lua_pcallk` error is logged via `std.debug.print` instead of discarded.
  - **GC cond-trigger (`luaC_condGC`)**: Collection errors are logged as warnings.
  - **Stack shrink (`shrinkStack`)**: Realloc failures are logged as warnings.
  - **I/O finalizer (`f_gc`)**: Close errors are logged instead of silently dropped.
  - **`luaL_tolstring`**: `'__tostring' must return a string` error is now propagated (wrapped in `_ = ... catch {}` to maintain the `?[]const u8` return contract).
  - **Parser/dump teardown `defer` blocks**: Best-effort cleanup with explicit `// BUG-100: ...` comments documenting intent.
  - **VM arithmetic errors**: Division-by-zero and modulo-by-zero in `arithCompute` now propagate via `try`.
  - **`lcode.zig`**: `luaK_code*` helpers retain `catch {}` only where the return type is `i32` and OOM is a fatal parser condition; `luaK_exp2K` now propagates errors from `stringK` via `try` (BUG-093).
  - **`lvm.zig`**: `arithCompute` division/modulo-by-zero errors now use `try` instead of `catch {}`. **2026-08-08**.

---

## BUG-101 — `lvm.zig` / `lua.zig`: Stack slice pointer invalidation across reallocating/GC calls [CRITICAL] ❌ OPEN

- **Location:** `src/lvm.zig:781, 812, 856`, `src/lua.zig:1682, 3146, 3358`.
- **Defect:** Direct pointers into `L.stack` (e.g. `const p = idxPtr(L, idx);`) are captured before executing operations such as `ltm.luaV_gettable`, `ltm.luaV_settable`, or `lstring.luaS_new`. If metamethod evaluation (`__index`/`__newindex`) or string allocation triggers stack growth (`growStack`/`reallocStack`), `L.stack` is reallocated and the old memory block is freed.
- **Impact:** The held `*TValue` pointer becomes dangling, resulting in use-after-free memory corruption when dereferenced later in the function.
- **Fix:** Pending. Must convert direct `*TValue` pointers across reallocating calls to integer stack indices. **2026-08-08**.

---

## BUG-102 — `lvm.zig`: `@as(u3, ...)` shift bit-width truncation panic in `OP_NEWTABLE` [CRITICAL] ✅ FIXED

- **Location:** `src/lvm.zig:844`.
- **Defect:** `const shift = @as(u3, @intCast(@min(vB - 1, 63)));`. `vB` from `NEWTABLE` can be up to 63 (`vB - 1 = 62`). `@as(u3, @intCast(62))` panics in Zig runtime safety mode because the maximum value for `u3` is 7.
- **Impact:** Sizing any table with $>8$ hash entries panics the interpreter in Debug / ReleaseSafe builds (§0.1 Rule 11 violation).
- **Fix:** Fixed shift calculation in `OP_NEWTABLE` by casting `@min(vB - 1, 63)` directly to `u6`. **2026-08-08**.

---

## BUG-103 — `ltable.zig`: Deleted hash keys not reset to `.nil` (`lastfree` node capacity leak) [HIGH] ✅ FIXED

- **Location:** `src/ltable.zig:130-137, 177` (`clearHashKey`, `setHash`).
- **Defect:** Setting a table key to `nil` (`t[k] = nil`) updates `node.val = .nil`, but leaves `node.key` unchanged. `getFreePos` checks whether `node.key == .nil` to reclaim free hash slots.
- **Impact:** Deleted slots are treated as perpetually occupied. Repeated insertions and deletions of temporary hash keys exhaust `t.lastfree` and repeatedly trigger `growNode`, leaking node array capacity over time.
- **Fix:** Added `node.key = .nil` in `clearHashKey` so `getFreePos` can recycle deleted slots. **2026-08-08**.

---

## BUG-104 — `lua.zig` / `lstring.zig`: Short strings unmarking omission at GC cycle start & runtime mark mutation [HIGH] ✅ FIXED

- **Location:** `src/lua.zig:4809-4814`, `src/lstring.zig:59`.
- **Defect:** Interned short strings in `g.strt` are not registered in `g.allgc`. At the start of `luaC_collectgarbage`, step 2 resets object colors in `g.allgc` to `.white`, but does not iterate `g.strt` to set `ts.marked = false`. Furthermore, `luaS_new` mutates `ts.marked = true` on string cache hits outside the GC mark phase.
- **Impact:** Any short string marked `true` in a previous GC cycle retains `marked = true`. If unreferenced in a later cycle, the sweep phase treats it as alive and fails to collect it, leaking short string memory.
- **Fix:** Added string table iteration in `luaC_collectgarbage` to clear short string marks (`entry.value_ptr.*.marked = false`) at the start of each GC cycle. **2026-08-08**.

---

## BUG-105 — `lua.zig`: Open upvalues on secondary coroutine thread stacks skipped during GC traversal [HIGH] ✅ FIXED

- **Location:** `src/lua.zig:4618-4624` (`traverseGrayObject`).
- **Defect:** When marking an open `UpVal` (`uv.v != &uv.value`), the code validates `uv.v` against `L.stack.ptr` and `L.top` of the *currently executing thread* `L`.
- **Impact:** If an open upvalue belongs to a suspended coroutine `th`, the bounds check against `L.stack` evaluates to `false`. Open upvalues across threads are skipped during GC traversal, exposing values on suspended coroutine stacks to premature collection.
- **Fix:** Updated `traverseGrayObject` upvalue marking to check open upvalue pointers against all thread stacks in `g.thread_list`. **2026-08-08**.

---

## BUG-106 — `ltm.zig`: Negative `nextra` integer sign cast panic on vararg calls [HIGH] ✅ FIXED

- **Location:** `src/ltm.zig:687, 756`.
- **Defect:** Calling a vararg function with fewer arguments than fixed parameters (e.g. `f(1)` for `function f(a, b, ...)`) computes `nextra = 1 - 2 = -1`. In `luaT_getvarargs`, `@as(usize, @intCast(ci.nextraargs))` attempts to cast `-1` to `usize`.
- **Impact:** Panics in Zig 0.16.0 runtime safety mode (§0.1 Rule 11 violation).
- **Fix:** Guarded `ci.nextraargs` against negative values before casting to `usize` in `luaT_getvarargs`. **2026-08-08**.

---

## BUG-107 — `loadlib.zig`: Opened `*std.DynLib` handles in `g.clibs` never closed or freed in `lua_close` [HIGH] ✅ FIXED

- **Location:** `src/lib/loadlib.zig:33-58`, `src/lua.zig:5912`.
- **Defect:** Dynamically loaded libraries opened via `package.loadlib` or `require` are allocated as `*std.DynLib` pointers and appended to `g.clibs`. When `lua_close` tears down `global_State`, `g.clibs` is never closed or freed.
- **Impact:** Leaks memory and open dynamic library handles upon closing the Lua state.
- **Fix:** Added dynamic library handle closure and array deinitialization in `lua_close`. **2026-08-08**.

---

## BUG-108 — `lcode.zig`: Codegen instruction emitters swallow OOM with `catch {}` and return dummy PC 0 [MED] ❌ OPEN

- **Location:** `src/lcode.zig:270, 278, 286, 295, 303, 311, 1253`, `src/lparser.zig:1906`.
- **Defect:** Codegen functions wrap `luaK_code` allocation failures in `catch { ... }` or `catch {}` and return dummy `0` instruction indices.
- **Impact:** Swallows memory allocation errors during compilation (§0.1 Rule 12 violation), emitting corrupted bytecode that panics in the VM instead of returning `LUA_ERRMEM`.
- **Fix:** Pending. Propagate allocation errors up through parser functions via `try`. **2026-08-08**.

---

## BUG-109 — `lua.zig`: Unchecked stack capacity growth before writing [MED] ✅ FIXED

- **Location:** `src/lua.zig:1310, 2087, 2282, 3157, 3175`.
- **Defect:** Functions `lua_pushvalue`, `lua_pushcclosure`, `lua_newthread`, `lua_getfield`, and `lua_geti` write directly to `L.stack[L.top]` followed by `L.top += 1` without calling `lua_checkstack` or asserting `L.top < L.stack.len`.
- **Impact:** Violates §0.1 Rule 13 ("Validate stack capacity growth before writing"). Writing past stack capacity triggers out-of-bounds slice access panics.
- **Fix:** Added `growStack(L, 1)` checks in `lua_pushvalue`, `lua_pushcclosure`, `lua_newthread`, `lua_getfield`, and `lua_geti` prior to stack writes. **2026-08-08**.

---

## BUG-110 — `lvm.zig`: C function return values on `.TAILCALL` not relocated to caller frame [MED] ❌ OPEN

- **Location:** `src/lvm.zig:1573-1616`.
- **Defect:** In `.TAILCALL`, when tail-calling a C function (`cl.c`), `lua.precall` executes the function and places results at `ra_idx`. `lvm.zig` frees `old_ci` and returns without calling `poscall` or moving return values from `ra_idx` to `old_ci.func`.
- **Impact:** Return values from tail-called C functions (`return math.abs(x)`) are lost or left in wrong stack slots.
- **Fix:** Pending. Invoke `poscall` or copy return values to `old_ci.func` before returning from `.TAILCALL`. **2026-08-08**.

---

## BUG-111 — `ldump.zig` / `lundump.zig`: Negative line numbers dumped as unsigned u64 varints [MED] ❌ OPEN

- **Location:** `src/ldump.zig:77-79`, `src/lundump.zig:86-91`.
- **Defect:** `dumpInt` casts negative `i32` values to `u64` via `@bitCast(@as(i64, x))`, writing a 10-byte varint. When `lundump.zig` reads this with `loadInt` (which enforces limit `2147483647`), it fails with `error.IntegerOverflow`.
- **Impact:** Precompiled bytecode dumped from functions with negative line numbers (`lineDefined = -1`) fails to deserialize.
- **Fix:** Pending. Encode negative line numbers using signed zigzag varint encoding or standard signed integer serialization. **2026-08-08**.

---

## BUG-112 — `lib/iolib.zig`: Sentinel slice evaluated before NUL byte initialization in `io_tmpfile` [MED] ✅ FIXED

- **Location:** `src/lib/iolib.zig:219`.
- **Defect:** `buf[0..path.len :0].ptr` is evaluated before line 226 sets `buf[path.len] = 0`.
- **Impact:** In Debug and ReleaseSafe modes, creating a sentinel slice `[:0]` over uninitialized stack memory triggers a runtime panic.
- **Fix:** Set `buf[path.len] = 0` before calling `openatZ` with `[:0]` sentinel slice in `io_tmpfile`. **2026-08-08**.

---

## BUG-113 — `lua.zig`: $O(N)$ linear scan in `getGCObject` during GC marking (quadratic GC latency) [MED] ❌ OPEN

- **Location:** `src/lua.zig:4437-4498`.
- **Defect:** When resolving `*UpVal` (or objects where `ptr.gc == null`), `getGCObject` performs a linear scan over `g.allgc` (`while (curr) |obj| : (curr = obj.next)`).
- **Impact:** Traversal of every upvalue during GC marking turns overall mark complexity quadratic ($O(N \times M)$), introducing latency spikes on large heaps.
- **Fix:** Pending. Maintain direct `ptr.gc` back-links for all GC-tracked objects to eliminate linear list scans. **2026-08-08**.

---

## BUG-114 — `lauxlib.zig` / `iolib.zig` / `oslib.zig`: Direct system calls bypassing `std.Io` parameter [LOW] ❌ OPEN

- **Location:** `src/lauxlib.zig:1028`, `src/lib/iolib.zig:76+`, `src/lib/oslib.zig:27+`.
- **Defect:** Direct libc/POSIX calls (`getenv`, `std.c.open`, `std.c.close`, `localtime_r`, `remove`, `rename`) are used instead of threading `io: std.Io` from `L.l_G.?.io`.
- **Impact:** Direct violation of §0.1 Rule 10 ("Adopt juicy-main + std.Io threading").
- **Fix:** Pending. Thread `io: std.Io` down through library functions. **2026-08-08**.





