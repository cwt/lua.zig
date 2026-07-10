---
type: architecture_guideline
title: Stack Design
description: The Lua stack as a Zig slice, indexing semantics, growth strategy, and how C pointer arithmetic maps to slice operations.
tags: [stack, slices, lua_state]
timestamp: 2026-07-10T00:00:00Z
---

## Design

The Lua stack is a **contiguous `[]TValue` slice** owned by `lua_State`:

```zig
pub const lua_State = struct {
    stack: []TValue,      // the stack slice
    top: usize,           // index of first empty slot (stack top)
    stack_last: usize,    // index of last usable slot
    // ...
};
```

## Indexing

### C Style
- Positive: `1` = first stack slot, `n` = nth slot
- Negative: `-1` = top, `-n` = nth from top
- Pseudo-indices: `LUA_REGISTRYINDEX` = `-(INT_MAX/2 + 1000)` for globals/registry

### Zig Implementation
Conversion functions in `src/lua.zig`:

```zig
fn idxPtr(L: *lua_State, idx: i32) ?*TValue {
    if (idx > 0) {
        const u = @as(usize, @intCast(idx - 1));
        if (u < L.top) return &L.stack[u];
    } else if (idx < 0) {
        const abs = @as(usize, @intCast(-idx));
        if (abs <= L.top) return &L.stack[L.top - abs];
    }
    return null;
}
```

Key difference: `idxPtr` returns `?*TValue` (nullable pointer), checked with `orelse`. The C reference uses unchecked pointer arithmetic and relies on the caller to validate indices.

## Stack Operations

All implemented in `src/lua.zig` as plain functions (not methods):

| Function | Signature | Description |
|----------|-----------|-------------|
| `lua_gettop` | `(L: *lua_State) i32` | Returns `L.top` as i32 |
| `lua_settop` | `(L: *lua_State, idx: i32) void` | Sets top; nil-fills or truncates |
| `lua_pushvalue` | `(L: *lua_State, idx: i32) void` | Copies value at idx to top |
| `lua_rotate` | `(L: *lua_State, idx: i32, n: i32) void` | Rotates stack segment (stub) |
| `lua_copy` | `(L: *lua_State, fromidx: i32, toidx: i32) void` | Copies between indices |
| `lua_checkstack` | `(L: *lua_State, n: i32) i32` | Grows stack if needed |
| `lua_xmove` | `(L: *lua_State, from: *lua_State, n: i32) void` | Transfers values between states |
| `lua_pop` | `(L: *lua_State, n: i32) void` | Decrements top by n |

## Stack Growth

`lua_checkstack` uses `gpa.realloc`:

```zig
pub fn lua_checkstack(L: *lua_State, n: i32) i32 {
    const needed = L.top + @as(usize, @intCast(n));
    if (needed <= L.stack.len) return 1;
    const new_cap = needed + LUA_MINSTACK;
    L.stack = L.allocator.realloc(L.stack, new_cap) catch return 0;
    L.stack_last = L.stack.len - 1;
    return 1;
}
```

- Returns `0` (failure) on OOM, not `catch unreachable`
- Grows by at least `LUA_MINSTACK` (20) extra slots
- Updates `stack_last` to the new capacity boundary

## Push Functions

Each push function writes to `L.stack[L.top]` and increments `L.top`:

| Function | TValue variant written |
|----------|----------------------|
| `lua_pushnil` | `.nil` |
| `lua_pushnumber` | `.number` |
| `lua_pushinteger` | `.number` (converted to f64) |
| `lua_pushboolean` | `.boolean` |
| `lua_pushstring` | `.string` (allocates `lua_TString`) |
| `lua_pushlstring` | `.string` (with explicit length) |
| `lua_pushcclosure` | `.function` → `.c` variant |
| `lua_pushlightuserdata` | `.lightud` |
| `lua_pushthread` | `.thread` |
| `lua_createtable` | `.table` (allocates `lua_Table`) |
| `lua_newuserdatauv` | `.userdata` (allocates `lua_Udata`) |

## Absolute Index Conversion

```zig
pub fn lua_absindex(L: *lua_State, idx: i32) i32 {
    if (idx >= 1 and @as(usize, @intCast(idx)) <= L.top) return idx;
    return @as(i32, @intCast(L.top)) + 1 + idx;
}
```

## Macros from C That Map to Direct Calls

| C macro | Zig equivalent |
|---------|----------------|
| `lua_pop(L,n)` → `lua_settop(L, -(n)-1)` | `lua_pop(L, n)` (direct function) |
| `lua_tonumber(L,i)` → `lua_tonumberx(L,i,NULL)` | `lua_tonumber(L, i)` (wrapper) |
| `lua_tointeger(L,i)` → `lua_tointegerx(L,i,NULL)` | `lua_tointeger(L, i)` (wrapper) |
| `lua_pushliteral(L,s)` → `lua_pushstring(L,"" s)` | `lua_pushstring(L, s)` (slice already literal) |
| `lua_pushcfunction(L,f)` → `lua_pushcclosure(L,f,0)` | `lua_pushcclosure(L, f, 0)` |
