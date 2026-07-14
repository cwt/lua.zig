---
type: project_priority
title: Development Roadmap
description: Phase-based development plan for the Lua-to-Zig port, with dependencies and verification requirements.
tags: [roadmap, planning, phases]
timestamp: 2026-07-12T00:00:00Z
---

## Phase Overview

```
Phase A (DONE) --> Phase B (DONE) --> Phase C (DONE) --> Phase D (DONE) --> Phase E (DONE) --> Phase F (DONE) --> Phase G (DONE)
 Foundations       Tables           Front-End (loader)     VM               Runtime           Libs              Source compiler

                                                                                                                          v
                                                                                                                   Phase H (NEXT)
                                                                                                              Drop-in replacement
                                                                                                              gap closure
```

Work **top-down from the foundation**, validating each layer with tests before proceeding. Phases A–G are complete; **Phase H (drop-in replacement gap closure)** is the next planned work.

## Phase A -- Foundations (Complete)

- Module layout mirrors `lua/` C modules
- Single type model: one `lua_State`, one `lua_CFunction`, one `global_State`
- Real stack: `stack: []TValue` slice, `lua_checkstack` with `gpa.realloc`
- Correct instruction decode: proper bit shifts in GETARG/SETARG
- Version constants: Lua 5.5.1
- juicy-main entry: `src/luazig.zig` with `std.process.Init`
- Builds exe + lib + tests
- 7 passing tests: type checks + stack round-trip

## Phase B -- Tables and String Interning (Complete)

### Tables

Implement the `lua_Table` type properly:

- **Hash part**: open-addressing hash table modeled on `lua/ltable.c`
  - `Node` struct with key + value + next index
  - "dummy node" sentinel for empty hash parts (`isdummy`)
  - Computed main position (`luaH_mainposition`)
  - `luaH_get*` / `luaH_set*` / `luaH_pset*` operations
  - `luaH_resize` / `luaH_resizearray`
- **Array part**: `std.ArrayList(?TValue)` for integer keys 1..n
- **API functions**: `lua_createtable`, `lua_settable`/`lua_gettable`, `lua_rawset`/`lua_rawget`, `lua_seti`/`lua_geti`, `lua_next`, `lua_rawlen`
- **Metatable cache**: `t->flags` bits for fast-access TM check

### String Interning

- `stringtable` in `global_State`: hash table of `lua_TString*`
- Short strings (<=40 bytes): interned, pointer-equality comparable
- Long strings: stored but not deduplicated
- `lua_pushstring`/`lua_pushlstring`: lookup or create

### Verification

- Table creation, insertion, retrieval (integer + string keys)
- Array part auto-expansion
- Hash part collision handling
- String interning: same literal yields same pointer
- `lua_next` traversal
- All old tests still pass

## Phase C -- Front-End

**Decision required**: either (a) port the full lexer+parser+codegen, or (b) implement a bytecode loader with precompiled chunks.

### Option (a) -- Full Front-End

- **Lexer** (`lualex.c`): `LexState`, `luaX_next`, `luaX_newstring`, token types, reserved words
- **Parser** (`luaparser.c`): `FuncState`, `expdesc`, `luaY_parser`, recursive descent
  - Expression parsing: prefix/infix, operator precedence
  - Statement parsing: blocks, if/while/repeat/for, local/global declarations
- **Code generator** (`luacode.c`): instruction emission, register allocation, patch lists
  - `expdesc` to instruction translation
  - Patch lists for boolean short-circuit and goto

### Option (b) -- Bytecode Loader

- Port `lua/lundump.c`: read precompiled Lua bytecode chunks
- Produce identical `lua_Proto` structures
- Use bytecode from reference `lua` executable for testing

### Verification

- Parse `"return 1+2"` to valid `Proto`
- Round-trip source string through `luaL_dostring`
- Test basic Lua scripts from `lua/testes/`

## Phase D -- Working VM

Implement `lvm.run` for real:

- **Constant pool**: LOADK, LOADKX, LOADI, LOADF read from `Proto.k`
- **Arithmetic**: ADD, SUB, MUL, DIV, IDIV, MOD, POW, SHL, SHR, BAND, BOR, BXOR (with immediate variants)
- **Comparisons**: EQ, LT, LE (with EQI, LTI, LEI, GTI, GEI variants)
- **Table access**: GETTABLE, SETTABLE, GETI, SETI, GETFIELD, SETFIELD
- **Upvalues**: GETUPVAL, SETUPVAL, GETTABUP, SETTABUP
- **Function calls**: CALL, TAILCALL with `CallInfo` chain management
- **Returns**: RETURN, RETURN0, RETURN1 -- value propagation
- **Closures**: CLOSURE -- `Proto` to `lua_Closure.lua`
- **Varargs**: VARARG, VARARGPREP, GETVARG
- **Loops**: FORLOOP, FORPREP, TFORPREP, TFORCALL, TFORLOOP
- **Jumps**: JMP with offset, patch lists
- **Metamethod dispatch**: MMBIN, MMBINI, MMBINK for binary ops with TM fallback

## Phase E -- Runtime Systems

- **Error handling**: replace remaining `lua_longjmp` usage, wire Zig errors through `lua_pcallk`/`lua_callk`, implement `lua_error` via error return
- **Metatables**: `lua_setmetatable`, `lua_getmetatable`, `TM_*` dispatch in `lua_arith`/`lua_compare`/`lua_get*`/`lua_set*`
- **GC**: tri-color mark-and-sweep, generational + incremental modes, write barriers, finalization, weak tables, ephemerons

## Phase F -- Standard Libraries (Complete, 2026-07-12)

Implement library bodies in `src/lib/*.zig`:

- baselib: `print`, `assert`, `type`, `pairs`, `ipairs`, `tostring`, `tonumber`, etc. — **DONE**
- mathlib: `math.sin`, `math.cos`, `math.sqrt`, `math.random`, etc. — **DONE** (2026-07-11)
- stringlib: pattern matching, `string.find`, `string.gsub`, `string.match`, etc. — **DONE** (2026-07-12)
- tablelib: `table.insert`, `table.remove`, `table.sort`, `table.concat`, etc. — **DONE**
- utf8lib: UTF-8 character/byte iteration — **DONE** (2026-07-12, ported from `lua/lutf8lib.c`)
- oslib: `os.clock`, `os.date`, `os.time`, `os.execute` etc. — **DONE**
- iolib: file I/O via `std.Io` instead of C FILE* — **DONE**
- corolib: coroutine creation/resume/yield — **DONE** (2026-07-12, all 8 functions + C API)
- loadlib: `require`, `package`, module loading — **DONE** (require chain minimal)
- bit32: bitwise operations — **DONE** (2026-07-11, ported from Lua 5.3 `lbitlib.c`)
- debug: debug API — **DONE** (2026-07-12, all 16 functions)

Wire `iolib`/`oslib` to `std.Io`/`init.io`. **67/67 tests pass, zero memory leaks.**

## Phase G — Source-Text Compiler ✅ DONE (2026-07-13)

All G.1–G.4 completed. Full Lua 5.5.1 lexer, recursive-descent parser, and code generator ported to Zig 0.16.0. `lua_load` now detects source vs bytecode and compiles text source via `luaD_protectedparser`. 73/73 tests pass, zero leaks.

### Phase G.1 — Lexer (`src/llex.zig`) ✅ DONE
### Phase G.2 — Parser (`src/lparser.zig`) ✅ DONE
### Phase G.3 — Code generator (`src/lcode.zig`) ✅ DONE
### Phase G.4 — Wire `lua_load` ✅ DONE

See `docs/frontend.md` for architecture decisions and `AGENTS.md` §Phase G for details.

## Phase H — Drop-in replacement gap closure (IN PROGRESS)

Phases A–G built a working, self-hosting Lua interpreter. Phase H closes the gap between "working" and "drop-in replacement for Lua 5.5.1". The gaps were identified by a systematic audit comparing `luazig` against `lua/lua.h`, `lua/lauxlib.h`, and the standard library C sources.

### H.1 — C API stubs → implementations (DONE, Rev 61)
Silent no-ops that produce wrong results:
- `lua_concat` — body discards `n`, does nothing
- `lua_len` — body discards `idx`, does nothing
- `lua_getallocf` / `lua_setallocf` — returns undefined / ignores params
- `lua_toclose` / `lua_closeslot` — `<close>` variables never fire
- `createargtable` — `arg` table never populated
- `luaL_newtable` — empty body
- `luaL_where` — always pushes `""`
- `luaL_len` — uses `lua_rawlen` without `__len` metamethod

### H.2 — oslib stubs (DONE, Rev 64)
- `os.date` — `*t` table (year/month/day/hour/min/sec/wday/yday/isdst) + real `strftime` formatting via `extern "c"` libc `localtime_r`/`gmtime_r`/`strftime` (glibc `tm` layout declared locally).
- `os.execute` — real subprocess via `std.process.spawn` + `child.wait`, returning `(true/nil, "exit"/"signal", code)` matching the reference. Uses `L.l_G.?.io`.
- `os.exit` — calls `lua_close` then `std.process.exit` (runs `__close`/`__gc` finalizers first).
- `os.setlocale` — real `std.c.setlocale` with category parsing (`classcat`).
- `os_time` — table form (requires year/month/day) via `mktime`; non-table falls back to `clock_gettime`.
- Note: `std.c` on this Zig version exposes only `setlocale`/`LC`/`time_t` (no `time`/`strftime`/`mktime`/`localtime_r`/`gmtime_r`/`tm`), so those are bound directly with `extern "c"`.

### H.3 — iolib stubs (LOW priority)
- `io.flush` / `file:flush` — no-op
- `file:setvbuf` — no-op

### H.4 — Reference system (MEDIUM priority) ✅ DONE (2026-07-14)
- `luaL_ref` / `luaL_unref` — needed by C extensions
- `LUA_NOREF` / `LUA_REFNIL` constants
- Port from `lua/lauxlib.c`

### H.5 — Missing C API functions (MEDIUM priority)
- `lua_atpanic`, `lua_version`, `lua_pushexternalstring`, `lua_numbertocstring`
- `luaL_checkversion_`, `luaL_callmeta`, `luaL_alloc`, `luaL_loadfilex`, `luaL_loadbufferx`, `luaL_loadstring`, `luaL_makeseed`, `luaL_getsubtable`, `luaL_requiref`, `luaL_dofile`
- Buffer aux: `luaL_addstring`, `luaL_buffinitsize`, `luaL_prepbuffer`, `luaL_bufflen`, `luaL_buffaddr`, `luaL_buffsub`

### H.6 — CLI/REPL improvements (MEDIUM priority)
- `-e`, `-l`, `-i`, `-v` flags
- Multi-line input in REPL
- Readline/history/line-editing
- `arg` table (depends on H.1 `createargtable`)
- `--` argument separator

### H.7 — Convenience macros (LOW priority)
`lua_insert`, `lua_remove`, `lua_newtable`, `lua_register`, `lua_pushglobaltable`, `lua_pushliteral`, `lua_isnoneornil`, `lua_isfunction`, `lua_isthread`, `lua_islightuserdata`

### H.8 — Deprecated compatibility aliases (LOW priority)
`lua_newuserdata`, `lua_getuservalue`, `lua_setuservalue`, `lua_resetthread`

### H.9 — Missing constants and exports (LOW priority)
`LUA_GNAME`, `LUA_ERRFILE`, `LUA_LOADED_TABLE`, `LUA_PRELOAD_TABLE`, `LUA_NOREF`, `LUA_REFNIL`, `LUAL_NUMSIZES`, `LUA_COPYRIGHT`, `LUA_AUTHORS`, `lua_ident`

### H.10 — GC completeness (LOW priority)
- `LUA_GCPARAM` option 9 not handled
- GC parameter get/set (`LUA_GCPMINORMUL`, `LUA_GCPSTEPMUL`, etc.)

### Verification
Each H.x sub-phase must compile, pass all existing tests, and add focused tests for the new functionality. After Phase H is complete, `luazig` should pass all Lua 5.5.1 `lua/testes/` test files without modification (modulo `os.execute` platform dependency and `os.date` localization).

See `AGENTS.md` §Phase H for detailed per-item breakdown. §0.1 gate applies to all work.
