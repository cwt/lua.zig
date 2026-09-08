// $Id: ltable.zig
// Lua tables (hash) for Lua.zig (Zig port of Lua 5.5.0)
// See Copyright Notice in lua.h
//
// Tables keep elements in two parts: an array part and a hash part.
// Non-negative integer keys are candidates for the array part; everything
// else (and integer keys beyond the array part) lives in the hash part.
//
// The hash part is a chained scatter table (the same invariant as the C
// reference: a key not in its main position implies the colliding key is in
// its own main position). `Node.next` is an absolute node index (0 = end of
// chain), which is simpler to manage than the C reference's offset chains
// while preserving identical lookup/iteration semantics.

const std = @import("std");
const lua = @import("lua.zig");

const TValue = lua.TValue;
const Table = lua.lua_Table;
const Node = lua.Node;
const TString = lua.lua_TString;

const LIMFORLAST: usize = 4;

/// A key/value pair returned by table traversals.
pub const KV = struct { key: TValue, val: TValue };

/// Classify a numeric TValue as an integer key, if it has an integral value
/// within the representable integer range.
inline fn asInt(v: TValue) ?i64 {
    return v.toIntegerExactOpt();
}

/// Raw key equality. Treats equal string contents as equal (interned strings
/// also satisfy pointer equality). Each field access is guarded by an explicit
/// tag check so the function is safe to inline at call sites where the key's
/// active tag is statically known.
inline fn keyEquals(a: TValue, b: TValue) bool {
    // Cross-type numeric: integers and floats with the same value are equal as keys.
    if (a == .integer and b == .number) {
        return @as(f64, @floatFromInt(a.integer)) == b.number;
    }
    if (a == .number and b == .integer) {
        return a.number == @as(f64, @floatFromInt(b.integer));
    }
    if (@as(std.meta.Tag(TValue), a) != @as(std.meta.Tag(TValue), b)) {
        return false;
    }
    if (a == .number and b == .number) return a.number == b.number;
    if (a == .integer and b == .integer) return a.integer == b.integer;
    if (a == .string and b == .string) {
        if (a.string) |sa| {
            if (b.string) |sb| {
                if (sa == sb) return true;
                return std.mem.eql(u8, sa.s, sb.s);
            }
        }
        return false;
    }
    if (a == .boolean and b == .boolean) return a.boolean == b.boolean;
    if (a == .lightud and b == .lightud) return a.lightud == b.lightud;
    if (a == .table and b == .table) return a.table == b.table;
    if (a == .function and b == .function) return a.function == b.function;
    if (a == .userdata and b == .userdata) return a.userdata == b.userdata;
    if (a == .thread and b == .thread) return a.thread == b.thread;
    if (a == .proto and b == .proto) return a.proto == b.proto;
    if (a == .nil and b == .nil) return true;
    return false;
}

fn hashBits(x: u64) usize {
    // mix to avoid trivial patterns
    var h = x;
    h ^= h >> 33;
    h *%= 0xff51afd7ed558ccd;
    h ^= h >> 33;
    h *%= 0xc4ceb9fe1a85ec53;
    h ^= h >> 33;
    return @intCast(h);
}

/// Hash a key into a node index for a table with `len` nodes.
///
/// `len` is always a power of two (see `computeHashSize`/`growNode`), so the
/// modulo reduces to a bitmask — a single `and` instead of a runtime integer
/// division.
inline fn hashKey(key: TValue, len: usize) usize {
    if (len == 0) return 0;
    const mask = len - 1;
    const h: usize = switch (key) {
        .number => |n| blk: {
            // BUG-096: normalize -0.0 to 0.0 so t[-0.0] and t[0.0] hash to
            // the same bucket (they are equal as keys in Lua).
            const normalized: f64 = if (n == 0.0 and @as(u64, @bitCast(n)) == 0x8000000000000000) 0.0 else n;
            break :blk hashBits(@bitCast(normalized));
        },
        .integer => |n| hashBits(@bitCast(@as(f64, @floatFromInt(n)))),
        .string => |ts| if (ts) |s| s.hash else 0,
        .boolean => |b| if (b) 1 else 0,
        .lightud => |p| if (p) |q| hashBits(@intFromPtr(q)) else 0,
        .userdata => |p| if (p) |q| hashBits(@intFromPtr(q)) else 0,
        .function => |p| if (p) |q| hashBits(@intFromPtr(q)) else 0,
        .table => |p| if (p) |q| hashBits(@intFromPtr(q)) else 0,
        .thread => |p| if (p) |q| hashBits(@intFromPtr(q)) else 0,
        .proto => |p| if (p) |q| hashBits(@intFromPtr(q)) else 0,
        else => 0,
    };
    return h & mask;
}

/// Smallest power of two >= n (n clamped to >=1).
fn ceilPow2(n: usize) usize {
    var p: usize = 1;
    while (p < n) p <<= 1;
    return p;
}

/// Initial hash-part size for a requested number of records.
fn computeHashSize(nrec: usize) usize {
    if (nrec == 0) return 0;
    return ceilPow2(nrec);
}

/// Find a free node scanning backward from `lastfree`.
fn getFreePos(t: *Table) ?usize {
    if (t.node.items.len == 0) return null;
    while (t.lastfree > 0) {
        t.lastfree -= 1;
        if (t.node.items[t.lastfree].key == .nil) return t.lastfree;
    }
    return null;
}

/// Insert (key, val) into a node list. Assumes there is room; returns false
/// if no free slot exists.
/// Grow the hash part to accommodate more entries, re-inserting everything via setHash.
fn countActiveHashKeys(t: *Table) usize {
    var count: usize = 0;
    for (t.node.items) |nd| {
        if (nd.key != .nil and nd.val != .nil) count += 1;
    }
    return count;
}

fn growNode(t: *Table) anyerror!void {
    const active_count = countActiveHashKeys(t) + 1;
    var newlen = ceilPow2(active_count);
    if (newlen < 4) newlen = 4;
    var old_node = t.node;
    const old_cap = old_node.capacity;
    const old_lastfree = t.lastfree;
    var newlist = std.ArrayList(Node).empty;
    try newlist.ensureTotalCapacityPrecise(t.allocator, newlen);
    newlist.appendNTimesAssumeCapacity(.{ .key = .{ .nil = {} }, .val = .{ .nil = {} }, .next = -1 }, newlen);
    t.node = newlist;
    t.lastfree = newlen;
    errdefer {
        t.node.deinit(t.allocator);
        t.node = old_node;
        t.lastfree = old_lastfree;
    }
    for (old_node.items) |nd| {
        if (nd.key != .nil and nd.val != .nil) {
            try setHash(t, nd.key, nd.val);
        }
    }
    old_node.deinit(t.allocator);
    if (t.g) |g| {
        const new_bytes = t.node.capacity * @sizeOf(Node);
        const old_bytes = old_cap * @sizeOf(Node);
        if (new_bytes > old_bytes) {
            g.totalbytes += (new_bytes - old_bytes);
        } else if (old_bytes > new_bytes) {
            if (g.totalbytes >= old_bytes - new_bytes) {
                g.totalbytes -= (old_bytes - new_bytes);
            } else {
                g.totalbytes = 0;
            }
        }
    }
}

/// Remove a key's value from the hash part if present.
fn clearHashKey(t: *Table, key: TValue) void {
    if (findNodeIndex(t, key)) |idx| {
        t.node.items[idx].val = .{ .nil = {} };
    }
}

/// Find the node index holding `key` in the hash part, if any.
fn findNodeIndex(t: *Table, key: TValue) ?usize {
    const len = t.node.items.len;
    if (len == 0) return null;
    const mp = hashKey(key, len);
    var n = mp;
    while (true) {
        if (keyEquals(t.node.items[n].key, key)) return n;
        const next_idx = t.node.items[n].next;
        if (next_idx < 0 or next_idx >= len) return null;
        n = @intCast(next_idx);
    }
}

// ===================================================================
// Public table operations
// ===================================================================

pub fn createTable(allocator: std.mem.Allocator, narr: usize, nrec: usize) !*Table {
    const t = try allocator.create(Table);
    var array = std.ArrayList(TValue).empty;
    var i: usize = 0;
    while (i < narr) : (i += 1) {
        try array.append(allocator, TValue{ .nil = {} });
    }
    var node = std.ArrayList(Node).empty;
    const nhash = computeHashSize(nrec);
    var j: usize = 0;
    while (j < nhash) : (j += 1) {
        try node.append(allocator, Node{ .key = TValue{ .nil = {} }, .val = TValue{ .nil = {} }, .next = -1 });
    }
    t.* = .{
        .allocator = allocator,
        .array = array,
        .node = node,
        .lastfree = nhash,
        .metatable = null,
        .flags = 0,
    };
    return t;
}

pub fn deinit(t: *Table) void {
    t.array.deinit(t.allocator);
    t.node.deinit(t.allocator);
    t.allocator.destroy(t);
}

/// Ensure the array part has at least `size` elements, filling any new slots with nil.
pub fn ensureArraySize(t: *Table, size: usize) !void {
    if (size > t.array.items.len) {
        const old_cap = t.array.capacity;
        const old_len = t.array.items.len;
        try t.array.ensureTotalCapacity(t.allocator, size);
        t.array.items.len = size;
        if (t.g) |g| {
            if (t.array.capacity > old_cap) {
                g.totalbytes += (t.array.capacity - old_cap) * @sizeOf(TValue);
            }
        }
        for (t.array.items[old_len..size], old_len + 1..) |*slot, idx| {
            slot.* = TValue{ .nil = {} };
            clearHashKey(t, TValue{ .integer = @intCast(idx) });
        }
    }
}

pub fn arrayIsEmpty(t: *Table, i: usize) bool {
    // i is a 1-based array index
    if (i < 1 or i > t.array.items.len) return true;
    return t.array.items[i - 1] == .nil;
}

/// Get the value for an integer key (Lua semantics: array part first).
pub inline fn getInt(t: *Table, k: i64) TValue {
    if (k >= 1) {
        const u: usize = @intCast(k);
        if (u <= t.array.items.len) {
            return t.array.items[u - 1];
        }
    }
    return getHash(t, TValue{ .integer = k });
}

pub inline fn getHash(t: *Table, key: TValue) TValue {
    const len = t.node.items.len;
    if (len == 0) return TValue{ .nil = {} };
    const mp = hashKey(key, len);
    var n = mp;
    while (true) {
        if (keyEquals(t.node.items[n].key, key)) return t.node.items[n].val;
        const next_idx = t.node.items[n].next;
        if (next_idx < 0 or next_idx >= len) return TValue{ .nil = {} };
        n = @intCast(next_idx);
    }
}

/// Specialized lookup for interned-string keys — the dominant case for
/// globals and field access. Interned strings are unique per content, so keys
/// compare by pointer identity. This skips the generic `hashKey` switch and the
/// `keyEquals` union comparison that `getHash` performs (the Zig-idiomatic
/// counterpart of C Lua's `luaH_getshortstr`).
inline fn getStr(t: *Table, key: *const TString) TValue {
    const len = t.node.items.len;
    if (len == 0) {
        @branchHint(.unlikely);
        return TValue{ .nil = {} };
    }
    const mp = @as(usize, key.hash) & (len - 1);
    var n = mp;
    while (true) {
        const k = t.node.items[n].key;
        if (k == .string) {
            if (k.string) |ks| {
                if (ks == key) return t.node.items[n].val;
                if (std.mem.eql(u8, ks.s, key.s)) {
                    @branchHint(.unlikely);
                    return t.node.items[n].val;
                }
            }
        }
        const next_idx = t.node.items[n].next;
        if (next_idx < 0 or next_idx >= len) return TValue{ .nil = {} };
        n = @intCast(next_idx);
    }
}

/// Get the value for any key.
pub inline fn get(t: *Table, key: TValue) TValue {
    if (key == .nil) return TValue{ .nil = {} };
    if (key == .string) return getStr(t, key.string.?);
    if (asInt(key)) |k| return getInt(t, k);
    return getHash(t, key);
}

/// Set the value for an integer key.
pub fn setInt(t: *Table, k: i64, val: TValue) !void {
    if (val == .nil) {
        if (k >= 1) {
            const u: usize = @intCast(k);
            if (u <= t.array.items.len) {
                t.array.items[u - 1] = TValue{ .nil = {} };
                return;
            }
        }
        try setHash(t, TValue{ .integer = k }, val);
        return;
    }
    if (k >= 1) {
        const u: usize = @intCast(k);
        if (u <= t.array.items.len) {
            t.array.items[u - 1] = val;
            return;
        }
        if (u == t.array.items.len + 1) {
            clearHashKey(t, TValue{ .integer = k });
            const old_cap = t.array.capacity;
            try t.array.append(t.allocator, val);
            if (t.g) |g| {
                if (t.array.capacity > old_cap) {
                    g.totalbytes += (t.array.capacity - old_cap) * @sizeOf(TValue);
                }
            }
            return;
        }
        if (u > t.array.items.len + 1) {
            // gap: keep it in the hash part rather than filling with holes
            try setHash(t, TValue{ .integer = k }, val);
            return;
        }
    }
    try setHash(t, TValue{ .integer = k }, val);
}

fn setHash(t: *Table, key: TValue, val: TValue) anyerror!void {
    const len = t.node.items.len;
    if (len == 0) {
        if (val == .nil) return; // assigning nil to non-existent key in empty hash is no-op
        try growNode(t);
        return setHash(t, key, val);
    }

    const mp = hashKey(key, len);
    var n = mp;
    while (true) {
        if (keyEquals(t.node.items[n].key, key)) {
            t.node.items[n].val = val;
            return;
        }
        const next_idx = t.node.items[n].next;
        if (next_idx < 0 or next_idx >= len) break;
        n = @intCast(next_idx);
    }

    if (val == .nil) {
        return;
    }

    if (t.node.items[mp].key == .nil) {
        t.node.items[mp] = .{ .key = key, .val = val, .next = -1 };
        return;
    }

    const f = getFreePos(t) orelse {
        try growNode(t);
        return setHash(t, key, val);
    };

    const othermp = hashKey(t.node.items[mp].key, len);
    if (othermp != mp) {
        var prev = othermp;
        while (t.node.items[prev].next >= 0 and @as(usize, @intCast(t.node.items[prev].next)) != mp) {
            prev = @intCast(t.node.items[prev].next);
        }
        if (t.node.items[prev].next != -1 and @as(usize, @intCast(t.node.items[prev].next)) == mp) {
            t.node.items[prev].next = @intCast(f);
            t.node.items[f] = t.node.items[mp];
            t.node.items[mp] = .{ .key = key, .val = val, .next = -1 };
        } else {
            t.node.items[f] = .{ .key = key, .val = val, .next = t.node.items[mp].next };
            t.node.items[mp].next = @intCast(f);
        }
    } else {
        t.node.items[f] = .{ .key = key, .val = val, .next = t.node.items[mp].next };
        t.node.items[mp].next = @intCast(f);
    }
}

/// Set the value for any key. A nil value removes the entry.
pub fn set(t: *Table, key: TValue, val: TValue) !void {
    if (key == .nil) return error.TableIndexIsNil;
    if (key == .number and std.math.isNan(key.number)) return error.TableIndexIsNaN;
    if (asInt(key)) |k| {
        try setInt(t, k, val);
        return;
    }
    try setHash(t, key, val);
}

/// Scan the hash part for the first non-empty node at index >= `start`.
fn scanHashFrom(t: *Table, start: usize) ?KV {
    var n = start;
    while (n < t.node.items.len) : (n += 1) {
        if (t.node.items[n].key != .nil and t.node.items[n].val != .nil) {
            return .{ .key = t.node.items[n].key, .val = t.node.items[n].val };
        }
    }
    return null;
}

/// Next key/value pair for traversal. `key == nil` starts the iteration.
/// Order: array part by ascending index, then hash part by node order.
pub fn next(t: *Table, key: TValue) anyerror!?KV {
    if (key == .nil) {
        var i: usize = 1;
        while (i <= t.array.items.len) : (i += 1) {
            if (t.array.items[i - 1] != .nil) {
                return .{ .key = TValue{ .integer = @intCast(i) }, .val = t.array.items[i - 1] };
            }
        }
        return scanHashFrom(t, 0);
    }
    if (asInt(key)) |k| {
        if (k >= 1) {
            const u: usize = @intCast(k);
            if (u <= t.array.items.len) {
                var i = u + 1;
                while (i <= t.array.items.len) : (i += 1) {
                    if (t.array.items[i - 1] != .nil) {
                        return .{ .key = TValue{ .integer = @intCast(i) }, .val = t.array.items[i - 1] };
                    }
                }
                return scanHashFrom(t, 0);
            }
        }
        const start = findNodeIndex(t, key) orelse return error.InvalidKeyToNext;
        return scanHashFrom(t, start + 1);
    }
    const start = findNodeIndex(t, key) orelse return error.InvalidKeyToNext;
    return scanHashFrom(t, start + 1);
}

/// Length of a table (the "border" as defined by Lua).
pub fn getn(t: *Table) usize {
    const asize = t.array.items.len;
    if (asize == 0) {
        return hashLength(t, 0);
    }
    // Find the largest present index in [1, asize].
    var lo: usize = 1;
    var hi: usize = asize;
    var ans: usize = 0;
    while (lo <= hi) {
        const mid = (lo + hi) / 2;
        if (arrayIsEmpty(t, mid)) {
            hi = mid - 1;
        } else {
            ans = mid;
            lo = mid + 1;
        }
    }
    if (ans < asize) {
        return ans;
    }
    // t[asize] is present; length is asize unless asize+1 is also present
    if (!hashHasInt(t, asize + 1)) {
        return asize;
    }
    return hashSearch(t, asize);
}

fn hashHasInt(t: *Table, k: usize) bool {
    const v = getHash(t, TValue{ .integer = @as(i64, @intCast(k)) });
    return v != .nil;
}

/// Find a border when asize+1 is present in the hash part.
fn hashSearch(t: *Table, asize: usize) usize {
    var i: usize = asize + 1;
    var j: usize = i + 1;
    while (hashHasInt(t, j)) {
        i = j;
        if (j > (std.math.maxInt(i64) / 2)) {
            return i;
        }
        j = j * 2;
    }
    while (j - i > 1) {
        const m = (i + j) / 2;
        if (hashHasInt(t, m)) {
            i = m;
        } else {
            j = m;
        }
    }
    return i;
}

/// Length for a table whose array part is empty: largest integer key `i`
/// such that t[i] present and t[i+1] absent, starting the search at `start`.
fn hashLength(t: *Table, start: usize) usize {
    var i = start;
    var j = i + 1;
    while (hashHasInt(t, j)) {
        i = j;
        if (j > (std.math.maxInt(i64) / 2)) {
            return i;
        }
        j = j * 2;
    }
    if (i == 0 and !hashHasInt(t, 1)) return 0;
    while (j - i > 1) {
        const m = (i + j) / 2;
        if (hashHasInt(t, m)) {
            i = m;
        } else {
            j = m;
        }
    }
    return i;
}
