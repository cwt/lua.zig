const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    // Default to ReleaseFast, matching the reference Lua's `-O2` production
    // build (`lua/makefile`: CFLAGS=-O2). ReleaseSmall (Lua's "smallest
    // binary" idea) was measurably slower than the reference; ReleaseFast
    // gives the fairest comparison (~2x, dominated by the 16-byte tagged-union
    // TValue vs the reference's 8-byte NaN-boxed values). Override with
    // `-Dmode=Debug` (e.g. for readable stack traces while developing) or
    // `-Dmode=ReleaseSmall`/`ReleaseSafe`. A Debug build is far too slow for
    // the upstream `lua/testes` suite (a 1M-deep recursion takes ~5s in Debug
    // vs ~0.08s in an optimized build), which is what times out
    // `constructs.lua`.
    const optimize = b.option(
        std.builtin.OptimizeMode,
        "mode",
        "Optimization mode (default: ReleaseFast)",
    ) orelse .ReleaseFast;

    // Memory-safety build options (mirror talyn/build.zig):
    //  - asan: build with the C sanitizer (sanitize_c = .full, i.e. UBSan),
    //    which instruments the exe/lib/test binaries for undefined-behaviour
    //    checks. Note: in Zig 0.16 this is UBSan, not heap AddressSanitizer, so
    //    it does not intercept malloc/free for double-free / use-after-free.
    //    Heap UAF/DF is caught by the safety DebugAllocator (std.testing.allocator
    //    in tests, and -Ddebug-alloc for the luazig executable).
    //  - debug-alloc: the luazig executable uses std.heap.DebugAllocator (safety)
    //    instead of init.gpa, catching heap double-free / use-after-free / leaks
    //    at runtime. Zig 0.16 has no first-class ASAN for Zig heaps (only
    //    -fsanitize-c / UBSan and -fsanitize-thread / TSan), so this is the
    //    Zig-native equivalent.
    const asan = b.option(bool, "asan", "Build with the C sanitizer (UBSan; catches undefined behaviour)") orelse false;
    const debug_alloc = b.option(
        bool,
        "debug-alloc",
        "Use std.heap.DebugAllocator (safety) for luazig's heap — catches double-free / leaks / UAF at runtime",
    ) orelse false;

    const build_options = b.addOptions();
    build_options.addOption(bool, "asan", asan);
    build_options.addOption(bool, "debug_alloc", debug_alloc);
    const build_options_module = build_options.createModule();

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/luazig.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .sanitize_c = if (asan) .full else null,
    });
    root_module.addImport("build_options", build_options_module);

    const lua_module = b.createModule(.{
        .root_source_file = b.path("src/lua.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    // LTO is only enabled for Release builds: the Debug+LTO codegen path
    // triggers an LLVM backend crash in this toolchain. ReleaseFast/ReleaseSmall
    // LTO works correctly and yields the optimized interpreter.
    const use_lto = optimize != .Debug;

    const exe = b.addExecutable(.{
        .name = "luazig",
        .root_module = root_module,
    });
    exe.lto = if (use_lto) .thin else .none;
    exe.root_module.strip = true;

    b.installArtifact(exe);

    const lib = b.addLibrary(.{
        .name = "lua",
        .root_module = root_module,
    });
    lib.lto = if (use_lto) .thin else .none;
    lib.root_module.strip = true;

    b.installArtifact(lib);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests/test_basic.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .sanitize_c = if (asan) .full else null,
    });
    test_mod.addImport("lua", lua_module);
    test_mod.addImport("build_options", build_options_module);

    const test_exe = b.addTest(.{
        .name = "test_basic",
        .root_module = test_mod,
    });

    const run_tests = b.addRunArtifact(test_exe);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
    test_step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Build and run luazig");
    run_step.dependOn(&exe.step);

    const lib_step = b.step("lib", "Build lua library");
    lib_step.dependOn(&lib.step);
}
