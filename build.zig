const std = @import("std");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});
    const target = b.standardTargetOptions(.{});

    _ = b.addModule("cfmt", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const tests = b.addTest(.{
        .name = "cfmt_tests",
        .root_source_file = b.path("src/root.zig"),
        .optimize = optimize,
        .target = target,
    });
    b.installArtifact(tests);

    const test_step = b.step("test", "Test the library");
    const run_tests = b.addRunArtifact(tests);
    run_tests.has_side_effects = true;
    run_tests.step.dependOn(b.getInstallStep());
    test_step.dependOn(&run_tests.step);
}
