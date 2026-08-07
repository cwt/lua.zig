const std = @import("std");

// Shared resolver for the hosted libm (glibc on Linux). Lua's math.* is
// specified in terms of C math.h, and glibc's hand-tuned libm is faster than
// Zig's bundled compiler_rt for the true transcendentals (x86-64 has no
// hardware log/sin/exp/... instruction). LLVM folds any call named
// `log`/`sin`/... into a compiler_rt builtin at compile time, so we resolve
// libm's symbols at runtime via std.DynLib — an indirect call through a
// pointer the compiler cannot constant-fold reaches glibc. libm is permanently
// loaded via DT_NEEDED (build.zig sets link_libc), so the pointers stay valid.
// If resolution ever fails we fall back to std.math (the previous behavior),
// so callers never need to handle an error.
//
// Hardware-backed ops (sqrt/floor/ceil/trunc/abs/signbit/isNan/isInf) are NOT
// routed here: glibc just wraps the same CPU instruction in a slower PLT call,
// and they don't use compiler_rt anyway.
pub const Libm = struct {
    sin: *const fn (f64) callconv(.c) f64,
    cos: *const fn (f64) callconv(.c) f64,
    tan: *const fn (f64) callconv(.c) f64,
    asin: *const fn (f64) callconv(.c) f64,
    acos: *const fn (f64) callconv(.c) f64,
    atan2: *const fn (f64, f64) callconv(.c) f64,
    log: *const fn (f64) callconv(.c) f64,
    log2: *const fn (f64) callconv(.c) f64,
    log10: *const fn (f64) callconv(.c) f64,
    exp: *const fn (f64) callconv(.c) f64,
    pow: *const fn (f64, f64) callconv(.c) f64,
    fmod: *const fn (f64, f64) callconv(.c) f64,
    frexp: *const fn (f64, *i32) callconv(.c) f64,
    ldexp: *const fn (f64, i32) callconv(.c) f64,
};

var libm_handle: ?std.DynLib = null;
var libm_cache: ?Libm = null;

pub fn getLibm() Libm {
    if (libm_cache) |m| return m;
    const m = resolve() orelse fallback();
    libm_cache = m;
    return m;
}

fn resolve() ?Libm {
    const builtin = @import("builtin");
    const lib_name = if (builtin.os.tag.isDarwin()) "libSystem.dylib" else "libm.so.6";
    var handle = std.DynLib.open(lib_name) catch return null;
    const lib = &handle;
    const sin = lib.lookup(*const fn (f64) callconv(.c) f64, "sin") orelse return null;
    const cos = lib.lookup(*const fn (f64) callconv(.c) f64, "cos") orelse return null;
    const tan = lib.lookup(*const fn (f64) callconv(.c) f64, "tan") orelse return null;
    const asin = lib.lookup(*const fn (f64) callconv(.c) f64, "asin") orelse return null;
    const acos = lib.lookup(*const fn (f64) callconv(.c) f64, "acos") orelse return null;
    const atan2 = lib.lookup(*const fn (f64, f64) callconv(.c) f64, "atan2") orelse return null;
    const log = lib.lookup(*const fn (f64) callconv(.c) f64, "log") orelse return null;
    const log2 = lib.lookup(*const fn (f64) callconv(.c) f64, "log2") orelse return null;
    const log10 = lib.lookup(*const fn (f64) callconv(.c) f64, "log10") orelse return null;
    const exp = lib.lookup(*const fn (f64) callconv(.c) f64, "exp") orelse return null;
    const pow = lib.lookup(*const fn (f64, f64) callconv(.c) f64, "pow") orelse return null;
    const fmod = lib.lookup(*const fn (f64, f64) callconv(.c) f64, "fmod") orelse return null;
    const frexp = lib.lookup(*const fn (f64, *i32) callconv(.c) f64, "frexp") orelse return null;
    const ldexp = lib.lookup(*const fn (f64, i32) callconv(.c) f64, "ldexp") orelse return null;
    libm_handle = handle;
    return Libm{
        .sin = sin, .cos = cos, .tan = tan, .asin = asin, .acos = acos,
        .atan2 = atan2, .log = log, .log2 = log2, .log10 = log10, .exp = exp,
        .pow = pow, .fmod = fmod, .frexp = frexp, .ldexp = ldexp,
    };
}

fn fallback() Libm {
    return Libm{
        .sin = fbSin, .cos = fbCos, .tan = fbTan, .asin = fbAsin, .acos = fbAcos,
        .atan2 = fbAtan2, .log = fbLog, .log2 = fbLog2, .log10 = fbLog10, .exp = fbExp,
        .pow = fbPow, .fmod = fbFmod, .frexp = fbFrexp, .ldexp = fbLdexp,
    };
}

fn fbSin(x: f64) callconv(.c) f64 {
    return @sin(x);
}
fn fbCos(x: f64) callconv(.c) f64 {
    return @cos(x);
}
fn fbTan(x: f64) callconv(.c) f64 {
    return @tan(x);
}
fn fbAsin(x: f64) callconv(.c) f64 {
    return std.math.asin(x);
}
fn fbAcos(x: f64) callconv(.c) f64 {
    return std.math.acos(x);
}
fn fbAtan2(y: f64, x: f64) callconv(.c) f64 {
    return std.math.atan2(y, x);
}
fn fbLog(x: f64) callconv(.c) f64 {
    return @log(x);
}
fn fbLog2(x: f64) callconv(.c) f64 {
    return std.math.log2(x);
}
fn fbLog10(x: f64) callconv(.c) f64 {
    return std.math.log10(x);
}
fn fbExp(x: f64) callconv(.c) f64 {
    return std.math.exp(x);
}
fn fbPow(x: f64, y: f64) callconv(.c) f64 {
    return std.math.pow(f64, x, y);
}
const c_fmod = @extern(*const fn (f64, f64) callconv(.c) f64, .{ .name = "fmod" });
fn fbFmod(x: f64, y: f64) callconv(.c) f64 {
    return c_fmod(x, y);
}
fn fbFrexp(x: f64, exp: *i32) callconv(.c) f64 {
    const r = std.math.frexp(x);
    exp.* = r.exponent;
    return r.significand;
}
fn fbLdexp(x: f64, exp: i32) callconv(.c) f64 {
    return std.math.ldexp(x, exp);
}
