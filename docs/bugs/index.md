---
type: directory_index
title: Bug Reports & Defect Catalog
description: Index of all tracked defects, conformance fixes, and architectural bugs
  in luazig (BUG-001 through BUG-154).
tags:
- bugs
- defects
- index
- catalog
timestamp: '2026-09-08T21:20:00Z'
---

# Bug Reports & Defect Catalog — luazig

> Working catalog of defects, bug-avoidance audits, and conformance fixes in the `luazig` codebase.
> Bugs are numbered `BUG-001` through `BUG-154`.
> Each document records the location, defect, impact, and fix or resolution.

## Legend
- **[CRITICAL]** Memory corruption, Use-After-Free, ABI/stack violations, or interpreter panics.
- **[HIGH]** Crashes, wrong control flow, or incorrect results on ordinary programs.
- **[MED]** Incorrect behavior in defined edge cases or latent breakage in untested paths.
- **[LOW]** Cosmetic, minor deviation, or latent issue not currently triggered by tests.

## Bug Catalog

| ID | Title | Severity | Status |
|---|---|:---:|:---:|
| [BUG-001](001.md) | Bitwise shifts panic on negative / large second operand | `HIGH` | ✅ FIXED |
| [BUG-002](002.md) | `lua_callk` / `lua_call` swallow runtime errors | `HIGH` | ✅ FIXED |
| [BUG-003](003.md) | Proto garbage collection leaks sub-prototypes and the struct | `MED` | ❌ NOT A BUG |
| [BUG-004](004.md) | `lua_tointegerx` truncates non-integral floats | `MED` | ✅ FIXED |
| [BUG-005](005.md) | `lua_isinteger` hardcoded to return 0 | `MED` | ✅ FIXED |
| [BUG-006](006.md) | `lua_pushvfstring` / `lua_pushfstring` ignore the format string | `MED` | ❌ WON'T FIX |
| [BUG-007](007.md) | `luaL_checkstack` (auxlib) errors almost always | `MED` | ✅ FIXED |
| [BUG-008](008.md) | `luaL_register` registers every function under the name `"func"` | `MED` | ✅ FIXED |
| [BUG-009](009.md) | `TValue.typ()` maps `.upval` to `LUA_TTHREAD` | `LOW` | ✅ FIXED |
| [BUG-010](010.md) | `lua_precall` C-closure `top = L.top + 20` is unbounded | `LOW` | ✅ FIXED |
| [BUG-011](011.md) | Numeric `for` loops are broken (wrong register layout) | `HIGH` | ✅ FIXED |
| [BUG-012](012.md) | C-API `lua_gettable`/`lua_settable` and friends silently swallow metamethod errors | `MED` | ✅ FIXED |
| [BUG-013](013.md) | `lua_checkstack` return value ignored in `luaT_callTM`/`callTMres` → latent OOB | `LOW` | ✅ FIXED |
| [BUG-014](014.md) | Number→string formatting in `.CONCAT` / `lua_push*` differs from Lua | `LOW` | ❌ WON'T FIX |
| [BUG-015](015.md) | `getiofile` uses string-key `getfield` but default files are stored under pointer keys | `HIGH` | ✅ FIXED |
| [BUG-016](016.md) | `io.close()` with no arguments panics (`unreachable`) | `HIGH` | ✅ FIXED |
| [BUG-017](017.md) | `f_read`/`f_write` ignore `self` → `file:read()`/`file:write()` use the wrong file | `MED` | ✅ FIXED |
| [BUG-018](018.md) | `read_chars` over-reads: passes `buf.len` instead of `bytes_read` | `HIGH` | ✅ FIXED |
| [BUG-019](019.md) | `g_read` format dispatch is dead code (`if (n > 0)` should check the format type) | `HIGH` | ✅ FIXED |
| [BUG-020](020.md) | `luaL_newmetatable` key mismatch + `lua_setmetatable` index shift | `MED` | ✅ FIXED |
| [BUG-021](021.md) | `os.remove`/`os.rename` cast `[]const u8` to `[*:0]const u8` without a NUL terminator | `MED` | ✅ FIXED |
| [BUG-022](022.md) | `os.remove` ignores the syscall result and always returns `true` | `MED` | ✅ FIXED |
| [BUG-023](023.md) | `openio` leaks the FILE* metatable on the stack | `LOW` | ✅ FIXED |
| [BUG-024](024.md) | Hardcoded `std.heap.page_allocator` in iolib read/line helpers | `LOW` | ✅ FIXED |
| [BUG-025](025.md) | Empty `catch {}` in `luaL_setfuncs` / `luaL_fileresult` | `LOW` | ✅ FIXED |
| [BUG-026](026.md) | Lua-function coroutines without continuation re-execute from the start | `MED` | ✅ FIXED |
| [BUG-027](027.md) | Table hash part Node.next collision sentinel bug | `HIGH` | ✅ FIXED |
| [BUG-028](028.md) | Stack-imbalance popping in `loadlib.zig` helper functions | `MED` | ✅ FIXED |
| [BUG-029](029.md) | `require` upvalue closure registration mismatch | `MED` | ✅ FIXED |
| [BUG-030](030.md) | Memory leak of dynamic `path` in `searchpath` | `LOW` | ✅ FIXED |
| [BUG-031](031.md) | `loadlib.zig`: 9 silent `catch {}` swallow errors (§0.1 rule 12) | `HIGH` | ✅ FIXED |
| [BUG-032](032.md) | `loadlib.zig`: heap-allocated `std.DynLib` handle is never freed (latent leak) | `MED` | ✅ FIXED |
| [BUG-033](033.md) | `luaL_getenv`: Linux-only `/proc/self/environ`, exec-time snapshot, swallows I/O errors | `MED` | ✅ FIXED |
| [BUG-034](034.md) | `luaL_getenv` bypasses `std.Io` (§0.1 rule 10) | `LOW` | ✅ FIXED |
| [BUG-035](035.md) | `luaL_gsub` leaks its `luaL_Buffer` on OOM | `LOW` | ✅ FIXED |
| [BUG-036](036.md) | VM: vararg functions not executed correctly (VARARGPREP no-op, no adjustvarargs) | `MED` | ✅ FIXED |
| [BUG-037](037.md) | `luaL_newstate` leaves `L.l_G.?.io` dangling (stack `threaded` moved to `io_backend`) | `HIGH` | ✅ FIXED |
| [BUG-038](038.md) | VM `TAILCALL` with a C function drops the argument / misplaces results | `HIGH` | ✅ FIXED |
| [BUG-039](039.md) | String GC sweep corrupts the intern pool via stale key slices | `HIGH` | ✅ FIXED |
| [BUG-040](040.md) | FILE metatable never populated / no `__index`: every `file:method` call fails | `HIGH` | ✅ FIXED |
| [BUG-041](041.md) | `file:read("a")` (bare, no `*`) returns nil; read-all truncates / wrong on empty | `MED` | ✅ FIXED |
| [BUG-042](042.md) | `file:read("*n")` (number format) not implemented | `MED` | ✅ FIXED |
| [BUG-043](043.md) | `os.exit` ignores second argument: always calls `lua_close` unconditionally | `MED` | ⏳ OPEN |
| [BUG-044](044.md) | `lua_close` does not run `__gc`/`__close` finalizers (comment is misleading) | `MED` | ⏳ OPEN |
| [BUG-045](045.md) | `luaL_tolstring` leaves the stack unchanged for strings (breaks REPL table expansion) | `MED` | ✅ FIXED |
| [BUG-046](046.md) | `error_expected`/`check_match` store a dangling pointer into a stack-local buffer | `HIGH` | ✅ FIXED |
| [BUG-047](047.md) | `print("2"+1); print("2"+1)` crashes on second invocation (ABI Stack Argument Mismatch) | `HIGH` | ✅ FIXED |
| [BUG-048](048.md) | `parseInteger` rejects `minint` (`-9223372036854775808`) and hex boundaries | `HIGH` | ✅ FIXED |
| [BUG-049](049.md) | `tonumber` with custom base fails on strings with surrounding whitespace or hex prefix | `HIGH` | ✅ FIXED |
| [BUG-050](050.md) | VM binary arithmetic opcodes missing string-to-number coercion (25 opcodes) | `HIGH` | ⏳ OPEN |
| [BUG-051](051.md) | Silent `catch {}` swallowing errors in critical paths (31 sites) | `HIGH` | ⏳ OPEN |
| [BUG-052](052.md) | Dangling raw stack pointer passed through `lua_checkstack` in MMBIN | `HIGH` | ⏳ OPEN |
| [BUG-053](053.md) | `lua_checkstack` result discarded → OOB writes on OOM (10 sites) | `HIGH` | ⏳ OPEN |
| [BUG-054](054.md) | `unreachable` on genuinely fallible operations | `HIGH` | ⏳ OPEN |
| [BUG-055](055.md) | `ltable.zig`: Duplicate keys across array and hash parts cause stale reads on setting to nil | `HIGH` | ✅ FIXED |
| [BUG-056](056.md) | `lauxlib.zig`: Stack leakage in `luaL_register` | `MED` | ✅ FIXED |
| [BUG-057](057.md) | `loadlib.zig`: Stack leakage in `searchpath` on module name substitution | `LOW` | ✅ FIXED |
| [BUG-058](058.md) | `lstring.zig`: Leaked key buffer and dangling string table entry on OOM | `HIGH` | ✅ FIXED |
| [BUG-059](059.md) | `iolib.zig`: File descriptor leaks on OOM in `io_open`, `g_iofile`, and `io_tmpfile` | `HIGH` | ✅ FIXED |
| [BUG-060](060.md) | `lparser.zig`: Compiler state and prototype buffer leaks in `close_func` | `MED` | ✅ FIXED |
| [BUG-061](061.md) | `ltable.zig`: `old_node` array leak on allocation failure in `growNode` | `MED` | ✅ FIXED |
| [BUG-062](062.md) | `ltable.zig`: Tombstone accumulation in hash part causes early re-hash cycles | `LOW` | ✅ FIXED |
| [BUG-063](063.md) | `oslib.zig`: Redundant allocation loop in `os_date` when `strftime` returns 0 | `LOW` | ✅ FIXED |
| [BUG-064](064.md) | `lua.zig`: Unused / dangling references check during `reallocStack` and thread upvalues | `LOW` | ✅ FIXED |
| [BUG-065](065.md) | `lua.zig`: Integer overflow panics on `LUA_MININTEGER` / `LUA_MAXINTEGER` arithmetic | `HIGH` | ✅ FIXED |
| [BUG-066](066.md) | `ltm.zig`: `select('#', ...)` pushes Float TValue instead of Integer | `MED` | ✅ FIXED |
| [BUG-067](067.md) | `lvm.zig`: Integer underflow in `MMBIN` opcodes when `ci.savedpc < 2` | `HIGH` | ✅ FIXED |
| [BUG-068](068.md) | `lcode.zig`: Underflow panic in `ceillog2(0)` | `MED` | ✅ FIXED |
| [BUG-069](069.md) | `ltable.zig`: Unchecked negative index cast panic in hash chain search | `HIGH` | ✅ FIXED |
| [BUG-070](070.md) | `ldump.zig`: Debug info stripping format protocol discrepancy | `LOW` | ✅ FIXED |
| [BUG-071](071.md) | `lauxlib.zig`: Non-portable environment reader in `luaL_getenv` | `HIGH` | ✅ FIXED |
| [BUG-072](072.md) | `lstring.zig`: Use-After-Free (UAF) read in `createString` on OOM | `HIGH` | ✅ FIXED |
| [BUG-073](073.md) | `lundump.zig`: Invalid free / segfault on static slice deallocation in `loadDebug` | `HIGH` | ✅ FIXED |
| [BUG-074](074.md) | `lparser.zig`: Double free and slice leak in `close_func` | `MED` | ✅ FIXED |
| [BUG-075](075.md) | `lua.zig`: Unconditional free of externally-owned strings in state teardown | `MED` | ✅ FIXED |
| [BUG-076](076.md) | `lib/loadlib.zig`: `std.DynLib` heap memory leak on registration failure | `MED` | ✅ FIXED |
| [BUG-077](077.md) | `lvm.zig`: Heap memory leak in `pushclosure` on OOM | `MED` | ✅ FIXED |
| [BUG-078](078.md) | `ltable.zig`: `lastfree` out-of-bounds index corruption on failed table growth | `HIGH` | ✅ FIXED |
| [BUG-079](079.md) | `lua.zig`: GC zombie string state leak on OOM during string sweep | `MED` | ✅ FIXED |
| [BUG-080](080.md) | `lcode.zig`: Code emission corruption on allocation failure | `HIGH` | ✅ FIXED |
| [BUG-081](081.md) | `lib/iolib.zig`: Raw `std.c` POSIX syscalls bypass `std.Io` capability interface | `LOW` | ✅ FIXED |
| [BUG-082](082.md) | `lib/utf8lib.zig` & `lib/tablib.zig`: `@bitCast` used for numeric type conversions | `LOW` | ✅ FIXED |
| [BUG-083](083.md) | `lua.zig`: Imprecise bitwise float conversion predicates | `MED` | ✅ FIXED |
| [BUG-084](084.md) | `lauxlib.zig` & `lib/baselib.zig`: Duplicated preamble skipping & reader adapter logic | `LOW` | ✅ FIXED |
| [BUG-085](085.md) | `lua.zig`: Double initialization loop in userdata creation | `LOW` | ✅ FIXED |
| [BUG-086](086.md) | `lua.zig`: Coroutine open upvalues skipped during GC mark traversal | `HIGH` | ✅ FIXED |
| [BUG-087](087.md) | `lstring.zig`: Dangling stack slice key in `strt` on allocation failure | `HIGH` | ✅ FIXED |
| [BUG-088](088.md) | `lua.zig`: Cross-thread open upvalue pointers ignored during `reallocStack` | `HIGH` | ✅ FIXED |
| [BUG-089](089.md) | `luazig.zig`: Invalid `free()` on static string literal in CLI error handler | `HIGH` | ✅ FIXED |
| [BUG-090](090.md) | `lua.zig`: `lua_close` fails to free objects on `g.finobj` list | `HIGH` | ✅ FIXED |
| [BUG-091](091.md) | `ltable.zig`: `lastfree` index left out-of-bounds if table growth fails | `HIGH` | ✅ FIXED |
| [BUG-092](092.md) | `lvm.zig`: `u5` cast overflow and bitwise shift panic in `OP_NEWTABLE` | `HIGH` | ✅ FIXED |
| [BUG-093](093.md) | `lcode.zig`: Constant allocation error fallback (`catch 0`) emits corrupt code | `HIGH` | ✅ FIXED |
| [BUG-094](094.md) | `lcode.zig`: Swallowed allocation errors in `luaK_code*` helpers emit PC 0 | `HIGH` | ✅ FIXED |
| [BUG-095](095.md) | `lparser.zig`: Premature state mutation in `newupvalue` on missing enclosing function | `MED` | ✅ FIXED |
| [BUG-096](096.md) | `ltable.zig`: Floating point `-0.0` vs `0.0` hash mismatch | `MED` | ✅ FIXED |
| [BUG-097](097.md) | `lib/bit32.zig`: Signed integer addition overflow panic in `field + width` | `MED` | ✅ FIXED |
| [BUG-098](098.md) | `lib/mathlib.zig`: Unsigned integer cast overflow panic in `math.random` | `MED` | ✅ FIXED |
| [BUG-099](099.md) | `lib/corolib.zig`: Coroutine self-closure on invalid argument | `MED` | ✅ FIXED |
| [BUG-100](100.md) | Codebase-wide: 26 instances of empty `catch {}` error swallowing | `HIGH` | ✅ FIXED |
| [BUG-101](101.md) | `lvm.zig` / `lua.zig`: Stack slice pointer invalidation across reallocating/GC calls | `CRITICAL` | ✅ FIXED |
| [BUG-102](102.md) | `lvm.zig`: `@as(u3, ...)` shift bit-width truncation panic in `OP_NEWTABLE` | `CRITICAL` | ✅ FIXED |
| [BUG-103](103.md) | `ltable.zig`: Deleted hash keys not reset to `.nil` (`lastfree` node capacity leak) | `HIGH` | ✅ FIXED |
| [BUG-104](104.md) | `lua.zig` / `lstring.zig`: Short strings unmarking omission at GC cycle start & runtime mark mutation | `HIGH` | ✅ FIXED |
| [BUG-105](105.md) | `lua.zig`: Open upvalues on secondary coroutine thread stacks skipped during GC traversal | `HIGH` | ✅ FIXED |
| [BUG-106](106.md) | `ltm.zig`: Negative `nextra` integer sign cast panic on vararg calls | `HIGH` | ✅ FIXED |
| [BUG-107](107.md) | `loadlib.zig`: Opened `*std.DynLib` handles in `g.clibs` never closed or freed in `lua_close` | `HIGH` | ✅ FIXED |
| [BUG-108](108.md) | `lcode.zig`: Codegen instruction emitters swallow OOM with `catch {}` and return dummy PC 0 | `MED` | ✅ FIXED |
| [BUG-109](109.md) | `lua.zig`: Unchecked stack capacity growth before writing | `MED` | ✅ FIXED |
| [BUG-110](110.md) | `lvm.zig`: C function return values on `.TAILCALL` not relocated to caller frame | `MED` | ✅ FIXED |
| [BUG-111](111.md) | `ldump.zig` / `lundump.zig`: Negative line numbers dumped as unsigned u64 varints | `MED` | ✅ FIXED |
| [BUG-112](112.md) | `lib/iolib.zig`: Sentinel slice evaluated before NUL byte initialization in `io_tmpfile` | `MED` | ✅ FIXED |
| [BUG-113](113.md) | `lua.zig`: $O(N)$ linear scan in `getGCObject` during GC marking (quadratic GC latency) | `MED` | ✅ FIXED |
| [BUG-114](114.md) | `lauxlib.zig` / `iolib.zig` / `oslib.zig`: Direct system calls bypassing `std.Io` parameter | `LOW` | ✅ FIXED |
| [BUG-115](115.md) | `io.popen` was a stub: always returned `(nil, "'popen' not supported")` | `HIGH` | ✅ FIXED |
| [BUG-116](116.md) | `lundump.zig`: `loadInt` zigzag-decodes counts — every binary chunk fails to load (rev 152 regression) + all loader errors misreported as "truncated chunk" | `CRITICAL` | ✅ FIXED |
| [BUG-117](117.md) | `ldump.zig`/`lundump.zig`: dump wire format incompatible with Lua 5.5.1 both directions (`dumpInt` zigzag counts) | `HIGH` | ✅ FIXED |
| [BUG-118](118.md) | `ltable.zig`: `clearHashKey` nils node keys → mid-chain slot reuse breaks `.next` chains, silently losing entries | `CRITICAL` | ✅ FIXED |
| [BUG-119](119.md) | `lua.zig`: `reallocStack` cross-thread upvalue fix-up writes `&t.stack[...]` instead of `&L.stack[...]` (and matches freed memory ranges) | `HIGH` | ✅ FIXED |
| [BUG-120](120.md) | `lua.zig`: coroutine threads invisible to the GC — unreachable coroutines leak until `lua_close` | `HIGH` | ✅ FIXED |
| [BUG-121](121.md) | `lua.zig`: `__gc` resurrection unsupported — finalized objects freed even when the finalizer re-referenced them → UAF | `HIGH` | ✅ FIXED |
| [BUG-122](122.md) | `lua.zig`: unguarded stack writes in `close_one_slot`/`closeupvals` when the safe top reaches stack capacity | `HIGH` | ✅ FIXED |
| [BUG-123](123.md) | float→string via Zig `{d}` + undersized buffers: CONCAT silently emits empty string for large floats, io.write diverges, `lua_tolstring` returns null (supersedes BUG-014 scope) | `HIGH` | ✅ FIXED |
| [BUG-124](124.md) | `lua.zig`: `lua_rawequal` divergences — int/float cross-type false, non-interned string content ignored, invented C-closure equality | `MED` | ✅ FIXED |
| [BUG-125](125.md) | `lua.zig`: C-API `lua_concat` still uses the left-to-right single-metamethod algorithm (self-pairing, early return) | `MED` | ✅ FIXED |
| [BUG-126](126.md) | `lauxlib.zig`: `luaL_ref` pre-seeds `t[1]=0` (numbering off-by-one, pollutes iteration); `luaL_unref` accepts ref==0 | `MED` | ❌ FALSE POSITIVE |
| [BUG-127](127.md) | `ltable.zig`: `asInt` rejects integral float keys ≥ 9.0e18 accepted by the reference as integer keys | `MED` | ✅ FIXED |
| [BUG-128](128.md) | `lcode.zig`: OOM during instruction emission swallowed, emitters return dummy PC 0 (BUG-093/094/108 regression) | `HIGH` | ✅ FIXED |
| [BUG-129](129.md) | CLI divergences: no LUA_INIT/LUA_INIT_5_5/-E, missing progname error prefix, no negative arg[] indices | `LOW` | ✅ FIXED |
| [BUG-130](130.md) | `lauxlib.zig`: `LUA_ERRFILE = 5` collides with `LUA_ERRERR`; constant removed upstream in 5.5 | `LOW` | ✅ FIXED |
| [BUG-131](131.md) | Minor output-text divergences: `string.rep` overflow message, zero-padded `%p` pointer formatting | `LOW` | ✅ FIXED |
| [BUG-132](132.md) | `iolib.zig`: `catch unreachable` on integer/float formatting in `g_write` | `LOW` | ✅ FIXED |
| [BUG-133](133.md) | Residual swallowed-error inventory (~90 sites): iolib child reaping, pcallk errormsg dispatch, pushstring results discarded | `LOW` | ✅ FIXED |
| [BUG-134](134.md) | `std.debug.print` used for runtime warnings / GC & finalizer errors / lundump header diagnostics instead of threaded io | `LOW` | ✅ FIXED |
| [BUG-135](135.md) | `lvm.zig`: OP_SETLIST stores per-element via `setInt` instead of array pre-allocation + direct stores | `MED` | ✅ FIXED |
| [BUG-136](136.md) | `lua.zig`: `getGCObject` O(N) allgc fallback scans remain for tables/closures/userdata/upvalues (BUG-113 fixed strings only) | `LOW` | ✅ FIXED |
| [BUG-137](137.md) | Dead code inventory: committed `libm.zig.orig`, unused `lua_numbertocstring`/`hasFinalizer`/`lenhint`, duplicated `registerGC` switch, identical lundump branches, stale strcache comment | `LOW` | ✅ FIXED |
| [BUG-138](138.md) | Misc API divergences: io.popen("r") child stdin ignored, luaL_dostring collapses pcall errors, lua_xmove truncates, io.tmpfile no EEXIST retry | `LOW` | ✅ FIXED |
| [BUG-139](139.md) | `lua.zig`: `finishLoad` GC object dangling pointers, UAF, and double-free on OOM | `CRITICAL` | ✅ FIXED |
| [BUG-140](140.md) | `lvm.zig`: `pushclosure` missing `errdefer` causes sequential heap leaks on OOM | `HIGH` | ⏳ OPEN |
| [BUG-141](141.md) | `lundump.zig`: `loadProtos` leaves uninitialized wild pointers in proto `sub_protos` slice | `CRITICAL` | ⏳ OPEN |
| [BUG-142](142.md) | `corolib.zig` / `lua.zig`: `coroutine.close` on running thread destroys active `CallInfo` causing UAF and double-free | `CRITICAL` | ⏳ OPEN |
| [BUG-143](143.md) | `lua.zig`: `growStack(L, 1)` is a no-op bug causing latent out-of-bounds stack panics | `HIGH` | ⏳ OPEN |
| [BUG-144](144.md) | `iolib.zig`: Empty line truncation, `read(0)` unconditional nil, `f:lines()` non-iterator, and FD leaks | `HIGH` | ⏳ OPEN |
| [BUG-145](145.md) | `iolib.zig`: Closed file handles bypass state check and issue syscalls with `fd = -1` | `MED` | ⏳ OPEN |
| [BUG-146](146.md) | `bit32.zig`: `bit32.extract` and `bit32.replace` panic on wrapping integer addition | `HIGH` | ⏳ OPEN |
| [BUG-147](147.md) | `baselib.zig`: `dofile` and `loadfile` error on omitted filename instead of reading from `stdin` | `MED` | ⏳ OPEN |
| [BUG-148](148.md) | `mathlib.zig`: `math.random(n)` missing lower bounds check allows negative integers to wrap into pseudo-random bounds | `MED` | ⏳ OPEN |
| [BUG-149](149.md) | `format.zig`: `string.format` raises divergent error message for 3-digit width/precision specifiers (reference also rejects them; only the message differs) | `LOW` | ⏳ OPEN |
| [BUG-150](150.md) | `oslib.zig`: `os.tmpname` rapid deterministic filename collisions via second-resolution timestamp | `MED` | ⏳ OPEN |
| [BUG-151](151.md) | `lua.zig` / `ltable.zig`: Table growth bypasses `totalbytes` causing GC tracking underflow and zero count | `HIGH` | ⏳ OPEN |
| [BUG-152](152.md) | `ltm.zig` / `ltable.zig`: Dead code `checknoTM` and `Table.flags` missing invalidation on key mutation (only `lua_setmetatable` clears flags) | `LOW` | ⏳ OPEN |
| [BUG-153](153.md) | `lauxlib.zig`: Swallowed error via dummy `catch {}` in `luaL_tolstring` violating rule §0.1 item 12 | `MED` | ⏳ OPEN |
| [BUG-154](154.md) | `luazig.zig`: `std.process.exit` in `main` bypasses `lua_close` and GPA `deinit` defer handlers | `LOW` | ⏳ OPEN |

## Systematic Bug Audits
- [BUG-050](050.md) – [BUG-054](054.md): Systematic Bug-Pattern Audit (2026-07-31) cross-cutting codebase analysis.
- [BUG-055](055.md) – [BUG-085](085.md): Comprehensive Memory & Static Analysis Audit (2026-08-08).
- [BUG-086](086.md) – [BUG-114](114.md): Concurrency, Coroutines, GC & Platform Conformance Audit (2026-08-08).
- [BUG-116](116.md) – [BUG-138](138.md): Deep Audit vs Lua 5.5.1 Reference (2026-08-24) — full-source review with differential testing against `lua/lua`; found the rev-152 loader regression (all `.luac` loading broken, 127/132 tests), dump-format wire incompatibility, table chain-corruption hazard, GC gaps (threads never collected, `__gc` resurrection UAF), float-to-string regressions, and assorted conformance divergences.
- [BUG-139](139.md) – [BUG-154](154.md): Memory Safety, Conformance & Dead Code Deep Audit (2026-09-08) — static analysis hunting for UAF, double-free, uninitialized pointers, stack growth no-ops, I/O boundary defects, and Zig 0.16.0 rule compliance.

---
- [← Documentation Root](../index.md)
- [Log](../log.md)
