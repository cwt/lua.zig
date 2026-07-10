---
type: architecture_guideline
title: Metatable System and Metamethod Dispatch
description: Metatable operations, TM_* event types, fast-access cache, and dispatch logic for arithmetic, comparison, and indexing.
tags: [metatables, metamethods, tags]
timestamp: 2026-07-10T00:00:00Z
---

## Metamethod Events (`lua/ltm.h`)

```c
typedef enum {
  TM_INDEX,       // __index
  TM_NEWINDEX,    // __newindex
  TM_GC,          // __gc
  TM_MODE,        // __mode (weak tables)
  TM_LEN,         // __len
  TM_EQ,          // __eq  (last fast-access method)
  TM_ADD,         // __add
  TM_SUB,         // __sub
  TM_MUL,         // __mul
  TM_MOD,         // __mod
  TM_POW,         // __pow
  TM_DIV,         // __div
  TM_IDIV,        // __idiv
  TM_BAND,        // __band
  TM_BOR,         // __bor
  TM_BXOR,        // __bxor
  TM_SHL,         // __shl
  TM_SHR,         // __shr
  TM_UNM,         // __unm
  TM_BNOT,        // __bnot
  TM_LT,          // __lt
  TM_LE,          // __le
  TM_CONCAT,      // __concat
  TM_CALL,        // __call
  TM_CLOSE,       // __close (to-be-closed variables)
  TM_N            // number of tag methods
} TMS;
```

## Fast-Access Cache

Each table has a `flags` field (8-bit mask). Bit `i` is `1` if the metatable does NOT have metamethod `TM_i` for `i` in `0..TM_EQ`.

```zig
fn checknoTM(t: *lua_Table, event: TMS) bool {
    return t.flags & (@as(u8, 1) << @intFromEnum(event)) != 0;
}
```

## API Functions

| Function | Status | Purpose |
|----------|--------|---------|
| `lua_getmetatable` | Stub | Get object's metatable |
| `lua_setmetatable` | Stub | Set table's metatable |
| `lua_getiuservalue` | Stub | Get user value |
| `lua_setiuservalue` | Stub | Set user value |

## Metamethod Lookup

```zig
fn gettm(L: *lua_State, mt: *lua_Table, event: TMS) ?TValue {
    if (checknoTM(mt, event)) return null;
    // rawget in metatable for the event name
    const tmname = getTMName(event);  // "__index", "__add", etc.
    return luaH_getstr(mt, tmname);
}
```

## Dispatch Points

Metamethods are checked at:

- **Arithmetic** (`lua_arith`): if operands are not both numbers, try `__add`, `__sub`, etc.
- **Comparison** (`lua_compare`): if types differ or raw compare fails, try `__eq`, `__lt`, `__le`
- **Indexing** (`lua_gettable`): if key not present, try `__index`
- **Setting** (`lua_settable`): if key not writable, try `__newindex`
- **Length** (`lua_len`): try `__len`
- **Concat** (`lua_concat`): try `__concat`
- **Call** (`lua_call`): try `__call` on non-function values
- **Close** (`lua_closeslot`): try `__close` for to-be-closed variables
- **GC** (`luaC_checkfinalizer`): call `__gc` on userdata during sweep

## Implementation Priority

Metamethod dispatch depends on:
1. Working tables (Phase B) — to store and look up metatables
2. Working string interning (Phase B) — metamethod names are interned strings
3. Working function calls (Phase D) — to invoke metamethod functions
4. Working error handling (Phase E) — to propagate errors from metamethods

Plan for Phase E: implement all `luaT_*` functions from `lua/ltm.c`.
