const std = @import("std");

// Configure the build graph (`b`) that will be then executed by an external runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // The main zig module
    const mod = b.addModule("minesweeper", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    // The executable and its root module.
    const exe = b.addExecutable(.{
        .name = "minesweeper",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "minesweeper", .module = mod },
            },
        }),
    });

    // Put the executable under `zig-out` when building.
    b.installArtifact(exe);

    // The run step
    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);

    // Run from the installation dir (`zig-out`) rather than from the cache dir.
    run_cmd.step.dependOn(b.getInstallStep());

    // Allow the user to pass arguments to the application in the build
    // command itself, like this: `zig build run -- arg1 arg2 etc`
    run_cmd.addPassthruArgs();

    // Creates an executable that will run `test` blocks from the provided module.
    const mod_tests = b.addTest(.{
        .root_module = mod,
    });

    // A run step for the test executable.
    const run_mod_tests = b.addRunArtifact(mod_tests);

    // Creates an executable that will run `test` blocks from the executable's
    // root module.
    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });

    // A run step for the second test executable.
    const run_exe_tests = b.addRunArtifact(exe_tests);

    // A top level step for running all tests.
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
