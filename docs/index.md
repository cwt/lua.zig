---
type: bundle_root
title: luazig — A Zig 0.16.0 Port of Lua 5.5.1
description: Development knowledge base for porting the Lua reference implementation (C) to idiomatic Zig 0.16.0, following strict rules against transliteration.
tags: [lua, zig, port, okf]
timestamp: 2026-07-10T00:00:00Z
---

## Documentation Map

### Architecture & Design
- [Architecture](architecture.md) — Overall project architecture, Zig design philosophy, §0.1 rule enforcement
- [Type Model](type-model.md) — Complete type mapping from C to Zig (`TValue`, `lua_State`, `global_State`, closures)
- [Stack Design](stack.md) — Stack as `[]TValue` slice, growth strategy, indexing semantics

### Phase B — Tables (next implementation priority)
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
- [Log](log.md) — Running modification log

## Quick Reference

| Module | Zig source | C reference | Status |
|--------|-----------|-------------|--------|
| Core API | `src/lua.zig` | `lua/lapi.c` + `lua/lua.h` | ✅ Foundations, stubs for tables/load |
| Limits | `src/llimits.zig` | `lua/llimits.h` | ✅ Constants only |
| Config | `src/luaconf.zig` | `lua/luaconf.h` | ✅ Platform config |
| State | `src/lstate.zig` | `lua/lstate.c` + `lua/lstate.h` | ✅ Full, needs merging with `lua.zig` placeholder |
| VM | `src/lvm.zig` | `lua/lvm.c` + `lua/lvm.h` | ⚠️ Opcodes defined, `run` is a skeleton |
| Auxlib | `src/lauxlib.zig` | `lua/lauxlib.c` + `lua/lauxlib.h` | ⚠️ Stubs |
| Libs | `src/lualib.zig` + `src/lib/*` | `lua/lbaselib.c` etc. | ⚠️ `baselib` ✅, `mathlib` ✅, 8 others ⬜ |
| Entry | `src/luazig.zig` | `lua/lua.c` | ✅ juicy-main |

## External References
- C reference sources: `lua/` (Lua 5.5.1)
- Lua test suite: `lua/testes/`
- Zig 0.16.0 skill: `zig-0.16.0-development` (skill)
- OKF specification: built into this skill bundle
