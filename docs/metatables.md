---
type: architecture_guideline
title: Metatable System and Metamethod Dispatch
description: Metatable operations, TM_* event types, fast-access cache, and dispatch logic for arithmetic, comparison, and indexing.
tags: [metatables, metamethods, tags]
timestamp: 2026-07-10T00:00:00Z
---

## Metamethod Events (`lua/ltm.h`)

```zig
pub const TMS = enum(u5) {
    INDEX = 0,    // __index
    NEWINDEX = 1, // __newindex
    GC = 2, MODE = 3, LEN = 4, EQ = 5,    // fast-access (≤ EQ cached in flags)
    ADD = 6, SUB = 7, MUL = 8, MOD = 9, POW = 10,
    DIV = 11, IDIV = 12,
    BAND = 13, BOR = 14, BXOR = 15, SHL = 16, SHR = 17,
    UNM = 18, BNOT = 19, LT = 20, LE = 21,
    CONCAT = 22, CALL = 23, CLOSE = 24,
    pub const N = 25;
};
```

## Fast-Access Cache

Each table has a `flags` field (8-bit mask). Bit `i` is `1` if the metatable does **not** have metamethod `TMS_i` for `i ≤ TMS.EQ`.

```zig
pub inline fn checknoTM(mt: ?*lua_Table, event: TMS) bool {
    if (mt) |m| return (m.flags & (1 << @intCast(@intFromEnum(event)))) != 0;
    return true;
}
```

## Core Dispatch Functions (src/ltm.zig)

### `luaT_gettmbyobj` — look up a metamethod on any value

Returns the metamethod TValue (or `.nil`) by checking the value's metatable (or the global per-type metatable for primitive types).

### `luaT_callTM` / `luaT_callTMres` — call a metamethod

Push function + arguments onto the stack, call via `luaD_call`, and optionally capture the result.

### `luaT_trybinTM` — binary arithmetic metamethod dispatch

Tries `p1`'s metamethod first, falls back to `p2`'s, errors if neither has it.

### `luaT_callorderTM` — comparison metamethod dispatch

Returns a `bool` result from a `__lt` or `__le` metamethod call.

### `luaT_equalobj` — equality with `__eq` dispatch

Handles table and userdata equality with `__eq` fallback.

### `luaT_lt` / `luaT_le` — ordered comparisons

Fast-path for numeric/string, fall back to `luaT_callorderTM`.

### `luaV_gettable` — metamethod-aware table read (Phase E)

```zig
pub fn luaV_gettable(L: *lua_State, t: TValue, key: TValue, res: usize) !void
```

Implements `result = t[key]` with full `__index` chain following:
1. If `t` is a table and `key` exists → return value directly.
2. If `__index` is absent → return nil.
3. If `__index` is a function → call it, write result to `L.stack[res]`.
4. If `__index` is a table → recurse (up to `MAXTAGLOOP = 2000` iterations).
5. Error `RuntimeError` on chain-too-long or non-table without `__index`.

### `luaV_settable` — metamethod-aware table write (Phase E)

```zig
pub fn luaV_settable(L: *lua_State, t: TValue, key: TValue, val: TValue) !void
```

Implements `t[key] = val` with full `__newindex` chain following:
1. If `t` is a table and `key` already exists → raw write (no `__newindex`).
2. If `__newindex` is absent → raw insert.
3. If `__newindex` is a function → call it.
4. If `__newindex` is a table → recurse.

## C API — Table Access

| Function | Metamethods? | Purpose |
|----------|:------------:|---------|
| `lua_gettable` | `__index` | Keyed read (stack key, overwrites key slot) |
| `lua_getfield` | `__index` | String-key read |
| `lua_geti` | `__index` | Integer-key read |
| `lua_rawget` | raw | Keyed read, no metamethods |
| `lua_rawgeti` | raw | Integer-key read, no metamethods |
| `lua_rawgetp` | raw | Pointer-key read, no metamethods |
| `lua_settable` | `__newindex` | Keyed write |
| `lua_setfield` | `__newindex` | String-key write |
| `lua_seti` | `__newindex` | Integer-key write |
| `lua_rawset` | raw | Keyed write, no metamethods |
| `lua_rawseti` | raw | Integer-key write, no metamethods |
| `lua_rawsetp` | raw | Pointer-key write, no metamethods |

## VM Opcode Integration

All table-access opcodes in `src/lvm.zig` now call `luaV_gettable` / `luaV_settable`:

- `GETTABLE`, `GETI`, `GETFIELD`, `GETTABUP` -> `luaV_gettable`
- `SETTABLE`, `SETI`, `SETFIELD`, `SETTABUP` -> `luaV_settable`
- `SELF` -> `luaV_gettable` (method lookup)

## Stack Index Convention (Phase E fix)

`idxPtr` now decodes positive indices as **frame-relative** when inside a call frame (`L.ci` is non-null): index 1 = `L.stack[ci.base]`, index 2 = `L.stack[ci.base + 1]`, etc. At the top level (no active frame) positive indices are treated as 1-based absolute stack indices. Upvalue pseudo-indices (`lua_upvalueindex(n)` = `LUA_REGISTRYINDEX - n`) resolve to the current C closure's `upvals[n-1]`.

## New C API Additions (Phase E)

| Function | Purpose |
|----------|---------|
| `lua_pushcfunction(L, f)` | Push a C function with 0 upvalues |
| `lua_upvalueindex(n)` | Convert upvalue n to pseudo-index |
| `lua_getupvalue(L, _, n)` | Get upvalue n of current C closure onto stack |
| `lua_setupvalue(L, _, n)` | Set upvalue n of current C closure from stack |
| `lua_getmetatable(L, idx)` | Get metatable of value at idx |
| `lua_setmetatable(L, idx)` | Set metatable of value at idx (pops mt from stack) |

## Test Coverage

```
test "__index function metamethod via C API"    PASS
test "__index table chain metamethod via C API" PASS
test "__newindex function metamethod via C API" PASS
```

## Remaining Work

- `__len`, `__concat`, `__call` dispatch not yet tested.
- `__gc` needs real GC mark/sweep (Phase F).
- Metamethod caching (flag invalidation on `lua_setmetatable`) partially done via `tbl.flags = 0`.
