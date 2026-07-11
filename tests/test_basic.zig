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
    try lua.lua_setfield(&L, -2, "key");
    _ = try lua.lua_getfield(&L, -1, "key");
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
        try lua.lua_seti(&L, -2, i);
    }
    _ = try lua.lua_geti(&L, -1, 3);
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
    try lua.lua_seti(&L, -2, 1);
    try std.testing.expectEqual(@as(usize, 1), lua.lua_rawlen(&L, -1));
    lua.lua_pushnil(&L);
    try lua.lua_seti(&L, -2, 1);
    try std.testing.expectEqual(@as(usize, 0), lua.lua_rawlen(&L, -1));
}

test "table hash part stores string keys" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 4);
    _ = lua.lua_pushstring(&L, "v");
    try lua.lua_setfield(&L, -2, "k");
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
    try lua.lua_seti(&L, -2, 1);
    lua.lua_pushinteger(&L, 20);
    try lua.lua_seti(&L, -2, 2);
    _ = lua.lua_pushstring(&L, "x");
    try lua.lua_setfield(&L, -2, "a");

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
    try lua.lua_settable(&L, -3);
    _ = lua.lua_pushstring(&L, "name");
    _ = try lua.lua_gettable(&L, -2);
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

test "numeric for loop register layout" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // Craft a proto for: for i=1,3 do end
    // Register layout: R0=init, R1=limit, R2=step
    // After PREP (matches C ref float path):
    //   R0 = limit, R1 = step, R2 = init (control var)
    // FORLOOP: reads R2 (idx), R1 (step), R0 (limit);
    //   writes updated idx to R2 and R3; loops back
    // After loop ends (idx > limit), R0 = limit = 3

    var code = try gpa.alloc(lua.lvm.Instruction, 6);

    var inst: lua.lvm.Instruction = 0;
    // LOADI R0 1     ; init = 1
    lua.lvm.SET_OPCODE(&inst, .LOADI);
    lua.lvm.SETARG_A(&inst, 0);
    lua.lvm.SETARG_sBx(&inst, 1);
    code[0] = inst;

    // LOADI R1 3     ; limit = 3
    inst = 0;
    lua.lvm.SET_OPCODE(&inst, .LOADI);
    lua.lvm.SETARG_A(&inst, 1);
    lua.lvm.SETARG_sBx(&inst, 3);
    code[1] = inst;

    // LOADI R2 1     ; step = 1
    inst = 0;
    lua.lvm.SET_OPCODE(&inst, .LOADI);
    lua.lvm.SETARG_A(&inst, 2);
    lua.lvm.SETARG_sBx(&inst, 1);
    code[2] = inst;

    // FORPREP R0 0   ; skip+1 = PC 5 (RETURN1) if empty loop
    inst = 0;
    lua.lvm.SET_OPCODE(&inst, .FORPREP);
    lua.lvm.SETARG_A(&inst, 0);
    lua.lvm.SETARG_Bx(&inst, 0);
    code[3] = inst;

    // FORLOOP R0 1   ; jump back to self (empty body)
    inst = 0;
    lua.lvm.SET_OPCODE(&inst, .FORLOOP);
    lua.lvm.SETARG_A(&inst, 0);
    lua.lvm.SETARG_Bx(&inst, 1);
    code[4] = inst;

    // RETURN1 R0     ; returns R0 = limit (3 after FORPREP scramble)
    inst = 0;
    lua.lvm.SET_OPCODE(&inst, .RETURN1);
    lua.lvm.SETARG_A(&inst, 0);
    code[5] = inst;

    const proto = try lua.createProto(gpa);
    proto.* = lua.lua_Proto{
        .source = null,
        .lineDefined = 0,
        .lastLineDefined = 0,
        .numParams = 0,
        .isVarArg = false,
        .maxStackSize = 4,
        .code = code,
        .k = &.{},
        .p = &.{},
        .upvalues = &.{},
        .lineinfo = &.{},
        .abslineinfo = &.{},
        .locvars = &.{},
    };
    try lua.registerGC(&L, proto);

    const lc = try gpa.create(lua.lua_LClosure);
    lc.* = .{
        .p = proto,
        .upvals = try gpa.alloc(?*lua.UpVal, 0),
    };
    const closure = try gpa.create(lua.lua_Closure);
    closure.* = .{ .lua = lc };
    try lua.registerGC(&L, closure);

    L.stack[L.top] = lua.TValue{ .function = closure };
    L.top += 1;

    const func_idx = L.top - 1;
    const new_ci = (try lua.precall(&L, func_idx, 1)) orelse return error.NoFrame;
    try lua.lvm.run(&L, new_ci);

    try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(&L));
    const result = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, 3.0), result);
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
    try lua.lua_setfield(&L, mt_idx, "__index");

    // setmetatable(t, mt)
    try std.testing.expectEqual(@as(i32, 1), lua.lua_setmetatable(&L, t_idx));

    // t["missing"] should invoke __index and return 42
    _ = try lua.lua_getfield(&L, t_idx, "missing");
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
    try lua.lua_setfield(&L, parent_idx, "x");

    // child is empty; mt.__index = parent
    lua.lua_createtable(&L, 0, 0);
    const child_idx: i32 = lua.lua_gettop(&L);

    lua.lua_createtable(&L, 0, 1);
    const child_mt_idx: i32 = lua.lua_gettop(&L);
    lua.lua_pushvalue(&L, parent_idx);
    try lua.lua_setfield(&L, child_mt_idx, "__index");
    try std.testing.expectEqual(@as(i32, 1), lua.lua_setmetatable(&L, child_idx));

    // child["x"] should follow chain -> parent -> 99
    _ = try lua.lua_getfield(&L, child_idx, "x");
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
            try lua.lua_setfield(LS, lua.lua_upvalueindex(1), "written");
            return 0;
        }
    };
    lua.lua_pushvalue(&L, shadow_idx); // upvalue 1 = shadow
    lua.lua_pushcclosure(&L, NewIdxSimple.newindex, 1);
    try lua.lua_setfield(&L, proxy_mt_idx, "__newindex");
    try std.testing.expectEqual(@as(i32, 1), lua.lua_setmetatable(&L, proxy_idx));

    // proxy["key"] = 77 — triggers __newindex
    lua.lua_pushnumber(&L, 77.0);
    try lua.lua_setfield(&L, proxy_idx, "key");

    // shadow["written"] should now be 77
    _ = try lua.lua_getfield(&L, shadow_idx, "written");
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
    try lua.lua_setfield(&L, mt_idx, "__add");

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
    try lua.lua_setfield(&L, mt_idx, "__add");

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
    try lua.lua_setfield(&L, mt_idx, "__eq");

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
    try lua.lua_setfield(&L, mt_idx, "__lt");

    const LeFn = struct {
        fn le(LS: *lua.lua_State) anyerror!i32 {
            lua.lua_pushboolean(LS, 1);
            return 1;
        }
    };
    lua.lua_pushcfunction(&L, LeFn.le);
    try lua.lua_setfield(&L, mt_idx, "__le");

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

test "utf8: utf8 library" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const T = struct {
        fn g(Ls: *lua.lua_State, name: []const u8) !void {
            _ = lua.lua_getglobal(Ls, "utf8");
            _ = try lua.lua_getfield(Ls, -1, name);
        }
    };

    // utf8.char(65) -> "A"
    try T.g(&L, "char");
    lua.lua_pushinteger(&L, 65);
    try lua.lua_call(&L, 1, 1);
    const a = lua.lua_tolstring(&L, -1, null) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "A", a);
    lua.lua_pop(&L, 2);

    // utf8.char(0x1F600) -> 4-byte sequence (emoji)
    try T.g(&L, "char");
    lua.lua_pushinteger(&L, 0x1F600);
    try lua.lua_call(&L, 1, 1);
    const emoji = lua.lua_tolstring(&L, -1, null) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(usize, 4), emoji.len);
    try std.testing.expectEqual(@as(u8, 0xF0), emoji[0]);
    lua.lua_pop(&L, 2);

    // utf8.codepoint("é") -> 233 (U+00E9)
    try T.g(&L, "codepoint");
    _ = lua.lua_pushlstring(&L, "é", 2);
    try lua.lua_call(&L, 1, 1);
    const cp = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 233), cp);
    lua.lua_pop(&L, 2);

    // utf8.codepoint("A", 1, 1) -> 65 (single value)
    try T.g(&L, "codepoint");
    _ = lua.lua_pushlstring(&L, "A", 1);
    lua.lua_pushinteger(&L, 1);
    lua.lua_pushinteger(&L, 1);
    try lua.lua_call(&L, 3, 1);
    const cp2 = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 65), cp2);
    lua.lua_pop(&L, 2);

    // utf8.codepoint("AB", 1, 2) -> two values 65, 66
    try T.g(&L, "codepoint");
    _ = lua.lua_pushlstring(&L, "AB", 2);
    lua.lua_pushinteger(&L, 1);
    lua.lua_pushinteger(&L, 2);
    try lua.lua_call(&L, 3, 2);
    const v1 = lua.lua_tointeger(&L, -2) orelse return error.TestFailed;
    const v2 = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 65), v1);
    try std.testing.expectEqual(@as(i64, 66), v2);
    lua.lua_pop(&L, 2);

    // utf8.len("Hello") -> 5
    try T.g(&L, "len");
    _ = lua.lua_pushlstring(&L, "Hello", 5);
    try lua.lua_call(&L, 1, 1);
    const hl = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 5), hl);
    lua.lua_pop(&L, 2);

    // utf8.len("é") -> 1 (2 bytes, 1 char)
    try T.g(&L, "len");
    _ = lua.lua_pushlstring(&L, "é", 2);
    try lua.lua_call(&L, 1, 1);
    const e1 = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 1), e1);
    lua.lua_pop(&L, 2);

    // utf8.len of invalid sequence "a\xff" -> nil (first result)
    try T.g(&L, "len");
    const bad = [_]u8{ 'a', 0xFF };
    _ = lua.lua_pushlstring(&L, &bad, bad.len);
    try lua.lua_call(&L, 1, 1);
    try std.testing.expect(lua.lua_isnil(&L, -1) != 0);
    lua.lua_pop(&L, 2);

    // utf8.offset("Hello", 4) -> 4
    try T.g(&L, "offset");
    _ = lua.lua_pushlstring(&L, "Hello", 5);
    lua.lua_pushinteger(&L, 4);
    try lua.lua_call(&L, 2, 1);
    const off = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 4), off);
    lua.lua_pop(&L, 2);

    // utf8.offset on a multibyte string: "éx" -> byte position of 'x' is 3
    try T.g(&L, "offset");
    _ = lua.lua_pushlstring(&L, "éx", 3);
    lua.lua_pushinteger(&L, 2);
    try lua.lua_call(&L, 2, 1);
    const off2 = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 3), off2);
    lua.lua_pop(&L, 2);

    // utf8.len of mixed 2-char string "éA" -> 2
    try T.g(&L, "len");
    _ = lua.lua_pushlstring(&L, "éA", 3);
    try lua.lua_call(&L, 1, 1);
    const e2 = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 2), e2);
    lua.lua_pop(&L, 2);

    // utf8.codes("AB") iterator: first call yields (pos=1, codepoint=65)
    _ = lua.lua_getglobal(&L, "utf8");
    _ = try lua.lua_getfield(&L, -1, "codes");
    _ = lua.lua_pushlstring(&L, "AB", 2);
    try lua.lua_call(&L, 1, 3); // stack: [utf8, f, s, 0]
    try lua.lua_call(&L, 2, 2); // call f(s, 0) -> (pos, codepoint)
    const pv = lua.lua_tointeger(&L, -2) orelse return error.TestFailed;
    const cv = lua.lua_tointeger(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(i64, 1), pv);
    try std.testing.expectEqual(@as(i64, 65), cv);
    lua.lua_pop(&L, 3);

    // utf8.charpattern is a string
    _ = lua.lua_getglobal(&L, "utf8");
    _ = try lua.lua_getfield(&L, -1, "charpattern");
    try std.testing.expect(lua.lua_isstring(&L, -1) != 0);
    lua.lua_pop(&L, 2);

    // utf8.codepoint on an invalid byte raises an error
    lua.lua_pushcfunction(&L, struct {
        fn cf(Ls: *lua.lua_State) anyerror!i32 {
            _ = lua.lua_getglobal(Ls, "utf8");
            _ = try lua.lua_getfield(Ls, -1, "codepoint");
            _ = lua.lua_pushlstring(Ls, "\xff", 1);
            try lua.lua_call(Ls, 1, 1);
            return 1;
        }
    }.cf);
    const status = lua.lua_pcallk(&L, 0, 0, 0, 0, null);
    try std.testing.expectEqual(lua.LUA_ERRRUN, status);
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

test "mathlib: constants and basic functions" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const testfn = struct {
        fn f(Ls: *lua.lua_State) anyerror!i32 {
            // math.pi
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "pi");
            const pi = lua.lua_tonumber(Ls, -1) orelse return error.NoPi;
            try std.testing.expect(std.math.approxEqAbs(f64, pi, std.math.pi, 0.0001));
            lua.lua_pop(Ls, 1);

            // math.huge
            _ = try lua.lua_getfield(Ls, -1, "huge");
            const huge = lua.lua_tonumber(Ls, -1) orelse return error.NoHuge;
            try std.testing.expect(huge > 1e308);
            lua.lua_pop(Ls, 1);

            // math.maxinteger (compare as float due to f64 precision)
            _ = try lua.lua_getfield(Ls, -1, "maxinteger");
            const maxint = lua.lua_tonumber(Ls, -1) orelse return error.NoMaxInt;
            try std.testing.expectApproxEqAbs(@as(f64, @floatFromInt(lua.LUA_MAXINTEGER)), maxint, 1.0);
            lua.lua_pop(Ls, 1);

            // math.mininteger
            _ = try lua.lua_getfield(Ls, -1, "mininteger");
            const minint = lua.lua_tonumber(Ls, -1) orelse return error.NoMinInt;
            try std.testing.expectApproxEqAbs(@as(f64, @floatFromInt(lua.LUA_MININTEGER)), minint, 1.0);
            lua.lua_pop(Ls, 2);

            // math.abs(-5) == 5 (integer)
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "abs");
            lua.lua_pushinteger(Ls, -5);
            try lua.lua_call(Ls, 1, 1);
            const abs_i = lua.lua_tointeger(Ls, -1) orelse return error.NoAbsInt;
            try std.testing.expectEqual(@as(i64, 5), abs_i);
            lua.lua_pop(Ls, 2);

            // math.abs(-3.5) == 3.5 (float)
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "abs");
            lua.lua_pushnumber(Ls, -3.5);
            try lua.lua_call(Ls, 1, 1);
            const abs_f = lua.lua_tonumber(Ls, -1) orelse return error.NoAbsFloat;
            try std.testing.expectEqual(@as(f64, 3.5), abs_f);
            lua.lua_pop(Ls, 2);

            // math.floor(3.7) == 3
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "floor");
            lua.lua_pushnumber(Ls, 3.7);
            try lua.lua_call(Ls, 1, 1);
            const fl = lua.lua_tointeger(Ls, -1) orelse return error.NoFloor;
            try std.testing.expectEqual(@as(i64, 3), fl);
            lua.lua_pop(Ls, 2);

            // math.ceil(3.2) == 4
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "ceil");
            lua.lua_pushnumber(Ls, 3.2);
            try lua.lua_call(Ls, 1, 1);
            const cl = lua.lua_tointeger(Ls, -1) orelse return error.NoCeil;
            try std.testing.expectEqual(@as(i64, 4), cl);
            lua.lua_pop(Ls, 2);

            // math.sqrt(9) == 3
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "sqrt");
            lua.lua_pushnumber(Ls, 9.0);
            try lua.lua_call(Ls, 1, 1);
            const sq = lua.lua_tonumber(Ls, -1) orelse return error.NoSqrt;
            try std.testing.expectEqual(@as(f64, 3.0), sq);
            lua.lua_pop(Ls, 2);

            return 0;
        }
    }.f;
    lua.lua_pushcfunction(&L, testfn);
    const status = lua.lua_pcallk(&L, 0, 0, 0, 0, null);
    try std.testing.expectEqual(lua.LUA_OK, status);
}

test "mathlib: min, max, type, ult, tointeger" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const testfn = struct {
        fn f(Ls: *lua.lua_State) anyerror!i32 {
            // math.max(3, 7, 5) == 7
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "max");
            lua.lua_pushinteger(Ls, 3);
            lua.lua_pushinteger(Ls, 7);
            lua.lua_pushinteger(Ls, 5);
            try lua.lua_call(Ls, 3, 1);
            const mx = lua.lua_tointeger(Ls, -1) orelse return error.NoMax;
            try std.testing.expectEqual(@as(i64, 7), mx);
            lua.lua_pop(Ls, 2);

            // math.min(3, 7, 5) == 3
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "min");
            lua.lua_pushinteger(Ls, 3);
            lua.lua_pushinteger(Ls, 7);
            lua.lua_pushinteger(Ls, 5);
            try lua.lua_call(Ls, 3, 1);
            const mn = lua.lua_tointeger(Ls, -1) orelse return error.NoMin;
            try std.testing.expectEqual(@as(i64, 3), mn);
            lua.lua_pop(Ls, 2);

            // math.type(3) == "integer"
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "type");
            lua.lua_pushinteger(Ls, 42);
            try lua.lua_call(Ls, 1, 1);
            const ti = lua.lua_tostring(Ls, -1) orelse return error.NoType;
            try std.testing.expectEqualStrings("integer", ti);
            lua.lua_pop(Ls, 2);

            // math.type(3.5) == "float"
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "type");
            lua.lua_pushnumber(Ls, 3.5);
            try lua.lua_call(Ls, 1, 1);
            const tf = lua.lua_tostring(Ls, -1) orelse return error.NoType;
            try std.testing.expectEqualStrings("float", tf);
            lua.lua_pop(Ls, 2);

            // math.ult(3, 7) == true
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "ult");
            lua.lua_pushinteger(Ls, 3);
            lua.lua_pushinteger(Ls, 7);
            try lua.lua_call(Ls, 2, 1);
            const ult1 = lua.lua_toboolean(Ls, -1);
            try std.testing.expectEqual(@as(i32, 1), ult1);
            lua.lua_pop(Ls, 2);

            // math.ult(7, 3) == false
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "ult");
            lua.lua_pushinteger(Ls, 7);
            lua.lua_pushinteger(Ls, 3);
            try lua.lua_call(Ls, 2, 1);
            const ult2 = lua.lua_toboolean(Ls, -1);
            try std.testing.expectEqual(@as(i32, 0), ult2);
            lua.lua_pop(Ls, 2);

            // math.tointeger(3.0) == 3
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "tointeger");
            lua.lua_pushnumber(Ls, 3.0);
            try lua.lua_call(Ls, 1, 1);
            const ti2 = lua.lua_tointeger(Ls, -1) orelse return error.NoToInt;
            try std.testing.expectEqual(@as(i64, 3), ti2);
            lua.lua_pop(Ls, 2);

            // math.tointeger(3.5) == nil (not integral)
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "tointeger");
            lua.lua_pushnumber(Ls, 3.5);
            try lua.lua_call(Ls, 1, 1);
            try std.testing.expectEqual(lua.lua_type(Ls, -1), lua.LUA_TNIL);
            lua.lua_pop(Ls, 2);

            return 0;
        }
    }.f;
    lua.lua_pushcfunction(&L, testfn);
    const status = lua.lua_pcallk(&L, 0, 0, 0, 0, null);
    try std.testing.expectEqual(lua.LUA_OK, status);
}

test "mathlib: random and randomseed" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const testfn = struct {
        fn f(Ls: *lua.lua_State) anyerror!i32 {
            // math.random() returns a float in [0, 1)
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "random");
            try lua.lua_call(Ls, 0, 1);
            const r1 = lua.lua_tonumber(Ls, -1) orelse return error.NoRandom;
            try std.testing.expect(r1 >= 0.0 and r1 < 1.0);
            lua.lua_pop(Ls, 2);

            // math.random(n) returns an integer in [1, n]
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "random");
            lua.lua_pushinteger(Ls, 100);
            try lua.lua_call(Ls, 1, 1);
            const r2 = lua.lua_tointeger(Ls, -1) orelse return error.NoRandomInt;
            try std.testing.expect(r2 >= 1 and r2 <= 100);
            lua.lua_pop(Ls, 2);

            // math.random(m, n) returns an integer in [m, n]
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "random");
            lua.lua_pushinteger(Ls, 50);
            lua.lua_pushinteger(Ls, 60);
            try lua.lua_call(Ls, 2, 1);
            const r3 = lua.lua_tointeger(Ls, -1) orelse return error.NoRandomRange;
            try std.testing.expect(r3 >= 50 and r3 <= 60);
            lua.lua_pop(Ls, 2);

            // math.randomseed re-seeds
            _ = lua.lua_getglobal(Ls, "math");
            _ = try lua.lua_getfield(Ls, -1, "randomseed");
            lua.lua_pushinteger(Ls, 42);
            try lua.lua_call(Ls, 1, lua.LUA_MULTRET);
            const nret = lua.lua_gettop(Ls);
            try std.testing.expectEqual(@as(i32, 3), nret);
            lua.lua_pop(Ls, nret);

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

test "bit32: bitwise library" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const testfn = struct {
        fn check(Ls: *lua.lua_State, name: []const u8, args: []const i64, exp: i64) !void {
            _ = lua.lua_getglobal(Ls, "bit32");
            _ = try lua.lua_getfield(Ls, -1, name);
            for (args) |a| lua.lua_pushinteger(Ls, a);
            try lua.lua_call(Ls, @as(i32, @intCast(args.len)), 1);
            const got = lua.lua_tointeger(Ls, -1) orelse return error.NoResult;
            if (got != exp) return error.UnexpectedResult;
            lua.lua_pop(Ls, 2);
        }
        fn checkb(Ls: *lua.lua_State, name: []const u8, args: []const i64, exp: i32) !void {
            _ = lua.lua_getglobal(Ls, "bit32");
            _ = try lua.lua_getfield(Ls, -1, name);
            for (args) |a| lua.lua_pushinteger(Ls, a);
            try lua.lua_call(Ls, @as(i32, @intCast(args.len)), 1);
            const got = lua.lua_toboolean(Ls, -1);
            if (got != exp) return error.UnexpectedResult;
            lua.lua_pop(Ls, 2);
        }
        fn f(Ls: *lua.lua_State) anyerror!i32 {
            // band / bor / bxor / bnot
            try check(Ls, "band", &[_]i64{ 15, 7 }, 7);
            try check(Ls, "bor", &[_]i64{ 1, 2 }, 3);
            try check(Ls, "bxor", &[_]i64{ 15, 5 }, 10);
            try check(Ls, "bnot", &[_]i64{0}, 0xFFFFFFFF);

            // btest returns a boolean
            try checkb(Ls, "btest", &[_]i64{ 0xF0, 0x10 }, 1);
            try checkb(Ls, "btest", &[_]i64{ 0xF0, 0x01 }, 0);

            // shifts (all values masked to 32 bits)
            try check(Ls, "lshift", &[_]i64{ 1, 4 }, 16);
            try check(Ls, "rshift", &[_]i64{ 16, 4 }, 1);
            // arshift is arithmetic only when bit 31 is set
            try check(Ls, "arshift", &[_]i64{ -1, 1 }, 0xFFFFFFFF);
            try check(Ls, "arshift", &[_]i64{ 0x80000000, 1 }, 0xC0000000);
            try check(Ls, "arshift", &[_]i64{ 0x12345678, 8 }, 0x00123456);
            // |disp| >= 32 yields 0
            try check(Ls, "lshift", &[_]i64{ 1, 32 }, 0);
            try check(Ls, "rshift", &[_]i64{ 0xFFFFFFFF, 32 }, 0);
            // rotations use disp % 32
            try check(Ls, "lrotate", &[_]i64{ 1, 1 }, 2);
            try check(Ls, "rrotate", &[_]i64{ 1, 1 }, 0x80000000);
            try check(Ls, "lrotate", &[_]i64{ 1, 33 }, 2);

            // extract / replace
            try check(Ls, "extract", &[_]i64{ 0x12345678, 8, 8 }, 0x56);
            try check(Ls, "replace", &[_]i64{ 0x12345678, 0xFF, 16, 8 }, 0x12FF5678);

            return 0;
        }
    }.f;
    lua.lua_pushcfunction(&L, testfn);
    const status = lua.lua_pcallk(&L, 0, 0, 0, 0, null);
    try std.testing.expectEqual(lua.LUA_OK, status);
}

test "string library: comprehensive verification" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const testfn = struct {
        fn check_format(Ls: *lua.lua_State, fmt: []const u8, val_push_fn: anytype, expected: []const u8) !void {
            _ = lua.lua_getglobal(Ls, "string");
            _ = try lua.lua_getfield(Ls, -1, "format");
            _ = lua.lua_pushstring(Ls, fmt);
            val_push_fn(Ls);
            try lua.lua_call(Ls, 2, 1);
            const got = lua.lua_tostring(Ls, -1) orelse return error.NoResult;
            try std.testing.expectEqualStrings(expected, got);
            lua.lua_pop(Ls, 2); // pop result and string table
        }
        
        fn f(Ls: *lua.lua_State) anyerror!i32 {
            // Integer formatting
            try check_format(Ls, "%d", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 42); } }.g, "42");
            try check_format(Ls, "%5d", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 42); } }.g, "   42");
            try check_format(Ls, "%-5d", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 42); } }.g, "42   ");
            try check_format(Ls, "%05d", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 42); } }.g, "00042");
            try check_format(Ls, "%+d", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 42); } }.g, "+42");
            try check_format(Ls, "% d", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 42); } }.g, " 42");
            try check_format(Ls, "%+05d", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 42); } }.g, "+0042");
            try check_format(Ls, "%.5d", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 42); } }.g, "00042");
            
            // Hex/Octal/Unsigned
            try check_format(Ls, "%x", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 255); } }.g, "ff");
            try check_format(Ls, "%X", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 255); } }.g, "FF");
            try check_format(Ls, "%o", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 8); } }.g, "10");
            try check_format(Ls, "%u", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, -1); } }.g, "18446744073709551615");
            try check_format(Ls, "%#x", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 255); } }.g, "0xff");
            try check_format(Ls, "%#o", struct { fn g(l: *lua.lua_State) void { lua.lua_pushinteger(l, 8); } }.g, "010");

            // Float formatting
            try check_format(Ls, "%f", struct { fn g(l: *lua.lua_State) void { lua.lua_pushnumber(l, 3.14); } }.g, "3.140000");
            try check_format(Ls, "%.2f", struct { fn g(l: *lua.lua_State) void { lua.lua_pushnumber(l, 3.14159); } }.g, "3.14");
            try check_format(Ls, "%e", struct { fn g(l: *lua.lua_State) void { lua.lua_pushnumber(l, 1000); } }.g, "1.000000e+03");
            try check_format(Ls, "%.1e", struct { fn g(l: *lua.lua_State) void { lua.lua_pushnumber(l, 1000); } }.g, "1.0e+03");
            try check_format(Ls, "%g", struct { fn g(l: *lua.lua_State) void { lua.lua_pushnumber(l, 123.456); } }.g, "123.456");
            try check_format(Ls, "%a", struct { fn g(l: *lua.lua_State) void { lua.lua_pushnumber(l, 1.5); } }.g, "0x1.8p+0");

            // String formatting
            try check_format(Ls, "%s", struct { fn g(l: *lua.lua_State) void { _ = lua.lua_pushstring(l, "hello"); } }.g, "hello");
            try check_format(Ls, "%10s", struct { fn g(l: *lua.lua_State) void { _ = lua.lua_pushstring(l, "hello"); } }.g, "     hello");
            try check_format(Ls, "%-10s", struct { fn g(l: *lua.lua_State) void { _ = lua.lua_pushstring(l, "hello"); } }.g, "hello     ");
            try check_format(Ls, "%.3s", struct { fn g(l: *lua.lua_State) void { _ = lua.lua_pushstring(l, "hello"); } }.g, "hel");

            // Quoted and pointers
            try check_format(Ls, "%q", struct { fn g(l: *lua.lua_State) void { _ = lua.lua_pushstring(l, "a\nb\"c"); } }.g, "\"a\\\nb\\\"c\"");
            try check_format(Ls, "%p", struct { fn g(l: *lua.lua_State) void { lua.lua_pushnil(l); } }.g, "(null)");

            // Pattern Matching and Gsub
            {
                // find
                _ = lua.lua_getglobal(Ls, "string");
                _ = try lua.lua_getfield(Ls, -1, "find");
                _ = lua.lua_pushstring(Ls, "hello world");
                _ = lua.lua_pushstring(Ls, "l+o");
                try lua.lua_call(Ls, 2, 2);
                const start = lua.lua_tointeger(Ls, -2) orelse 0;
                const end = lua.lua_tointeger(Ls, -1) orelse 0;
                try std.testing.expectEqual(@as(i64, 3), start);
                try std.testing.expectEqual(@as(i64, 5), end);
                lua.lua_pop(Ls, 3); // result-1, result-2, string table
            }
            {
                // gsub
                _ = lua.lua_getglobal(Ls, "string");
                _ = try lua.lua_getfield(Ls, -1, "gsub");
                _ = lua.lua_pushstring(Ls, "banana");
                _ = lua.lua_pushstring(Ls, "a");
                _ = lua.lua_pushstring(Ls, "o");
                try lua.lua_call(Ls, 3, 2);
                const got = lua.lua_tostring(Ls, -2) orelse "";
                const count = lua.lua_tointeger(Ls, -1) orelse 0;
                try std.testing.expectEqualStrings("bonono", got);
                try std.testing.expectEqual(@as(i64, 3), count);
                lua.lua_pop(Ls, 3); // results, count, string table
            }
            
            return 0;
        }
    }.f;
    lua.lua_pushcfunction(&L, testfn);
    const status = lua.lua_pcallk(&L, 0, 0, 0, 0, null);
    if (status != lua.LUA_OK) {
        const err_msg = lua.lua_tostring(&L, -1) orelse "no error message";
        std.debug.print("Lua error bytes:", .{});
        for (err_msg) |byte| {
            std.debug.print(" {x}", .{byte});
        }
        std.debug.print("\n", .{});
    }
    try std.testing.expectEqual(lua.LUA_OK, status);
}
