---
type: project_priority
title: Code Organization — `lua.zig` Breakdown & Deduplication Plan
description: src/lua.zig is a 6253-line monolith packing seven C reference modules (lapi/ldo/lgc/lstate/ldebug/lobject + headers); verified code duplication (two number parsers, 7x CallInfo-unwind loop, 41 bufPrint-idiom sites, etc.). Two-phase plan: Phase A dedupe (6 commits), Phase B mirror-the-C-file-layout breakdown into 6 new modules + a slim hub. Pure refactoring — zero semantic change, gated by the full test battery.
tags:
  - refactoring
  - code-organization
  - dedupe
  - lua.zig
  - roadmap
timestamp: 2026-09-10T23:55:00Z
status: draft
sources:
  - src/lua.zig
  - src/llex.zig
  - src/ltm.zig
  - src/lparser.zig
  - src/lauxlib.zig
  - docs/performance.md
---

# Code Organization — `lua.zig` Breakdown & Deduplication

## Why

- `src/lua.zig` is **6253 lines** (~21% of all project LOC) and packs **seven**
  C reference modules into one file: `lapi.c` + `ldo.c` + `lgc.c` +
  `lstate.c` + `ldebug.c` + `lobject.c` (messages & number parsing) + the
  header types (`lobject.h`/`lstate.h`/`lapi.h`). The project convention
  (AGENTS.md §1) is that every other module already mirrors one C file
  (`lvm.zig`↔`lvm.c`, `lparser.zig`↔`lparser.c`, …); `lua.zig` is the one
  exception.
- Duplication has accumulated in the monolith (verified 2026-09-10, see
  below). The repo has hit this failure mode before: `src/lstate.zig` was
  deleted once for carrying a stale duplicate.
- **Design principle (binding for every Phase A/B commit):** the C
  reference is the oracle for *semantics* only — which strings are
  numbers, which errors fire, which bytes of bytecode. *Structure and
  mechanism* are designed for Zig (AGENTS.md §0.2: "diff against `lua/`
  for semantics, never for structure"). The Phase B filenames mirror the
  C layout because that layout is *also* convenient for reference-
  diffing; it is not a transcription mandate. Where C's mechanism is a
  C artifact (global locale, `strtod`, NUL-terminated strings, one
  all-purpose parser), the Zig port uses the better mechanism
  (explicit locale-as-data, `[]const u8`, allocation-free specialized
  entry points) — see the A1 design.
- Performance work (BUG-174, `performance.md`) is at its P4 plateau
  (375B / ~12.7s); the remaining RC1 lever is a deeper structural pass and
  is explicitly out of scope — this refactor must **not** change
  instruction count (perf-invariance gate below) and is about
  maintainability, not speed.

## Duplication evidence (verified 2026-09-10)

| # | Duplication | Locations | C reference |
|---|-------------|-----------|-------------|
| D1 | **Two number parsers**: the lexer has its own scanner set, and lobject-side has a separate one | `llex.zig` 326–474 (`l_str2int`, `lua_strx2number`, `l_str2d`, `str2num`) vs `lua.zig` 5744–5902 (`parseInteger`, `parseLocaleNumber`, `tonumberValue`, `isHexDigit`…) | one parser in `lobject.c`, called from `llex.c` |
| D2 | **CallInfo-unwind loop copy-pasted 7×** ("destroy CIs from `L.ci` down to the anchor") | `lua.zig`:957 (`precall`), :3856 (`lua_pcallk`), :4448 (`precover`); `ltm.zig`:143 (`luaD_call`), :186, :218, :250 (`callTM1`/`callTM2`/`callTM` helper group) | C keeps one walk in the `luaD_*` call machinery; the ltm copies are port artifacts |
| D3 | **`close_one_slot`**: two ~30-line near-identical catch blocks (the `callTM2`/`callTM1` branches differ only in call shape) | `lua.zig` 475–540 | C inlines one `aux_close` path |
| D4 | **`luaG_*` message builders**: seven functions, each ~80% identical boilerplate (fmt → `luaS_new` → push → return) | `lua.zig` 4062–4148 | C shares `luaG_typeerror`-family plumbing |
| D5 | **`var buf: [N]u8 + std.fmt.bufPrint … catch "fallback"` idiom ×41** (verified: `lua.zig` ×23, `lauxlib.zig` ×8, `lparser.zig` ×10; the other 31 `bufPrint` uses are *different* families — `try`-propagating traceback sites, `if (bufPrint)` branches, the lexer's persistent `errmsg_buf`, and `lib/string/*`'s `string.format` implementation — and are out of scope) | `lua.zig`, `lauxlib.zig`, `lparser.zig` | C uses one `buffprint` helper |
| D6 | **`LUAI_MAXCCALLS` constant defined twice** | `llimits.zig` (shared) **and** `lparser.zig:25` (local copy = 200) | single `luaconf.h` constant |
| D7 | **C-call-limit check duplicated**: `luaD_call` re-checks `nCcalls` after `precall` already enforces it | `ltm.zig` 135–141 vs `lua.zig` 936–943 | review item: confirm vs C `luaD_call` (C checks *before* the call, not after) |

## Phase A — Dedupe (six commits, each fully gated)

Order = cheap/safe wins first, riskiest last:

- **A5 → commit 1**: add one `fmtMsg` helper (the D5 idiom as a function:
  `fmtMsg(buf, fallback, comptime fmt, args)` formats into the caller's
  fixed buffer, returning `fallback` verbatim on overflow —
  behavior-identical to the original `catch` expression). Convert all 41
  D5-family sites in `lua.zig`/`lauxlib.zig`/`lparser.zig`. Mechanical;
  zero behavior change (same buffers, same fallbacks).
- **A6 → commit 2**: single-source `LUAI_MAXCCALLS` in `llimits.zig`;
  delete the `lparser.zig:25` local copy. While in `ltm.zig`, **review
  D7** against C `luaD_call` (C checks the limit before invoking the
  function; verify luazig's double-check is harmless or fix it to match C —
  a semantic fix only if it demonstrably deviates from the reference).
- **A3 → commit 3**: extract the shared close-error path out of
  `close_one_slot` (one helper taking the `tm` + `old_top` +
  `saved_err`, called from both branches). D3 gone.
- **A4 → commit 4**: extract the `luaG_*` shared tail into
  `fn luaG_err(L, fmt, args, fallback) !void` (pushes the message, sets
  the error state); the seven wrappers shrink to their unique format
  strings. D4 gone.
- **A2 → commit 5**: add `fn unwindCis(L: *lua_State, up_to: ?*CallInfo)
  void` (the D2 walk, once: destroy the chain above `up_to`, keep the
  embedded `base_ci`, set `L.ci = up_to`, clear `up_to.next`); replace
  all 7 copy-pasted sites (precover keeps its extra parent-sever line
  after the call).
- **A1 → commit 6** ✅ **DONE (2026-09-10)** — one shared,
  allocation-free number-parsing engine in `src/lobject.zig` (pulled
  forward from B3, which now only moves the `luaG_*` message wrappers
  + tostring helpers into the existing file). **Not** a mirror of C's
  `luaO_str2num`; design principle: C reference = *semantics* oracle,
  *mechanism* designed for Zig. Final shape (refined by C-vs-port
  behavior probes before implementation):
  - **One decimal-float core: `std.fmt.parseFloat`** — allocation-free,
    correctly rounded, overflow → ±inf / underflow → 0 (C `strtod`
    semantics), whole-string (trailing junk rejected). Probes showed
    it accepts **every** decimal form C accepts (`"1."`, `"5."`, `".5"`,
    `"1.e2"`, `"0x.8"`, `"0x8."`) and rejects exactly what C rejects
    (`"1e"`, `"0x"`, `"0x12p"`). It replaced **two** parsers:
    `llex.l_str2d` (which *allocated* via `normalizeDecimal` + parseFloat
    over a gpa buffer — the lexer's OOM path is gone, strictly more
    robust) and `lobject.parseLocaleNumber` (C `strtod` interop).
  - **Hex floats: the C reference `lua_strx2number` algorithm**
    (restored into `lobject.zig` as `hexFloatValue`, 30-significant-
    digit + `ldexp` exponent correction). A probe caught that
    `std.fmt.parseFloat` is **not** correctly rounded for long hex
    significands (150-digit case lands 1 ULP low vs C — upstream
    `math.lua`'s long-numerals asserts), so hex routes through the
    C-verified algorithm, decimal through `parseFloat`.
  - **Two specialized entry points** (deliberately not C's one
    all-purpose parser):
    - `lobject.parseInteger` (moved verbatim; C's u64-wrap hex-int
      overflow — `0x10000000000000000` → int 0, verified identical to
      the C reference) → `llex.str2num`'s TK_INT/TK_FLT wrapper.
      `str2num` is now allocation-free (its `alloc` parameter removed).
    - `lobject.tonumberValue(s) ?TValue` (allocation-free specialization
      of the coercion core; lvm's P4 hot path keeps its exact
      signature via `lua.zig`'s re-export) and
      `lobject.lua_stringtonumber(L, s)` (full fidelity, threads
      `L.allocator`).
  - **Locale as data**: `parseNumericFloat(gpa, s, dp)` takes the
    decimal-point char; coercion passes `localeDecimalPoint()` (both
    `'.'` and the locale point accepted — matching C's strtod +
    replace-first-'.' fallback); the lexer passes `'.'` (the reference
    lexer is locale-independent; the old `normalizeDecimal` comma
    mapping was **dead** — numeral tokens never contain `','`).
  - **C-oracle fixes pinned by the `"A1 …"` tests** (a numeric-behavior
    change is documented in the commit, not smuggled):
    1. `tonumber("3,14")` (C locale): 3.14 → **nil** (matches C; comma
       only counts as decimal point when it *is* the locale point).
    2. `tonumber("-inf")` / `"Infinity"` spellings: **nil** (the old
       guard checked the first char only; now sign-aware, case-
       insensitive prefix — C rejects all inf/nan spellings).
    3. 4000-digit strings: **±inf** instead of nil (the old 2048-byte
       cap is gone — the fast path never copies; the rare locale
       remap uses a 1024 stack buffer, gpa beyond).
    4. Lexer OOM path eliminated (no observable change; robustness).
  - **Verification**: 188/188 unit tests (6 new `"A1 …"` blocks pin the
    whole probed table), upstream suite **PASS 20 / FAIL 0**,
    `tests/pi-5.5.lua` byte-identical vs the C reference, perf gate
    **375.58B** instructions (P4 baseline 375.6B — invariant).

## Phase B — Breakdown into C-file modules (seven commits, moves-only)

Policy per commit: **pure code moves** — no renames, no semantic edits
(dedupe already happened in Phase A). Call sites are untouched by the
**re-export hub** approach below. No `build.zig` changes needed: Zig
compiles only `@import`ed files, and `src/lua.zig` (the lib root)
re-exports the new modules.

| Commit | New module | Content (C provenance, current `lua.zig` line ranges) | ~Lines |
|--------|-----------|--------------------------------------------------------|--------|
| B1 | `src/ldebug.zig` ✅ DONE (2026-09-10) | debug introspection: `lua_getstack`, `lua_sethook`/`gethook*`, `testAMode`/`testMMMode`/`filterpc`/`findsetreg`/`kname`/`upvalname`/`basicgetobjname`/`isEnv`/`rname`/`getobjname`/`funcnamefrom*`/`getfuncname`, `isLua`/`currentpc`, `luaF_getlocalname`/`luaG_findlocal`/`lua_getlocal`/`lua_setlocal`, `luaO_chunkid`, `funcinfo`/`getcurrentline`/`luaG_getfuncline`/`getbaseline`/`collectvalidlines`/`nextline`, `lua_getinfo` (`ldebug.c`). Moved verbatim; `lua.zig` re-exports the 14 pub symbols + 4 cross-module helpers (`upvalname`/`funcnamefromcall`/`getfuncname`/`getobjname` — used by the error-message builders that stay in `lua.zig` until B4/B6, exposed pub for the move). ~687 lines out of `lua.zig` (6077 → 5414). | ~700 |
| B2 | `src/lgc.zig` ✅ DONE (2026-09-10) | GC engine: `registerGC`, `getGCObject`/`getGCObjectFromValue`/`isWhiteGCObject`/`isClearedGCValue`, `mark*`/`traverseGrayObject`/`freeGCObject`, weak modes, `luaS_clearcache`, `luaC_collectgarbage`, finalizers (`rawHasFinalizer`/`metatableOf`/`callFinalizer`), GC constants (`lgc.c`). Moved 909 lines (engine + `registerGC`); the 17 `LUA_GC*` constants + `freeGCObject`/`freeAllCallInfos` re-exported (visibility bumps only; `G`, `ltable`, `ltm` made pub for cross-module access). `lua.zig` 5414 -> 4513. | ~900 |
| B4 | `src/ldo.zig` ✅ DONE (2026-09-10) | call/continuation: `precall`/`poscall` + CallInfo pool (`allocCallInfo`/`freeCallInfo`/`freeAllCallInfos`/`recycleCallInfos`), `precover`/`unroll`/`do_resume`/`completePcallRecovery`, `lua_yield*`/`lua_resume`/`lua_status`/`lua_isyieldable`, `luaG_errormsg`/`lua_error`/`lua_next`?, `finishLoad`/`lua_load` glue, `closeupvals`/`close_one_slot`/`luaF_closeupval`/`findupval` (`ldo.c` + upvalue-close). Moved 935 lines in 3 chunks (CallInfo pool + upvalue-close + precall/poscall; resume/yield block; luaG_errormsg/lua_error); 24 symbols re-exported; visibility bumps only (`closeCallFailed`/`reserveErrorStack`/`close_one_slot`/`recycleCallInfos` pub). `lua.zig` 4544 -> 3633. | ~1400 |
| B5 | `src/lstate.zig` ✅ DONE (2026-09-10) | state lifecycle: `lua_State`/`global_State` **construction** (`luaL_newstate`/`luaL_newstate_io`/`lua_newthread`/`lua_closethread`/`lua_close`), stack growth (`growStack`/`shrinkStack`/`reallocStack`/`reserveErrorStack`/`lua_checkstack`/`lua_xmove`), hooks (`luaD_hook`/`luaG_traceexec`), warning API, `createargtable` (`lstate.c`). **Note:** this filename was deleted once (stale duplicate, AGENTS.md); this time it is a *real move* of the state-lifecycle block. Moved ~510 lines in 5 scattered chunks (stack growth, newthread/closethread, warning API, newstate+createargtable, lua_close); `luaD_errerr` moved to `ldo.zig` (its C home) in the same commit; 17 symbols re-exported; visibility bumps only (`shrinkStack`/`reallocStack`/`l_alloc` made pub). `lua.zig` 3633 -> 3122. | ~800 |
| B3 | `src/lobject.zig` ✅ DONE (2026-09-10) | the remaining lobject-side value utilities: `luaG_*` message wrappers (post-A4), `tostringbuffFloat`/`luaO_tostringbuff`, `tvEqual`/`luaV_rawequalobj` (`lobject.c`). Note: A1 **creates** `lobject.zig` with the shared number-parsing engine (design principle above); B3 only moves the leftovers into the existing file. Moved 4 chunks (~310 lines: tostringbuffFloat/luaO_tostringbuff, toNumeric, luaV_rawequalobj, and the whole luaG_* message-builder family incl. luaG_runerror); 14 symbols re-exported; `snprintf` extern made pub (visibility only). `lua.zig` 3122 -> 2839. | ~400 |
| B6 | `src/lapi.zig` ✅ DONE (2026-09-10) | the C API proper: index helpers (`idxPtr`/`toAbsoluteIndex`/`lua_absindex`/`stackAt`), get/set/top, type predicates + conversions, push family, upvalue API, table/metatable API, `lua_callk`/`lua_pcallk` entry points, `atpanic`/`version`/`getallocf`/`setallocf`, `checkclosemth`/`toclose`/`closeslot`, `luaV_concat`/`lua_len`/`luaV_shift`/`numMod` (`lapi.c`). Moved 112 items (~1970 lines: the whole C API surface incl. `lua_load`/`finishLoad`/`lua_dump`/`lua_next`, `luaL_dostring`/`luaL_dostringReader`, the H.5 `lua_tostring` alias); 112 symbols re-exported; visibility bumps only (`getTable`/`numMod`/`toAbsoluteIndex` pub, `TValue.toBoolean` method pub). `lua.zig` 2839 -> 883 lines (hub territory). | ~1800 |
| B7 | hub cleanup | `src/lua.zig` left with: **core type definitions only** (`TValue`, `lua_Table`, closures, `UpVal`, `CallInfo`, `VMGCObject`, `global_State` *definition*, `lua_State` *definition*) + constants + the thin re-export tail (`pub const precall = ldo.precall; …`). The `global_State`/`lua_State` *constructors* live in B5. | ~800 |

**Import-cycle policy:** types and constants stay in the `lua.zig` hub;
each new module `@import`s the hub for types; the hub re-exports the
moved functions at its tail (the same pattern as the existing
`lauxlib` alias tail at `lua.zig:6147–6156`). This is a *hub-and-spoke*
cycle (hub ↔ each spoke), which the codebase already uses (e.g.
`lua.zig` ↔ `lvm.zig` ↔ `ltm.zig` all cycle today) and Zig 0.16
compiles without complaint. If any spoke pair needs to call each other
directly, add the re-export on the *hub* side — spokes never import
other spokes.

**Type-definition split rule:** the `global_State` *struct* and
`lua_State` *struct* stay in the hub (every module needs them); their
*initialization code* (`luaL_newstate`, `lua_newthread`, …) moves to
B5. `createProto`/`destroyProto` move with B6 or stay in the hub —
decide at commit time by which imports they need.

## Verification protocol (per commit, A and B alike)

1. `zig build` clean.
2. `zig build test --summary all` → 182/182, **0 leaks**.
3. `./run_testes.sh` → **20 PASS / 0 FAIL / 0 CRASH**.
4. Pi benchmark byte-identity: `diff <(./lua/lua ../pi/pi-5.5.lua)
   <(./zig-out/bin/luazig ../pi/pi-5.5.lua)`.
5. **Perf-invariance gate** (this is refactoring, not optimization):
   `perf stat -e instructions` must stay within noise of the P4
   baseline (**375.6B** ± ~2B). A >5B drift means the move changed code
   layout/register allocation (e.g. inlining opportunities) — stop and
   investigate before continuing.
6. Commit message: §0.1 self-audit line + "pure move, no semantic
   change" statement.

## Expected outcome

- `src/lua.zig`: 6253 → ~800 lines (hub: types + constants + re-exports).
- Six new modules of 400–1800 lines, each ≈ its C counterpart's size —
  restoring the project's "one Zig file per C file" convention.
- Deduplication: 2 number parsers → 1; 7 unwind loops → 1 helper; 41
  bufPrint idiom sites → 1 `fmtMsg`; 7 `luaG_*` boilerplate bodies → 1
  shared tail; duplicate `LUAI_MAXCCALLS` → single source. Net LOC
  roughly **−800…−1200**.
- Review surface: each future bug in, say, GC or debug-introspection
  has one 700–900-line home instead of a 6000-line kitchen sink.

## Risks

- **A1** (parser consolidation) ✅ done — it was the riskiest commit and
  the risk was real: `std.fmt.parseFloat` turned out to be 1 ULP low on
  long hex significands (caught by upstream `math.lua`), fixed by
  routing hex through the C-verified `lua_strx2number` algorithm.
  Mitigations that worked: last of Phase A, C-vs-port behavior probes
  *before* coding, pinned edge-case tests, byte-identity + perf gate.
- **B6** (`lapi`, ~1800 lines) is the biggest move; do it second-to-last
  so only the hub cleanup remains behind it.
- Moving a hot function out of the module can change inlining
  boundaries — the perf-invariance gate (§5) catches that.
- No semantic drift is acceptable: any commit that changes behavior is
  *not* a refactor commit and must be split out with its own tests
  (the D7 `luaD_call` review, if it finds a deviation, is such a case).

## Related

- [Performance](performance.md) — P4 plateau; RC1 deep pass (deferred)
- [Roadmap](roadmap.md) — phase history
- [Log](log.md) — modification log
