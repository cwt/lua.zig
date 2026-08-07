---
type: project_priority
title: Development Roadmap
description: Phase-based development plan for the Lua-to-Zig port, with dependencies and verification requirements.
tags: [roadmap, planning, phases]
timestamp: 2026-08-07T23:40:00Z
---

## Phase Overview

```
Phase A (DONE) --> Phase B (DONE) --> Phase C (DONE) --> Phase D (DONE) --> Phase E (DONE) --> Phase F (DONE) --> Phase G (DONE)
 Foundations       Tables           Front-End (loader)     VM               Runtime           Libs              Source compiler

                                                                                                                          v
                                                                                                                Phase H (DONE)
                                                                                                              Drop-in replacement
                                                                                                              & perf optimization
```

Work **top-down from the foundation**, validating each layer with tests before proceeding. Phases A–G and H are **complete**; the full upstream `lua/testes/*.lua` suite passes (PASS 19, FAIL 0) with zero memory leaks, full static defect resolutions (BUG-055 to BUG-064), and Zig 0.16.0 performance optimizations.

## Phase A -- Foundations (Complete)

- Module layout mirrors `lua/` C modules
- Single type model: one `lua_State`, one `lua_CFunction`, one `global_State`
- Real stack: `stack: []TValue` slice, `lua_checkstack` with `gpa.realloc`
- Correct instruction decode: proper bit shifts in GETARG/SETARG
- Version constants: Lua 5.5.1 (upstream `v5.5.1` tag, 2026-08-07)
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

All G.1–G.4 completed. Full Lua 5.5.0 lexer, recursive-descent parser, and code generator ported to Zig 0.16.0. `lua_load` now detects source vs bytecode and compiles text source via `luaD_protectedparser`. 73/73 tests pass, zero leaks.

### Phase G.1 — Lexer (`src/llex.zig`) ✅ DONE
### Phase G.2 — Parser (`src/lparser.zig`) ✅ DONE
### Phase G.3 — Code generator (`src/lcode.zig`) ✅ DONE
### Phase G.4 — Wire `lua_load` ✅ DONE

See `docs/frontend.md` for architecture decisions and `AGENTS.md` §Phase G for details.

## Phase H — Drop-in replacement gap closure ✅ COMPLETE (2026-08-07)

Phases A–G built a working, self-hosting Lua interpreter. Phase H closes the gap between "working" and "drop-in replacement for Lua 5.5.0". The gaps were identified by a systematic audit comparing `luazig` against `lua/lua.h`, `lua/lauxlib.h`, and the standard library C sources.

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

### H.3 — iolib stubs (LOW priority) ✅ DONE (revs 66-67)
- `io.flush` / `file:flush` — real flush
- `file:setvbuf` — real buffering
- `file:read("*n")` — ported PUC-Rio `read_number`

### H.4 — Reference system (MEDIUM priority) ✅ DONE (2026-07-14)
- `luaL_ref` / `luaL_unref` — needed by C extensions
- `LUA_NOREF` / `LUA_REFNIL` constants
- Port from `lua/lauxlib.c`

### H.5 — Missing C API functions (MEDIUM priority) ✅ DONE except `lua_pushexternalstring` (2026-07-14)
- `lua_atpanic` ✅ (`global_State.panic` added)
- `lua_version` ✅ (returns `LUA_VERSION_NUM` = 505.0)
- `lua_pushexternalstring` ✅ (2026-07-14) — non-interned `lua_TString` with `falloc`/`ud`; GC frees LSTRMEM bytes
- `lua_numbertocstring` ✅
- `luaL_checkversion_` ✅
- `luaL_callmeta` ✅
- `luaL_alloc` ✅
- `luaL_loadfilex` ✅ (reads via `std.Io`)
- `luaL_loadbufferx` ✅
- `luaL_loadstring` ✅
- `luaL_makeseed` ✅
- `luaL_getsubtable` ✅
- `luaL_requiref` ✅
- `luaL_dofile` ✅
- Buffer aux: `luaL_addstring` ✅, `luaL_buffinitsize` ✅, `luaL_prepbuffer` ✅, `luaL_bufflen` ✅, `luaL_buffaddr` ✅, `luaL_buffsub` ✅

### H.6 — CLI/REPL improvements (MEDIUM priority) ✅ DONE (2026-07-14)
- `src/luazig.zig` rewritten as a complete CLI driver (port of `lua/lua.c` arg handling)
- `-e <chunk>` ✅ (repeatable; runs before the script)
- `-l <name>` ✅ (registers in `package.loaded[name]` if `_G[name]` exists, else `require(name)`)
- `-i` ✅ (REPL after script / `-e` chunks; `-v` suppresses the REPL banner)
- `-v` ✅ (prints `LUA_COPYRIGHT`; suppresses REPL banner when combined with `-i`)
- `--` ✅ (stops option parsing; remaining args → script name + `arg[2..]`)
- `-` ✅ (reads script from stdin via `readAllStdin`)
- `arg` table ✅ (via H.1 `createargtable`; `arg[0]`=script, `arg[2..]`=extra args)
- Multi-line REPL ✅ (line-continuation via `LUA_ERRSYNTAX` + `<eof>` detection)
- REPL table expansion ✅ (`printValue` raw `lua_next`, depth cap 3)
- Supporting fixes: `luaL_tolstring` pushes a copy for strings (contract fix);
  `llex.lexerror` stores message in persistent `ls.buff` + ` near <eof>` suffix
  (fixes `lparser.error_expected`/`check_match` dangling-pointer garbage)
- Out of scope: readline/history editing; `pairs()`-based REPL expansion (raw `lua_next` used)
- Tests: `H.6 luaL_tolstring pushes a copy`, `H.6 CLI luazig behaves like the reference
  interpreter` (subprocess test; `build.zig` `test` step now builds the `luazig` exe)
- Status: 117/117 tests pass, zero leaks

### H.7 — Convenience macros (LOW priority) ✅ DONE (2026-07-14)
`lua_insert` ✅, `lua_remove` ✅, `lua_newtable` ✅, `lua_register` ✅, `lua_pushglobaltable` ✅, `lua_pushliteral` ✅, `lua_isnoneornil` ✅, `lua_isfunction` ✅, `lua_isthread` ✅, `lua_islightuserdata` ✅ — declared as `pub inline fn` in `src/lua.zig` (4 of 10 existed from earlier work)

### H.8 — Deprecated compatibility aliases (LOW priority) ✅ DONE (2026-07-14)
`lua_newuserdata` ✅, `lua_getuservalue` ✅, `lua_setuservalue` ✅, `lua_resetthread` ✅ — `pub inline fn` delegating to their modern equivalents
`lua_newuserdata`, `lua_getuservalue`, `lua_setuservalue`, `lua_resetthread`

### H.9 — Missing constants and exports (LOW priority) ✅ DONE (2026-07-14)
- `LUA_GNAME` ✅, `LUA_ERRFILE` ✅, `LUA_LOADED_TABLE` ✅, `LUA_PRELOAD_TABLE` ✅ (added in H.5)
- `LUA_NOREF` ✅, `LUA_REFNIL` ✅ (H.4)
- `LUAL_NUMSIZES` ✅ (H.5)
- `LUA_COPYRIGHT` ✅, `LUA_AUTHORS` ✅ (already present)
- `lua_ident` ✅ (2026-07-14) — `"$LuaVersion: ... $LuaAuthors: ... $"` as comptime `[]const u8`

### H.10 — GC completeness (LOW priority) ✅ DONE (2026-07-14)
- All `lua_gc` options handled (STOP/RESTART/COLLECT/COUNT/COUNTB/STEP/ISRUNNING/GEN/INC/GCPARAM) ✅
- GC constants fixed to Lua 5.5.0 (removed GCSETPAUSE/GCSETSTEPMUL, added GCISRUNNING=6/GCGEN=7/GCINC=8/GCPARAM=9) ✅
- LUA_GCPARAM get/set for all 6 sub-parameters (MINORMUL/MAJORMINOR/MINORMAJOR/PAUSE/STEPMUL/STEPSIZE) ✅
- `lua_gc` signature extended with 4th `value` parameter ✅
- `collectgarbage` baselib updated to Lua 5.5 option names ("param" with sub-options) ✅
- `luaL_checkoption` `def` made nullable (`?[]const u8`) for null-default support ✅

### Verification
Each H.x sub-phase must compile, pass all existing tests, and add focused tests for the new functionality.

## Post-Phase H — Upstream test-suite conformance ✅ COMPLETE (2026-07-19, updated 2026-08-07)

Phase H closed the C-API gap; the upstream `lua/testes/*.lua` suite now
passes in full — **PASS 19, FAIL 0, CRASH 0, TIMEOUT 0, CHECK 0**. The
remaining skipped files require the internal C test library `T` (a dev-only
test library not shipped in production Lua), the `all.lua` harness, or are
OOM stress tests (`heavy.lua`). See `docs/log.md` for the conformance and
5.5.1 upgrade history.

### Major blockers addressed in current session
- **Exit-code propagation**: `had_error` + `std.process.exit(1)` on uncaught
  errors (was exit 0).
- **Traceback on uncaught errors**: `msghandler` + `pcallWithHandler` routes
  all top-level calls through a message handler that builds tracebacks.
- **`lua_type` fix**: Returns `LUA_TNONE` for out-of-range indices (was
  `LUA_TNIL`), unblocking all argument validation.
- **`_G` global**: Set to globals table in `openbaselib` (was nil).
- **GC rewrite**: Back-pointers, thread-stack traversal, weak tables,
  auto-tuning.
- **Stack safety**: All push functions check capacity before writing.
- **`luaV_shift`**: Correct semantics for `|s| >= 64` → `0`.
- **Vararg fixes**: Table assignment syntax, `n` field validation.
- **Library registration**: All libraries registered in `package.loaded`.

### Remaining work

#### A. Architectural — Exact 64-bit integer type (dominant blocker)
`TValue` stores all numbers as `f64` (`lua_pushinteger` does
`@floatFromInt`). `math.maxinteger` / `math.mininteger` round-trip
inexactly, breaking every test relying on exact integer semantics:
`math`, `sort`, `verybig` (partially), `utf8`, `tpack`, `nextvar`, `big`,
`gengc`, `cstack`, `attrib`. Requires adding `.integer: i64` variant to
`TValue` + updating every operator/table-key/comparison/C-API path.

#### B. Real bugs (individually fixable)
- **Lexer**: `\x` escape with no hex digits doesn't error (`literals.lua`).
- **Parser**: `goto` label scoping (label inside block seen as visible,
  `goto.lua`).
- **Tablelib**: `table.unpack({}, 1, n=2^30)` mishandles extra named arg
  (`errors.lua`).
- **Os/iolib**: `os.getenv"PATH"` / `io.stdin` / `io.input` (`files.lua`).
- **Stringlib pattern matcher**: `string.find` with embedded NULs off-by-one
  (`pm.lua`).
- **VM/GC**: `constructs.lua` TIMEOUT — nondeterministic infinite loop when
  generating thousands of nested `and`/`or`/`not` expressions.
- **IO write**: `verybig.lua` native SIGABRT in `std.Io.Writer.fixedDrain`
  `@memcpy` while writing >64k programs (io-write buffer overflow).
- **CLI interpreter**: `main.lua` tests the standalone CLI itself.
- **Misc**: `calls/closure/big/gengc/db/events/locals` — assertion/error-object
  mismatches needing per-test diagnosis.

#### C. Unit tests (2 pre-existing failures, unrelated)
- `garbage collector mark and sweep`
- `H.5 lua_pushexternalstring … frees external bytes on GC`

### Strategy
1. Fix group B library/lexer bugs (low risk, clear wins).
2. Debug `constructs.lua` VM/GC hang (needs instrumentation).
3. Fix `pm.lua` string matcher NUL handling.
4. Plan integer-type `TValue` rework (group A) — the single highest-impact
   change, but requires a dedicated focused phase.
