# lua.zig

A from-scratch port of the [Lua](https://www.lua.org/) reference implementation
(Lua 5.5.1, upstream `v5.5.1`) to **Zig 0.16.0**. It is a faithful interpreter
that follows Lua's reference *semantics* while adopting idiomatic Zig for the
*structure*.

> This is a **static** project summary. The living, machine-friendly knowledge
> bundle lives under [`docs/`](docs/README.md) (Google OKF v0.1).

## Status

**Phases A–H are complete.** The interpreter is a drop-in replacement for the
Lua 5.5.1 reference:

- **Full source-text pipeline**: a lexer, recursive-descent parser, and code
  generator (Phase G) compile Lua source to the same `lua_Proto` shape the
  bytecode loader builds, so the VM serves both.
- **All 10 standard libraries**: base, math, string, table, utf8, coroutine,
  bit32, io, os, debug, loadlib.
- **Full C API + auxlib surface** (Phase H.1–H.10): every `lua.h`/`lauxlib.h`
  function implemented (no stubs), the reference system (`luaL_ref`/`luaL_unref`),
  CLI flags matching the reference interpreter (`-e`, `-l`, `-i`, `-v`, `--`),
  and a complete mark-and-sweep garbage collector with all `lua_gc` options.
- **Upstream test-suite conformance** (Phase H.11): the entire
  `lua/testes/*.lua` suite passes — **PASS 19, FAIL 0** — including coroutines,
  to-be-closed variables, metamethod yields, and error routing.
- **Ported to 5.5.1**: the reference subrepo tracks the `v5.5.1` tag
  (repeat-until scoping, lazy vararg tables, GC-on-load, and more).

Error handling is longjmp-free: Zig error unions (`!T`/`try`) replace Lua's
`setjmp`/`longjmp`, with continuation support for `lua_pcallk`/`lua_callk`.

| Phase | Area | State |
|-------|------|-------|
| A | Foundations (type model, stack, decode) | ✅ |
| B | Tables & string interning | ✅ |
| C | Bytecode loader (`lundump`) | ✅ |
| D | Working VM (incl. varargs) | ✅ |
| E | Metatables / error handling / GC | ✅ |
| F | Standard libraries (10 libs) | ✅ |
| G | Source-text compiler (lexer/parser/codegen) | ✅ |
| H | Drop-in replacement gap closure (incl. upstream suite) | ✅ |

## Build & test

```sh
zig build        # build the `luazig` executable and `lua` library
zig build test   # run the unit tests (131 passing)
./run_testes.sh  # run the upstream lua/testes/*.lua conformance suite
```

## Layout

```
src/        Zig sources (lua.zig core, lvm.zig, ltable.zig, ltm.zig, lundump.zig, llex.zig, lparser.zig, lcode.zig, ...)
src/lib/    standard library implementations (baselib, mathlib, stringlib, ...)
tests/      unit tests + sample bytecode
lua/        Git subrepo: the authoritative Lua 5.5.1 C reference (usable as a compiler oracle)
docs/       OKF v0.1 knowledge bundle
```

## Design principles

- Thread the allocator (`std.mem.Allocator`) — no hardcoded `page_allocator`.
- Propagate errors with `!T` + `try`; no `catch unreachable` on allocation and
  no error-swallowing `catch {}` where an error can propagate.
- Replace `setjmp`/`longjmp` with Zig error unions.
- Use `TValue = union(enum)` for values (no NaN-boxing / `@bitCast` tricks).
- Unmanaged containers; `std.Io` for I/O; no `@cImport`.

## REPL / CLI

```
luazig            # interactive REPL
luazig script.lua # run a Lua source file
```

The banner identifies the build as **Lua 5.5.1** and preserves the upstream
Lua.org MIT copyright (`lua/lua.h`).

See [`AGENTS.md`](AGENTS.md) for the full coding mandate.
