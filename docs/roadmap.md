---
type: project_priority
title: Development Roadmap
description: Phase-based development plan for the Lua-to-Zig port, with dependencies and verification requirements.
tags: [roadmap, planning, phases]
timestamp: 2026-07-10T00:00:00Z
---

## Phase Overview

```
Phase A (DONE) --> Phase B --> Phase C --> Phase D --> Phase E --> Phase F
 Foundations       Tables      Front-End      VM        Runtime       Libs
                                        ^
                                   (or loader first)
```

Work **top-down from the foundation**, validating each layer with tests before proceeding.

## Phase A -- Foundations (Complete)

- Module layout mirrors `lua/` C modules
- Single type model: one `lua_State`, one `lua_CFunction`, one `global_State`
- Real stack: `stack: []TValue` slice, `lua_checkstack` with `gpa.realloc`
- Correct instruction decode: proper bit shifts in GETARG/SETARG
- Version constants: Lua 5.5.1
- juicy-main entry: `src/luazig.zig` with `std.process.Init`
- Builds exe + lib + tests
- 7 passing tests: type checks + stack round-trip

## Phase B -- Tables and String Interning (NEXT)

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

## Phase F -- Standard Libraries

Implement library bodies in `src/lib/*.zig`:

- baselib: `print`, `assert`, `type`, `pairs`, `ipairs`, `tostring`, `tonumber`, etc. — **DONE**
- mathlib: `math.sin`, `math.cos`, `math.sqrt`, `math.random`, etc. — **DONE** (2026-07-11)
- stringlib: pattern matching, `string.find`, `string.gsub`, `string.match`, etc.
- tablelib: `table.insert`, `table.remove`, `table.sort`, `table.concat`, etc.
- utf8lib: UTF-8 character/byte iteration
- oslib: `os.clock`, `os.date`, `os.time`, `os.execute` etc.
- iolib: file I/O via `std.Io` instead of C FILE*
- corolib: coroutine creation/resume/yield
- loadlib: `require`, `package`, module loading
- bit32: bitwise operations — **DONE** (2026-07-11, ported from Lua 5.3 `lbitlib.c`)
- debug: debug API

Wire `iolib`/`oslib` to `std.Io`/`init.io`.
