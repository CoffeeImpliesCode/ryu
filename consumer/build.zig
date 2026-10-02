const std = @import("std");

/// A package that consumes `ryu` from outside.
///
/// This exists to prove one thing: that a dependent needs only
/// `dep.module("ryu")` and gets a working, correctly linked library. If the
/// facade module stopped carrying its C artifact, or the translated header
/// stopped matching the C source, this would stop building or stop producing
/// the answers below, and nothing inside the library would notice.
///
/// Run it with `zig build run`. It exits non-zero if any answer disagrees with
/// the one upstream publishes for that exact value, so it is a check and not a
/// demo.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep = b.dependency("ryu", .{
        .target = target,
        .optimize = optimize,
    });

    // No `link_libc` here on purpose. The C requirement belongs to the library
    // module, which carries it; a dependent states its own, and this program
    // needs nothing beyond what the library already brings. Adding it here
    // would hide a library that forgot to declare it.
    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_mod.addImport("ryu", dep.module("ryu"));

    const exe = b.addExecutable(.{
        .name = "ryu-consumer",
        .root_module = exe_mod,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
