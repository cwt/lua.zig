---
type: database_schema
title: Type Model — Mapping Lua's C Type System to Zig
description: Complete mapping of Lua's C type hierarchy (lobject.h, lua.h, lstate.h) to Zig 0.16.0 tagged unions, structs, and optionals.
tags: [types, tvalue, lua_state, zig]
timestamp: 2026-07-10T00:00:00Z
---

## TValue — The Central Value Representation

### C Reference (`lobject.h`)
```c
typedef union Value {
  struct GCObject *gc;  /* collectable objects */
  void *p;              /* light userdata */
  lua_CFunction f;      /* light C functions */
  lua_Integer i;        /* integer numbers */
  lua_Number n;         /* float numbers */
  lu_byte ub;
} Value;

#define TValuefields  Value value_; lu_byte tt_
typedef struct TValue { TValuefields; } TValue;
```

### Zig Implementation (`src/lua.zig`)
```zig
pub const TValue = union(enum) {
    nil: void,
    boolean: bool,
    lightud: ?*anyopaque,
    number: f64,
    string: ?*lua_TString,
    table: ?*lua_Table,
    function: ?*lua_Closure,
    userdata: ?*lua_Udata,
    thread: ?*lua_State,
    upval: ?*UpVal,
    proto: ?*lua_Proto,
};
```

### Type Tag Constants
All `LUA_T*` constants are re-exported from `llimits.zig` through `lua.zig`:

| Constant | Value | TValue variant |
|----------|-------|----------------|
| `LUA_TNONE` | -1 | (sentinel, no variant) |
| `LUA_TNIL` | 0 | `.nil` |
| `LUA_TBOOLEAN` | 1 | `.boolean` |
| `LUA_TLIGHTUSERDATA` | 2 | `.lightud` |
| `LUA_TNUMBER` | 3 | `.number` |
| `LUA_TSTRING` | 4 | `.string` |
| `LUA_TTABLE` | 5 | `.table` |
| `LUA_TFUNCTION` | 6 | `.function` |
| `LUA_TUSERDATA` | 7 | `.userdata` |
| `LUA_TTHREAD` | 8 | `.thread` |

Internal types (not exposed via C API):
| Constant | Value | TValue variant |
|----------|-------|----------------|
| `LUA_TUPVAL` | 9 | `.upval` |
| `LUA_TPROTO` | 10 | `.proto` |

## lua_State — The Interpreter State

### C Reference (`lstate.h` + `lua.h`)
A deeply opaque `lua_State*` with all fields hidden behind macros and inline functions.

### Zig Implementation (`src/lua.zig`)
A flat struct with all fields public (Zig has no information hiding):

```zig
pub const lua_State = struct {
    tt: i8,                    // GC header: type tag
    marked: u8,                // GC header: mark bits
    gch: u32,                  // GC header: generic collector header
    allowhook: u8,             // debug hook enabled
    status: u8,                // thread status (LUA_OK, LUA_YIELD, etc.)
    top: usize,                // stack top index
    l_G: ?*global_State,       // linked global state
    ci: ?*CallInfo,            // call info chain
    stack: []TValue,           // stack as slice (key design decision)
    stack_last: usize,         // index of last usable stack slot
    openupval: ?*UpVal,        // list of open upvalues
    tbclist: usize,            // list of to-be-closed variables
    gclist: ?*GCObject,        // list of collectable objects
    twups: ?*lua_State,        // list of threads with upvalues
    errorJmp: ?*lua_longjmp,   // error jump buffer (retained for compat, unused)
    base_ci: CallInfo,         // pre-allocated call info
    hook: ?lua_Hook,           // debug hook function
    errfunc: isize,            // error function index
    nCcalls: u32,              // number of C call levels
    oldpc: i32,                // last pc for debug
    nci: i32,                  // number of call infos
    basehookcount: i32,        // base hook count
    hookcount: i32,            // hook count
    hookmask: u8,              // hook mask (bitfield)
    transferinfo: struct {     // value transfer tracking
        ftransfer: i32,
        ntransfer: i32,
    },
    allocator: std.mem.Allocator,  // Zig allocator (replaces lua_Alloc)
};
```

### Key Design Difference: Stack as Slice
- **C**: `StkId` is `TValue*` pointer arithmetic; stack is a malloc'd block accessed via offset macros.
- **Zig**: `stack: []TValue` is a slice. Indexing is `L.stack[idx]`. `stack_last` tracks the last valid index. Growth uses `gpa.realloc`.

## global_State

### C Reference (`lstate.h`)
Contains the GC machinery, string table, registry, panic handler, and root Lua state.

### Zig Implementation (`src/lstate.zig`)
Full struct with all GC lists, string table, registry, memory counters. Currently separate from the placeholder in `lua.zig`:

```zig
pub const global_State = struct {
    frealloc: llimits.lua_Alloc,  // to be replaced with std.mem.Allocator
    ud: ?*anyopaque,
    GCtotalbytes: usize,
    GCdebt: usize,
    GCmarked: usize,
    GCmajorminor: i32,
    strt: stringtable,
    l_registry: lua.TValue,
    nilvalue: lua.TValue,
    seed: usize,
    currentwhite: u8,
    gcstate: u8,
    gckind: u8,
    gcstopem: u8,
    gcstp: u8,
    gcemergency: u8,
    allgc: ?*lua.GCObject,
    sweepgc: ?*lua.GCObject,
    finobj: ?*lua.GCObject,
    gray: ?*lua.GCObject,
    grayagain: ?*lua.GCObject,
    weak: ?*lua.GCObject,
    ephemeron: ?*lua.GCObject,
    allweak: ?*lua.GCObject,
    tobefnz: ?*lua.GCObject,
    fixedgc: ?*lua.GCObject,
    twups: ?*lua.lua_State,
    panic: ?lua.lua_CFunction,
    memerrmsg: ?lua.lua_TString,
    mainth: lua.lua_State,
    warnf: ?lua.lua_WarnFunction,
    ud_warn: ?*anyopaque,
};
```

**TODO**: Merge `lua.zig`'s placeholder `global_State` with this full struct. The placeholder is a compile-time stub; the real struct must be used once GC is implemented.

## Function Types

| C typedef | Zig equivalent | Location |
|-----------|---------------|----------|
| `lua_CFunction` | `*const fn (*lua_State) i32` | `lua.zig:34` |
| `lua_KFunction` | `*const fn (*lua_State, i32, lua_KContext) i32` | `lua.zig:35` |
| `lua_Reader` | `*const fn (*lua_State, ?*anyopaque, ?*usize) ?[]const u8` | `lua.zig:36` |
| `lua_Writer` | `*const fn (*lua_State, ?*anyopaque, usize, ?*anyopaque) i32` | `lua.zig:37` |
| `lua_Hook` | `*const fn (*lua_State, ?*lua_Debug) void` | `lua.zig:38` |
| `lua_Alloc` | `*const fn (?*anyopaque, ?*anyopaque, usize, usize) ?*anyopaque` | `llimits.zig:23` (to be retired) |

## GCUnion — Collectable Object Union

### C Reference (`lstate.h`)
```c
typedef union GCUnion {
  GCObject gc;
  TString ts;
  Udata u;
  Closure cl;
  Table h;
  Proto p;
  lua_State th;
  UpVal upv;
} GCUnion;
```

### Zig Implementation (`src/lstate.zig`)
```zig
pub const GCUnion = union(enum) {
    gc: lua.GCObject,
    ts: lua.lua_TString,
    u: lua.lua_Udata,
    cl: lua.lua_Closure,
    h: lua.lua_Table,
    p: lua.lua_Proto,
    th: lua.lua_State,
    upv: lua.UpVal,
};
```

## String Types

| C type | Zig type | Notes |
|--------|----------|-------|
| `TString` | `lua_TString` | `s: []const u8, len: usize` — no null terminator |
| `Udata` | `lua_Udata` | `len: usize, metatable: ?*anyopaque` |

## Table Types

| C type | Zig type | Notes |
|--------|----------|-------|
| `Table` | `lua_Table` | `flags, ls, array: ArrayList(?TValue), i_size, nsize` — hash part not implemented |
| `Node` | (not yet) | Hash node — not yet ported from `ltable.h` |

## Closure Types

| C type | Zig type | Notes |
|--------|----------|-------|
| `CClosure` | `lua_CClosure` | `f: lua_CFunction, nups: u8` |
| `LClosure` | (via `lua_Proto` in `.lua` variant) | Lua closures use `lua_Proto` directly |
| `Closure` | `lua_Closure` | `union(enum) { c: *lua_CClosure, lua: *lua_Proto }` |
| `UpVal` | `UpVal` | `t: TValue, uv: ?*UpVal` |
