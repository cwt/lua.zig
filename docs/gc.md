---
type: architecture_guideline
title: Garbage Collector Design
description: Porting Lua's tri-color incremental/generational GC to Zig. GC lists, write barriers, finalization, weak tables, ephemerons.
tags: [gc, memory, garbage-collection]
timestamp: 2026-07-10T00:00:00Z
---

## Overview

Lua uses a **tri-color mark-and-sweep** garbage collector with both **incremental** and **generational** modes. All GC-managed objects carry a `CommonHeader` with type tag, mark bits, and a GC list link.

## Objects

Every collectable object starts with `GCObject`:

```zig
pub const GCObject = struct {
    tt: i8,         // type tag
    marked: u8,     // color + generation bits
    gch: u32,       // generic collector header (gcnext pointer)
};
```

Collectable types: `lua_TString`, `lua_Udata`, `lua_Closure`, `lua_Table`, `lua_Proto`, `lua_State`, `UpVal`.

The `GCUnion` in `lstate.zig` unifies them:

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

## GC Lists (in global_State)

| List | Contents |
|------|----------|
| `allgc` | All objects not marked for finalization. Subdivided into generations: `survival` -> `old` -> `old1` -> `reallyold` |
| `finobj` | Objects marked for finalization (userdata with `__gc` metamethod). Subdivided similarly. |
| `tobefnz` | Objects ready to be finalized |
| `fixedgc` | Objects never collected (short strings like reserved words) |
| `gray` | Gray objects waiting to be visited |
| `grayagain` | Objects to revisit at atomic phase (black objects with write barrier, weak tables, threads) |
| `weak` | Weak tables to clear |
| `ephemeron` | Ephemeron tables (weak keys, strong values with white->white entries) |
| `allweak` | Tables with weak keys and/or values |

## Colors

| Color | Meaning |
|-------|---------|
| White | Not visited. Two white bits for incremental GC (current/next cycle) |
| Gray | Visited but not yet scanned (children not marked) |
| Black | Fully scanned |

## Write Barriers

Lua uses both forward and backward barriers:

- **Barrierfast**: for tables (most common store). Marks the black table gray so it gets rescanned.
- **Barrierback**: for all other stores. Marks the object being stored into black if the value is white.
- **Barrierfix**: for generational mode fix-up.

## GC Steps

The incremental GC has phases:
1. **Propagate**: mark from gray roots
2. **Atomic**: (stop-the-world) finish marking, clear weak tables
3. **Sweep**: sweep allgc list
4. **Finalize**: call finalizers on tobefnz

## Generational Mode

Generations:
- **Young** (new): collected every minor GC
- **Survival**: survived one collection
- **Old**: survived two collections
- **Really old**: old for multiple cycles

Minor GC collects young objects only. Major GC collects everything.

## Implementation Status

`global_State` in `lstate.zig` already has all GC fields defined. But:
- No GC cycle is ever triggered
- No objects are tracked on GC lists
- `lua_gc` is a stub
- `lua_close` only frees the stack, not individual objects
- String allocation does not register the string with GC

### TODO for Phase E

1. Implement GC object allocation (`luaM_new*` wrappers) that register with `allgc`
2. Implement `luaC_step` / `luaC_fullgc` cycle management
3. Implement tri-color marking functions
4. Implement sweep phase
5. Implement write barriers for table stores and upvalue stores
6. Implement finalization (userdata `__gc`)
7. Implement weak table and ephemeron handling
8. Port both incremental and generational modes from `lua/lgc.c`
9. Wire `lua_gc` API to real GC operations
