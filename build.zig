const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const root_module = b.createModule(.{
        .root_source_file = b.path("src/luazig.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

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

    b.installArtifact(exe);

    const lib = b.addLibrary(.{
        .name = "lua",
        .root_module = root_module,
    });
    lib.lto = if (use_lto) .thin else .none;

    b.installArtifact(lib);

    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests/test_basic.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_mod.addImport("lua", lua_module);

    const test_exe = b.addTest(.{
        .name = "test_basic",
        .root_module = test_mod,
    });

    const run_tests = b.addRunArtifact(test_exe);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);

    const run_step = b.step("run", "Build and run luazig");
    run_step.dependOn(&exe.step);

    const lib_step = b.step("lib", "Build lua library");
    lib_step.dependOn(&lib.step);
}
