// $Id: llex.zig $
// Lexical Analyzer for Lua.zig (Zig port of Lua 5.5.0 llex.c / lzio.c)
// See Copyright Notice in lua.zig
//
// This is Phase G.1 of the source-text compiler. It turns a character stream
// (a `lua_Reader`) into a token stream. It mirrors the semantics of the C
// reference `llex.c` exactly, written in idiomatic Zig 0.16.0:
//   * The allocator and Lua state are threaded (no globals, no page_allocator).
//   * Every fallible operation propagates errors with `try` / `!T` — there is
//     no `catch {}` swallowing (BUG-002 / BUG-012 / BUG-025 / BUG-031).
//   * String interning goes through `lstring.luaS_new`, which already keeps a
//     single copy per unique string in `global_State.strt`.
//
// NOTE on ctype: the reference uses a 258-entry property table. We reproduce
// the *ASCII* semantics of that table (NONA = 0 build: high bytes are NOT
// alphabetic) directly with `std.ascii`-style predicates. This is exact for
// the LexState's needs and avoids a fragile hand transcription.

const std = @import("std");
const lua = @import("lua.zig");
const lobject = @import("lobject.zig");
const lstring = @import("lstring.zig");
const lparser = @import("lparser.zig");
const luaconf = @import("luaconf.zig");

const Allocator = std.mem.Allocator;

// ---------------------------------------------------------------------------
// Shared parser data structures (declared here so that `LexState` can carry a
// `Dyndata` pointer-free handle and `lcode.zig` can reach the active-variable
// descriptor list via `fs.ls.dyd.actvar`).
// ---------------------------------------------------------------------------

// Description of an active variable. The `val` field overlaps the compile-time
// constant value (mirrors the C `union Vardesc`).
pub const Vardesc = struct {
    val: lua.TValue = .{ .nil = {} },
    kind: u8 = 0,
    ridx: u8 = 0,
    pidx: i16 = 0,
    name: ?*lua.lua_TString = null,
};

pub const Labeldesc = struct {
    name: ?*lua.lua_TString = null,
    pc: i32 = 0,
    line: i32 = 0,
    nactvar: i16 = 0,
    close: u8 = 0,
};

pub const Dyndata = struct {
    actvar: std.ArrayList(Vardesc) = .empty,
    gt: std.ArrayList(Labeldesc) = .empty,
    label: std.ArrayList(Labeldesc) = .empty,

    pub fn deinit(self: *Dyndata, alloc: Allocator) void {
        self.actvar.deinit(alloc);
        self.gt.deinit(alloc);
        self.label.deinit(alloc);
    }
};

// End of stream sentinel (mirrors the C `EOZ = -1`).
const EOZ: i32 = -1;

// Maximum length of a single scanned lexical element. Past this we reject the
// input as "too long" instead of letting the buffer grow without bound.
const MAX_SIZE: usize = 1 << 26;

// ---------------------------------------------------------------------------
// Token identifiers
// ---------------------------------------------------------------------------
// Single-char tokens use their own ASCII code; other tokens start at
// FIRST_RESERVED (UCHAR_MAX + 1). These MUST stay in the same order as the C
// `enum RESERVED` so the future parser sees the same ids.
pub const FIRST_RESERVED: i32 = 257;

pub const TK_AND: i32 = 257;
pub const TK_BREAK: i32 = 258;
pub const TK_DO: i32 = 259;
pub const TK_ELSE: i32 = 260;
pub const TK_ELSEIF: i32 = 261;
pub const TK_END: i32 = 262;
pub const TK_FALSE: i32 = 263;
pub const TK_FOR: i32 = 264;
pub const TK_FUNCTION: i32 = 265;
pub const TK_GLOBAL: i32 = 266;
pub const TK_GOTO: i32 = 267;
pub const TK_IF: i32 = 268;
pub const TK_IN: i32 = 269;
pub const TK_LOCAL: i32 = 270;
pub const TK_NIL: i32 = 271;
pub const TK_NOT: i32 = 272;
pub const TK_OR: i32 = 273;
pub const TK_REPEAT: i32 = 274;
pub const TK_RETURN: i32 = 275;
pub const TK_THEN: i32 = 276;
pub const TK_TRUE: i32 = 277;
pub const TK_UNTIL: i32 = 278;
pub const TK_WHILE: i32 = 279;
pub const TK_IDIV: i32 = 280;
pub const TK_CONCAT: i32 = 281;
pub const TK_DOTS: i32 = 282;
pub const TK_EQ: i32 = 283;
pub const TK_GE: i32 = 284;
pub const TK_LE: i32 = 285;
pub const TK_NE: i32 = 286;
pub const TK_SHL: i32 = 287;
pub const TK_SHR: i32 = 288;
pub const TK_DBCOLON: i32 = 289;
pub const TK_EOS: i32 = 290;
pub const TK_FLT: i32 = 291;
pub const TK_INT: i32 = 292;
pub const TK_NAME: i32 = 293;
pub const TK_STRING: i32 = 294;

// Reserved-word table. Kept in the same order as the token ids above so a
// linear scan reproduces the reference's `isreserved`/reserved-word match.
const reserved_words = [_]struct { name: []const u8, tok: i32 }{
    .{ .name = "and", .tok = TK_AND },
    .{ .name = "break", .tok = TK_BREAK },
    .{ .name = "do", .tok = TK_DO },
    .{ .name = "else", .tok = TK_ELSE },
    .{ .name = "elseif", .tok = TK_ELSEIF },
    .{ .name = "end", .tok = TK_END },
    .{ .name = "false", .tok = TK_FALSE },
    .{ .name = "for", .tok = TK_FOR },
    .{ .name = "function", .tok = TK_FUNCTION },
    .{ .name = "global", .tok = TK_GLOBAL },
    .{ .name = "goto", .tok = TK_GOTO },
    .{ .name = "if", .tok = TK_IF },
    .{ .name = "in", .tok = TK_IN },
    .{ .name = "local", .tok = TK_LOCAL },
    .{ .name = "nil", .tok = TK_NIL },
    .{ .name = "not", .tok = TK_NOT },
    .{ .name = "or", .tok = TK_OR },
    .{ .name = "repeat", .tok = TK_REPEAT },
    .{ .name = "return", .tok = TK_RETURN },
    .{ .name = "then", .tok = TK_THEN },
    .{ .name = "true", .tok = TK_TRUE },
    .{ .name = "until", .tok = TK_UNTIL },
    .{ .name = "while", .tok = TK_WHILE },
};

// Quoted single-char token text (mirrors `luaX_token2str` for `token < FIRST_RESERVED`).
const quoted_chars = blk: {
    var arr: [256][3]u8 = undefined;
    for (0..256) |i| arr[i] = [3]u8{ '\'', @intCast(i), '\'' };
    break :blk arr;
};

// Quoted reserved-word text ('and', 'break', ...), one per entry of `reserved_words`.
const quoted_reserved = [_][]const u8{
    "'and'", "'break'", "'do'", "'else'", "'elseif'", "'end'", "'false'",
    "'for'", "'function'", "'global'", "'goto'", "'if'", "'in'", "'local'",
    "'nil'", "'not'", "'or'", "'repeat'", "'return'", "'then'", "'true'",
    "'until'", "'while'",
};

fn isReserved(name: []const u8) ?i32 {
    if (luaconf.LUA_COMPAT_GLOBAL and std.mem.eql(u8, name, "global")) return null;
    for (reserved_words) |r| {
        if (std.mem.eql(u8, r.name, name)) return r.tok;
    }
    return null;
}

// ---------------------------------------------------------------------------
// Error type
// ---------------------------------------------------------------------------
pub const LexError = error{SyntaxError};

// ---------------------------------------------------------------------------
// Semantic info attached to a token (mirrors the C `SemInfo` union).
// ---------------------------------------------------------------------------
pub const SemInfo = struct {
    i: i64 = 0,
    r: f64 = 0,
    ts: ?*lua.lua_TString = null,
};

// A scanned token.
pub const Token = struct {
    token: i32 = 0,
    seminfo: SemInfo = .{},
};

// ---------------------------------------------------------------------------
// Lexer state
// ---------------------------------------------------------------------------
pub const LexState = struct {
    allocator: Allocator,
    L: *lua.lua_State,
    dyd: Dyndata = .{},
    level: i32 = 0,
    brkn: ?*lua.lua_TString = null,
    envn: ?*lua.lua_TString = null,
    current: i32, // current character (char int) or EOZ
    linenumber: i32,
    lastline: i32,
    t: Token = .{},
    lookahead: Token = .{ .token = TK_EOS },
    reader: lua.lua_Reader,
    data: ?*anyopaque,
    // Input stream chunk currently being consumed.
    chunk: []const u8 = &[_]u8{},
    chunk_off: usize = 0,
    eof: bool = false,
    // Scratch buffer for the current token's text (mirrors `Mbuffer`).
    buff: std.ArrayList(u8),
    source: *lua.lua_TString,
    // Currently-parsing function state (mirrors the C `LexState.fs`).
    fs: ?*lparser.FuncState = null,
    // Last syntax-error message (for diagnostics; null when no error).
    // Stored in the inline buffer so it survives error propagation through
    // the parser (unlike ls.buff which may be cleared during unwind).
    errmsg: ?[]const u8 = null,
    errmsg_buf: [512]u8 = undefined,
    anchor_tab: ?*lua.lua_Table = null,
    glbn: ?*lua.lua_TString = null,
};

// ---------------------------------------------------------------------------
// Character-class predicates (Lua's "lctype" semantics, ASCII)
//
// The i32 scanner set (ldigit/lisxdigit/lisspace/hexval) is the single
// source in lobject.zig (Phase A.1 consolidation); re-exported here.
// ---------------------------------------------------------------------------
const lisdigit = lobject.ldigit;
const lisxdigit = lobject.lisxdigit;
const lisspace = lobject.lisspace;
const hexval = lobject.hexval;

fn lislalpha(c: i32) bool {
    return c == '_' or (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z');
}
fn lislalnum(c: i32) bool {
    return lislalpha(c) or lisdigit(c);
}
fn lisprint(c: i32) bool {
    return c >= 0x20 and c < 0x7f;
}

// ---------------------------------------------------------------------------
// Character stream (mirrors the C `ZIO`)
// ---------------------------------------------------------------------------
fn readByte(ls: *LexState) !?u8 {
    if (ls.chunk_off >= ls.chunk.len) {
        if (ls.eof) return null;
        var size: usize = 0;
        const slice = (try ls.reader(ls.L, ls.data, &size)) orelse {
            ls.eof = true;
            return null;
        };
        if (slice.len == 0 or size == 0) {
            ls.eof = true;
            return null;
        }
        ls.chunk = slice;
        ls.chunk_off = 0;
    }
    const b = ls.chunk[ls.chunk_off];
    ls.chunk_off += 1;
    return b;
}

fn next(ls: *LexState) void {
    const b = readByte(ls) catch null;
    ls.current = if (b) |v| @as(i32, v) else EOZ;
}

fn currIsNewline(ls: *LexState) bool {
    return ls.current == '\n' or ls.current == '\r';
}

// ---------------------------------------------------------------------------
// Buffer helpers
// ---------------------------------------------------------------------------
fn save(ls: *LexState, c: i32) !void {
    if (ls.buff.items.len >= MAX_SIZE) {
        return lexerror(ls, "lexical element too long", TK_EOS);
    }
    try ls.buff.append(ls.allocator, @intCast(c));
}

fn save_and_next(ls: *LexState) !void {
    try save(ls, ls.current);
    next(ls);
}

fn check_next1(ls: *LexState, c: i32) !bool {
    if (ls.current == c) {
        next(ls);
        return true;
    }
    return false;
}

// `set` must be exactly two characters.
fn check_next2(ls: *LexState, set: []const u8) !bool {
    if (ls.current == set[0] or ls.current == set[1]) {
        try save_and_next(ls);
        return true;
    }
    return false;
}

// ---------------------------------------------------------------------------
// Number parsing — shared engine lives in lobject.zig (Phase A.1).
// ---------------------------------------------------------------------------

// Convert the scanned numeral text (NUL-terminated in the buffer) to a Lua
// number, filling `seminfo`. Returns TK_INT or TK_FLT, or SyntaxError for a
// malformed numeral. The shared engine never allocates (the lexer path is
// locale-independent and needs no remapping), so no allocator is threaded.
fn str2num(buf: []const u8, seminfo: *SemInfo) !i32 {
    // buf ends with a NUL we appended; parse the text without it.
    const s = buf[0 .. buf.len - 1];
    if (lobject.parseInteger(s)) |i| {
        seminfo.i = i;
        return TK_INT;
    }
    if (lobject.parseNumericFloat(null, s, '.')) |n| {
        seminfo.r = n;
        return TK_FLT;
    }
    return error.SyntaxError;
}

// ---------------------------------------------------------------------------
// UTF-8 helpers
// ---------------------------------------------------------------------------
// Encode codepoint `x` into `buff` (up to 8 bytes); return the length.
// The bytes are placed at the end of the buffer, from index `8 - length` to `7`.
fn utf8esc(buff: *[8]u8, x_val: u32) u8 {
    var x = x_val;
    var n: u8 = 1;
    std.debug.assert(x <= 0x7FFFFFFF);
    if (x < 0x80) {
        buff[8 - 1] = @intCast(x);
    } else {
        var mfb: u32 = 0x3F;
        while (true) {
            buff[8 - n] = @intCast(0x80 | (x & 0x3F));
            n += 1;
            x >>= 6;
            mfb >>= 1;
            if (x <= mfb) break;
        }
        buff[8 - n] = @as(u8, @truncate((~mfb << 1) | x));
    }
    return n;
}

// ---------------------------------------------------------------------------
// Error reporting
// ---------------------------------------------------------------------------
fn lexerror(ls: *LexState, msg: []const u8, token: i32) LexError {
    // Build "<msg> near <token>" into the dedicated inline buffer so the
    // string is stable during error propagation. Token 0 = no "near" clause.
    // For NAME/STRING/FLT/INT the near token is the partial token text;
    // other tokens use token2str.
    const s = if (token == 0)
        std.fmt.bufPrint(&ls.errmsg_buf, "{s}", .{msg})
    else if (token == TK_NAME or token == TK_STRING or token == TK_FLT or token == TK_INT) blk: {
        // Token text is accumulated in ls.buff. Numerals have a trailing NUL
        // terminator (see read_numeral's save(ls, 0)); strip it so the
        // displayed token matches the reference (which does not print the NUL).
        const tok = ls.buff.items;
        const tok_text = if (tok.len > 0 and tok[tok.len - 1] == 0) tok[0 .. tok.len - 1] else tok;
        break :blk std.fmt.bufPrint(&ls.errmsg_buf, "{s} near '{s}'", .{ msg, tok_text });
    }
    else if (token < FIRST_RESERVED) blk: {
        // Single-byte symbols (token < FIRST_RESERVED): printable chars are
        // quoted as 'x'; control characters are rendered as '<\NN>' (mirrors
        // the reference's luaX_token2str).
        if (token >= 0x20 and token < 0x7f) {
            break :blk std.fmt.bufPrint(&ls.errmsg_buf, "{s} near '{c}'", .{ msg, @as(u8, @intCast(token)) });
        } else {
            break :blk std.fmt.bufPrint(&ls.errmsg_buf, "{s} near '<\\{d}>'", .{ msg, token });
        }
    }
    else
        std.fmt.bufPrint(&ls.errmsg_buf, "{s} near {s}", .{ msg, token2str(token) });
    ls.errmsg = s catch msg;
    return error.SyntaxError;
}

pub fn luaX_syntaxerror(ls: *LexState, msg: []const u8) LexError {
    return lexerror(ls, msg, ls.t.token);
}

// ---------------------------------------------------------------------------
// String interning
// ---------------------------------------------------------------------------
pub fn luaX_newstring(ls: *LexState, str: []const u8) !*lua.lua_TString {
    const L = ls.L;
    const ts = try lstring.luaS_new(L, str);
    if (ls.anchor_tab) |tab| {
        // Deduplicate: reuse an existing string with the same content so that
        // equal literals across the whole chunk (including nested functions)
        // share one object (mirrors the reference's anchorstr / ls->h). The
        // anchor table stores t[string] = string.
        const existing = @import("ltable.zig").getHash(tab, .{ .string = ts });
        if (existing == .string) {
            if (existing.string) |s| return s;
        }
        try @import("ltable.zig").set(tab, .{ .string = ts }, .{ .string = ts });
        // Reference luaX_checkliteral checkGC after the anchor-table insert
        // (lua/llex.c:146).
        lua.luaC_condGC(L);
    }
    return ts;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

// The reference `luaX_init` interns and fixes reserved-word strings. In our
// port reserved words are matched by name against a comptime table (see
// `isReserved`), so there is nothing to pre-intern here. Kept for API parity.
pub fn luaX_init(_: *lua.lua_State) void {}

// Prepare `ls` to scan `source` from `reader`. The caller owns `ls.buff` and
// must call `ls.buff.deinit(ls.allocator)` when done.
pub fn luaX_setinput(
    L: *lua.lua_State,
    ls: *LexState,
    reader: lua.lua_Reader,
    data: ?*anyopaque,
    source: *lua.lua_TString,
    first_slice: []const u8,
    is_eof: bool,
) !void {
    ls.allocator = L.allocator;
    ls.L = L;
    ls.reader = reader;
    ls.data = data;
    ls.source = source;
    ls.anchor_tab = null;
    ls.dyd = .{ .actvar = .empty, .gt = .empty, .label = .empty };
    ls.level = 0;
    ls.brkn = try luaX_newstring(ls, "_break");
    ls.envn = try luaX_newstring(ls, "_ENV");
    ls.glbn = try luaX_newstring(ls, "global");
    ls.t = .{};
    ls.lookahead = .{ .token = TK_EOS };
    ls.linenumber = 1;
    ls.lastline = 1;
    ls.chunk = first_slice;
    ls.chunk_off = 0;
    ls.eof = is_eof;
    ls.fs = null;
    ls.buff = std.ArrayList(u8).empty;
    ls.current = if (try readByte(ls)) |b| @as(i32, b) else EOZ;
}

pub fn luaX_next(ls: *LexState) !void {
    ls.lastline = ls.linenumber;
    if (ls.lookahead.token != TK_EOS) {
        ls.t = ls.lookahead;
        ls.lookahead = .{ .token = TK_EOS };
    } else {
        ls.t.token = try llex(ls, &ls.t.seminfo);
    }
}

pub fn luaX_lookahead(ls: *LexState) !i32 {
    std.debug.assert(ls.lookahead.token == TK_EOS);
    ls.lookahead.token = try llex(ls, &ls.lookahead.seminfo);
    return ls.lookahead.token;
}

// ---------------------------------------------------------------------------
// Line handling
// ---------------------------------------------------------------------------
fn inclinenumber(ls: *LexState) !void {
    const old = ls.current;
    std.debug.assert(currIsNewline(ls));
    next(ls);
    if (currIsNewline(ls) and ls.current != old) next(ls);
    ls.linenumber += 1;
    if (ls.linenumber >= std.math.maxInt(i32)) {
        return lexerror(ls, "chunk has too many lines", TK_EOS);
    }
}

// ---------------------------------------------------------------------------
// Long strings / comments
// ---------------------------------------------------------------------------

// Read a sequence '[=*[' or ']=*]', leaving the last bracket. Returns the
// number of '='s + 2 if well formed; 1 for a single bracket; 0 for an
// unfinished '[==...'.
fn skip_sep(ls: *LexState) !usize {
    var count: usize = 0;
    const s = ls.current;
    std.debug.assert(s == '[' or s == ']');
    try save_and_next(ls);
    while (ls.current == '=') {
        try save_and_next(ls);
        count += 1;
    }
    return if (ls.current == s) count + 2 else if (count == 0) 1 else 0;
}

fn read_long_string(ls: *LexState, seminfo: ?*SemInfo, sep: usize) !void {
    const line = ls.linenumber;
    _ = line;
    try save_and_next(ls); // skip 2nd '['
    if (currIsNewline(ls)) try inclinenumber(ls);
    while (true) {
        switch (ls.current) {
            EOZ => {
                return lexerror(ls, if (seminfo != null)
                    "unfinished long string"
                else
                    "unfinished long comment", TK_EOS);
            },
            ']' => {
                if ((try skip_sep(ls)) == sep) {
                    try save_and_next(ls); // skip 2nd ']'
                    break;
                }
            },
            '\n', '\r' => {
                try save(ls, '\n');
                try inclinenumber(ls);
                if (seminfo == null) ls.buff.clearRetainingCapacity();
            },
            else => {
                if (seminfo != null) try save_and_next(ls) else next(ls);
            },
        }
    }
    if (seminfo != null) {
        const items = ls.buff.items;
        seminfo.?.*.ts = try luaX_newstring(ls, items[sep .. items.len - sep]);
    }
}

// ---------------------------------------------------------------------------
// Short strings / escapes
// ---------------------------------------------------------------------------
fn esccheck(ls: *LexState, ok: bool, msg: []const u8) !void {
    if (!ok) {
        if (ls.current != EOZ) try save_and_next(ls);
        return lexerror(ls, msg, TK_STRING);
    }
}

fn read_save(ls: *LexState, c: i32) !void {
    next(ls);
    _ = ls.buff.pop();
    try save(ls, c);
}

fn only_save(ls: *LexState, c: i32) !void {
    _ = ls.buff.pop();
    try save(ls, c);
}

fn gethexa(ls: *LexState) !u64 {
    try save_and_next(ls);
    try esccheck(ls, lisxdigit(ls.current), "hexadecimal digit expected");
    return hexval(ls.current);
}

fn readhexaesc(ls: *LexState) !u64 {
    const r1 = try gethexa(ls);
    const r2 = try gethexa(ls);
    const r = (r1 << 4) | r2;
    _ = ls.buff.pop();
    _ = ls.buff.pop();
    return r;
}

fn readdecesc(ls: *LexState) !u64 {
    var i: usize = 0;
    var r: u64 = 0;
    while (i < 3 and lisdigit(ls.current)) : (i += 1) {
        r = r * 10 + @as(u64, @intCast(ls.current - '0'));
        try save_and_next(ls);
    }
    try esccheck(ls, r <= 0xFF, "decimal escape too large");
    var k: usize = 0;
    while (k <= i) : (k += 1) _ = ls.buff.pop();
    return r;
}

fn read_string(ls: *LexState, del: i32, seminfo: *SemInfo) !void {
    try save_and_next(ls); // keep delimiter (for error messages)
    while (ls.current != del) {
        switch (ls.current) {
            EOZ => return lexerror(ls, "unfinished string", TK_EOS),
            '\n', '\r' => return lexerror(ls, "unfinished string", TK_EOS),
            '\\' => {
                try save_and_next(ls); // keep '\\'
                switch (ls.current) {
                    'a' => try read_save(ls, '\x07'),
                    'b' => try read_save(ls, '\x08'),
                    'f' => try read_save(ls, '\x0c'),
                    'n' => try read_save(ls, '\n'),
                    'r' => try read_save(ls, '\r'),
                    't' => try read_save(ls, '\t'),
                    'v' => try read_save(ls, '\x0b'),
                    'x' => {
                        const c = try readhexaesc(ls);
                        try read_save(ls, @intCast(c));
                    },
                    'u' => {
                        // current is 'u'; '\' already saved
                        try save_and_next(ls); // save 'u'
                        try esccheck(ls, ls.current == '{', "missing '{'");
                        try save_and_next(ls); // save '{' (kept for error messages)
                        // At least one hex digit is required (mirrors the
                        // reference's `gethexa` for the first digit).
                        try esccheck(ls, lisxdigit(ls.current), "hexadecimal digit expected");
                        var r: u32 = @as(u32, @intCast(hexval(ls.current)));
                        try save_and_next(ls);
                        var nd: usize = 1;
                        while (lisxdigit(ls.current)) {
                            // Reference checks the bound *before* shifting so that
                            // the u32 accumulator never wraps: `(0x7FFFFFFF >> 4)`.
                            try esccheck(ls, r <= (0x7FFFFFFF >> 4), "UTF-8 value too large");
                            r = (r << 4) | @as(u32, @intCast(hexval(ls.current)));
                            try save_and_next(ls);
                            nd += 1;
                        }
                        try esccheck(ls, ls.current == '}', "missing '}'");
                        next(ls); // skip '}' (not saved)
                        // Remove the escape text saved so far: '\', 'u', '{', and
                        // the (nd) hex digits. Matches the reference's
                        // `luaZ_buffremove(buff, 3 + nd)`.
                        var k: usize = 0;
                        while (k < 3 + nd) : (k += 1) _ = ls.buff.pop();
                        var ubuf: [8]u8 = undefined;
                        const n = utf8esc(&ubuf, r);
                        var j = n;
                        while (j > 0) : (j -= 1) try save(ls, ubuf[8 - j]);
                    },
                    '\n', '\r' => {
                        try inclinenumber(ls);
                        try only_save(ls, '\n');
                    },
                    '\\', '"', '\'' => try read_save(ls, @intCast(ls.current)),
                    EOZ => {}, // will raise on next loop iteration
                    'z' => {
                        _ = ls.buff.pop(); // remove '\\'
                        next(ls); // skip 'z'
                        while (lisspace(ls.current)) {
                            if (currIsNewline(ls)) try inclinenumber(ls) else next(ls);
                        }
                    },
                    else => {
                        try esccheck(ls, lisdigit(ls.current), "invalid escape sequence");
                        const c = try readdecesc(ls);
                        try save(ls, @intCast(c));
                    },
                }
            },
            else => try save_and_next(ls),
        }
    }
    try save_and_next(ls); // skip delimiter
    const items = ls.buff.items;
    seminfo.ts = try luaX_newstring(ls, items[1 .. items.len - 1]);
}

// ---------------------------------------------------------------------------
// Numerals
// ---------------------------------------------------------------------------
fn read_numeral(ls: *LexState, seminfo: *SemInfo) !i32 {
    const first = ls.current;
    std.debug.assert(lisdigit(ls.current));
    try save_and_next(ls);
    var expo: []const u8 = "Ee";
    if (first == '0' and (try check_next2(ls, "xX"))) expo = "Pp";
    while (true) {
        if (try check_next2(ls, expo)) {
            _ = try check_next2(ls, "-+");
        } else if (lisxdigit(ls.current) or ls.current == '.') {
            try save_and_next(ls);
        } else break;
    }
    if (lislalpha(ls.current)) {
        try save_and_next(ls); // force an error
    }
    try save(ls, 0);
    const kind = str2num(ls.buff.items, seminfo) catch {
        return lexerror(ls, "malformed number", TK_INT);
    };
    return kind;
}

// ---------------------------------------------------------------------------
// The core scanner
// ---------------------------------------------------------------------------
fn llex(ls: *LexState, seminfo: *SemInfo) !i32 {
    ls.buff.clearRetainingCapacity();
    while (true) {
        switch (ls.current) {
            '\n', '\r' => {
                try inclinenumber(ls);
            },
            ' ', '\t', '\x0c', '\x0b' => {
                next(ls);
            },
            '-' => {
                next(ls);
                if (ls.current != '-') return '-';
                next(ls);
                if (ls.current == '[') {
                    const sep = try skip_sep(ls);
                    ls.buff.clearRetainingCapacity();
                    if (sep >= 2) {
                        try read_long_string(ls, null, sep);
                        ls.buff.clearRetainingCapacity();
                        continue;
                    }
                }
                while (!currIsNewline(ls) and ls.current != EOZ) next(ls);
            },
            '[' => {
                const sep = try skip_sep(ls);
                if (sep >= 2) {
                    try read_long_string(ls, seminfo, sep);
                    return TK_STRING;
                } else if (sep == 0) {
                    return lexerror(ls, "invalid long string delimiter", TK_STRING);
                }
                return '[';
            },
            '=' => {
                next(ls);
                if (try check_next1(ls, '=')) return TK_EQ;
                return '=';
            },
            '<' => {
                next(ls);
                if (try check_next1(ls, '=')) return TK_LE;
                if (try check_next1(ls, '<')) return TK_SHL;
                return '<';
            },
            '>' => {
                next(ls);
                if (try check_next1(ls, '=')) return TK_GE;
                if (try check_next1(ls, '>')) return TK_SHR;
                return '>';
            },
            '/' => {
                next(ls);
                if (try check_next1(ls, '/')) return TK_IDIV;
                return '/';
            },
            '~' => {
                next(ls);
                if (try check_next1(ls, '=')) return TK_NE;
                return '~';
            },
            ':' => {
                next(ls);
                if (try check_next1(ls, ':')) return TK_DBCOLON;
                return ':';
            },
            '"', '\'' => {
                try read_string(ls, ls.current, seminfo);
                return TK_STRING;
            },
            '.' => {
                try save_and_next(ls);
                if (try check_next1(ls, '.')) {
                    if (try check_next1(ls, '.')) return TK_DOTS;
                    return TK_CONCAT;
                } else if (!lisdigit(ls.current)) {
                    return '.';
                } else {
                    return try read_numeral(ls, seminfo);
                }
            },
            '0'...'9' => {
                return try read_numeral(ls, seminfo);
            },
            EOZ => {
                return TK_EOS;
            },
            else => {
                if (lislalpha(ls.current)) {
                    while (true) {
                        try save_and_next(ls);
                        if (!lislalnum(ls.current)) break;
                    }
                    const ts = try luaX_newstring(ls, ls.buff.items);
                    if (isReserved(ls.buff.items)) |tok| return tok;
                    seminfo.ts = ts;
                    return TK_NAME;
                } else {
                    const c = ls.current;
                    next(ls);
                    return c;
                }
            },
        }
    }
}

// ---------------------------------------------------------------------------
// Diagnostic helpers (used by the future parser for error messages)
// ---------------------------------------------------------------------------
pub fn token2str(token: i32) []const u8 {
    if (token < FIRST_RESERVED) {
        // single-char symbol: quote it (e.g. '+')
        if (token >= 0x20 and token < 0x7f) return &quoted_chars[@intCast(token)];
        return "<nonprintable>";
    }
    for (reserved_words, 0..) |r, i| {
        if (r.tok == token) return quoted_reserved[i];
    }
    return switch (token) {
        TK_IDIV => "'//'",
        TK_CONCAT => "'..'",
        TK_DOTS => "'...'",
        TK_EQ => "'=='",
        TK_GE => "'>='",
        TK_LE => "'<='",
        TK_NE => "'~='",
        TK_SHL => "'<<'",
        TK_SHR => "'>>'",
        TK_DBCOLON => "'::'",
        TK_EOS => "<eof>",
        TK_FLT => "<number>",
        TK_INT => "<integer>",
        TK_NAME => "<name>",
        TK_STRING => "<string>",
        else => "<unknown>",
    };
}

// ---------------------------------------------------------------------------
// Tests for the lexer live in tests/test_basic.zig (the test root), because a
// module built as a dependency of the test root is compiled without its own
// `test` declarations. They are reachable there via `lua.llex.*`.
// ---------------------------------------------------------------------------
