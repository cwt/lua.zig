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
timestamp: 2026-09-09T23:00:00Z
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
| Fix plan P1–P4 | ⏳ PLANNED, not started |
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

### P1 — Drop the per-instruction GC check; mirror the reference `checkGC` sites

- **Files:** `src/lvm.zig` (delete loop-head block at 727–732; add 3 calls),
  `src/lua.zig` (helper + C-call/C-API sites), `src/lstring.zig`
  (interning site), `src/ltable.zig` (allocation site if needed).
- **What:**
  - Add `checkGC(L)` helper mirroring `luaC_condGC` (`lua/lgc.h:233`):
    `if (g.gc_running and g.gc_count >= g.gc_threshold) { g.gc_count = 0;
    collect }` (keep the existing collection call; §0.1: propagate errors,
    never swallow).
  - Call it at the reference's object-registration sites:
    - VM opcodes: `.NEWTABLE`, `.CONCAT`, `.CLOSURE` bodies in `lvm.zig`
      (mirror `lua/lvm.c:1431/1637/1939`);
    - `luaS_new` in `lstring.zig` — only when a string is **newly**
      interned;
    - table creation in `lua.zig` (`lua_createtable`/`luaH_new`);
    - C-call return path (`precall`/`poscall`/`luaK_finish` in `lua.zig`) —
      audit `lua/lapi.c` `luaC_checkGC` sites and map each to its Zig
      equivalent before finalizing.
- **Expected:** −30B instructions (~0.5s).
- **Risk:** LOW–MED. GC timing shifts (checks run at allocation sites, as
  in the reference; in the pi loop they run *never*). Must re-run the full
  upstream suite (GC-sensitive tests) + 131 unit tests + 0-leak check.

### P2 — Loop-local `savedpc` + hoisted `hookmask` in `run`

- **File:** `src/lvm.zig` (`run` only, ~40–60 line diff).
- **What** (mirror C's register-`pc` + `savepc`/`updatetrap` pattern,
  `lua/lvm.c:1130–1180`):
  - `var pc = ci.savedpc;` → `while (pc < code.len)`, `instruction =
    code[pc]; pc += 1;`.
  - `var hookmask = L.hookmask;` checked locally; reloaded at the C
    `updatetrap` sites only (after JMP, after call/return, at Protect
    sites) — nested `debug.sethook` still works.
  - **Sync audit** — `ci.savedpc = pc;` immediately before:
    - every `try <helper>` in an opcode body (GET\*/SET\*/SELF/
      GETFIELD/CONCAT/CALL/TAILCALL/CLOSE/NEWTABLE/CLOSURE/…);
    - every `return error.*` / `luaG_runerror` exit from `run`
      (error-line reporting reads `ci.savedpc` via `luaG_errormsg` /
      `luaG_getfuncline`);
    - `precover` / `closeupvals` boundaries; resume/yield points;
      coroutine close paths.
  - The hot arithmetic + `JMP` path then has **zero** savedpc memory
    traffic; back-edge becomes a register-register compare.
- **Expected:** −40–60B (~0.8–1.2s); likely shrinks the 4.7KB frame and
  lets the backend pin loop state in callee-saved registers (acceptance
  signal: re-disasm the back-edge — the `movq -0x440(%rbp)` g-reload and
  `0x18(%r15)` savedpc traffic must be gone).
- **Risk:** MED — the sync audit is the correctness-critical part.
  Tripwires: `locals.lua` (TBC/precover), pcall/coroutine upstream tests,
  all 131 unit tests, 0 leaks.

### P3 — `getLibm()` returns `*const Libm` instead of a 112-byte value

- **File:** `src/libm.zig` (~10 lines; call sites unchanged — Zig
  auto-derefs `m.log(x)` on a `*const Libm`).
- **What:** keep one lazily-resolved static `Libm` (DynLib resolve +
  fallback, as today); `pub fn getLibm() *const Libm { ensureResolved();
  return &the_static; }`.
- **Expected:** −10B (~0.2s) + removes a spill-pressure source from the
  big frame. **Risk:** NONE (no semantic change).

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
2. `zig build` + `zig build test` (131 tests, 0 leaks) after each item.
3. Benchmark: `time ./zig-out/bin/luazig tests/pi-5.5.lua` and
   `perf stat -e instructions` — record per step (baseline: 425B / 15.5s;
   C reference: 192B / 8.2s).
4. After P1 + P2: full upstream `lua/testes` suite (must stay
   20 PASS / 0 FAIL / 0 CRASH per current `./run_testes.sh` baseline).
5. Re-profile via the shadow-build method above; confirm the RC1 back-edge
   loads are gone from the disassembly.
6. Update this document (flip statuses), `log.md`, and close
   [BUG-174](bugs/174.md) when done.

## Expected Outcome

425B → ~310–330B instructions ≈ **10.5–11.5s ≈ 1.3–1.4× the C reference**,
from ~10 lines in `libm.zig`, ~15 in `lua.zig`/`lstring.zig`, ~50 in
`lvm.zig` — no data-layout or opcode-semantics changes. Reaching full
parity requires deeper register-pinning work (second pass, not planned
here).

## Related

- [VM design](vm.md) — opcode fast-paths, execution model
- [GC design](gc.md) — GC lists, stepping; loop-head check deviation
- [BUG-174](bugs/174.md) — defect tracking
- [Log](log.md)
