---
type: architecture_guideline
title: Error Handling Strategy
description: Replacing Lua's setjmp/longjmp with Zig error unions. Design for error propagation, OOM handling, lua_pcall, and lua_error.
tags: [errors, setjmp, longjmp, error-unions]
timestamp: 2026-07-10T00:00:00Z
---

## The C Problem

Lua's C implementation uses `setjmp`/`longjmp` for non-local error handling throughout the runtime:

```c
// ldo.c
TStatus luaD_rawrunprotected (lua_State *L, Pfunc f, void *ud) {
  struct lua_longjmp lj;
  lj.status = LUA_OK;
  lj.previous = L->errorJmp;
  L->errorJmp = &lj;
  if (setjmp(lj.b)) {  // longjmp target
    L->errorJmp = lj.previous;  // restore
    return lj.status;
  }
  f(L, ud);
  L->errorJmp = lj.previous;
  return LUA_OK;
}
```

This pattern appears in:
- `lua_pcall` — protected call
- `luaD_pcall` — internal protected call wrapper
- `luaD_rawrunprotected` — raw setjmp/longjmp
- `lua_error` — initiates the longjmp
- `luaD_throw` — actually longjmps

## The Zig Solution

Replace all setjmp/longjmp with Zig error unions (`!T`) and `try`/`catch`:

### Error Set

Define a dedicated error set:

```zig
pub const LuaError = error{
    RunError,       // LUA_ERRRUN
    SyntaxError,    // LUA_ERRSYNTAX
    MemoryError,    // LUA_ERRMEM
    ErrorError,     // LUA_ERRERR
};
```

### Function Signatures

Functions that can fail return `LuaError!T`:

```zig
pub fn lua_pcallk(L: *lua_State, nargs: i32, nresults: i32,
    errfunc: i32, ctx: lua_KContext, k: ?lua_KFunction) LuaError!i32 { ... }

pub fn lua_error(L: *lua_State) LuaError { ... }

pub fn luaL_dostring(L: *lua_State, s: []const u8, name: []const u8) LuaError!i32 { ... }
```

Functions that allocate can fail with OOM:

```zig
pub fn lua_checkstack(L: *lua_State, n: i32) LuaError!void {
    const needed = L.top + @as(usize, @intCast(n));
    if (needed <= L.stack.len) return;
    const new_cap = needed + LUA_MINSTACK;
    L.stack = try L.allocator.realloc(L.stack, new_cap);
    L.stack_last = L.stack.len - 1;
}
```

### Current Status

The codebase has already removed `lua_longjmp` from the type model:
- `lua_longjmp` struct exists in `lua.zig` as an empty stub (for struct completeness only)
- `errorJmp` field in `lua_State` exists but is never used
- Most stub functions return `LUA_OK` directly
- `lua_error` currently prints to stderr and returns `LUA_ERRRUN`

### TODO for Phase E

1. Remove `errorJmp` field from `lua_State` entirely
2. Wire all allocation sites to return `error.MemoryError` on OOM instead of `catch unreachable`
3. Implement `lua_pcallk` with Zig `try`/`catch` around the called function
4. Port `luaD_protectedparser` to use error return propagation
5. Ensure `lua_error` propagates through Zig error union (not C longjmp)
6. Update `lua_CFunction` signature to return `LuaError!i32` if it can error

### Design Decision: Error Returns vs try/catch

Option A: All API functions return `i32` error codes (C style)
- Maintaining compatibility with C function signatures
- But requires manual error checking at every call site

Option B: Use `LuaError!` error unions throughout
- Idiomatic Zig
- The compiler ensures errors are handled
- But: changes `lua_CFunction` signature away from C convention
- **Preferred**: use Zig error unions. The `lua_CFunction` typedef may need adjustment.

Option C: Hybrid approach
- Core runtime uses error unions internally
- Public API wraps results into `i32` return codes at the boundary
- This is the current approach (all stub functions return `LUA_OK`)

**Recommendation**: Option C for the public C-compatible API surface, Option B internally.
