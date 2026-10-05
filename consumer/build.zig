// SPDX-License-Identifier: Apache-2.0
//
// Fork-authored; `FORK-LICENSE.md` records the grant and on whose authority,
// and `NOTICE.md` carries the file inventory. Nothing here reaches upstream's
// own material.

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

    // The library's three build options are declared here and forwarded, so a
    // consumer run exercises the configuration it names rather than silently
    // falling back to the library's own defaults. Without them `zig build run
    // -Dlinkage=dynamic` would build the shared variant for nobody and link
    // this program against the static one, and `zig build run -Druntime=true`
    // would run a linked configuration while claiming a loaded one; either
    // would be a gate that had checked nothing.
    //
    // All three are passed unconditionally because all three are declared by the
    // library's `build.zig`, which this package resolves at `..`.
    // `b.dependency` fails loudly on an option the dependency does not declare,
    // so a name drifting apart here is a configure error rather than a default
    // nobody noticed.
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
    // Forwarded so `zig build run -Druntime=true -- --provider <file>` and the
    // sibling `--system <name>` reach `src/main.zig`, which reads both and
    // falls back to `RYU_PROVIDER` otherwise. With no arguments this is inert,
    // so a linked run is unchanged.
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run", "Build and run the consumer program");
    run_step.dependOn(&run_exe.step);
}