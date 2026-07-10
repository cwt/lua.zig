// $Id: ltable.zig
// Lua tables (hash) for Lua.zig (Zig port of Lua 5.5.1)
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

const LIMFORLAST: usize = 4;

/// A key/value pair returned by table traversals.
pub const KV = struct { key: TValue, val: TValue };

/// Classify a numeric TValue as an integer key, if it has an integral value
/// within the representable integer range.
fn asInt(v: TValue) ?i64 {
    if (v != .number) return null;
    const n = v.number;
    if (n != @floor(n)) return null;
    if (n < -9.0e18 or n > 9.0e18) return null;
    return @intFromFloat(n);
}

/// Raw key equality. Treats equal string contents as equal (interned strings
/// also satisfy pointer equality).
fn keyEquals(a: TValue, b: TValue) bool {
    if (@as(std.meta.Tag(TValue), a) != @as(std.meta.Tag(TValue), b)) {
        return false;
    }
    return switch (a) {
        .nil => true,
        .boolean => |x| x == b.boolean,
        .number => |x| x == b.number,
        .string => |sa| blk: {
            const sb = b.string orelse break :blk false;
            if (sa == sb) break :blk true;
            break :blk std.mem.eql(u8, sa.?.s, sb.s);
        },
        .lightud => |pa| pa == b.lightud,
        .table => |ta| ta == b.table,
        .function => |fa| fa == b.function,
        .userdata => |ua| ua == b.userdata,
        .thread => |ta| ta == b.thread,
        else => false,
    };
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
fn hashKey(key: TValue, len: usize) usize {
    if (len == 0) return 0;
    const h: usize = switch (key) {
        .number => |n| hashBits(@bitCast(n)),
        .string => |ts| if (ts) |s| s.hash else 0,
        .boolean => |b| if (b) 1 else 0,
        .lightud => |p| if (p) |q| @intFromPtr(q) else 0,
        .userdata => |p| if (p) |q| @intFromPtr(q) else 0,
        .function => |p| if (p) |q| @intFromPtr(q) else 0,
        .table => |p| if (p) |q| @intFromPtr(q) else 0,
        .thread => |p| if (p) |q| @intFromPtr(q) else 0,
        else => 0,
    };
    return h % len;
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
    var i = t.lastfree;
    while (i > 0) {
        i -= 1;
        if (t.node.items[i].key == .nil) return i;
    }
    return null;
}

/// Insert (key, val) into a node list. Assumes there is room; returns false
/// if no free slot exists.
fn insertInto(list: []Node, key: TValue, val: TValue) bool {
    const len = list.len;
    if (len == 0) return false;
    const mp = hashKey(key, len);
    var n = mp;
    while (true) {
        if (list[n].key == .nil) {
            list[n] = .{ .key = key, .val = val, .next = 0 };
            return true;
        }
        if (keyEquals(list[n].key, key)) {
            list[n].val = val;
            return true;
        }
        if (list[n].next == 0) break;
        n = @intCast(list[n].next);
    }
    // search a free slot from the end
    var f = len;
    while (f > 0) {
        f -= 1;
        if (list[f].key == .nil) {
            list[f] = .{ .key = key, .val = val, .next = list[mp].next };
            list[mp].next = @intCast(f);
            return true;
        }
    }
    return false;
}

/// Grow the hash part to accommodate more entries, re-inserting everything.
fn growNode(t: *Table) !void {
    const newlen: usize = if (t.node.items.len == 0) LIMFORLAST else t.node.items.len * 2;
    var newlist = std.ArrayList(Node).empty;
    try newlist.ensureTotalCapacity(t.allocator, newlen);
    newlist.items.len = newlen;
    @memset(newlist.items, Node{ .key = TValue{ .nil = {} }, .val = TValue{ .nil = {} }, .next = 0 });
    for (t.node.items) |nd| {
        if (nd.key != .nil and nd.val != .nil) {
            _ = insertInto(newlist.items, nd.key, nd.val);
        }
    }
    t.node.deinit(t.allocator);
    t.node = newlist;
    t.lastfree = newlen;
}

/// Remove `key` from the hash part (if present), unlinking it from its chain.
fn removeFromHash(t: *Table, key: TValue) void {
    const len = t.node.items.len;
    if (len == 0) return;
    const mp = hashKey(key, len);
    var prev: ?usize = null;
    var n = mp;
    while (true) {
        if (t.node.items[n].key == .nil) return;
        if (keyEquals(t.node.items[n].key, key)) {
            if (prev) |p| {
                t.node.items[p].next = t.node.items[n].next;
            }
            t.node.items[n] = .{ .key = TValue{ .nil = {} }, .val = TValue{ .nil = {} }, .next = 0 };
            return;
        }
        if (t.node.items[n].next == 0) return;
        prev = n;
        n = @intCast(t.node.items[n].next);
    }
}

/// Find the node index holding `key` in the hash part, if any.
fn findNodeIndex(t: *Table, key: TValue) ?usize {
    const len = t.node.items.len;
    if (len == 0) return null;
    const mp = hashKey(key, len);
    var n = mp;
    while (true) {
        if (t.node.items[n].key == .nil) return null;
        if (keyEquals(t.node.items[n].key, key)) return n;
        if (t.node.items[n].next == 0) return null;
        n = @intCast(t.node.items[n].next);
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
        try node.append(allocator, Node{ .key = TValue{ .nil = {} }, .val = TValue{ .nil = {} }, .next = 0 });
    }
    t.* = .{
        .allocator = allocator,
        .array = array,
        .node = node,
        .lastfree = nhash,
        .lenhint = narr / 2,
    };
    return t;
}

pub fn deinit(t: *Table) void {
    t.array.deinit(t.allocator);
    t.node.deinit(t.allocator);
    t.allocator.destroy(t);
}

pub fn arrayIsEmpty(t: *Table, i: usize) bool {
    // i is a 1-based array index
    if (i < 1 or i > t.array.items.len) return true;
    return t.array.items[i - 1] == .nil;
}

/// Get the value for an integer key (Lua semantics: array part first).
pub fn getInt(t: *Table, k: i64) TValue {
    if (k >= 1) {
        const u: usize = @intCast(k);
        if (u <= t.array.items.len) {
            return t.array.items[u - 1];
        }
    }
    return getHash(t, TValue{ .number = @as(f64, @floatFromInt(k)) });
}

fn getHash(t: *Table, key: TValue) TValue {
    const len = t.node.items.len;
    if (len == 0) return TValue{ .nil = {} };
    const mp = hashKey(key, len);
    var n = mp;
    while (true) {
        if (t.node.items[n].key == .nil) return TValue{ .nil = {} };
        if (keyEquals(t.node.items[n].key, key)) return t.node.items[n].val;
        if (t.node.items[n].next == 0) return TValue{ .nil = {} };
        n = @intCast(t.node.items[n].next);
    }
}

/// Get the value for any key.
pub fn get(t: *Table, key: TValue) TValue {
    if (key == .nil) return TValue{ .nil = {} };
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
        removeFromHash(t, TValue{ .number = @as(f64, @floatFromInt(k)) });
        return;
    }
    if (k >= 1) {
        const u: usize = @intCast(k);
        if (u <= t.array.items.len) {
            t.array.items[u - 1] = val;
            return;
        }
        if (u == t.array.items.len + 1) {
            try t.array.append(t.allocator, val);
            return;
        }
        if (u > t.array.items.len + 1) {
            // gap: keep it in the hash part rather than filling with holes
            try setHash(t, TValue{ .number = @as(f64, @floatFromInt(k)) }, val);
            return;
        }
    }
    try setHash(t, TValue{ .number = @as(f64, @floatFromInt(k)) }, val);
}

fn setHash(t: *Table, key: TValue, val: TValue) !void {
    // update if present
    const len = t.node.items.len;
    if (len > 0) {
        const mp = hashKey(key, len);
        var n = mp;
        while (true) {
            if (t.node.items[n].key == .nil) break;
            if (keyEquals(t.node.items[n].key, key)) {
                t.node.items[n].val = val;
                return;
            }
            if (t.node.items[n].next == 0) break;
            n = @intCast(t.node.items[n].next);
        }
    }
    if (val == .nil) {
        removeFromHash(t, key);
        return;
    }
    const f = getFreePos(t) orelse {
        try growNode(t);
        return setHash(t, key, val);
    };
    const newlen = t.node.items.len;
    const mp = hashKey(key, newlen);
    if (t.node.items[mp].key == .nil) {
        t.node.items[mp] = .{ .key = key, .val = val, .next = 0 };
    } else {
        t.node.items[f] = .{ .key = key, .val = val, .next = t.node.items[mp].next };
        t.node.items[mp].next = @intCast(f);
    }
}

/// Set the value for any key. A nil value removes the entry.
pub fn set(t: *Table, key: TValue, val: TValue) !void {
    if (key == .nil) return error.TableIndexIsNil;
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
pub fn next(t: *Table, key: TValue) ?KV {
    if (key == .nil) {
        var i: usize = 1;
        while (i <= t.array.items.len) : (i += 1) {
            if (t.array.items[i - 1] != .nil) {
                return .{ .key = TValue{ .number = @as(f64, @floatFromInt(i)) }, .val = t.array.items[i - 1] };
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
                        return .{ .key = TValue{ .number = @as(f64, @floatFromInt(i)) }, .val = t.array.items[i - 1] };
                    }
                }
                return scanHashFrom(t, 0);
            }
        }
        const start = findNodeIndex(t, key) orelse return null;
        return scanHashFrom(t, start + 1);
    }
    const start = findNodeIndex(t, key) orelse return null;
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
    const v = getHash(t, TValue{ .number = @as(f64, @floatFromInt(k)) });
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
