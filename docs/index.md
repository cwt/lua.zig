---
type: bundle_root
title: luazig — A Zig 0.16.0 Port of Lua 5.5.1
description: Development knowledge base for porting the Lua reference implementation (C) to idiomatic Zig 0.16.0, following strict rules against transliteration.
tags: [lua, zig, port, okf]
timestamp: 2026-09-09T23:00:00Z
---

## Documentation Map

### Architecture & Design
- [Architecture](architecture.md) — Overall project architecture, Zig design philosophy, §0.1 rule enforcement
- [Type Model](type-model.md) — Complete type mapping from C to Zig (`TValue`, `lua_State`, `global_State`, closures)
- [Stack Design](stack.md) — Stack as `[]TValue` slice, growth strategy, indexing semantics

### Data Structures
- [Tables](tables.md) — Table implementation: array + hash part, open-addressing, metatable cache
- [String Interning](string-interning.md) — String deduplication, hash table, short vs long strings

### Virtual Machine
- [VM Instruction Set](vm.md) — Opcode formats (iABC/ivABC/iABx/iAsBx/iAx/isJ), decode helpers, execution model

### Front-End
- [Front-End](frontend.md) — Lexer (`llex.c`), Parser (`lparser.c`), Code Generator (`lcode.c`), Bytecode Loader (`lundump.c`)

### Runtime Systems
- [Error Handling](error-handling.md) — Zig error unions replacing `setjmp`/`longjmp`, OOM propagation
- [Garbage Collector](gc.md) — GC design: tri-color marking, generational vs incremental, white/black/gray lists
- [Metatables](metatables.md) — Metatable system, metamethod dispatch (`TM_*`), fast-access cache

### Standard Libraries
- [Libraries](libraries.md) — Standard library modules, `std.Io` threading, library registration

### Project Management
- [Roadmap](roadmap.md) — Phase-based development plan, dependencies between layers
- [Performance](performance.md) — 2× perf gap vs C reference: root-cause findings (RC1–RC5) + minimal-change fix plan P1–P4 (BUG-174)
- [Refactor](refactor.md) — `lua.zig` breakdown & deduplication plan: verified duplication (D1–D7) + Phase A (dedupe) / Phase B (mirror-the-C-file-layout split)
- [Bugs & Fixes](bugs/index.md) — Chronological lessons from debugging sessions (conformance fixes, root causes)
- [Log](log.md) — Running modification log

## Quick Reference

| Module | Zig source | C reference | Status |
|--------|-----------|-------------|--------|
| Core API | `src/lua.zig` | `lua/lapi.c` + `lua/lua.h` | ✅ All core C API including coroutines — 6253-line monolith packing 7 C modules; planned breakdown → [refactor.md](refactor.md) |
| Limits | `src/llimits.zig` | `lua/llimits.h` | ✅ Constants only |
| Config | `src/luaconf.zig` | `lua/luaconf.h` | ✅ Platform config |
| State | `src/lstate.zig` | `lua/lstate.c` + `lua/lstate.h` | ✅ Deleted (merged into `lua.zig`) |
| VM | `src/lvm.zig` | `lua/lvm.c` + `lua/lvm.h` | ✅ Full execution loop, all opcodes |
| Auxlib | `src/lauxlib.zig` | `lua/lauxlib.c` + `lua/lauxlib.h` | ✅ All core helpers + Phase H.1/H.4 (`luaL_newtable`, `luaL_len`, `luaL_where`, `luaL_ref`/`luaL_unref`); Phase H.5 complete (`luaL_checkversion_`, `luaL_callmeta`, `luaL_alloc`, `luaL_loadfilex`/`luaL_loadbufferx`/`luaL_loadstring`, `luaL_makeseed`, `luaL_getsubtable`, `luaL_requiref`, `luaL_dofile`, buffer fns) |
| Libs | `src/lualib.zig` + `src/lib/*` | `lua/lbaselib.c` etc. | ✅ `baselib`, `mathlib`, `bit32`, `utf8lib`, `stringlib`, `tablib`, `corolib` — **all 10**; oslib real in Phase H.2 (`os.date`/`os.execute`/`os.exit`/`os.setlocale`) |
| Entry | `src/luazig.zig` | `lua/lua.c` | ✅ juicy-main |

## External References
- C reference sources: `lua/` (Lua 5.5.1, upstream `v5.5.1` tag)
- Lua test suite: `lua/testes/`
- Zig 0.16.0 skill: `zig-0.16.0-development` (skill)
- OKF specification: built into this skill bundle
