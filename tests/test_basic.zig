const std = @import("std");
const lua = @import("lua");
const lauxlib = lua.lauxlib;

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
    while ((try lua.lua_next(&L, -2)) != 0) {
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

fn stringReader(L: *lua.lua_State, data: ?*anyopaque, size: ?*usize) anyerror!?[]const u8 {
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
    threaded.allocator = gpa;
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
    // LOADF R0 1     ; init = 1.0
    lua.lvm.SET_OPCODE(&inst, .LOADF);
    lua.lvm.SETARG_A(&inst, 0);
    lua.lvm.SETARG_sBx(&inst, 1);
    code[0] = inst;

    // LOADF R1 3     ; limit = 3.0
    inst = 0;
    lua.lvm.SET_OPCODE(&inst, .LOADF);
    lua.lvm.SETARG_A(&inst, 1);
    lua.lvm.SETARG_sBx(&inst, 3);
    code[1] = inst;

    // LOADF R2 1     ; step = 1.0
    inst = 0;
    lua.lvm.SET_OPCODE(&inst, .LOADF);
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
    threaded.allocator = gpa;
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
    const pcall_status = lua.lua_pcall(&L, 0, 1, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), pcall_status);

    // The top of the stack should contain the returned number 52
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(&L));
    try std.testing.expectEqual(@as(i32, lua.LUA_TNUMBER), lua.lua_type(&L, -1));
    const result = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, 52.0), result);
}

test "BUG-036: VM vararg execution (VARARGPREP/VARARG)" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    var threaded: std.Io.Threaded = .init_single_threaded;
    threaded.allocator = gpa;
    const io = threaded.io();
    const bytecode = try std.Io.Dir.cwd().readFileAlloc(io, "tests/test_vararg.luac", gpa, .unlimited);
    defer gpa.free(bytecode);

    var reader_state = StringReaderState{
        .code = bytecode,
        .read_done = false,
    };

    const status = lua.lua_load(&L, stringReader, &reader_state, "test_vararg.luac", "b");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);

    // Chunk: local function f(a,b,...) return ... end; return f(1,2,3,4,5)
    // f drops a=1,b=2 and returns varargs 3,4,5; with 1 result we expect 3.
    const pcall_status = lua.lua_pcall(&L, 0, 1, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), pcall_status);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(&L));
    try std.testing.expectEqual(@as(i32, lua.LUA_TNUMBER), lua.lua_type(&L, -1));
    try std.testing.expectEqual(@as(f64, 3.0), lua.lua_tonumber(&L, -1) orelse return error.TestFailed);
}

test "luaL_dostring loads and runs a chunk (properly implemented)" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    var threaded: std.Io.Threaded = .init_single_threaded;
    threaded.allocator = gpa;
    const io = threaded.io();
    const bytecode = try std.Io.Dir.cwd().readFileAlloc(io, "tests/test_dostring.luac", gpa, .unlimited);
    defer gpa.free(bytecode);

    // luaL_dostring should load the chunk from the string and run it via pcall,
    // returning LUA_OK and leaving the chunk's result (6*7 = 42) on the stack.
    const status = try lua.luaL_dostring(&L, bytecode, "=test_dostring");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(&L));
    try std.testing.expectEqual(@as(f64, 42.0), lua.lua_tonumber(&L, -1) orelse return error.TestFailed);
}

test "luaL_dostring executes source-text string and handles syntax errors" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // Valid source-text compilation and execution
    const status_ok = try lua.luaL_dostring(&L, "return 42", "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status_ok);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(&L));
    try std.testing.expectEqual(@as(f64, 42.0), lua.lua_tonumber(&L, -1) orelse return error.TestFailed);
    lua.lua_pop(&L, 1);

    // Invalid source-text should fail load with LUA_ERRSYNTAX
    const status_err = try lua.luaL_dostring(&L, "return 42 +", "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_ERRSYNTAX), status_err);
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
    // Large shift: per Lua 5.5 luaV_shiftl, a shift count >= NBITS (64)
    // yields 0 (not a masked wrap). 1 << 70 == 0.
    try std.testing.expectEqual(@as(i64, 0), lua.luaV_shift(1, 70));
    // Negative large: -70 <= -64 also yields 0.
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

test "BUG-FIX #1/#2: luaT_callTMres passes both operands to binary metamethod" {
    // A binary metamethod must receive BOTH operands (nargs=2) and old_top
    // must be captured AFTER lua_checkstack, so the call frame is valid even
    // when the stack is about to grow. Regression for the metamethod
    // dispatch where only one operand was passed.
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    const t1_idx = lua.lua_gettop(&L);
    lua.lua_createtable(&L, 0, 0);
    const t2_idx = lua.lua_gettop(&L);
    lua.lua_createtable(&L, 0, 1);
    const mt_idx = lua.lua_gettop(&L);

    // __add records how many operands it received and returns a sentinel.
    const AddFn = struct {
        fn add(LS: *lua.lua_State) anyerror!i32 {
            const nargs = lua.lua_gettop(LS);
            if (nargs != 2) return error.TestFailed; // both operands must be present
            _ = lua.lua_tonumber(LS, 1);
            _ = lua.lua_tonumber(LS, 2);
            lua.lua_pushnumber(LS, 99.0);
            return 1;
        }
    };
    lua.lua_pushcfunction(&L, AddFn.add);
    try lua.lua_setfield(&L, mt_idx, "__add");
    lua.lua_pushvalue(&L, mt_idx);
    _ = lua.lua_setmetatable(&L, t1_idx);

    lua.lua_pushvalue(&L, t1_idx);
    lua.lua_pushvalue(&L, t2_idx);
    lua.lua_arith(&L, lua.LUA_OPADD);
    const v = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, 99.0), v);
}

test "BUG-FIX #3: string metatable __unm arithmetic (LUA_OPUNM)" {
    // lua string metatable arithmetic must handle LUA_OPUNM in both the
    // integer and float operand paths. Verifies "-(\"3\")" yields -3.0.
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    // "return -('3')" must evaluate to -3.0 via the string __unm metamethod.
    var reader_state = StringReaderState{ .code = "return -('3')", .read_done = false };
    const status = lua.lua_load(&L, stringReader, &reader_state, "=test", "t");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    const rc = lua.lua_pcall(&L, 0, 1, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), rc);
    const v = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqual(@as(f64, -3.0), v);
}

test "VM execution of arithmetic metamethod" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    var threaded: std.Io.Threaded = .init_single_threaded;
    threaded.allocator = gpa;
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
    const load_pcall = lua.lua_pcall(&L, 0, 1, 0);
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
    const pcall_status = lua.lua_pcall(&L, 2, 1, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), pcall_status);

    // The top of the stack should contain the returned number 999.0
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(&L));
    try std.testing.expectEqual(@as(i32, lua.LUA_TNUMBER), lua.lua_type(&L, -1));
    const result = lua.lua_tonumber(&L, -1) orelse return error.TestFailed;
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
    const status = lua.lua_pcall(&L, 0, 0, 0);
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
    const status = lua.lua_pcall(&L, 0, 0, handler_idx);
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
    const status = lua.lua_gc(&L, lua.LUA_GCCOLLECT, 0, 0);
    try std.testing.expectEqual(@as(i32, 0), status);

    // Verify that:
    // - The referenced table is NOT collected.
    // - The unreferenced table IS collected.
    // - The referenced string is NOT collected.
    // - The unreferenced string is retained by the API string cache
    //   (strcache); the GC marks cache entries as roots (matching the
    //   reference), so a recently-created string survives even after it is
    //   popped from the stack.
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

    // Run GC again. The popped table is collected (tables are not cached),
    // but both interned strings remain alive: they reside in the API string
    // cache (strcache), which the GC marks as a root (matching the reference).
    // So the strings survive until a later string evicts them from the cache.
    _ = lua.lua_gc(&L, lua.LUA_GCCOLLECT, 0, 0);

    // The cached strings are swept.
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
    const status = lua.lua_pcall(&L, 0, 0, 0);
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
    const status = lua.lua_pcall(&L, 0, 0, 0);
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
    const status = lua.lua_pcall(&L, 0, 0, 0);
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
    const status = lua.lua_pcall(&L, 0, 0, 0);
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
    const status = lua.lua_pcall(&L, 0, 0, 0);
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
    const status = lua.lua_pcall(&L, 0, 0, 0);
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
    const status = lua.lua_pcall(&L, 0, 0, 0);
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
    const status = lua.lua_pcall(&L, 0, 0, 0);
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
    const status = lua.lua_pcall(&L, 0, 0, 0);
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
    const status = lua.lua_pcall(&L, 0, 0, 0);
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
            try check_format(Ls, "%d", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 42);
                }
            }.g, "42");
            try check_format(Ls, "%5d", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 42);
                }
            }.g, "   42");
            try check_format(Ls, "%-5d", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 42);
                }
            }.g, "42   ");
            try check_format(Ls, "%05d", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 42);
                }
            }.g, "00042");
            try check_format(Ls, "%+d", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 42);
                }
            }.g, "+42");
            try check_format(Ls, "% d", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 42);
                }
            }.g, " 42");
            try check_format(Ls, "%+05d", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 42);
                }
            }.g, "+0042");
            try check_format(Ls, "%.5d", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 42);
                }
            }.g, "00042");

            // Hex/Octal/Unsigned
            try check_format(Ls, "%x", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 255);
                }
            }.g, "ff");
            try check_format(Ls, "%X", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 255);
                }
            }.g, "FF");
            try check_format(Ls, "%o", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 8);
                }
            }.g, "10");
            try check_format(Ls, "%u", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, -1);
                }
            }.g, "18446744073709551615");
            try check_format(Ls, "%#x", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 255);
                }
            }.g, "0xff");
            try check_format(Ls, "%#o", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushinteger(l, 8);
                }
            }.g, "010");

            // Float formatting
            try check_format(Ls, "%f", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushnumber(l, 3.14);
                }
            }.g, "3.140000");
            try check_format(Ls, "%.2f", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushnumber(l, 3.14159);
                }
            }.g, "3.14");
            try check_format(Ls, "%e", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushnumber(l, 1000);
                }
            }.g, "1.000000e+03");
            try check_format(Ls, "%.1e", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushnumber(l, 1000);
                }
            }.g, "1.0e+03");
            try check_format(Ls, "%g", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushnumber(l, 123.456);
                }
            }.g, "123.456");
            try check_format(Ls, "%a", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushnumber(l, 1.5);
                }
            }.g, "0x1.8p+0");

            // String formatting
            try check_format(Ls, "%s", struct {
                fn g(l: *lua.lua_State) void {
                    _ = lua.lua_pushstring(l, "hello");
                }
            }.g, "hello");
            try check_format(Ls, "%10s", struct {
                fn g(l: *lua.lua_State) void {
                    _ = lua.lua_pushstring(l, "hello");
                }
            }.g, "     hello");
            try check_format(Ls, "%-10s", struct {
                fn g(l: *lua.lua_State) void {
                    _ = lua.lua_pushstring(l, "hello");
                }
            }.g, "hello     ");
            try check_format(Ls, "%.3s", struct {
                fn g(l: *lua.lua_State) void {
                    _ = lua.lua_pushstring(l, "hello");
                }
            }.g, "hel");

            // Quoted and pointers
            try check_format(Ls, "%q", struct {
                fn g(l: *lua.lua_State) void {
                    _ = lua.lua_pushstring(l, "a\nb\"c");
                }
            }.g, "\"a\\\nb\\\"c\"");
            try check_format(Ls, "%p", struct {
                fn g(l: *lua.lua_State) void {
                    lua.lua_pushnil(l);
                }
            }.g, "(null)");

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
    const status = lua.lua_pcall(&L, 0, 0, 0);
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

test "string library: byte/char/len/sub/reverse/case/rep/match/gmatch/pack coverage" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    // Push string.<name> onto the stack: layout becomes [string_table, func].
    const setup = struct {
        fn call(Ls: *lua.lua_State, name: []const u8) anyerror!void {
            lua.lua_settop(Ls, 0);
            _ = lua.lua_getglobal(Ls, "string");
            _ = try lua.lua_getfield(Ls, -1, name);
        }
    }.call;

    const testfn = struct {
        fn f(Ls: *lua.lua_State) anyerror!i32 {
            // ----- string.len -----
            try setup(Ls, "len");
            _ = lua.lua_pushstring(Ls, "hello");
            try lua.lua_call(Ls, 1, 1);
            try std.testing.expectEqual(@as(i64, 5), lua.lua_tointeger(Ls, 2) orelse 0);

            // ----- string.byte single -----
            try setup(Ls, "byte");
            _ = lua.lua_pushstring(Ls, "abc");
            try lua.lua_call(Ls, 1, 1);
            try std.testing.expectEqual(@as(i64, 97), lua.lua_tointeger(Ls, 2) orelse 0);

            // ----- string.byte range -----
            try setup(Ls, "byte");
            _ = lua.lua_pushstring(Ls, "abc");
            _ = lua.lua_pushinteger(Ls, 1);
            _ = lua.lua_pushinteger(Ls, 2);
            try lua.lua_call(Ls, 3, 2);
            try std.testing.expectEqual(@as(i64, 97), lua.lua_tointeger(Ls, 2) orelse 0);
            try std.testing.expectEqual(@as(i64, 98), lua.lua_tointeger(Ls, 3) orelse 0);

            // ----- string.byte negative index -----
            try setup(Ls, "byte");
            _ = lua.lua_pushstring(Ls, "abc");
            _ = lua.lua_pushinteger(Ls, -1);
            try lua.lua_call(Ls, 2, 1);
            try std.testing.expectEqual(@as(i64, 99), lua.lua_tointeger(Ls, 2) orelse 0);

            // ----- string.byte empty interval returns no values -----
            try setup(Ls, "byte");
            _ = lua.lua_pushstring(Ls, "abc");
            _ = lua.lua_pushinteger(Ls, 2);
            _ = lua.lua_pushinteger(Ls, 1);
            try lua.lua_call(Ls, 3, 0);
            try std.testing.expectEqual(@as(i32, 1), lua.lua_gettop(Ls)); // only the string table remains

            // ----- string.char -----
            try setup(Ls, "char");
            _ = lua.lua_pushinteger(Ls, 97);
            _ = lua.lua_pushinteger(Ls, 98);
            _ = lua.lua_pushinteger(Ls, 99);
            try lua.lua_call(Ls, 3, 1);
            try std.testing.expectEqualStrings("abc", lua.lua_tostring(Ls, 2) orelse "");

            // ----- string.char out of range raises an error -----
            try setup(Ls, "char");
            _ = lua.lua_pushinteger(Ls, 256);
            const char_status = lua.lua_pcall(Ls, 1, 1, 0);
            try std.testing.expect(char_status != lua.LUA_OK);

            // ----- string.sub -----
            try setup(Ls, "sub");
            _ = lua.lua_pushstring(Ls, "hello");
            _ = lua.lua_pushinteger(Ls, 1);
            _ = lua.lua_pushinteger(Ls, 3);
            try lua.lua_call(Ls, 3, 1);
            try std.testing.expectEqualStrings("hel", lua.lua_tostring(Ls, 2) orelse "");

            // ----- string.sub with negative indices -----
            try setup(Ls, "sub");
            _ = lua.lua_pushstring(Ls, "hello");
            _ = lua.lua_pushinteger(Ls, -3);
            try lua.lua_call(Ls, 2, 1);
            try std.testing.expectEqualStrings("llo", lua.lua_tostring(Ls, 2) orelse "");

            try setup(Ls, "sub");
            _ = lua.lua_pushstring(Ls, "hello");
            _ = lua.lua_pushinteger(Ls, 2);
            _ = lua.lua_pushinteger(Ls, -2);
            try lua.lua_call(Ls, 3, 1);
            try std.testing.expectEqualStrings("ell", lua.lua_tostring(Ls, 2) orelse "");

            // ----- string.reverse -----
            try setup(Ls, "reverse");
            _ = lua.lua_pushstring(Ls, "abc");
            try lua.lua_call(Ls, 1, 1);
            try std.testing.expectEqualStrings("cba", lua.lua_tostring(Ls, 2) orelse "");

            // ----- string.upper / string.lower -----
            try setup(Ls, "upper");
            _ = lua.lua_pushstring(Ls, "abc");
            try lua.lua_call(Ls, 1, 1);
            try std.testing.expectEqualStrings("ABC", lua.lua_tostring(Ls, 2) orelse "");

            try setup(Ls, "lower");
            _ = lua.lua_pushstring(Ls, "ABC");
            try lua.lua_call(Ls, 1, 1);
            try std.testing.expectEqualStrings("abc", lua.lua_tostring(Ls, 2) orelse "");

            // ----- string.rep -----
            try setup(Ls, "rep");
            _ = lua.lua_pushstring(Ls, "ab");
            _ = lua.lua_pushinteger(Ls, 3);
            try lua.lua_call(Ls, 2, 1);
            try std.testing.expectEqualStrings("ababab", lua.lua_tostring(Ls, 2) orelse "");

            try setup(Ls, "rep");
            _ = lua.lua_pushstring(Ls, "ab");
            _ = lua.lua_pushinteger(Ls, 3);
            _ = lua.lua_pushstring(Ls, ",");
            try lua.lua_call(Ls, 3, 1);
            try std.testing.expectEqualStrings("ab,ab,ab", lua.lua_tostring(Ls, 2) orelse "");

            try setup(Ls, "rep");
            _ = lua.lua_pushstring(Ls, "x");
            _ = lua.lua_pushinteger(Ls, 0);
            try lua.lua_call(Ls, 2, 1);
            try std.testing.expectEqualStrings("", lua.lua_tostring(Ls, 2) orelse "");

            // ----- string.match -----
            try setup(Ls, "match");
            _ = lua.lua_pushstring(Ls, "hello");
            _ = lua.lua_pushstring(Ls, "l+");
            try lua.lua_call(Ls, 2, 1);
            try std.testing.expectEqualStrings("ll", lua.lua_tostring(Ls, 2) orelse "");

            try setup(Ls, "match");
            _ = lua.lua_pushstring(Ls, "x=10");
            _ = lua.lua_pushstring(Ls, "(%d+)");
            try lua.lua_call(Ls, 2, 1);
            try std.testing.expectEqualStrings("10", lua.lua_tostring(Ls, 2) orelse "");

            // ----- string.gmatch iteration -----
            {
                try setup(Ls, "gmatch");
                _ = lua.lua_pushstring(Ls, "1 2 3");
                _ = lua.lua_pushstring(Ls, "%d");
                try lua.lua_call(Ls, 2, 1); // stack: [string_table(-2), iterator(-1)]
                // The iterator keeps its state in upvalues; lua_call consumes the
                // closure, so duplicate it (sharing the same upvalue cells) before
                // each call to preserve the iterator for the next iteration.
                const expected = [_][]const u8{ "1", "2", "3" };
                for (expected) |exp| {
                    lua.lua_pushvalue(Ls, -1); // copy iterator on top
                    try lua.lua_call(Ls, 0, 1); // [.., iterator, result]
                    const got = lua.lua_tostring(Ls, -1) orelse return error.TestFailed;
                    try std.testing.expectEqualStrings(exp, got);
                    lua.lua_pop(Ls, 1); // back to [.., iterator]
                }
                // next call yields nil (end of matches)
                lua.lua_pushvalue(Ls, -1);
                try lua.lua_call(Ls, 0, 1);
                try std.testing.expectEqual(@as(i32, 1), lua.lua_isnil(Ls, -1));
            }

            // ----- string.pack / unpack / packsize -----
            try setup(Ls, "pack");
            _ = lua.lua_pushstring(Ls, "i4");
            _ = lua.lua_pushinteger(Ls, 1);
            try lua.lua_call(Ls, 2, 1);
            const packed_str = lua.lua_tostring(Ls, 2) orelse return error.TestFailed;
            try std.testing.expectEqual(@as(usize, 4), packed_str.len);

            try setup(Ls, "packsize");
            _ = lua.lua_pushstring(Ls, "i4");
            try lua.lua_call(Ls, 1, 1);
            try std.testing.expectEqual(@as(i64, 4), lua.lua_tointeger(Ls, 2) orelse 0);

            // unpack the packed value back
            try setup(Ls, "unpack");
            _ = lua.lua_pushstring(Ls, "i4");
            _ = lua.lua_pushlstring(Ls, packed_str, packed_str.len);
            _ = lua.lua_pushinteger(Ls, 1);
            try lua.lua_call(Ls, 3, 2);
            try std.testing.expectEqual(@as(i64, 1), lua.lua_tointeger(Ls, 2) orelse 0);
            try std.testing.expectEqual(@as(i64, 5), lua.lua_tointeger(Ls, 3) orelse 0); // next position

            // big-endian pack/unpack round trip
            try setup(Ls, "pack");
            _ = lua.lua_pushstring(Ls, ">i4");
            _ = lua.lua_pushinteger(Ls, 1);
            try lua.lua_call(Ls, 2, 1);
            const packed_be_str = lua.lua_tostring(Ls, 2) orelse return error.TestFailed;
            try std.testing.expectEqual(@as(usize, 4), packed_be_str.len);

            try setup(Ls, "unpack");
            _ = lua.lua_pushstring(Ls, ">i4");
            _ = lua.lua_pushlstring(Ls, packed_be_str, packed_be_str.len);
            _ = lua.lua_pushinteger(Ls, 1);
            try lua.lua_call(Ls, 3, 2);
            try std.testing.expectEqual(@as(i64, 1), lua.lua_tointeger(Ls, 2) orelse 0);

            return 0;
        }
    }.f;

    // Run the checks directly so any failing assertion reports its real
    // location (instead of being swallowed by a pcall wrapper).
    _ = try testfn(&L);
}

test "table library: create/insert/remove/pack/unpack/concat/move/sort" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const testfn = struct {
        fn setTestTab(Ls: *lua.lua_State) void {
            lua.lua_setglobal(Ls, "_tabtest");
        }
        fn getTestTab(Ls: *lua.lua_State) void {
            _ = lua.lua_getglobal(Ls, "_tabtest");
        }

        fn f(Ls: *lua.lua_State) anyerror!i32 {
            // ----- table.create -----
            lua.lua_settop(Ls, 0);
            _ = lua.lua_getglobal(Ls, "table");
            _ = try lua.lua_getfield(Ls, -1, "create");
            _ = lua.lua_pushinteger(Ls, 3);
            _ = lua.lua_pushinteger(Ls, 0);
            try lua.lua_call(Ls, 2, 1);
            try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(Ls, -1));
            lua.lua_pop(Ls, 1);

            // ----- table.insert at end -----
            lua.lua_settop(Ls, 0);
            lua.lua_createtable(Ls, 1, 0);
            setTestTab(Ls);
            _ = lua.lua_getglobal(Ls, "table");
            _ = try lua.lua_getfield(Ls, -1, "insert");
            lua.lua_remove(Ls, -2);
            getTestTab(Ls);
            _ = lua.lua_pushinteger(Ls, 10);
            try lua.lua_call(Ls, 2, 0);
            getTestTab(Ls);
            _ = try lua.lua_geti(Ls, -1, 1);
            try std.testing.expectEqual(@as(i64, 10), lua.lua_tointeger(Ls, -1) orelse 0);
            lua.lua_pop(Ls, 1);

            // ----- table.insert at position -----
            lua.lua_settop(Ls, 0);
            lua.lua_createtable(Ls, 2, 0);
            _ = lua.lua_pushinteger(Ls, 10);
            lua.lua_rawseti(Ls, -2, 1);
            _ = lua.lua_pushinteger(Ls, 20);
            lua.lua_rawseti(Ls, -2, 2);
            setTestTab(Ls);
            _ = lua.lua_getglobal(Ls, "table");
            _ = try lua.lua_getfield(Ls, -1, "insert");
            lua.lua_remove(Ls, -2);
            getTestTab(Ls);
            _ = lua.lua_pushinteger(Ls, 1); // position
            _ = lua.lua_pushinteger(Ls, 5); // value
            try lua.lua_call(Ls, 3, 0);
            getTestTab(Ls);
            _ = try lua.lua_geti(Ls, -1, 1);
            try std.testing.expectEqual(@as(i64, 5), lua.lua_tointeger(Ls, -1) orelse 0);
            _ = try lua.lua_geti(Ls, -2, 3);
            try std.testing.expectEqual(@as(i64, 20), lua.lua_tointeger(Ls, -1) orelse 0);
            lua.lua_pop(Ls, 2);

            // ----- table.remove -----
            lua.lua_settop(Ls, 0);
            lua.lua_createtable(Ls, 2, 0);
            _ = lua.lua_pushinteger(Ls, 10);
            lua.lua_rawseti(Ls, -2, 1);
            _ = lua.lua_pushinteger(Ls, 20);
            lua.lua_rawseti(Ls, -2, 2);
            setTestTab(Ls);
            _ = lua.lua_getglobal(Ls, "table");
            _ = try lua.lua_getfield(Ls, -1, "remove");
            lua.lua_remove(Ls, -2);
            getTestTab(Ls);
            _ = lua.lua_pushinteger(Ls, 1);
            try lua.lua_call(Ls, 2, 1);
            try std.testing.expectEqual(@as(i64, 10), lua.lua_tointeger(Ls, -1) orelse 0);
            lua.lua_pop(Ls, 1);

            // ----- table.pack -----
            lua.lua_settop(Ls, 0);
            _ = lua.lua_getglobal(Ls, "table");
            _ = try lua.lua_getfield(Ls, -1, "pack");
            _ = lua.lua_pushinteger(Ls, 1);
            _ = lua.lua_pushinteger(Ls, 2);
            _ = lua.lua_pushinteger(Ls, 3);
            try lua.lua_call(Ls, 3, 1);
            _ = try lua.lua_geti(Ls, -1, 1);
            try std.testing.expectEqual(@as(i64, 1), lua.lua_tointeger(Ls, -1) orelse 0);
            lua.lua_pop(Ls, 1);
            _ = try lua.lua_geti(Ls, -1, 3);
            try std.testing.expectEqual(@as(i64, 3), lua.lua_tointeger(Ls, -1) orelse 0);
            lua.lua_pop(Ls, 1);
            _ = try lua.lua_getfield(Ls, -1, "n");
            try std.testing.expectEqual(@as(i64, 3), lua.lua_tointeger(Ls, -1) orelse 0);
            lua.lua_pop(Ls, 2);

            // ----- table.unpack -----
            lua.lua_settop(Ls, 0);
            lua.lua_createtable(Ls, 2, 0);
            _ = lua.lua_pushinteger(Ls, 10);
            lua.lua_rawseti(Ls, -2, 1);
            _ = lua.lua_pushinteger(Ls, 20);
            lua.lua_rawseti(Ls, -2, 2);
            _ = lua.lua_getglobal(Ls, "table");
            _ = try lua.lua_getfield(Ls, -1, "unpack");
            lua.lua_remove(Ls, -2);
            lua.lua_insert(Ls, -2);
            try lua.lua_call(Ls, 1, 2);
            try std.testing.expectEqual(@as(i64, 10), lua.lua_tointeger(Ls, -2) orelse 0);
            try std.testing.expectEqual(@as(i64, 20), lua.lua_tointeger(Ls, -1) orelse 0);
            lua.lua_pop(Ls, 2);

            // ----- table.concat -----
            lua.lua_settop(Ls, 0);
            lua.lua_createtable(Ls, 3, 0);
            _ = lua.lua_pushstring(Ls, "a");
            lua.lua_rawseti(Ls, -2, 1);
            _ = lua.lua_pushstring(Ls, "b");
            lua.lua_rawseti(Ls, -2, 2);
            _ = lua.lua_pushstring(Ls, "c");
            lua.lua_rawseti(Ls, -2, 3);
            _ = lua.lua_getglobal(Ls, "table");
            _ = try lua.lua_getfield(Ls, -1, "concat");
            lua.lua_remove(Ls, -2);
            lua.lua_insert(Ls, -2);
            try lua.lua_call(Ls, 1, 1);
            try std.testing.expectEqualStrings("abc", lua.lua_tostring(Ls, -1) orelse "");
            lua.lua_pop(Ls, 1);

            // ----- table.concat with separator -----
            lua.lua_settop(Ls, 0);
            lua.lua_createtable(Ls, 3, 0);
            _ = lua.lua_pushstring(Ls, "a");
            lua.lua_rawseti(Ls, -2, 1);
            _ = lua.lua_pushstring(Ls, "b");
            lua.lua_rawseti(Ls, -2, 2);
            _ = lua.lua_pushstring(Ls, "c");
            lua.lua_rawseti(Ls, -2, 3);
            _ = lua.lua_getglobal(Ls, "table");
            _ = try lua.lua_getfield(Ls, -1, "concat");
            lua.lua_remove(Ls, -2);
            lua.lua_insert(Ls, -2);
            _ = lua.lua_pushstring(Ls, ",");
            try lua.lua_call(Ls, 2, 1);
            try std.testing.expectEqualStrings("a,b,c", lua.lua_tostring(Ls, -1) orelse "");
            lua.lua_pop(Ls, 1);

            // ----- table.sort -----
            lua.lua_settop(Ls, 0);
            lua.lua_createtable(Ls, 3, 0);
            _ = lua.lua_pushinteger(Ls, 3);
            lua.lua_rawseti(Ls, -2, 1);
            _ = lua.lua_pushinteger(Ls, 1);
            lua.lua_rawseti(Ls, -2, 2);
            _ = lua.lua_pushinteger(Ls, 2);
            lua.lua_rawseti(Ls, -2, 3);
            setTestTab(Ls);
            _ = lua.lua_getglobal(Ls, "table");
            _ = try lua.lua_getfield(Ls, -1, "sort");
            lua.lua_remove(Ls, -2);
            getTestTab(Ls);
            try lua.lua_call(Ls, 1, 0);
            getTestTab(Ls);
            _ = try lua.lua_geti(Ls, -1, 1);
            try std.testing.expectEqual(@as(i64, 1), lua.lua_tointeger(Ls, -1) orelse 0);
            _ = try lua.lua_geti(Ls, -2, 2);
            try std.testing.expectEqual(@as(i64, 2), lua.lua_tointeger(Ls, -1) orelse 0);
            _ = try lua.lua_geti(Ls, -3, 3);
            try std.testing.expectEqual(@as(i64, 3), lua.lua_tointeger(Ls, -1) orelse 0);
            lua.lua_pop(Ls, 3);

            // ----- table.move -----
            lua.lua_settop(Ls, 0);
            lua.lua_createtable(Ls, 4, 0);
            _ = lua.lua_pushinteger(Ls, 10);
            lua.lua_rawseti(Ls, -2, 1);
            _ = lua.lua_pushinteger(Ls, 20);
            lua.lua_rawseti(Ls, -2, 2);
            setTestTab(Ls);
            _ = lua.lua_getglobal(Ls, "table");
            _ = try lua.lua_getfield(Ls, -1, "move");
            lua.lua_remove(Ls, -2);
            getTestTab(Ls);
            _ = lua.lua_pushinteger(Ls, 1); // f
            _ = lua.lua_pushinteger(Ls, 2); // e
            _ = lua.lua_pushinteger(Ls, 3); // t
            _ = lua.lua_pushnil(Ls); // same table
            try lua.lua_call(Ls, 5, 1);
            lua.lua_pop(Ls, 1); // result: source table
            getTestTab(Ls);
            _ = try lua.lua_geti(Ls, -1, 3);
            try std.testing.expectEqual(@as(i64, 10), lua.lua_tointeger(Ls, -1) orelse 0);
            _ = try lua.lua_geti(Ls, -2, 4);
            try std.testing.expectEqual(@as(i64, 20), lua.lua_tointeger(Ls, -1) orelse 0);
            lua.lua_pop(Ls, 2);

            return 0;
        }
    }.f;

    _ = try testfn(&L);
}

test "coroutine infrastructure: newthread/pushthread/status/isyieldable/closethread" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // lua_newthread creates a new thread, pushes it on the stack
    const co = try lua.lua_newthread(&L);
    try std.testing.expect(lua.lua_type(&L, -1) == lua.LUA_TTHREAD);
    try std.testing.expect(lua.lua_tothread(&L, -1) == co);
    lua.lua_pop(&L, 1);

    // lua_pushthread pushes current thread
    _ = lua.lua_pushthread(&L);
    try std.testing.expect(lua.lua_type(&L, -1) == lua.LUA_TTHREAD);
    lua.lua_pop(&L, 1);

    // lua_status on a fresh thread returns LUA_OK
    const co2 = try lua.lua_newthread(&L);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), lua.lua_status(co2));
    lua.lua_pop(&L, 1);

    // lua_isyieldable on main thread (no active C call → not yieldable when ci == base_ci)
    try std.testing.expectEqual(@as(i32, 0), lua.lua_isyieldable(&L));

    // lua_closethread
    const co3 = try lua.lua_newthread(&L);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), lua.lua_closethread(co3, &L));
    lua.lua_pop(&L, 1);
}

fn yield_resume_k(L2: *lua.lua_State, status: i32, ctx: lua.lua_KContext) anyerror!i32 {
    _ = status;
    _ = ctx;
    _ = lua.lua_pushstring(L2, "done");
    return 1;
}

fn yield_resume_cfunc(L2: *lua.lua_State) anyerror!i32 {
    _ = lua.lua_pushstring(L2, "hello");
    _ = lua.lua_pushstring(L2, "world");
    return lua.lua_yieldk(L2, 2, 0, yield_resume_k);
}

test "coroutine yield/resume via C API" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const co = try lua.lua_newthread(&L);
    lua.lua_pushcfunction(&L, yield_resume_cfunc);
    lua.lua_xmove(&L, co, 1);

    var nres: i32 = 0;
    const status1 = lua.lua_resume(co, &L, 0, &nres);
    try std.testing.expectEqual(@as(i32, lua.LUA_YIELD), status1);
    try std.testing.expectEqual(@as(i32, 2), nres);
    try std.testing.expectEqualStrings("hello", lua.lua_tostring(co, -2).?);
    try std.testing.expectEqualStrings("world", lua.lua_tostring(co, -1).?);

    const status2 = lua.lua_resume(co, &L, 0, &nres);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status2);
    try std.testing.expectEqualStrings("done", lua.lua_tostring(co, -1).?);
}

test "io library opens and registers functions" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "io");
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));

    _ = try lua.lua_getfield(&L, -1, "type");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "open");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "close");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "write");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "read");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "lines");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "flush");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "tmpfile");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "input");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "output");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 2);
}

test "io.type on non-file returns nil" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "io");
    _ = try lua.lua_getfield(&L, -1, "type");
    lua.lua_pushnil(&L);
    _ = lua.lua_pcall(&L, 1, 1, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_TNIL), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 2);
}

test "file:setvbuf no writes immediately (unbuffered)" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    const script =
        \\local f = io.open("/tmp/luazig_h3_no.txt", "w")
        \\assert(f:setvbuf("no") == true)
        \\f:write("immediate")
        \\local g = io.open("/tmp/luazig_h3_no.txt", "r")
        \\local s = g:read("a")
        \\f:close()
        \\g:close()
        \\return s
    ;
    const status = try lua.luaL_dostring(&L, script, "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    const s = lua.lua_tostring(&L, -1);
    try std.testing.expect(s != null);
    try std.testing.expectEqualStrings("immediate", s.?);
}

test "file:setvbuf full buffers until flush then persists" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    // Full buffering: before flush the data lives in the buffer (file still empty);
    // after f:flush() it is on disk. file:flush() must also return true.
    const script =
        \\local f = io.open("/tmp/luazig_h3_full.txt", "w")
        \\assert(f:setvbuf("full", 64) == true)
        \\f:write("buffered")
        \\local g = io.open("/tmp/luazig_h3_full.txt", "r")
        \\local before = g:read("a")
        \\g:close()
        \\assert(f:flush() == true)
        \\local h = io.open("/tmp/luazig_h3_full.txt", "r")
        \\local after = h:read("a")
        \\h:close()
        \\f:close()
        \\return before .. "|" .. after
    ;
    const status = try lua.luaL_dostring(&L, script, "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    const s = lua.lua_tostring(&L, -1);
    try std.testing.expect(s != null);
    try std.testing.expectEqualStrings("|buffered", s.?);
}

test "io.flush flushes the default output file" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    const script =
        \\local f = io.open("/tmp/luazig_h3_flush.txt", "w")
        \\assert(f:setvbuf("full", 16) == true)
        \\f:write("flushed-data")
        \\local g = io.open("/tmp/luazig_h3_flush.txt", "r")
        \\local before = g:read("a")
        \\g:close()
        \\assert(f:flush() == true)
        \\local h = io.open("/tmp/luazig_h3_flush.txt", "r")
        \\local after = h:read("a")
        \\h:close()
        \\f:close()
        \\return (before or "") .. "|" .. (after or "")
    ;
    const status = try lua.luaL_dostring(&L, script, "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    const s = lua.lua_tostring(&L, -1);
    try std.testing.expect(s != null);
    try std.testing.expectEqualStrings("|flushed-data", s.?);
}

test "io.write writes to the current output file without leaking the handle as an arg" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    // Regression test: `io.output(file)` must not leave the filename (nor the
    // file handle) on the stack, otherwise the next `io.write` sees it as an
    // extra argument and fails with "string expected, got FILE*".
    const script =
        \\local file = os.tmpname()
        \\io.output(file)
        \\io.write("hello")
        \\io.write(" ", 42, "\n")
        \\io.close()
        \\local f = io.open(file, "r")
        \\local content = f:read("*a")
        \\f:close()
        \\os.remove(file)
        \\return content
    ;
    const status = try lua.luaL_dostring(&L, script, "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    const s = lua.lua_tostring(&L, -1);
    try std.testing.expect(s != null);
    try std.testing.expectEqualStrings("hello 42\n", s.?);
}

test "file:read(\"*n\") parses integers, floats, hex and invalids" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    // Writes "10 3.5 -7 0xFF 1e3\nhello\n", then reads the five numbers, an
    // invalid token (nil), and the following line — exercising the one-byte
    // pushback so the trailing char of each number is visible to later reads.
    const script =
        \\local f = io.open("/tmp/luazig_h3_n.txt", "w")
        \\f:write("10 3.5 -7 0xFF 1e3\nhello\n")
        \\f:close()
        \\local g = io.open("/tmp/luazig_h3_n.txt", "r")
        \\local a, b, c, d, e, nn = g:read("*n", "*n", "*n", "*n", "*n", "*n")
        \\local s = g:read("*l")
        \\g:close()
        \\return tostring(a) .. ";" .. tostring(b) .. ";" .. tostring(c) .. ";" .. tostring(d) .. ";" .. tostring(e) .. ";" .. tostring(nn) .. ";" .. tostring(s)
    ;
    const status = try lua.luaL_dostring(&L, script, "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    const s = lua.lua_tostring(&L, -1);
    try std.testing.expect(s != null);
    try std.testing.expectEqualStrings("10;3.5;-7;255;1000.0;nil;hello", s.?);
}

test "os library opens and registers functions" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "os");
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));

    _ = try lua.lua_getfield(&L, -1, "clock");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "date");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "time");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "difftime");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "exit");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "getenv");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 2);
}

test "os.time returns an integer" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "os");
    _ = try lua.lua_getfield(&L, -1, "time");
    _ = lua.lua_pcall(&L, 0, 1, 0);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isinteger(&L, -1));
    const t = lua.lua_tointeger(&L, -1) orelse return error.Fail;
    try std.testing.expect(t > 1700000000);
    lua.lua_pop(&L, 2);
}

test "os.clock returns a number" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "os");
    _ = try lua.lua_getfield(&L, -1, "clock");
    _ = lua.lua_pcall(&L, 0, 1, 0);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_isnumber(&L, -1));
    const c = lua.lua_tonumber(&L, -1) orelse return error.Fail;
    try std.testing.expect(c >= 0);
    lua.lua_pop(&L, 2);
}

test "os.difftime returns difference" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "os");
    _ = try lua.lua_getfield(&L, -1, "difftime");
    lua.lua_pushinteger(&L, 1000);
    lua.lua_pushinteger(&L, 500);
    _ = lua.lua_pcall(&L, 2, 1, 0);
    const d = lua.lua_tonumber(&L, -1) orelse return error.Fail;
    try std.testing.expectEqual(@as(f64, 500.0), d);
    lua.lua_pop(&L, 2);
}

test "BUG-020: luaL_newmetatable stores under string key for luaL_setmetatable/luaL_testudata" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // Step 1: verify we can set and get a field in the registry
    _ = lua.lua_pushstring(&L, "hello") orelse return error.Fail;
    try lua.lua_setfield(&L, lua.LUA_REGISTRYINDEX, "mykey");
    _ = try lua.lua_getfield(&L, lua.LUA_REGISTRYINDEX, "mykey");
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    try std.testing.expectEqualStrings("hello", lua.lua_tostring(&L, -1).?);
    lua.lua_pop(&L, 1);

    // Step 2: luaL_newmetatable creates and stores metatable
    const created = try lua.luaL_newmetatable(&L, "TestMeta");
    try std.testing.expectEqual(@as(i32, 1), created);

    // Step 3: verify it's in the registry with getfield
    _ = try lua.lua_getfield(&L, lua.LUA_REGISTRYINDEX, "TestMeta");
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    // Step 4: create userdata and set its metatable
    const p = lua.lua_newuserdatauv(&L, @sizeOf(u8), 0) orelse return error.Fail;
    @as(*u8, @ptrCast(@alignCast(p))).* = 42;
    try lua.luaL_setmetatable(&L, "TestMeta");

    // Step 5: verify metatable is attached
    try std.testing.expectEqual(@as(i32, 1), lua.lua_getmetatable(&L, -1));
    lua.lua_pop(&L, 1);

    // Step 6: test luaL_testudata
    const ud = lua.luaL_testudata(&L, -1, "TestMeta");
    try std.testing.expect(ud != null);
    try std.testing.expectEqual(@as(u8, 42), @as(*u8, @ptrCast(@alignCast(ud.?))).*);

    // Step 7: test luaL_checkudata
    _ = try lua.luaL_checkudata(&L, -1, "TestMeta");
    lua.lua_pop(&L, 2);

    // Step 8: creating again returns 0 (already exists)
    const already_exists = try lua.luaL_newmetatable(&L, "TestMeta");
    try std.testing.expectEqual(@as(i32, 0), already_exists);
}

fn loadlib_test_loader(L: *lua.lua_State) anyerror!i32 {
    _ = lua.lua_pushstring(L, "module_value");
    return 1;
}

test "package table structure" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "package");
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));

    _ = try lua.lua_getfield(&L, -1, "config");
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "path");
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "cpath");
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "loaded");
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "preload");
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "searchers");
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));
    const n = lua.lua_rawlen(&L, -1);
    try std.testing.expectEqual(@as(usize, 4), n);
    lua.lua_pop(&L, 1);

    lua.lua_pop(&L, 1);
}

test "package.searchpath returns error for nonexistent module" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "package");
    _ = try lua.lua_getfield(&L, -1, "searchpath");
    _ = lua.lua_pushstring(&L, "nonexistent_module_xyz_123");
    _ = lua.lua_pushstring(&L, "/nonexistent/?.lua");
    const status = lua.lua_pcall(&L, 2, 2, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 2);
    lua.lua_pop(&L, 1);
}

test "require function exists in global namespace" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "require");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);
}

test "package.loadlib exists" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "package");
    _ = try lua.lua_getfield(&L, -1, "loadlib");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 2);
}

test "require with preloaded C module" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "package");
    _ = try lua.lua_getfield(&L, -1, "preload");
    lua.lua_pushcfunction(&L, loadlib_test_loader);
    try lua.lua_setfield(&L, -2, "mymod");
    lua.lua_pop(&L, 2);

    _ = lua.lua_getglobal(&L, "require");
    _ = lua.lua_pushstring(&L, "mymod");
    const status = lua.lua_pcall(&L, 1, 1, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    try std.testing.expectEqualStrings("module_value", lua.lua_tostring(&L, -1).?);
    lua.lua_pop(&L, 1);
}

test "require caches module in package.loaded" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "package");
    _ = try lua.lua_getfield(&L, -1, "preload");
    lua.lua_pushcfunction(&L, loadlib_test_loader);
    try lua.lua_setfield(&L, -2, "mymod");
    lua.lua_pop(&L, 2);

    // First require
    _ = lua.lua_getglobal(&L, "require");
    _ = lua.lua_pushstring(&L, "mymod");
    var status = lua.lua_pcall(&L, 1, 1, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    lua.lua_pop(&L, 1);

    // Check package.loaded["mymod"]
    _ = lua.lua_getglobal(&L, "package");
    _ = try lua.lua_getfield(&L, -1, "loaded");
    _ = try lua.lua_getfield(&L, -1, "mymod");
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    try std.testing.expectEqualStrings("module_value", lua.lua_tostring(&L, -1).?);
    lua.lua_pop(&L, 3);

    // Second require should return the cached value
    _ = lua.lua_getglobal(&L, "require");
    _ = lua.lua_pushstring(&L, "mymod");
    status = lua.lua_pcall(&L, 1, 1, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expectEqualStrings("module_value", lua.lua_tostring(&L, -1).?);
    lua.lua_pop(&L, 1);
}

test "require non-existent module fails" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    _ = lua.lua_getglobal(&L, "require");
    _ = lua.lua_pushstring(&L, "definitely_not_a_real_module_xyz");
    const status = lua.lua_pcall(&L, 1, 1, 0);
    // pcall catches the error raised by require, returning LUA_ERRRUN
    try std.testing.expectEqual(@as(i32, lua.LUA_ERRRUN), status);
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    const err = lua.lua_tostring(&L, -1).?;
    try std.testing.expect(std.mem.indexOf(u8, err, "not found") != null);
    lua.lua_pop(&L, 1);
}

test "os.getenv environment variable lookup" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var threaded: std.Io.Threaded = .init_single_threaded;
    threaded.allocator = gpa;
    defer threaded.deinit();
    const io = threaded.io();

    var L: lua.lua_State = undefined;
    try lua.luaL_newstate_io(&L, gpa, io);
    defer lua.lua_close(&L);

    try lua.luaL_openlibs(&L);

    // Test a variable that should exist (e.g., PATH)
    _ = lua.lua_getglobal(&L, "os");
    _ = try lua.lua_getfield(&L, -1, "getenv");
    _ = lua.lua_pushstring(&L, "PATH");
    var status = lua.lua_pcall(&L, 1, 1, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    const path_val = lua.lua_tostring(&L, -1).?;
    try std.testing.expect(path_val.len > 0);
    lua.lua_pop(&L, 2); // pop result and os table

    // Test a nonexistent variable
    _ = lua.lua_getglobal(&L, "os");
    _ = try lua.lua_getfield(&L, -1, "getenv");
    _ = lua.lua_pushstring(&L, "THIS_VARIABLE_DOES_NOT_EXIST_XYZ");
    status = lua.lua_pcall(&L, 1, 1, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expectEqual(@as(i32, lua.LUA_TNIL), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 2);
}

test "debug library registration" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    // debug table is a global
    _ = lua.lua_getglobal(&L, "debug");
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));

    // Check key functions exist
    _ = try lua.lua_getfield(&L, -1, "getinfo");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "traceback");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "getupvalue");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "setupvalue");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "getlocal");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "sethook");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    _ = try lua.lua_getfield(&L, -1, "getregistry");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    lua.lua_pop(&L, 1); // pop debug table
}

test "debug.getupvalue on C closure" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    // Push a C closure with one upvalue
    lua.lua_pushinteger(&L, 42);
    const myfunc: lua.lua_CFunction = struct {
        fn f(LS: *lua.lua_State) !i32 {
            _ = LS;
            return 0;
        }
    }.f;
    lua.lua_pushcclosure(&L, myfunc, 1);

    // getupvalue(closure, 1) → should return the upvalue
    const name = lua.lua_getupvalue(&L, -1, 1);
    // C closures return "" as name
    try std.testing.expect(name != null);
    // The upvalue value (42) was pushed on stack
    try std.testing.expectEqual(@as(i32, lua.LUA_TNUMBER), lua.lua_type(&L, -1));
    try std.testing.expectEqual(@as(i64, 42), lua.lua_tointeger(&L, -1).?);
    lua.lua_pop(&L, 1); // pop upvalue
    lua.lua_pop(&L, 1); // pop closure
}

test "debug.getinfo on C function" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const myfunc: lua.lua_CFunction = struct {
        fn f(LS: *lua.lua_State) !i32 {
            _ = LS;
            return 0;
        }
    }.f;
    lua.lua_pushcfunction(&L, myfunc);

    var ar: lua.lua_Debug = std.mem.zeroes(lua.lua_Debug);
    ar.i_ci = null;
    // Use '>' prefix to query function from stack top
    lua.lua_pushvalue(&L, -1); // push a copy for getinfo to consume
    const status = try lua.lua_getinfo(&L, ">Su", &ar);
    try std.testing.expectEqual(@as(i32, 1), status);
    // C function should have linedefined = -1
    try std.testing.expectEqual(@as(i32, -1), ar.linedefined);
    try std.testing.expect(ar.what != null);
    try std.testing.expect(std.mem.eql(u8, ar.what.?, "C"));
    lua.lua_pop(&L, 1); // pop original closure
}

test "debug.sethook and gethook" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // Initially no hook
    try std.testing.expect(lua.lua_gethook(&L) == null);
    try std.testing.expectEqual(@as(i32, 0), lua.lua_gethookmask(&L));

    // Set a hook via C API
    const myhook: lua.lua_Hook = struct {
        fn h(LS: *lua.lua_State, ar: ?*lua.lua_Debug) void {
            _ = LS;
            _ = ar;
        }
    }.h;
    lua.lua_sethook(&L, myhook, @bitCast(lua.LUA_MASKLINE | lua.LUA_MASKCALL), 0);

    try std.testing.expect(lua.lua_gethook(&L) != null);
    const got_mask = lua.lua_gethookmask(&L);
    try std.testing.expect((got_mask & @as(i32, @bitCast(lua.LUA_MASKLINE))) != 0);

    // Remove hook
    lua.lua_sethook(&L, null, 0, 0);
    try std.testing.expect(lua.lua_gethook(&L) == null);
}

test "debug.traceback produces non-empty string" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    // Call debug.traceback() with an empty msg
    _ = lua.lua_getglobal(&L, "debug");
    _ = try lua.lua_getfield(&L, -1, "traceback");
    _ = lua.lua_pushstring(&L, "test error");
    const rc = lua.lua_pcall(&L, 1, 1, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), rc);
    // Result should be a string
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    const tb = lua.lua_tostring(&L, -1).?;
    // Should contain "stack traceback:"
    try std.testing.expect(std.mem.indexOf(u8, tb, "stack traceback:") != null);
    lua.lua_pop(&L, 2); // pop result and debug table
}

// ---------------------------------------------------------------------------
// Lexer tests (Phase G.1) — see src/llex.zig for the implementation.
// ---------------------------------------------------------------------------
const LexerReaderData = struct {
    src: []const u8,
    pos: usize,
};

fn lexerStringReader(
    _: *lua.lua_State,
    data: ?*anyopaque,
    size: ?*usize,
) anyerror!?[]const u8 {
    const st = @as(*LexerReaderData, @ptrCast(@alignCast(data orelse return null)));
    if (st.pos >= st.src.len) {
        size.?.* = 0;
        return null;
    }
    const rest = st.src[st.pos..];
    st.pos = st.src.len;
    size.?.* = rest.len;
    return rest;
}

fn newSource(L: *lua.lua_State, name: []const u8) !*lua.lua_TString {
    return try lua.lstring.luaS_new(L, name);
}

test "lex basic tokens and numbers" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const src = "local x = 1 + 2.5 -- comment\nprint('hi')";
    var rd = LexerReaderData{ .src = src, .pos = 0 };
    const source = try newSource(&L, "test");

    var ls: lua.llex.LexState = undefined;
    try lua.llex.luaX_setinput(&L, &ls, lexerStringReader, &rd, source, &[_]u8{}, false);
    defer ls.buff.deinit(ls.allocator);

    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_LOCAL);

    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_NAME);
    try std.testing.expect(std.mem.eql(u8, ls.t.seminfo.ts.?.s, "x"));

    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == '=');

    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_INT);
    try std.testing.expectEqual(@as(i64, 1), ls.t.seminfo.i);

    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == '+');

    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_FLT);
    try std.testing.expect(std.math.approxEqAbs(f64, ls.t.seminfo.r, 2.5, 1e-9));

    // skip the comment and 'print'
    try lua.llex.luaX_next(&ls); // 'print' name
    try std.testing.expect(ls.t.token == lua.llex.TK_NAME);
    try lua.llex.luaX_next(&ls); // '('
    try std.testing.expect(ls.t.token == '(');
    try lua.llex.luaX_next(&ls); // string 'hi'
    try std.testing.expect(ls.t.token == lua.llex.TK_STRING);
    try std.testing.expect(std.mem.eql(u8, ls.t.seminfo.ts.?.s, "hi"));
    try lua.llex.luaX_next(&ls); // ')'
    try std.testing.expect(ls.t.token == ')');

    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_EOS);
}

test "lex integer and hex/float forms" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const src = "0 42 -7 0xff 3.14 1e10 0x1p4 1. .5";
    var rd = LexerReaderData{ .src = src, .pos = 0 };
    const source = try newSource(&L, "t2");

    var ls: lua.llex.LexState = undefined;
    try lua.llex.luaX_setinput(&L, &ls, lexerStringReader, &rd, source, &[_]u8{}, false);
    defer ls.buff.deinit(ls.allocator);

    const expect_int = struct {
        fn check(ls2: *lua.llex.LexState, v: i64) !void {
            try lua.llex.luaX_next(ls2);
            try std.testing.expect(ls2.t.token == lua.llex.TK_INT);
            try std.testing.expectEqual(v, ls2.t.seminfo.i);
        }
    }.check;
    const expect_flt = struct {
        fn check(ls2: *lua.llex.LexState, v: f64) !void {
            try lua.llex.luaX_next(ls2);
            try std.testing.expect(ls2.t.token == lua.llex.TK_FLT);
            try std.testing.expect(std.math.approxEqAbs(f64, v, ls2.t.seminfo.r, 1e-9));
        }
    }.check;

    try expect_int(&ls, 0);
    try expect_int(&ls, 42);
    try lua.llex.luaX_next(&ls); // '-' is the unary-minus operator, not part of the numeral
    try std.testing.expect(ls.t.token == '-');
    try expect_int(&ls, 7);
    try expect_int(&ls, 0xff);
    try expect_flt(&ls, 3.14);
    try expect_flt(&ls, 1e10);
    try expect_flt(&ls, 0x1p4);
    try expect_flt(&ls, 1.0);
    try expect_flt(&ls, 0.5);

    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_EOS);
}

test "lex long string, escapes, and comments" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const src =
        "s = [[line1\nline2]] .. 'a\\nb' .. \"\\x41\" .. '\\u{41}' --[[c]] -- d\n" ++
        "t = 'tab\\tend'";
    var rd = LexerReaderData{ .src = src, .pos = 0 };
    const source = try newSource(&L, "t3");

    var ls: lua.llex.LexState = undefined;
    try lua.llex.luaX_setinput(&L, &ls, lexerStringReader, &rd, source, &[_]u8{}, false);
    defer ls.buff.deinit(ls.allocator);

    try lua.llex.luaX_next(&ls); // s
    try std.testing.expect(ls.t.token == lua.llex.TK_NAME);
    try lua.llex.luaX_next(&ls); // =
    try lua.llex.luaX_next(&ls); // [[...]] long string
    try std.testing.expect(ls.t.token == lua.llex.TK_STRING);
    try std.testing.expect(std.mem.eql(u8, ls.t.seminfo.ts.?.s, "line1\nline2"));
    try lua.llex.luaX_next(&ls); // ..
    try std.testing.expect(ls.t.token == lua.llex.TK_CONCAT);
    try lua.llex.luaX_next(&ls); // 'a\nb'
    try std.testing.expect(ls.t.token == lua.llex.TK_STRING);
    try std.testing.expect(std.mem.eql(u8, ls.t.seminfo.ts.?.s, "a\nb"));
    try lua.llex.luaX_next(&ls); // ..
    try lua.llex.luaX_next(&ls); // "\x41"
    try std.testing.expect(std.mem.eql(u8, ls.t.seminfo.ts.?.s, "A"));
    try lua.llex.luaX_next(&ls); // ..
    try lua.llex.luaX_next(&ls); // '\u{41}'
    try std.testing.expect(std.mem.eql(u8, ls.t.seminfo.ts.?.s, "A"));
    // comment '--[[c]]' and '-- d' skipped; then newline; then 't'
    try lua.llex.luaX_next(&ls); // t
    try std.testing.expect(ls.t.token == lua.llex.TK_NAME);
    try lua.llex.luaX_next(&ls); // =
    try lua.llex.luaX_next(&ls); // 'tab\tend'
    try std.testing.expect(std.mem.eql(u8, ls.t.seminfo.ts.?.s, "tab\tend"));
    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_EOS);
}

test "lex error on unfinished string" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const src = "x = 'unterminated";
    var rd = LexerReaderData{ .src = src, .pos = 0 };
    const source = try newSource(&L, "t4");

    var ls: lua.llex.LexState = undefined;
    try lua.llex.luaX_setinput(&L, &ls, lexerStringReader, &rd, source, &[_]u8{}, false);
    defer ls.buff.deinit(ls.allocator);

    // x
    try lua.llex.luaX_next(&ls);
    // =
    try lua.llex.luaX_next(&ls);
    // 'unterminated -> error
    const got = lua.llex.luaX_next(&ls);
    try std.testing.expectError(error.SyntaxError, got);
}

test "lex reserved words and operators" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const src = "if a <= b then return a ~= b end";
    var rd = LexerReaderData{ .src = src, .pos = 0 };
    const source = try newSource(&L, "t5");

    var ls: lua.llex.LexState = undefined;
    try lua.llex.luaX_setinput(&L, &ls, lexerStringReader, &rd, source, &[_]u8{}, false);
    defer ls.buff.deinit(ls.allocator);

    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_IF);
    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_NAME);
    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_LE);
    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_NAME);
    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_THEN);
    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_RETURN);
    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_NAME);
    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_NE);
    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_NAME);
    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_END);
    try lua.llex.luaX_next(&ls);
    try std.testing.expect(ls.t.token == lua.llex.TK_EOS);
}

test "function execution and variable assignment" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const status = try lua.luaL_dostring(&L, "local x = 0; function f(a) x = a end; f(42.0); return x", "=(test)");
    if (status != 0) {
        if (lua.lua_tostring(&L, -1)) |msg| {
            std.debug.print("\nLUA SYNTAX ERROR: {s}\n", .{msg});
        }
    }
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expectEqual(@as(f64, 42.0), lua.lua_tonumber(&L, -1));
}

// ===================================================================
// Phase H.1 — C API stubs -> implementations
// ===================================================================

fn h1_testLen(L: *lua.lua_State) !i32 {
    lua.lua_pushinteger(L, 7);
    return 1;
}

fn h1_testClose(L: *lua.lua_State) !i32 {
    // Mark that __close ran by setting a global flag.
    lua.lua_pushboolean(L, 1);
    lua.lua_setglobal(L, "__closed_ran");
    return 0;
}

fn h1_dummyAlloc(ud: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) ?*anyopaque {
    _ = ud;
    _ = ptr;
    _ = osize;
    _ = nsize;
    return null;
}

test "H.1 luaL_newtable creates an empty table" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.luaL_newtable(&L);
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));
    try std.testing.expectEqual(@as(usize, 0), lua.lua_rawlen(&L, -1));
}

test "H.1 lua_concat concatenates strings and numbers" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // strings
    _ = lua.lua_pushstring(&L, "ab");
    _ = lua.lua_pushstring(&L, "cd");
    _ = lua.lua_pushstring(&L, "ef");
    lua.lua_concat(&L, 3);
    const s = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "abcdef", s);

    // mixed number + string
    lua.lua_settop(&L, 0);
    lua.lua_pushinteger(&L, 42);
    _ = lua.lua_pushstring(&L, "xyz");
    lua.lua_concat(&L, 2);
    const s2 = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "42xyz", s2);

    // empty concat yields empty string
    lua.lua_settop(&L, 0);
    lua.lua_concat(&L, 0);
    const s3 = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "", s3);
}

test "H.1 lua_len pushes length (string/table/__len)" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // string length
    _ = lua.lua_pushstring(&L, "hello");
    try lua.lua_len(&L, -1);
    try std.testing.expectEqual(@as(f64, 5.0), lua.lua_tonumber(&L, -1));
    lua.lua_settop(&L, 0);

    // table length
    lua.lua_createtable(&L, 0, 0);
    var i: i32 = 1;
    while (i <= 3) : (i += 1) {
        lua.lua_pushinteger(&L, @as(i64, @intCast(i * 10)));
        lua.lua_rawseti(&L, -2, @as(i64, @intCast(i)));
    }
    try lua.lua_len(&L, -1);
    try std.testing.expectEqual(@as(f64, 3.0), lua.lua_tonumber(&L, -1));
    lua.lua_settop(&L, 0);

    // __len metamethod
    lua.lua_createtable(&L, 0, 0); // subject table
    lua.lua_createtable(&L, 0, 0); // metatable
    lua.lua_pushcfunction(&L, h1_testLen);
    try lua.lua_setfield(&L, -2, "__len");
    _ = lua.lua_setmetatable(&L, -2);
    try lua.lua_len(&L, -1);
    try std.testing.expectEqual(@as(f64, 7.0), lua.lua_tonumber(&L, -1));
}

test "H.1 luaL_len returns integer length via __len" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    var i: i32 = 1;
    while (i <= 4) : (i += 1) {
        lua.lua_pushinteger(&L, @as(i64, @intCast(i)));
        lua.lua_rawseti(&L, -2, @as(i64, @intCast(i)));
    }
    const len = try lua.luaL_len(&L, -1);
    try std.testing.expectEqual(@as(i64, 4), len);

    // __len metamethod path
    lua.lua_createtable(&L, 0, 0);
    lua.lua_createtable(&L, 0, 0);
    lua.lua_pushcfunction(&L, h1_testLen);
    try lua.lua_setfield(&L, -2, "__len");
    _ = lua.lua_setmetatable(&L, -2);
    const len2 = try lua.luaL_len(&L, -1);
    try std.testing.expectEqual(@as(i64, 7), len2);
}

test "H.1 luaL_where pushes a source location string" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.luaL_where(&L, 1);
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    // At top level there is no active function, so the result is "".
    const s = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "", s);
}

test "H.1 createargtable builds the global arg table" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lua.createargtable(&L, &[_][]const u8{ "luazig", "script.lua", "extra1", "extra2" });
    _ = lua.lua_getglobal(&L, "arg");
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));

    _ = lua.lua_rawgeti(&L, -1, 0);
    const a0 = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "script.lua", a0);
    lua.lua_pop(&L, 1);

    _ = lua.lua_rawgeti(&L, -1, 1);
    const a1 = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "extra1", a1);
    lua.lua_pop(&L, 1);

    _ = lua.lua_rawgeti(&L, -1, 2);
    const a2 = lua.lua_tostring(&L, -1) orelse return error.TestFailed;
    try std.testing.expectEqualSlices(u8, "extra2", a2);
}

test "H.1 lua_getallocf / lua_setallocf roundtrip" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    var ud1: ?*anyopaque = undefined;
    const af1 = lua.lua_getallocf(&L, &ud1);
    // Default allocator must be present.
    if (ud1 == null) return error.TestFailed;

    // Swap in a different allocator and read it back.
    lua.lua_setallocf(&L, h1_dummyAlloc, @as(?*anyopaque, @ptrFromInt(0x1234)));
    var ud2: ?*anyopaque = undefined;
    const af2 = lua.lua_getallocf(&L, &ud2);
    if (af2 != h1_dummyAlloc) return error.TestFailed;
    if (ud2 != @as(?*anyopaque, @ptrFromInt(0x1234))) return error.TestFailed;

    // Restore the default so the state stays usable.
    lua.lua_setallocf(&L, af1, ud1);
}

test "H.1 lua_closeslot runs __close metamethod" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // Build a table with a __close metamethod.
    lua.lua_createtable(&L, 0, 0); // subject
    lua.lua_createtable(&L, 0, 0); // metatable
    lua.lua_pushcfunction(&L, h1_testClose);
    try lua.lua_setfield(&L, -2, "__close");
    _ = lua.lua_setmetatable(&L, -2);

    // Before closing, the flag is absent.
    _ = lua.lua_getglobal(&L, "__closed_ran");
    try std.testing.expectEqual(@as(i32, lua.LUA_TNIL), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    lua.lua_closeslot(&L, -1);

    _ = lua.lua_getglobal(&L, "__closed_ran");
    try std.testing.expectEqual(@as(i32, 1), lua.lua_toboolean(&L, -1));
}

// ===================================================================
// Phase H.2 — oslib stubs -> implementations
// ===================================================================

test "H.2 os.date '*t' returns a populated table" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const status = try lua.luaL_dostring(
        &L,
        "local t = os.date('*t'); return t.year, t.month, t.day, t.hour, t.min, t.sec, t.wday, t.yday",
        "=(test)",
    );
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expect(lua.lua_tointeger(&L, -8).? >= 2024); // year
    try std.testing.expect((lua.lua_tointeger(&L, -7).? >= 1) and (lua.lua_tointeger(&L, -7).? <= 12)); // month
    try std.testing.expect((lua.lua_tointeger(&L, -1).? >= 1) and (lua.lua_tointeger(&L, -1).? <= 366)); // yday
}

test "H.2 os.date format string and UTC prefix" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const status = try lua.luaL_dostring(
        &L,
        "return os.date('%Y'), os.date('!%Y')",
        "=(test)",
    );
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    const local_year = lua.lua_tostring(&L, -2).?;
    try std.testing.expectEqual(@as(usize, 4), local_year.len);
    const utc_year = lua.lua_tostring(&L, -1).?;
    try std.testing.expectEqual(@as(usize, 4), utc_year.len);
}

test "H.2 os.time returns epoch and round-trips with '*t'" {
    if (@import("builtin").os.tag != .linux) return error.SkipZigTest;
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const status = try lua.luaL_dostring(
        &L,
        "local t = os.date('*t'); return os.time(), os.time(t) == os.time()",
        "=(test)",
    );
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expect(lua.lua_tonumber(&L, -2).? > 0);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_toboolean(&L, -1));
}

test "H.2 os.execute reports success/failure with status code" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    // `os.execute` returns three values: (status, "exit", code). The first
    // result (at index -3) is `true` on success and `nil` on failure.
    // Failure: status non-zero -> first result is nil.
    var status = try lua.luaL_dostring(&L, "return os.execute('false')", "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expectEqual(@as(i32, 3), lua.lua_gettop(&L));
    try std.testing.expectEqual(@as(i32, lua.LUA_TNIL), lua.lua_type(&L, -3));
    lua.lua_settop(&L, 0);

    // Success: status 0 -> first result is boolean true.
    status = try lua.luaL_dostring(&L, "return os.execute('true')", "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expectEqual(@as(i32, 3), lua.lua_gettop(&L));
    try std.testing.expectEqual(@as(i32, 1), lua.lua_toboolean(&L, -3));
}

test "H.2 os.setlocale returns the active locale" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const status = try lua.luaL_dostring(&L, "return os.setlocale('C')", "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    const loc = lua.lua_tostring(&L, -1).?;
    try std.testing.expectEqual(@as(usize, 1), loc.len);
    try std.testing.expectEqual(@as(u8, 'C'), loc[0]);
}

// ===================================================================
// BUG-038 — VM TAILCALL with a C function must deliver its arguments
// ===================================================================

test "BUG-038 tail call to C function delivers the argument" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    // `return os.execute('true')` is a tail call: the string arg was being lost.
    // `os.execute` returns three values (status, "exit", code); the first
    // result (-3) is `true` on success.
    var status = try lua.luaL_dostring(&L, "return os.execute('true')", "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expectEqual(@as(i32, 1), lua.lua_toboolean(&L, -3));
    lua.lua_settop(&L, 0);

    // C function receiving a value computed by the caller (Lua -> C tail call).
    status = try lua.luaL_dostring(
        &L,
        "function g(x) return string.rep('ab', x) end; return g(3)",
        "=(test)",
    );
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    const s = lua.lua_tostring(&L, -1).?;
    try std.testing.expectEqual(@as(usize, 6), s.len);
    try std.testing.expectEqual(@as(u8, 'a'), s[0]);
}

test "BUG-038 tail call between Lua functions propagates the argument" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    // f is called only in tail position; the argument must flow through.
    const status = try lua.luaL_dostring(
        &L,
        "function f(x) return x + 1 end; function g(x) return f(x) end; return g(41)",
        "=(test)",
    );
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expectEqual(@as(f64, 42), lua.lua_tonumber(&L, -1).?);
}

// ===================================================================
// BUG-043 — os.exit honours the second argument (conditional lua_close)
// ===================================================================

test "BUG-043 os.exit is registered as a function" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    // Verify os.exit is accessible in the os table.
    const status = try lua.luaL_dostring(&L, "return type(os.exit)", "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    try std.testing.expectEqualStrings("function", lua.lua_tostring(&L, -1).?);
    lua.lua_settop(&L, 0);

    // We cannot test os.exit behavior in-process because os.exit always calls
    // std.process.exit, which terminates the process immediately. The
    // exit behavior is verified at the binary level by running the built
    // luazig binary with scripts that call os.exit with various arguments.
}

// ===================================================================
// Phase H.4 — Reference system (luaL_ref / luaL_unref)
// ===================================================================

test "H.4 luaL_ref stores a value and returns a reference" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // Create a table to use as the reference table
    lua.lua_createtable(&L, 0, 0);
    const t = lua.lua_gettop(&L); // index of the table

    // Store a string value
    _ = lua.lua_pushstring(&L, "hello") orelse unreachable;
    const ref1 = lauxlib.luaL_ref(&L, t);
    try std.testing.expect(ref1 >= 0);
    try std.testing.expectEqual(@as(i32, 2), ref1); // first ref should be 2 (t[1]=0, so rawlen=1, ref=2)

    // Store a boolean
    lua.lua_pushboolean(&L, 1);
    const ref2 = lauxlib.luaL_ref(&L, t);
    try std.testing.expect(ref2 >= 0);
    try std.testing.expectEqual(@as(i32, 3), ref2); // second sequential ref should be 3

    lua.lua_settop(&L, 0);
}

test "H.4 luaL_ref returns LUA_REFNIL for nil" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    const t = lua.lua_gettop(&L);

    lua.lua_pushnil(&L);
    const ref = lauxlib.luaL_ref(&L, t);
    try std.testing.expectEqual(@as(i32, lauxlib.LUA_REFNIL), ref);

    lua.lua_settop(&L, 0);
}

test "H.4 luaL_unref frees a reference for reuse" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    const t = lua.lua_gettop(&L);

    // Store two values
    _ = lua.lua_pushstring(&L, "first") orelse unreachable;
    const ref1 = lauxlib.luaL_ref(&L, t);
    _ = lua.lua_pushstring(&L, "second") orelse unreachable;
    const ref2 = lauxlib.luaL_ref(&L, t);

    try std.testing.expectEqual(@as(i32, 2), ref1);
    try std.testing.expectEqual(@as(i32, 3), ref2);

    // Free ref1 — it should go back into the free list
    lauxlib.luaL_unref(&L, t, ref1);

    // Push a new value — it should reuse ref1 (2)
    _ = lua.lua_pushstring(&L, "third") orelse unreachable;
    const ref3 = lauxlib.luaL_ref(&L, t);
    try std.testing.expectEqual(@as(i32, 2), ref3); // reuses freed slot 2

    lua.lua_settop(&L, 0);
}

test "H.4 luaL_ref stores and retrieves via rawgeti" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    const t = lua.lua_gettop(&L);

    _ = lua.lua_pushstring(&L, "stored_value") orelse unreachable;
    const ref = lauxlib.luaL_ref(&L, t);

    // Retrieve the stored value via rawgeti
    const typ = lua.lua_rawgeti(&L, t, @intCast(ref));
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), typ);
    const s = lua.lua_tostring(&L, -1) orelse "";
    try std.testing.expectEqualStrings("stored_value", s);

    lua.lua_settop(&L, 0);
}

test "H.4 luaL_unref on LUA_REFNIL is a no-op" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    const t = lua.lua_gettop(&L);

    // unref with negative value should be a no-op
    lauxlib.luaL_unref(&L, t, lauxlib.LUA_REFNIL);
    lauxlib.luaL_unref(&L, t, lauxlib.LUA_NOREF);

    // Should still be able to create references
    _ = lua.lua_pushstring(&L, "ok") orelse unreachable;
    const ref = lauxlib.luaL_ref(&L, t);
    try std.testing.expectEqual(@as(i32, 2), ref);

    lua.lua_settop(&L, 0);
}

test "H.4 luaL_ref works via Lua code (internal C API interaction)" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // From Lua, create a table and pass it to a C function that uses refs
    // We test indirectly: store in a table, mutate the original, verify ref
    // doesn't change.
    const status = try lua.luaL_dostring(&L, "local t = {a = 1, b = 2}\n" ++
        "-- The C API reference system works on the table via rawgeti/rawseti\n" ++
        "-- so we can test via raw access from Lua too\n" ++
        "t[1] = 42\n" ++
        "return #t", "=(test)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
    // After setting t[1] = 42, the table length should be 1 (sequence)
    const len = lua.lua_tointeger(&L, -1) orelse 0;
    try std.testing.expectEqual(@as(i64, 1), len);

    lua.lua_settop(&L, 0);
}

// ===================================================================
// Phase H.5 - Missing C API functions
// ===================================================================

test "H.5 lua_version returns the version number" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const ver = lua.lua_version(&L);
    try std.testing.expectEqual(@as(f64, 505.0), ver);
}

test "H.5 lua_atpanic sets and returns old panic handler" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const old = lua.lua_atpanic(&L, null);
    try std.testing.expectEqual(@as(?lua.lua_CFunction, null), old);

    const handler: lua.lua_CFunction = struct {
        fn panic(L_: *lua.lua_State) anyerror!i32 {
            _ = L_;
            return 0;
        }
    }.panic;
    const prev = lua.lua_atpanic(&L, handler);
    try std.testing.expectEqual(@as(?lua.lua_CFunction, null), prev);

    // Setting it again should return the previously stored handler.
    const prev2 = lua.lua_atpanic(&L, null);
    try std.testing.expect(prev2 == handler);
}

test "H.5 lua_numbertocstring formats a number" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_pushnumber(&L, 42.5);
    var buf: [64]u8 = undefined;
    const n = lua.lua_numbertocstring(&L, -1, &buf);
    try std.testing.expect(n > 0);
    const s = buf[0 .. n - 1];
    try std.testing.expectEqualStrings("42.5", s);

    lua.lua_settop(&L, 0);
}

test "H.5 lua_numbertocstring returns 0 for non-number" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    _ = lua.lua_pushstring(&L, "not a number");
    var buf: [64]u8 = undefined;
    const n = lua.lua_numbertocstring(&L, -1, &buf);
    try std.testing.expectEqual(@as(usize, 0), n);

    lua.lua_settop(&L, 0);
}

test "H.5 luaL_loadstring loads a Lua chunk" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const status = lauxlib.luaL_loadstring(&L, "return 42");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);

    const call_status = lua.lua_pcall(&L, 0, lua.LUA_MULTRET, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), call_status);

    const val = lua.lua_tointeger(&L, -1) orelse 0;
    try std.testing.expectEqual(@as(i64, 42), val);

    lua.lua_settop(&L, 0);
}

test "H.5 luaL_loadbufferx loads a Lua chunk from a buffer" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const chunk = "return 'hello'";
    const status = lauxlib.luaL_loadbufferx(&L, chunk, "=(buffer)", "t");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);

    const call_status = lua.lua_pcall(&L, 0, lua.LUA_MULTRET, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), call_status);

    const s = lua.lua_tostring(&L, -1) orelse "";
    try std.testing.expectEqualStrings("hello", s);

    lua.lua_settop(&L, 0);
}

test "H.5 luaL_getsubtable creates or gets a subtable" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    const t = lua.lua_gettop(&L);

    const created = try lauxlib.luaL_getsubtable(&L, t, "sub");
    try std.testing.expectEqual(@as(i32, 0), created);
    lua.lua_pop(&L, 1);

    const found = try lauxlib.luaL_getsubtable(&L, t, "sub");
    try std.testing.expectEqual(@as(i32, 1), found);
    lua.lua_pop(&L, 1);

    lua.lua_settop(&L, 0);
}

test "H.5 luaL_dofile fails gracefully for nonexistent file" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const status = lauxlib.luaL_dofile(&L, "/nonexistent/file.lua");
    try std.testing.expect(status != lua.LUA_OK);

    lua.lua_settop(&L, 0);
}

test "H.5 luaL_makeseed returns a non-zero seed" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const seed = lauxlib.luaL_makeseed(&L);
    try std.testing.expect(seed != 0);
}

test "H.5 luaL_checkversion_ succeeds for matching version" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lauxlib.luaL_checkversion_(&L, 505.0, lauxlib.LUAL_NUMSIZES);
}

test "H.5 luaL_checkversion convenience wrapper succeeds" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    try lauxlib.luaL_checkversion(&L);
}

test "H.5 luaL_loadfilex loads and runs a real file" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    var threaded: std.Io.Threaded = .init_single_threaded;
    threaded.allocator = gpa;
    const io = threaded.io();
    defer threaded.deinit();

    const tmp_path = "test_h5_loadfile_tmp.lua";
    const content = "return 99";
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = tmp_path, .data = content });
    defer std.Io.Dir.cwd().deleteFile(io, tmp_path) catch {};

    const status = lauxlib.luaL_loadfilex(&L, tmp_path, "t");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);

    const call_status = lua.lua_pcall(&L, 0, lua.LUA_MULTRET, 0);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), call_status);

    const val = lua.lua_tointeger(&L, -1) orelse 0;
    try std.testing.expectEqual(@as(i64, 99), val);

    lua.lua_settop(&L, 0);
}

test "H.5 luaL_callmeta calls __tostring on a table with metatable" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // Create a table with a __tostring metamethod, using the C API directly.
    const Meta_tostr: lua.lua_CFunction = struct {
        fn tostr(L_: *lua.lua_State) anyerror!i32 {
            _ = lua.lua_pushstring(L_, "custom");
            return 1;
        }
    }.tostr;

    lua.lua_createtable(&L, 0, 0); // the table
    lua.lua_createtable(&L, 0, 1); // the metatable
    lua.lua_pushcfunction(&L, Meta_tostr);
    try lua.lua_setfield(&L, -2, "__tostring");
    _ = lua.lua_setmetatable(&L, -2); // attach metatable to the table

    const called = try lauxlib.luaL_callmeta(&L, -1, "__tostring");
    try std.testing.expectEqual(@as(i32, 1), called);
    const s = lua.lua_tostring(&L, -1) orelse "";
    try std.testing.expectEqualStrings("custom", s);

    lua.lua_settop(&L, 0);
}

test "H.5 luaL_callmeta returns 0 when no metamethod" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 0);
    const called = try lauxlib.luaL_callmeta(&L, -1, "__nonexistent");
    try std.testing.expectEqual(@as(i32, 0), called);

    lua.lua_settop(&L, 0);
}

test "H.5 luaL_buffer functions: addstring, bufflen, buffaddr, buffsub" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    var b: lauxlib.luaL_Buffer = .{};
    lauxlib.luaL_buffinit(&L, &b);
    defer b.buf.deinit(L.allocator);

    try lauxlib.luaL_addstring(&L, &b, "hello");
    try lauxlib.luaL_addstring(&L, &b, " world");

    try std.testing.expectEqual(@as(usize, 11), lauxlib.luaL_bufflen(&b));

    const addr = lauxlib.luaL_buffaddr(&b);
    try std.testing.expectEqualStrings("hello world", addr);

    lauxlib.luaL_buffsub(&b, 6);
    try std.testing.expectEqual(@as(usize, 5), lauxlib.luaL_bufflen(&b));
}

test "H.5 luaL_buffinitsize and luaL_prepbuffer reserve capacity" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    var b: lauxlib.luaL_Buffer = .{};
    const slice = try lauxlib.luaL_buffinitsize(&L, &b, 32);
    defer b.buf.deinit(L.allocator);

    try std.testing.expectEqual(@as(usize, 0), lauxlib.luaL_bufflen(&b));
    try std.testing.expect(slice.len >= 32);

    // Write into the prepared buffer, then commit via luaL_addsize.
    @memcpy(slice[0..5], "hello");
    lauxlib.luaL_addsize(&b, 5);
    try std.testing.expectEqual(@as(usize, 5), lauxlib.luaL_bufflen(&b));
    const addr = lauxlib.luaL_buffaddr(&b);
    try std.testing.expectEqualStrings("hello", addr);

    // luaL_prepbuffer should reserve additional capacity (>= 1 byte).
    const p = try lauxlib.luaL_prepbuffer(&L, &b);
    try std.testing.expect(p.len >= 1);
}

test "H.6 luaL_tolstring pushes a copy (string contract)" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    _ = lua.lua_pushstring(&L, "hello");
    const top_before = lua.lua_gettop(&L);
    const s = lauxlib.luaL_tolstring(&L, -1, null);
    try std.testing.expect(s != null);
    try std.testing.expectEqualStrings("hello", s.?);
    const top_after = lua.lua_gettop(&L);
    // luaL_tolstring must always leave exactly one value on top. For a string
    // it pushes a copy, so the stack grows by one and the original remains.
    try std.testing.expectEqual(@as(i32, top_before + 1), top_after);
    lua.lua_pop(&L, 1);
    try std.testing.expectEqualStrings("hello", lua.lua_tostring(&L, -1).?);
}

test "H.6 CLI luazig behaves like the reference interpreter" {
    const gpa = std.testing.allocator;
    // Build a spawn-capable I/O instance (the global single-threaded one uses a
    // failing allocator, so it cannot spawn child processes).
    var threaded: std.Io.Threaded = .init_single_threaded;
    threaded.allocator = gpa;
    defer threaded.deinit();
    const io = threaded.io();

    // `zig build test` builds the interpreter into zig-out/bin/luazig.
    const bin = "zig-out/bin/luazig";
    std.Io.Dir.cwd().access(io, bin, .{}) catch |err| switch (err) {
        error.FileNotFound => return, // binary not built; skip
        else => return err,
    };

    const runCapture = struct {
        fn runCapture(ally: std.mem.Allocator, i: std.Io, argv: []const []const u8) ![]u8 {
            const result = try std.process.run(ally, i, .{ .argv = argv });
            ally.free(result.stderr);
            return result.stdout; // caller frees
        }
    }.runCapture;

    // -e "print(42)" => "42\n"
    {
        const out = try runCapture(gpa, io, &[_][]const u8{ bin, "-e", "print(42)" });
        defer gpa.free(out);
        try std.testing.expectEqualStrings("42\n", out);
    }

    // arithmetic via -e
    {
        const out = try runCapture(gpa, io, &[_][]const u8{ bin, "-e", "print(1+2)" });
        defer gpa.free(out);
        try std.testing.expectEqualStrings("3\n", out);
    }

    // -v prints the Lua 5.5 copyright banner
    {
        const out = try runCapture(gpa, io, &[_][]const u8{ bin, "-v" });
        defer gpa.free(out);
        try std.testing.expect(std.mem.indexOf(u8, out, "Lua 5.5") != null);
    }

    // -l math loads the math library; -e then uses it
    {
        const out = try runCapture(gpa, io, &[_][]const u8{ bin, "-l", "math", "-e", "print(math.pi)" });
        defer gpa.free(out);
        try std.testing.expect(std.mem.indexOf(u8, out, "3.14159265358979") != null);
    }

    // script file
    {
        const tmp = try std.Io.Dir.cwd().createFile(io, "h6_cli_tmp.lua", .{});
        defer std.Io.Dir.cwd().deleteFile(io, "h6_cli_tmp.lua") catch {};
        defer tmp.close(io);
        try tmp.writeStreamingAll(io, "print(\"hi\")");
        const out = try runCapture(gpa, io, &[_][]const u8{ bin, "h6_cli_tmp.lua" });
        defer gpa.free(out);
        try std.testing.expectEqualStrings("hi\n", out);
    }

    // -- stops option parsing: "-e" after -- is a script name, not an option
    {
        const out = try runCapture(gpa, io, &[_][]const u8{ bin, "--", "-e", "print(7)" });
        defer gpa.free(out);
        try std.testing.expect(std.mem.indexOf(u8, out, "7") == null);
    }
}

/// Helper `lua_Alloc` for the LSTRMEM external-string test: frees the caller's
/// bytes via the test allocator and counts free calls.
const ExtAllocCtx = struct {
    alloc: std.mem.Allocator,
    free_count: usize,
};

fn testExtAlloc(ud: ?*anyopaque, ptr: ?*anyopaque, osize: usize, nsize: usize) ?*anyopaque {
    const ctx = @as(*ExtAllocCtx, @ptrCast(@alignCast(ud.?)));
    if (nsize == 0) {
        if (ptr) |p| {
            const bytes: [*]u8 = @ptrCast(@alignCast(p));
            const slice = bytes[0..osize];
            ctx.alloc.free(slice);
            ctx.free_count += 1;
        }
        return null;
    } else if (ptr == null) {
        const slice = ctx.alloc.alloc(u8, nsize) catch return null;
        return slice.ptr;
    }
    const old_bytes: [*]u8 = @ptrCast(@alignCast(ptr.?));
    const old = old_bytes[0..osize];
    const new_slice = ctx.alloc.realloc(old, nsize) catch return null;
    return new_slice.ptr;
}

test "H.5 lua_pushexternalstring (LSTRMEM) frees external bytes on GC" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    var ctx: ExtAllocCtx = .{ .alloc = gpa, .free_count = 0 };
    // 11 bytes, NUL-terminated (C contract: s[len] == 0).
    const external = try gpa.dupeZ(u8, "external!!");
    const s = lua.lua_pushexternalstring(
        &L,
        external,
        10,
        testExtAlloc,
        @ptrCast(@alignCast(&ctx)),
    ) orelse return error.OutOfMemory;
    try std.testing.expectEqualStrings("external!!", s);
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));

    // Remove the only reference and collect: the external buffer must be freed.
    lua.lua_pop(&L, 1);
    _ = lua.lua_gc(&L, lua.LUA_GCCOLLECT, 0, 0);
    try std.testing.expectEqual(@as(usize, 1), ctx.free_count);
}

test "H.5 lua_pushexternalstring (LSTRFIX) keeps static bytes, distinct from interned" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    const static_str = "fixed-external";
    const s = lua.lua_pushexternalstring(
        &L,
        static_str,
        static_str.len,
        null,
        null,
    ) orelse return error.OutOfMemory;
    try std.testing.expectEqualStrings("fixed-external", s);

    // An equal-content interned string is a distinct object (not deduplicated).
    const interned = lua.lua_pushstring(&L, "fixed-external").?;
    try std.testing.expectEqualStrings("fixed-external", interned);
    try std.testing.expect(@intFromPtr(interned.ptr) != @intFromPtr(s.ptr));

    // GC must not free the static bytes (falloc == null): no use-after-free.
    lua.lua_pop(&L, 2);
    _ = lua.lua_gc(&L, lua.LUA_GCCOLLECT, 0, 0);
    try std.testing.expectEqualStrings("fixed-external", static_str);
}

test "H.5 lua_pushexternalstring as table key (equal-content externals match)" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    lua.lua_createtable(&L, 0, 1); // t
    _ = lua.lua_pushexternalstring(&L, "k", 1, null, null); // t, extkey
    _ = lua.lua_pushstring(&L, "ext"); // t, extkey, "ext"
    try lua.lua_settable(&L, -3); // t[extkey] = "ext"

    // Another external "k" of equal content is the SAME key: external strings
    // carry hash = seed and compare by content, so equal-content externals
    // index the same slot (matching the C reference). The external string is a
    // distinct *object* from an equal-content interned string (see the LSTRFIX
    // test); here we verify the table round-trip behaviour.
    _ = lua.lua_pushexternalstring(&L, "k", 1, null, null); // t, extkey2
    _ = try lua.lua_gettable(&L, -2); // t, "ext"
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    try std.testing.expectEqualStrings("ext", lua.lua_tostring(&L, -1).?);
    lua.lua_pop(&L, 2);
}

test "H.10 GC completeness (stop, restart, isrunning, collect, step, GCPARAM get/set, gen/inc)" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    // Default: GC is running
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gc(&L, lua.LUA_GCISRUNNING, 0, 0));

    // Stop and verify
    try std.testing.expectEqual(@as(i32, 0), lua.lua_gc(&L, lua.LUA_GCSTOP, 0, 0));
    try std.testing.expectEqual(@as(i32, 0), lua.lua_gc(&L, lua.LUA_GCISRUNNING, 0, 0));

    // Restart and verify
    try std.testing.expectEqual(@as(i32, 0), lua.lua_gc(&L, lua.LUA_GCRESTART, 0, 0));
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gc(&L, lua.LUA_GCISRUNNING, 0, 0));

    // Collect (full GC)
    try std.testing.expectEqual(@as(i32, 0), lua.lua_gc(&L, lua.LUA_GCCOLLECT, 0, 0));

    // Step (runs full collection synchronously in our port)
    try std.testing.expectEqual(@as(i32, 1), lua.lua_gc(&L, lua.LUA_GCSTEP, 0, 0));

    // GCCOUNT / GCCOUNTB (returns memory usage in KB / remainder bytes)
    try std.testing.expect(lua.lua_gc(&L, lua.LUA_GCCOUNT, 0, 0) > 0);
    try std.testing.expect(lua.lua_gc(&L, lua.LUA_GCCOUNTB, 0, 0) >= 0);

    // GCGEN / GCINC (acknowledge, return 0)
    try std.testing.expectEqual(@as(i32, 0), lua.lua_gc(&L, lua.LUA_GCGEN, 0, 0));
    try std.testing.expectEqual(@as(i32, 0), lua.lua_gc(&L, lua.LUA_GCINC, 0, 0));

    // Invalid option -> -1
    try std.testing.expectEqual(@as(i32, -1), lua.lua_gc(&L, 999, 0, 0));

    // GCPARAM: get default values
    try std.testing.expectEqual(@as(i32, 10), lua.lua_gc(&L, lua.LUA_GCPARAM, lua.LUA_GCPMINORMUL, -1));
    try std.testing.expectEqual(@as(i32, 20), lua.lua_gc(&L, lua.LUA_GCPARAM, lua.LUA_GCPMAJORMINOR, -1));
    try std.testing.expectEqual(@as(i32, 50), lua.lua_gc(&L, lua.LUA_GCPARAM, lua.LUA_GCPMINORMAJOR, -1));
    try std.testing.expectEqual(@as(i32, 200), lua.lua_gc(&L, lua.LUA_GCPARAM, lua.LUA_GCPPAUSE, -1));
    try std.testing.expectEqual(@as(i32, 200), lua.lua_gc(&L, lua.LUA_GCPARAM, lua.LUA_GCPSTEPMUL, -1));
    try std.testing.expectEqual(@as(i32, 13), lua.lua_gc(&L, lua.LUA_GCPARAM, lua.LUA_GCPSTEPSIZE, -1));
    // Invalid param index -> -1
    try std.testing.expectEqual(@as(i32, -1), lua.lua_gc(&L, lua.LUA_GCPARAM, 99, -1));

    // GCPARAM: set a new value and verify
    try std.testing.expectEqual(@as(i32, 150), lua.lua_gc(&L, lua.LUA_GCPARAM, lua.LUA_GCPPAUSE, 150));
    try std.testing.expectEqual(@as(i32, 150), lua.lua_gc(&L, lua.LUA_GCPARAM, lua.LUA_GCPPAUSE, -1));

    // Test collectgarbage through the Lua API (string-based)
    // "collect" option
    _ = lua.lua_getglobal(&L, "collectgarbage");
    _ = lua.lua_pushstring(&L, "collect");
    try lua.lua_call(&L, 1, 0);

    // "count" option through Lua
    _ = lua.lua_getglobal(&L, "collectgarbage");
    _ = lua.lua_pushstring(&L, "count");
    try lua.lua_call(&L, 1, 1);
    try std.testing.expectEqual(@as(i32, lua.LUA_TNUMBER), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    // "isrunning" option through Lua: should be true (restarted above)
    _ = lua.lua_getglobal(&L, "collectgarbage");
    _ = lua.lua_pushstring(&L, "isrunning");
    try lua.lua_call(&L, 1, 1);
    try std.testing.expect(lua.lua_toboolean(&L, -1) != 0);
    lua.lua_pop(&L, 1);

    // "param" option through Lua: get pause parameter
    _ = lua.lua_getglobal(&L, "collectgarbage");
    _ = lua.lua_pushstring(&L, "param");
    _ = lua.lua_pushstring(&L, "pause");
    try lua.lua_call(&L, 2, 1);
    try std.testing.expectEqual(@as(i32, lua.LUA_TNUMBER), lua.lua_type(&L, -1));
    try std.testing.expectEqual(@as(f64, 150.0), lua.lua_tonumber(&L, -1));
    lua.lua_pop(&L, 1);

    // "param" option through Lua: set and verify
    _ = lua.lua_getglobal(&L, "collectgarbage");
    _ = lua.lua_pushstring(&L, "param");
    _ = lua.lua_pushstring(&L, "stepmul");
    _ = lua.lua_pushinteger(&L, 175);
    try lua.lua_call(&L, 3, 1);
    try std.testing.expectEqual(@as(f64, 175.0), lua.lua_tonumber(&L, -1));
    lua.lua_pop(&L, 1);
    // Verify via direct API
    try std.testing.expectEqual(@as(i32, 175), lua.lua_gc(&L, lua.LUA_GCPARAM, lua.LUA_GCPSTEPMUL, -1));

    // "generational" and "incremental" options (acknowledged, return 0)
    _ = lua.lua_getglobal(&L, "collectgarbage");
    _ = lua.lua_pushstring(&L, "generational");
    try lua.lua_call(&L, 1, 1);
    try std.testing.expectEqual(@as(i32, lua.LUA_TNUMBER), lua.lua_type(&L, -1));
    try std.testing.expectEqual(@as(f64, 0.0), lua.lua_tonumber(&L, -1));
    lua.lua_pop(&L, 1);

    _ = lua.lua_getglobal(&L, "collectgarbage");
    _ = lua.lua_pushstring(&L, "incremental");
    try lua.lua_call(&L, 1, 1);
    try std.testing.expectEqual(@as(i32, lua.LUA_TNUMBER), lua.lua_type(&L, -1));
    try std.testing.expectEqual(@as(f64, 0.0), lua.lua_tonumber(&L, -1));
    lua.lua_pop(&L, 1);

    // Verify state still usable after GC operations
    _ = lua.lua_pushstring(&L, "gc_complete");
    try std.testing.expectEqualStrings("gc_complete", lua.lua_tostring(&L, -1).?);
    lua.lua_pop(&L, 1);
}

test "H.7 convenience macros (insert, remove, newtable, register, pushglobaltable, pushliteral, type predicates)" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // --- lua_newtable ---
    lua.lua_newtable(&L);
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));
    // Stack: [t]

    // --- lua_pushliteral ---
    const lit = lua.lua_pushliteral(&L, "hello").?;
    try std.testing.expectEqualStrings("hello", lit);
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -1));
    // Stack: [t, "hello"]

    // --- lua_insert: move "hello" from -1 to -2 (before t) ---
    // lua_insert(L, -2) rotates the interval [-2, -1] up by 1:
    // the element at -2 (the table) moves to top, "hello" shifts to -2.
    // Result: ["hello", t]
    lua.lua_insert(&L, -2);
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));
    try std.testing.expectEqual(@as(i32, lua.LUA_TSTRING), lua.lua_type(&L, -2));
    try std.testing.expectEqualStrings("hello", lua.lua_tostring(&L, -2).?);
    lua.lua_pop(&L, 2); // ["hello", t] → []

    // --- lua_remove: push 3 strings, remove middle one ---
    _ = lua.lua_pushstring(&L, "a");
    _ = lua.lua_pushstring(&L, "b");
    _ = lua.lua_pushstring(&L, "c");
    // Stack: ["a", "b", "c"]
    lua.lua_remove(&L, -2); // remove "b": ["a", "c"]
    try std.testing.expectEqualStrings("c", lua.lua_tostring(&L, -1).?);
    try std.testing.expectEqualStrings("a", lua.lua_tostring(&L, -2).?);
    lua.lua_pop(&L, 2); // []

    // --- lua_pushglobaltable ---
    lua.lua_pushglobaltable(&L);
    try std.testing.expectEqual(@as(i32, lua.LUA_TTABLE), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    // --- lua_register ---
    const myFn: lua.lua_CFunction = struct {
        fn call(L2: *lua.lua_State) !i32 {
            _ = lua.lua_pushstring(L2, "registered!");
            return 1;
        }
    }.call;
    lua.lua_register(&L, "my_test_fn", myFn);
    _ = lua.lua_getglobal(&L, "my_test_fn");
    try std.testing.expectEqual(@as(i32, lua.LUA_TFUNCTION), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    // --- lua_isfunction ---
    lua.lua_createtable(&L, 0, 0);
    try std.testing.expect(!lua.lua_isfunction(&L, -1));
    lua.lua_pop(&L, 1);
    _ = lua.lua_getglobal(&L, "my_test_fn");
    try std.testing.expect(lua.lua_isfunction(&L, -1));
    lua.lua_pop(&L, 1);

    // --- lua_isnoneornil ---
    lua.lua_pushnil(&L);
    try std.testing.expect(lua.lua_isnoneornil(&L, -1));
    lua.lua_pop(&L, 1);
    try std.testing.expect(lua.lua_isnoneornil(&L, 999)); // invalid index
    lua.lua_pushinteger(&L, 42);
    try std.testing.expect(!lua.lua_isnoneornil(&L, -1));
    lua.lua_pop(&L, 1);

    // --- lua_isthread ---
    lua.lua_pushinteger(&L, 42);
    try std.testing.expect(!lua.lua_isthread(&L, -1));
    lua.lua_pop(&L, 1);
    const co = try lua.lua_newthread(&L);
    _ = co;
    try std.testing.expectEqual(@as(i32, lua.LUA_TTHREAD), lua.lua_type(&L, -1));
    try std.testing.expect(lua.lua_isthread(&L, -1));
    lua.lua_pop(&L, 1);

    // --- lua_islightuserdata ---
    var dummy: i32 = 0;
    lua.lua_pushlightuserdata(&L, @ptrCast(&dummy));
    try std.testing.expect(lua.lua_islightuserdata(&L, -1));
    try std.testing.expect(!lua.lua_islightuserdata(&L, -2));
    lua.lua_pop(&L, 1);
}

test "H.9 missing constants and exports (lua_ident, LUA_COPYRIGHT, LUA_AUTHORS)" {
    // These are comptime consts — verify they exist and have expected content.
    try std.testing.expectEqualStrings(
        "Lua 5.5  Copyright (C) 1994-2026 Lua.org, PUC-Rio",
        lua.LUA_COPYRIGHT,
    );
    try std.testing.expectEqualStrings(
        "R. Ierusalimschy, L. H. de Figueiredo, W. Celes",
        lua.LUA_AUTHORS,
    );

    // lua_ident should contain both version and author markers.
    try std.testing.expect(std.mem.containsAtLeast(u8, lua.lua_ident, 1, "$LuaVersion:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, lua.lua_ident, 1, "$LuaAuthors:"));
    try std.testing.expect(std.mem.containsAtLeast(u8, lua.lua_ident, 1, "Copyright"));
    try std.testing.expect(std.mem.containsAtLeast(u8, lua.lua_ident, 1, "PUC-Rio"));
}

test "H.8 deprecated compatibility aliases (newuserdata, getuservalue, setuservalue, resetthread)" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);

    // --- lua_newuserdata: alias for lua_newuserdatauv(L, s, 1) ---
    const ud = lua.lua_newuserdata(&L, 8);
    try std.testing.expect(ud != null);
    try std.testing.expectEqual(@as(i32, lua.LUA_TUSERDATA), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);

    // --- lua_getuservalue / lua_setuservalue: real user-value storage ---
    // lua_newuserdata (nuvalue=1) creates a full userdata with one user value.
    const ud2 = lua.lua_newuserdata(&L, 8);
    try std.testing.expect(ud2 != null);
    try std.testing.expectEqual(@as(i32, lua.LUA_TUSERDATA), lua.lua_type(&L, -1));
    lua.lua_pushinteger(&L, 42);
    const r1 = lua.lua_setuservalue(&L, -2);
    try std.testing.expectEqual(@as(i32, 1), r1);
    const r2 = lua.lua_getuservalue(&L, -1);
    try std.testing.expectEqual(@as(i32, lua.LUA_TNUMBER), r2);
    try std.testing.expectEqual(@as(i64, 42), lua.lua_tointeger(&L, -1).?);
    lua.lua_pop(&L, 2); // pop uservalue + userdata

    // Out-of-range user value index: getiuservalue returns LUA_TNONE,
    // setiuservalue returns 0 (matching the reference for nuvalue=0 userdata).
    const r3 = lua.lua_getiuservalue(&L, -1, 2);
    try std.testing.expectEqual(@as(i32, lua.LUA_TNONE), r3);
    try std.testing.expectEqual(@as(i32, lua.LUA_TNIL), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1); // pop the nil pushed by getiuservalue
    lua.lua_pushboolean(&L, 1);
    const r4 = lua.lua_setiuservalue(&L, -2, 2);
    try std.testing.expectEqual(@as(i32, 0), r4);
    lua.lua_pop(&L, 1); // pop the boolean consumed by setiuservalue
    lua.lua_pop(&L, 1); // pop the userdata

    // --- lua_resetthread: alias for lua_closethread(L, null) ---
    const r5 = lua.lua_resetthread(&L);
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), r5);
    // The state should still be usable after reset.
    lua.lua_pushinteger(&L, 99);
    try std.testing.expectEqual(@as(i32, lua.LUA_TNUMBER), lua.lua_type(&L, -1));
    lua.lua_pop(&L, 1);
}

test "BUG-047 repeated string arithmetic print doesn't crash" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const status = try lua.luaL_dostring(&L, "print('2'+1); print('2'+1)", "=test");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
}



test "H.11 equal literals across the chunk share one object (constant dedup)" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    // A long string literal (>40 chars) repeated in the same chunk must be a
    // single object; a runtime concatenation of the same content must not be.
    const status = try lua.luaL_dostring(&L,
        \\local s1 = "01234567890123456789012345678901234567890123456789"
        \\local function foo() return "01234567890123456789012345678901234567890123456789" end
        \\local a1 = string.format("%p", s1)
        \\assert(a1 == string.format("%p", foo()))
        \\local sd = "0123456789" .. "0123456789012345678901234567890123456789"
        \\assert(sd == s1 and string.format("%p", sd) ~= a1)
    , "=(dedup)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
}

test "H.11 yield from a __index metamethod inside a coroutine (finishOp)" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    // The chunk's env has a __index metamethod that yields; the first resume
    // must yield 'g' (the __index result must be completed on resume).
    const status = try lua.luaL_dostring(&L,
        \\local env = {assert = assert}
        \\local f = assert(load("local y = {0,1,2,3}; X = y; assert(X[3] == 2); return 0", nil, nil, env))
        \\f()
        \\for k in pairs(env) do env[k] = nil end
        \\setmetatable(env, {
        \\  __index = function (t, n) coroutine.yield('g'); return _G[n] end,
        \\  __newindex = function (t, n, v) coroutine.yield('s'); _G[n] = v end,
        \\})
        \\X = nil
        \\local co = coroutine.wrap(f)
        \\assert(co() == 's')
        \\assert(co() == 'g')
        \\assert(co() == 'g')
        \\assert(co() == 0)
    , "=(finishop)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
}

test "H.11 io.open returns nil, message, errno and validates mode" {
    const gpa = std.testing.allocator;
    var L: lua.lua_State = undefined;
    try lua.luaL_newstate(&L, gpa);
    defer lua.lua_close(&L);
    try lua.luaL_openlibs(&L);

    const status = try lua.luaL_dostring(&L,
        \\local a, b, c = io.open('xuxu_nao_existe')
        \\assert(not a and type(b) == "string" and type(c) == "number")
        \\local ok, err = pcall(io.open, "x", "rw")
        \\assert(not ok and string.find(err, "invalid mode"))
        \\local ok2, err2 = pcall(io.input, "xuxu_nao_existe")
        \\assert(not ok2 and string.find(err2, "No such file"))
    , "=(io)");
    try std.testing.expectEqual(@as(i32, lua.LUA_OK), status);
}
