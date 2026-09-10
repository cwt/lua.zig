// $Id: ldebug.zig $
//! Debug introspection (port of ldebug.c) — moved from lua.zig (Refactor B1,
//! pure move; re-exported by lua.zig for callers).

const std = @import("std");
const lua = @import("lua.zig");
const lvm = @import("lvm.zig");

pub fn lua_getstack(L: *lua.lua_State, level: i32, ar: *lua.lua_Debug) i32 {
    if (level < 0) return 0;
    var ci: ?*lua.CallInfo = L.ci;
    var lvl = level;
    while (lvl > 0 and ci != null) {
        if (ci.? == &L.base_ci) break;
        ci = ci.?.previous;
        lvl -= 1;
    }
    if (lvl == 0 and ci != null and ci.? != &L.base_ci) {
        ar.i_ci = ci;
        return 1;
    }
    return 0;
}

pub fn lua_sethook(L: *lua.lua_State, func: ?lua.lua_Hook, mask: i32, count: i32) void {
    var actual_func = func;
    var actual_mask = mask;
    if (func == null or mask == 0) {
        actual_mask = 0;
        actual_func = null;
    }
    L.hook = actual_func;
    L.basehookcount = count;
    L.hookcount = count;
    L.hookmask = @intCast(actual_mask);
    L.oldpc = -1;
}

pub fn lua_gethook(L: *lua.lua_State) ?lua.lua_Hook {
    return L.hook;
}

pub fn lua_gethookmask(L: *lua.lua_State) i32 {
    return L.hookmask;
}

pub fn lua_gethookcount(L: *lua.lua_State) i32 {
    return L.basehookcount;
}

fn testAMode(op: lvm.OpCode) bool {
    return switch (op) {
        .MOVE, .LOADI, .LOADF, .LOADK, .LOADKX, .LOADFALSE, .LFALSESKIP, .LOADTRUE, .LOADNIL, .GETUPVAL, .GETTABUP, .GETTABLE, .GETI, .GETFIELD, .NEWTABLE, .SELF, .ADDI, .ADDK, .SUBK, .MULK, .MODK, .POWK, .DIVK, .IDIVK, .BANDK, .BORK, .BXORK, .SHLI, .SHRI, .ADD, .SUB, .MUL, .MOD, .POW, .DIV, .IDIV, .BAND, .BOR, .BXOR, .SHL, .SHR, .UNM, .BNOT, .NOT, .LEN, .CONCAT, .TESTSET, .CALL, .TAILCALL, .FORLOOP, .FORPREP, .TFORLOOP, .CLOSURE, .VARARG, .GETVARG => true,
        else => false,
    };
}

fn testMMMode(op: lvm.OpCode) bool {
    return switch (op) {
        .MMBIN, .MMBINI, .MMBINK => true,
        else => false,
    };
}

fn filterpc(pc: i32, jmptarget: i32) i32 {
    return if (pc < jmptarget) -1 else pc;
}

fn findsetreg(p: *const lua.lua_Proto, lastpc: i32, reg: i32) i32 {
    var pc: i32 = 0;
    var setreg: i32 = -1;
    var jmptarget: i32 = 0;
    var lpc = lastpc;
    if (lpc >= 0 and lpc < p.code.len) {
        if (testMMMode(lvm.GET_OPCODE(p.code[@intCast(lpc)]))) {
            lpc -= 1;
        }
    }
    while (pc < lpc) {
        const i = p.code[@intCast(pc)];
        const op = lvm.GET_OPCODE(i);
        const a = lvm.GETARG_A(i);
        var change = false;
        switch (op) {
            .LOADNIL => {
                const b = lvm.GETARG_B(i);
                change = (a <= reg and reg <= a + b);
            },
            .TFORCALL => {
                change = (reg >= a + 2);
            },
            .CALL, .TAILCALL => {
                change = (reg >= a);
            },
            .JMP => {
                const b = lvm.GETARG_sJ(i);
                const dest = pc + 1 + b;
                if (dest <= lpc and dest > jmptarget) {
                    jmptarget = dest;
                }
                change = false;
            },
            else => {
                change = (testAMode(op) and reg == a);
            },
        }
        if (change) {
            setreg = filterpc(pc, jmptarget);
        }
        pc += 1;
    }
    return setreg;
}

fn kname(p: *const lua.lua_Proto, index: usize, name: *?[]const u8) ?[]const u8 {
    if (index < p.k.len) {
        const kvalue = p.k[index];
        if (kvalue == .string) {
            if (kvalue.string) |ts| {
                name.* = ts.s;
                return "constant";
            }
        }
    }
    name.* = "?";
    return null;
}

pub fn upvalname(p: *const lua.lua_Proto, uv: usize) []const u8 {
    if (uv < p.upvalues.len) {
        if (p.upvalues[uv].name) |s| {
            return s.s;
        }
        if (uv == 0) return "_ENV";
    }
    return "?";
}

fn basicgetobjname(p: *const lua.lua_Proto, ppc: *i32, reg: i32, name: *?[]const u8) ?[]const u8 {
    var pc = ppc.*;
    if (luaF_getlocalname(p, reg + 1, pc)) |ln| {
        name.* = ln;
        return "local";
    }
    ppc.* = findsetreg(p, pc, reg);
    pc = ppc.*;
    if (pc != -1) {
        const i = p.code[@intCast(pc)];
        const op = lvm.GET_OPCODE(i);
        switch (op) {
            .MOVE => {
                const b = lvm.GETARG_B(i);
                if (b < lvm.GETARG_A(i)) {
                    return basicgetobjname(p, ppc, b, name);
                }
            },
            .GETUPVAL => {
                name.* = upvalname(p, @intCast(lvm.GETARG_B(i)));
                return "upvalue";
            },
            .LOADK => {
                return kname(p, @intCast(lvm.GETARG_Bx(i)), name);
            },
            .LOADKX => {
                const extra = p.code[@intCast(pc + 1)];
                return kname(p, @intCast(lvm.GETARG_Ax(extra)), name);
            },
            else => {},
        }
    }
    return null;
}

fn isEnv(p: *const lua.lua_Proto, pc: i32, i: lvm.Instruction, isup: bool) []const u8 {
    const t = lvm.GETARG_B(i);
    var name: ?[]const u8 = null;
    if (isup) {
        name = upvalname(p, @intCast(t));
    } else {
        var pc_copy = pc;
        const what = basicgetobjname(p, &pc_copy, t, &name);
        if (what == null or (!std.mem.eql(u8, what.?, "local") and !std.mem.eql(u8, what.?, "upvalue"))) {
            name = null;
        }
    }
    return if (name != null and std.mem.eql(u8, name.?, "_ENV")) "global" else "field";
}

fn rname(p: *const lua.lua_Proto, pc: i32, c: i32, name: *?[]const u8) void {
    var pc_copy = pc;
    const what = basicgetobjname(p, &pc_copy, c, name);
    if (what == null or what.?[0] != 'c') { // "constant" starts with 'c'
        name.* = "?";
    }
}

pub fn getobjname(p: *const lua.lua_Proto, lastpc: i32, reg: i32, name: *?[]const u8) ?[]const u8 {
    var lastpc_copy = lastpc;
    if (basicgetobjname(p, &lastpc_copy, reg, name)) |kind| {
        return kind;
    } else if (lastpc_copy != -1) {
        const i = p.code[@intCast(lastpc_copy)];
        const op = lvm.GET_OPCODE(i);
        switch (op) {
            .GETTABUP => {
                const k = lvm.GETARG_C(i);
                _ = kname(p, @intCast(k), name);
                return isEnv(p, lastpc_copy, i, true);
            },
            .GETTABLE, .GETVARG => {
                const k = lvm.GETARG_C(i);
                rname(p, lastpc_copy, k, name);
                return isEnv(p, lastpc_copy, i, false);
            },
            .GETI => {
                name.* = "integer index";
                return "field";
            },
            .GETFIELD => {
                const k = lvm.GETARG_C(i);
                _ = kname(p, @intCast(k), name);
                return isEnv(p, lastpc_copy, i, false);
            },
            .SELF => {
                const k = lvm.GETARG_C(i);
                _ = kname(p, @intCast(k), name);
                return "method";
            },
            else => {},
        }
    }
    return null;
}

fn funcnamefromcode(L: *lua.lua_State, p: *const lua.lua_Proto, pc: i32, name: *?[]const u8) ?[]const u8 {
    if (pc < 0 or pc >= p.code.len) {
        return null;
    }
    const i = p.code[@intCast(pc)];
    const op = lvm.GET_OPCODE(i);
    var tm: ?@import("ltm.zig").TMS = null;
    switch (op) {
        .CALL, .TAILCALL => {
            return getobjname(p, pc, lvm.GETARG_A(i), name);
        },
        .TFORCALL => {
            name.* = "for iterator";
            return "for iterator";
        },
        .SELF, .GETTABUP, .GETTABLE, .GETI, .GETFIELD => {
            tm = .INDEX;
        },
        .SETTABUP, .SETTABLE, .SETI, .SETFIELD => {
            tm = .NEWINDEX;
        },
        .MMBIN, .MMBINI, .MMBINK => {
            const tm_idx = lvm.GETARG_C(i);
            const TMS = @import("ltm.zig").TMS;
            if (tm_idx >= 0 and tm_idx < @typeInfo(TMS).@"enum".fields.len) {
                tm = @enumFromInt(tm_idx);
            }
        },
        .ADD, .ADDK, .ADDI => tm = .ADD,
        .SUB, .SUBK => tm = .SUB,
        .MUL, .MULK => tm = .MUL,
        .MOD, .MODK => tm = .MOD,
        .POW, .POWK => tm = .POW,
        .DIV, .DIVK => tm = .DIV,
        .IDIV, .IDIVK => tm = .IDIV,
        .BAND, .BANDK => tm = .BAND,
        .BOR, .BORK => tm = .BOR,
        .BXOR, .BXORK => tm = .BXOR,
        .SHL, .SHLI => tm = .SHL,
        .SHR, .SHRI => tm = .SHR,
        .UNM => tm = .UNM,
        .BNOT => tm = .BNOT,
        .LEN => tm = .LEN,
        .CONCAT => tm = .CONCAT,
        .EQ => tm = .EQ,
        .LT, .LTI, .GTI => tm = .LT,
        .LE, .LEI, .GEI => tm = .LE,
        .CLOSE, .RETURN => tm = .CLOSE,
        else => return null,
    }
    if (tm) |t| {
        const idx = @intFromEnum(t);
        if (L.l_G.?.tmname[idx]) |ts| {
            name.* = ts.s[2..];
            return "metamethod";
        }
    }
    return null;
}

pub fn funcnamefromcall(L: *lua.lua_State, ci: *lua.CallInfo, name: *?[]const u8) ?[]const u8 {
    if (ci.is_hooked) {
        name.* = "?";
        return "hook";
    }
    if (ci.is_fin) {
        name.* = "__gc";
        return "metamethod";
    }
    if (isLua(ci, L)) {
        const val = L.stack[ci.func];
        if (val == .function) {
            if (val.function) |cl| {
                if (cl.* == .lua) {
                    return funcnamefromcode(L, cl.lua.p, currentpc(ci), name);
                }
            }
        }
    }
    return null;
}

pub fn getfuncname(L: *lua.lua_State, ci: ?*lua.CallInfo, name: *?[]const u8) ?[]const u8 {
    // Mirror the reference: the name is looked up in the *calling* frame
    // (ci->previous); a hooked frame is reported via funcnamefromcall.
    if (ci) |c| {
        if (c.previous) |prev| {
            return funcnamefromcall(L, prev, name);
        }
    }
    return null;
}

pub fn isLua(ci: *lua.CallInfo, L: *lua.lua_State) bool {
    _ = L;
    return ci.is_lua;
}

pub fn currentpc(ci: *lua.CallInfo) i32 {
    if (ci.savedpc == 0) return 0;
    return @intCast(ci.savedpc - 1);
}

pub fn luaF_getlocalname(f: *const lua.lua_Proto, local_number: i32, pc: i32) ?[]const u8 {
    var lnum = local_number;
    for (f.locvars) |lv| {
        if (lv.startpc <= pc) {
            if (pc < lv.endpc) {
                lnum -= 1;
                if (lnum == 0) {
                    if (lv.varname) |ts| {
                        return ts.s;
                    }
                    return null;
                }
            }
        }
    }
    return null;
}

pub fn luaG_findlocal(L: *lua.lua_State, ci: *lua.CallInfo, n: i32, pos: *?usize) ?[]const u8 {
    const base = ci.base;
    var name: ?[]const u8 = null;
    const is_lua = isLua(ci, L);
    if (is_lua) {
        if (n < 0) {
            const nextra = ci.nextraargs;
            if (-n <= nextra) {
                const un = @as(usize, @intCast(-n));
                pos.* = ci.func - @as(usize, @intCast(nextra)) + (un - 1);
                return "(vararg)";
            }
            return null;
        } else {
            const val = L.stack[ci.func];
            if (val == .function) {
                if (val.function) |cl| {
                    if (cl.* == .lua) {
                        name = luaF_getlocalname(cl.lua.p, n, currentpc(ci));
                    }
                }
            }
        }
    }
    if (name == null) {
        // Mirror the reference: for the current frame the limit is L->top;
        // for an older frame it is the next frame's function position.
        const limit = if (ci == L.ci) L.top else (if (ci.next) |next| next.func else L.top);
        const un = @as(usize, @intCast(n));
        if (n > 0 and limit >= base + un) {
            name = if (is_lua) "(temporary)" else "(C temporary)";
        } else {
            return null;
        }
    }
    pos.* = base + @as(usize, @intCast(n - 1));
    return name;
}

pub fn lua_getlocal(L: *lua.lua_State, ar: ?*const lua.lua_Debug, n: i32) ?[]const u8 {
    var name: ?[]const u8 = null;
    if (ar == null) {
        if (L.top > 0) {
            const val = L.stack[L.top - 1];
            if (val == .function) {
                if (val.function) |cl| {
                    if (cl.* == .lua) {
                        name = luaF_getlocalname(cl.lua.p, n, 0);
                    }
                }
            }
        }
    } else {
        const ci = ar.?.i_ci orelse return null;
        var pos: ?usize = null;
        name = luaG_findlocal(L, ci, n, &pos);
        if (name != null and pos != null) {
            L.stack[L.top] = L.stack[pos.?];
            L.top += 1;
        }
    }
    return name;
}

pub fn lua_setlocal(L: *lua.lua_State, ar: ?*const lua.lua_Debug, n: i32) ?[]const u8 {
    if (L.top == 0) return null;
    const ci = ar.?.i_ci orelse return null;
    var pos: ?usize = null;
    const name = luaG_findlocal(L, ci, n, &pos);
    if (name != null and pos != null) {
        L.stack[pos.?] = L.stack[L.top - 1];
        L.top -= 1;
    }
    return name;
}

pub fn luaO_chunkid(out: *[lua.LUA_IDSIZE]u8, source: []const u8) void {
    const bufflen = lua.LUA_IDSIZE;
    @memset(out, 0);

    if (source.len > 0 and source[0] == '=') {
        const src = source[1..];
        const len = @min(src.len, bufflen - 1);
        @memcpy(out[0..len], src[0..len]);
    } else if (source.len > 0 and source[0] == '@') {
        const src = source[1..];
        if (src.len < bufflen) {
            @memcpy(out[0..src.len], src);
        } else {
            const RETS = "...";
            const rets_len = RETS.len;
            @memcpy(out[0..rets_len], RETS);
            const remaining = bufflen - rets_len - 1;
            const start = src.len - remaining;
            @memcpy(out[rets_len .. rets_len + remaining], src[start..]);
        }
    } else {
        const PRE = "[string \"";
        const POS = "\"]";
        const RETS = "...";

        var nl_idx: ?usize = null;
        for (source, 0..) |c, idx| {
            if (c == '\n') {
                nl_idx = idx;
                break;
            }
        }

        const reserved = PRE.len + RETS.len + POS.len + 1;
        const limit = if (bufflen > reserved) bufflen - reserved else 0;

        var write_idx: usize = 0;
        @memcpy(out[write_idx .. write_idx + PRE.len], PRE);
        write_idx += PRE.len;

        var srclen = source.len;
        if (nl_idx) |idx| {
            srclen = idx;
        }

        if (srclen <= limit and nl_idx == null) {
            @memcpy(out[write_idx .. write_idx + srclen], source[0..srclen]);
            write_idx += srclen;
        } else {
            const len = @min(srclen, limit);
            @memcpy(out[write_idx .. write_idx + len], source[0..len]);
            write_idx += len;
            @memcpy(out[write_idx .. write_idx + RETS.len], RETS);
            write_idx += RETS.len;
        }
        @memcpy(out[write_idx .. write_idx + POS.len], POS);
    }
}

fn funcinfo(ar: *lua.lua_Debug, cl: *lua.lua_Closure) void {
    switch (cl.*) {
        .c => {
            ar.source = "=[C]";
            ar.srclen = "=[C]".len;
            ar.linedefined = -1;
            ar.lastlinedefined = -1;
            ar.what = "C";
        },
        .lua => |lcl| {
            const p = lcl.p;
            if (p.source) |src_ts| {
                ar.source = src_ts.s;
                ar.srclen = ar.source.?.len;
            } else {
                ar.source = "=?";
                ar.srclen = "=?".len;
            }
            ar.linedefined = p.lineDefined;
            ar.lastlinedefined = p.lastLineDefined;
            ar.what = if (ar.linedefined == 0) "main" else "Lua";
        },
    }
    if (ar.source) |src| {
        luaO_chunkid(&ar.short_src, src);
    } else {
        luaO_chunkid(&ar.short_src, "=*");
    }
}

fn getcurrentline(ci: *lua.CallInfo, L: *lua.lua_State) i32 {
    const val = L.stack[ci.func];
    if (val == .function) {
        if (val.function) |cl| {
            if (cl.* == .lua) {
                return luaG_getfuncline(cl.lua.p, currentpc(ci));
            }
        }
    }
    return -1;
}

pub fn luaG_getfuncline(f: *const lua.lua_Proto, pc: i32) i32 {
    if (f.lineinfo.len == 0) {
        return -1;
    } else {
        var basepc: i32 = undefined;
        var baseline = getbaseline(f, pc, &basepc);
        basepc += 1;
        while (basepc <= pc) {
            if (basepc >= 0 and @as(usize, @intCast(basepc)) < f.lineinfo.len) {
                baseline += @as(i32, f.lineinfo[@as(usize, @intCast(basepc))]);
            }
            basepc += 1;
        }
        return baseline;
    }
}

fn getbaseline(f: *const lua.lua_Proto, pc: i32, basepc: *i32) i32 {
    const sizeabs = f.abslineinfo.len;
    if (sizeabs == 0 or pc < f.abslineinfo[0].pc) {
        basepc.* = -1;
        return f.lineDefined;
    } else {
        var i = @divTrunc(pc, 128) - 1;
        if (i < 0) {
            i = 0;
        } else if (i >= sizeabs) {
            i = @intCast(sizeabs - 1);
        }
        while (i + 1 < sizeabs and pc >= f.abslineinfo[@intCast(i + 1)].pc) {
            i += 1;
        }
        basepc.* = f.abslineinfo[@intCast(i)].pc;
        return f.abslineinfo[@intCast(i)].line;
    }
}

fn collectvalidlines(L: *lua.lua_State, cl: *lua.lua_Closure) !void {
    switch (cl.*) {
        .c => {
            L.stack[L.top] = .{ .nil = {} };
            L.top += 1;
        },
        .lua => |lcl| {
            const p = lcl.p;
            lua.lua_createtable(L, 0, 0);
            if (p.lineinfo.len > 0) {
                var currentline = p.lineDefined;
                var i: usize = 0;
                if (p.isVarArg) {
                    currentline = nextline(p, currentline, 0);
                    i = 1;
                }
                while (i < p.lineinfo.len) {
                    currentline = nextline(p, currentline, @intCast(i));
                    lua.lua_pushboolean(L, 1);
                    try lua.lua_rawseti(L, -2, currentline);
                    i += 1;
                }
            }
        },
    }
}

fn nextline(p: *const lua.lua_Proto, currentline: i32, pc: i32) i32 {
    if (pc < p.lineinfo.len) {
        if (p.lineinfo[@intCast(pc)] != -128) {
            return currentline + p.lineinfo[@intCast(pc)];
        } else {
            return luaG_getfuncline(p, pc);
        }
    }
    return currentline;
}

pub fn lua_getinfo(L: *lua.lua_State, what: []const u8, ar: *lua.lua_Debug) !i32 {
    var status: i32 = 1;
    var ci = ar.i_ci;
    var func_val: lua.TValue = undefined;
    var what_str = what;

    if (what_str.len > 0 and what_str[0] == '>') {
        ci = null;
        if (L.top == 0) return 0;
        func_val = L.stack[L.top - 1];
        L.top -= 1;
        what_str = what_str[1..];
    } else {
        if (ci) |c| {
            func_val = L.stack[c.func];
        } else {
            return 0;
        }
    }

    if (func_val != .function) return 0;
    const cl = func_val.function orelse return 0;

    for (what_str) |c| {
        switch (c) {
            'S' => {
                funcinfo(ar, cl);
            },
            'l' => {
                ar.currentline = if (ci != null and isLua(ci.?, L)) getcurrentline(ci.?, L) else -1;
            },
            'u' => {
                switch (cl.*) {
                    .c => |ccl| {
                        ar.nups = @intCast(ccl.upvals.len);
                        ar.isvararg = true;
                        ar.nparams = 0;
                    },
                    .lua => |lcl| {
                        ar.nups = @intCast(lcl.upvals.len);
                        ar.isvararg = lcl.p.isVarArg;
                        ar.nparams = lcl.p.numParams;
                    },
                }
            },
            't' => {
                ar.istailcall = if (ci) |info_ci| info_ci.is_tailcall else false;
                ar.extraargs = if (ci) |info_ci| @intCast(@max(0, info_ci.nextraargs)) else 0;
            },
            'n' => {
                var name_opt: ?[]const u8 = null;
                ar.namewhat = getfuncname(L, ci, &name_opt);
                if (ar.namewhat) |_| {
                    ar.name = name_opt;
                } else {
                    ar.namewhat = "";
                    ar.name = null;
                }
            },
            'r' => {
                if (ci == null or !ci.?.is_hooked) {
                    ar.ftransfer = 0;
                    ar.ntransfer = 0;
                } else {
                    ar.ftransfer = L.transferinfo.ftransfer;
                    ar.ntransfer = L.transferinfo.ntransfer;
                }
            },
            'L', 'f' => {},
            else => {
                status = 0;
            },
        }
    }

    var i: usize = 0;
    while (i < what_str.len) : (i += 1) {
        const c = what_str[i];
        if (c == 'f') {
            L.stack[L.top] = func_val;
            L.top += 1;
        } else if (c == 'L') {
            try collectvalidlines(L, cl);
        }
    }

    return status;
}
