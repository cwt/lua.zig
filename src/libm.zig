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
//
// BUG-174 P3: `getLibm` returns `*const Libm` (a pointer to a process-lifetime
// singleton) instead of copying the 14-pointer (112-byte) struct by value on
// every call. A hot caller like `math.log` previously paid that 112-byte
// copy + spills in every invocation; now it loads a single 8-byte pointer
// from global storage and reads only the one function pointer it needs.
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

// Process-lifetime singletons. `libm_resolved` is filled by `resolve` on first
// use and is valid only once `libm_resolved_ok` is true; `libm_fallback` is a
// const readonly global wired to std.math / compiler-rt fallbacks. Both live
// at fixed addresses, so `getLibm` can hand out pointers to them.
var libm_handle: ?std.DynLib = null;
var libm_resolved: Libm = undefined;
var libm_resolved_ok: bool = false;
const libm_fallback: Libm = Libm{
    .sin = fbSin, .cos = fbCos, .tan = fbTan, .asin = fbAsin, .acos = fbAcos,
    .atan2 = fbAtan2, .log = fbLog, .log2 = fbLog2, .log10 = fbLog10, .exp = fbExp,
    .pow = fbPow, .fmod = fbFmod, .frexp = fbFrexp, .ldexp = fbLdexp,
};

pub fn getLibm() *const Libm {
    if (libm_resolved_ok) return &libm_resolved;
    if (resolve() == true) {
        libm_resolved_ok = true;
        return &libm_resolved;
    }
    return &libm_fallback;
}

// Looks up every symbol in the hosted libm and fills the `libm_resolved`
// singleton. Returns false (and leaves the singleton untouched) if the library
// or any one symbol cannot be resolved, in which case `getLibm` reports the
// fallback instead.
fn resolve() bool {
    const builtin = @import("builtin");
    const lib_name = if (builtin.os.tag.isDarwin()) "libSystem.dylib" else "libm.so.6";
    var handle = std.DynLib.open(lib_name) catch return false;
    const lib = &handle;
    const sin = lib.lookup(*const fn (f64) callconv(.c) f64, "sin") orelse return false;
    const cos = lib.lookup(*const fn (f64) callconv(.c) f64, "cos") orelse return false;
    const tan = lib.lookup(*const fn (f64) callconv(.c) f64, "tan") orelse return false;
    const asin = lib.lookup(*const fn (f64) callconv(.c) f64, "asin") orelse return false;
    const acos = lib.lookup(*const fn (f64) callconv(.c) f64, "acos") orelse return false;
    const atan2 = lib.lookup(*const fn (f64, f64) callconv(.c) f64, "atan2") orelse return false;
    const log = lib.lookup(*const fn (f64) callconv(.c) f64, "log") orelse return false;
    const log2 = lib.lookup(*const fn (f64) callconv(.c) f64, "log2") orelse return false;
    const log10 = lib.lookup(*const fn (f64) callconv(.c) f64, "log10") orelse return false;
    const exp = lib.lookup(*const fn (f64) callconv(.c) f64, "exp") orelse return false;
    const pow = lib.lookup(*const fn (f64, f64) callconv(.c) f64, "pow") orelse return false;
    const fmod = lib.lookup(*const fn (f64, f64) callconv(.c) f64, "fmod") orelse return false;
    const frexp = lib.lookup(*const fn (f64, *i32) callconv(.c) f64, "frexp") orelse return false;
    const ldexp = lib.lookup(*const fn (f64, i32) callconv(.c) f64, "ldexp") orelse return false;
    libm_handle = handle;
    libm_resolved = .{
        .sin = sin, .cos = cos, .tan = tan, .asin = asin, .acos = acos,
        .atan2 = atan2, .log = log, .log2 = log2, .log10 = log10, .exp = exp,
        .pow = pow, .fmod = fmod, .frexp = frexp, .ldexp = ldexp,
    };
    return true;
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
