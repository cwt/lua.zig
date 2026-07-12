---
type: architecture_guideline
title: Table Implementation Design
description: Design for the lua_Table type with array part, open-addressing hash part, metatable cache, and the API surface.
tags: [tables, hashtable, phase-b]
timestamp: 2026-07-10T00:00:00Z
---

## Current State (updated 2026-07-10 — Phase B complete)

`lua_Table` is fully implemented in `src/ltable.zig` with both an array part and a
chained-scatter hash part. Semantics follow `lua/ltable.c` (array part for integer
keys `1..asize`, hash part for everything else), but the representation is idiomatic
Zig rather than the C inverted bit-packed layout (per AGENTS.md §0.1):

```zig
pub const Node = struct {
    key: TValue,
    val: TValue,
    next: i32, // absolute node index, -1 = end of chain
};

pub const lua_Table = struct {
    allocator: std.mem.Allocator,
    array: std.ArrayList(TValue),   // slot i (1-based) -> array[i-1]; nil = empty
    node: std.ArrayList(Node),      // hash part; entry present iff key != nil && val != nil
    lastfree: usize,                // backward scan pointer for free nodes
    lenhint: usize,                 // hint for #t
};
```

Implemented API (in `src/lua.zig`, delegating to `ltable`): `lua_createtable`,
`lua_gettable`/`lua_getfield`/`lua_geti`/`lua_rawget`/`lua_rawgeti`/`lua_rawgetp`,
`lua_settable`/`lua_setfield`/`lua_seti`/`lua_rawset`/`lua_rawseti`/`lua_rawsetp`,
`lua_next`, `lua_rawlen`. `get`/`set`/`getInt`/`setInt`/`next`/`getn` live in
`ltable.zig`. Hash part grows 2x (min 4) and rehashes on overflow. `next` traverses
array part by ascending index then hash part by node order. `getn` returns the Lua
border via binary search over the array part plus a hash fallback.

Note: `lua_gettable`/`lua_settable` currently do **raw** access (no `__index`/
`__newindex` dispatch) — that is Phase E. OOM in the set paths is swallowed (`catch {}`)
because the C API has no error return; this will move to the error-union mechanism in
Phase E.

## C Reference (`lua/ltable.c` + `lua/ltable.h`)

### Data Structures

The C `Table` has:
- `array`: inverted layout -- values at negative indices from midpoint, tags at positive indices from midpoint, with an unsigned between them for `#t` hint
- `node`: dynamic array of `Node` structs (hash part)
- `flags`: 8-bit mask for fast-access metamethod cache
- `ls`: log2 of `sizenode`
- `asize`: allocated array size
- `sizenode`: allocated hash size (power of 2)
- `lastfree`: pointer for hash insertion (linear probing)

```c
typedef struct Node {
  TValue i_val;
  TKey i_key;  // TValuefields + next index
} Node;
```

### Hash Algorithm

1. Compute main position: `luaH_mainposition(t, key)`
2. If target slot is free, use it
3. If occupied, find a free slot via `lastfree` pointer, link through `Node.u.next`
4. For `luaH_get`, traverse the linked chain from main position

### Array Part

- Stores integer keys in range `1 <= key <= asize`
- Two parallel arrays: values (decreasing from midpoint) and tags (increasing from midpoint)
- `#t` hint stored as unsigned between the arrays to avoid padding waste

### Key Operations

| Function | Purpose |
|----------|---------|
| `luaH_new` | Allocate new table |
| `luaH_get` | Generic get by TValue key |
| `luaH_getint` | Get by integer key |
| `luaH_getstr` | Get by string key |
| `luaH_getshortstr` | Get by short string (optimized) |
| `luaH_set` | Set with TValue key |
| `luaH_setint` | Set with integer key |
| `luaH_pset*` | Pre-set (check before modifying) |
| `luaH_resize` | Resize both array and hash parts |
| `luaH_next` | Iteration (next key-value pair) |
| `luaH_getn` | Length operator (#t) |

## Zig Implementation Strategy

### Phase 1: Basic Hash Part

```zig
pub const Node = struct {
    i_val: TValue,
    i_key: struct {
        val: TValue,
        next: i32,  // index of next node in collision chain, -1 = end
    },
};
```

### Hash Function

Port `luaH_mainposition` from `lua/ltable.c`:

```zig
fn mainposition(t: *lua_Table, key: *const TValue) usize {
    return switch (key.*) {
        .nil => unreachable,  // nil cannot be a key
        .boolean => |v| @as(usize, @intCast(@intFromBool(v))) & (t.hsize - 1),
        .number => |v| {
            // hash the raw bits of the number
            const bits = @as(u64, @bitCast(v));
            return lmod(@as(usize, @truncate(bits)), t.hsize);
        },
        .string => |s| {
            // use the precomputed string hash
            return lmod(s.?.hash, t.hsize);
        },
        // ... other types
    };
}
```

### Resize Strategy

Follow `luaH_resize` logic:
1. Compute new sizes for array and hash parts
2. Allocate new storage
3. Reinsert all existing elements into new arrays
4. Free old storage
5. Update `lastfree` for new hash part

### Array Part in Zig

Use `std.ArrayList(?TValue)` for simplicity rather than the inverted C layout:

```zig
array: std.ArrayList(?TValue),  // index 0 = Lua key 1, index n = Lua key n+1
```

### Speed Optimization: Metatable Cache

The `flags` field is a bitmask. Bit `i` is 1 if the metatable does NOT have metamethod `TM_i`. Checked before every metamethod lookup:

```zig
fn checknoTM(t: *lua_Table, event: TMS) bool {
    return (t.flags & (@as(u8, 1) << @intFromEnum(event))) != 0;
}
```

### Verification Tests

After implementation:
1. Create table with `lua_createtable`
2. Set value with integer key, retrieve with `lua_geti`/`lua_rawgeti`
3. Set value with string key, retrieve with `lua_getfield`/`lua_rawget`
4. Auto-expand array part by inserting at successively larger integer keys
5. Hash collision: insert many string keys, verify all retrievable
6. `lua_next` iteration over all key-value pairs
7. `lua_rawlen` returns correct array length
8. `lua_createtable(0, 10)` preallocates hash part
