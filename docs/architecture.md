---
type: architecture_guideline
title: Project Architecture & Zig Design Philosophy
description: High-level architecture of the luazig port, mandatory coding rules, and how each C module maps to Zig.
tags: [architecture, zig, rules, design]
timestamp: 2026-07-10T00:00:00Z
---

## Core Principle

This is a **semantic port**, not a transliteration. Every function must ask *"What would a native Zig programmer write here?"* before writing a single line. The C reference (`lua/`) is the authority for *behavior* (opcode semantics, algorithm correctness), never for *structure* (control flow, memory management, type representation).

## The 10 Non-Negotiable Rules (§0.1)

These rules are enforced at every code review and by every agent:

1. **Thread the allocator.** Every allocating function takes `allocator: std.mem.Allocator`. The C `lua_Alloc` typedef is retired.
2. **Propagate errors with `!T` + `try`.** No `catch unreachable` on allocation; OOM returns `LUA_ERRMEM`. No `unreachable` for runtime conditions.
3. **Replace `setjmp`/`longjmp` with Zig error unions.** No `luaD_rawrunprotected` / `lua_longjmp` mechanics.
4. **`@intFromFloat` / `@floatFromInt` / `@intCast` for numeric conversions.** No `@bitCast` between `i64`/`f64`/`usize` to convert values.
5. **Bounded `[]const u8` slices.** No C null-terminated strings except at ABI boundaries.
6. **No C-style varargs.** Use explicit params, `anytype`, or `std.fmt`-style.
7. **Unmanaged containers initialized with `.empty`.** No `.append` on slices.
8. **`TValue = union(enum)` tagged union.** No raw NaN-boxing or `@bitCast` tricks.
9. **Single type model.** One `lua_State`, one `lua_CFunction`, one `global_State`. No `*anyopaque` shortcuts.
10. **juicy-main + `std.Io` threading.** All I/O through `io: std.Io`.

## Module Dependency Graph

```
llimits.zig + luaconf.zig  (pure constants)
        |
     lua.zig  (types + core API stubs)
       /|\
      / | \
     /  |  \
lvm.zig  lauxlib.zig  lstate.zig
    |       |
lualib.zig  src/lib/*.zig
    |
luazig.zig (entry point)
```

## Mapping Canonical C Files to Zig

| C file | Zig module | Strategy |
|--------|-----------|----------|
| `lua.h` + `lapi.c` | `src/lua.zig` | Zig-ified API; `lua_State` as struct with slice stack |
| `llimits.h` | `src/llimits.zig` | Constants only, types moved to `lua.zig` |
| `luaconf.h` | `src/luaconf.zig` | Number type config, path defaults |
| `lobject.h` | → `lua.zig` (`TValue`, `lua_TString`) | Tagged union replaces NaN-boxing |
| `lstate.h` + `lstate.c` | `src/lstate.zig` + `lua.zig` (partial) | Full `global_State` in lstate.zig, placeholder in lua.zig |
| `lvm.c` + `lvm.h` | `src/lvm.zig` | Opcodes as Zig enum; `run` as switch over opcodes |
| `lauxlib.c` | `src/lauxlib.zig` | Auxiliary helpers, error-producing check functions |
| `lualib.h` + `linit.c` | `src/lualib.zig` | Stub library registration |
| `lbaselib.c` etc. | `src/lib/*.zig` | Library bodies (broken stubs currently) |
| `lua.c` | `src/luazig.zig` | juicy-main entry point |

## Key Design Decisions

### TValue as Tagged Union
The C reference uses NaN-boxing (`Value` union + `tt_` byte in a `f64`). Zig has native tagged unions, so `TValue` is a `union(enum)` with variants for each Lua type. This guarantees type safety at compile time and eliminates the entire class of `@bitCast` bugs.

### No lua_Alloc
Zig's `std.mem.Allocator` interface replaces the C `lua_Alloc` function pointer. This gives us comptime-known allocation strategies, built-in tracking, and seamless integration with Zig's testing allocator.

### No lua_longjmp
C's `setjmp`/`longjmp` for error handling is replaced by Zig error unions (`!T`). Functions that can fail return error codes through the type system, not through C stack unwinding.
