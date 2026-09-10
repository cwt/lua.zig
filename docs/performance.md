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
| P4 (`luaL_checknumber` fast path) | ✅ DONE (2026-09-10) — 394B → 375B, 12.7s wall |
| RC1/RC5 deep pass (D1–D4) | D1 ✅ done · D2 ⬅️ attempted+reverted · D3/D4 deferred |
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
- **Status update (post P1–P4):** the per-instruction loop-head costs above
  are GONE — P1 removed the GC check and P2 pinned `pc`/`hookmask` in
  registers (the back-edge is now a register compare + register hook test).
  What remains is the **error-union ABI slot of the hot helper calls**
  (`precall`/`poscall`/`luaT_*`/`closeupvals`/`checkclosemth`) and the
  still-large frame — see the "RC1 deep pass (D1–D4)" plan below. The
  TValue tag byte-loads are intrinsic and shared with the C reference.

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

### P4 — `luaL_checknumber` non-error fast path in `mathlib` ✅ DONE (2026-09-10)

- **Re-measure first (per the plan):** post-P1–P3, `luaL_checknumber` was
  still the #2 hot leaf (~22% of samples, ~62–87B of the 394B total) — the
  `!lua_Number` error-union ABI (a caller-reserved stack slot the callee
  writes on *every* invocation: error-value + discriminant) plus a cold
  cross-module index-resolution call. The C reference pays ~1/3 of that
  because it throws via `longjmp`, not a value-carrying error return.
- **Implemented** (`src/lib/mathlib.zig` only; `luaL_checknumber`'s public
  API and semantics untouched): every numeric-argument read in the math
  library now uses the tonumber-first pattern
  `lua.lua_tonumber(L, N) orelse try lauxlib.luaL_checknumber(L, N)`
  (22 sites). The hot path (a plain number/integer argument) goes through
  the **non-error** `?lua_Number` read and never touches the error-union
  ABI; a genuine type error falls through to the exact throwing call.
  Provably behavior-identical: `luaL_checknumber` is itself
  `lua_tonumber` + "throw if null", so value and error message are
  unchanged in every case.
- **Measured result:** pi 394B → **375B** instructions (−18B, inside the
  plan's −15–30B estimate), wall 13.8s → **12.7s** (~1.55× C). `luaL_checknumber`
  no longer appears as a frame in the profile (its inlined fast path now
  shows up inside `math_log`/`math_floor`). Output byte-identical to the C
  reference; 182/182 unit tests, 0 leaks; upstream suite
  20 PASS / 0 FAIL / 0 CRASH.
- **Remaining gap vs C (192B / 8.2s):** `lvm.run` is now the dominant
  single frame (~60% of samples). See the RC1 deep pass (D1–D4) below for
  the plan to close it.

### RC1 deep pass (D1–D4) — plan, NOT yet implemented

**Refined root cause (post-P4 disasm, `perf annotate` on the 375B build):**
- The `lvm.run` back-edge is already register-pinned (P2): `pc`/`hookmask`
  are register compares (`jae`/`testb`), not frame reloads. The loop-
  invariant TValue tag byte-loads (`movzx …, byte [base+0x8]`) are
  intrinsic to Lua's stack-in-memory model — the C reference pays the same
  byte-loads.
- The frame shrank 0x1258 → **0x1158 (4440B)** but is still ~40× the C
  reference's 104B. The dominant *residual* hot cost is the **error-union
  return ABI of the hot helper calls**: the 8.26% line
  `movzx edx, word [rbp-0xba8]` sits immediately after
  `call lua.precall` (it reloads the caller-reserved `anyerror` slot).
  `lvm.run` makes ~354 `call`s, top targets: `poscall` (×8), `precall`
  (×6), `closeupvals` (×4), `checkclosemth` (×4), `getnumargs` (×6),
  `ltable.set` (×4). **This is RC5 manifesting inside the VM** — C's
  `luaD_precall`/`luaD_poscall` are `void` and throw via `longjmp`, so the
  hot path is a single predictable branch, not a value-carrying error
  return.
- Therefore the RC1 deep pass is, mechanically, an **RC5 pass**: remove
  the `!` error-union ABI from the hot VM helper-call paths (the P4
  fast/slow-split idea, applied to `precall`/`poscall`/`luaT_*`/
  `closeupvals`/`checkclosemth`). As the ABI slots and their live error
  values disappear, the 4.4KB frame should shrink and the backend should
  be able to pin `L`/`ci`/`base`/`G`/`proto` in callee-saved registers
  (the C model) — the actual RC1 win.

**Ordered steps (minimal-change discipline; one commit each):**

- **D1 — Measure & attribute (read-only) ✅ DONE (2026-09-10):**
  - Frame: `sub rsp, 0x1158` = 4440B (was 4696B pre-P1..P4 — P1–P4
    shrank it ~256B).
  - The dominant residual hot line in `lvm.run` is the **error-union ABI
    slot of `precall`**: `movzx edx, word [rbp-0xba8]` + `test` + `jne`
    immediately after `call lua.precall` (8.26% of `lvm.run` samples in
    the P4 build). `precall` returns `!?*CallInfo` (value + error), whose
    caller-reserved return slot is reloaded after every call. The `.CALL`
    arm (2×/iter on the pi benchmark: `math.log`, `math.floor`) and
    `.TFORCALL` are the hot sites.
  - **Important ABI nuance found:** the `!void` helpers (`poscall`,
    `closeupvals`) use a *cheap* register ABI (error in `ax`,
    `test ax,ax` + `jne` — no stack slot). Only the value-carrying
    `!?*CallInfo` return of `precall` pays the slot reload. So D2
    targets `precall` only; `poscall`/`closeupvals` are already near-C
    cheap at the ABI level.
  - The per-iteration loop-state frame mirrors (`mov [rbp-0x38], pc+1`
    ≈1.2% in P4) are the RC1 frame-pinning residual; the TValue tag
    byte-loads are intrinsic (C pays them too).
- **D2 — `precall` fast/slow split ⬅️ ATTEMPTED, REVERTED (2026-09-10).**
  Implemented `precallStatus` (enum + `*?*CallInfo`/`*anyerror`
  out-params; the `!` `precall` became a thin wrapper; all three VM
  sites — `.CALL`, TAILCALL-`.c`, `.TFORCALL` — converted), with
  behavior-identical semantics (182/182 tests, 20/0/0 upstream,
  byte-identical pi output). **Measured: −0.8B instructions, +0.2s
  wall (12.74 → 12.95s) — the −20..−40B projection was falsified.**
  Re-disasm: the ABI slot reloads are indeed gone, but the backend
  re-spilled: the back-edge now mirrors `ci`/`base`/`pc+1` into the
  frame every iteration (`lea r10,[rbx+1]` 4.65% +
  `mov [rbp-0x40], r10` 4.75% + 2 more stores), offsetting the saving.
  **Lesson:** removing one helper's return-ABI slot does not reduce the
  overall register pressure of `lvm.run` enough to stop the loop-state
  frame mirrors (the RC1 effect); the extra out-params even raised
  pressure. Reverted to the P4 state (375B / 12.7s, the best achieved).
- **D3 — `luaT_*` + `closeupvals`/`checkclosemth` fast paths.** The
  no-metamethod / no-to-be-closed case is pure (no user code, no error) —
  return the result directly; only fall through to the `!` slow path when
  a metamethod runs or a `__close` can raise. Est. −10–20B on
  table/metamethod workloads (near-zero on pi). **Risk: MEDIUM.**
  *Status: deferred — D2's lesson (out-params raise register pressure,
  and pi doesn't execute these helpers anyway) suggests the expected
  benefit on the pi benchmark is ~0; only worthwhile for
  metatable-heavy workloads. Not attempted.*
- **D4 — Frame shrink / register pinning (the real RC1 lever).** The D2
  attempt showed the residual cost is the backend keeping loop-state
  (`ci`/`base`/`pc`) mirrored into the 4.4KB frame every iteration.
  Closing it needs to reduce `run`'s *global* register pressure (fewer
  simultaneously-live values across the 57 arms + helper calls) or split
  `run` so the register allocator can pin the loop state — a structural
  change, low confidence, high effort. **Out of the current scope;
  recorded as the remaining work on BUG-174.**

**Verification per D-step:** `zig build` + `zig build test` (182, 0
leaks) + `./run_testes.sh` (must stay 20 PASS / 0 FAIL / 0 CRASH) +
pi benchmark (wall + `perf stat -e instructions`) + re-disasm to confirm
the ABI-slot reloads are gone from the hot arms.

**Projection (revised post-D2):** D2's revert means the post-pass state
stays at **375B / 12.7s (≈1.55× C)** — the best achieved. The original
"375B → ~330–350B" projection is abandoned: the D2 attempt showed the
residual cost is the backend's loop-state frame mirroring (RC1 register
pressure), which single-helper ABI changes do not relieve. Any further
gain requires the D4 structural pass (split / pressure-reduction of
`lvm.run`), which is a bigger, lower-confidence effort. Full parity with
the C reference (192B / 8.2s) is not expected from any minimal change;
the intrinsic TValue tag loads and Zig's `anyerror` design floor the
instruction count above C's longjmp model.

## Verification Protocol (per item)

1. One hg commit per item; §0.1 self-audit in the commit message (new `try`
   sites must propagate — never `catch {}` / `catch unreachable`).
2. `zig build` + `zig build test` (182 tests, 0 leaks — judge by
   `--summary all` / exit code, not the misleading "failed command" line;
   see the P1 tooling note) after each item.
3. Benchmark: `time ./zig-out/bin/luazig tests/pi-5.5.lua` and
   `perf stat -e instructions` — record per step (history: 425B/15.5s
   pre-P1 → **397B/15.2s post-P1** → 403B/14.6s post-P2 → 394B/13.8s
   post-P3 → **375B/12.7s post-P4**; C reference: 192B / 8.2s).
4. After P1 + P2: full upstream `lua/testes` suite via `./run_testes.sh`
   (must stay 20 PASS / 0 FAIL / 0 CRASH; `cstack` needs CWD
   `lua/testes` for the pure-Lua `tracegc.lua` fallback — a standalone run
   from the repo root fails identically on the C reference, i.e.
   environmental).
5. Re-profile via the shadow-build method above; confirm the RC1 back-edge
   loads are gone from the disassembly.
6. Update this document (flip statuses), `log.md`, and close
   [BUG-174](bugs/174.md) when done.

## Outcome (minimal-change pass complete)

- All four parts P1–P4 have landed. Instruction count: 425B → **375B**
  (−50B, −12%), wall time 15.5s → **12.7s** (~1.55× C; C reference 8.2s /
  192B). Output stayed byte-identical to the C reference and the full
  upstream suite stayed 20 PASS / 0 FAIL / 0 CRASH throughout.
  - P1 (GC check sites): 425B → 397B, as estimated.
  - P2 (loop-local `pc`/`hookmask`): improved wall time but *raised* the
    instruction count to 403B (sync/reload sites offset the back-edge
    saving); the 4.7KB `lvm.run` frame (RC1) never shrank.
  - P3 (`getLibm` pointer): 403B → 394B, as estimated.
  - P4 (`luaL_checknumber` fast path): 394B → 375B, inside the −15–30B
    estimate; `luaL_checknumber` no longer appears as a hot frame.
- The original "425B → ~310–330B / ~1.3–1.4× C" projection was optimistic;
  the actual post-pass state is **375B / 12.7s ≈ 1.55× C**. The remaining
  gap to C is dominated by RC1/RC5 — the `lvm.run` frame (~4.4KB vs C's
  104B) kept large by the `!` error-union ABI of its hot helper calls
  (`precall`/`poscall`/`luaT_*`/`closeupvals`/`checkclosemth`). The plan
  to close it is the **"RC1 deep pass (D1–D4)"** section above (strip the
  `!` ABI off the hot VM helper-call paths, P4-style; the frame should then
  shrink and the backend pin the loop state). It is a deeper, higher-risk
  pass, explicitly out of the minimal-change scope of the P1–P4 work.

## Related

- [VM design](vm.md) — opcode fast-paths, execution model
- [GC design](gc.md) — GC lists, stepping; loop-head check deviation
- [BUG-174](bugs/174.md) — defect tracking
- [Log](log.md)
