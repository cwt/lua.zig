const std = @import("std");
const lua = @import("lua");

test "nil push and type check" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_pushnil(&L);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isnil(&L, -1));
    try std.testing.expectEqual(@as(i32, lua.LUA_TNIL), lua.lua_type(&L, -1));
}

test "boolean push and type check" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_pushboolean(&L, 1);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isboolean(&L, -1));
    try std.testing.expectEqual(@as(i32, 1), lua.lua_toboolean(&L, -1));

    lua.lua_pushboolean(&L, 0);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isboolean(&L, -1));
    try std.testing.expectEqual(@as(i32, 0), lua.lua_toboolean(&L, -1));
}

test "number push and type check" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_pushnumber(&L, 3.14);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isnumber(&L, -1));
    const n = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expect(std.math.approxEqAbs(f64, n, 3.14, 0.001));
}

test "integer push and type check" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_pushinteger(&L, 42);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isnumber(&L, -1));
    const i = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 42), i);
}

test "string push and type check" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    _ = lua.lua_pushstring(&L, "hello world");
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isstring(&L, -1));
}

test "table creation and type check" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_istable(&L, -1));
}

test "stack push pop round trip" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try std.testing.expectEqual(@as(i32, 0), lua.lua_gettop(&L));

    lua.lua_pushnumber(&L, 1.0);
    lua.lua_pushnumber(&L, 2.0);
    lua.lua_pushnumber(&L, 3.0);
    try std.testing.expectEqual(@as(i32, 3), lua.lua_gettop(&L));

    lua.lua_pop(&L, 2);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(&L));

    const v = lua.lua_tonumber(&L, 1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, 1.0), v);
}

test "string interning shares pointer" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    _ = lua.lua_pushstring(&L, "shared");
    _ = lua.lua_pushstring(&L, "shared");
    const ta = lua.lua_topointer(&L, -2);
    const tb = lua.lua_topointer(&L, -1);
    try std.testing.expectEqual(@as(?*anyopaque, ta), tb);
}

test "table setfield/getfield" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    _ = lua.lua_pushstring(&L, "hello");
    lua.lua_setfield(&L, -2, "key");
    _ = lua.lua_getfield(&L, -1, "key");
    const s = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "hello", s);
}

test "table seti/geti and length" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    var i: i32 = 1;
    while (i <= 5) : (i += 1) {
        lua.lua_pushinteger(&L, i * 10);
        lua.lua_seti(&L, -2, i);
    }
    _ = lua.lua_geti(&L, -1, 3);
    const v = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 30), v);
    try std.testing.expectEqual(@as(usize, 5), lua.lua_rawlen(&L, -2));
}

test "empty table length is 0" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    try std.testing.expectEqual(@as(usize, 0), lua.lua_rawlen(&L, -1));
}

test "table remove entry" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    lua.lua_pushinteger(&L, 99);
    lua.lua_seti(&L, -2, 1);
    try std.testing.expectEqual(@as(usize, 1), lua.lua_rawlen(&L, -1));
    lua.lua_pushnil(&L);
    lua.lua_seti(&L, -2, 1);
    try std.testing.expectEqual(@as(usize, 0), lua.lua_rawlen(&L, -1));
}

test "table hash part stores string keys" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 4);
    _ = lua.lua_pushstring(&L, "v");
    lua.lua_setfield(&L, -2, "k");
    _ = lua.lua_pushstring(&L, "k");
    _ = lua.lua_rawget(&L, -2);
    const got = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "v", got);
}

test "table next traversal visits all entries" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    lua.lua_pushinteger(&L, 10);
    lua.lua_seti(&L, -2, 1);
    lua.lua_pushinteger(&L, 20);
    lua.lua_seti(&L, -2, 2);
    _ = lua.lua_pushstring(&L, "x");
    lua.lua_setfield(&L, -2, "a");

    lua.lua_pushnil(&L);
    var count: usize = 0;
    while (lua.lua_next(&L, -2) != 0) {
        count += 1;
        lua.lua_pop(&L, 1);
    }
    try std.testing.expectEqual(@as(usize, 3), count);
}

test "table gettable/settable with stack key" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    _ = lua.lua_pushstring(&L, "name");
    _ = lua.lua_pushstring(&L, "zig");
    lua.lua_settable(&L, -3);
    _ = lua.lua_pushstring(&L, "name");
    _ = lua.lua_gettable(&L, -2);
    const got = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "zig", got);
}

const StringReaderState = struct {
    code: []const u8,
    read_done: bool,
};

fn stringReader(L: *lua.lua_State, data: ?*anyopaque, size: ?*usize) ?[]const u8 {
    _ = L;
    const state: *StringReaderState = @ptrCast(@alignCast(data.?));
    if (state.read_done) {
        if (size) |p| p.* = 0;
        return &.{};
    }
    state.read_done = true;
    if (size) |p| p.* = state.code.len;
    return state.code;
}

test "bytecode loader (lundump)" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const bytecode = try std.Io.Dir.cwd().readFileAlloc(io, "tests/test_chunk.luac", gpa, .unlimited);
    defer gpa.free(bytecode);

    var reader_state = StringReaderState{
        .code = bytecode,
        .read_done = false,
    };

    const status = lua.lua_load(&L, stringReader, &reader_state, "test_chunk.luac", "b");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);

    // The top of the stack should contain the loaded closure
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(&L));
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));

    // Get the closure and check the prototype
    const val = L.stack[L.top - 1];
    try std.testing.expect(val == .function);
    const cl = val.function.?;
    try std.testing.expect(cl.* == .lua);
    const proto = cl.lua.p;

    // Verify main prototype properties
    try std.testing.expectEqual(@as(u8, 0), proto.numParams);
    try std.testing.expect(proto.code.len > 0);
    try std.testing.expect(proto.k.len > 0);

    // Main prototype should have 1 nested prototype (the `sub` function)
    try std.testing.expectEqual(@as(usize, 1), proto.p.len);
    const sub_proto = proto.p[0];

    // Verify sub-prototype properties
    try std.testing.expectEqual(@as(u8, 1), sub_proto.numParams);
    try std.testing.expect(sub_proto.code.len > 0);
}

test "VM execution" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const bytecode = try std.Io.Dir.cwd().readFileAlloc(io, "tests/test_chunk.luac", gpa, .unlimited);
    defer gpa.free(bytecode);

    var reader_state = StringReaderState{
        .code = bytecode,
        .read_done = false,
    };

    const status = lua.lua_load(&L, stringReader, &reader_state, "test_chunk.luac", "b");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);

    // Perform a protected call (0 arguments, 1 result expected)
    const pcall_status = lua.lua_pcallk(&L, 0, 1, 0, 0, null);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), pcall_status);

    // The top of the stack should contain the returned number 52
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(&L));
    try std.testing.expectEqual(@as(i32, lua.LUA_TNUMBER), lua.lua_type(&L, -1));
    const result = L.stack[L.top - 1].number;
    try std.testing.expectEqual(@as(f64, 52.0), result);
}

test "__index function metamethod via C API" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // t is an empty table
    lua.lua_createtable(&L, 0, 0);
    const t_idx: i32 = lua.lua_gettop(&L);

    // mt with __index = function that always returns 42
    lua.lua_createtable(&L, 0, 1);
    const mt_idx: i32 = lua.lua_gettop(&L);

    const IndexFn = struct {
        fn index(LS: *lua.lua_State) anyerror!i32 {
            lua.lua_pushnumber(LS, 42.0);
            return 1;
        }
    };
    lua.lua_pushcfunction(&L, IndexFn.index);
    lua.lua_setfield(&L, mt_idx, "__index");

    // setmetatable(t, mt)
    try std.testing.expectEqual(@as(i32, 1), lua.lua_setmetatable(&L, t_idx));

    // t["missing"] should invoke __index and return 42
    _ = lua.lua_getfield(&L, t_idx, "missing");
    const v = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, 42.0), v);
}

test "__index table chain metamethod via C API" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // parent["x"] = 99
    lua.lua_createtable(&L, 0, 1);
    const parent_idx: i32 = lua.lua_gettop(&L);
    lua.lua_pushnumber(&L, 99.0);
    lua.lua_setfield(&L, parent_idx, "x");

    // child is empty; mt.__index = parent
    lua.lua_createtable(&L, 0, 0);
    const child_idx: i32 = lua.lua_gettop(&L);

    lua.lua_createtable(&L, 0, 1);
    const child_mt_idx: i32 = lua.lua_gettop(&L);
    lua.lua_pushvalue(&L, parent_idx);
    lua.lua_setfield(&L, child_mt_idx, "__index");
    try std.testing.expectEqual(@as(i32, 1), lua.lua_setmetatable(&L, child_idx));

    // child["x"] should follow chain -> parent -> 99
    _ = lua.lua_getfield(&L, child_idx, "x");
    const v = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, 99.0), v);
}

test "__newindex function metamethod via C API" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // shadow table to capture writes
    lua.lua_createtable(&L, 0, 0);
    const shadow_idx: i32 = lua.lua_gettop(&L); // absolute index 1 in clean state

    // proxy table (empty) with __newindex that forwards to shadow
    lua.lua_createtable(&L, 0, 0);
    const proxy_idx: i32 = lua.lua_gettop(&L);

    lua.lua_createtable(&L, 0, 1);
    const proxy_mt_idx: i32 = lua.lua_gettop(&L);

    // __newindex function: writes value to shadow["written"]
    // shadow is at absolute stack index shadow_idx (captured by value in the closure)
    const NewIdxFn = struct {
        fn newindex(LS: *lua.lua_State) anyerror!i32 {
            // LS: stack[1]=proxy, stack[2]=key, stack[3]=value
            // shadow is absolute slot 1 of the outer Lua state — we use the
            // upvalue closure trick here for simplicity: just push to stack[1].
            // Since C functions get a fresh base, we use lua_pushvalue to shadow.
            lua.lua_pushvalue(LS, 3); // value
            // write to the upvalue table at slot 1 (shadow in the outer test)
            // — we can't easily reference the outer L here, so instead we
            // capture shadow via a C closure upvalue.
            lua.lua_setupvalue(LS, 1); // shadow["written"] = value
            return 0;
        }
    };
    _ = NewIdxFn.newindex; // referenced below via a simpler approach

    // Simpler approach: use a CClosure with shadow as upvalue index 1
    const NewIdxSimple = struct {
        fn newindex(LS: *lua.lua_State) anyerror!i32 {
            // upvalue 1 = shadow table (set via lua_pushcclosure below)
            // args: t(1), key(2), val(3)
            lua.lua_pushvalue(LS, 3); // val
            lua.lua_setfield(LS, lua.lua_upvalueindex(1), "written");
            return 0;
        }
    };
    lua.lua_pushvalue(&L, shadow_idx); // upvalue 1 = shadow
    lua.lua_pushcclosure(&L, NewIdxSimple.newindex, 1);
    lua.lua_setfield(&L, proxy_mt_idx, "__newindex");
    try std.testing.expectEqual(@as(i32, 1), lua.lua_setmetatable(&L, proxy_idx));

    // proxy["key"] = 77 — triggers __newindex
    lua.lua_pushnumber(&L, 77.0);
    lua.lua_setfield(&L, proxy_idx, "key");

    // shadow["written"] should now be 77
    _ = lua.lua_getfield(&L, shadow_idx, "written");
    const v = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, 77.0), v);
}

test "bitwise shift operations with negative and large shift" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // Test luaV_shift helper directly (i64 shifts with u64 semantics)
    // 1 << 1 = 2
    try std.testing.expectEqual(@as(i64, 2), lua.luaV_shift(1, 1));
    // 1 >> 1 = 0  (via negative shift)
    try std.testing.expectEqual(@as(i64, 0), lua.luaV_shift(1, -1));
    // 2 << 2 = 8
    try std.testing.expectEqual(@as(i64, 8), lua.luaV_shift(2, 2));
    // 16 >> 2 = 4
    try std.testing.expectEqual(@as(i64, 4), lua.luaV_shift(16, -2));
    // -8 << 1 = -16
    try std.testing.expectEqual(@as(i64, -16), lua.luaV_shift(-8, 1));
    // Large shift: 1 << 70 = 1 << (70 & 0x3F) = 1 << 6 = 64
    try std.testing.expectEqual(@as(i64, 64), lua.luaV_shift(1, 70));
    // Negative large: 1 << -70 = 1 >> (70 & 0x3F) = 1 >> 6 = 0
    try std.testing.expectEqual(@as(i64, 0), lua.luaV_shift(1, -70));

    // Test via C API lua_arith
    // 8 << 2
    lua.lua_pushnumber(&L, 8.0);
    lua.lua_pushnumber(&L, 2.0);
    lua.lua_arith(&L, lua.LUA_OPSHL);
    const r1 = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, 32.0), r1);
    lua.lua_pop(&L, 1);

    // 8 >> 2 = 2
    lua.lua_pushnumber(&L, 8.0);
    lua.lua_pushnumber(&L, 2.0);
    lua.lua_arith(&L, lua.LUA_OPSHR);
    const r2 = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, 2.0), r2);
    lua.lua_pop(&L, 1);

    // Negative shift: 1 << -1 => 1 >> 1 = 0
    lua.lua_pushnumber(&L, 1.0);
    lua.lua_pushnumber(&L, -1.0);
    lua.lua_arith(&L, lua.LUA_OPSHL);
    const r3 = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, 0.0), r3);
    lua.lua_pop(&L, 1);
}

test "__add arithmetic metamethod via C API" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // Create table t1
    lua.lua_createtable(&L, 0, 0);
    const t1_idx = lua.lua_gettop(&L);

    // Create table t2
    lua.lua_createtable(&L, 0, 0);
    const t2_idx = lua.lua_gettop(&L);

    // Create metatable mt
    lua.lua_createtable(&L, 0, 1);
    const mt_idx = lua.lua_gettop(&L);

    // Push __add function: returns a dummy number, say 123
    const AddFn = struct {
        fn add(LS: *lua.lua_State) anyerror!i32 {
            // args: operand1(1), operand2(2)
            lua.lua_pushnumber(LS, 123.0);
            return 1;
        }
    };
    lua.lua_pushcfunction(&L, AddFn.add);
    lua.lua_setfield(&L, mt_idx, "__add");

    // Set mt on t1
    lua.lua_pushvalue(&L, mt_idx);
    _ = lua.lua_setmetatable(&L, t1_idx);

    // Push t1 and t2 onto the stack
    lua.lua_pushvalue(&L, t1_idx);
    lua.lua_pushvalue(&L, t2_idx);

    // Call lua_arith(L, LUA_OPADD)
    lua.lua_arith(&L, lua.LUA_OPADD);

    // Expect the result to be 123.0 on top of the stack
    const v = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, 123.0), v);
}

test "VM execution of arithmetic metamethod" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    var threaded: std.Io.Threaded = .init_single_threaded;
    const io = threaded.io();
    const bytecode = try std.Io.Dir.cwd().readFileAlloc(io, "tests/test_add.luac", gpa, .unlimited);
    defer gpa.free(bytecode);

    var reader_state = StringReaderState{
        .code = bytecode,
        .read_done = false,
    };

    const status = lua.lua_load(&L, stringReader, &reader_state, "test_add.luac", "b");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);

    // Perform a protected call on the loaded chunk (0 arguments, 1 result expected)
    // This executes the chunk which returns the closure function.
    const load_pcall = lua.lua_pcallk(&L, 0, 1, 0, 0, null);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), load_pcall);

    // Create table t1
    lua.lua_createtable(&L, 0, 0);

    // Create table t2
    lua.lua_createtable(&L, 0, 0);

    // Create metatable mt
    lua.lua_createtable(&L, 0, 1);
    const mt_idx = lua.lua_gettop(&L);

    // Push __add function: returns 999.0
    const AddFn = struct {
        fn add(LS: *lua.lua_State) anyerror!i32 {
            lua.lua_pushnumber(LS, 999.0);
            return 1;
        }
    };
    lua.lua_pushcfunction(&L, AddFn.add);
    lua.lua_setfield(&L, mt_idx, "__add");

    // Set mt on t1 (t1 is at stack index 2)
    lua.lua_pushvalue(&L, mt_idx);
    _ = lua.lua_setmetatable(&L, 2);

    // Pop mt from the stack
    lua.lua_pop(&L, 1);

    // Stack currently:
    // 1: Loaded closure function
    // 2: t1
    // 3: t2
    try std.testing.expectEqual(@as(i32, 3), lua.lua_gettop(&L));

    // Call the closure function with t1 and t2
    const pcall_status = lua.lua_pcallk(&L, 2, 1, 0, 0, null);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), pcall_status);

    // The top of the stack should contain the returned number 999.0
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(&L));
    try std.testing.expectEqual(@as(i32, lua.LUA_TNUMBER), lua.lua_type(&L, -1));
    const result = L.stack[L.top - 1].number;
    try std.testing.expectEqual(@as(f64, 999.0), result);
}

test "__eq metamethod via C API" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0); // t1 (idx 1)
    const t1_idx = lua.lua_gettop(&L);

    lua.lua_createtable(&L, 0, 0); // t2 (idx 2)
    const t2_idx = lua.lua_gettop(&L);

    lua.lua_createtable(&L, 0, 1); // mt (idx 3)
    const mt_idx = lua.lua_gettop(&L);

    const EqFn = struct {
        fn eq(LS: *lua.lua_State) anyerror!i32 {
            lua.lua_pushboolean(LS, 1);
            return 1;
        }
    };
    lua.lua_pushcfunction(&L, EqFn.eq);
    lua.lua_setfield(&L, mt_idx, "__eq");

    // Set mt on t1
    lua.lua_pushvalue(&L, mt_idx);
    _ = lua.lua_setmetatable(&L, t1_idx);

    // Set mt on t2
    lua.lua_pushvalue(&L, mt_idx);
    _ = lua.lua_setmetatable(&L, t2_idx);

    lua.lua_pop(&L, 1); // pop mt

    const cond = lua.lua_compare(&L, t1_idx, t2_idx, lua.LUA_OPEQ);
    try std.testing.expectEqual(@as(i32, 1), cond);
}

test "__lt and __le metamethods via C API" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0); // t1 (idx 1)
    const t1_idx = lua.lua_gettop(&L);

    lua.lua_createtable(&L, 0, 0); // t2 (idx 2)
    const t2_idx = lua.lua_gettop(&L);

    lua.lua_createtable(&L, 0, 2); // mt (idx 3)
    const mt_idx = lua.lua_gettop(&L);

    const LtFn = struct {
        fn lt(LS: *lua.lua_State) anyerror!i32 {
            lua.lua_pushboolean(LS, 1);
            return 1;
        }
    };
    lua.lua_pushcfunction(&L, LtFn.lt);
    lua.lua_setfield(&L, mt_idx, "__lt");

    const LeFn = struct {
        fn le(LS: *lua.lua_State) anyerror!i32 {
            lua.lua_pushboolean(LS, 1);
            return 1;
        }
    };
    lua.lua_pushcfunction(&L, LeFn.le);
    lua.lua_setfield(&L, mt_idx, "__le");

    // Set mt on t1
    lua.lua_pushvalue(&L, mt_idx);
    _ = lua.lua_setmetatable(&L, t1_idx);

    // Set mt on t2
    lua.lua_pushvalue(&L, mt_idx);
    _ = lua.lua_setmetatable(&L, t2_idx);

    lua.lua_pop(&L, 1); // pop mt

    const cond_lt = lua.lua_compare(&L, t1_idx, t2_idx, lua.LUA_OPLT);
    try std.testing.expectEqual(@as(i32, 1), cond_lt);

    const cond_le = lua.lua_compare(&L, t1_idx, t2_idx, lua.LUA_OPLE);
    try std.testing.expectEqual(@as(i32, 1), cond_le);
}

test "error propagation and pcall" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // Push a C function that throws an error
    const ErrorFn = struct {
        fn run(LS: *lua.lua_State) anyerror!i32 {
            _ = lua.lua_pushstring(LS, "my custom error");
            return lua.lua_error(LS);
        }
    };
    lua.lua_pushcfunction(&L, ErrorFn.run);

    // Call it protected
    const status = lua.lua_pcallk(&L, 0, 0, 0, 0, null);
    try std.testing.expectEqual(@as(i32, lua.LUA_ERRRUN), status);

    // The top of the stack should contain the error object "my custom error"
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(&L));
    const err_msg = lua.lua_tolstring(&L, -1, null) orelse return error.TestFailed;
    try std.testing.expectEqualStrings("my custom error", err_msg);
}

test "pcall with errfunc error handler" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // Push error handler function: appends " handled" to the message
    const HandlerFn = struct {
        fn handle(LS: *lua.lua_State) anyerror!i32 {
            const msg = lua.lua_tolstring(LS, 1, null) orelse "no msg";
            _ = msg;
            _ = lua.lua_pushstring(LS, "custom error handled");
            return 1;
        }
    };
    lua.lua_pushcfunction(&L, HandlerFn.handle);
    const handler_idx = lua.lua_gettop(&L);

    // Push the function that throws an error
    const ErrorFn = struct {
        fn run(LS: *lua.lua_State) anyerror!i32 {
            _ = lua.lua_pushstring(LS, "original error");
            return lua.lua_error(LS);
        }
    };
    lua.lua_pushcfunction(&L, ErrorFn.run);


    // Call it protected with the error handler at handler_idx
    const status = lua.lua_pcallk(&L, 0, 0, handler_idx, 0, null);
    try std.testing.expectEqual(@as(i32, lua.LUA_ERRRUN), status);

    // The top of the stack should contain the handled error object "custom error handled"
    try std.testing.expectEqual(@as(i32, 2), lua.lua_gettop(&L));
    const err_msg = lua.lua_tolstring(&L, -1, null) orelse return error.TestFailed;
    try std.testing.expectEqualStrings("custom error handled", err_msg);
}

test "garbage collector mark and sweep" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const g = L.l_G.?;

    // Count initial objects
    var init_count: usize = 0;
    var curr = g.allgc;
    while (curr) |gc| {
        init_count += 1;
        curr = gc.next;
    }

    // 1. Create a table and push it on the stack (referenced!)
    lua.lua_createtable(&L, 0, 0);

    // 2. Create another table and push it, then pop it (unreferenced!)
    lua.lua_createtable(&L, 0, 0);
    lua.lua_pop(&L, 1);

    // 3. Create a string and push it on the stack (referenced!)
    _ = lua.lua_pushstring(&L, "referenced_string");

    // 4. Create another string, push it, then pop it (unreferenced!)
    _ = lua.lua_pushstring(&L, "unreferenced_string");
    lua.lua_pop(&L, 1);

    // Verify that the string table contains both strings
    try std.testing.expect(g.strt.contains("referenced_string"));
    try std.testing.expect(g.strt.contains("unreferenced_string"));

    // Run Garbage Collection
    const status = lua.lua_gc(&L, lua.LUA_GCCOLLECT, 0);
    try std.testing.expectEqual(@as(i32, 0), status);

    // Verify that:
    // - The referenced table is NOT collected.
    // - The unreferenced table IS collected.
    // - The referenced string is NOT collected.
    // - The unreferenced string IS collected (removed from strt).
    try std.testing.expect(g.strt.contains("referenced_string"));
    try std.testing.expect(!g.strt.contains("unreferenced_string"));

    // Count remaining GC objects
    var end_count: usize = 0;
    curr = g.allgc;
    while (curr) |gc| {
        end_count += 1;
        curr = gc.next;
    }

    // We added 2 tables, 1 should be swept.
    // So end_count should be init_count + 1.
    try std.testing.expectEqual(init_count + 1, end_count);

    // Pop the remaining table and string
    lua.lua_pop(&L, 2);

    // Run GC again — now everything we created should be collected!
    _ = lua.lua_gc(&L, lua.LUA_GCCOLLECT, 0);

    // Verify both are gone
    try std.testing.expect(!g.strt.contains("referenced_string"));

    var final_count: usize = 0;
    curr = g.allgc;
    while (curr) |gc| {
        final_count += 1;
        curr = gc.next;
    }
    try std.testing.expectEqual(init_count, final_count);
}


// ===================================================================
// Phase F — Base Library Tests
// ===================================================================

test "baselib: type() function" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const typefn = struct {
        fn f(Ls: *lua.lua_State) anyerror!i32 {
            // type(nil) == "nil"
            lua.lua_pushnil(Ls);
            _ = lua.lua_getglobal(Ls, "type");
            lua.lua_pushvalue(Ls, -2);
            try lua.lua_call(Ls, 1, 1);
            const s = lua.lua_tostring(Ls, -1);
            if (s == null or !std.mem.eql(u8, s.?, "nil")) return error.TypeMismatchNil;
            lua.lua_pop(Ls, 2);

            // type(true) == "boolean"
            lua.lua_pushboolean(Ls, 1);
            _ = lua.lua_getglobal(Ls, "type");
            lua.lua_pushvalue(Ls, -2);
            try lua.lua_call(Ls, 1, 1);
            const s2 = lua.lua_tostring(Ls, -1);
            if (s2 == null or !std.mem.eql(u8, s2.?, "boolean")) return error.TypeMismatchBool;
            lua.lua_pop(Ls, 2);

            // type(42) == "number"
            lua.lua_pushinteger(Ls, 42);
            _ = lua.lua_getglobal(Ls, "type");
            lua.lua_pushvalue(Ls, -2);
            try lua.lua_call(Ls, 1, 1);
            const s3 = lua.lua_tostring(Ls, -1);
            if (s3 == null or !std.mem.eql(u8, s3.?, "number")) return error.TypeMismatchNum;
            lua.lua_pop(Ls, 2);

            return 0;
        }
    }.f;
    lua.lua_pushcfunction(&L, typefn);
    const status = lua.lua_pcallk(&L, 0, 0, 0, 0, null);
    try std.testing.expectEqual(lua.LUA_OK, status);
}

test "baselib: rawequal(), rawlen(), rawget(), rawset()" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const testfn = struct {
        fn f(Ls: *lua.lua_State) anyerror!i32 {
            // rawequal(1, 1) == true
            _ = lua.lua_getglobal(Ls, "rawequal");
            lua.lua_pushinteger(Ls, 1);
            lua.lua_pushinteger(Ls, 1);
            try lua.lua_call(Ls, 2, 1);
            if (lua.lua_toboolean(Ls, -1) == 0) return error.FailedRawEqual;
            lua.lua_pop(Ls, 1);

            // Create a table and use rawset/rawget
            lua.lua_newtable(Ls);
            // rawset(t, "k", 99)
            _ = lua.lua_getglobal(Ls, "rawset");
            lua.lua_pushvalue(Ls, -2); // table
            _ = lua.lua_pushstring(Ls, "k");
            lua.lua_pushinteger(Ls, 99);
            try lua.lua_call(Ls, 3, 0);

            // rawget(t, "k") == 99
            _ = lua.lua_getglobal(Ls, "rawget");
            lua.lua_pushvalue(Ls, -2); // table
            _ = lua.lua_pushstring(Ls, "k");
            try lua.lua_call(Ls, 2, 1);
            const r_val = lua.lua_tointeger(Ls, -1);
            if (r_val orelse 0 != 99) return error.FailedRawGet;
            lua.lua_pop(Ls, 1);

            // rawlen({}) == 0
            _ = lua.lua_getglobal(Ls, "rawlen");
            lua.lua_pushvalue(Ls, -2); // table
            try lua.lua_call(Ls, 1, 1);
            const r_len = lua.lua_tointeger(Ls, -1);
            if (r_len orelse -1 != 0) return error.FailedRawLen;
            lua.lua_pop(Ls, 2);

            return 0;
        }
    }.f;
    lua.lua_pushcfunction(&L, testfn);
    const status = lua.lua_pcallk(&L, 0, 0, 0, 0, null);
    try std.testing.expectEqual(lua.LUA_OK, status);
}

test "baselib: setmetatable() and getmetatable()" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const testfn = struct {
        fn f(Ls: *lua.lua_State) anyerror!i32 {
            // getmetatable(t) before setting — should be nil
            lua.lua_newtable(Ls); // t at -1
            _ = lua.lua_getglobal(Ls, "getmetatable");
            lua.lua_pushvalue(Ls, -2);
            try lua.lua_call(Ls, 1, 1);
            if (lua.lua_type(Ls, -1) != lua.LUA_TNIL) return error.ShouldBeNil;
            lua.lua_pop(Ls, 1);

            // setmetatable(t, mt)
            lua.lua_newtable(Ls); // mt at -1
            _ = lua.lua_getglobal(Ls, "setmetatable");
            lua.lua_pushvalue(Ls, -3); // t
            lua.lua_pushvalue(Ls, -3); // mt
            try lua.lua_call(Ls, 2, 0);

            // getmetatable(t) == mt
            _ = lua.lua_getglobal(Ls, "getmetatable");
            lua.lua_pushvalue(Ls, -3); // t
            try lua.lua_call(Ls, 1, 1);
            if (lua.lua_type(Ls, -1) != lua.LUA_TTABLE) return error.ShouldBeTable;
            lua.lua_pop(Ls, 3);

            return 0;
        }
    }.f;
    lua.lua_pushcfunction(&L, testfn);
    const status = lua.lua_pcallk(&L, 0, 0, 0, 0, null);
    try std.testing.expectEqual(lua.LUA_OK, status);
}

test "baselib: tonumber() and tostring()" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const testfn = struct {
        fn f(Ls: *lua.lua_State) anyerror!i32 {
            // tonumber("42") == 42
            _ = lua.lua_getglobal(Ls, "tonumber");
            _ = lua.lua_pushstring(Ls, "42");
            try lua.lua_call(Ls, 1, 1);
            if (lua.lua_tointeger(Ls, -1) orelse -1 != 42) return error.FailedToNum1;
            lua.lua_pop(Ls, 1);

            // tonumber("ff", 16) == 255
            _ = lua.lua_getglobal(Ls, "tonumber");
            _ = lua.lua_pushstring(Ls, "ff");
            lua.lua_pushinteger(Ls, 16);
            try lua.lua_call(Ls, 2, 1);
            if (lua.lua_tointeger(Ls, -1) orelse -1 != 255) return error.FailedToNum2;
            lua.lua_pop(Ls, 1);

            // tonumber("hello") == nil
            _ = lua.lua_getglobal(Ls, "tonumber");
            _ = lua.lua_pushstring(Ls, "hello");
            try lua.lua_call(Ls, 1, 1);
            if (lua.lua_type(Ls, -1) != lua.LUA_TNIL) return error.ShouldBeNil;
            lua.lua_pop(Ls, 1);

            // tostring(42) == "42"
            _ = lua.lua_getglobal(Ls, "tostring");
            lua.lua_pushinteger(Ls, 42);
            try lua.lua_call(Ls, 1, 1);
            const s = lua.lua_tostring(Ls, -1);
            if (s == null or !std.mem.eql(u8, s.?, "42")) return error.FailedToStr;
            lua.lua_pop(Ls, 1);

            return 0;
        }
    }.f;
    lua.lua_pushcfunction(&L, testfn);
    const status = lua.lua_pcallk(&L, 0, 0, 0, 0, null);
    try std.testing.expectEqual(lua.LUA_OK, status);
}

test "baselib: select()" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const testfn = struct {
        fn f(Ls: *lua.lua_State) anyerror!i32 {
            // select("#", a, b, c) == 3
            _ = lua.lua_getglobal(Ls, "select");
            _ = lua.lua_pushstring(Ls, "#");
            lua.lua_pushinteger(Ls, 10);
            lua.lua_pushinteger(Ls, 20);
            lua.lua_pushinteger(Ls, 30);
            try lua.lua_call(Ls, 4, 1);
            const r1 = lua.lua_tointeger(Ls, -1);
            if (r1 orelse -1 != 3) return error.FailedCount;
            lua.lua_pop(Ls, 1);

            // select(2, 10, 20, 30) returns 20, 30 (2 results)
            _ = lua.lua_getglobal(Ls, "select");
            lua.lua_pushinteger(Ls, 2);
            lua.lua_pushinteger(Ls, 10);
            lua.lua_pushinteger(Ls, 20);
            lua.lua_pushinteger(Ls, 30);
            try lua.lua_call(Ls, 4, lua.LUA_MULTRET);
            const top = lua.lua_gettop(Ls);
            if (top != 2) return error.WrongCount;
            if (lua.lua_tointeger(Ls, 1) orelse -1 != 20) return error.FailedVal1;
            if (lua.lua_tointeger(Ls, 2) orelse -1 != 30) return error.FailedVal2;
            lua.lua_settop(Ls, 0);

            return 0;
        }
    }.f;
    lua.lua_pushcfunction(&L, testfn);
    const status = lua.lua_pcallk(&L, 0, 0, 0, 0, null);
    try std.testing.expectEqual(lua.LUA_OK, status);
}
