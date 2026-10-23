// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

/// Builds and runs an external consumer through `dep.module("ryu")`.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Forward all three library options so this run matches the requested configuration.
    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Forwarded to the ryu package: the delivery variant its module carries. Static is the library's own default and is repeated here so this option means the same thing in both packages. A target whose OS has no dynamic linker refuses `dynamic` in the library, and refuses it here too, by refusing to forward it.",
    ) orelse .static;

    const generic_128 = b.option(
        bool,
        "generic128",
        "Forwarded to the ryu package: also build upstream's experimental generic 128-bit shortest converter and translate its header, so the facade's `generic128` namespace and the runtime dispatch carry its five converters as well as the default sixteen.",
    ) orelse false;

    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Forwarded to the ryu package: resolve the native entry points through the platform loader instead of linking them, which this program then reaches through an explicit `ryu.load(...)`. Independent of `-Dlinkage`, which still decides which artifact the library builds and installs.",
    ) orelse false;

    const dep = b.dependency("ryu", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
        .generic128 = generic_128,
        .runtime = runtime_loaded,
    });

    // The dependency module declares its libc requirement.
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
    // Forward runtime-provider arguments to the consumer.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}
