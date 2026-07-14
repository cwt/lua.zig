---
type: lessons_learned
title: Bug Report — luazig (Zig port of Lua 5.5.1)
description: Working document tracking known defects in the luazig codebase, ordered by priority.
tags: [bugs, defects, tracking]
timestamp: 2026-07-14T16:10:00Z
---

# Bug Report — luazig (Zig port of Lua 5.5.1)

> Working document tracking known defects in the `luazig` codebase. Bugs are
> numbered `BUG-001` … in priority order. Severity reflects runtime impact.
> Each entry records the location, the defect, the impact, and the recommended fix.
> Last updated: 2026-07-14 (BUG-040–042 appended after Phase H.3 — io buffering + read("*n")).

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
- **Defect:** In Lua 5.5.1 (`lua/lvm.c`), `OP_VARARGPREP` calls `luaT_adjustvarargs(L, ci, cl->p)`, which inspects `p->is_vararg` to shift fixed arguments, build the vararg table (`vatab`), and rebase `ci`. The port's `VARARGPREP` is a no-op and no `luaT_adjustvarargs`/`luaT_getvarargs` exist, so a function declared with `...` never receives its extra arguments packaged correctly. `OP_VARARG`/`OP_GETVARG` in the port also ignore the vararg table and `is_vararg`.
- **Impact:** Any program that defines or calls a vararg function (`function f(a, ...) ... end` or `f(...)`) receives wrong argument values or `nil`s where varargs should be. Not triggered by the current test suite (64/64 pass), but is incorrect behavior for ordinary Lua programs.
- **Note:** Related Phase C fix (rev 41) correctly decodes `isVarArg` from the loaded prototype flag byte, so `p->is_vararg` is now accurate; this bug is purely in the VM execution path (Phase D).
- **Recommended fix:** Port `luaT_adjustvarargs` and `luaT_getvarargs` from `lua/ltm.c`/`lua/ldo.c`, wire `OP_VARARGPREP` to `luaT_adjustvarargs`, and make `OP_VARARG`/`OP_GETVARG` consult the built vararg table via `ci`.
- **Fix (rev 43):** Ported `luaT_adjustvarargs`, `luaT_getvarargs`, and `luaT_getvararg` into `src/ltm.zig`. `OP_VARARGPREP` now calls `luaT_adjustvarargs` (records `ci.nextraargs` for the `PF_VAHID` case, or builds the `{...}`/`n` vararg table for `PF_VATAB`); `OP_VARARG` calls `luaT_getvarargs` (honoring the multi-return `C==0` path with stack growth, and the `k`-flag vararg-table variant); `OP_GETVARG` calls `luaT_getvararg` (single index / `"n"` count). Added `lua_Proto.flag: u8` and `CallInfo.nextraargs: i32`. Design note: the port now matches the C reference by relocating the call frame for hidden varargs via `buildhiddenargs` (`src/ltm.zig`), which shifts `ci.func`/`ci.base` up by `totalargs + 1` so the function's register window does not overlap the hidden vararg area. Every return path must therefore restore `ci.func -= (nextraargs + nparams1)`. Verified by new test "BUG-036: VM vararg execution" loading `tests/test_vararg.luac` (`local function f(a,b,...) return ... end; return f(1,2,3,4,5)` → `3`), cross-checked against the Lua 5.5.1 reference binary. **65/65 tests pass, zero leaks.**
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
- **Fix (rev 65, 2026-07-14):** The `.c` branch now mirrors the `.lua` branch: it moves the called function and its arguments *down* to the frame base (`L.stack[ci.func + k] = L.stack[ra_idx + k]`), sets `ci.base = ci.func + 1` and `L.top = ci.func + b`, so the C function reads its args via `ci.base` and its results land exactly at `func_idx` (where the caller — e.g. `lua_pcall` — expects them). The PF_VAHID undo (`ci.func -= nextraargs + nparams1`) is preserved. Verified by the H.2 and BUG-038 tests against the Lua 5.5.1 reference: `return os.execute('true')` → `true`, `return os.execute('false')` → `nil`. **88/88 tests pass, stable across repeated runs (seed-independent).**

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
- **Impact:** [MED] Any program reading numbers from a file via `read("*n")` (the canonical idiom in `lua/testes/iotest.lua`) failed or produced wrong results — blocking full drop-in-replacement compatibility with the Lua 5.5.1 test suite.
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
- **Impact:** [MED] `os.exit(code)` always runs `lua_close`, which is unnecessary for a fast exit and violates the Lua 5.5.1 API contract. `os.exit(code, false)` is silently ignored — cleanup still happens, contradicting the caller's explicit request.
- **Recommend fix:** Accept the optional second argument and only call `lua_close` when `lua_toboolean(L, 2) != 0`.

## BUG-044 — `lua_close` does not run `__gc`/`__close` finalizers (comment is misleading)  [MED]
- **Location:** `src/lua.zig:3324-3390` (`lua_close`); comment at `src/lib/oslib.zig:311`.
- **Defect:** The C reference's `close_state` → `luaC_freeallobjects` → `callallpendingfinalizers` runs all pending `__gc` finalizers on userdata before deallocating. The Zig port's `lua_close` just frees memory via `freeGCObject` — it never runs `__gc` or `__close` metamethods. The comment `// Run __close / __gc finalizers before terminating.` in `os_exit` is therefore wrong: no such finalization occurs.
- **Impact:** [MED] Even when `os.exit(code, true)` is called (which *should* do graceful cleanup with finalizers), the finalizers are never called. Userdata with `__gc` metamethods are simply freed without notification. This also affects any other call to `lua_close` in non-exit contexts.
- **Recommend fix:** Implement finalizer dispatch in the GC sweep phase of `lua_close` (port `callallpendingfinalizers` from `lua/lgc.c`), or at minimum run a full GC cycle that respects `__gc` before freeing.
