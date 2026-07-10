# lua.zig

A from-scratch port of the [Lua](https://www.lua.org/) reference implementation
(Lua 5.5.1) to **Zig 0.16.0**. It aims to be a faithful interpreter that follows
Lua's reference *semantics* while adopting idiomatic Zig for the *structure*.

> This is a **static** project summary. The living, machine-friendly knowledge
> bundle lives under [`docs/`](docs/README.md) (Google OKF v0.1).

## Status

Phases A–E (partial) are complete: a working VM executes precompiled Lua 5.5.1
bytecode, with tables, string interning, metamethod dispatch for
`__index`/`__newindex`, and a flat GC sweep list for leak-free teardown.
Source-text compilation (lexer/parser) and the standard library bodies are
**not yet** finished.

| Phase | Area | State |
|-------|------|-------|
| A | Foundations (type model, stack, decode) | ✅ |
| B | Tables & string interning | ✅ |
| C | Bytecode loader (`lundump`) | ✅ |
| D | Working VM | ✅ |
| E | Metatables / error handling / GC | 🚧 partial |
| F | Standard libraries | ⬜ |

## Build & test

```sh
zig build        # build the `luazig` executable and `lua` library
zig build test   # run the unit tests (20 passing)
```

## Layout

```
src/        Zig sources (lua.zig core, lvm.zig, ltable.zig, ltm.zig, lundump.zig, ...)
src/lib/    standard library stubs (baselib, mathlib, stringlib, ...)
tests/      unit tests + sample bytecode
lua/        Git subrepo: the authoritative Lua 5.5.1 C reference
docs/       OKF v0.1 knowledge bundle
```

## Design principles

- Thread the allocator (`std.mem.Allocator`) — no hardcoded `page_allocator`.
- Propagate errors with `!T` + `try`; no `catch unreachable` on allocation.
- Replace `setjmp`/`longjmp` with Zig error unions.
- Use `TValue = union(enum)` for values (no NaN-boxing / `@bitCast` tricks).
- Unmanaged containers; `std.Io` for I/O; no `@cImport`.

See [`AGENTS.md`](AGENTS.md) for the full coding mandate.
