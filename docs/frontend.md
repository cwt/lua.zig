---
type: architecture_guideline
title: Front-End Design — Lexer, Parser, Code Generator, Loader
description: Design for porting the Lua front-end (lualex.c, luaparser.c, luacode.c) or bytecode loader (lundump.c) to Zig.
tags: [lexer, parser, codegen, bytecode]
timestamp: 2026-07-10T00:00:00Z
---

## Current State

The bytecode loader (**Option B: `lundump.zig`**) has been fully implemented.

- **`src/lundump.zig`** (new): Implements `loadBinaryChunk` and the structural parser for precompiled Lua 5.5.1 bytecode chunks. Handles alignment, varints, strings (interned via `luaS_new`), instructions, constants, nested prototypes, upvalues, and debug info (lineinfo, abslineinfo, locvars).
- **`src/lua.zig`**: `lua_load` is now updated to inspect the first character of the input stream. If it matches `\x1b` (LUA_SIGNATURE[0]), it routes the request to the binary loader in `lundump.zig`.

*Note: Text compilation (Option A: lexer, parser, code generator) is not yet implemented.*


## Architecture Decision

Before implementing, decide between:

### Option A: Full Lexer/Parser/Codegen

Port the three C modules plus supporting infrastructure:

- `lualex.zig` — Lexical analyzer
- `luaparser.zig` — Recursive-descent parser
- `luacode.zig` — Code generator

**Pros**: Can run arbitrary Lua source code. No external tools needed.
**Cons**: Largest implementation effort. Approximately 67K lines of C (llex.c: 17K + lparser.c: 66K + lcode.c: 57K).

### Option B: Bytecode Loader Only

Port only `lundump.zig` and use precompiled bytecode chunks.

**Pros**: Much smaller (lundump.c: 11K). Faster path to running real code.
**Cons**: Requires an external `luac` to compile scripts. `luaL_dostring` is implemented but only executes precompiled bytecode (no source-text parser yet), so text source still fails load.

## Lexer Design (`lua/llex.c`)

### Key C Structures

```c
typedef struct Token {
  int token;          // token type (single char or RESERVED enum value)
  SemInfo seminfo;    // semantic value (number, string, etc.)
} Token;

typedef struct LexState {
  int current;        // current character
  int linenumber;     // input line counter
  Token t;            // current token
  Token lookahead;    // look-ahead token
  struct FuncState *fs;     // current function (parser)
  ZIO *z;             // input stream
  Mbuffer *buff;      // buffer for tokens
  TString *source;    // current source name
  // ...
} LexState;
```

### Zig Equivalent

```zig
pub const Token = struct {
    token: i32,
    seminfo: union {
        r: lua_Number,
        i: lua_Integer,
        ts: *lua_TString,
    },
};

pub const LexState = struct {
    current: i32,
    linenumber: i32,
    lastline: i32,
    t: Token,
    lookahead: Token,
    fs: ?*FuncState,
    L: *lua_State,
    buff: Mbuffer,
    source: ?*lua_TString,
    // ...
};
```

### Token Types

- Single-char tokens: their own ASCII value
- Reserved words: `TK_AND`, `TK_BREAK`, ..., `TK_WHILE` (starts at `UCHAR_MAX + 1`)
- Other terminals: `TK_IDIV`, `TK_CONCAT`, `TK_DOTS`, `TK_EQ`, `TK_GE`, `TK_LE`, `TK_NE`, `TK_SHL`, `TK_SHR`, `TK_DBCOLON`, `TK_EOS`
- Literals: `TK_FLT`, `TK_INT`, `TK_NAME`, `TK_STRING`

### Reserved Words

```
and, break, do, else, elseif, end, false, for, function,
global, goto, if, in, local, nil, not, or, repeat, return,
then, true, until, while
```

## Parser Design (`lua/lparser.c`)

### Key Structures

```c
typedef struct FuncState {
  Proto *f;            // current function header
  struct FuncState *prev;  // enclosing function
  struct LexState *ls;
  int pc;              // next code position
  int lasttarget;
  int nk, np;          // count of constants/protos
  short nactvar;       // active variable count
  lu_byte nups;        // upvalue count
  lu_byte freereg;     // first free register
  // ...
} FuncState;

typedef struct expdesc {
  expkind k;           // expression kind
  union { int info; lua_Integer ival; lua_Number nval; TString *strval; ... } u;
  int t;               // true jump list
  int f;               // false jump list
} expdesc;
```

### Expression Kinds

```
VVOID, VNIL, VTRUE, VFALSE, VK, VKFLT, VKINT, VKSTR,
VNONRELOC, VLOCAL, VVARGVAR, VGLOBAL, VUPVAL, VCONST,
VINDEXED, VVARGIND, VINDEXUP, VINDEXI, VINDEXSTR,
VJMP, VRELOC, VCALL, VVARARG
```

### Parser Structure

Recursive descent with one function per grammar rule:
- `luaY_parser` — entry point
- `mainfunc` — top-level function
- `body` — function body
- `block` / `statlist` / `statement`
- `expr` / `subexpr` — expression parsing with precedence climbing
- `simpleexp` / `primaryexp` / `singlevar` / `field` / `key`
- `funcargs` / `functioncall`

## Code Generator (`lua/lcode.c`)

### Key Functions

| Function | Purpose |
|----------|---------|
| `luaK_codeABC` | Emit iABC format instruction |
| `luaK_codeABx` | Emit iABx format instruction |
| `luaK_codeAsBx` | Emit iAsBx format instruction |
| `luaK_dischargevars` | Convert variable to register |
| `luaK_exp2reg` | Force expression result into register |
| `luaK_exp2nextreg` | Expression to next free register |
| `luaK_goiftrue` | Generate jump-if-true patchlist |
| `luaK_goiffalse` | Generate jump-if-false patchlist |
| `luaK_patchlist` / `luaK_patchtohere` | Jump-list patching |
| `luaK_jump` | Emit unconditional jump, return patch position |
| `luaK_storevar` | Store value to variable |
| `luaK_setreturns` | Handle multiple return values |

### Register Allocation

Lua uses virtual registers (slots in the stack frame). `freereg` tracks the next free register. Expression results are assigned to consecutive registers starting from `freereg`. On function entry, parameters occupy registers 0..n-1.

## Bytecode Loader (`lua/lundump.c`)

### Format

Precompiled Lua chunks have the format:

```
  signature:     "\x1bLua"
  version:       1 byte (major*16 + minor)
  format:        1 byte (0 = official)
  data:          6 bytes (LUAC_DATA: 0x19 0x93 0x0D 0x0A 0x1A 0x0A)
  instruction_size: 1 byte (sizeof(Instruction) = 4)
  size_int:      sizeof(int)
  size_size_t:   sizeof(size_t)
  size_Instruction: sizeof(Instruction)
  size_lua_Integer: sizeof(lua_Integer)
  size_lua_Number:  sizeof(lua_Number)
  LUAC_INT:      (int)0x5678  (endianness check)
  LUAC_NUM:      (lua_Number)370.5  (float format check)
  
  -- Prototype body
  source_name:   string
  linedefined:   int
  lastlinedefined: int
  nups:          byte
  numparams:     byte
  isvararg:      byte
  maxstacksize:  byte
  code:          list of Instructions
  constants:     list of TValues
  upvalues:      list of strings
  protos:        list of Protos (recursive)
  debug info:    lineinfo, abslineinfo, locvars, upvalue names
```

### Key Function

```c
LClosure *luaU_undump(lua_State *L, ZIO *Z, Table *anchor,
                       const char *name, int fixed);
```

Returns a `LClosure` (wrapping a `Proto`) that can be executed by `lvm.run`.

### Verification Load Values

```c
#define LUAC_INT   (-0x5678)
#define LUAC_NUM   (-370.5)
```

These values are written at dump time and checked at load time to detect endianness and float-format mismatches.

## Proto Structure

The `lua_Proto` is the compiled representation of a Lua function:

```zig
pub const lua_Proto = struct {
    source: ?[]const u8,
    size: usize,
    lineDefined: i32,
    lastLineDefined: i32,
    numParams: i32,
    isVarArg: bool,
    maxStackSize: i32,
    code: []lvm.Instruction,     // bytecode
    k: ?[]TValue,                 // constant pool
    p: ?*lua_Proto,               // nested protos (linked list)
};
```
