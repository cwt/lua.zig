// $Id: lparser.zig $
// Parser for Lua.zig (Zig port of Lua 5.5.0 lparser.c)
// See Copyright Notice in lua.zig
//
// Recursive-descent parser that drives the code generator in lcode.zig.
// Written in idiomatic Zig 0.16.0: the allocator is threaded through
// FuncState/LexState, every fallible operation propagates errors with `try`,
// and nothing swallows allocation errors.

const std = @import("std");
const lua = @import("lua.zig");
const lvm = @import("lvm.zig");
const lcode = @import("lcode.zig");
const llex = @import("llex.zig");
const lstring = @import("lstring.zig");

const ltable = @import("ltable.zig");
const luaconf = @import("luaconf.zig");

pub const NO_JUMP: i32 = -1;

// maximum number of local variables per function (must be < 250)
const MAXVARS: i32 = 200;
const MAXUPVAL: i32 = 255;
const LUAI_MAXCCALLS: i32 = 200;
const MAX_CNST: i32 = @divFloor(std.math.maxInt(i32), 2);

// Prototype flag bits (lua/lobject.h).
pub const PF_VAHID: u8 = 1; // function has hidden vararg arguments
pub const PF_VATAB: u8 = 2; // function has vararg table

// Variable-description kinds (lua/lparser.h).
const VDKREG: u8 = 0;
const RDKCONST: u8 = 1;
const RDKVAVAR: u8 = 2;
const RDKTOCLOSE: u8 = 3;
const RDKCTC: u8 = 4;
const GDKREG: u8 = 5;
const GDKCONST: u8 = 6;

// loop control variables are read-only by default.
const LOOPVARKIND: u8 = RDKCONST;

const UNARY_PRIORITY: i32 = 12;

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

pub const ExpKind = enum {
    VVOID,
    VNIL,
    VTRUE,
    VFALSE,
    VK,
    VKFLT,
    VKINT,
    VKSTR,
    VNONRELOC,
    VLOCAL,
    VVARGVAR,
    VGLOBAL,
    VUPVAL,
    VCONST,
    VINDEXED,
    VVARGIND,
    VINDEXUP,
    VINDEXI,
    VINDEXSTR,
    VJMP,
    VRELOC,
    VCALL,
    VVARARG,
};

pub const BinOpr = enum {
    OPR_ADD,
    OPR_SUB,
    OPR_MUL,
    OPR_MOD,
    OPR_POW,
    OPR_DIV,
    OPR_IDIV,
    OPR_BAND,
    OPR_BOR,
    OPR_BXOR,
    OPR_SHL,
    OPR_SHR,
    OPR_CONCAT,
    OPR_NE,
    OPR_EQ,
    OPR_LT,
    OPR_LE,
    OPR_GT,
    OPR_GE,
    OPR_AND,
    OPR_OR,
    OPR_NOBINOPR,
};

pub const UnOpr = enum {
    OPR_MINUS,
    OPR_BNOT,
    OPR_NOT,
    OPR_LEN,
    OPR_NOUNOPR,
};

pub const expdesc = struct {
    k: ExpKind,
    t: i32,
    f: i32,
    u: union(enum) {
        info: i32,
        ival: i64,
        nval: f64,
        strval: ?*lua.lua_TString,
        uv: struct { ridx: u8, vidx: i16 },
        ind: struct { t: u8, idx: i32, ridx: i32, ro: i32, keystr: i32, keyint: i32 },
    },
};

pub const BlockCnt = struct {
    previous: ?*BlockCnt = null,
    firstlabel: i32 = 0,
    firstgoto: i32 = 0,
    nactvar: i16 = 0,
    upval: u8 = 0,
    isloop: u8 = 0,
    insidetbc: u8 = 0,
};

pub const FuncState = struct {
    ls: *llex.LexState = undefined,
    f: *lua.lua_Proto = undefined,
    prev: ?*FuncState = null,
    bl: ?*BlockCnt = null,
    lasttarget: i32 = 0,
    previousline: i32 = 0,
    freereg: i32 = 0,
    nactvar: i32 = 0,
    firstlocal: i32 = 0,
    firstlabel: i32 = 0,
    firstgoto: i32 = 0,
    nlocvars: i32 = 0,
    nups: i32 = 0,
    needclose: bool = false,
    iwthabs: i32 = 0,
    nabslineinfo: i32 = 0,
    abslineinfo: std.ArrayList(lua.AbsLineInfo) = .empty,
    code: std.ArrayList(lvm.Instruction) = .empty,
    k: std.ArrayList(lua.TValue) = .empty,
    lineinfo: std.ArrayList(i8) = .empty,
    p: std.ArrayList(*lua.lua_Proto) = .empty,
    upvalues: std.ArrayList(lua.Upvaldesc) = .empty,
    locvars: std.ArrayList(lua.LocVar) = .empty,
};

const ConsControl = struct {
    v: expdesc,
    t: *expdesc,
    nh: i32,
    na: i32,
    tostore: i32,
    maxtostore: i32,
};

const LHS_assign = struct {
    prev: ?*LHS_assign,
    v: expdesc,
};

// Priority table for binary operators (ORDER OPR).
const priority = [_]struct { left: u8, right: u8 }{
    .{ .left = 10, .right = 10 }, // OPR_ADD
    .{ .left = 10, .right = 10 }, // OPR_SUB
    .{ .left = 11, .right = 11 }, // OPR_MUL
    .{ .left = 11, .right = 11 }, // OPR_MOD
    .{ .left = 14, .right = 13 }, // OPR_POW
    .{ .left = 11, .right = 11 }, // OPR_DIV
    .{ .left = 11, .right = 11 }, // OPR_IDIV
    .{ .left = 6, .right = 6 }, // OPR_BAND
    .{ .left = 4, .right = 4 }, // OPR_BOR
    .{ .left = 5, .right = 5 }, // OPR_BXOR
    .{ .left = 7, .right = 7 }, // OPR_SHL
    .{ .left = 7, .right = 7 }, // OPR_SHR
    .{ .left = 9, .right = 8 }, // OPR_CONCAT
    .{ .left = 3, .right = 3 }, // OPR_NE
    .{ .left = 3, .right = 3 }, // OPR_EQ
    .{ .left = 3, .right = 3 }, // OPR_LT
    .{ .left = 3, .right = 3 }, // OPR_LE
    .{ .left = 3, .right = 3 }, // OPR_GT
    .{ .left = 3, .right = 3 }, // OPR_GE
    .{ .left = 2, .right = 2 }, // OPR_AND
    .{ .left = 1, .right = 1 }, // OPR_OR
    .{ .left = 0, .right = 0 }, // OPR_NOBINOPR
};

// ---------------------------------------------------------------------------
// Small helpers
// ---------------------------------------------------------------------------

fn eqstr(a: ?*lua.lua_TString, b: ?*lua.lua_TString) bool {
    if (a == b) return true;
    const sa = a orelse return false;
    const sb = b orelse return false;
    return std.mem.eql(u8, sa.s, sb.s);
}

fn eqstr_str(ts: ?*lua.lua_TString, lit: []const u8) bool {
    if (ts == null) return false;
    return std.mem.eql(u8, ts.?.s, lit);
}

fn getstr(ts: ?*lua.lua_TString) []const u8 {
    return if (ts) |t| t.s else "*";
}

fn envn(ls: *llex.LexState) *lua.lua_TString {
    return ls.envn.?;
}

fn isvararg(f: *lua.lua_Proto) bool {
    return f.isVarArg;
}

fn hasmultret(k: ExpKind) bool {
    return k == .VCALL or k == .VVARARG;
}

fn vkisvar(k: ExpKind) bool {
    const a = @intFromEnum(ExpKind.VLOCAL);
    const b = @intFromEnum(ExpKind.VINDEXSTR);
    const v = @intFromEnum(k);
    return v >= a and v <= b;
}

fn vkisindexed(k: ExpKind) bool {
    const a = @intFromEnum(ExpKind.VINDEXED);
    const b = @intFromEnum(ExpKind.VINDEXSTR);
    const v = @intFromEnum(k);
    return v >= a and v <= b;
}

fn varinreg(vd: llex.Vardesc) bool {
    return vd.kind <= RDKTOCLOSE;
}

fn varglobal(vd: llex.Vardesc) bool {
    return vd.kind >= GDKREG;
}

fn init_exp(e: *expdesc, k: ExpKind, i: i32) void {
    e.t = NO_JUMP;
    e.f = NO_JUMP;
    e.k = k;
    e.u = .{ .info = i };
}

fn codestring(e: *expdesc, s: ?*lua.lua_TString) void {
    e.t = NO_JUMP;
    e.f = NO_JUMP;
    e.k = .VKSTR;
    e.u = .{ .strval = s };
}

fn codename(ls: *llex.LexState, e: *expdesc) !void {
    codestring(e, try str_checkname(ls));
}

fn check_condition(ls: *llex.LexState, c: bool, msg: []const u8) !void {
    if (!c) return llex.luaX_syntaxerror(ls, msg);
}

fn error_expected(ls: *llex.LexState, token: i32) !void {
    var buf: [64]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "{s} expected", .{llex.token2str(token)}) catch "syntax error";
    return llex.luaX_syntaxerror(ls, msg);
}

fn check(ls: *llex.LexState, c: i32) !void {
    if (ls.t.token != c) try error_expected(ls, c);
}

fn checknext(ls: *llex.LexState, c: i32) !void {
    try check(ls, c);
    try llex.luaX_next(ls);
}

fn testnext(ls: *llex.LexState, c: i32) !bool {
    if (ls.t.token == c) {
        try llex.luaX_next(ls);
        return true;
    }
    return false;
}

fn check_match(ls: *llex.LexState, what: i32, who: i32, where: i32) !void {
    if (!(try testnext(ls, what))) {
        if (where == ls.linenumber) {
            try error_expected(ls, what);
        } else {
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "{s} expected (to close {s})", .{
                llex.token2str(what),
                llex.token2str(who),
            }) catch "syntax error";
            return llex.luaX_syntaxerror(ls, msg);
        }
    }
}

fn str_checkname(ls: *llex.LexState) !*lua.lua_TString {
    try check(ls, llex.TK_NAME);
    const ts = ls.t.seminfo.ts;
    try llex.luaX_next(ls);
    return ts.?;
}

fn luaK_jumpto(fs: *FuncState, target: i32) !void {
    try lcode.luaK_patchlist(fs, lcode.luaK_jump(fs), target);
}

fn luaK_setmultret(fs: *FuncState, e: *expdesc) !void {
    try lcode.luaK_setreturns(fs, e, lua.LUA_MULTRET);
}

fn getinstruction(fs: *FuncState, e: *expdesc) *lvm.Instruction {
    return &fs.code.items[@intCast(e.u.info)];
}

// ---------------------------------------------------------------------------
// Limit / stack helpers (called by lcode.zig)
// ---------------------------------------------------------------------------

pub fn luaY_checklimit(fs: *FuncState, v: i32, l: i32, what: []const u8) !void {
    if (v > l) {
        // Mirror the reference's errorlimit: include where the limit was hit
        // ("in main function" or "in function at line N").
        const line = fs.f.lineDefined;
        var buf: [160]u8 = undefined;
        const msg = if (line == 0)
            std.fmt.bufPrint(&buf, "too many {s} (limit is {d}) in main function", .{ what, l }) catch "limit exceeded"
        else
            std.fmt.bufPrint(&buf, "too many {s} (limit is {d}) in function at line {d}", .{ what, l, line }) catch "limit exceeded";
        return llex.luaX_syntaxerror(fs.ls, msg);
    }
}

pub fn luaY_nvarstack(fs: *FuncState) i32 {
    return reglevel(fs, fs.nactvar);
}

pub fn needvatab(f: *lua.lua_Proto) void {
    f.flag |= PF_VATAB;
    f.flag &= ~PF_VAHID;
}

// ---------------------------------------------------------------------------
// Variable-description helpers
// ---------------------------------------------------------------------------

fn getlocalvardesc(fs: *FuncState, vidx: i32) *llex.Vardesc {
    const idx = fs.firstlocal + vidx;
    return &fs.ls.dyd.actvar.items.ptr[@intCast(idx)];
}

fn reglevel(fs: *FuncState, nvar: i32) i32 {
    var n = nvar;
    while (n > 0) {
        n -= 1;
        const vd = getlocalvardesc(fs, n);
        if (varinreg(vd.*)) return @as(i32, vd.ridx) + 1;
    }
    return 0;
}

fn localdebuginfo(fs: *FuncState, vidx: i32) ?*lua.LocVar {
    const vd = getlocalvardesc(fs, vidx);
    if (!varinreg(vd.*)) return null;
    const idx = vd.pidx;
    return &fs.locvars.items[@intCast(idx)];
}

fn init_var(fs: *FuncState, e: *expdesc, vidx: i32) void {
    e.t = NO_JUMP;
    e.f = NO_JUMP;
    e.k = .VLOCAL;
    e.u = .{ .uv = .{ .vidx = @intCast(vidx), .ridx = getlocalvardesc(fs, vidx).ridx } };
}

fn new_varkind(ls: *llex.LexState, name: ?*lua.lua_TString, kind: u8) !i32 {
    const fs = ls.fs.?;
    const dyd = &ls.dyd;
    try dyd.actvar.append(ls.L.allocator, .{ .val = .{ .nil = {} }, .kind = kind, .name = name });
    return @intCast(@as(i32, @intCast(dyd.actvar.items.len - 1)) - fs.firstlocal);
}

fn new_localvar(ls: *llex.LexState, name: ?*lua.lua_TString) !i32 {
    return try new_varkind(ls, name, VDKREG);
}

fn new_localvarliteral(ls: *llex.LexState, v: []const u8) !i32 {
    const ts = try llex.luaX_newstring(ls, v);
    return try new_localvar(ls, ts);
}

fn registerlocalvar(ls: *llex.LexState, fs: *FuncState, varname: ?*lua.lua_TString) !i16 {
    try fs.locvars.append(ls.L.allocator, .{ .varname = varname });
    fs.locvars.items[fs.locvars.items.len - 1].startpc = @intCast(fs.code.items.len);
    const idx: i16 = @intCast(fs.nlocvars);
    fs.nlocvars += 1;
    return idx;
}

fn adjustlocalvars(ls: *llex.LexState, nvars: i32) !void {
    const fs = ls.fs.?;
    const reg = luaY_nvarstack(fs);
    var i: i32 = 0;
    while (i < nvars) : (i += 1) {
        const vidx = fs.nactvar;
        fs.nactvar += 1;
        const vd = getlocalvardesc(fs, vidx);
        vd.ridx = @intCast(reg + i);
        vd.pidx = try registerlocalvar(ls, fs, vd.name);
        try luaY_checklimit(fs, reg + i + 1, MAXVARS, "local variables");
    }
}

fn removevars(fs: *FuncState, tolevel: i32) void {
    const num_to_remove = fs.nactvar - tolevel;
    while (fs.nactvar > tolevel) {
        fs.nactvar -= 1;
        const v: ?*lua.LocVar = localdebuginfo(fs, fs.nactvar);
        if (v) |vv| vv.endpc = @intCast(fs.code.items.len);
    }
    fs.ls.dyd.actvar.items.len -= @intCast(num_to_remove);
}

fn searchupvalue(fs: *FuncState, n: *lua.lua_TString) i32 {
    var i: i32 = 0;
    while (i < fs.nups) : (i += 1) {
        if (eqstr(fs.upvalues.items[@intCast(i)].name, n)) return i;
    }
    return -1;
}

fn allocupvalue(fs: *FuncState) !*lua.Upvaldesc {
    try luaY_checklimit(fs, fs.nups + 1, MAXUPVAL, "upvalues");
    try fs.upvalues.append(fs.ls.L.allocator, .{ .name = null, .instack = 0, .idx = 0, .kind = 0 });
    fs.nups += 1;
    return &fs.upvalues.items[fs.upvalues.items.len - 1];
}

fn newupvalue(fs: *FuncState, name: *lua.lua_TString, v: *expdesc) !i32 {
    // BUG-095: validate fs.prev *before* mutating fs.upvalues.
    if (fs.prev == null) return llex.luaX_syntaxerror(fs.ls, "no enclosing function");
    const up = try allocupvalue(fs);
    const prev = fs.prev.?;
    if (v.k == .VLOCAL) {
        up.instack = 1;
        up.idx = v.u.uv.ridx;
        up.kind = getlocalvardesc(prev, v.u.uv.vidx).kind;
    } else {
        up.instack = 0;
        up.idx = @intCast(v.u.info);
        up.kind = prev.upvalues.items[@intCast(v.u.info)].kind;
    }
    up.name = name;
    return fs.nups - 1;
}

fn searchvar(fs: *FuncState, n: *lua.lua_TString, vp: *expdesc) i32 {
    var i: i32 = fs.nactvar - 1;
    while (i >= 0) : (i -= 1) {
        const vd = getlocalvardesc(fs, i);
        if (varglobal(vd.*)) {
            if (vd.name == null) {
                if (vp.u.info < 0) vp.u = .{ .info = fs.firstlocal + i };
            } else {
                if (eqstr(vd.name, n)) {
                    init_exp(vp, .VGLOBAL, fs.firstlocal + i);
                    return @intFromEnum(ExpKind.VGLOBAL);
                } else if (vp.u.info == -1) {
                    vp.u = .{ .info = -2 };
                }
            }
        } else if (eqstr(vd.name, n)) {
            if (vd.kind == RDKCTC) {
                init_exp(vp, .VCONST, fs.firstlocal + i);
            } else {
                init_var(fs, vp, i);
                if (vd.kind == RDKVAVAR) vp.k = .VVARGVAR;
            }
            return @intFromEnum(vp.k);
        }
    }
    return -1;
}

fn markupval(fs: *FuncState, level: i32) void {
    var bl = fs.bl;
    while (bl != null and bl.?.nactvar > level) bl = bl.?.previous;
    if (bl) |b| b.upval = 1;
    fs.needclose = true;
}

fn marktobeclosed(fs: *FuncState) void {
    const bl = fs.bl orelse return;
    bl.upval = 1;
    bl.insidetbc = 1;
    fs.needclose = true;
}

fn singlevaraux(fs: *FuncState, n: *lua.lua_TString, vp: *expdesc, base: bool) !void {
    const v = searchvar(fs, n, vp);
    if (v >= 0) {
        if (!base) {
            if (vp.k == .VVARGVAR) lcode.luaK_vapar2local(fs, vp);
            if (vp.k == .VLOCAL) markupval(fs, vp.u.uv.vidx);
        }
    } else {
        var idx = searchupvalue(fs, n);
        if (idx < 0) {
            if (fs.prev != null) try singlevaraux(fs.prev.?, n, vp, false);
            if (vp.k == .VLOCAL or vp.k == .VUPVAL) {
                idx = try newupvalue(fs, n, vp);
            } else return;
        }
        init_exp(vp, .VUPVAL, idx);
    }
}

fn buildglobal(ls: *llex.LexState, varname: *lua.lua_TString, vp: *expdesc) !void {
    const fs = ls.fs.?;
    var key: expdesc = undefined;
    init_exp(vp, .VGLOBAL, -1);
    try singlevaraux(fs, envn(ls), vp, true);
    if (vp.k == .VGLOBAL) {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "_ENV is global when accessing variable '{s}'", .{varname.s}) catch "_ENV is global";
        try lcode.luaK_semerror(ls, msg);
    }
    try lcode.luaK_exp2anyregup(fs, vp);
    codestring(&key, varname);
    try lcode.luaK_indexed(fs, vp, &key);
}

fn checkglobal(ls: *llex.LexState, varname: *lua.lua_TString, line: i32) !void {
    const fs = ls.fs.?;
    var var_: expdesc = undefined;
    try buildglobal(ls, varname, &var_);
    const k = var_.u.ind.keystr;
    try lcode.luaK_codecheckglobal(fs, &var_, k, line);
}

fn buildvar(ls: *llex.LexState, varname: *lua.lua_TString, vp: *expdesc) !void {
    const fs = ls.fs.?;
    init_exp(vp, .VGLOBAL, -1);
    try singlevaraux(fs, varname, vp, true);
    if (vp.k == .VGLOBAL) {
        const info = vp.u.info;
        if (info == -2) {
            var buf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&buf, "variable '{s}' not declared", .{varname.s}) catch "variable not declared";
            try lcode.luaK_semerror(ls, msg);
        }
        try buildglobal(ls, varname, vp);
        if (info != -1) {
            const kind = ls.dyd.actvar.items[@intCast(info)].kind;
            if (kind == GDKCONST) vp.u.ind.ro = 1;
        }
    }
}

fn singlevar(ls: *llex.LexState, vp: *expdesc) !void {
    try buildvar(ls, try str_checkname(ls), vp);
}

fn check_readonly(ls: *llex.LexState, e: *expdesc) !void {
    const fs = ls.fs.?;
    var varname: ?*lua.lua_TString = null;
    switch (e.k) {
        .VCONST => {
            varname = fs.ls.dyd.actvar.items[@intCast(e.u.info)].name;
        },
        .VLOCAL, .VVARGVAR => {
            const vardesc = getlocalvardesc(fs, e.u.uv.vidx);
            if (vardesc.kind != VDKREG) varname = vardesc.name;
        },
        .VUPVAL => {
            const up = &fs.upvalues.items[@intCast(e.u.info)];
            if (up.kind != VDKREG) varname = up.name;
        },
        .VVARGIND => {
            needvatab(fs.f);
            e.k = .VINDEXED;
            if (e.u.ind.ro != 0) varname = fs.k.items[@intCast(e.u.ind.keystr)].string;
        },
        .VINDEXUP, .VINDEXSTR, .VINDEXED => {
            if (e.u.ind.ro != 0) varname = fs.k.items[@intCast(e.u.ind.keystr)].string;
        },
        else => {
            std.debug.assert(e.k == .VINDEXI);
            return;
        },
    }
    if (varname) |vn| {
        const msg = try std.fmt.allocPrint(ls.L.allocator, "attempt to assign to const variable '{s}'", .{vn.s});
        defer ls.L.allocator.free(msg);
        try lcode.luaK_semerror(ls, msg);
    }
}

// ---------------------------------------------------------------------------
// Blocks / scopes
// ---------------------------------------------------------------------------

fn enterlevel(ls: *llex.LexState) !void {
    ls.level += 1;
    if (ls.level > LUAI_MAXCCALLS) {
        // Mirrors the reference (enterlevel -> luaE_incCstack -> luaE_checkcstack),
        // which raises "C stack overflow" when parser recursion reaches the
        // C-call limit.
        return lua.luaG_runerror(ls.L, "C stack overflow");
    }
}

fn leavelevel(ls: *llex.LexState) void {
    ls.level -= 1;
}

fn block_follow(ls: *llex.LexState, withuntil: bool) bool {
    return switch (ls.t.token) {
        llex.TK_ELSE, llex.TK_ELSEIF, llex.TK_END, llex.TK_EOS => true,
        llex.TK_UNTIL => withuntil,
        else => false,
    };
}

fn enterblock(fs: *FuncState, bl: *BlockCnt, isloop: u8) void {
    bl.isloop = isloop;
    bl.nactvar = @intCast(fs.nactvar);
    bl.firstlabel = @intCast(fs.ls.dyd.label.items.len);
    bl.firstgoto = @intCast(fs.ls.dyd.gt.items.len);
    bl.upval = 0;
    bl.insidetbc = if (fs.bl) |b| b.insidetbc else 0;
    bl.previous = fs.bl;
    fs.bl = bl;
}

fn leaveblock(fs: *FuncState) !void {
    const bl = fs.bl.?;
    const ls = fs.ls;
    const stklevel = reglevel(fs, bl.nactvar);
    if (bl.previous != null and bl.upval != 0) {
        _ = lcode.luaK_codeABC(fs, .CLOSE, stklevel, 0, 0);
    }
    fs.freereg = stklevel;
    removevars(fs, bl.nactvar);
    if (bl.isloop == 2) {
        try createlabel(ls, ls.brkn.?, 0, false);
    }
    try solvegotos(fs, bl);
    if (bl.previous == null) {
        if (bl.firstgoto < ls.dyd.gt.items.len) {
            try undefgoto(ls, &ls.dyd.gt.items[@intCast(bl.firstgoto)]);
        }
    }
    fs.bl = bl.previous;
}

fn block(ls: *llex.LexState) anyerror!void {
    const fs = ls.fs.?;
    var bl: BlockCnt = .{};
    enterblock(fs, &bl, 0);
    try statlist(ls);
    try leaveblock(fs);
}

fn statlist(ls: *llex.LexState) !void {
    while (!block_follow(ls, true)) {
        if (ls.t.token == llex.TK_RETURN) {
            try statement(ls);
            return;
        }
        try statement(ls);
    }
}

// ---------------------------------------------------------------------------
// Goto / label machinery (also used by `break`)
// ---------------------------------------------------------------------------

fn findlabel(ls: *llex.LexState, name: *lua.lua_TString, ilb: i32) ?*llex.Labeldesc {
    var i = ilb;
    while (i < ls.dyd.label.items.len) : (i += 1) {
        if (eqstr(ls.dyd.label.items[@intCast(i)].name, name)) {
            return &ls.dyd.label.items[@intCast(i)];
        }
    }
    return null;
}

fn newlabelentry(ls: *llex.LexState, l: *std.ArrayList(llex.Labeldesc), name: *lua.lua_TString, line: i32, pc: i32) !i32 {
    const n = l.items.len;
    try l.append(ls.L.allocator, .{
        .name = name,
        .line = line,
        .nactvar = @intCast(ls.fs.?.nactvar),
        .close = 0,
        .pc = pc,
    });
    return @intCast(n);
}

fn newgotoentry(ls: *llex.LexState, name: *lua.lua_TString, line: i32) !i32 {
    const fs = ls.fs.?;
    const pc = lcode.luaK_jump(fs);
    _ = lcode.luaK_codeABC(fs, .CLOSE, 0, 1, 0);
    return try newlabelentry(ls, &ls.dyd.gt, name, line, pc);
}

fn jumpscopeerror(ls: *llex.LexState, gt: *llex.Labeldesc) !void {
    const tsname = getlocalvardesc(ls.fs.?, gt.nactvar).name;
    const varname = if (tsname) |ts| ts.s else "*";
    const gtname = if (gt.name) |gn| gn.s else "";
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "<goto {s}> at line {d} jumps into the scope of '{s}'", .{ gtname, gt.line, varname }) catch "<goto> jumps into the scope of a local variable";
    try lcode.luaK_semerror(ls, msg);
}

fn closegoto(ls: *llex.LexState, g: i32, label: *llex.Labeldesc, bup: u8) !void {
    const fs = ls.fs.?;
    const gl = &ls.dyd.gt;
    const gt = &gl.items[@intCast(g)];
    std.debug.assert(eqstr(gt.name, label.name));
    if (gt.nactvar < label.nactvar) try jumpscopeerror(ls, gt);
    if (gt.close != 0 or (label.nactvar < gt.nactvar and bup != 0)) {
        const stklevel = reglevel(fs, label.nactvar);
        fs.code.items[@intCast(gt.pc + 1)] = fs.code.items[@intCast(gt.pc)];
        fs.code.items[@intCast(gt.pc)] = lvm.CREATE_ABCk(.CLOSE, stklevel, 0, 0, 0);
        gt.pc += 1;
    }
    try lcode.luaK_patchlist(fs, gt.pc, label.pc);
    var i = g;
    while (i < gl.items.len - 1) : (i += 1) {
        gl.items[@intCast(i)] = gl.items[@intCast(i + 1)];
    }
    gl.items.len -= 1;
}

fn solvegotos(fs: *FuncState, bl: *BlockCnt) !void {
    const ls = fs.ls;
    const gl = &ls.dyd.gt;
    const outlevel = reglevel(fs, bl.nactvar);
    var igt = bl.firstgoto;
    while (igt < gl.items.len) {
        const gt = &gl.items[@intCast(igt)];
        const lb = findlabel(ls, gt.name.?, bl.firstlabel);
        if (lb != null) {
            try closegoto(ls, igt, lb.?, bl.upval);
        } else {
            if (bl.upval != 0 and reglevel(fs, gt.nactvar) > outlevel) gt.close = 1;
            gt.nactvar = bl.nactvar;
            igt += 1;
        }
    }
    ls.dyd.label.items.len = @intCast(bl.firstlabel);
}

fn createlabel(ls: *llex.LexState, name: *lua.lua_TString, line: i32, last: bool) !void {
    const fs = ls.fs.?;
    const ll = &ls.dyd.label;
    const l = try newlabelentry(ls, ll, name, line, lcode.luaK_getlabel(fs));
    if (last) ll.items[@intCast(l)].nactvar = fs.bl.?.nactvar;
}

fn undefgoto(ls: *llex.LexState, gt: *llex.Labeldesc) !void {
    std.debug.assert(!eqstr(gt.name, ls.brkn));
    const gtname = if (gt.name) |gn| gn.s else "";
    var buf: [256]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, "no visible label '{s}' for <goto> at line {d}", .{ gtname, gt.line }) catch "no visible label for <goto>";
    try lcode.luaK_semerror(ls, msg);
}

fn checkrepeated(ls: *llex.LexState, name: *lua.lua_TString) !void {
    const lb = findlabel(ls, name, ls.fs.?.firstlabel);
    if (lb) |l| {
        var buf: [256]u8 = undefined;
        const msg = std.fmt.bufPrint(&buf, "label '{s}' already defined on line {d}", .{ name.s, l.line }) catch "label already defined";
        try lcode.luaK_semerror(ls, msg);
    }
}

fn labelstat(ls: *llex.LexState, name: *lua.lua_TString, line: i32) !void {
    try checknext(ls, llex.TK_DBCOLON);
    while (ls.t.token == ';' or ls.t.token == llex.TK_DBCOLON) {
        try statement(ls);
    }
    try checkrepeated(ls, name);
    try createlabel(ls, name, line, block_follow(ls, false));
}

fn gotostat(ls: *llex.LexState, line: i32) !void {
    const name = try str_checkname(ls);
    _ = try newgotoentry(ls, name, line);
}

fn breakstat(ls: *llex.LexState, line: i32) !void {
    var bl: ?*BlockCnt = ls.fs.?.bl;
    while (bl != null) {
        if (bl.?.isloop != 0) break;
        bl = bl.?.previous;
    } else {
        return llex.luaX_syntaxerror(ls, "break outside loop");
    }
    bl.?.isloop = 2;
    try llex.luaX_next(ls);
    _ = try newgotoentry(ls, ls.brkn.?, line);
}

// ---------------------------------------------------------------------------
// Prototypes / functions
// ---------------------------------------------------------------------------

fn addprototype(ls: *llex.LexState) !*lua.lua_Proto {
    const fs = ls.fs.?;
    const f = try lua.createProto(ls.L.allocator);
    try lua.registerGC(ls.L, f);
    if (ls.anchor_tab) |tab| {
        try ltable.set(tab, .{ .proto = f }, .{ .boolean = true });
    }
    try fs.p.append(ls.L.allocator, f);
    return f;
}

fn codeclosure(ls: *llex.LexState, e: *expdesc) !void {
    const parent = ls.fs.?.prev.?;
    init_exp(e, .VRELOC, lcode.luaK_codeABx(parent, .CLOSURE, 0, @as(i32, @intCast(parent.p.items.len)) - 1));
    try lcode.luaK_exp2nextreg(parent, e);
}

fn open_func(ls: *llex.LexState, fs: *FuncState, bl: *BlockCnt) !void {
    const f = fs.f;
    fs.prev = ls.fs;
    fs.ls = ls;
    ls.fs = fs;
    fs.lasttarget = 0;
    fs.previousline = f.lineDefined;
    fs.iwthabs = 0;
    fs.freereg = 0;
    fs.nlocvars = 0;
    fs.nabslineinfo = 0;
    fs.nactvar = 0;
    fs.needclose = false;
    fs.firstlocal = @intCast(ls.dyd.actvar.items.len);
    fs.firstlabel = @intCast(ls.dyd.label.items.len);
    fs.bl = null;
    f.source = ls.source;
    f.maxStackSize = 2;
    fs.code = .empty;
    fs.k = .empty;
    fs.lineinfo = .empty;
    fs.abslineinfo = .empty;
    fs.p = .empty;
    fs.upvalues = .empty;
    fs.locvars = .empty;
    enterblock(fs, bl, 0);
}

fn close_func(ls: *llex.LexState) !void {
    const fs = ls.fs orelse return;
    defer ls.fs = fs.prev;
    const f = fs.f;
    try lcode.luaK_ret(fs, luaY_nvarstack(fs), 0);
    try leaveblock(fs);
    std.debug.assert(fs.bl == null);
    try lcode.luaK_finish(fs);

    const alloc = ls.L.allocator;
    errdefer {
        fs.code.deinit(alloc);
        fs.k.deinit(alloc);
        fs.lineinfo.deinit(alloc);
        fs.abslineinfo.deinit(alloc);
        fs.p.deinit(alloc);
        fs.upvalues.deinit(alloc);
        fs.locvars.deinit(alloc);
    }
    f.code = try fs.code.toOwnedSlice(alloc);
    f.k = try fs.k.toOwnedSlice(alloc);
    f.lineinfo = try fs.lineinfo.toOwnedSlice(alloc);
    f.abslineinfo = try fs.abslineinfo.toOwnedSlice(alloc);
    f.p = try fs.p.toOwnedSlice(alloc);
    f.upvalues = try fs.upvalues.toOwnedSlice(alloc);
    f.locvars = try fs.locvars.toOwnedSlice(alloc);
    f.isVarArg = (f.flag & (PF_VAHID | PF_VATAB)) != 0;
}

fn setvararg(fs: *FuncState) void {
    fs.f.isVarArg = true;
    if ((fs.f.flag & PF_VATAB) == 0) {
        fs.f.flag |= PF_VAHID;
    }
    _ = lcode.luaK_codeABC(fs, .VARARGPREP, 0, 0, 0);
}

fn body(ls: *llex.LexState, e: *expdesc, ismethod: bool, line: i32) !void {
    var new_fs: FuncState = .{};
    errdefer cleanupFuncState(&new_fs, ls.L.allocator);
    var bl: BlockCnt = .{};
    new_fs.f = try addprototype(ls);
    new_fs.f.lineDefined = line;
    try open_func(ls, &new_fs, &bl);
    try checknext(ls, '(');
    if (ismethod) {
        _ = try new_localvarliteral(ls, "self");
        try adjustlocalvars(ls, 1);
    }
    try parlist(ls);
    try checknext(ls, ')');
    try statlist(ls);
    new_fs.f.lastLineDefined = ls.linenumber;
    try check_match(ls, llex.TK_END, llex.TK_FUNCTION, line);
    try codeclosure(ls, e);
    try close_func(ls);
}

fn parlist(ls: *llex.LexState) !void {
    const fs = ls.fs.?;
    const f = fs.f;
    var nparams: i32 = 0;
    var varargk: i32 = 0;
    if (ls.t.token != ')') {
        while (true) {
            switch (ls.t.token) {
                llex.TK_NAME => {
                    _ = try new_localvar(ls, try str_checkname(ls));
                    nparams += 1;
                },
                llex.TK_DOTS => {
                    varargk = 1;
                    try llex.luaX_next(ls);
                    if (ls.t.token == llex.TK_NAME) {
                        // Declare the named vararg parameter. The vararg table
                        // (PF_VATAB) is chosen lazily (luaK_vapar2local /
                        // needvatab) only when the parameter is used as a
                        // value; indexing it (`v[k]`, `v.n`) uses OP_GETVARG
                        // with hidden arguments, like the reference.
                        _ = try new_varkind(ls, try str_checkname(ls), RDKVAVAR);
                    } else {
                        _ = try new_localvarliteral(ls, "(vararg table)");
                    }
                },
                else => {
                    return llex.luaX_syntaxerror(ls, "<name> or '...' expected");
                },
            }
            if (varargk != 0 or !(try testnext(ls, ','))) break;
        }
    }
    try adjustlocalvars(ls, nparams);
    f.numParams = @intCast(fs.nactvar);
    if (varargk != 0) {
        setvararg(fs);
        try adjustlocalvars(ls, 1);
    }
    try lcode.luaK_reserveregs(fs, fs.nactvar);
}

// ---------------------------------------------------------------------------
// Constructors
// ---------------------------------------------------------------------------

fn maxtostore(fs: *FuncState) i32 {
    const numfreeregs = lvm.MAX_FSTACK - fs.freereg;
    if (numfreeregs >= 160) return @divTrunc(numfreeregs, 5);
    if (numfreeregs >= 80) return 10;
    return 1;
}

fn constructor(ls: *llex.LexState, t: *expdesc) !void {
    const fs = ls.fs.?;
    const line = ls.linenumber;
    const pc = lcode.luaK_codevABCk(fs, .NEWTABLE, 0, 0, 0, 0);
    var cc: ConsControl = undefined;
    _ = try lcode.luaK_code(fs, 0);
    cc.na = 0;
    cc.nh = 0;
    cc.tostore = 0;
    cc.t = t;
    init_exp(t, .VNONRELOC, fs.freereg);
    try lcode.luaK_reserveregs(fs, 1);
    init_exp(&cc.v, .VVOID, 0);
    try checknext(ls, '{');
    cc.maxtostore = maxtostore(fs);
    while (true) {
        if (ls.t.token == '}') break;
        if (cc.v.k != .VVOID) try closelistfield(fs, &cc);
        try field(ls, &cc);
        try luaY_checklimit(fs, cc.tostore + cc.na + cc.nh, MAX_CNST, "items in a constructor");
        if (!(try testnext(ls, ',')) and !(try testnext(ls, ';'))) break;
    }
    try check_match(ls, '}', '{', line);
    try lastlistfield(fs, &cc);
    lcode.luaK_settablesize(fs, pc, t.u.info, cc.na, cc.nh);
}

fn closelistfield(fs: *FuncState, cc: *ConsControl) !void {
    std.debug.assert(cc.tostore > 0);
    try lcode.luaK_exp2nextreg(fs, &cc.v);
    cc.v.k = .VVOID;
    if (cc.tostore >= cc.maxtostore) {
        lcode.luaK_setlist(fs, cc.t.u.info, cc.na, cc.tostore);
        cc.na += cc.tostore;
        cc.tostore = 0;
    }
}

fn lastlistfield(fs: *FuncState, cc: *ConsControl) !void {
    if (cc.tostore == 0) return;
    if (hasmultret(cc.v.k)) {
        try luaK_setmultret(fs, &cc.v);
        lcode.luaK_setlist(fs, cc.t.u.info, cc.na, lua.LUA_MULTRET);
        cc.na -= 1;
    } else {
        if (cc.v.k != .VVOID) try lcode.luaK_exp2nextreg(fs, &cc.v);
        lcode.luaK_setlist(fs, cc.t.u.info, cc.na, cc.tostore);
    }
    cc.na += cc.tostore;
}

fn field(ls: *llex.LexState, cc: *ConsControl) !void {
    switch (ls.t.token) {
        llex.TK_NAME => {
            if (try llex.luaX_lookahead(ls) != '=') {
                try listfield(ls, cc);
            } else {
                try recfield(ls, cc);
            }
        },
        '[' => try recfield(ls, cc),
        else => try listfield(ls, cc),
    }
}

fn recfield(ls: *llex.LexState, cc: *ConsControl) !void {
    const fs = ls.fs.?;
    const reg = fs.freereg;
    var tab: expdesc = undefined;
    var key: expdesc = undefined;
    var val: expdesc = undefined;
    if (ls.t.token == llex.TK_NAME) {
        try codename(ls, &key);
    } else {
        try yindex(ls, &key);
    }
    cc.nh += 1;
    try checknext(ls, '=');
    tab = cc.t.*;
    try lcode.luaK_indexed(fs, &tab, &key);
    try expr(ls, &val);
    try lcode.luaK_storevar(fs, &tab, &val);
    fs.freereg = reg;
}

fn listfield(ls: *llex.LexState, cc: *ConsControl) !void {
    try expr(ls, &cc.v);
    cc.tostore += 1;
}

fn yindex(ls: *llex.LexState, v: *expdesc) !void {
    try llex.luaX_next(ls);
    try expr(ls, v);
    try lcode.luaK_exp2val(ls.fs.?, v);
    try checknext(ls, ']');
}

// ---------------------------------------------------------------------------
// Expression parsing
// ---------------------------------------------------------------------------

fn primaryexp(ls: *llex.LexState, v: *expdesc) !void {
    switch (ls.t.token) {
        '(' => {
            const line = ls.linenumber;
            try llex.luaX_next(ls);
            try expr(ls, v);
            try check_match(ls, ')', '(', line);
            lcode.luaK_dischargevars(ls.fs.?, v);
        },
        llex.TK_NAME => try singlevar(ls, v),
        else => {
            return llex.luaX_syntaxerror(ls, "unexpected symbol");
        },
    }
}

fn fieldsel(ls: *llex.LexState, v: *expdesc) !void {
    const fs = ls.fs.?;
    var key: expdesc = undefined;
    try lcode.luaK_exp2anyregup(fs, v);
    try llex.luaX_next(ls);
    try codename(ls, &key);
    try lcode.luaK_indexed(fs, v, &key);
}

fn suffixedexp(ls: *llex.LexState, v: *expdesc) !void {
    const fs = ls.fs.?;
    try primaryexp(ls, v);
    while (true) {
        switch (ls.t.token) {
            '.' => try fieldsel(ls, v),
            '[' => {
                var key: expdesc = undefined;
                try lcode.luaK_exp2anyregup(fs, v);
                try yindex(ls, &key);
                try lcode.luaK_indexed(fs, v, &key);
            },
            ':' => {
                var key: expdesc = undefined;
                try llex.luaX_next(ls);
                try codename(ls, &key);
                try lcode.luaK_self(fs, v, &key);
                try funcargs(ls, v);
            },
            '(', llex.TK_STRING, '{' => {
                try lcode.luaK_exp2nextreg(fs, v);
                try funcargs(ls, v);
            },
            else => return,
        }
    }
}

fn simpleexp(ls: *llex.LexState, v: *expdesc) anyerror!void {
    switch (ls.t.token) {
        llex.TK_FLT => {
            init_exp(v, .VKFLT, 0);
            v.u = .{ .nval = ls.t.seminfo.r };
        },
        llex.TK_INT => {
            init_exp(v, .VKINT, 0);
            v.u = .{ .ival = ls.t.seminfo.i };
        },
        llex.TK_STRING => {
            codestring(v, ls.t.seminfo.ts);
        },
        llex.TK_NIL => {
            init_exp(v, .VNIL, 0);
        },
        llex.TK_TRUE => {
            init_exp(v, .VTRUE, 0);
        },
        llex.TK_FALSE => {
            init_exp(v, .VFALSE, 0);
        },
        llex.TK_DOTS => {
            const fs = ls.fs.?;
            try check_condition(ls, isvararg(fs.f), "cannot use '...' outside a vararg function");
            init_exp(v, .VVARARG, lcode.luaK_codeABC(fs, .VARARG, 0, fs.f.numParams, 1));
        },
        '{' => {
            try constructor(ls, v);
            return;
        },
        llex.TK_FUNCTION => {
            try llex.luaX_next(ls);
            try body(ls, v, false, ls.linenumber);
            return;
        },
        else => {
            try suffixedexp(ls, v);
            return;
        },
    }
    try llex.luaX_next(ls);
}

fn getunopr(op: i32) UnOpr {
    return switch (op) {
        llex.TK_NOT => .OPR_NOT,
        '-' => .OPR_MINUS,
        '~' => .OPR_BNOT,
        '#' => .OPR_LEN,
        else => .OPR_NOUNOPR,
    };
}

fn getbinopr(op: i32) BinOpr {
    return switch (op) {
        '+' => .OPR_ADD,
        '-' => .OPR_SUB,
        '*' => .OPR_MUL,
        '%' => .OPR_MOD,
        '^' => .OPR_POW,
        '/' => .OPR_DIV,
        llex.TK_IDIV => .OPR_IDIV,
        '&' => .OPR_BAND,
        '|' => .OPR_BOR,
        '~' => .OPR_BXOR,
        llex.TK_SHL => .OPR_SHL,
        llex.TK_SHR => .OPR_SHR,
        llex.TK_CONCAT => .OPR_CONCAT,
        llex.TK_NE => .OPR_NE,
        llex.TK_EQ => .OPR_EQ,
        '<' => .OPR_LT,
        llex.TK_LE => .OPR_LE,
        '>' => .OPR_GT,
        llex.TK_GE => .OPR_GE,
        llex.TK_AND => .OPR_AND,
        llex.TK_OR => .OPR_OR,
        else => .OPR_NOBINOPR,
    };
}

fn subexpr(ls: *llex.LexState, v: *expdesc, limit: i32) anyerror!BinOpr {
    try enterlevel(ls);
    defer leavelevel(ls);
    var op: BinOpr = undefined;
    const uop = getunopr(ls.t.token);
    if (uop != .OPR_NOUNOPR) {
        const line = ls.linenumber;
        try llex.luaX_next(ls);
        _ = try subexpr(ls, v, UNARY_PRIORITY);
        try lcode.luaK_prefix(ls.fs.?, uop, v, line);
    } else {
        try simpleexp(ls, v);
    }
    op = getbinopr(ls.t.token);
    while (op != .OPR_NOBINOPR and priority[@intFromEnum(op)].left > limit) {
        var v2: expdesc = undefined;
        var nextop: BinOpr = undefined;
        const line = ls.linenumber;
        try llex.luaX_next(ls);
        try lcode.luaK_infix(ls.fs.?, op, v);
        nextop = try subexpr(ls, &v2, priority[@intFromEnum(op)].right);
        try lcode.luaK_posfix(ls.fs.?, op, v, &v2, line);
        op = nextop;
    }
    return op;
}

fn expr(ls: *llex.LexState, v: *expdesc) anyerror!void {
    _ = try subexpr(ls, v, 0);
}

// ---------------------------------------------------------------------------
// Statements
// ---------------------------------------------------------------------------

fn explist(ls: *llex.LexState, v: *expdesc) !i32 {
    var n: i32 = 1;
    try expr(ls, v);
    while (try testnext(ls, ',')) {
        try lcode.luaK_exp2nextreg(ls.fs.?, v);
        try expr(ls, v);
        n += 1;
    }
    return n;
}

fn funcargs(ls: *llex.LexState, f: *expdesc) !void {
    const fs = ls.fs.?;
    var args: expdesc = undefined;
    var base: i32 = undefined;
    var nparams: i32 = undefined;
    const line = ls.linenumber;
    switch (ls.t.token) {
        '(' => {
            try llex.luaX_next(ls);
            if (ls.t.token == ')') {
                args.k = .VVOID;
            } else {
                _ = try explist(ls, &args);
                if (hasmultret(args.k)) try luaK_setmultret(fs, &args);
            }
            try check_match(ls, ')', '(', line);
        },
        '{' => try constructor(ls, &args),
        llex.TK_STRING => {
            codestring(&args, ls.t.seminfo.ts);
            try llex.luaX_next(ls);
        },
        else => return llex.luaX_syntaxerror(ls, "function arguments expected"),
    }
    std.debug.assert(f.k == .VNONRELOC);
    base = f.u.info;
    if (hasmultret(args.k)) {
        nparams = lua.LUA_MULTRET;
    } else {
        if (args.k != .VVOID) try lcode.luaK_exp2nextreg(fs, &args);
        nparams = fs.freereg - (base + 1);
    }
    init_exp(f, .VCALL, lcode.luaK_codeABC(fs, .CALL, base, nparams + 1, 2));
    lcode.luaK_fixline(fs, line);
    fs.freereg = @intCast(base + 1);
}

fn adjust_assign(ls: *llex.LexState, nvars: i32, nexps: i32, e: *expdesc) !void {
    const fs = ls.fs.?;
    const needed = nvars - nexps;
    if (needed > 0) try lcode.luaK_checkstack(fs, needed);
    if (hasmultret(e.k)) {
        var extra = needed + 1;
        if (extra < 0) extra = 0;
        try lcode.luaK_setreturns(fs, e, extra);
    } else {
        if (e.k != .VVOID) try lcode.luaK_exp2nextreg(fs, e);
        if (needed > 0) lcode.luaK_nil(fs, fs.freereg, needed);
    }
    if (needed > 0) {
        try lcode.luaK_reserveregs(fs, needed);
    } else {
        fs.freereg = fs.freereg + needed;
    }
}

fn storevartop(fs: *FuncState, vp: *expdesc) !void {
    var e: expdesc = undefined;
    init_exp(&e, .VNONRELOC, fs.freereg - 1);
    try lcode.luaK_storevar(fs, vp, &e);
}

fn check_conflict(ls: *llex.LexState, lh: *LHS_assign, v: *expdesc) !void {
    const fs = ls.fs.?;
    const extra: u8 = @intCast(fs.freereg);
    var conflict: i32 = 0;
    var cur: ?*LHS_assign = lh;
    while (cur != null) : (cur = cur.?.prev) {
        if (vkisindexed(cur.?.v.k)) {
            if (cur.?.v.k == .VINDEXUP) {
                if (v.k == .VUPVAL and cur.?.v.u.ind.t == v.u.info) {
                    conflict = 1;
                    cur.?.v.k = .VINDEXSTR;
                    cur.?.v.u.ind.t = extra;
                }
            } else {
                if (v.k == .VLOCAL and cur.?.v.u.ind.t == v.u.uv.ridx) {
                    conflict = 1;
                    cur.?.v.u.ind.t = extra;
                }
                if (cur.?.v.k == .VINDEXED and v.k == .VLOCAL and cur.?.v.u.ind.idx == v.u.uv.ridx) {
                    conflict = 1;
                    cur.?.v.u.ind.idx = extra;
                }
            }
        }
    }
    if (conflict != 0) {
        if (v.k == .VLOCAL) {
            _ = lcode.luaK_codeABC(fs, .MOVE, extra, v.u.uv.ridx, 0);
        } else {
            _ = lcode.luaK_codeABC(fs, .GETUPVAL, extra, v.u.info, 0);
        }
        try lcode.luaK_reserveregs(fs, 1);
    }
}

fn restassign(ls: *llex.LexState, lh: *LHS_assign, nvars: i32) !void {
    var e: expdesc = undefined;
    try check_condition(ls, vkisvar(lh.v.k), "syntax error");
    try check_readonly(ls, &lh.v);
    if (try testnext(ls, ',')) {
        var nv: LHS_assign = undefined;
        nv.prev = lh;
        try suffixedexp(ls, &nv.v);
        if (!vkisindexed(nv.v.k)) try check_conflict(ls, lh, &nv.v);
        try enterlevel(ls);
        try restassign(ls, &nv, nvars + 1);
        leavelevel(ls);
    } else {
        try checknext(ls, '=');
        const nexps = try explist(ls, &e);
        if (nexps != nvars) {
            try adjust_assign(ls, nvars, nexps, &e);
        } else {
            try lcode.luaK_setoneret(ls.fs.?, &e);
            try lcode.luaK_storevar(ls.fs.?, &lh.v, &e);
            return;
        }
    }
    try storevartop(ls.fs.?, &lh.v);
}

fn cond(ls: *llex.LexState) !i32 {
    var v: expdesc = undefined;
    try expr(ls, &v);
    if (v.k == .VNIL) v.k = .VFALSE;
    try lcode.luaK_goiftrue(ls.fs.?, &v);
    return v.f;
}

fn exprstat(ls: *llex.LexState) !void {
    const fs = ls.fs.?;
    var v: LHS_assign = undefined;
    try suffixedexp(ls, &v.v);
    if (ls.t.token == '=' or ls.t.token == ',') {
        v.prev = null;
        try restassign(ls, &v, 1);
    } else {
        // Bare function-call statement. The reference checks the expdesc
        // kind *before* reading the instruction (see `luaK_setoneret`), so
        // guard the `getinstruction` (`u.info`) access with the kind check to
        // avoid touching `u.ind` for non-call expressions.
        try check_condition(ls, v.v.k == .VCALL, "syntax error");
        const inst = getinstruction(fs, &v.v);
        lvm.SETARG_C(inst, 1);
    }
}

fn retstat(ls: *llex.LexState) !void {
    const fs = ls.fs.?;
    var e: expdesc = undefined;
    var nret: i32 = 0;
    var first: i32 = luaY_nvarstack(fs);
    if (block_follow(ls, true) or ls.t.token == ';') {
        nret = 0;
    } else {
        nret = try explist(ls, &e);
        if (hasmultret(e.k)) {
            try luaK_setmultret(fs, &e);
            if (e.k == .VCALL and nret == 1 and
                (if (fs.bl) |b| b.insidetbc == 0 else true)) {
                lvm.SET_OPCODE(getinstruction(fs, &e), .TAILCALL);
                std.debug.assert(lvm.GETARG_A(getinstruction(fs, &e).*) == luaY_nvarstack(fs));
            }
            nret = lua.LUA_MULTRET;
        } else {
            if (nret == 1) {
                first = try lcode.luaK_exp2anyreg(fs, &e);
            } else {
                try lcode.luaK_exp2nextreg(fs, &e);
                std.debug.assert(nret == fs.freereg - first);
            }
        }
    }
    try lcode.luaK_ret(fs, first, nret);
    _ = try testnext(ls, ';');
}

fn initglobal(ls: *llex.LexState, nvars: i32, firstidx: i32, n: i32, line: i32) !void {
    if (n == nvars) {
        var e: expdesc = undefined;
        const nexps = try explist(ls, &e);
        try adjust_assign(ls, nvars, nexps, &e);
    } else {
        const fs = ls.fs.?;
        var var_: expdesc = undefined;
        const vardesc = getlocalvardesc(fs, firstidx + n);
        const gname = vardesc.name orelse return;
        try buildglobal(ls, gname, &var_);
        try enterlevel(ls);
        try initglobal(ls, nvars, firstidx, n + 1, line);
        leavelevel(ls);
        try checkglobal(ls, gname, line);
        try storevartop(fs, &var_);
    }
}

fn globalnames(ls: *llex.LexState, defkind: u8) !void {
    const fs = ls.fs.?;
    var nvars: i32 = 0;
    var lastidx: i32 = 0;
    while (true) {
        const vname = try str_checkname(ls);
        const kind = try getglobalattribute(ls, defkind);
        lastidx = try new_varkind(ls, vname, kind);
        nvars += 1;
        if (!(try testnext(ls, ','))) break;
    }
    if (try testnext(ls, '=')) {
        try initglobal(ls, nvars, lastidx - nvars + 1, 0, ls.linenumber);
    }
    fs.nactvar = @intCast(fs.nactvar + nvars);
}

fn globalstat(ls: *llex.LexState) !void {
    const fs = ls.fs.?;
    const defkind = try getglobalattribute(ls, GDKREG);
    if (!(try testnext(ls, '*'))) {
        try globalnames(ls, defkind);
    } else {
        _ = try new_varkind(ls, null, defkind);
        fs.nactvar += 1;
    }
}

fn globalfunc(ls: *llex.LexState, line: i32) !void {
    const fs = ls.fs.?;
    var var_: expdesc = undefined;
    var b: expdesc = undefined;
    const fname = try str_checkname(ls);
    _ = try new_varkind(ls, fname, GDKREG);
    fs.nactvar += 1;
    try buildglobal(ls, fname, &var_);
    try body(ls, &b, false, ls.linenumber);
    try checkglobal(ls, fname, line);
    try lcode.luaK_storevar(fs, &var_, &b);
    lcode.luaK_fixline(fs, line);
}

fn globalstatfunc(ls: *llex.LexState, line: i32) !void {
    try llex.luaX_next(ls);
    if (try testnext(ls, llex.TK_FUNCTION)) {
        try globalfunc(ls, line);
    } else {
        try globalstat(ls);
    }
}

fn ifstat(ls: *llex.LexState, line: i32) !void {
    const fs = ls.fs.?;
    var escapelist: i32 = NO_JUMP;
    try test_then_block(ls, &escapelist);
    while (ls.t.token == llex.TK_ELSEIF) {
        try test_then_block(ls, &escapelist);
    }
    if (try testnext(ls, llex.TK_ELSE)) try block(ls);
    try check_match(ls, llex.TK_END, llex.TK_IF, line);
    try lcode.luaK_patchtohere(fs, escapelist);
}

fn test_then_block(ls: *llex.LexState, escapelist: *i32) !void {
    const fs = ls.fs.?;
    var condtrue: i32 = undefined;
    try llex.luaX_next(ls);
    condtrue = try cond(ls);
    try checknext(ls, llex.TK_THEN);
    try block(ls);
    if (ls.t.token == llex.TK_ELSE or ls.t.token == llex.TK_ELSEIF) {
        try lcode.luaK_concat(fs, escapelist, lcode.luaK_jump(fs));
    }
    try lcode.luaK_patchtohere(fs, condtrue);
}

fn whilestat(ls: *llex.LexState, line: i32) !void {
    const fs = ls.fs.?;
    var bl: BlockCnt = .{};
    try llex.luaX_next(ls);
    const whileinit = lcode.luaK_getlabel(fs);
    const condexit = try cond(ls);
    enterblock(fs, &bl, 1);
    try checknext(ls, llex.TK_DO);
    try block(ls);
    try luaK_jumpto(fs, whileinit);
    try check_match(ls, llex.TK_END, llex.TK_WHILE, line);
    try leaveblock(fs);
    try lcode.luaK_patchtohere(fs, condexit);
}

fn repeatstat(ls: *llex.LexState, line: i32) !void {
    const fs = ls.fs.?;
    var bl1: BlockCnt = .{};
    var bl2: BlockCnt = .{};
    const repeat_init = lcode.luaK_getlabel(fs);
    enterblock(fs, &bl1, 1);
    enterblock(fs, &bl2, 0);
    try llex.luaX_next(ls);
    try statlist(ls);
    try check_match(ls, llex.TK_UNTIL, llex.TK_REPEAT, line);
    var condexit = try cond(ls);
    if (bl2.upval != 0) {
        const exit = lcode.luaK_jump(fs);
        try lcode.luaK_patchtohere(fs, condexit);
        _ = lcode.luaK_codeABC(fs, .CLOSE, reglevel(fs, bl2.nactvar), 0, 0);
        condexit = lcode.luaK_jump(fs);
        try lcode.luaK_patchtohere(fs, exit);
    }
    try lcode.luaK_patchlist(fs, condexit, repeat_init);
    try leaveblock(fs);
    try leaveblock(fs);
}

fn exp1(ls: *llex.LexState) !void {
    var e: expdesc = undefined;
    try expr(ls, &e);
    try lcode.luaK_exp2nextreg(ls.fs.?, &e);
    std.debug.assert(e.k == .VNONRELOC);
}

fn fixforjump(fs: *FuncState, pc: i32, dest: i32, back: i32) !void {
    const jmp = &fs.code.items[@intCast(pc)];
    var offset = dest - (pc + 1);
    if (back != 0) offset = -offset;
    if (offset > lvm.MAXARG_Bx) {
        return llex.luaX_syntaxerror(fs.ls, "control structure too long");
    }
    lvm.SETARG_Bx(jmp, offset);
}

fn forbody(ls: *llex.LexState, base: i32, line: i32, nvars: i32, isgen: i32) !void {
    const forprep = [_]lvm.OpCode{ .FORPREP, .TFORPREP };
    const forloop = [_]lvm.OpCode{ .FORLOOP, .TFORLOOP };
    var bl: BlockCnt = .{};
    const fs = ls.fs.?;
    try checknext(ls, llex.TK_DO);
    const prep = lcode.luaK_codeABx(fs, forprep[@intCast(isgen)], base, 0);
    fs.freereg -= 1;
    enterblock(fs, &bl, 0);
    try adjustlocalvars(ls, nvars);
    try lcode.luaK_reserveregs(fs, nvars);
    try block(ls);
    try leaveblock(fs);
    try fixforjump(fs, prep, lcode.luaK_getlabel(fs), 0);
    if (isgen != 0) {
        _ = lcode.luaK_codeABC(fs, .TFORCALL, base, 0, nvars);
        lcode.luaK_fixline(fs, line);
    }
    const endfor = lcode.luaK_codeABx(fs, forloop[@intCast(isgen)], base, 0);
    try fixforjump(fs, endfor, prep + 1, 1);
    lcode.luaK_fixline(fs, line);
}

fn fornum(ls: *llex.LexState, varname: *lua.lua_TString, line: i32) !void {
    const fs = ls.fs.?;
    const base = fs.freereg;
    _ = try new_localvarliteral(ls, "(for state)");
    _ = try new_localvarliteral(ls, "(for state)");
    _ = try new_varkind(ls, varname, LOOPVARKIND);
    try checknext(ls, '=');
    try exp1(ls);
    try checknext(ls, ',');
    try exp1(ls);
    if (try testnext(ls, ',')) {
        try exp1(ls);
    } else {
        lcode.luaK_int(fs, fs.freereg, 1);
        try lcode.luaK_reserveregs(fs, 1);
    }
    try adjustlocalvars(ls, 2);
    try forbody(ls, base, line, 1, 0);
}

fn forlist(ls: *llex.LexState, indexname: *lua.lua_TString) !void {
    const fs = ls.fs.?;
    var e: expdesc = undefined;
    var nvars: i32 = 4;
    const base = fs.freereg;
    _ = try new_localvarliteral(ls, "(for state)");
    _ = try new_localvarliteral(ls, "(for state)");
    _ = try new_localvarliteral(ls, "(for state)");
    _ = try new_varkind(ls, indexname, LOOPVARKIND);
    while (try testnext(ls, ',')) {
        _ = try new_localvar(ls, try str_checkname(ls));
        nvars += 1;
    }
    try checknext(ls, llex.TK_IN);
    // Mirror the reference: 'line' is the line of the iterator expression list
    // (the token just past 'in'), not the 'in' line, so loop instructions are
    // attributed to the expression that is actually evaluated/called.
    const line = ls.linenumber;
    const nexps = try explist(ls, &e);
    try adjust_assign(ls, 4, nexps, &e);
    try adjustlocalvars(ls, 3);
    marktobeclosed(fs);
    try lcode.luaK_checkstack(fs, 2);
    try forbody(ls, base, line, nvars - 3, 1);
}

fn forstat(ls: *llex.LexState, line: i32) !void {
    const fs = ls.fs.?;
    var bl: BlockCnt = .{};
    enterblock(fs, &bl, 1);
    try llex.luaX_next(ls);
    const varname = try str_checkname(ls);
    switch (ls.t.token) {
        '=' => try fornum(ls, varname, line),
        ',', llex.TK_IN => try forlist(ls, varname),
        else => return llex.luaX_syntaxerror(ls, "'=' or 'in' expected"),
    }
    try check_match(ls, llex.TK_END, llex.TK_FOR, line);
    try leaveblock(fs);
}

fn localfunc(ls: *llex.LexState) !void {
    const fs = ls.fs.?;
    const fvar = fs.nactvar;
    _ = try new_localvar(ls, try str_checkname(ls));
    try adjustlocalvars(ls, 1);
    var b: expdesc = undefined;
    try body(ls, &b, false, ls.linenumber);
    const info = localdebuginfo(fs, fvar) orelse return;
    info.startpc = @intCast(fs.code.items.len);
}

fn getvarattribute(ls: *llex.LexState, df: u8) !u8 {
    if (try testnext(ls, '<')) {
        const ts = try str_checkname(ls);
        try checknext(ls, '>');
        if (eqstr_str(ts, "const")) return RDKCONST;
        if (eqstr_str(ts, "close")) return RDKTOCLOSE;
        const msg = try std.fmt.allocPrint(ls.L.allocator, "unknown attribute '{s}'", .{ts.s});
        defer ls.L.allocator.free(msg);
        try lcode.luaK_semerror(ls, msg);
    }
    return df;
}

fn getglobalattribute(ls: *llex.LexState, df: u8) !u8 {
    const kind = try getvarattribute(ls, df);
    if (kind == RDKTOCLOSE) {
        try lcode.luaK_semerror(ls, "global variables cannot be to-be-closed");
        return undefined;
    }
    if (kind == RDKCONST) {
        return GDKCONST;
    }
    return kind;
}

fn checktoclose(fs: *FuncState, level: i32) !void {
    if (level != -1) {
        marktobeclosed(fs);
        _ = lcode.luaK_codeABC(fs, .TBC, reglevel(fs, level), 0, 0);
    }
}

fn localstat(ls: *llex.LexState) !void {
    const fs = ls.fs.?;
    var toclose: i32 = -1;
    var vidx: i32 = undefined;
    var nvars: i32 = 0;
    var nexps: i32 = 0;
    var e: expdesc = undefined;
    const defkind = try getvarattribute(ls, VDKREG);
    while (true) {
        const vname = try str_checkname(ls);
        const kind = try getvarattribute(ls, defkind);
        if (kind == RDKCONST) {
            // compile-time constant attribute; no extra action here
        }
        vidx = try new_varkind(ls, vname, kind);
        if (kind == RDKTOCLOSE) {
            if (toclose != -1) try lcode.luaK_semerror(ls, "multiple to-be-closed variables");
            toclose = fs.nactvar + nvars;
        }
        nvars += 1;
        if (!(try testnext(ls, ','))) break;
    }
    if (try testnext(ls, '=')) {
        nexps = try explist(ls, &e);
    } else {
        e.k = .VVOID;
        nexps = 0;
    }
    const lastvar = getlocalvardesc(fs, vidx);
    if (nvars == nexps and lastvar.kind == RDKCONST and
        lcode.luaK_exp2const(fs, &e, &lastvar.val)) {
        lastvar.kind = RDKCTC;
        try adjustlocalvars(ls, nvars - 1);
        fs.nactvar += 1;
    } else {
        try adjust_assign(ls, nvars, nexps, &e);
        try adjustlocalvars(ls, nvars);
    }
    try checktoclose(fs, toclose);
}

fn funcname(ls: *llex.LexState, v: *expdesc) !i32 {
    var ismethod: i32 = 0;
    try singlevar(ls, v);
    while (ls.t.token == '.') try fieldsel(ls, v);
    if (ls.t.token == ':') {
        ismethod = 1;
        try fieldsel(ls, v);
    }
    return ismethod;
}

fn funcstat(ls: *llex.LexState, line: i32) !void {
    var v: expdesc = undefined;
    var b: expdesc = undefined;
    try llex.luaX_next(ls);
    const ismethod = try funcname(ls, &v);
    try check_readonly(ls, &v);
    try body(ls, &b, ismethod != 0, line);
    try lcode.luaK_storevar(ls.fs.?, &v, &b);
    lcode.luaK_fixline(ls.fs.?, line);
}

fn statement(ls: *llex.LexState) anyerror!void {
    const line = ls.linenumber;
    try enterlevel(ls);
    switch (ls.t.token) {
        ';' => try llex.luaX_next(ls),
        llex.TK_IF => try ifstat(ls, line),
        llex.TK_GLOBAL => try globalstatfunc(ls, line),
        llex.TK_WHILE => try whilestat(ls, line),
        llex.TK_DO => {
            try llex.luaX_next(ls);
            try block(ls);
            try check_match(ls, llex.TK_END, llex.TK_DO, line);
        },
        llex.TK_FOR => try forstat(ls, line),
        llex.TK_REPEAT => try repeatstat(ls, line),
        llex.TK_FUNCTION => try funcstat(ls, line),
        llex.TK_LOCAL => {
            try llex.luaX_next(ls);
            if (try testnext(ls, llex.TK_FUNCTION)) {
                try localfunc(ls);
            } else {
                try localstat(ls);
            }
        },
        llex.TK_DBCOLON => {
            try llex.luaX_next(ls);
            try labelstat(ls, try str_checkname(ls), line);
        },
        llex.TK_RETURN => {
            try llex.luaX_next(ls);
            try retstat(ls);
        },
        llex.TK_BREAK => try breakstat(ls, line),
        llex.TK_GOTO => {
            try llex.luaX_next(ls);
            try gotostat(ls, line);
        },
        llex.TK_NAME => {
            if (luaconf.LUA_COMPAT_GLOBAL and eqstr(ls.t.seminfo.ts, ls.glbn)) {
                const lk = try llex.luaX_lookahead(ls);
                if (lk == '<' or lk == llex.TK_NAME or lk == '*' or lk == llex.TK_FUNCTION) {
                    try globalstatfunc(ls, line);
                } else {
                    try exprstat(ls);
                }
            } else {
                try exprstat(ls);
            }
        },
        else => try exprstat(ls),
    }
    const fs = ls.fs orelse return;
    std.debug.assert(fs.f.maxStackSize >= fs.freereg and fs.freereg >= luaY_nvarstack(fs));
    fs.freereg = luaY_nvarstack(fs);
    leavelevel(ls);
}

// ---------------------------------------------------------------------------
// Top level
// ---------------------------------------------------------------------------

fn mainfunc(ls: *llex.LexState, fs: *FuncState) !void {
    var bl: BlockCnt = .{};
    var env: *lua.Upvaldesc = undefined;
    try open_func(ls, fs, &bl);
    setvararg(fs);
    env = try allocupvalue(fs);
    env.instack = 1;
    env.idx = 0;
    env.kind = VDKREG;
    env.name = ls.envn.?;
    try llex.luaX_next(ls);
    try statlist(ls);
    try check(ls, llex.TK_EOS);
    try close_func(ls);
}

fn cleanupFuncState(fs: *FuncState, allocator: std.mem.Allocator) void {
    fs.code.deinit(allocator);
    fs.k.deinit(allocator);
    fs.lineinfo.deinit(allocator);
    fs.abslineinfo.deinit(allocator);
    fs.p.deinit(allocator);
    fs.upvalues.deinit(allocator);
    fs.locvars.deinit(allocator);
}

pub fn luaY_parser(L: *lua.lua_State, ls: *llex.LexState) !*lua.lua_Proto {
    var fs: FuncState = .{ .ls = ls, .f = try lua.createProto(L.allocator) };
    fs.f.source = ls.source;
    try lua.registerGC(L, fs.f);
    if (ls.anchor_tab) |tab| {
        try ltable.set(tab, .{ .proto = fs.f }, .{ .boolean = true });
    }
    errdefer {
        cleanupFuncState(&fs, L.allocator);
    }
    try mainfunc(ls, &fs);
    return fs.f;
}

pub fn luaD_protectedparser(
    L: *lua.lua_State,
    reader: lua.lua_Reader,
    dt: ?*anyopaque,
    chunkname: []const u8,
    first_slice: []const u8,
    is_eof: bool,
) !*lua.lua_Proto {
    L.noyield += 1; // cannot yield during parsing (mirrors the reference)
    defer L.noyield -= 1;
    const anchor_tab = try ltable.createTable(L.allocator, 0, 8);
    try lua.registerGC(L, anchor_tab);
    if (L.l_G) |g| {
        if (g.registry.table) |reg| {
            try ltable.set(reg, .{ .lightud = @ptrCast(anchor_tab) }, .{ .table = anchor_tab });
        }
    }
    defer {
        if (L.l_G) |g| {
            if (g.registry.table) |reg| {
                // BUG-100: best-effort cleanup on parser teardown; an error
                // here is non-fatal (the parser is already unwinding).
                _ = ltable.set(reg, .{ .lightud = @ptrCast(anchor_tab) }, .{ .nil = {} }) catch {};
            }
        }
    }
    var ls: llex.LexState = undefined;
    const source = try lstring.luaS_new(L, chunkname);
    try ltable.set(anchor_tab, .{ .string = source }, .{ .boolean = true });
    try llex.luaX_setinput(L, &ls, reader, dt, source, first_slice, is_eof);
    ls.anchor_tab = anchor_tab;
    if (ls.brkn) |brk| try ltable.set(anchor_tab, .{ .string = brk }, .{ .boolean = true });
    if (ls.envn) |env| try ltable.set(anchor_tab, .{ .string = env }, .{ .boolean = true });
    if (ls.glbn) |glb| try ltable.set(anchor_tab, .{ .string = glb }, .{ .boolean = true });
    errdefer {
        ls.buff.deinit(L.allocator);
        ls.dyd.deinit(L.allocator);
    }
    const f = luaY_parser(L, &ls) catch |err| {
        if (err == error.RuntimeError) {
            // The error object was already pushed by luaG_runerror (e.g. "C
            // stack overflow" from the parser recursion limit). Preserve it.
            return err;
        }
        if (ls.errmsg) |msg| {
            var short_src: [lua.LUA_IDSIZE]u8 = undefined;
            lua.luaO_chunkid(&short_src, chunkname);
            const len = std.mem.indexOfScalar(u8, &short_src, 0) orelse short_src.len;
            const src_str = short_src[0..len];
            var buf: [512]u8 = undefined;
            const formatted = std.fmt.bufPrint(&buf, "{s}:{d}: {s}", .{ src_str, ls.linenumber, msg }) catch msg;
            _ = lua.lua_pushstring(L, formatted);
        } else {
            _ = lua.lua_pushstring(L, "syntax error");
        }
        return err;
    };
    ls.buff.deinit(L.allocator);
    ls.dyd.deinit(L.allocator);
    return f;
}
