//! Build for the `ryu` package: upstream's C conversion core, compiled from
//! this repository, and a Zig facade over it.
//!
//! Run `zig build --help` for the steps and options this file declares. The
//! shape is:
//!
//!   zig build              build the C library and compile the smoke example
//!   zig build test         run the behavioural tests
//!   zig build smoke        run the smoke example
//!   zig build check        compile everything for the six required cross
//!                          targets, running nothing
//!
//!   cross-test          the same `test` step, for the published 53-platform
//!                      Zig 0.16.0 Tier 1/2 table rather than the host alone.
//!                      `cross-test` discovers `cross-test.profile.sh` from
//!                      the package root, runs `zig build test -Dtarget=TARGET`
//!                      for each of them over the default source closure, and
//!                      executes the binary where a runner exists and records
//!                      explicit `build_only` coverage where one does not.
//!                      `build()` resolves `-Dtarget` into the same graph the
//!                      `test` step above uses and never narrows it to the
//!                      host, so every platform in that table compiles the
//!                      five `core_sources` translation units and runs the
//!                      same `tests.zig`.
//!
//! Options
//!
//!   -Doptimize=...        standard; the gates use Debug and ReleaseSafe
//!   -Dtarget=...          standard; a non-native value makes `check` check
//!                         that one target instead of the six
//!   -Dgeneric128          also build upstream's experimental generic 128-bit
//!                         shortest converter. Off by default; see below.
//!
//! Nothing is downloaded and nothing is installed behind the caller's back.
//! The only compiled C is the five translation units named in
//! `core_sources`, taken from `ryu/` in this tree, and the include root is
//! this repository's root, which is the include root upstream's sources
//! already assume (`ryu/d2s.c:43-45`, `CMakeLists.txt:20-21`).
//!
//! ## What is built, and what is experimental
//!
//! `d2s.c`, `f2s.c` and `d2fixed.c` are upstream's stable core: shortest,
//! fixed and scientific formatting for `float` and `double`, published in
//! `ryu/ryu.h`. `s2d.c` and `s2f.c` are upstream's experimental parsers,
//! published in `ryu/ryu_parse.h`, whose own comment sets the limit: "At this
//! time, it only support up to 17 non-zero digits in the input, and also does
//! not support all formats. Use at your own risk." (`ryu/ryu_parse.h:25-27`).
//! They are built unconditionally because a fork that drops them is not the
//! same library, and their limits are the caller's to respect, not the build
//! file's to trim.
//!
//! `generic_128.c` is the third experimental piece and is *not* built by
//! default. Upstream builds it as a separate target tagged `nowindows`
//! (`ryu/BUILD:38-49`) and gates its own CMake target on the compiler
//! providing `__uint128_t` (`CMakeLists.txt:31-52`). `-Dgeneric128` turns it
//! on for a caller that wants `float_to_fd128` and friends; the header is
//! installed with it. The default graph, and therefore the six-target `check`,
//! never depends on it.
//!
//! ## Why there is no `b.systemIntegrationOption`
//!
//! This package deliberately offers no system-library mode, so the fork
//! rule about `b.systemIntegrationOption` is recorded as *not satisfied* and
//! not as vacuous-in-the-same-way-a-header-only-library-is: the reason is
//! that no installed ryu can supply this package's published surface.
//!
//!   * On this host no installed ryu was found: a file search of `/usr/include`
//!     for `ryu*` and of `/usr/lib` for `libryu*` returned nothing (checked
//!     2026-10-01, before any build was attempted). That is an observation
//!     about one machine, not a claim about every distribution.
//!   * Even where a distribution does install ryu, upstream's own install
//!     rules publish `ryu/ryu.h` and, when the compiler has `__uint128_t`,
//!     `ryu/ryu_generic_128.h` (`CMakeLists.txt:27-28,46-47`), and never
//!     `ryu_parse.h`. `s2d.c` and `s2f.c` are not in the CMake library target
//!     at all (`CMakeLists.txt:6-18`), so the parsers this package builds and
//!     installs would be unresolvable against an installed ryu.
//!   * Translating our headers against an installed library is exactly the
//!     failure mode the fork rule forbids: a bundled header newer than the
//!     installed ABI compiles and then misbehaves quietly.
//!
//! A mode that linked `-lryu` for formatting and compiled the parsers from
//! this tree would be a fork-specific hybrid with no upstream precedent and no
//! way to verify an installed ABI here, so it is not offered. A caller who
//! wants an installed ryu can link it directly; a caller who wants these
//! parsers needs this tree.
//!
//! ## How `check` proves the facade
//!
//! Zig analyses a function body only when something calls it, so compiling a
//! C archive proves nothing about the facade, and reflecting over the module
//! proves nothing either. `check` therefore compiles `tests.zig` and
//! `smoke.zig`, the two files at the root that are the package's only callers
//! of the public surface, for every target in the matrix. That is a standing
//! obligation on those two files, not on this script: every public
//! declaration in `zig/root.zig` must be called from one of them, or `check`
//! stops covering it. Namespacing is not a call: a function reached through
//! a public namespace still needs its own call site, because the namespace
//! itself has no body to analyse. Nothing is executed for a cross target, so
//! a passing `check` is compile evidence and not a claim that a foreign
//! binary ran.

const std = @import("std");

/// Flags the canonical C sources need on every target.
///
/// `-std=gnu17` pins the dialect instead of inheriting the compiler's
/// default, which has moved between releases. Upstream's sources are C99-era
/// and compile unchanged under `gnu17`; pinning it means a future default
/// cannot silently change how these bytes are parsed.
///
/// Nothing else is passed, and that is a finding rather than an omission.
/// Upstream's core converts a `double` by copying its bits
/// (`ryu/common.h:108-112`, `double_to_bits`) and then works in integer
/// arithmetic on `uint64_t`/`__uint128_t`; no result depends on how the
/// compiler rounds, contracts or reassociates floating-point arithmetic, so
/// `-ffp-contract=off` and friends would guard a risk this code does not
/// have.
const c_flags = [_][]const u8{
    "-std=gnu17",
};

/// The stable conversion core plus upstream's experimental parsers.
///
/// Every source in `ryu/` spells its includes as `ryu/<name>.h`, so these
/// names are relative to this repository's root and are listed the way the
/// rest of upstream's build files list them (`ryu/BUILD:7-19` for the core,
/// `ryu/BUILD:24-36` for the parsers).
const core_sources = [_][]const u8{
    "ryu/d2s.c",
    "ryu/f2s.c",
    "ryu/d2fixed.c",
    "ryu/s2d.c",
    "ryu/s2f.c",
};

/// The headers installed with the library, in the layout they are included
/// in: `include/ryu/ryu.h` and `include/ryu/ryu_parse.h`, which is also the
/// layout the aggregate `translate.h` expects, and the layout upstream's own
/// install rule produces (`CMakeLists.txt:28`).
const installed_headers = [_]struct { source: []const u8, dest: []const u8 }{
    .{ .source = "ryu/ryu.h", .dest = "ryu/ryu.h" },
    .{ .source = "ryu/ryu_parse.h", .dest = "ryu/ryu_parse.h" },
    // The aggregate header this package translates and installs, so that a C
    // consumer of the installed tree can reach both public APIs through one
    // name instead of writing both includes itself.
    .{ .source = "translate.h", .dest = "translate.h" },
};

/// The six targets `check` compiles for.
///
/// Nothing here is pre-judged. If a target turns out to need something this
/// machine lacks, that is for the gate to report, not for the build script to
/// guess at and quietly skip.
const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

const Graph = struct {
    /// The compiled C library. This is the artifact a C consumer links, and
    /// the one the facade module carries so a dependent gets it by asking
    /// for the module alone.
    c_lib: *std.Build.Step.Compile,
    /// The Zig facade, with `c` bound to the translated `translate.h`.
    module: *std.Build.Module,
};

const Programs = struct {
    /// The behaviour suite, `tests.zig`. Built by `test` and run there; built
    /// and not run by `check`.
    tests: *std.Build.Step.Compile,
    /// The smoke example, `smoke.zig`. Built by the default step and by
    /// `check`; built and run by `smoke`.
    smoke: *std.Build.Step.Compile,
};

/// Everything the build learns from `-D` options, resolved once in `build`
/// so that a repeated `addGraph` call for each cross target cannot re-read
/// them or register them twice.
const Options = struct {
    /// Build upstream's experimental generic 128-bit converter too.
    generic_128: bool,
};

/// Builds the C library and the facade for one target.
///
/// `public` selects between the package module set, which is what a dependent
/// reaches through `dep.module("ryu")`, and a private module. A cross-target
/// check needs the private form: modules are registered by name against the
/// whole build, so registering `ryu` once per cross target would leave only
/// the last of them reachable and silently stop checking the rest.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    public: bool,
    options: Options,
) Graph {
    const c_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        // libc, because `ryu/ryu.h` includes <stdint.h>, the sources
        // include <string.h> and <stdlib.h>, and `d2s`, `f2s`, `d2fixed` and
        // `d2exp` allocate the buffers they hand back (`ryu/d2s.c:505-509`,
        // `ryu/d2fixed.c:557-562`).
        .link_libc = true,
    });
    // This repository's root, because that is the include root upstream's own
    // sources and install layout assume: they include `"ryu/ryu.h"` and the
    // headers land in `<prefix>/include/ryu/` (`CMakeLists.txt:20-21,28`).
    c_mod.addIncludePath(b.path("."));
    c_mod.addCSourceFiles(.{ .files = &core_sources, .flags = &c_flags });
    if (options.generic_128) {
        // No include path and no macro is added for this one beyond the root
        // above; `generic_128.c` asks for `__uint128_t` itself
        // (`ryu/ryu_generic_128.h:42`) and for a working `long double`
        // (`ryu/generic_128.c:70-73`). Whether the compiler being used has
        // them is the compiler's answer for this target, and no
        // `-DRYU_*` flag is defined here to paper over it.
        c_mod.addCSourceFile(.{
            .file = b.path("ryu/generic_128.c"),
            .flags = &c_flags,
        });
    }

    const c_lib = b.addLibrary(.{
        .name = "ryu",
        // Upstream's CMake installs whatever the consumer asked for and
        // defaults to a static library; so does this.
        .linkage = .static,
        .root_module = c_mod,
    });
    for (installed_headers) |header| {
        c_lib.installHeader(b.path(header.source), header.dest);
    }
    if (options.generic_128) {
        c_lib.installHeader(b.path("ryu/ryu_generic_128.h"), "ryu/ryu_generic_128.h");
    }

    // The aggregate header, translated for the target being built rather than
    // for this machine: `addTranslateC` is handed the same `target`, so every
    // header it pulls in - `<stdint.h>`, `ryu/ryu.h`, `ryu/ryu_parse.h` - is
    // that target's own. Those two are upstream's headers as upstream ships
    // them, with one disclosed exception: `ryu/ryu.h:24` reads `<stdint.h>`
    // here and `<inttypes.h>` upstream. The header uses that include for
    // `uint32_t` alone, and NetBSD's `<inttypes.h>` cannot be read by the
    // pinned translator on any of its nine cells; `translate.h` records the
    // change and the reason. Nothing about this step is target-conditional -
    // one graph, one root header, all 53 cells.
    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("translate.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    // Same include root as the C above, so `<ryu/ryu.h>` and
    // `<ryu/ryu_parse.h>` resolve to this repository's headers by the same
    // rule the C sources' quoted includes do.
    translate_c.addIncludePath(b.path("."));
    const c_module = if (public)
        translate_c.addModule("c")
    else
        translate_c.createModule();

    const module = if (public)
        b.addModule("ryu", .{
            .root_source_file = b.path("zig/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        })
    else
        b.createModule(.{
            .root_source_file = b.path("zig/root.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
    module.addImport("c", c_module);
    // Transitive linking: `dep.module("ryu")` has to carry the compiled
    // archive, or a dependent would compile the facade against declarations
    // with nothing behind them and fail only at link time.
    module.linkLibrary(c_lib);

    return .{ .c_lib = c_lib, .module = module };
}

/// Builds the Zig side for one target: the test binary and the smoke example,
/// both of which import the facade under the module name a dependent uses.
///
/// Returns the two compile steps so a caller can depend on the builds
/// themselves (`check`, which runs nothing) or on a run of them (`test` and
/// `smoke`, which do).
fn addZigPrograms(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    graph: Graph,
) Programs {
    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport("ryu", graph.module);
    const tests = b.addTest(.{ .root_module = test_mod });

    const smoke_mod = b.createModule(.{
        .root_source_file = b.path("smoke.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    smoke_mod.addImport("ryu", graph.module);
    const smoke = b.addExecutable(.{
        .name = "ryu-smoke",
        .root_module = smoke_mod,
    });

    return .{ .tests = tests, .smoke = smoke };
}

/// Compiles the C library, the tests and the smoke example for one target and
/// attaches every one of them to `step`.
///
/// Compiling the tests and the example is what makes this a check of the
/// facade rather than of an unreferenced archive: Zig analyses a function body
/// only when something calls it, and those two files are the package's only
/// callers of the public surface. Nothing is run here, so every result is
/// compile evidence, never a claim that a foreign binary executed.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    options: Options,
) void {
    const cross_target = b.resolveTargetQuery(query);
    const cross = addGraph(b, cross_target, optimize, false, options);
    const programs = addZigPrograms(b, cross_target, optimize, cross);
    step.dependOn(&cross.c_lib.step);
    step.dependOn(&programs.tests.step);
    step.dependOn(&programs.smoke.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options: Options = .{
        .generic_128 = b.option(
            bool,
            "generic128",
            "Also build upstream's experimental generic 128-bit shortest converter (ryu/generic_128.c) and install ryu/ryu_generic_128.h. Upstream tags it 'nowindows'; it is off by default and the cross-target check never builds it.",
        ) orelse false,
    };

    const graph = addGraph(b, target, optimize, true, options);
    b.installArtifact(graph.c_lib);

    const programs = addZigPrograms(b, target, optimize, graph);
    // `zig build` installs the library with its headers and compiles the smoke
    // example. The example is not installed: it is a proof that the facade and
    // the C agree on types, symbols and link-time dependencies, not a
    // deliverable.
    b.getInstallStep().dependOn(&programs.smoke.step);

    // A run artifact already depends on building the executable. `zig build
    // smoke` deliberately does not pull in the install step: installing is
    // `zig build`'s job, and conflating the two would make a smoke run depend
    // on the install layout.
    const smoke_step = b.step("smoke", "Run the smoke example");
    smoke_step.dependOn(&b.addRunArtifact(programs.smoke).step);

    // The test root is `tests.zig`, the file that names the behavioural tests.
    b.step("test", "Run the behavioural tests").dependOn(&b.addRunArtifact(programs.tests).step);

    // The cross-target gate. With no `-Dtarget` this walks all six targets and
    // additionally builds the native test binary, because the native C library
    // and the native smoke example belong to the default graph and a `check`
    // that only looked at foreign targets would not cover them. An explicit
    // `-Dtarget` limits the gate to that one target; no target is ever dropped
    // silently, and none is skipped because it looks inconvenient.
    const check_step = b.step(
        "check",
        "Compile the C core, the translated interface, the tests and the smoke example for the six-target matrix without running anything",
    );
    if (target.query.isNative()) {
        check_step.dependOn(&graph.c_lib.step);
        check_step.dependOn(&programs.tests.step);
        check_step.dependOn(&programs.smoke.step);
        for (check_targets) |query| {
            addTargetCheck(b, check_step, query, optimize, options);
        }
    } else {
        addTargetCheck(b, check_step, target.query, optimize, options);
    }
}
