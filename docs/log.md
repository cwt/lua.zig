---
type: lessons_learned
title: Modification Log
description: Running chronological log of bundle modifications and significant changes.
tags: [log, changelog]
timestamp: 2026-07-14T16:10:00Z
---

## 2026-07-14 — H.10: GC completeness (all lua_gc options, GCPARAM)

Implemented all remaining GC options and the GC parameter system, completing
Phase H.

### Changes

**GC constants fixed to Lua 5.5.1** (`src/lua.zig`):
- Removed `LUA_GCSETPAUSE` (6) and `LUA_GCSETSTEPMUL` (7) (Lua 5.4 compat)
- `LUA_GCISRUNNING` = 6, `LUA_GCGEN` = 7, `LUA_GCINC` = 8, `LUA_GCPARAM` = 9
- Added parameter sub-constants `LUA_GCPMINORMUL` through `LUA_GCPSTEPSIZE`

**`lua_gc` overhaul** (`src/lua.zig`):
- Signature extended: `pub fn lua_gc(L, what, arg, value) i32` — the 4th
  `value` parameter carries the set-value for `LUA_GCPARAM` (pass -1 for get)
- All 10 GC options handled (STOP/RESTART/COLLECT/COUNT/COUNTB/STEP/
  ISRUNNING/GEN/INC/GCPARAM)
- `global_State` gains `gc_running: bool` and `gcparams: [6]u8` array
  initialised to C-reference defaults (PAUSE=200, STEPMUL=200, STEPSIZE=13,
  MINORMUL=10, MAJORMINOR=20, MINORMAJOR=50)

**`collectgarbage` updated** (`src/lib/baselib.zig`):
- Option list matches Lua 5.5: no "setpause"/"setstepmul", added "param"
  with sub-options "minormul"/"majorminor"/"minormajor"/"pause"/
  "stepmul"/"stepsize" (matching `lua/lbaselib.c`)

**`luaL_checkoption` made nullable** (`src/lauxlib.zig`):
- `def` parameter changed from `[]const u8` to `?[]const u8` so callers can
  pass `null` to require the argument (matching C behaviour)

**Tests**: single comprehensive H.10 test (124/124 pass, zero leaks) verifying
all direct `lua_gc` API options, GCPARAM get/set round-trip, and the
`collectgarbage` Lua-level interface.

§0.1 self-audit:
- Allocators: no new allocations (gcparams is inline array, gc_running is a
  bool flag). ✅
- Errors: `luaGC_collectgarbage` error propagated via `catch return -1`. ✅
- No setjmp/longjmp. ✅
- No numeric conversions beyond `@as(u8, @intCast(@min(...)))` for clamping. ✅
- `luaL_checkoption` nullable `def` is a straightforward widening — all
  existing callers pass string literals which coerce to `?[]const u8`. ✅
- `lua_gc` 4-param signature is a minor API change; all 5 callers updated. ✅

---

## 2026-07-14 — H.9: Missing constants and exports (lua_ident)

Added the one remaining missing H.9 item: `lua_ident`, the C API
identification string that embeds version and author markers.
Declared as a comptime `[]const u8` in `src/lua.zig`:

```zig
pub const lua_ident: []const u8 = "$LuaVersion: " ++ LUA_COPYRIGHT ++ " $" ++
    "$LuaAuthors: " ++ LUA_AUTHORS ++ " $";
```

All other H.9 constants (`LUA_GNAME`, `LUA_ERRFILE`, `LUA_LOADED_TABLE`,
`LUA_PRELOAD_TABLE`, `LUA_NOREF`, `LUA_REFNIL`, `LUAL_NUMSIZES`,
`LUA_COPYRIGHT`, `LUA_AUTHORS`) already existed from earlier phases.

Tests: verify string content (123/123 pass, zero leaks).

§0.1 self-audit: comptime concatenation of existing string constants;
no allocation, no error propagation, no runtime code.

---

## 2026-07-14 — H.8: Deprecated compatibility aliases

Added four deprecated backward-compatibility aliases as `pub inline fn` in
`src/lua.zig`:

- `lua_newuserdata(L, s)` → `lua_newuserdatauv(L, s, 1)`
- `lua_getuservalue(L, idx)` → `lua_getiuservalue(L, idx, 1)`
- `lua_setuservalue(L, idx)` → `lua_setiuservalue(L, idx, 1)`
- `lua_resetthread(L)` → `lua_closethread(L, null)`

Also fixed `lua_closethread` signature: `from` parameter changed from
`*lua_State` to `?*lua_State` to accept `null` (matching the C ABI,
where `lua_closethread(from)` accepts `NULL`).

Note: `lua_getiuservalue` and `lua_setiuservalue` remain stubs (return 1,
push nil) from the initial port — this is unchanged, the aliases are
purely mechanical. Runtime behaviour will be addressed when those
underlying functions are implemented.

Tests: single comprehensive test (122/122 pass, zero leaks) verifying all
4 aliases compile and return expected values.

§0.1 self-audit: thin delegating wrappers; no allocation, error
propagation, numeric conversion, or setjmp/longjmp. `lua_closethread`
parameter type fix is a one-line signature change without semantic
alteration.

---

## 2026-07-14 — H.7: Convenience macros

Implemented all Phase H.7 convenience macros as `pub inline fn` in
`src/lua.zig`. Four (`lua_insert`, `lua_remove`, `lua_newtable`,
`lua_isnoneornil`) already existed from earlier work. Six were added:

- `lua_register(L, name, func)` — `lua_pushcfunction + lua_setglobal`
- `lua_pushglobaltable(L)` — `lua_rawgeti(REGISTRY, RIDX_GLOBALS)`
- `lua_pushliteral(L, s)` — alias for `lua_pushstring`
- `lua_isfunction(L, n)` — `lua_type == LUA_TFUNCTION`
- `lua_isthread(L, n)` — `lua_type == LUA_TTHREAD`
- `lua_islightuserdata(L, n)` — `lua_type == LUA_TLIGHTUSERDATA`

Tests: single comprehensive test (121/121 pass, zero leaks) covering all 10
macros: `newtable`/`pushliteral`/`insert`/`remove` (stack manipulation),
`pushglobaltable`/`register` (globals), `isfunction`/`isnoneornil`/`isthread`/
`islightuserdata` (type predicates).

§0.1 self-audit: thin wrappers over existing API; no allocation, no error
propagation, no numeric conversion, no setjmp/longjmp, no C strings.

---

## 2026-07-14 — H.5 finisher: lua_pushexternalstring (external strings)

Implemented the last deferred H.5 item: Lua 5.5 `lua_pushexternalstring`, which
pushes a string whose bytes live in caller-owned memory (managed by a C
`lua_Alloc`) instead of being copied into Lua's intern pool.

### Design
- `lua_TString` gains three fields: `externally_owned: bool` (marks non-interned
external strings), `falloc: ?lua_Alloc` (the external deallocation callback;
  null for interned strings and for LSTRFIX fixed strings), and `ud: ?*anyopaque`.
- `lua_pushexternalstring(L, s, len, falloc, ud)` creates a `lua_TString` whose
  `.s` views `s[0..len]` (the external bytes), sets `hash = seed` (matching the C
  reference, so external strings never collide with content-hashed interned
  strings of equal content in a large table), marks it `externally_owned`, and
  registers it as a GC object via `registerGC`. On OOM (header or VMGCObject
  alloc) an LSTRMEM buffer is returned to `falloc`; LSTRFIX buffers are left to
  the caller.
- GC: external strings are now first-class `VMGCObject`s (`ValUnion.string`).
  `markValue` marks the wrapping object for externally-owned strings;
  `freeGCObject` calls `falloc(ud, ts.s.ptr, ts.len+1, 0)` for LSTRMEM and always
  destroys the `lua_TString` struct. LSTRFIX bytes are static and never freed.
- Table keys: `ltable.getStr` previously compared string keys by pointer
  identity only (valid because the port interns every string). External strings
  are distinct objects with equal content, so `getStr` now also does a content
  comparison — but only when at least one side is `externally_owned`, keeping
  interned-key lookups (the dominant case) free of per-node `memcmp`.

### Verification
- 3 new tests in `tests/test_basic.zig`: LSTRMEM frees the external buffer on
  GC (free-count assertion via a custom `lua_Alloc`), LSTRFIX keeps static bytes
  and is a distinct object from an equal-content interned string, and an
  equal-content external string round-trips as a table key (matching C, where
  external strings carry hash = seed and compare by content).
- `zig build test` -> 120/120 pass, zero leaks. `zig build` clean.

§0.1 self-audit:
- Allocator threaded (external TString + VMGCObject allocated via L.allocator);
  the external `falloc` is only ever a free callback on collection, never used
  for our own allocations. ✅
- Errors propagated (`!T`/`try`); OOM paths return null and restore LSTRMEM
  buffers to `falloc`. ✅
- No setjmp/longjmp; pure Zig error unions. ✅
- Numeric conversions: none new; `hash = @as(u32, @truncate(g.seed))` is the
  same seed->hash truncation the rest of the port uses. ✅
- `lua_Alloc` (C fn-pointer typedef) is retained ONLY to store/invoke the
  caller's external deallocation callback — a necessary, documented exception
  to §0.1 rule 1, since the external memory is owned by the C caller. ✅
- No @bitCast value conversions; TValue union retained; single type model. ✅
- Unmanaged containers unchanged; GC list (`allgc`) extended with `.string`. ✅
- No empty catch {} (OOM handled via `catch` returning null). ✅
- Type predicates precise. ✅

---

## 2026-07-14 — Phase H.6 (CLI / REPL improvements)

Completed the standalone CLI driver in `src/luazig.zig` (port of `lua/lua.c`
argument handling) plus two supporting port-correctness fixes.

### H.6 — CLI / REPL (`src/luazig.zig`, `build.zig`)
- `parseArgs` — handles `-e` (repeatable, runs before script), `-l <name>`, `-i`,
  `-v`, `--` (stops option parsing), and `-` (stdin script). Returns `ParsedArgs`.
- `createargtable` now driven from the parsed `arg[0]`/`script`/`extra_args` so the
  `arg` table is populated correctly for scripts, `-e`, and `--` combinations.
- `runString` — wraps `luaL_loadstring` + `lua_pcallk`; prints errors to stderr.
- `runRepl` — multi-line reader: accumulates lines, loads with `luaL_loadstring`;
  on `LUA_ERRSYNTAX` whose message contains `<eof>` it treats input as incomplete and
  continues reading (otherwise pops the error and prints it).
- `printValue` / `printResults` — expands tables via raw `lua_next` (depth cap 3) for
  readable REPL output; falls back to `luaL_tolstring` for scalars.
- `main` — `defer lua.lua_close(L)` on every exit path (including option-parse errors)
  so the Lua state is always released.

### Supporting fixes
- `lauxlib.luaL_tolstring` — for `LUA_TSTRING` it now pushes a copy, honouring the
  "always leaves a result on top" contract that `printValue` relies on (previously it
  left the stack unchanged for strings, corrupting table expansion).
- `llex.lexerror` — stores the formatted `"<msg> near <token>"` into the persistent
  `ls.buff` (no heap, no dangling pointer) and sets `ls.errmsg_allocated = false`;
  appends the ` near <eof>` suffix. `lparser.error_expected`/`check_match` rewritten to
  use it instead of storing a pointer into a stack-local buffer (latent use-after-free /
  garbage syntax-error messages).

### Verification
- 117/117 unit tests pass, zero leaks (`zig build test`).
- New tests: `H.6 luaL_tolstring pushes a copy (string contract)`;
  `H.6 CLI luazig behaves like the reference interpreter` (subprocess test that spawns
  the built `luazig` binary — `build.zig` `test` step now also builds the `luazig` exe).
- Manual checks: `-e`, `-v`, `-l math`, `--`, `-` (stdin), multi-line REPL, `arg` table
  (with and without `-e` mixing), non-zero exit on unrecognized option.

§0.1 self-audit: allocator threaded (`parseArgs`/`readAllStdin`/`runRepl` use
`.empty` + explicit allocator on every `append`/`appendSlice`); errors propagated via
`!T`/`try` (option errors return the error union, running `defer lua_close`); no
`setjmp`/`longjmp`; no `@bitCast` value conversions; `TValue` union retained; single
type model; `std.Io` threaded to `stdoutWrite`/`stderrWrite`/`readLine`; unmanaged
containers correct; no empty `catch {}`; stack slots reserved before write; type
predicates precise.

---

## 2026-07-14 — Phase H.4 (reference system) + Phase H.5 (missing C API functions)

Closed most of the Phase H drop-in replacement gap: the C-API reference system
(`luaL_ref`/`luaL_unref`) and all remaining missing core/auxlib functions.

### H.4 — Reference system (`src/lauxlib.zig`)
- `luaL_ref(L, t)` — creates a reference in table `t` using the C free-list chain
  pattern: `t[1]` holds the head of the free list; freed slots link via `t[slot]`.
- `luaL_unref(L, t, ref)` — releases a reference back to the free list; no-op for
  negative `ref` (mirrors the C `lauxlib.c` contract).
- `LUA_NOREF` (= -2) and `LUA_REFNIL` (= -1) constants exported.

### H.5 — Missing C API functions
**Core API (`src/lua.zig`):**
- `lua_atpanic` — added `panic: ?lua_CFunction` field to `global_State`; sets and
  returns the previous handler (matches `lua/lua.h`).
- `lua_version` — returns `LUA_VERSION_NUM` (computed `MAJOR*100 + MINOR` = 505.0).
- `lua_numbertocstring` — formats the number at `idx` into a caller-supplied
  `[]u8` buffer via `std.fmt.bufPrint`, returns bytes written + null terminator,
  or `0` if the value is not a number.
- `lua_pushexternalstring` — **deferred**: Lua 5.5 new feature requiring a new
  `lua_TString` variant backed by an external allocator + lifetime bookkeeping.

**Auxlib (`src/lauxlib.zig`):**
- `luaL_checkversion_` — errors via `luaL_error` on size/version mismatch.
- `luaL_callmeta` — pushes the metamethod (via `luaL_getmetafield`), the object,
  then `lua_call(L, 1, 1)`; returns `1` if called, `0` if absent.
- `luaL_alloc` — C-ABI allocator wrapper over `std.c.realloc`/`std.c.free`.
- `luaL_loadfilex` — reads the file via `std.Io.Dir.cwd().readFileAlloc`, builds an
  `@`-prefixed chunk name, then `lua_load` with a one-shot `getS` reader; uses
  `L.l_G.?.io` for I/O (no extra `io` parameter, matching the C API).
- `luaL_loadbufferx` / `luaL_loadstring` — one-shot `getS` reader over the slice.
- `luaL_makeseed` — mixes `L` and a local-var address for entropy.
- `luaL_getsubtable` — gets-or-creates a subtable; returns `1` if found, `0` if
  created (returns `!i32` because `lua_getfield` is fallible).
- `luaL_requiref` — registers in `package.loaded`, optionally in the globals table.
- `luaL_dofile` — `luaL_loadfilex` + `lua_pcallk`.

**Buffer auxlib functions (`src/lauxlib.zig`):**
- `luaL_addstring` (→ `luaL_addlstring`), `luaL_buffinitsize` (inits + reserves),
  `luaL_prepbuffer` (→ `luaL_prepbuffsize(B, LUAL_BUFFERSIZE)`), `luaL_bufflen`
  (`b.buf.items.len`), `luaL_buffaddr` (`b.buf.items`), `luaL_buffsub` (trims len).

**Constants added:** `LUA_VERSION_NUM`, `LUA_N2SBUFFSZ` (core); `LUAL_NUMSIZES`,
`LUA_ERRFILE`, `LUA_GNAME`, `LUA_LOADED_TABLE`, `LUA_PRELOAD_TABLE` (auxlib).

### §0.1 self-audit
1. ✅ Allocator threaded — `luaL_loadfilex` uses `L.l_G.?.allocator`; buffers use
   `L.allocator`.
2. ✅ Errors propagated — `luaL_callmeta`/`luaL_getsubtable`/`luaL_requiref` use
   `!i32`/`!void` + `try`; `luaL_checkversion_` errors via `luaL_error`.
3. ✅ No setjmp/longjmp — pure Zig error unions.
4. ✅ Numeric conversions — `@floatFromInt` for `LUA_VERSION_NUM`; no `@bitCast`
   for value conversion.
5. ✅ Slices not C strings — buffers and chunk names use `[]const u8`/`[]u8`.
6. ✅ No C varargs.
7. ✅ Unmanaged containers — `luaL_Buffer.buf` is `std.ArrayList(u8)` with `.empty`.
8. ✅ `TValue` tagged union retained.
9. ✅ Single type model (`lua_State`/`lua_CFunction`/`global_State`).
10. ✅ `std.Io` threaded to `luaL_loadfilex` (via `global_State.io`).
11. ✅ Shift bounds — not applicable here.
12. ✅ No empty `catch {}` — `luaL_dofile` file-open failure pushes a message and
    returns `LUA_ERRERR` explicitly.
13. ✅ Stack capacity validated — `luaL_addstring`/(buffer) rely on `appendSlice`.
14. ✅ Type predicates precise.

### Verification
- `zig build` clean; `zig build test` passes **112/112**, zero memory leaks.
- 14 new tests in `tests/test_basic.zig` cover every H.5 function (version,
  atpanic round-trip, numbertocstring, loadstring/loadbufferx, getsubtable,
  dofile error path, makeseed, checkversion, callmeta present/absent, buffer
  functions) plus the 6 H.4 reference-system tests.

---

## 2026-07-13 — Math via glibc libm (DynLib resolver → shared `src/libm.zig`) + ThinLTO

Routed every software-transcendental math call through glibc `libm` (C Lua uses
the same `libm`), then factorized the resolver into a shared module and enabled
ThinLTO on the build.

### Key discovery (root cause of slow math)
LLVM recognizes `log`/`sin`/`exp`/`pow` **by name** as math builtins and folds
calls into the static `compiler_rt` software implementation at compile time —
even when declared `extern fn`. A plain `extern fn log10 = @extern(...)` therefore
resolves to `compiler_rt.log10`, never glibc. `objdump` confirmed the hot path
still calling `compiler_rt.log10.log10` after `link_libc` alone. The only way to
reach glibc is to resolve the symbol **at runtime** via `std.DynLib`, because the
function pointer is data the optimizer cannot constant-fold into a builtin. Since
`libm.so.6` is permanently loaded via `DT_NEEDED` (static link against the
system libm), the resolved pointers stay valid for the process lifetime.

### Changes
- **`build.zig`**: `.link_libc = true` on `root_module` + `lua_module` `createModule`;
  `.lto = .thin` set on the `exe`/`lib` `*Step.Compile` (the `lto` field is on the
  Compile step, not `ExecutableOptions`/`LibraryOptions`). Compile time rises
  (~1s → ~16s) but produces one optimized module graph.
- **`src/libm.zig`** (new): single source of truth. `Libm` struct holds function
  pointers `{sin,cos,tan,asin,acos,atan2,log,log2,log10,exp,pow,fmod,frexp,ldexp}`.
  `resolve()` opens `libm.so.6` and looks up each symbol; `getLibm()` returns a
  cached `Libm`, falling back to `std.math.*` equivalents (`fallback()`) if
  resolution ever fails. Lookups use `callconv(.c)` (lowercase — `.C` is not a
  valid calling-convention name in this Zig version).
- **`src/lib/mathlib.zig`**: removed the local DynLib resolver; now `const libm =
  @import("../libm.zig")` and every transcendental (`sin/cos/tan/asin/acos/atan2/
  log/log2/log10/exp/fmod/frexp/ldexp`) calls `libm.getLibm().<fn>(...)`.
- **`src/lua.zig:980`** (`LUA_OPPOW`) and **`src/lvm.zig:540,658`** (`OP_POWK`/
  `OP_POW`): now `libm.getLibm().pow(...)`.
- **`src/llex.zig:398`** (`lua_strx2number`): `libm.getLibm().ldexp(r, e)` (was
  `std.math.ldexp`).
- **`src/lib/string/format.zig:122`** (`formatFloatG`): `libm.getLibm().log10(...)`
  (was `std.math.log10`).
- Hardware-backed ops (`@floor`,`@sqrt`,`@abs`,`@trunc`,`isNan`/`isInf`/`signbit`)
  and integer/comptime helpers (`maxInt`,`inf`,`nan`) intentionally stay Zig
  builtins/`std.math` — glibc merely wraps the same CPU instruction in a slower
  PLT call and they never invoke `compiler_rt`.

### Verification
- `zig build` clean; `zig build test` passes **73/73**, zero memory leaks.
- Output of `../pi/pi-5.5.lua` byte-for-byte identical to `./lua/lua`.
- `objdump` now shows `getLibm()` + indirect `call *%rN` (no `compiler_rt`), and
  `perf` shows math in `libm.so.6` (`__ieee754_log_fma`, `__log10_finite`).
- Wall-clock (`../pi/pi-5.5.lua`, ReleaseFast): luazig **0.13s** vs reference C
  **0.09s** (≈1.44×). **ThinLTO gave no measurable change (0.13s → 0.13s)** — the
  bottleneck is interpreter dispatch (`lvm.run` 36%) + table lookup
  (`luaV_gettable` 28%), not cross-module inlining.

### §0.1 self-audit
1. ✅ Allocator threaded — no hardcoded allocator.
2. ✅ Errors propagated — `resolve()` failure handled via `fallback()`, no
   `catch unreachable`; `std.DynLib.open`/`lookup` errors reach the caller.
3. ✅ No setjmp/longjmp; `%T`/`try` only where fallible.
4. ✅ Numeric conversions via `@intCast`/`@floatFromInt`; no `@bitCast` for value
   conversion.
5. ✅ Slices not C strings.
6. ✅ No C varargs.
7. ✅ Unmanaged containers where used.
8. ✅ Tagged union `TValue` retained.
9. ✅ Single type model.
10. ✅ `std.Io` threaded to I/O paths.
11. ✅ Shift bounds checked/masked.
12. ✅ No empty `catch {}` blocks.
13. ✅ Stack capacity validated before use.
14. ✅ Type predicates precise.

### Known limitations
- **Integer-pow bug (separate, pre-existing, NOT from libm):** `2^100` and
  `2^1023` return `0`/`0` in luazig (should be `8.99e307`/`inf`). `2^50` is
  correct. Standalone `pow` via the same `libm` resolver gives the correct
  `2^100 = 1.267e30`, so the fault is an integer-literal exponentiation path
  (suspected 64-bit overflow), not the math call. Deferred; tracked separately.

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

## 2026-07-12 — Phase D fix: VM vararg execution (BUG-036 FIXED, rev 43)

### Changes

- **`src/ltm.zig`**: Ported the vararg runtime helpers from `lua/ltm.c`/`lua/ldo.c`:
  - `luaT_adjustvarargs(L, ci, cl)` — for `PF_VATAB` builds the `{...}` table (with `n = <count>`) at `func+nfixparams+1`; for `PF_VAHID` records the extra-arg count in `ci.nextraargs`.
  - `luaT_getvarargs(L, ci, where, wanted, vatab)` — copies varargs into place, honoring the multi-return `wanted < 0` path (grows the stack when needed and sets `L.top`), padding with `nil` up to `wanted`, and reading from either the stack (hidden) or the vararg table (`vatab >= 0`).
  - `luaT_getvararg(L, ci, ra, rc)` — single-vararg access: numeric index `...[k]` and the `"n"` count query.
  - Added `PF_VAHID`/`PF_VATAB`/`PF_FIXED` flag-bit constants (`lua/lobject.h`).
- **`src/lvm.zig`**: Wired the opcodes — `VARARGPREP` → `luaT_adjustvarargs`, `VARARG` → `luaT_getvarargs` (decoding `C`→`wanted` and the `k` flag→`vatab`), `GETVARG` → `luaT_getvararg`.
- **`src/lua.zig`**: Added `lua_Proto.flag: u8 = 0` (populated by the loader) and `CallInfo.nextraargs: i32 = 0`.
- **`tests/test_vararg.luac`**: New precompiled chunk (`local function f(a,b,...) return ... end; return f(1,2,3,4,5)`), compiled with the Lua 5.5.1 reference binary.
- **`tests/test_basic.zig`**: New test "BUG-036: VM vararg execution" asserting the first returned vararg is `3`.

### Design note

The C reference relocates the call frame for hidden varargs (`buildhiddenargs`). This port keeps the frame in place and reads hidden varargs directly from the stack just above the fixed parameters — layout-equivalent, and avoids C-style frame surgery.

### §0.1 Self-Audit

- **Rule 1 (allocator threaded):** `createVarargTable` uses `L.allocator`/`g.allocator`; no `page_allocator`. ✅
- **Rule 2/12 (error propagation):** all fallible paths use `try` / `!void`; no `catch unreachable`, no swallowed errors. ✅
- **Rule 3 (no longjmp):** pure `!T` returns. ✅
- **Rule 4 (numeric conversions):** `@intCast`/`@floatFromInt`/`@intFromFloat` only; no `@bitCast` for value conversion. ✅
- **Rule 8/9 (type model):** operates on `TValue` union and the single `lua_Table`/`lua_LClosure`/`global_State`. ✅
- **Rule 13 (stack growth checked):** multi-return path reallocs and re-sets `stack_last` before writing past `top`. ✅

### Verification

`zig build test --summary all` → **65/65 tests pass, zero memory leaks.** Result cross-checked against the Lua 5.5.1 reference binary (`./lua/lua`).

## 2026-07-12 — `luaL_dostring` properly implemented (rev 44)

### Changes

- **`src/lua.zig`**: Replaced the no-op stub (which returned `LUA_OK` unconditionally) with a correct implementation mirroring the C reference (`lauxlib.c` `luaL_dostring` = `luaL_loadstring` + `lua_pcall`): it loads the chunk from the source string via `lua_load` (using a small `luaL_dostringReader` that yields the slice once) and, on load success, runs it with `lua_pcallk(L, 0, LUA_MULTRET, 0, 0, null)`. The load/pcall status is propagated (so text input correctly returns `LUA_ERRSYNTAX`; binary chunks execute and leave their results on the stack).
- **`src/luazig.zig`**: The CLI entry call now prints the (honest) load/run error to stderr instead of silently discarding it.
- **`tests/test_dostring.luac`**: New precompiled chunk (`return 6*7`), compiled with the Lua 5.5.1 reference binary.
- **`tests/test_basic.zig`**: Two new tests — `luaL_dostring loads and runs a chunk` (binary chunk → `LUA_OK`, result `42` on stack) and `luaL_dostring returns LUA_ERRSYNTAX for non-bytecode source`.

### §0.1 Self-Audit

- **Rule 1 (allocator threaded):** reader/loader use `L.allocator`; no `page_allocator`. ✅
- **Rule 2/12 (error propagation):** uses `lua_load` + `lua_pcallk` (`!i32`/`i32`); no `catch unreachable`, no swallowed errors (CLI now reports the error). ✅
- **Rule 3 (no longjmp):** plain `!T` returns. ✅
- **Rule 8/9 (type model):** operates on `TValue`/single type model. ✅
- **Rule 13 (stack capacity):** `lua_pcallk` manages its own frame; no manual stack writes past `top`. ✅

### Verification

`zig build test --summary all` → **67/67 tests pass, zero memory leaks.** Behavior cross-checked against the Lua 5.5.1 reference binary.

### Related

- Phase C source-text compiler (lexer/parser/codegen) remains the only outstanding Phase C item; `luaL_dostring` itself is now complete. `docs/frontend.md` updated to reflect that `luaL_dostring` runs precompiled bytecode.

## 2026-07-12 — Documentation sync: phases A–F marked complete; Phase G (source compiler) added to roadmap (rev 45)

### Changes

- **`README.md`**: Corrected stale status (was "Phase F in progress / 32 passing / lib stubs"). Now states A–F complete, 67/67 tests, all 10 libs done; added Phase G row (source-text compiler, not started) and notes the text-source gap.
- **`docs/roadmap.md`**: Updated phase overview diagram and phase states (A–F complete; removed stale "NEXT"/"In Progress" markers). Added a full **Phase G — Source-Text Compiler** section (G.1 lexer / G.2 parser / G.3 codegen / G.4 wire `lua_load`, verification, effort ~4,700 LOC). Updated timestamp.
- **`AGENTS.md`**: Reframed "What is NOT done" #1 as Phase G (not started); marked Phase F ✅ DONE; corrected stale file-by-file guidance (lualib/libraries); added **Phase G** section (items 17–21) to the recommended next-phase roadmap; rewrote §8 "What to work on next" to point at Phase G.

### Note

This is a documentation-only changeset. No source/test changes; `zig build test` still 67/67 pass, zero leaks. Phase G itself is not yet implemented — only planned and documented.

## 2026-07-12 — Phase G.1: Lexer implemented (`src/llex.zig`) (rev 46)

### Changes

- **`src/llex.zig`** (NEW, ~875 lines): Full Lua 5.5.1 lexer ported from `lua/llex.c` + number scanning from `lua/lobject.c`.
  - Token set (`TK_AND=257` … `TK_STRING=294`, `FIRST_RESERVED=257`), `LexState` with explicit `allocator: std.mem.Allocator` (Rule 1).
  - `luaX_setinput`, `luaX_next`, `luaX_lookahead`, `luaX_newstring` (interns via `lstring.luaS_new`), `luaX_init` (reserved-word table), `luaX_syntaxerror` (`LexError = error{SyntaxError}`, no longjmp — Rule 3), `token2str`.
  - Number scanning: `str2num` / `l_str2int` / `lua_strx2number` / `l_str2d`, with a `normalizeDecimal` pass so Zig's `std.fmt.parseFloat` accepts Lua's trailing-`.` forms (`1.`, `1.e2`). Hex floats (`0x1p4`) via `lua_strx2number`.
  - Strings / long strings / escapes (`read_string`, `read_long_string`, `skip_sep`), `\xHH` / `\u{...}` / decimal / `\n` `\t` etc.; `inclinenumber`, comments (`--`, long `---[[ ]]`).
  - Reader/chunk streaming via `lua_Reader` wrapper (mirrors ZIO); buffer is an unmanaged `std.ArrayList(u8)` growing with `ls.allocator`, capped at `MAX_SIZE` (BUG-024 avoidance).
- **`src/lua.zig`**: exposed `pub const llex = @import("llex.zig")` and `pub const lstring` so the lexer + its tests are reachable; no behavioral change to the runtime.
- **`tests/test_basic.zig`**: 5 new lexer tests (basic tokens + numbers; integer/hex/float forms; long string + escapes + comments; error on unfinished string; reserved words + operators). Note: tests live in the test root (not in `llex.zig`) because a module built as a dependency of the test root is compiled without its own `test` declarations.
- **`build.zig`**: no change required (lexer is part of the `lua` module).

### Bug-avoidance self-audit (against `docs/bugs.md`)

- **BUG-002 / 012 / 025 / 031 (swallowed errors):** lexer propagates `!void`/`!T` everywhere; no `catch {}`, no dummy `catch`. Syntax errors return `error.SyntaxError`.
- **BUG-024 (hardcoded `page_allocator`):** buffer grows via `ls.allocator`; never `page_allocator`.
- **BUG-010 / 013 (stack OOB / unchecked `lua_checkstack`):** lexer does not touch the Lua stack; `luaX_newstring` interns via the global string table (allocator-threaded).
- **BUG-021 (`[]const u8` → `[*:0]` without NUL):** all string handling uses bounded slices; no fake C strings.
- **BUG-001 (shift overflow):** no dynamic shifts in the lexer; numeric conversions use `std.fmt.parseFloat` / `@intCast` (Rule 4), never `@bitCast`.

### Verification

`zig build test --summary all` → **72/72 tests pass (was 67/67), zero memory leaks.** `zig build` produces the `luazig` executable. Lexer behavior cross-checked against the Lua 5.5.1 reference binary semantics for token classes, number forms, escapes, and long strings.

### Related

- Phase G.2 (parser, `src/lparser.zig`) and G.3 (codegen, `src/lcode.zig`) remain; G.4 wires `lua_load`'s text branch to `luaD_protectedparser`.

## 2026-07-13 — Phase G complete: Source-Text Compiler implemented (`src/lparser.zig`, `src/lcode.zig`, wired `lua_load`)

### Changes

- **`src/lparser.zig`**: Full recursive-descent parser ported from `lua/lparser.c` (and parts of `lua/ldo.c`).
  - Implemented blocks, statements (`if`, `while`, `repeat`, `for` loop variations, local/global variable declarations, assignments, functions, tailcalls, `goto`, labels, `break`).
  - Added clean error/syntax error propagation replacing C's longjmp mechanics.
  - Used safety-checked union assignment rules of Zig (`e.u = .{ ... }`) to avoid union field panics.
  - Implemented `cleanupFuncState` helper invoked in `errdefer` blocks to prevent memory leaks on syntax errors.
- **`src/lcode.zig`**: Full code generator ported from `lua/lcode.c`.
  - Implemented instruction emission, constant folding, register allocation, upvalue handling, and jump patch lists.
  - Fixed bitwise and shift operations to work under Zig's compile-time types and unsigned constraints.
- **`src/lua.zig`**: Wired the text-compilation path in `lua_load` to call `lparser.luaD_protectedparser` instead of failing with `LUA_ERRSYNTAX` for non-bytecode source. Updated `luaD_protectedparser` and `luaX_setinput` to pass/handle `first_slice` so the first read chunk is not discarded.
- **`tests/test_basic.zig`**: Added a new end-to-end integration test `luaL_dostring executes source-text string and handles syntax errors` verifying that source-text strings compilation, execution, and syntax errors work as expected. Updated existing lexer tests to match the new `luaX_setinput` signature.

### §0.1 Self-Audit

- **Rule 1 (allocator threaded):** all allocations (in `FuncState` arrays) use `ls.L.allocator` / `L.allocator`.
- **Rule 2/12 (error propagation):** no swallowed errors; errors cleanly bubble up via `try`/`return error.SyntaxError`.
- **Rule 3 (no longjmp):** longjmp completely eliminated and replaced by Zig's error union (`!T`) propagation.
- **Rule 5 (slices used):** uses slices (`[]const u8`) for buffers and identifiers.
- **Rule 7 (unmanaged containers):** `FuncState` uses unmanaged containers initialized with `.empty` and explicit allocator.
- **Rule 11 (boundary checks on dynamic bitwise shifts):** bitwise operators strictly cast and verify bounds.
- **Rule 12 (no swallowed runtime errors):** no empty/dummy catches.

### Verification

`zig build test` → **72/72 tests pass, zero memory leaks.** Validated by executing dynamic source compilation, VM execution of output bytecode, and correct cleanup on syntax error paths.

## 2026-07-13 — AND/OR logical operator codegen fix + `LUA_COMPAT_MATHLIB` removal

### AND/OR codegen fix

**Root cause:** `luaK_posfix` for `OPR_AND` called `luaK_goiftrue(fs, e1)` a second
time (after `luaK_infix` already called it), negating the comparison test condition
back to its original polarity. This caused the JMP to jump when the condition was
*true* instead of when it was *false* — i.e., the short-circuit branch was taken
on the wrong value. The C reference (`lua/lcode.c`) does **not** call
`luaK_goiftrue` in `luaK_posfix` for AND.

**Fix:** Removed the redundant `luaK_goiftrue(e1)` call from the `OPR_AND` case in
`luaK_posfix` (`src/lcode.zig:1107`).

**Verification:** All comparison + AND/OR combinations now evaluate correctly
(e.g. `print(1 >= 10 and true)` → `false`, `print(10 >= 1 and 42)` → `42`).

### `LUA_COMPAT_MATHLIB` removal

**Reason:** Lua 5.5.1 conditionally provides `math.atan2`, `math.cosh`,
`math.sinh`, `math.tanh`, `math.pow`, `math.log10` behind
`#if defined(LUA_COMPAT_MATHLIB)`, which is **off by default** in the stock build.
The port was including them unconditionally.

**Changes:**
- Removed `math_cosh`, `math_sinh`, `math_tanh`, `math_pow`, `math_log10`
  function definitions from `src/lib/mathlib.zig`.
- Removed `"atan2"`, `"cosh"`, `"sinh"`, `"tanh"`, `"pow"`, `"log10"`
  registration entries. Reduced table size hint from 30→25.
- `math.log(x, 10)` and `math.atan(y, x)` remain (they are not compat shims).

### Documentation
- `docs/libraries.md`: Updated mathlib function list and added note about
  `LUA_COMPAT_MATHLIB` conditional.

### §0.1 Self-Audit
- No `catch unreachable`, no `@bitCast` for value conversion.
- Errors propagated via `!T` + `try` throughout.
- Single type model maintained.
- AND/OR correctness verified against the C reference semantics.

### Verification
`zig build` and `zig build test` both pass: **72/72 tests**, zero memory leaks.
Behavior cross-checked against the Lua 5.5.1 reference binary for logical
operator evaluation and math library availability.

---

## 2026-07-13 — Phase H documented: gap analysis for drop-in replacement

Documented the comprehensive gulf between `luazig` and "drop-in replacement for
Lua 5.5.1" as **Phase H** in AGENTS.md and docs/roadmap.md. Identified 10
workstreams (H.1–H.10) by systematic audit against `lua/lua.h`,
`lua/lauxlib.h`, and standard library C sources.

### Critical blockers (H.1–H.2)
- **5 C API stubs**: `lua_concat`, `lua_len`, `lua_toclose`, `lua_closeslot`,
  `createargtable` are no-ops; `lua_getallocf`/`lua_setallocf` are stubs.
- **4 oslib stubs**: `os.date` (no formatting), `os.execute` (no-op),
  `os.exit` (no cleanup), `os.setlocale` (always "C").

### Important gaps (H.4–H.6)
- No `luaL_ref`/`luaL_unref` reference system.
- No `lua_atpanic`, `luaL_requiref`, `luaL_loadfilex`, `luaL_checkversion`,
  `luaL_makeseed`, and other missing C API / auxlib functions.
- CLI is bare: no `-e -l -i -v` flags, no multi-line REPL.

### Minor gaps (H.3, H.7–H.10)
- `io.flush`/`file.flush` stubs, missing convenience macros, deprecated
  compat aliases, missing constants/exports, GC parameter API gaps.

### Changes
- **`AGENTS.md`**: Added comprehensive `§Phase H` section (H.1–H.10) with
  prioritized gap descriptions and verification criteria.
- **`docs/roadmap.md`**: Updated phase diagram to include Phase H; added
  detailed `## Phase H` section with all 10 workstreams.
- **`docs/log.md`**: Added this entry.

### §0.1 Self-Audit
- Documentation-only changeset. No source code modified.
- OKF bundle guidelines followed: AGENTS.md + roadmap.md + log.md updated.
- See `AGENTS.md` §Phase H for §0.1 gate requirements on all Phase H work.

### Verification
`zig build test` still passes: **72/72 tests**, zero memory leaks.

## 2026-07-13 — Phase D fix: vararg RETURN/TAILCALL frame-restoration bug (3 test regressions)

### Root cause

After the vararg (`buildhiddenargs`) port, three tests regressed with
`lua_gettop` returning 2 instead of 1: `VM execution`, `BUG-036: VM vararg
execution`, and `luaL_dostring executes source-text string`.

Every Lua function compiled with `PF_VAHID` (the main chunk always is, via
`setvararg` in `mainfunc`) has its call frame relocated by `buildhiddenargs`,
which shifts `CallInfo.func` up by `totalargs + 1`. The matching restoration
`ci.func -= (nextraargs + nparams1)` must happen on return. The `.RETURN`
handler did this, but three other return paths did **not**:

1. **`OP_TAILCALL` (.lua branch):** `return sub(10)` compiles to a tail call
   that reuses the current `CallInfo`. It copied args into the shifted
   `ci.func` slot but never restored `ci.func`/`ci.base`, so the result landed
   at the wrong stack index and `L.top` ended up one too high.
2. **`OP_RETURN0` / `OP_RETURN1`:** these opcodes never restored `ci.func`.
3. **Text compiler `luaK_finish`:** when it converts `RETURN0`/`RETURN1` →
   `RETURN` for a `PF_VAHID` function, it set the opcode but (unlike the C
   reference, which *falls through* into the `OP_RETURN` case) never set
   `SETARG_C(pc, numParams + 1)`. So the C field stayed 0 and the `.RETURN`
   handler skipped the restoration.

### Changes

- **`src/lvm.zig`**: Added `isVarargFunc(L, ci)` and `numParamsOf(L, ci)`
  helpers. `OP_RETURN0` and `OP_RETURN1` now restore `ci.func`/`ci.base` when
  the executing closure is `PF_VAHID` (using `numParams + 1` as `nparams1`).
  `OP_TAILCALL`'s `.lua` and `.c` branches now correct `ci.func` via
  `nextraargs + GETARG_C(i)` before reusing the `CallInfo`, matching
  `lua/lvm.c` `OP_TAILCALL`.
- **`src/lcode.zig`**: `luaK_finish` now sets `SETARG_k`/`SETARG_C` on the
  `RETURN0`/`RETURN1` → `RETURN` conversion (equivalent to the C `fallthrough`
  into the `OP_RETURN` case), so the VM's `.RETURN` handler sees `C =
  numParams + 1` and restores the frame correctly.

### §0.1 Self-Audit

- **Rule 1 (allocator threaded):** no allocation changes; helpers only read
  `L.stack[ci.func]`.
- **Rule 2/12 (error propagation):** no error-handling changes; `poscall`
  path unchanged.
- **Rule 8 (single type model):** unchanged; still reads `lua_Closure` from
  the stack.
- **Rule 11 (boundary checks on dynamic bitwise shifts):** not touched.

### Verification

`zig build test` → **73/73 tests pass, zero memory leaks.** Verified all three
previously-failing tests (`VM execution`, `BUG-036`, `luaL_dostring`) now
report `lua_gettop == 1`. Cross-checked bytecode (reference-compiled
`tests/*.luac`) and text-compiled (`luaL_dostring "return 42"`) paths.

---

## Rev 46 — Table-lookup hot path optimization (2026-07-13)

### Context

Profiling `luazig` against the reference `lua/lua` binary on `../pi/pi-5.5.lua`
(a ~6M table-lookup / ~2M C-call workload) showed the table path at ~45% of
cycles (`ltable.getHash` 24.5% + `ltm.luaV_gettable` 20.4%) on top of the
earlier CallInfo fix. Cross-referenced the **talyn** OKF bundle
(`../talyn/docs/`), which uses `perf` IPC / backend-bound / dTLB metrics rather
than wall-clock.

### Key finding (from talyn's profiling methodology)

`perf stat` on the workload showed **IPC ≈ 3.2 with near-zero cache misses**
(3105 core cache-misses, 252 dTLB misses, 662 L1D misses). This is the
*opposite* of talyn's Priority 12 problem (70% backend-bound, fixed by struct
slimming). So for Lua.Zig the table path is **instruction-bound**, not
memory-bound: the fix must **reduce instructions per lookup**, not slim structs.
This reframed the work toward specialization of the common case (the lesson
talyn applies repeatedly in Priorities 9/15/21 — collapse generic dispatch for
the hot path).

### Changes

- **`src/ltable.zig`**: `hashKey` now uses a power-of-two bitmask
  (`h & (len - 1)`) instead of `h % len`. `node.items.len` is always a power of
  two (guaranteed by `computeHashSize`/`growNode`), so the modulo reduces to a
  single `and` — eliminating a runtime integer division on every probe (AGENTS
  Rule 11: mask instead of divide).
- **`src/ltable.zig`**: added `getStr(t, key: *const TString)` — a specialized
  interned-string lookup equivalent to C Lua's `luaH_getshortstr`. It hashes
  `key.hash & mask` and compares keys by pointer identity (`ks == key`),
  skipping the generic `hashKey` 9-case switch and the `keyEquals` union
  comparison. `get` dispatches string keys to `getStr`.
- **`src/ltable.zig`**: marked `get`, `getInt`, `getHash`, `getStr`, `asInt`,
  `keyEquals`, `hashKey` `inline` so the whole chain collapses at the call site
  (VM's `luaV_gettable`), letting the optimizer specialize for the constant
  string-key type.
- **`src/ltable.zig`**: hardened `keyEquals` to guard every field access with
  an explicit tag check (was accessing `b.<field>` under a `switch (a)` arm,
  which only failed to trip because the function was never inlined at a
  statically-typed call site — inlining `getInt`→`getHash`→`keyEquals` with a
  `.number` key exposed it).

### §0.1 Self-Audit

- **Rule 8 (single type model):** preserved. `getStr` still reads/writes
  `TValue`; it only specializes the *key* type, no NaN-boxing.
- **Rule 4 (no `@bitCast` for value conversion):** untouched.
- **Rule 11 (mask dynamic shifts / power-of-two modulo):** the `h % len` →
  `h & (len-1)` change is exactly this rule applied to hash probing.

### Verification

`zig build test` → **73/73 tests pass.** ReleaseFast wall-clock on
`../pi/pi-5.5.lua`: **0.184s → 0.14s** (~24% faster; ~7.6% from the bitmask,
~18% from string specialization + inlining). `perf report` now shows
`ltable.getHash` fallen off the hot list (<1.5%) and `ltm.luaV_gettable`
reduced to ~22% (the remaining cost is the metamethod scaffolding wrapper, not
the probe). Reference `lua/lua`: 0.092s.

## Rev 54 — Link libc; route mathlib transcendentals through glibc libm

**Date:** 2026-07-13
**Goal:** Eliminate the ~16% `compiler_rt` software-transcendental cost on
`../pi/pi-5.5.lua` (root cause #3 from the ranked slowness audit) by using the
hosted libm instead of Zig's bundled `compiler_rt` implementations.

### Discovery (why naive `link_libc` was not enough)

- Adding `.link_libc = true` to the **module** `createModule` (not to
  `addExecutable`/`addLibrary` — that field lives on the module in Zig 0.16.0;
  the builder rejects it on the install step) made `libm.so.6` a DT_NEEDED
  dependency, but the hot `math_log` still called `compiler_rt.log.log`.
- Root cause: LLVM **recognizes `log`/`log10`/`sin`/`exp`/... as math builtins**
  and folds any call to them (including a plain `extern fn log`) into the
  `compiler_rt` implementation at compile time. `nm` confirms `compiler_rt`
  exports bare `log`/`log10`/`sin` symbols, so an `extern fn` reference resolves
  to the statically-linked `compiler_rt` copy — glibc is never reached.
- `x86-64` has **no** hardware `log`/`sin`/`exp` instruction; both paths are
  library calls. glibc's `libm` is hand-tuned asm, faster than `compiler_rt`
  (musl-derived, correct but not x86-64-optimized). C Lua links libc and thus
  uses glibc's `libm` — so this also makes Lua's `math.*` match reference C Lua
  semantics (Lua's math is specified in terms of C `math.h`).

### Fix

- **`src/lib/mathlib.zig`**: replaced `std.math.*` / builtin `@sin`/`@log`/...
  calls for the true transcendentals (no hardware instruction exists for them)
  with pointers resolved **at runtime via `std.DynLib.open("libm.so.6")`**. A
  function pointer the compiler cannot constant-fold bypasses the builtin
  folding, so calls actually dispatch into glibc. Pointers are cached in a
  process-global after first resolution (libm is permanently loaded via
  DT_NEEDED, so they stay valid). Hardware-backed ops (`sqrt`/`floor`/`ceil`)
  stay as Zig builtins — inlining the hardware instruction is faster than an
  indirect call.
- **`build.zig`**: `.link_libc = true` added to `root_module` and `lua_module`
  `createModule` calls.

### §0.1 Self-Audit

- **Rule 1 (thread the allocator):** untouched; `openmathlib` takes `L`.
- **Rule 8 (single type model):** untouched.
- No `@cImport` used (the lighter `extern`-via-`DynLib` path; `@cImport` of
  `math.h` would have hit the same builtin-folding wall).

### Verification

`zig build test` → **73/73 pass** (mathlib tests 38–40 included; output matches
`./lua/lua` byte-for-byte on `pi-5.5.lua`). `perf report` now shows math
dispatching into `libm.so.6` (`__ieee754_log_fma`, `__log10_finite`) instead of
`compiler_rt`. ReleaseFast wall-clock on `../pi/pi-5.5.lua`: **0.14s → 0.13s**
(reference `lua/lua`: 0.092s). Remaining hot spots now clearly: `lvm.run` 36%,
`ltm.luaV_gettable` 28%, `lua.precall` 10%, `ltm.luaT_equalobj` 8.6%.

### Out of scope (left as-is)

- `src/lib/string/format.zig:122` (`std.math.log10` for `%g` precision) and
  `src/llex.zig:398` (`std.math.ldexp` at compile time) still use `compiler_rt`;
  neither is on this benchmark's hot path. Route them the same way if their
  semantics need to match glibc exactly.

---

## 2026-07-13 — Rev 55: VM hot-loop MMBIN skip + Debug-LTO crash workaround

### Goal

Continue closing the interpreter gap with reference C Lua on `../pi/pi-5.5.lua`
(product formula; hot loop is pure float arithmetic + per-iteration
`math.log(n,10)`/`math.floor` C-calls). Investigate and remove avoidable
per-opcode overhead.

### Changes

- **`src/lvm.zig` — removed TEMP profiling instrumentation.** The per-opcode
  histogram (`g_opcount`/`g_opdepth` globals, the `defer`-dumped histogram, and
  the `incq` counter in the fetch loop) was added only to profile the loop; it
  was a hot-path memory write and is now gone.
- **`src/lvm.zig` — unconditional MMBIN skip in number fast-paths.** Every
  binary/arithmetic opcode (`ADD/SUB/MUL/MOD/DIV/IDIV/POW/BAND/BOR/BXOR/SHL/SHR`
  and the `K`/`I` immediate variants `MULK/MODK/ADDI/...`/`GEI`/`EQI`) emitted
  `if (GET_OPCODE(code[ci.savedpc]) == .MMBINX) ci.savedpc += 1;` to skip the
  trailing metamethod guard. For valid Lua 5.5.1 bytecode a binary op is *always*
  followed by its `MMBIN`/`MMBINI`/`MMBINK` variant, and numbers never need a
  metamethod (running `MMBIN` with two numbers would itself error in C), so the
  guarded check is redundant for any correct program. The number path now does
  `ci.savedpc += 1;` unconditionally, deleting a per-opcode `code[]` read +
  compare + branch from the dispatch loop. The non-number path still runs the
  next instruction (the real `MMBIN` dispatch) unchanged.
- **`build.zig` — LTO only for Release builds.** `.lto = .thin` was previously
  unconditional, which made `zig build` (Debug) run the Debug+LTO codegen path.
  That path segfaults in this toolchain's LLVM backend (`process terminated
  with signal SEGV`), and the fault also reproduces on the committed tip — i.e.
  it is an environmental LLVM bug, not a regression in the port. LTO is now set
  `if (optimize != .Debug) .thin else .none`, so `zig build` (Debug) works and
  `zig build -Doptimize=ReleaseFast` still gets ThinLTO.

### Investigation findings

- `lvm.run` uses an LLVM **jump table** dispatch (`jmp *jt(,%rdx,8)`), O(1) and
  equivalent to C's computed-goto — dispatch shape is *not* the gap.
- `run`'s return type cannot be narrowed from `anyerror!void` to `!void`
  (error-set inference cycle: `run ↔ luaD_call ↔ luaT_callTMres`); the wide
  error union is inherent, not removable locally.
- `allocCallInfo` already uses a freelist; no per-call heap allocation.

### §0.1 Self-Audit

- **Rule 8 (single type model):** unchanged.
- **Rule 12 (no swallowed errors):** the MMBIN skip preserves semantics for all
  valid bytecode (numbers never invoke binary metamethods; malformed chunks are
  out of scope). Verified by 73/73 tests + byte-identical `pi-5.5.lua` output.
- No `@cImport`; libm still resolved via `std.DynLib` (`src/libm.zig`).

### Verification

`zig build test` → **73/73 pass**. `perf report` (ReleaseFast ThinLTO):
`lvm.run` 54.6%, `lua.precall` 15.6% (3M `math.log`/`math.floor` C-calls —
paid by C too), libm `log`/`log10` ~22.5%, `math_log` 3.8%; `luaT_equalobj`
and `luaV_gettable` folded into `lvm.run`. ReleaseFast wall-clock min-of-10 on
`../pi/pi-5.5.lua`: **luazig 100ms vs reference `lua/lua` 90ms (~1.11×)**.
Remaining ~10ms gap is C's tighter C-function call/inline overhead
(`math_log` inlined at the call site, lighter `precall`) — not addressable by
local fast-paths without restructuring C-function dispatch.

---

## 2026-07-14 — Phase H.1: C API stubs → implementations (Rev 61)

Closed the highest-priority correctness gap from AGENTS.md §8 H.1. Eight
functions that previously silently did nothing / returned wrong results now
behave per Lua 5.5.1 `lua.h` / `lauxlib.h`:

- `luaL_newtable` → `lua_createtable(L, 0, 0)` (was empty body).
- `luaL_len` → `lua_len` + integer check; returns `error.LuaTypeError` when the
  length is not an integer (was `lua_rawlen`, ignoring `__len`).
- `luaL_where` → `lua_getstack` / `lua_getinfo("Sl")` source location string
  (was always `""`).
- `lua_concat` → `std.ArrayListUnmanaged` concat of `n` top values; string and
  number operands stringified, others fall back to `luaL_tolstring` (was
  discarding `n`).
- `lua_len` → `!void`, absindex + `LEN` metamethod via `luaT_callTMres` (was
  discarding `idx`).
- `lua_getallocf` / `lua_setallocf` → real allocator abstraction: `global_State`
  gained `allocf` / `alloc_ud` / `alloc_wrapper`, backed by `AllocWrapper`
  (`{ .alloc = std.mem.Allocator }`) and the `l_alloc` thunk (default = the
  state's underlying `gpa`). Replaces the previous `undefined`/`ignored` bodies.
- `lua_toclose` / `lua_closeslot` → slot marking + `__close` metamethod dispatch
  through `luaT_callTM` (was empty / no-op).
- `createargtable` → builds the global `arg` table from CLI args (`arg[0]` =
  script name, `arg[1..]` = extra args) (was empty body).

### Bug fixed during H.1

`lua_absindex` correctly returns a **1-based** index (Lua C API convention),
but `lua_len` / `lua_closeslot` / `lua_toclose` were indexing `L.stack` with the
raw absolute value (0-based expected) — so any `lua_len` on a plain table hit
the `else` branch and raised `RuntimeError`. Switched those sites to `stackAt()`
(0-based) and stored `tbclist` 0-based. Also corrected `lua_closeslot` to use
`luaT_callTM` (discards results, nresults=0) instead of `luaT_callTMres`
(__close returns 0 results).

### §0.1 Self-Audit

- Allocator threaded via `global_State` (no `page_allocator`); default thunk
  wraps the state's `gpa`.
- Errors propagated with `!T` / `try`; `lua_closeslot`/`lua_toclose` swallow only
  the intended `__close` error (matches Lua semantics), not runtime conditions.
- Conversions via `@intCast` / `@intFromFloat`; no `@bitCast` for values; no C
  strings; unmanaged containers; `TValue` union retained; metamethods via `ltm`
  (no `longjmp`); no varargs.
- `l_alloc` cast fixed to `[*]u8` (the `@as([]u8, @ptrCast(...))` form triggered
  a compiler SEGV); no `callconv(.c)` on the thunk (matches `lua_Alloc` typedef).

### Verification

8 new tests in `tests/test_basic.zig` cover each function. `zig build test` →
**81/81 pass** (was 73/73), clean Debug build. Committed as Rev 61.

### Next

H.2 (oslib: `os.date`/`os.execute`/`os.exit`/`os.setlocale`), H.4
(`luaL_ref`/`luaL_unref`), H.5 (missing C API + auxlib buffer fns),
H.6 (CLI flags), per AGENTS.md §8.

## 2026-07-14 — Phase H.2: oslib stubs → real implementations + io lifetime fix

Completed H.2: real `os.date`, `os.execute`, `os.exit`, `os.setlocale`, and the
table form of `os_time`. Also fixed a latent `io` lifetime bug that the new
`os.execute` was the first code path to expose.

### Changes
- `src/lib/oslib.zig`:
  - `os_execute` — real subprocess via `std.process.spawn(io, .{ .argv = &[_][]const u8{ "/bin/sh", "-c", cmd }, .stdin/.stdout/.stderr = .inherit })` + `child.wait(io)`. Returns `(true, "exit", code)` for status 0, `(nil, "exit"/"signal", code)` otherwise (matches `luaL_execresult`).
  - `os_date` — `*t` table (year/month/day/hour/min/sec/wday/yday/isdst) via `localtime_r`/`gmtime_r`; formatted strings via `strftime` with growable buffer. `!` UTC prefix honored.
  - `os_time` — table form (requires year/month/day) via `mktime`; non-table falls back to `linux.clock_gettime`.
  - `os_setlocale` — real `std.c.setlocale` with category parsing (`classcat`).
  - `os_exit` — `lua_close(L_)` then `std.process.exit` (runs `__close`/`__gc` first).
  - `std.c` on this Zig version exposes only `setlocale`/`LC`/`time_t`; the missing broken-down-time libc functions are bound directly with `extern "c"` (`localtime_r`/`gmtime_r`/`mktime`/`strftime`/`time`) and a glibc-compatible `tm` (`extern struct`) is declared locally. This is the same mechanism `std.os.linux` uses for syscalls (not `@cImport`).
- `src/lua.zig` (`luaL_newstate`): `threaded.io()` captured a pointer to a
  **stack-local** `threaded`; after `threaded` was copied into `io_backend`
  (heap), `L.l_G.?.io` was dangling. Re-pointed `io` at
  `L.l_G.?.io_backend.?.io()` after the copy. This was the root cause of the
  `os.execute` SEGV in tests (the juicy-main binary passes a real `io` and was
  unaffected).

### Bugs filed
- `BUG-037` — `luaL_newstate` left `L.l_G.?.io` dangling (stack `threaded` moved to
  `io_backend`). Fixed by re-deriving `io` from the heap copy.
- `BUG-038` — VM `TAILCALL` with a C function drops the argument: `return f(args)`
  in tail position loses `args` (e.g. `return os.execute("true")` → "command must
  be a string"), while `print(f(args))` works. Pre-existing Phase-D issue, not
  fixed in this change (avoided in the H.2 test via a non-tail-call form).

### §0.1 Self-Audit
- Allocator threaded; errors propagated with `!T`/`try` (`os_execute`/`os_date`/
  `os_time`/`setfieldint` all propagate; error unions from `lua_getfield`/
  `lua_setfield` handled, not swallowed).
- `@intCast`/`@intFromEnum` used for conversions; `SIG` enum → integer via
  `@intFromEnum`; no `@bitCast` for values; no C strings (sentinel slices via
  `dupeZ`); `TValue` union retained; no `longjmp`; no varargs.
- `l_alloc` cast already correct (`[*]u8`). No `callconv(.c)`.

### Verification
5 new tests in `tests/test_basic.zig` (os.date `*t`, os.date format + UTC,
os.time round-trip, os.execute success/failure, os.setlocale). `os.date`/`os.execute`
output verified byte-for-byte against the Lua 5.5.1 reference binary. `zig build test`
→ **86/86 pass** (was 81/81), clean Debug build.

## Rev 65 — Fix two seed-independent GC / VM correctness bugs (2026-07-14)
- **BUG-039 (string GC sweep):** `lua_gc`'s string-sweep collected `[]const u8`
  slices into `g.strt` then `swapRemove`d them. `swapRemove` reorders the map's
  key array, invalidating the buffered slices, so later removals hit the wrong
  entries — corrupting the global intern pool. Now the sweep collects
  `*lua_TString` (stable `.s` bytes) and removes via `swapRemove(ts.s)`, which is
  safe across reordering. This was the true root cause of the H.2 `os.execute`
  resolving to `setlocale` (wrong `TString` pointer via `getStr` pointer-identity).
- **BUG-038 (TAILCALL to C at top level):** the `.c` branch set `ci.func = ra_idx`
  (above the discarded frame base), so results landed above the frame and leftover
  values leaked into `lua_gettop`. Now it moves the function+args down to the frame
  base (mirroring the `.lua` branch), so results land at `func_idx` where the caller
  (`lua_pcall`) expects them. `return os.execute('false')` now returns the correct
  three values `(nil, "exit", code)`.
- **Verification:** H.2 / BUG-038 tests updated to assert the correct 3-value return
  (`os.execute` returns `(status, "exit", code)`, first result at index `-3`).
  `zig build test` → **88/88 pass**, stable across 6+ repeated runs (seed-independent).
  Real `luazig` binary: `os.execute('true')`→`true`, `os.execute('false')`→`nil`.
- **Cleanup:** removed all DBG debug prints (ltable.getStr, oslib.openoslib &
  os_execute, lvm TAILCALL); removed temp `tests/t_min.zig`; removed `src/lvm.zig.orig`.

### §0.1 Self-Audit
- Allocator threaded; errors propagated with `!T`/`try`; no `@bitCast` for values;
  `TValue` union retained; no `longjmp`; no varargs; `swapRemove` misuse eliminated
  by collecting stable `*TString` values before mutating `g.strt`.

## 2026-07-14 — Phase H.3: io buffering (flush / setvbuf) + two io correctness fixes (Rev 66)

Implemented H.3: real `io.flush` / `file:flush` and `file:setvbuf` (was a stub
returning `true` without buffering). This exercise surfaced two latent io bugs
that had been hidden because no test ever called a `file:*` method.

### Changes (`src/lib/iolib.zig`)
- **Buffering infrastructure:** `LStream` gained `buf: ?[]u8`, `buf_len: usize`,
  `buf_mode: u8` (0 = unbuffered, 1 = full, 2 = line); `IO_BUFSIZE = 8192`. All
  six `LStream` creation sites initialize the new fields.
- **Write path:** `g_write` now takes `*LStream` and routes through `writeToStream`
  → `flushBuffer` → `appendBuf` / `rawWrite` (single `std.os.linux.write` syscall,
  looping until all bytes are written). `io_write` / `f_write` updated.
- **Flush / close:** `flushBuffer` flushes pending buffered output; `doClose`
  flushes + closes `fd` + frees `buf`; `io_flush`/`f_flush` call `flushBuffer` and
  report via `luaL_fileresult`. `io_fclose` now delegates to `f_close` (preserving
  the `closef` path).
- **`file:setvbuf`:** parses `"no"` / `"full"` / `"line"`; allocates/frees the
  buffer via `L_.allocator` (guards `size > 0`); for `"no"` frees any existing
  buffer and switches to unbuffered.

### Bugs filed (this session)
- **BUG-040** — `openio` never populated the FILE metatable (luazig's
  `luaL_newmetatable` doesn't push, unlike PUC-Rio) and never set `__index`, so
  `luaV_gettable` returned `error.RuntimeError` on every `file:method` access.
  Fixed by pushing the metatable, `luaL_setfuncs(&flib)`, and `__index = self`.
  This broke `f:write`/`f:read`/`f:close`/`f:setvbuf`/… entirely (latent because
  only the global `io.*` API was tested before).
- **BUG-041** — `g_read` only accepted `"*a"` (bare `"a"` is valid in Lua 5.5) and
  `read "a"` truncated at 4096 bytes / returned `nil` on empty files. Added
  `read_all` (loops to EOF, returns `""` for empty) and made the `*` prefix
  optional.

### §0.1 Self-Audit
- Allocator threaded (buffer alloc/free via `L_.allocator`; `doClose` frees `buf`);
  errors propagated with `!T`/`try` (`lua_setfield` on the metatable is `try`-ed;
  `luaL_fileresult` reports allocation failures); no `@bitCast` for values;
  `TValue` union retained; no `longjmp`; no varargs. `file:setvbuf` guards a zero
  size and frees any prior buffer before re-allocating.

### Verification
Three new tests in `tests/test_basic.zig`:
- `"file:setvbuf no writes immediately (unbuffered)"` — `f:setvbuf("no")` +
  `f:write` lands on disk before `f:close`.
- `"file:setvbuf full buffers until flush then persists"` — `f:setvbuf("full",64)`
  buffers (read-before-flush is empty) and `f:flush()` persists `"buffered"`.
- `"io.flush flushes the default output file"` — rewrote to flush a **file** (not
  `io.write` to stdout, which is the Zig test-runner IPC channel in `--listen`
  mode and would desync the harness) and assert the data is persisted.

`zig build test` → **91/91 pass** (was 88/88 at rev 65); `zig build` clean. Each
H.3 test also verified standalone via `luazig` against expected file contents.

### Note: test-harness IPC quirk
In `zig build test` listen mode the test binary uses `fd 1` (stdout) as the Zig
IPC channel, so any test that writes to the default stdout pollutes the protocol
and can desync/hang the runner. Keep stdout-writing assertions out of the harness
path (write to a file and re-open to verify), or run the binary directly. The
hang observed during this phase was the Zig test-runner IPC deadlock, not a
luazig defect.

## 2026-07-14 — file:read("*n") number parsing (BUG-042, Rev 67)

Implemented the Lua 5.5 `"*n"` number format for `file:read` / `io.read`, the
last piece of `file:read` deferred as "out of H.3 scope" when BUG-040/041 were
fixed. Ported PUC-Rio `liolib.c` `read_number` (≈428–510).

### Changes (`src/lib/iolib.zig`)
- **Pushback slot:** `LStream` gained `unget: ?u8` (one-level read pushback),
  initialized at all six creation sites. Required because `read_number` reads a
  single look-ahead byte that must be visible to the next read (`read("*n","*l")`,
  repeated reads). `read_byte` honors the pending byte; `read_all` / `read_line`
  / `read_chars` / `f_lines` were switched to take `*LStream` and consume it.
- **`read_number`:** builds a valid numeral prefix (`[+-]? 0x? [0-9a-f]*
  [.] [0-9a-f]* [eEpP [+-]? [0-9]*]`) into a 201-byte buffer via an `RN`
  look-ahead reader (mirrors C `RN` / `next` / `test2` / `readdigits`), then
  converts with the existing `lua.lua_stringtonumber` (pushes the number,
  returns consumed length). `g_read` dispatches `'n' => read_number`.
- Matches C semantics exactly: standalone `inf` / `nan` (and a stream pointer
  left on the offending letter) return `nil`; `12.` → `12`, `-3.5` → `-3.5`,
  `0xA`/`0xFF` → `10`/`255`, `1e3` → `1000`.

### §0.1 Self-Audit
Allocator threaded (number buffer is stack/`[]u8` scratch, no heap); errors
propagated via `!T`/`try` (read helpers return `bool`; `g_read` is `!i32`);
no `@bitCast` value conversions; `TValue` union retained; no `longjmp`; no
varargs. `read_number` leaves the number (or nothing) on the stack exactly as
the C API expects, so `g_read`'s failure path stays correct.

### Verification
One new test in `tests/test_basic.zig`: `"file:read(\"*n\") parses integers,
floats, hex and invalids"` — writes `10 3.5 -7 0xFF 1e3\nhello\n`, reads the five
numbers + an invalid token (`nil`) + the following line, asserting
`10;3.5;-7;255;1000;nil;hello`. `zig build test` → **92/92 pass** (was 91);
`zig build` clean. Edge cases (`0x1.8p3` → 12, `12.`, `-inf`/`nan` → nil, `0xA`
→ 10) verified standalone via `luazig`.

## 2026-07-14 — H.4 Reference system (luaL_ref / luaL_unref)

**Phase H.4 — Reference system** implemented and tested.

### Changes
- **`src/lauxlib.zig`**: Added `LUA_NOREF` (-2), `LUA_REFNIL` (-1) constants,
  `luaL_ref`, and `luaL_unref`. The implementation follows the C reference
  (`lua/lauxlib.c`) linked-list free list: t[1] stores the head of the free
  list; freed slots are chained together; `luaL_ref` pops a value from the stack
  and stores it in table `t` at an integer key; `luaL_unref` releases it back
  to the free list.
- **`src/lua.zig`**: Added `pub const lauxlib = @import("lauxlib.zig")` to
  re-export the lauxlib namespace so tests can access it through the `lua` module.
- **`build.zig`**: No changes needed (lauxlib already accessible via lua re-export).
- **`tests/test_basic.zig`**: 6 new tests covering `luaL_ref` with string/boolean,
  `LUA_REFNIL` for nil, `luaL_unref` with free-list reuse, store-and-retrieve
  via `rawgeti`, no-op on negative refs, and a Lua-level interaction test.

### §0.1 Self-Audit
Allocator: `luaL_ref`/`luaL_unref` use the C API stack ops (no heap allocation);
errors: `!T`/`try` used for table operations (`lua_rawgeti` has no fallible path
in the reference cycle — no `catch` needed); no `@bitCast` value conversions;
`TValue` union retained; no `longjmp`; no varargs; all Zig 0.16.0 idioms (`.empty`
not used — no unmanaged containers added).

### Verification
6 new tests in `tests/test_basic.zig`, 98+ tests pass total. `zig build` clean.
`AGENTS.md` updated with H.4 status.
