---
type: lessons_learned
title: Modification Log
description: Running chronological log of bundle modifications and significant changes.
tags: [log, changelog]
timestamp: 2026-07-10T00:00:00Z
---

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
