---
type: project_priority
title: Code Organization — `lua.zig` Breakdown & Deduplication Plan
description: src/lua.zig is a 6253-line monolith packing seven C reference modules (lapi/ldo/lgc/lstate/ldebug/lobject + headers); verified code duplication (two number parsers, 6x CallInfo-unwind loop, 58 bufPrint-idiom sites, etc.). Two-phase plan: Phase A dedupe (6 commits), Phase B mirror-the-C-file-layout breakdown into 6 new modules + a slim hub. Pure refactoring — zero semantic change, gated by the full test battery.
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
- Performance work (BUG-174, `performance.md`) is at its P4 plateau
  (375B / ~12.7s); the remaining RC1 lever is a deeper structural pass and
  is explicitly out of scope — this refactor must **not** change
  instruction count (perf-invariance gate below) and is about
  maintainability, not speed.

## Duplication evidence (verified 2026-09-10)

| # | Duplication | Locations | C reference |
|---|-------------|-----------|-------------|
| D1 | **Two number parsers**: the lexer has its own scanner set, and lobject-side has a separate one | `llex.zig` 326–474 (`l_str2int`, `lua_strx2number`, `l_str2d`, `str2num`) vs `lua.zig` 5744–5902 (`parseInteger`, `parseLocaleNumber`, `tonumberValue`, `isHexDigit`…) | one parser in `lobject.c`, called from `llex.c` |
| D2 | **CallInfo-unwind loop copy-pasted 6×** ("destroy CIs from `L.ci` down to `old_ci`") | `lua.zig`:957 (`precall`), :3856 (`lua_pcallk`), :4448 (`precover`); `ltm.zig`:143 (`luaD_call`), :186, :218 | one inline loop in `luaD_call_func`/`luaC_…` — 3 sites max, no ltm copy |
| D3 | **`close_one_slot`**: two ~30-line near-identical catch blocks (the `callTM2`/`callTM1` branches differ only in call shape) | `lua.zig` 475–540 | C inlines one `aux_close` path |
| D4 | **`luaG_*` message builders**: seven functions, each ~80% identical boilerplate (fmt → `luaS_new` → push → return) | `lua.zig` 4062–4148 | C shares `luaG_typeerror`-family plumbing |
| D5 | **`var buf: [128]u8 + std.fmt.bufPrint … catch "fallback"` idiom ×58** | `lua.zig` ×28, `lauxlib.zig` ×14, `lparser.zig` ×11, `llex.zig` ×5 | C uses one `buffprint` helper |
| D6 | **`LUAI_MAXCCALLS` constant defined twice** | `llimits.zig` (shared) **and** `lparser.zig:25` (local copy = 200) | single `luaconf.h` constant |
| D7 | **C-call-limit check duplicated**: `luaD_call` re-checks `nCcalls` after `precall` already enforces it | `ltm.zig` 135–141 vs `lua.zig` 936–943 | review item: confirm vs C `luaD_call` (C checks *before* the call, not after) |

## Phase A — Dedupe (six commits, each fully gated)

Order = cheap/safe wins first, riskiest last:

- **A5 → commit 1**: add one `fmtMsg` helper (the D5 idiom as a function:
  format into a 128-byte buffer, return the fallback literal on
  `bufPrint` error). Convert all 58 sites across the four files.
  Mechanical; zero behavior change (fallbacks are the same strings).
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
  void` (the D2 loop, once); replace all 6 copy-pasted sites.
- **A1 → commit 6** *(highest risk, last)*: consolidate the two number
  parsers. Target shape mirrors the C reference: the lobject-side parser
  (`tonumberValue` + `parseLocaleNumber` + friends, staying in `lua.zig`
  for now — it moves to `lobject.zig` in B3) becomes the **single**
  implementation, and `llex.zig`'s `str2num`/`l_str2d`/`l_str2int`
  delegate to it (C's `llex.c` calls `lobject.c`'s `luaO_str2d`).
  Delete the llex copies. Behavior must stay byte-identical for:
  integer literals, `0x`/hex-float literals, locale decimal point,
  `string.tonumber` coercion, and the `toNumeric`/`lua_tonumber` fast
  path (P4 depends on it). Extra tripwires beyond the standard battery:
  the Phase-G "compile `return 42` → Proto identical to reference"
  check and the string/number round-trip tests.

## Phase B — Breakdown into C-file modules (seven commits, moves-only)

Policy per commit: **pure code moves** — no renames, no semantic edits
(dedupe already happened in Phase A). Call sites are untouched by the
**re-export hub** approach below. No `build.zig` changes needed: Zig
compiles only `@import`ed files, and `src/lua.zig` (the lib root)
re-exports the new modules.

| Commit | New module | Content (C provenance, current `lua.zig` line ranges) | ~Lines |
|--------|-----------|--------------------------------------------------------|--------|
| B1 | `src/ldebug.zig` | debug introspection: `lua_getstack`, `lua_sethook`/`gethook*`, `testAMode`/`testMMMode`/`filterpc`/`findsetreg`/`kname`/`upvalname`/`basicgetobjname`/`isEnv`/`rname`/`getobjname`/`funcnamefrom*`/`getfuncname`, `isLua`/`currentpc`, `luaF_getlocalname`/`luaG_findlocal`/`lua_getlocal`/`lua_setlocal`, `luaO_chunkid`, `funcinfo`/`getcurrentline`/`luaG_getfuncline`/`getbaseline`/`collectvalidlines`/`nextline`, `lua_getinfo` (`ldebug.c`) | ~700 |
| B2 | `src/lgc.zig` | GC engine: `registerGC`, `getGCObject`/`getGCObjectFromValue`/`isWhiteGCObject`/`isClearedGCValue`, `mark*`/`traverseGrayObject`/`freeGCObject`, weak modes, `luaS_clearcache`, `luaC_collectgarbage`, finalizers (`rawHasFinalizer`/`metatableOf`/`callFinalizer`), GC constants (`lgc.c`) | ~900 |
| B4 | `src/ldo.zig` | call/continuation: `precall`/`poscall` + CallInfo pool (`allocCallInfo`/`freeCallInfo`/`freeAllCallInfos`/`recycleCallInfos`), `precover`/`unroll`/`do_resume`/`completePcallRecovery`, `lua_yield*`/`lua_resume`/`lua_status`/`lua_isyieldable`, `luaG_errormsg`/`lua_error`/`lua_next`?, `finishLoad`/`lua_load` glue, `closeupvals`/`close_one_slot`/`luaF_closeupval`/`findupval` (`ldo.c` + upvalue-close) | ~1400 |
| B5 | `src/lstate.zig` | state lifecycle: `lua_State`/`global_State` **construction** (`luaL_newstate`/`luaL_newstate_io`/`lua_newthread`/`lua_closethread`/`lua_close`), stack growth (`growStack`/`shrinkStack`/`reallocStack`/`reserveErrorStack`/`lua_checkstack`/`lua_xmove`), hooks (`luaD_hook`/`luaG_traceexec`), warning API, `createargtable` (`lstate.c`). **Note:** this filename was deleted once (stale duplicate, AGENTS.md); this time it is a *real move* of the state-lifecycle block. | ~800 |
| B3 | `src/lobject.zig` | lobject-side value utilities: the `luaG_*` message wrappers (post-A4), the consolidated number parsers (post-A1), `tostringbuffFloat`/`luaO_tostringbuff`, `toNumeric`, `tvEqual`/`luaV_rawequalobj` (`lobject.c`) | ~400 |
| B6 | `src/lapi.zig` | the C API proper: index helpers (`idxPtr`/`toAbsoluteIndex`/`lua_absindex`/`stackAt`), get/set/top, type predicates + conversions, push family, upvalue API, table/metatable API, `lua_callk`/`lua_pcallk` entry points, `atpanic`/`version`/`getallocf`/`setallocf`, `checkclosemth`/`toclose`/`closeslot`, `luaV_concat`/`lua_len`/`luaV_shift`/`numMod` (`lapi.c`) | ~1800 |
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
- Deduplication: 2 number parsers → 1; 6 unwind loops → 1 helper; 58
  bufPrint idiom sites → 1 `fmtMsg`; 7 `luaG_*` boilerplate bodies → 1
  shared tail; duplicate `LUAI_MAXCCALLS` → single source. Net LOC
  roughly **−800…−1200**.
- Review surface: each future bug in, say, GC or debug-introspection
  has one 700–900-line home instead of a 6000-line kitchen sink.

## Risks

- **A1** (parser consolidation) is the riskiest commit: it touches the
  lexer and the runtime coercion fast path (P4's `tonumber`-first
  pattern). Mitigation: last of Phase A, extra tripwires (bytecode
  identity + round-trip tests), and revert-able as a single commit.
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
