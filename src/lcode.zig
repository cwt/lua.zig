// $Id: lcode.zig $
// Code generator for Lua.zig (Zig port of Lua 5.5.0 lcode.c)
// See Copyright Notice in lua.zig

const std = @import("std");
const lua = @import("lua.zig");
const lvm = @import("lvm.zig");
const llex = @import("llex.zig");
const lparser = @import("lparser.zig");
const ltm = @import("ltm.zig");

const Instruction = lvm.Instruction;
const FuncState = lparser.FuncState;
const expdesc = lparser.expdesc;
const ExpKind = lparser.ExpKind;

pub const NO_JUMP: i32 = -1;

fn hasjumps(e: *const expdesc) bool {
    return e.t != e.f;
}

// -------------------------------------------------------------------
// semantic error
// -------------------------------------------------------------------
pub fn luaK_semerror(ls: *llex.LexState, msg: []const u8) !void {
    ls.t.token = 0; // remove "near <token>" from final message
    ls.linenumber = ls.lastline; // back to line of last used token
    return llex.luaX_syntaxerror(ls, msg);
}

fn tonumeral(e: *const expdesc, v: *lua.TValue) bool {
    if (hasjumps(e)) return false;
    switch (e.k) {
        .VKINT => {
            v.* = .{ .number = @floatFromInt(e.u.ival) };
            return true;
        },
        .VKFLT => {
            v.* = .{ .number = e.u.nval };
            return true;
        },
        else => return false,
    }
}

fn const2val(fs: *FuncState, e: *const expdesc) *lua.TValue {
    std.debug.assert(e.k == .VCONST);
    return &fs.ls.dyd.actvar.items[@as(usize, @intCast(e.u.info))].val;
}

fn exp2const(fs: *FuncState, e: *const expdesc, v: *lua.TValue) bool {
    if (hasjumps(e)) return false;
    switch (e.k) {
        .VFALSE => {
            v.* = .{ .boolean = false };
            return true;
        },
        .VTRUE => {
            v.* = .{ .boolean = true };
            return true;
        },
        .VNIL => {
            v.* = .{ .nil = {} };
            return true;
        },
        .VKSTR => {
            v.* = .{ .string = e.u.strval };
            return true;
        },
        .VCONST => {
            v.* = const2val(fs, e).*;
            return true;
        },
        else => return tonumeral(e, v),
    }
}

fn previousinstruction(fs: *FuncState) ?*Instruction {
    if (fs.code.items.len > 0 and fs.code.items.len > @as(usize, @intCast(fs.lasttarget)))
        return &fs.code.items[fs.code.items.len - 1];
    return null;
}

pub fn luaK_nil(fs: *FuncState, from: i32, n: i32) void {
    const l = from + n - 1;
    const previous = previousinstruction(fs);
    if (previous) |pi| {
        if (lvm.GET_OPCODE(pi.*) == .LOADNIL) {
            const pfrom = lvm.GETARG_A(pi.*);
            const pl = pfrom + lvm.GETARG_B(pi.*);
            if ((pfrom <= from and from <= pl + 1) or
                (from <= pfrom and pfrom <= l + 1))
            {
                const nf = if (pfrom < from) pfrom else from;
                const nl = if (pl > l) pl else l;
                lvm.SETARG_A(pi, nf);
                lvm.SETARG_B(pi, nl - nf);
                return;
            }
        }
    }
    _ = luaK_codeABC(fs, .LOADNIL, from, n - 1, 0);
}

fn getjump(fs: *FuncState, pc: i32) i32 {
    if (pc < 0) {
        return NO_JUMP;
    }
    const offset = lvm.GETARG_sJ(fs.code.items[@as(usize, @intCast(pc))]);
    if (offset == NO_JUMP) return NO_JUMP;
    return (pc + 1) + offset;
}

fn fixjump(fs: *FuncState, pc: i32, dest: i32) void {
    const jmp = &fs.code.items[@as(usize, @intCast(pc))];
    const offset = dest - (pc + 1);
    if (!((-lvm.OFFSET_sJ <= offset) and (offset <= lvm.MAXARG_sJ - lvm.OFFSET_sJ))) {
        _ = llex.luaX_syntaxerror(fs.ls, "control structure too long") catch {};
        return;
    }
    std.debug.assert(lvm.GET_OPCODE(jmp.*) == .JMP);
    lvm.SETARG_sJ(jmp, offset);
}

pub fn luaK_concat(fs: *FuncState, l1: *i32, l2: i32) void {
    if (l2 == NO_JUMP) return;
    if (l1.* == NO_JUMP) {
        l1.* = l2;
    } else {
        var list = l1.*;
        while (true) {
            const next = getjump(fs, list);
            if (next == NO_JUMP) break;
            list = next;
        }
        fixjump(fs, list, l2);
    }
}

pub fn luaK_jump(fs: *FuncState) i32 {
    return codesJ(fs, .JMP, NO_JUMP, 0);
}

pub fn luaK_ret(fs: *FuncState, first: i32, nret: i32) !void {
    const op: lvm.OpCode = switch (nret) {
        0 => .RETURN0,
        1 => .RETURN1,
        else => .RETURN,
    };
    try lparser.luaY_checklimit(fs, nret + 1, lvm.MAXARG_B, "returns");
    const b = @min(nret + 1, lvm.MAXARG_B);
    _ = luaK_codeABC(fs, op, first, b, 0);
}

fn condjump(fs: *FuncState, op: lvm.OpCode, a: i32, b: i32, c: i32, k: i32) i32 {
    _ = luaK_codeABCk(fs, op, a, b, c, k);
    return luaK_jump(fs);
}

pub fn luaK_getlabel(fs: *FuncState) i32 {
    fs.lasttarget = @intCast(fs.code.items.len);
    return @intCast(fs.code.items.len);
}

fn getjumpcontrol(fs: *FuncState, pc: i32) *Instruction {
    const idx: usize = @intCast(pc);
    if (pc >= 1 and lvm.testTMode(lvm.GET_OPCODE(fs.code.items[idx - 1]))) {
        return &fs.code.items[idx - 1];
    }
    return &fs.code.items[idx];
}

fn patchtestreg(fs: *FuncState, node: i32, reg: i32) i32 {
    const i = getjumpcontrol(fs, node);
    if (lvm.GET_OPCODE(i.*) != .TESTSET) return 0;
    if (reg != lvm.NO_REG and reg != lvm.GETARG_B(i.*)) {
        lvm.SETARG_A(i, reg);
    } else {
        i.* = lvm.CREATE_ABCk(.TEST, lvm.GETARG_B(i.*), 0, 0, lvm.GETARG_k(i.*));
    }
    return 1;
}

fn removevalues(fs: *FuncState, list: i32) void {
    var l = list;
    while (l != NO_JUMP) : (l = getjump(fs, l)) {
        _ = patchtestreg(fs, l, lvm.NO_REG);
    }
}

fn patchlistaux(fs: *FuncState, list: i32, vtarget: i32, reg: i32, dtarget: i32) void {
    var l = list;
    while (l != NO_JUMP) {
        const next = getjump(fs, l);
        if (patchtestreg(fs, l, reg) != 0)
            fixjump(fs, l, vtarget)
        else
            fixjump(fs, l, dtarget);
        l = next;
    }
}

pub fn luaK_patchlist(fs: *FuncState, list: i32, target: i32) void {
    std.debug.assert(target <= @as(i32, @intCast(fs.code.items.len)));
    patchlistaux(fs, list, target, lvm.NO_REG, target);
}

pub fn luaK_patchtohere(fs: *FuncState, list: i32) void {
    const hr = luaK_getlabel(fs);
    luaK_patchlist(fs, list, hr);
}

fn savelineinfo(fs: *FuncState, line: i32) !void {
    const linedif = line - fs.previousline;
    const pc = fs.code.items.len - 1;
    // f->lineinfo is 1:1 with instructions, indexed by pc. When called
    // from luaK_code the lineinfo vector is one short (instruction just
    // appended), so we grow it; when called from luaK_fixline it already
    // holds an entry for this pc, so we overwrite in place.
    if (fs.lineinfo.items.len <= pc) {
        try fs.lineinfo.append(fs.ls.allocator, 0);
    }
    if (@abs(linedif) >= lvm.LIMLINEDIFF or fs.iwthabs >= lvm.MAXIWTHABS) {
        try fs.abslineinfo.append(fs.ls.allocator, .{ .pc = @intCast(pc), .line = line });
        fs.nabslineinfo += 1;
        fs.lineinfo.items[pc] = @truncate(lvm.ABSLINEINFO);
        fs.previousline = line;
        fs.iwthabs = 1;
    } else {
        fs.lineinfo.items[pc] = @truncate(linedif);
        fs.previousline = line;
        fs.iwthabs += 1;
    }
}

fn removelastlineinfo(fs: *FuncState) void {
    const pc = fs.code.items.len - 1;
    // Mirrors the reference: adjust counters (and drop the absolute
    // abslineinfo entry if present) but do NOT shrink the lineinfo array
    // -- luaK_fixline's subsequent savelineinfo overwrites the slot in
    // place. Only removelastinstruction pops the lineinfo vector.
    if (pc < fs.lineinfo.items.len and fs.lineinfo.items[pc] == lvm.ABSLINEINFO) {
        fs.nabslineinfo -= 1;
        fs.iwthabs = lvm.MAXIWTHABS + 1;
        _ = fs.abslineinfo.pop();
    } else {
        fs.previousline -= fs.lineinfo.items[pc];
        fs.iwthabs -= 1;
    }
}

fn removelastinstruction(fs: *FuncState) void {
    removelastlineinfo(fs);
    _ = fs.code.pop();
    _ = fs.lineinfo.pop();
}

pub fn luaK_code(fs: *FuncState, i: Instruction) !i32 {
    try fs.code.append(fs.ls.allocator, i);
    try savelineinfo(fs, fs.ls.lastline);
    return @intCast(fs.code.items.len - 1);
}

pub fn luaK_codeABCk(fs: *FuncState, o: lvm.OpCode, a: i32, b: i32, c: i32, k: i32) i32 {
    std.debug.assert(a <= lvm.MAXARG_A and b <= lvm.MAXARG_B and
        c <= lvm.MAXARG_C and (k & ~@as(i32, 1)) == 0);
    return luaK_code(fs, lvm.CREATE_ABCk(o, a, b, c, k)) catch 0;
}

pub fn luaK_codevABCk(fs: *FuncState, o: lvm.OpCode, a: i32, b: i32, c: i32, k: i32) i32 {
    std.debug.assert(a <= lvm.MAXARG_A and b <= lvm.MAXARG_vB and
        c <= lvm.MAXARG_vC and (k & ~@as(i32, 1)) == 0);
    return luaK_code(fs, lvm.CREATE_vABCk(o, a, b, c, k)) catch 0;
}

pub fn luaK_codeABx(fs: *FuncState, o: lvm.OpCode, a: i32, bx: i32) i32 {
    std.debug.assert(a <= lvm.MAXARG_A and bx <= lvm.MAXARG_Bx);
    return luaK_code(fs, lvm.CREATE_ABx(o, a, bx)) catch 0;
}

fn codeAsBx(fs: *FuncState, o: lvm.OpCode, a: i32, bx: i32) i32 {
    const b = bx + lvm.OFFSET_sBx;
    std.debug.assert(b <= lvm.MAXARG_Bx);
    return luaK_code(fs, lvm.CREATE_ABx(o, a, b)) catch 0;
}

fn codesJ(fs: *FuncState, o: lvm.OpCode, sj: i32, k: i32) i32 {
    std.debug.assert(sj + lvm.OFFSET_sJ <= lvm.MAXARG_sJ and (k & ~@as(i32, 1)) == 0);
    return luaK_code(fs, lvm.CREATE_sJ(o, sj, k)) catch 0;
}

fn codeextraarg(fs: *FuncState, a: i32) i32 {
    std.debug.assert(a <= lvm.MAXARG_Ax);
    return luaK_code(fs, lvm.CREATE_Ax(.EXTRAARG, a)) catch 0;
}

fn luaK_codek(fs: *FuncState, reg: i32, k: i32) i32 {
    if (k <= lvm.MAXARG_Bx)
        return luaK_codeABx(fs, .LOADK, reg, k);
    _ = luaK_codeABx(fs, .LOADKX, reg, 0);
    _ = codeextraarg(fs, k);
    return 1;
}

pub fn luaK_checkstack(fs: *FuncState, n: i32) !void {
    const newstack = fs.freereg + n;
    if (newstack > fs.f.maxStackSize) {
        try lparser.luaY_checklimit(fs, newstack, lvm.MAX_FSTACK, "registers");
        fs.f.maxStackSize = @truncate(@as(usize, @intCast(newstack)));
    }
}

pub fn luaK_reserveregs(fs: *FuncState, n: i32) !void {
    try luaK_checkstack(fs, n);
    fs.freereg = @intCast(@as(i32, fs.freereg) + n);
}

fn freereg(fs: *FuncState, reg: i32) void {
    if (reg >= lparser.luaY_nvarstack(fs)) {
        fs.freereg -= 1;
        std.debug.assert(reg == fs.freereg);
    }
}

fn freeregs(fs: *FuncState, r1: i32, r2: i32) void {
    if (r1 > r2) {
        freereg(fs, r1);
        freereg(fs, r2);
    } else {
        freereg(fs, r2);
        freereg(fs, r1);
    }
}

fn freeexp(fs: *FuncState, e: *expdesc) void {
    if (e.k == .VNONRELOC) freereg(fs, e.u.info);
}

fn freeexps(fs: *FuncState, e1: *expdesc, e2: *expdesc) void {
    const r1 = if (e1.k == .VNONRELOC) e1.u.info else -1;
    const r2 = if (e2.k == .VNONRELOC) e2.u.info else -1;
    freeregs(fs, r1, r2);
}

fn addk(fs: *FuncState, v: lua.TValue) !i32 {
    const k = fs.k.items.len;
    try fs.k.append(fs.ls.allocator, v);
    return @intCast(k);
}

fn stringK(fs: *FuncState, s: ?*lua.lua_TString) !i32 {
    return try addk(fs, .{ .string = s });
}

fn intK(fs: *FuncState, n: i64) !i32 {
    return try addk(fs, .{ .integer = n });
}

fn numberK(fs: *FuncState, r: f64) !i32 {
    return try addk(fs, .{ .number = r });
}

fn boolF(fs: *FuncState) !i32 {
    return try addk(fs, .{ .boolean = false });
}

fn boolT(fs: *FuncState) !i32 {
    return try addk(fs, .{ .boolean = true });
}

fn nilK(fs: *FuncState) !i32 {
    return try addk(fs, .{ .nil = {} });
}

fn fitsC(i: i64) bool {
    return (i >= -@as(i64, lvm.OFFSET_sC) and i <= @as(i64, lvm.MAXARG_C) - lvm.OFFSET_sC);
}

fn fitsBx(i: i64) bool {
    return (-lvm.OFFSET_sBx <= i and i <= lvm.MAXARG_Bx - lvm.OFFSET_sBx);
}

fn int2sC(i: i32) i32 {
    return i + lvm.OFFSET_sC;
}

pub fn luaK_int(fs: *FuncState, reg: i32, i: i64) void {
    if (fitsBx(i))
        _ = codeAsBx(fs, .LOADI, reg, @intCast(i))
    else
        _ = luaK_codek(fs, reg, intK(fs, i) catch 0);
}

fn luaK_float(fs: *FuncState, reg: i32, f: f64) void {
    var fi: i64 = 0;
    if (flttointeger(f, &fi) and fitsBx(fi))
        _ = codeAsBx(fs, .LOADF, reg, @intCast(fi))
    else
        _ = luaK_codek(fs, reg, numberK(fs, f) catch 0);
}

fn const2exp(v: *lua.TValue, e: *expdesc) void {
    e.t = NO_JUMP;
    e.f = NO_JUMP;
    switch (v.*) {
        .number => |n| {
            var iv: i64 = 0;
            if (flttointeger(n, &iv)) {
                e.k = .VKINT;
                e.u = .{ .ival = iv };
            } else {
                e.k = .VKFLT;
                e.u = .{ .nval = n };
            }
        },
        .boolean => |b| {
            e.k = if (b) .VTRUE else .VFALSE;
        },
        .nil => {
            e.k = .VNIL;
        },
        .string => |s| {
            e.k = .VKSTR;
            e.u = .{ .strval = s };
        },
        else => std.debug.assert(false),
    }
}

pub fn luaK_setreturns(fs: *FuncState, e: *expdesc, nresults: i32) !void {
    const pc = &fs.code.items[@as(usize, @intCast(e.u.info))];
    _ = lparser.luaY_checklimit(fs, nresults + 1, lvm.MAXARG_C, "multiple results") catch {};
    const c = @min(nresults + 1, lvm.MAXARG_C);
    if (e.k == .VCALL) {
        lvm.SETARG_C(pc, c);
    } else {
        std.debug.assert(e.k == .VVARARG);
        lvm.SETARG_C(pc, c);
        lvm.SETARG_A(pc, fs.freereg);
        try luaK_reserveregs(fs, 1);
    }
}

fn str2K(fs: *FuncState, e: *expdesc) i32 {
    std.debug.assert(e.k == .VKSTR);
    const s = e.u.strval;
    e.u = .{ .info = stringK(fs, s) catch 0 };
    e.k = .VK;
    return e.u.info;
}

pub fn luaK_setoneret(fs: *FuncState, e: *expdesc) !void {
    if (e.k == .VCALL) {
        std.debug.assert(lvm.GETARG_C(fs.code.items[@as(usize, @intCast(e.u.info))]) == 2);
        e.k = .VNONRELOC;
        e.u = .{ .info = lvm.GETARG_A(fs.code.items[@as(usize, @intCast(e.u.info))]) };
    } else if (e.k == .VVARARG) {
        lvm.SETARG_C(&fs.code.items[@as(usize, @intCast(e.u.info))], 2);
        e.k = .VRELOC;
    }
}

pub fn luaK_vapar2local(fs: *FuncState, vp: *expdesc) void {
    lparser.needvatab(fs.f);
    vp.k = .VLOCAL;
}

pub fn luaK_dischargevars(fs: *FuncState, e: *expdesc) void {
    switch (e.k) {
        .VCONST => {
            var tmp: expdesc = undefined;
            const2exp(const2val(fs, e), &tmp);
            e.* = tmp;
        },
        .VVARGVAR => {
            luaK_vapar2local(fs, e);
            const temp = e.u.uv.ridx;
            e.u = .{ .info = temp };
            e.k = .VNONRELOC;
        },
        .VLOCAL => {
            const temp = e.u.uv.ridx;
            e.u = .{ .info = temp };
            e.k = .VNONRELOC;
        },
        .VUPVAL => {
            const info = e.u.info;
            e.u = .{ .info = luaK_codeABC(fs, .GETUPVAL, 0, info, 0) };
            e.k = .VRELOC;
        },
        .VINDEXUP => {
            const t = e.u.ind.t;
            const idx = e.u.ind.idx;
            e.u = .{ .info = luaK_codeABC(fs, .GETTABUP, 0, t, idx) };
            e.k = .VRELOC;
        },
        .VINDEXI => {
            const t = e.u.ind.t;
            const idx = e.u.ind.idx;
            freereg(fs, t);
            e.u = .{ .info = luaK_codeABC(fs, .GETI, 0, t, idx) };
            e.k = .VRELOC;
        },
        .VINDEXSTR => {
            const t = e.u.ind.t;
            const idx = e.u.ind.idx;
            freereg(fs, t);
            e.u = .{ .info = luaK_codeABC(fs, .GETFIELD, 0, t, idx) };
            e.k = .VRELOC;
        },
        .VINDEXED => {
            const t = e.u.ind.t;
            const idx = e.u.ind.idx;
            freeregs(fs, t, idx);
            e.u = .{ .info = luaK_codeABC(fs, .GETTABLE, 0, t, idx) };
            e.k = .VRELOC;
        },
        .VVARGIND => {
            const t = e.u.ind.t;
            const idx = e.u.ind.idx;
            freeregs(fs, t, idx);
            e.u = .{ .info = luaK_codeABC(fs, .GETVARG, 0, t, idx) };
            e.k = .VRELOC;
        },
        .VVARARG, .VCALL => {
            try luaK_setoneret(fs, e);
        },
        else => {},
    }
}

fn discharge2reg(fs: *FuncState, e: *expdesc, reg: i32) void {
    luaK_dischargevars(fs, e);
    switch (e.k) {
        .VNIL => luaK_nil(fs, reg, 1),
        .VFALSE => _ = luaK_codeABC(fs, .LOADFALSE, reg, 0, 0),
        .VTRUE => _ = luaK_codeABC(fs, .LOADTRUE, reg, 0, 0),
        .VKSTR => {
            _ = str2K(fs, e);
            _ = luaK_codek(fs, reg, e.u.info);
        },
        .VK => _ = luaK_codek(fs, reg, e.u.info),
        .VKFLT => luaK_float(fs, reg, e.u.nval),
        .VKINT => luaK_int(fs, reg, e.u.ival),
        .VRELOC => {
            const pc = &fs.code.items[@as(usize, @intCast(e.u.info))];
            lvm.SETARG_A(pc, reg);
        },
        .VNONRELOC => {
            if (reg != e.u.info)
                _ = luaK_codeABC(fs, .MOVE, reg, e.u.info, 0);
        },
        else => {
            std.debug.assert(e.k == .VJMP);
            return;
        },
    }
    e.u = .{ .info = reg };
    e.k = .VNONRELOC;
}

fn discharge2anyreg(fs: *FuncState, e: *expdesc) !void {
    if (e.k != .VNONRELOC) {
        try luaK_reserveregs(fs, 1);
        discharge2reg(fs, e, fs.freereg - 1);
    }
}

fn code_loadbool(fs: *FuncState, a: i32, op: lvm.OpCode) i32 {
    _ = luaK_getlabel(fs);
    return luaK_codeABC(fs, op, a, 0, 0);
}

fn need_value(fs: *FuncState, list: i32) bool {
    var l = list;
    while (l != NO_JUMP) : (l = getjump(fs, l)) {
        const i = getjumpcontrol(fs, l).*;
        if (lvm.GET_OPCODE(i) != .TESTSET) return true;
    }
    return false;
}

fn exp2reg(fs: *FuncState, e: *expdesc, reg: i32) void {
    discharge2reg(fs, e, reg);
    if (e.k == .VJMP)
        luaK_concat(fs, &e.t, e.u.info);
    if (hasjumps(e)) {
        var final: i32 = 0;
        var p_f: i32 = NO_JUMP;
        var p_t: i32 = NO_JUMP;
        if (need_value(fs, e.t) or need_value(fs, e.f)) {
            const fj = if (e.k == .VJMP) NO_JUMP else luaK_jump(fs);
            p_f = code_loadbool(fs, reg, .LFALSESKIP);
            p_t = code_loadbool(fs, reg, .LOADTRUE);
            luaK_patchtohere(fs, fj);
        }
        final = luaK_getlabel(fs);
        patchlistaux(fs, e.f, final, reg, p_f);
        patchlistaux(fs, e.t, final, reg, p_t);
    }
    e.f = NO_JUMP;
    e.t = NO_JUMP;
    e.u = .{ .info = reg };
    e.k = .VNONRELOC;
}

pub fn luaK_exp2nextreg(fs: *FuncState, e: *expdesc) !void {
    luaK_dischargevars(fs, e);
    freeexp(fs, e);
    try luaK_reserveregs(fs, 1);
    exp2reg(fs, e, fs.freereg - 1);
}

pub fn luaK_exp2anyreg(fs: *FuncState, e: *expdesc) !i32 {
    luaK_dischargevars(fs, e);
    if (e.k == .VNONRELOC) {
        if (!hasjumps(e))
            return e.u.info;
        if (e.u.info >= lparser.luaY_nvarstack(fs)) {
            exp2reg(fs, e, e.u.info);
            return e.u.info;
        }
    }
    try luaK_exp2nextreg(fs, e);
    return e.u.info;
}

pub fn luaK_codecheckglobal(fs: *FuncState, var_: *expdesc, k: i32, line: i32) !void {
    _ = try luaK_exp2anyreg(fs, var_);
    luaK_fixline(fs, line);
    var k2 = k;
    if (k2 >= lvm.MAXARG_Bx) k2 = 0 else k2 += 1;
    _ = luaK_codeABx(fs, .ERRNNIL, var_.u.info, k2);
    luaK_fixline(fs, line);
    freeexp(fs, var_);
}

pub fn luaK_exp2anyregup(fs: *FuncState, e: *expdesc) !void {
    if ((e.k != .VUPVAL and e.k != .VVARGVAR) or hasjumps(e))
        _ = try luaK_exp2anyreg(fs, e);
}

pub fn luaK_exp2val(fs: *FuncState, e: *expdesc) !void {
    if (e.k == .VJMP or hasjumps(e))
        _ = try luaK_exp2anyreg(fs, e)
    else
        luaK_dischargevars(fs, e);
}

fn luaK_exp2K(fs: *FuncState, e: *expdesc) bool {
    if (!hasjumps(e)) {
        const info: i32 = switch (e.k) {
            .VTRUE => boolT(fs) catch 0,
            .VFALSE => boolF(fs) catch 0,
            .VNIL => nilK(fs) catch 0,
            .VKINT => intK(fs, e.u.ival) catch 0,
            .VKFLT => numberK(fs, e.u.nval) catch 0,
            .VKSTR => stringK(fs, e.u.strval) catch 0,
            .VK => e.u.info,
            else => return false,
        };
        if (info <= lvm.MAXINDEXRK) {
            e.k = .VK;
            e.u = .{ .info = info };
            return true;
        }
    }
    return false;
}

fn exp2RK(fs: *FuncState, e: *expdesc) !bool {
    if (luaK_exp2K(fs, e))
        return true;
    _ = try luaK_exp2anyreg(fs, e);
    return false;
}

fn codeABRK(fs: *FuncState, o: lvm.OpCode, a: i32, b: i32, ec: *expdesc) !void {
    const k = try exp2RK(fs, ec);
    _ = luaK_codeABCk(fs, o, a, b, ec.u.info, if (k) 1 else 0);
}

pub fn luaK_storevar(fs: *FuncState, vp: *expdesc, ex: *expdesc) !void {
    switch (vp.k) {
        .VLOCAL => {
            freeexp(fs, ex);
            exp2reg(fs, ex, vp.u.uv.ridx);
            return;
        },
        .VUPVAL => {
            const e = try luaK_exp2anyreg(fs, ex);
            _ = luaK_codeABC(fs, .SETUPVAL, e, vp.u.info, 0);
        },
        .VINDEXUP => {
            try codeABRK(fs, .SETTABUP, vp.u.ind.t, vp.u.ind.idx, ex);
        },
        .VINDEXI => {
            try codeABRK(fs, .SETI, vp.u.ind.t, vp.u.ind.idx, ex);
        },
        .VINDEXSTR => {
            try codeABRK(fs, .SETFIELD, vp.u.ind.t, vp.u.ind.idx, ex);
        },
        .VVARGIND => {
            lparser.needvatab(fs.f);
            try codeABRK(fs, .SETTABLE, vp.u.ind.t, vp.u.ind.idx, ex);
        },
        .VINDEXED => {
            try codeABRK(fs, .SETTABLE, vp.u.ind.t, vp.u.ind.idx, ex);
        },
        else => std.debug.assert(false),
    }
    freeexp(fs, ex);
}

fn negatecondition(fs: *FuncState, e: *expdesc) !void {
    const pc = getjumpcontrol(fs, e.u.info);
    std.debug.assert(lvm.testTMode(lvm.GET_OPCODE(pc.*)) and
        lvm.GET_OPCODE(pc.*) != .TESTSET and lvm.GET_OPCODE(pc.*) != .TEST);
    lvm.SETARG_k(pc, lvm.GETARG_k(pc.*) ^ 1);
}

fn jumponcond(fs: *FuncState, e: *expdesc, cond: i32) !i32 {
    if (e.k == .VRELOC) {
        const ie = fs.code.items[@as(usize, @intCast(e.u.info))];
        if (lvm.GET_OPCODE(ie) == .NOT) {
            removelastinstruction(fs);
            return condjump(fs, .TEST, lvm.GETARG_B(ie), 0, 0, if (cond == 0) 1 else 0);
        }
    }
    try discharge2anyreg(fs, e);
    freeexp(fs, e);
    return condjump(fs, .TESTSET, lvm.NO_REG, e.u.info, 0, cond);
}

pub fn luaK_goiftrue(fs: *FuncState, e: *expdesc) !void {
    var pc: i32 = undefined;
    luaK_dischargevars(fs, e);
    switch (e.k) {
        .VJMP => {
            try negatecondition(fs, e);
            pc = e.u.info;
        },
        .VK, .VKFLT, .VKINT, .VKSTR, .VTRUE => {
            pc = NO_JUMP;
        },
        else => {
            pc = try jumponcond(fs, e, 0);
        },
    }
    luaK_concat(fs, &e.f, pc);
    luaK_patchtohere(fs, e.t);
    e.t = NO_JUMP;
}

fn luaK_goiffalse(fs: *FuncState, e: *expdesc) !void {
    var pc: i32 = undefined;
    luaK_dischargevars(fs, e);
    switch (e.k) {
        .VJMP => {
            pc = e.u.info;
        },
        .VNIL, .VFALSE => {
            pc = NO_JUMP;
        },
        else => {
            pc = try jumponcond(fs, e, 1);
        },
    }
    luaK_concat(fs, &e.t, pc);
    luaK_patchtohere(fs, e.f);
    e.f = NO_JUMP;
}

fn codenot(fs: *FuncState, e: *expdesc) !void {
    switch (e.k) {
        .VNIL, .VFALSE => {
            e.k = .VTRUE;
        },
        .VK, .VKFLT, .VKINT, .VKSTR, .VTRUE => {
            e.k = .VFALSE;
        },
        .VJMP => {
            try negatecondition(fs, e);
        },
        .VRELOC, .VNONRELOC => {
            try discharge2anyreg(fs, e);
            freeexp(fs, e);
            e.u = .{ .info = luaK_codeABC(fs, .NOT, 0, e.u.info, 0) };
            e.k = .VRELOC;
        },
        else => std.debug.assert(false),
    }
    const temp = e.f;
    e.f = e.t;
    e.t = temp;
    removevalues(fs, e.f);
    removevalues(fs, e.t);
}

fn isKstr(fs: *FuncState, e: *expdesc) bool {
    _ = fs;
    return (e.k == .VK and !hasjumps(e) and e.u.info <= lvm.MAXINDEXRK);
}

fn isKint(e: *expdesc) bool {
    return (e.k == .VKINT and !hasjumps(e));
}

fn isCint(e: *expdesc) bool {
    return (isKint(e) and @as(u64, @bitCast(e.u.ival)) <= lvm.MAXARG_C);
}

fn isSCint(e: *expdesc) bool {
    return (isKint(e) and fitsC(e.u.ival));
}

fn flttointeger(f: f64, i: *i64) bool {
    // i64 range is [-2^63, 2^63-1]; 2^63 itself does not fit. Use strict
    // bounds with exactly-representable f64 endpoints so @intFromFloat never
    // traps (it panics on out-of-range values). Note 2^63 (=9.22...e18) is
    // exactly representable and is EXCLUDED by the strict '<' upper bound.
    const min_i64_f: f64 = -9223372036854775808.0; // exactly -2^63
    const max_i64_f: f64 = 9223372036854775808.0; // exactly 2^63
    if (f >= min_i64_f and f < max_i64_f) {
        const fl = @floor(f);
        if (fl == f) {
            i.* = @intFromFloat(fl);
            return true;
        }
    }
    return false;
}

fn isSCnumber(e: *expdesc, pi: *i32, isfloat: *bool) bool {
    var i: i64 = 0;
    if (e.k == .VKINT) {
        i = e.u.ival;
    } else if (e.k == .VKFLT and flttointeger(e.u.nval, &i)) {
        isfloat.* = true;
    } else {
        return false;
    }
    if (!hasjumps(e) and fitsC(i)) {
        pi.* = int2sC(@intCast(i));
        return true;
    }
    return false;
}

pub fn luaK_self(fs: *FuncState, e: *expdesc, key: *expdesc) !void {
    _ = try luaK_exp2anyreg(fs, e);
    const ereg = e.u.info;
    freeexp(fs, e);
    const base = fs.freereg;
    e.u = .{ .info = base };
    e.k = .VNONRELOC;
    try luaK_reserveregs(fs, 2);
    std.debug.assert(key.k == .VKSTR);
    if (luaK_exp2K(fs, key)) {
        _ = luaK_codeABCk(fs, .SELF, base, ereg, key.u.info, 0);
    } else {
        _ = try luaK_exp2anyreg(fs, key);
        _ = luaK_codeABC(fs, .MOVE, base + 1, ereg, 0);
        _ = luaK_codeABC(fs, .GETTABLE, base, ereg, key.u.info);
    }
    freeexp(fs, key);
}

fn fillidxk(t: *expdesc, idx: i32, k: ExpKind) void {
    t.u = .{ .ind = .{ .idx = @intCast(idx), .t = t.u.ind.t, .ro = 0, .keystr = t.u.ind.keystr, .ridx = 0, .keyint = 0 } };
    t.k = k;
}

pub fn luaK_indexed(fs: *FuncState, t: *expdesc, k: *expdesc) !void {
    var keystr: i32 = -1;
    if (k.k == .VKSTR)
        keystr = str2K(fs, k);
    std.debug.assert(!hasjumps(t) and
        (t.k == .VLOCAL or t.k == .VVARGVAR or t.k == .VNONRELOC or t.k == .VUPVAL));
    if (t.k == .VUPVAL and !isKstr(fs, k)) {
        _ = try luaK_exp2anyreg(fs, t);
    }
    if (t.k == .VUPVAL) {
        const temp: u8 = @intCast(t.u.info);
        t.u = .{ .ind = .{ .idx = 0, .t = temp, .ro = 0, .keystr = keystr, .ridx = 0, .keyint = 0 } };
        std.debug.assert(isKstr(fs, k));
        fillidxk(t, k.u.info, .VINDEXUP);
    } else if (t.k == .VVARGVAR) {
        const kreg = try luaK_exp2anyreg(fs, k);
        const vreg: u8 = t.u.uv.ridx;
        std.debug.assert(vreg == fs.f.numParams);
        t.u = .{ .ind = .{ .idx = 0, .t = vreg, .ro = 0, .keystr = keystr, .ridx = 0, .keyint = 0 } };
        fillidxk(t, kreg, .VVARGIND);
    } else {
        const temp: u8 = if (t.k == .VLOCAL) t.u.uv.ridx else @intCast(t.u.info);
        t.u = .{ .ind = .{ .idx = 0, .t = temp, .ro = 0, .keystr = keystr, .ridx = 0, .keyint = 0 } };
        if (isKstr(fs, k)) {
            fillidxk(t, k.u.info, .VINDEXSTR);
        } else if (isCint(k)) {
            fillidxk(t, @intCast(k.u.ival), .VINDEXI);
        } else {
            fillidxk(t, try luaK_exp2anyreg(fs, k), .VINDEXED);
        }
    }
    t.u.ind.keystr = keystr;
}

fn constfolding(_: *FuncState, _: i32, _: *expdesc, _: *const expdesc) bool {
    return false;
}

fn validop(_: i32, _: *lua.TValue, _: *lua.TValue) bool {
    return true;
}

fn binopr2op(opr: lparser.BinOpr, baser: lparser.BinOpr, base: lvm.OpCode) lvm.OpCode {
    return @as(lvm.OpCode, @enumFromInt(@intFromEnum(opr) - @intFromEnum(baser) + @intFromEnum(base)));
}

fn unopr2op(opr: lparser.UnOpr) lvm.OpCode {
    return @as(lvm.OpCode, @enumFromInt(@intFromEnum(opr) - @intFromEnum(lparser.UnOpr.OPR_MINUS) + @intFromEnum(lvm.OpCode.UNM)));
}

fn binopr2TM(opr: lparser.BinOpr) ltm.TMS {
    return @as(ltm.TMS, @enumFromInt(@intFromEnum(opr) - @intFromEnum(lparser.BinOpr.OPR_ADD) + @intFromEnum(ltm.TMS.ADD)));
}

fn codeunexpval(fs: *FuncState, op: lvm.OpCode, e: *expdesc, line: i32) !void {
    const r = try luaK_exp2anyreg(fs, e);
    freeexp(fs, e);
    e.u = .{ .info = luaK_codeABC(fs, op, 0, r, 0) };
    e.k = .VRELOC;
    luaK_fixline(fs, line);
}

fn finishbinexpval(fs: *FuncState, e1: *expdesc, e2: *expdesc, op: lvm.OpCode, v2: i32, flip: bool, line: i32, mmop: lvm.OpCode, event: ltm.TMS) !void {
    const v1 = try luaK_exp2anyreg(fs, e1);
    // Emit the arithmetic opcode with A=0 as a placeholder. When 'e1' is later
    // discharged to a register, the VRELOC fixup (discharge2reg) rewrites A to
    // the final result register, matching the reference C behaviour.
    _ = luaK_codeABCk(fs, op, 0, v1, v2, 0);
    freeexps(fs, e1, e2);
    e1.u = .{ .info = @intCast(fs.code.items.len - 1) };
    e1.k = .VRELOC;
    luaK_fixline(fs, line);
    _ = luaK_codeABCk(fs, mmop, v1, v2, @intFromEnum(event), if (flip) 1 else 0);
    luaK_fixline(fs, line);
}

fn codebinexpval(fs: *FuncState, opr: lparser.BinOpr, e1: *expdesc, e2: *expdesc, line: i32) !void {
    const op = binopr2op(opr, .OPR_ADD, .ADD);
    const v2 = try luaK_exp2anyreg(fs, e2);
    const k_val = @intFromEnum(e1.k);
    std.debug.assert((@intFromEnum(ExpKind.VNIL) <= k_val and k_val <= @intFromEnum(ExpKind.VKSTR)) or
        e1.k == .VNONRELOC or e1.k == .VRELOC);
    std.debug.assert(@intFromEnum(lvm.OpCode.ADD) <= @intFromEnum(op) and @intFromEnum(op) <= @intFromEnum(lvm.OpCode.SHR));
    _ = try finishbinexpval(fs, e1, e2, op, v2, false, line, .MMBIN, binopr2TM(opr));
}

fn codebini(fs: *FuncState, op: lvm.OpCode, e1: *expdesc, e2: *expdesc, flip: bool, line: i32, event: ltm.TMS) !void {
    const v2 = int2sC(@intCast(e2.u.ival));
    std.debug.assert(e2.k == .VKINT);
    try finishbinexpval(fs, e1, e2, op, v2, flip, line, .MMBINI, event);
}

fn codebinK(fs: *FuncState, opr: lparser.BinOpr, e1: *expdesc, e2: *expdesc, flip: bool, line: i32) !void {
    const event = binopr2TM(opr);
    const v2 = e2.u.info;
    const op = binopr2op(opr, .OPR_ADD, .ADDK);
    try finishbinexpval(fs, e1, e2, op, v2, flip, line, .MMBINK, event);
}

fn finishbinexpneg(fs: *FuncState, e1: *expdesc, e2: *expdesc, op: lvm.OpCode, line: i32, event: ltm.TMS) !bool {
    if (!isKint(e2)) return false;
    const i2v = e2.u.ival;
    if (!(fitsC(i2v) and fitsC(-i2v))) return false;
    const v2 = @as(i32, @intCast(i2v));
    try finishbinexpval(fs, e1, e2, op, int2sC(-v2), false, line, .MMBINI, event);
    lvm.SETARG_B(&fs.code.items[fs.code.items.len - 1], int2sC(v2));
    return true;
}

fn swapexps(e1: *expdesc, e2: *expdesc) void {
    const temp = e1.*;
    e1.* = e2.*;
    e2.* = temp;
}

fn codebinNoK(fs: *FuncState, opr: lparser.BinOpr, e1: *expdesc, e2: *expdesc, flip: bool, line: i32) !void {
    if (flip) swapexps(e1, e2);
    try codebinexpval(fs, opr, e1, e2, line);
}

fn codearith(fs: *FuncState, opr: lparser.BinOpr, e1: *expdesc, e2: *expdesc, flip: bool, line: i32) !void {
    var dummy: lua.TValue = undefined;
    if (tonumeral(e2, &dummy) and luaK_exp2K(fs, e2)) {
        try codebinK(fs, opr, e1, e2, flip, line);
    } else {
        try codebinNoK(fs, opr, e1, e2, flip, line);
    }
}

fn codecommutative(fs: *FuncState, op: lparser.BinOpr, e1: *expdesc, e2: *expdesc, line: i32) !void {
    var flip = false;
    var dummy: lua.TValue = undefined;
    if (tonumeral(e1, &dummy)) {
        swapexps(e1, e2);
        flip = true;
    }
    if (op == .OPR_ADD and isSCint(e2)) {
        try codebini(fs, .ADDI, e1, e2, flip, line, .ADD);
    } else {
        try codearith(fs, op, e1, e2, flip, line);
    }
}

fn codebitwise(fs: *FuncState, opr: lparser.BinOpr, e1: *expdesc, e2: *expdesc, line: i32) !void {
    var flip = false;
    if (e1.k == .VKINT) {
        swapexps(e1, e2);
        flip = true;
    }
    if (e2.k == .VKINT and luaK_exp2K(fs, e2)) {
        try codebinK(fs, opr, e1, e2, flip, line);
    } else {
        try codebinNoK(fs, opr, e1, e2, flip, line);
    }
}

fn codeorder(fs: *FuncState, opr: lparser.BinOpr, e1: *expdesc, e2: *expdesc) !void {
    var r1: i32 = 0;
    var r2: i32 = 0;
    var im: i32 = 0;
    var isfloat: bool = false;
    var op: lvm.OpCode = undefined;
    if (isSCnumber(e2, &im, &isfloat)) {
        r1 = try luaK_exp2anyreg(fs, e1);
        r2 = im;
        op = binopr2op(opr, .OPR_LT, .LTI);
    } else if (isSCnumber(e1, &im, &isfloat)) {
        r1 = try luaK_exp2anyreg(fs, e2);
        r2 = im;
        op = binopr2op(opr, .OPR_LT, .GTI);
    } else {
        r1 = try luaK_exp2anyreg(fs, e1);
        r2 = try luaK_exp2anyreg(fs, e2);
        op = binopr2op(opr, .OPR_LT, .LT);
    }
    freeexps(fs, e1, e2);
    e1.u = .{ .info = condjump(fs, op, r1, r2, @intFromBool(isfloat), 1) };
    e1.t = NO_JUMP;
    e1.f = NO_JUMP;
    e1.k = .VJMP;
}

fn codeeq(fs: *FuncState, opr: lparser.BinOpr, e1: *expdesc, e2: *expdesc) !void {
    var r1: i32 = 0;
    var r2: i32 = 0;
    var im: i32 = 0;
    var isfloat: bool = false;
    var op: lvm.OpCode = undefined;
    if (e1.k != .VNONRELOC) {
        std.debug.assert(e1.k == .VK or e1.k == .VKINT or e1.k == .VKFLT);
        swapexps(e1, e2);
    }
    r1 = try luaK_exp2anyreg(fs, e1);
    if (isSCnumber(e2, &im, &isfloat)) {
        op = .EQI;
        r2 = im;
    } else if (try exp2RK(fs, e2)) {
        op = .EQK;
        r2 = e2.u.info;
    } else {
        op = .EQ;
        r2 = try luaK_exp2anyreg(fs, e2);
    }
    freeexps(fs, e1, e2);
    e1.u = .{ .info = condjump(fs, op, r1, r2, @intFromBool(isfloat), if (opr == .OPR_EQ) 1 else 0) };
    e1.t = NO_JUMP;
    e1.f = NO_JUMP;
    e1.k = .VJMP;
}

fn undefined_exp() expdesc {
    return .{ .k = .VKINT, .u = .{ .ival = 0 }, .t = NO_JUMP, .f = NO_JUMP };
}

pub fn luaK_prefix(fs: *FuncState, opr: lparser.UnOpr, e: *expdesc, line: i32) !void {
    luaK_dischargevars(fs, e);
    switch (opr) {
        .OPR_MINUS, .OPR_BNOT => {
            if (constfolding(fs, @intFromEnum(opr) + lua.LUA_OPUNM, e, &undefined_exp())) return;
            try codeunexpval(fs, unopr2op(opr), e, line);
        },
        .OPR_LEN => {
            try codeunexpval(fs, unopr2op(opr), e, line);
        },
        .OPR_NOT => try codenot(fs, e),
        .OPR_NOUNOPR => unreachable,
    }
}

pub fn luaK_infix(fs: *FuncState, op: lparser.BinOpr, v: *expdesc) !void {
    luaK_dischargevars(fs, v);
    switch (op) {
        .OPR_AND => _ = try luaK_goiftrue(fs, v),
        .OPR_OR => _ = try luaK_goiffalse(fs, v),
        .OPR_CONCAT => try luaK_exp2nextreg(fs, v),
        .OPR_ADD, .OPR_SUB, .OPR_MUL, .OPR_DIV, .OPR_IDIV, .OPR_MOD, .OPR_POW, .OPR_BAND, .OPR_BOR, .OPR_BXOR, .OPR_SHL, .OPR_SHR => {
            var dummy: lua.TValue = undefined;
            if (!tonumeral(v, &dummy)) _ = try luaK_exp2anyreg(fs, v);
        },
        .OPR_EQ, .OPR_NE => {
            var dummy: lua.TValue = undefined;
            if (!tonumeral(v, &dummy)) _ = try exp2RK(fs, v);
        },
        .OPR_LT, .OPR_LE, .OPR_GT, .OPR_GE => {
            var d1: i32 = 0;
            var d2: bool = false;
            if (!isSCnumber(v, &d1, &d2)) _ = try luaK_exp2anyreg(fs, v);
        },
        .OPR_NOBINOPR => unreachable,
    }
}

fn codeconcat(fs: *FuncState, e1: *expdesc, e2: *expdesc, line: i32) !void {
    const ie2 = previousinstruction(fs);
    if (ie2) |pi| {
        if (lvm.GET_OPCODE(pi.*) == .CONCAT) {
            const n = lvm.GETARG_B(pi.*);
            std.debug.assert(e1.u.info + 1 == lvm.GETARG_A(pi.*));
            freeexp(fs, e2);
            lvm.SETARG_A(pi, e1.u.info);
            lvm.SETARG_B(pi, n + 1);
            return;
        }
    }
    _ = luaK_codeABC(fs, .CONCAT, e1.u.info, 2, 0);
    freeexp(fs, e2);
    luaK_fixline(fs, line);
}

pub fn luaK_posfix(fs: *FuncState, opr: lparser.BinOpr, e1: *expdesc, e2: *expdesc, line: i32) !void {
    luaK_dischargevars(fs, e2);
    if (constfolding(fs, @intFromEnum(opr) + lua.LUA_OPADD, e1, e2)) return;
    switch (opr) {
        .OPR_AND => {
            luaK_concat(fs, &e2.f, e1.f);
            e1.* = e2.*;
        },
        .OPR_OR => {
            std.debug.assert(e1.f == NO_JUMP);
            luaK_concat(fs, &e2.t, e1.t);
            e1.* = e2.*;
        },
        .OPR_CONCAT => {
            try luaK_exp2nextreg(fs, e2);
            try codeconcat(fs, e1, e2, line);
        },
        .OPR_ADD, .OPR_MUL => {
            try codecommutative(fs, opr, e1, e2, line);
        },
        .OPR_SUB => {
            if (try finishbinexpneg(fs, e1, e2, .ADDI, line, .SUB)) return;
            // fallthrough: e2 is not a constant int, emit general subtract
            try codearith(fs, opr, e1, e2, false, line);
        },
        .OPR_DIV, .OPR_IDIV, .OPR_MOD, .OPR_POW => {
            try codearith(fs, opr, e1, e2, false, line);
        },
        .OPR_BAND, .OPR_BOR, .OPR_BXOR => {
            try codebitwise(fs, opr, e1, e2, line);
        },
        .OPR_SHL => {
            if (isSCint(e1)) {
                swapexps(e1, e2);
                try codebini(fs, .SHLI, e1, e2, true, line, .SHL);
            } else if (try finishbinexpneg(fs, e1, e2, .SHRI, line, .SHL)) {
                // coded as (r1 >> -I)
            } else {
                try codebinexpval(fs, opr, e1, e2, line);
            }
        },
        .OPR_SHR => {
            if (isSCint(e2)) {
                try codebini(fs, .SHRI, e1, e2, false, line, .SHR);
            } else {
                try codebinexpval(fs, opr, e1, e2, line);
            }
        },
        .OPR_EQ, .OPR_NE => {
            try codeeq(fs, opr, e1, e2);
        },
        .OPR_GT, .OPR_GE => {
            swapexps(e1, e2);
            const newop: lparser.BinOpr = @as(lparser.BinOpr, @enumFromInt(@intFromEnum(opr) - @intFromEnum(lparser.BinOpr.OPR_GT) + @intFromEnum(lparser.BinOpr.OPR_LT)));
            try codeorder(fs, newop, e1, e2);
        },
        .OPR_LT, .OPR_LE => {
            try codeorder(fs, opr, e1, e2);
        },
        .OPR_NOBINOPR => unreachable,
    }
}

pub fn luaK_fixline(fs: *FuncState, line: i32) void {
    removelastlineinfo(fs);
    savelineinfo(fs, line) catch {};
}

pub fn luaK_settablesize(fs: *FuncState, pc: i32, ra: i32, asize: i32, hsize: i32) void {
    const inst = &fs.code.items[@as(usize, @intCast(pc))];
    const extra = @divTrunc(asize, lvm.MAXARG_vC + 1);
    const rc = @rem(asize, lvm.MAXARG_vC + 1);
    const k = if (extra > 0) @as(i32, 1) else @as(i32, 0);
    const hh = if (hsize != 0) ceillog2(@as(u32, @intCast(hsize))) + 1 else 0;
    inst.* = lvm.CREATE_vABCk(.NEWTABLE, ra, @intCast(hh), rc, k);
    fs.code.items[@as(usize, @intCast(pc + 1))] = lvm.CREATE_Ax(.EXTRAARG, extra);
}

pub fn luaK_setlist(fs: *FuncState, base: i32, nelems: i32, tostore: i32) void {
    std.debug.assert(tostore != 0);
    var ts = tostore;
    if (tostore == lua.LUA_MULTRET) ts = 0;
    if (nelems <= lvm.MAXARG_vC) {
        _ = luaK_codevABCk(fs, .SETLIST, base, ts, nelems, 0);
    } else {
        const extra = @divTrunc(nelems, lvm.MAXARG_vC + 1);
        const ne = @rem(nelems, lvm.MAXARG_vC + 1);
        _ = luaK_codevABCk(fs, .SETLIST, base, ts, ne, 1);
        _ = codeextraarg(fs, extra);
    }
    fs.freereg = @intCast(base + 1);
}

fn ceillog2(x: u32) u32 {
    var v = x;
    v -= 1;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    return @bitSizeOf(u32) - @clz(v);
}

fn finaltarget(code: []Instruction, i: i32) i32 {
    var count: i32 = 0;
    var idx = i;
    while (count < 100) : (count += 1) {
        const pc = code[@as(usize, @intCast(idx))];
        if (lvm.GET_OPCODE(pc) != .JMP) break;
        idx += lvm.GETARG_sJ(pc) + 1;
    }
    return idx;
}

pub fn luaK_finish(fs: *FuncState) void {
    const p = fs.f;
    if ((p.flag & lparser.PF_VATAB) != 0)
        p.flag &= ~@as(u8, lparser.PF_VAHID);
    var i: usize = 0;
    while (i < fs.code.items.len) : (i += 1) {
        const pc = &fs.code.items[i];
        switch (lvm.GET_OPCODE(pc.*)) {
            .RETURN0, .RETURN1 => {
                if (!(fs.needclose or (p.flag & lparser.PF_VAHID) != 0)) break;
                lvm.SET_OPCODE(pc, .RETURN);
                if (fs.needclose)
                    lvm.SETARG_k(pc, 1);
                if ((p.flag & lparser.PF_VAHID) != 0)
                    lvm.SETARG_C(pc, p.numParams + 1);
            },
            .RETURN, .TAILCALL => {
                if (fs.needclose)
                    lvm.SETARG_k(pc, 1);
                if ((p.flag & lparser.PF_VAHID) != 0)
                    lvm.SETARG_C(pc, p.numParams + 1);
            },
            .GETVARG => {
                if ((p.flag & lparser.PF_VATAB) != 0)
                    lvm.SET_OPCODE(pc, .GETTABLE);
            },
            .VARARG => {
                if ((p.flag & lparser.PF_VATAB) != 0)
                    lvm.SETARG_k(pc, 1);
            },
            .JMP => {
                const target = finaltarget(fs.code.items, @intCast(i));
                fixjump(fs, @intCast(i), target);
            },
            else => {},
        }
    }
}

pub fn luaK_codeABC(fs: *FuncState, o: lvm.OpCode, a: i32, b: i32, c: i32) i32 {
    return luaK_codeABCk(fs, o, a, b, c, 0);
}

pub fn luaK_exp2const(fs: *FuncState, e: *const expdesc, v: *lua.TValue) bool {
    return exp2const(fs, e, v);
}
