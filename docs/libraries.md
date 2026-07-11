---
type: architecture_guideline
title: Standard Libraries Porting Guide
description: Strategy for porting each standard library module, std.Io threading, library registration, and per-module implementation notes.
tags: [libraries, baselib, mathlib, stringlib, iolib]
timestamp: 2026-07-10T00:00:00Z
---

## Library Registration

Libraries are registered through `luaL_openselectedlibs` in `lauxlib.zig`, which uses a bitmask system:

```zig
pub const LUA_BASELIB:  i32 = 1 << 0;
pub const LUA_COLIB:    i32 = 1 << 1;
pub const LUA_TABLIB:   i32 = 1 << 2;
pub const LUA_IOLIB:    i32 = 1 << 3;
pub const LUA_OSLIB:    i32 = 1 << 4;
pub const LUA_STRLIB:   i32 = 1 << 5;
pub const LUA_MATHLIB:  i32 = 1 << 6;
pub const LUA_UTF8LIB:  i32 = 1 << 7;
pub const LUA_DBLIB:    i32 = 1 << 8;
pub const LUA_LOADLIB:  i32 = 1 << 9;
pub const LUA_BITLIB:   i32 = 1 << 10;
pub const LUA_COROLIB:  i32 = 1 << 1;
```

Each library has an open function in `lualib.zig` (currently all stubs) and a body in `src/lib/*.zig` (currently broken code).

## I/O Threading Requirement

Per §0.1 rule 10: all I/O must flow through `std.Io` from `std.process.Init`:

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;  // std.Io
    // thread io down to iolib, oslib
}
```

The `io` object must be stored somewhere accessible to library functions — either in `global_State` or as a field on `lua_State`.

## Module-by-Module Notes

### baselib (`lua/lbaselib.c`)

Functions: `assert`, `collectgarbage`, `dofile`, `error`, `getmetatable`, `ipairs`, `load`, `loadfile`, `next`, `pairs`, `pcall`, `print`, `rawequal`, `rawlen`, `rawget`, `rawset`, `select`, `setmetatable`, `tonumber`, `tostring`, `type`, `xpcall`, `warn`

Key dependencies: working tables, working calls, working metatables, working error handling.

`dofile`/`loadfile` need the front-end (Phase C) to work.

Current `src/lib/baselib.zig` status: **fully implemented** — `type`, `rawequal`, `rawlen`, `rawget`, `rawset`, `setmetatable`, `getmetatable`, `tonumber`, `tostring`, `select`, `pcall`, `xpcall`, `print`, `assert`, `error`, `next`, `pairs`, `ipairs`, `collectgarbage` all wired. Verified by 5 integration tests (32 total).

### mathlib (`lua/lmathlib.c`)

Functions: `abs`, `acos`, `asin`, `atan`, `atan2`, `ceil`, `cos`, `cosh`, `deg`, `exp`, `floor`, `fmod`, `huge`, `log`, `max`, `min`, `modf`, `pi`, `rad`, `random`, `randomseed`, `sin`, `sinh`, `sqrt`, `tan`, `tanh`, `tointeger`, `type`, `ult`

Mostly pure number operations. Low dependency on other components.

Current `src/lib/mathlib.zig` status: **fully implemented** — all 26 functions
(`abs`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `floor`, `ceil`, `fmod`,
`modf`, `sqrt`, `ult`, `log`, `exp`, `deg`, `rad`, `frexp`, `ldexp`, `min`,
`max`, `type`, `random`, `randomseed`, `tointeger`) plus constants
(`pi`, `huge`, `maxinteger`, `mininteger`) ported from `lua/lmathlib.c`.
PRNG uses a per-state `std.Random.Xoshiro256` seeded in `luaL_newstate_io`.
Verified by 3 integration tests (37 total).

Note: the C reference also provides `cosh`, `sinh`, `tanh` (hyperbolic) and
`math.maxinteger`/`math.mininteger` constants. The current implementation matches
Lua 5.5.1 `lua/lmathlib.c` exactly (no hyperbolic functions; integer bounds
exposed as constants).

### stringlib (`lua/lstrlib.c`)

Functions: `byte`, `char`, `dump`, `find`, `format`, `gmatch`, `gsub`, `len`, `lower`, `match`, `pack`, `packsize`, `rep`, `reverse`, `sub`, `unpack`, `upper`

Pattern matching is the most complex part. `string.dump` depends on `lua_dump` (loader).

### tablelib (`lua/ltablib.c`)

Functions: `concat`, `insert`, `move`, `pack`, `remove`, `sort`, `unpack`

Depends on working tables (Phase B).

### utf8lib (`lua/lutf8lib.c`)

Functions: `charpattern`, `codes`, `codepoint`, `char`, `len`, `offset`

Pure UTF-8 byte manipulation. Low external dependencies.

Current `src/lib/utf8lib.zig` status: **fully implemented** — all 6 functions
(`char`, `codepoint`, `len`, `offset`, `codes`) plus `utf8.charpattern`, ported
from `lua/lutf8lib.c`. `codes`/`offset` semantics (iterator closures, 2-value
byte positions) preserved; `len` returns `nil, pos` on invalid bytes.

### iolib (`lua/liolib.c`)

Functions: `close`, `flush`, `input`, `lines`, `open`, `output`, `popen`, `read`, `tmpfile`, `type`, `write`

**Must use `std.Io` instead of C `FILE*`.** This is the primary Zig-ification point. Create a Zig `File`-based wrapper instead of porting C file I/O.

### oslib (`lua/loslib.c`)

Functions: `clock`, `date`, `difftime`, `execute`, `exit`, `getenv`, `remove`, `rename`, `setlocale`, `t1`, `time`, `tmpname`

`os.execute` and `os.exit` need careful handling. `os.clock` maps to Zig `std.time` functions.

### corolib (`lua/lcorolib.c`)

Functions: `create`, `resume`, `yield`, `status`, `isyieldable`, `running`, `wrap`, `close`

Depends on working coroutine support in `lua_State` (thread creation, resume/yield).

### loadlib (`lua/loadlib.c`)

Functions: `require`, `searchpath`, `preload`, `loadlib`

Requires module search logic and dynamic loading. On Zig, consider whether `@cImport` for `dlopen` is acceptable or if a pure-Zig approach exists.

### debug (`lua/ldblib.c`)

Functions: `debug`, `gethook`, `getinfo`, `getlocal`, `getmetatable`, `getregistry`, `getupvalue`, `getuservalue`, `sethook`, `setlocal`, `setupvalue`, `setuservalue`, `traceback`, `upvalueid`, `upvaluejoin`

Depends on debug hooks and `CallInfo` introspection.

### bit32 (`lua/lbitlib.c`)

Functions: `arshift`, `band`, `bnot`, `bor`, `btest`, `bxor`, `extract`, `lrotate`, `lshift`, `replace`, `rrotate`, `rshift` — **DONE** (2026-07-11)

All 12 functions ported from Lua 5.3.6 `lbitlib.c` (absent from this 5.5.1 tree).
Pure bit manipulation on unsigned 32-bit values (`LUA_NBITS = 32`). `lshift`/`rshift`
return `0` for `|disp| >= 32`; `arshift` is arithmetic (sign-extends bit 31) only
when bit 31 is set; `lrotate`/`rrotate` use `disp & 31`. `extract`/`replace` accept
a `width` argument and validate `field >= 0`, `width > 0`, `field + width <= 32`.
Low dependencies (only `lua` + `lauxlib`).
