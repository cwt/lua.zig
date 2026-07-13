# lua.zig

A from-scratch port of the [Lua](https://www.lua.org/) reference implementation
(Lua 5.5.1) to **Zig 0.16.0**. It aims to be a faithful interpreter that follows
Lua's reference *semantics* while adopting idiomatic Zig for the *structure*.

> This is a **static** project summary. The living, machine-friendly knowledge
> bundle lives under [`docs/`](docs/README.md) (Google OKF v0.1).

## Status

Phases A–G are complete. The working VM executes **both** precompiled Lua 5.5.1
bytecode and Lua **source text** (a full lexer/parser/code generator, Phase G,
feeds the same `lua_Proto` shape the loader builds, so the VM is untouched):
tables, string interning, metamethod dispatch
(`__index`/`__newindex`/arithmetic/comparison/concat/len/call/`__close`),
longjmp-free error propagation with continuations (`lua_pcallk`/`lua_callk`), a
mark-and-sweep garbage collector, and **all 10 standard libraries** (base, math,
string, table, utf8, coroutine, bit32, io, os, debug, loadlib). Vararg functions
execute correctly, and `luaL_dostring` / `luaL_loadstring` load and run Lua source
or precompiled chunks.

**Phase H (drop-in replacement gap closure) is in progress.** Phase H.1 — the
high-priority C API stubs that silently returned wrong results — is **done**
(`lua_concat`, `lua_len`, `lua_getallocf`/`lua_setallocf`, `lua_toclose`/
`lua_closeslot`, `luaL_newtable`, `luaL_len`, `luaL_where`, `createargtable`).
Remaining H.x work: `oslib`/`iolib` stubs, `luaL_ref`/`luaL_unref`, missing C API
+ auxlib functions, CLI flags. See `docs/roadmap.md` and `AGENTS.md` §8.

| Phase | Area | State |
|-------|------|-------|
| A | Foundations (type model, stack, decode) | ✅ |
| B | Tables & string interning | ✅ |
| C | Bytecode loader (`lundump`) | ✅ |
| D | Working VM (incl. varargs) | ✅ |
| E | Metatables / error handling / GC | ✅ |
| F | Standard libraries (10 libs) | ✅ |
| G | Source-text compiler (lexer/parser/codegen) | ✅ |
| H | Drop-in replacement gap closure | 🚧 in progress (H.1 done) |

## Build & test

```sh
zig build        # build the `luazig` executable and `lua` library
zig build test   # run the unit tests (81 passing)
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
- Propagate errors with `!T` + `try`; no `catch unreachable` on allocation.
- Replace `setjmp`/`longjmp` with Zig error unions.
- Use `TValue = union(enum)` for values (no NaN-boxing / `@bitCast` tricks).
- Unmanaged containers; `std.Io` for I/O; no `@cImport`.

## REPL / CLI

```
luazig            # interactive REPL
luazig script.lua # run a Lua source file
```

The banner identifies the build as **Lua.Zig 5.5.1** and preserves the upstream
Lua.org MIT copyright (`lua/lua.h`).

See [`AGENTS.md`](AGENTS.md) for the full coding mandate.
