---
type: project_priority
title: Performance — 2x Gap vs C Reference: Root Cause & Fix Plan (BUG-174)
description: perf investigation of luazig vs Lua 5.5.1 C reference on a 100M-iteration pi benchmark; 2.2x instruction-count gap (425B vs 192B) with similar-or-higher IPC; root causes RC1-RC5; ordered minimal-change fix plan P1-P4; expected 425B -> ~310-330B (~1.3-1.4x C).
tags:
  - performance
  - vm
  - gc
  - profiling
  - libm
  - roadmap
timestamp: 2026-09-09T23:55:00Z
status: draft
sources:
  - src/lvm.zig
  - src/libm.zig
  - src/lauxlib.zig
  - src/lib/mathlib.zig
  - tests/pi-5.5.lua
  - lua/lvm.c
  - lua/lgc.h
verified: machine-confirmed
stale_after: 2026-12-31T00:00:00Z
---

# Performance — 2x Gap vs C Reference (BUG-174)

## Status

| Part | State |
|------|-------|
| Root-cause investigation | ✅ DONE (2026-09-09, machine-confirmed via `perf`) |
| P1 (GC check sites) | ✅ DONE (2026-09-09) — 425B → 397B, suite 20/0/0 |
| P2 (loop-local pc + hookmask) | ✅ DONE (2026-09-10) — 14.66s wall; instr count 403B (see P2 note) |
| P3 (`getLibm` pointer) | ✅ DONE (2026-09-10) — 403B → 394B, 13.8s wall |
| P4 (`luaL_checknumber`) | ⏳ PLANNED — re-measure after P1–P3 |
| Tracking | [BUG-174](bugs/174.md) |

## Benchmark

Workload: `tests/pi-5.5.lua` — 100M-iteration generic `for` loop, per
iteration: ~23 VM opcodes (float arith, `GETGLOBAL math`, `GETFIELD
log/floor`, `FORLOOP`/`JMP`) + 2 C calls (`math.log`, `math.floor`) + 1
float `MOD`. Output is **identical** to the C reference (no conformance
issue; pure speed gap).

| Binary | Wall | Instructions | IPC | Cycles |
|--------|------|--------------|-----|--------|
| `./lua/lua` (C 5.5.1, -O2) | 8.2s | 192B | 4.5 | 43B |
| `./zig-out/bin/luazig` (ReleaseFast+thinLTO) | 15.5s | 425B | 5.2 | 82B |

- The gap is **instruction count (2.2x)**, not misprediction (branch-miss
  rates are comparable; luazig has *higher* IPC).
- ~2.3B VM opcodes total → **~118 instr/opcode (luazig) vs ~45 (C)**.

## Where the Time Goes (ReleaseFast, leaf profile)

| Region | luazig | C reference |
|--------|--------|-------------|
| Interpreter loop (`lvm.run` / `luaV_execute`) | 64% (272B) | 48–56% (~100B) |
| `luaL_checknumber` (+ `lua_tonumberx`) | 12.6% (54B) | ~10.3% (~20B) |
| C-call dispatch (`precall`/`poscall`/`closeupvals`) | ~9% (~40B) | ~8.8% (~17B) |
| mathlib bodies (`math_log`, `math_floor`, `numMod`) | ~6% (~25B) | ~8% (~16B) |
| libm (`log`/`log10`/`fmod`) | ~8% (~35B) | ~16%+ (~40B) |

The libm cost is roughly equivalent; the gap is in the interpreter loop and
its C-call plumbing.

## Methodology (reproducible)

- `perf stat -e cycles,instructions,branches,branch-misses` on both
  binaries for the aggregate instruction count.
- `perf record -g` + `perf report --no-children` for leaf hotspots.
- The production exe is **stripped** (`build.zig`:
  `root_module.strip = (optimize != .Debug)`). To get a symbolized
  ReleaseFast binary **without touching the project**:
  - shadow dir (copy of `build.zig` + symlinks to `src/`/`tests/`) in /tmp;
  - **toolchain quirk (verified):** in this 0.16.0 toolchain, setting
    `root_module.strip = false` *still* produces a stripped binary;
    **omitting the strip assignment entirely (null) keeps `.symtab`**.
    Verify with `readelf -S <bin> | grep symtab`.
- `zig build -Dmode=Debug` keeps symbols too, but Debug enables
  `-ferror-tracing` by default → `std.debug` dwarf self-unwinder +
  DebugAllocator noise dominates the profile; use Debug only for coarse
  ranking, not for relative hotspot measurement.
- `perf annotate` on a symtab-only binary gives per-instruction hot lines
  (disassembly, no source-line mapping).

## Root Causes

### RC1 — `lvm.run` keeps its loop state in a ~4.7KB stack frame (dominant)

- Disasm: `lvm.run` prologue `subq $0x1258, %rsp` (**4696B frame**). The C
  reference `luaV_execute` (gcc -O2) uses a **104B frame** and pins the loop
  state in callee-saved registers set once at entry: `L`→r12, `ci`→r15,
  `base`→r14, `G`→r13, `proto`→rbp.
- Zig instead spills/reloads per back-edge: `g` from `-0x440(%rbp)`, `L`
  from `-0x30(%rbp)` (reloaded after every helper call), `code` from
  `-0x188(%rbp)`; `ci.savedpc` is read *and stored through memory* every
  instruction.
- Hot prologue lines (`perf annotate`, % of `lvm.run`): dispatch jump table
  10.3%, `savedpc` store 4.6%, `gc_running` load 4.7%, `gccount` jbe 4.9%,
  bounds `cmpq` 3.9%, `hookmask` load+branch 4.2%+1.1% ≈ **~35% local
  (~22% of total runtime ≈ 95B of 425B)** vs ~15B for the same work in C.

### RC2 — per-instruction GC check is a deviation from the reference

- `src/lvm.zig:727` runs `if (g.gc_running and g.gc_count > g.gc_threshold)`
  **on every instruction** — 3 pointer loads (global_State +0x9f3/+0x9d0/
  +0x9c8) + 2 branches per opcode.
- The C 5.5 reference has **no GC check in the loop head** (see
  `lua/lvm.c` `luaV_execute`): GC stepping is GCdebt-based via
  `luaC_condGC` (`lua/lgc.h:233`), called only at object-registration
  sites — `lua/lvm.c:1431` (NEWTABLE), `:1637` (CONCAT), `:1939`
  (CLOSURE) — plus C-API/allocator sites (`lua/lapi.c`, `lua/lmem.c`).

### RC3 — `luaL_checknumber` cost (moderate)

- `src/lauxlib.zig:113` returns `!lua_Number` (error union) + `lua_type`
  re-check; every `math.*` call site pays the call boundary + error
  discriminant. C 5.5's `luaL_checknumber` is a real function with the
  same semantics (`lua/lauxlib.h:59`) but its error path is longjmp (zero
  hot-path cost). 12.6% vs ~10.3%; `math_log` calls it **twice** per call.

### RC4 — `libm.getLibm()` copies a 112-byte struct by value (moderate)

- `src/libm.zig:37` returns the 14-function-pointer `Libm` **by value** on
  every call (~112B move + spills into the 4.7KB frame), then the call
  site makes an *indirect* call through the pointer. C calls `log`/
  `log10`/`fmod` directly through the PLT. Sites: `src/lib/mathlib.zig`
  (~20 fns), `src/lvm.zig:58` (`numMod`, VM `MOD` opcode), `src/lvm.zig:1146`
  (`POW`). The pi loop triggers ~2 per iteration.

### RC5 — `anyerror` plumbing in hot paths (minor)

- `lvm.run` returns `anyerror!void`; hot opcode bodies use `try`
  (`luaV_gettable`/`luaV_settable`, `precall`/`poscall`), adding
  error-discriminant branches per call site that C (longjmp) does not pay
  in the hot path.

## Fix Plan (ordered, minimal-diff)

### P1 — Drop the per-instruction GC check; mirror the reference `checkGC` sites ✅ DONE (2026-09-09)

- **Result:** 425B → **397B instructions** (−28B, plan estimated −30B);
  pi wall-clock 15.5s → 15.2s (the gap is still dominated by RC1/RC3/RC4 —
  see P2–P4). Output byte-identical to the reference; `zig build test`
  182/182 (incl. 2 new P1 tests), 0 leaks; upstream suite 20 PASS / 0 FAIL
  / 0 CRASH (baseline preserved).
- **Implemented:**
  - `src/lvm.zig`: loop-head `g.gc_count > g.gc_threshold` block deleted
    (and the now-unused `const g`); `try lua.luaC_checkGC(L, top)` added at
    `.NEWTABLE` (top `ra_idx + 1`), `.CONCAT` (top `L.top`), `.CLOSURE`
    (top `ra_idx + 1`) — mirroring `lua/lvm.c:1431/1637/1939`.
  - `src/lua.zig`: new `luaC_checkGC(L, top)` — propagating variant for the
    VM sites (sets `L.top` around the step for emergency GC, restores
    after); `luaC_condGC` (fire-and-forget, C-API sites) now **logs** a
    failed step instead of the §0.1-forbidden empty `catch {}` (its
    BUG-100 comment promised logging the code never had).
  - C-API/lexer/parser sites (fire-and-forget `luaC_condGC`, matching the
    reference's void `luaC_checkGC`): `lua_pushlstring`,
    `lua_pushexternalstring`, `lua_pushvfstring`, `lua_pushfstring`,
    `lua_pushcclosure` (all 3 paths), `lua_createtable`, `lua_newthread`,
    `lua_load` (entry), `lua_closeslot`, `lua_warning`,
    `lua_tolstring` (number-coercion branch); `llex.zig` `luaX_newstring`
    (new-entry branch, `llex.c:146`); `lparser.zig` `close_func`
    (`lparser.c:850`). The vararg-table site (`ltm.zig`, C `ltm.c:245`)
    already existed.
  - The plan's `lstring.zig`/`ltable.zig` sites were **not needed**: the
    C reference does not check inside interning/table-alloc — debt
    adjusts there and the *callers'* sites (above) cover them. The
    `lua/lapi.c` audit (lines 426/549/564/581/592/603/630/800/1125/1215/
    1305/1366) mapped 1:1 to the list; `lapi.c:1215` (GCSTEP) is already
    covered by the BUG-169 step accumulator in `lua_gc`.
- **Lesson (found by the suite):** the VM sites must **anchor the new
  object on the stack BEFORE the check** — C does `sethvalue2s(ra, t)`
  then `checkGC(L, ra + 1)`. The first NEWTABLE patch checked before
  writing the slot, so a triggered collection swept the just-registered
  table (unreachable) and the slot then held a dangling pointer → 5
  upstream tests crashed with glibc "unaligned tcache chunk" heap
  corruption. Fixed by reordering; the strengthened P1 test now keeps
  alive some loop tables and verifies their contents survive in-loop
  collections (regression pin for this ordering).
- **Tooling note:** `zig build test` in this 0.16 toolchain prints
  `failed command: ... test_basic ... --listen=-` even when the step
  **succeeds** (display artifact of the listen-protocol exit handshake).
  Judge by exit code / `zig build test --summary all`
  ("9/9 steps succeeded; 182/182 tests passed").

### P2 — Loop-local `savedpc` + hoisted `hookmask` in `run` ✅ DONE (2026-09-10)

- **Implemented** (`src/lvm.zig` only):
  - `var pc = ci.savedpc;` + `var hookmask = L.hookmask;` loop locals
    (mirror of the C reference's local `Instruction *pc` / `trap`); the
    back-edge is now a register compare + register hook check — no
    per-instruction `ci.savedpc`/`L.hookmask`/`g` traffic.
  - `ci.savedpc = pc;` sync at the top of every error-capable arm (57
    arms) + before the RETURN-yield rewind + at every frame switch
    (`pc = ci.savedpc` restart) + defensive loop-end sync.
  - `hookmask = L.hookmask;` reload after user-code sites: traceexec,
    `precall`/`poscall`, `closeupvals`/`checkclosemth`, `luaV_concat`,
    metamethod-dispatch helpers, TAILCALL new-frame entry. Pure
    arithmetic/jump instructions cost nothing (jumps cannot run user
    code, matching the C `dojump` rationale for this port, which has no
    signal→trap path).
  - `docondjump` reworked to be pc-based (returns the new pc); 15 call
    sites updated; JMP/TESTSET/FORPREP/FORLOOP/TFORPREP/TFORLOOP
    arms now update `pc` locally.
- **Measured result:** pi wall 15.2s → **14.66s** (~1.79× C); output
  byte-identical; 182/182 unit tests + 20/0/0 upstream suite.
  Back-edge acceptance signal met: disasm shows register-based loop
  guard (`jae`), register hook check (`testb`), no per-instruction
  savedpc store / g-reload.
- **Instruction count went UP, not down** (397B → 403B, +1.6%): the
  plan's −40–60B estimate assumed the big frame would shrink and loop
  state would pin in callee-saved registers; it did not — the ~5
  arm-top syncs + ~7 hookmask reloads executed per pi iteration
  outweigh the back-edge saving in raw instructions (though wall time
  improved, since the removed traffic was the memory-heavy part). The
  4.7KB `lvm.run` frame (RC1) remains; making the backend pin the loop
  state is the deeper follow-up (see "Explicitly NOT doing").

### P3 — `getLibm()` returns `*const Libm` instead of a 112-byte value ✅ DONE (2026-09-10)

- **Implemented** (`src/libm.zig`, ~50-line diff; all call sites
  unchanged — Zig auto-derefs `m.log(x)` on a `*const Libm`):
  - `getLibm()` now returns `*const Libm`, pointing at a
    process-lifetime singleton instead of copying the 14-function-pointer
    (112-byte) struct by value on every call.
  - Storage: a mutable global `libm_resolved` (filled once by
    `resolve()`, gated by a `libm_resolved_ok` flag) and a `const`
    readonly global `libm_fallback` (wired to the std.math fallbacks).
    Both live at fixed addresses, so `getLibm` just hands out a
    pointer to one of them.
  - `resolve()` fills `libm_resolved` in place and returns `bool`
    (previously returned `?Libm` by value + a separate `fallback()`);
    the old `libm_cache: ?Libm` optional-global is gone.
- **Measured result:** pi 403B → **394B** instructions (−9B, matching the
  plan's −10B), wall 14.6s → **13.8s** (~1.69× C). A hot caller like
  `math.log` now loads a single 8-byte pointer and reads only the one
  function pointer it needs, instead of paying the 112-byte copy + spills
  in every invocation. `libm.getLibm` no longer appears as a frame in the
  symbolized profile (was 0.75% of samples pre-P3). Output byte-identical
  to the C reference; 182/182 unit tests, 0 leaks; upstream suite
  20 PASS / 0 FAIL / 0 CRASH.

### P4 — `luaL_checknumber` (defer; re-measure after P1–P3)

- The 54B vs 20B gap is the `!lua_Number` call-boundary + frame-spill
  cost; it shrinks automatically as P1/P2 cut the frame. If still hot,
  follow-up: a non-error fast path used by `mathlib` (bigger API change —
  out of scope for the minimal pass).

### Explicitly NOT doing this pass

- Opcode body rewrites, `TValue` layout changes, GC engine changes,
  `precall`/`poscall` restructuring, backend register-pinning workarounds.

## Verification Protocol (per item)

1. One hg commit per item; §0.1 self-audit in the commit message (new `try`
   sites must propagate — never `catch {}` / `catch unreachable`).
2. `zig build` + `zig build test` (182 tests, 0 leaks — judge by
   `--summary all` / exit code, not the misleading "failed command" line;
   see the P1 tooling note) after each item.
3. Benchmark: `time ./zig-out/bin/luazig tests/pi-5.5.lua` and
   `perf stat -e instructions` — record per step (history: 425B/15.5s
   pre-P1 → **397B/15.2s post-P1** → 403B/14.6s post-P2 → **394B/13.8s
   post-P3**; C reference: 192B / 8.2s).
4. After P1 + P2: full upstream `lua/testes` suite via `./run_testes.sh`
   (must stay 20 PASS / 0 FAIL / 0 CRASH; `cstack` needs CWD
   `lua/testes` for the pure-Lua `tracegc.lua` fallback — a standalone run
   from the repo root fails identically on the C reference, i.e.
   environmental).
5. Re-profile via the shadow-build method above; confirm the RC1 back-edge
   loads are gone from the disassembly.
6. Update this document (flip statuses), `log.md`, and close
   [BUG-174](bugs/174.md) when done.

## Expected Outcome

- P1 landed at 425B → **397B** (15.2s), confirming the −30B estimate for
  RC2. P2 (loop-local `pc`/`hookmask`) improved wall time (14.6s) but
  *raised* the instruction count to **403B** — the per-arm sync/reload
  sites outweighed the back-edge saving in raw instructions, and the 4.7KB
  `lvm.run` frame (RC1) is still the dominant term. P3 (`getLibm` pointer)
  landed at 403B → **394B** (13.8s, ~1.69× C), confirming the −10B RC4
  estimate.
- Remaining levers, in order: P4 (`luaL_checknumber`, re-measure now that
  P1–P3 have cut the frame), and a deeper register-pinning pass on the
  interpreter frame to attack RC1 (out of the minimal-change scope). The
  original "425B → ~310–330B / ~1.3–1.4× C" projection was optimistic; the
  post-P3 state is **394B / 13.8s ≈ 1.69× C** (vs 192B / 8.2s for the C
  reference). Full parity needs the RC1 frame-pinning follow-up.

## Related

- [VM design](vm.md) — opcode fast-paths, execution model
- [GC design](gc.md) — GC lists, stepping; loop-head check deviation
- [BUG-174](bugs/174.md) — defect tracking
- [Log](log.md)
