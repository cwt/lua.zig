# lua.zig

A from-scratch port of the [Lua](https://www.lua.org/) reference implementation
(Lua 5.5.1) to **Zig 0.16.0**. It aims to be a faithful interpreter that follows
Lua's reference *semantics* while adopting idiomatic Zig for the *structure*.

> This is a **static** project summary. The living, machine-friendly knowledge
> bundle lives under [`docs/`](docs/README.md) (Google OKF v0.1).

## Status

Phases A–F are complete. The working VM executes precompiled Lua 5.5.1 bytecode through a full interpreter: tables, string interning, metamethod dispatch (`__index`/`__newindex`/arithmetic/comparison/concat/len/call), longjmp-free error propagation with continuations (`lua_pcallk`/`lua_callk`), a mark-and-sweep garbage collector, and **all 10 standard libraries** (base, math, string, table, utf8, coroutine, bit32, io, os, debug, loadlib). Vararg functions execute correctly, and `luaL_dostring` loads and runs precompiled chunks.

The one remaining core gap is **source-text compilation**: there is no lexer/parser/code generator yet, so text Lua source fails to load (`LUA_ERRSYNTAX`) — only precompiled `\x1b` bytecode runs. This is planned as **Phase G** (see `docs/roadmap.md` and `AGENTS.md` §8).

| Phase | Area | State |
|-------|------|-------|
| A | Foundations (type model, stack, decode) | ✅ |
| B | Tables & string interning | ✅ |
| C | Bytecode loader (`lundump`) | ✅ |
| D | Working VM (incl. varargs) | ✅ |
| E | Metatables / error handling / GC | ✅ |
| F | Standard libraries (10 libs) | ✅ |
| G | Source-text compiler (lexer/parser/codegen) | 🚧 not started |

## Build & test

```sh
zig build        # build the `luazig` executable and `lua` library
zig build test   # run the unit tests (67 passing)
```

## Layout

```
src/        Zig sources (lua.zig core, lvm.zig, ltable.zig, ltm.zig, lundump.zig, ...)
src/lib/    standard library implementations (baselib, mathlib, stringlib, ...)
tests/      unit tests + sample bytecode
lua/        Git subrepo: the authoritative Lua 5.5.1 C reference (usable as a compiler oracle)
docs/       OKF v0.1 knowledge bundle
```

## Design principles

- Thread the allocator (`std.mem.Allocator`) — no hardcoded `page_allocator`.
- Propagate errors with `!T` + `try`; no `catch unreachable` on allocation.
- Replace `setjmp`/`longjmp` with Zig error unions.
- Use `TValue = union(enum)` for values (no NaN-boxing / `@bitCast` tricks).
- Unmanaged containers; `std.Io` for I/O; no `@cImport`.

See [`AGENTS.md`](AGENTS.md) for the full coding mandate.
