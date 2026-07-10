---
type: architecture_guideline
title: String Interning Design
description: String deduplication for lua_TString, short vs long strings, hash computation, and the global string table.
tags: [strings, interning, hashtable]
timestamp: 2026-07-10T00:00:00Z
---

## Purpose

Lua interns short strings so that:
1. String equality comparisons are pointer comparisons (O(1) instead of O(n))
2. Table lookups with string keys can use the string pointer directly
3. Memory is saved by deduplicating identical strings

## C Reference (`lua/lstring.c` + `lua/lstring.h`)

### Split: Short vs Long Strings

- **Short strings** (max 40 bytes by default): interned in the global string table
  - Tagged as `LUA_VSHRSTR`
  - Pointer equality via `eqshrstr`
  - Stored in `stringtable` hash in `global_State`
  - Extra field used for reserved word ID (positive = reserved word index)

- **Long strings**: not interned; allocated directly
  - Tagged as `LUA_VLNGSTR`
  - Equality must compare byte-by-byte
  - `luaS_hashlongstr` caches the hash in `TString.hash`

### TString Layout (C)

```c
typedef struct TString {
  CommonHeader;        // GCObject header: tt, marked, gcnext
  lu_byte extra;       // reserved words for short strings; 0 for long
  lu_byte shrlen;      // length for short strings
  unsigned int hash;
  union { size_t lnglen; struct TString *hnext; } u;
  char contents[];     // flexible array member with string bytes
} TString;
```

### String Table

```c
typedef struct stringtable {
  TString **hash;
  int nuse;    // number of elements
  int size;    // array size (power of 2)
} stringtable;
```

## Zig Implementation Strategy

### lua_TString

```zig
pub const lua_TString = struct {
    // GC common header (via GCObject)
    tt: i8,
    marked: u8,
    // String data
    s: []const u8,       // the string bytes (slice, NOT null-terminated)
    len: usize,          // string length
    hash: u32,           // precomputed hash
    extra: u8,           // reserved word index for short strings
    hnext: ?*lua_TString, // next in hash chain
};
```

### String Table

```zig
pub const stringtable = struct {
    hash: []?*lua_TString,  // open hash table
    nuse: i32,              // number of strings in use
    size: i32,              // hash array size (power of 2)
};
```

Stored in `global_State.strt`.

### Hash Computation

Port `luaS_hash` from `lua/lstring.c`:

```zig
fn hashString(s: []const u8, seed: usize) u32 {
    var h: u32 = @as(u32, @truncate(seed ^ @as(usize, @intCast(s.len))));
    for (s) |c| {
        h = h ^ (c << (h & 3));
        h = h ^ (h >> 5);
    }
    return h;
}
```

### Key Functions

| Zig function | C equivalent | Purpose |
|-------------|-------------|---------|
| `luaS_newlstr` | `luaS_newlstr` | Create/get string with explicit length |
| `luaS_new` | `luaS_new` | Create/get null-terminated string |
| `luaS_resize` | `luaS_resize` | Resize string table hash |
| `luaS_hash` | `luaS_hash` | Compute string hash |
| `luaS_init` | `luaS_init` | Initialize string table |
| `luaS_remove` | `luaS_remove` | Remove string from table (GC) |

### Lookup Algorithm

```
function newlstr(L, s, len):
    if len > LUAI_MAXSHORTLEN:
        // long string: allocate directly, no interning
        return allocateLongString(L, s, len)
    
    // short string: check string table
    hash = hashString(s, G(L).seed)
    bucket = hash & (G(L).strt.size - 1)
    entry = G(L).strt.hash[bucket]
    while entry != null:
        if entry.len == len and entry.hash == hash:
            if mem.eql(u8, entry.s, s):
                return entry    // found
        entry = entry.hnext
    
    // not found: create new entry
    newstr = allocateShortString(L, s, len, hash)
    newstr.hnext = G(L).strt.hash[bucket]
    G(L).strt.hash[bucket] = newstr
    G(L).strt.nuse += 1
    
    // resize if load factor too high
    if G(L).strt.nuse > G(L).strt.size:
        luaS_resize(L, G(L).strt.size * 2)
    
    return newstr
```

### Impact on lua_pushstring

Currently `lua_pushlstring` allocates a new `lua_TString` every time. After interning:

1. Hash the input string
2. Look up in `global_State.strt`
3. If found, return existing string (free the unused allocation if any)
4. If not found, create new entry, insert into hash table

This ensures that `lua_pushstring(L, "hello")` always returns the same pointer.

### Verification

1. Push same literal twice, compare pointers: must be equal
2. Push literals with same content but from different sources: must be same pointer
3. Push long string (>40 bytes): not interned, different allocations
4. String table resize still preserves all existing strings
