// SPDX-License-Identifier: Apache-2.0

const std = @import("std");

const manifest = @import("build.zig.zon");

/// Shared module factory; avoid duplicate runtime-core type instances.
const runtime_graph = @import("runtime/graph.zig");

/// Parsed manifest version used in generated package metadata.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

const lib_name = "ryu";

const c_flags = [_][]const u8{
    "-std=gnu17",
};

const core_sources = [_][]const u8{
    "ryu/d2s.c",
    "ryu/f2s.c",
    "ryu/d2fixed.c",
    "ryu/s2d.c",
    "ryu/s2f.c",
};

const installed_headers = [_]struct { source: []const u8, dest: []const u8 }{
    .{ .source = "ryu/ryu.h", .dest = "ryu/ryu.h" },
    .{ .source = "ryu/ryu_parse.h", .dest = "ryu/ryu_parse.h" },
    .{ .source = "translate.h", .dest = "translate.h" },
};

const licence_records = [_][]const u8{
    "LICENSE-Apache2",
    "LICENSE-Boost",
    "CONTRIBUTORS",
    "NOTICE.md",
    "FORK-LICENSE.md",
    "UPSTREAM.md",
    "README.upstream.md",
    "third_party/gtest/LICENSE",
    "third_party/junit/LICENSE",
    "third_party/mersenne/LICENSE",
    "third_party/jaffer/LICENSE",
    "third_party/double-conversion/LICENSE",
    "third_party/double-conversion/COPYING",
};

const check_targets = [_]std.Target.Query{
    .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .aarch64, .os_tag = .macos, .abi = .none },
    .{ .cpu_arch = .x86_64, .os_tag = .windows, .abi = .gnu },
    .{ .cpu_arch = .riscv64, .os_tag = .linux, .abi = .gnu },
    .{ .cpu_arch = .wasm32, .os_tag = .wasi },
};

const Graph = struct {
    c_lib: *std.Build.Step.Compile,
    module: *std.Build.Module,
};

const Programs = struct {
    tests: *std.Build.Step.Compile,
    smoke: *std.Build.Step.Compile,
};

/// Resolve options once before constructing target-specific graphs.
const Options = struct {
    /// Include upstream's optional generic 128-bit converter.
    generic_128: bool,
    runtime_loaded: bool,
};

/// Builds the C library and facade for one target.
/// Cross-target checks use private modules to avoid duplicate public names.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    requested_linkage: std.builtin.LinkMode,
    public: bool,
    options: Options,
) Graph {
    const linkage = deliveredLinkage(b, target, requested_linkage);

    const c_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        // The C sources and headers use libc.
        .link_libc = true,
        // Shared artifacts require position-independent code.
        .pic = if (linkage == .dynamic) true else null,
    });
    c_mod.addIncludePath(b.path("."));
    c_mod.addCSourceFiles(.{ .files = &core_sources, .flags = &c_flags });
    if (options.generic_128) {
        c_mod.addCSourceFile(.{
            .file = b.path("ryu/generic_128.c"),
            .flags = &c_flags,
        });
    }

    const c_lib = b.addLibrary(.{
        .name = lib_name,
        .linkage = linkage,
        // Upstream defines no ABI version, so leave the shared version unset.
        .version = null,
        .root_module = c_mod,
    });
    for (installed_headers) |header| {
        c_lib.installHeader(b.path(header.source), header.dest);
    }
    if (options.generic_128) {
        c_lib.installHeader(b.path("ryu/ryu_generic_128.h"), "ryu/ryu_generic_128.h");
    }

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("translate.h"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    translate_c.addIncludePath(b.path("."));
    // Keep translated generic-128 declarations in step with the compiled source.
    if (options.generic_128) {
        translate_c.defineCMacro("RYU_TRANSLATE_GENERIC_128", "1");
    }
    // Runtime dispatch owns the translated module; avoid duplicate nominal types.
    const linked_c_module: ?*std.Build.Module = if (public and !options.runtime_loaded)
        translate_c.addModule("c")
    else
        null;

    const module = if (public)
        b.addModule(lib_name, .{
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
    if (options.runtime_loaded) {
        // Runtime dispatch owns symbol resolution; do not link the archive.
        module.addImport("c", runtime_graph.createModule(b, translate_c, target, optimize));
    } else {
        // Link the archive through the facade module for dependents.
        module.addImport("c", linked_c_module orelse translate_c.createModule());
        module.addImport("rt", runtime_graph.createCoreModule(b, target, optimize));
        module.linkLibrary(c_lib);
    }

    return .{ .c_lib = c_lib, .module = module };
}

/// Emits relocatable pkg-config metadata for either linkage.
fn addPkgConfig(b: *std.Build) std.Build.LazyPath {
    return b.addWriteFiles().add("ryu.pc", b.fmt(
        \\# Generated by ryu/build.zig. Upstream ships no pkg-config file,
        \\# so this one is fork-authored; do not edit it by hand.
        \\#
        \\# `prefix` is this file's own directory, so the metadata is right
        \\# wherever the prefix is placed; that spelling needs pkg-config 0.29+
        \\# or pkgconf.
        \\prefix=${{pcfiledir}}/../..
        \\exec_prefix=${{prefix}}
        \\libdir=${{exec_prefix}}/lib
        \\includedir=${{prefix}}/include
        \\
        \\Name: ryu
        \\Description: Shortest, fixed and scientific IEEE-754 to decimal conversion, and experimental string parsers, from ulfjack/ryu
        \\URL: https://github.com/ulfjack/ryu
        \\Version: {f}
        \\Cflags: -I${{includedir}}
        \\Libs: -L${{libdir}} -lryu
        \\Libs.private: -lc
        \\
    , .{manifest_version}));
}

fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        b.installFile(record, b.fmt("share/licenses/{s}/{s}", .{ lib_name, record }));
    }
}

fn addZigPrograms(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.lang.Optimize,
    graph: Graph,
) Programs {
    const test_mod = b.createModule(.{
        .root_source_file = b.path("tests.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    test_mod.addImport(lib_name, graph.module);
    const tests = b.addTest(.{ .root_module = test_mod });

    const smoke_mod = b.createModule(.{
        .root_source_file = b.path("smoke.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    smoke_mod.addImport(lib_name, graph.module);
    const smoke = b.addExecutable(.{
        .name = "ryu-smoke",
        .root_module = smoke_mod,
    });

    return .{ .tests = tests, .smoke = smoke };
}

/// Compiles the library, tests and smoke example for one matrix target.
/// Excludes matrix targets outside the selected options' platform boundaries.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.lang.Optimize,
    linkage: std.builtin.LinkMode,
    options: Options,
) void {
    const cross_target = b.resolveTargetQuery(query);

    if (linkage == .dynamic and !targetCarriesSharedObject(cross_target)) return;
    if (options.runtime_loaded) switch (cross_target.result.os.tag) {
        .wasi, .emscripten, .freestanding => return,
        else => {},
    };
    // Upstream marks generic_128 as nowindows in ryu/BUILD.
    if (options.generic_128 and cross_target.result.os.tag == .windows) return;

    const cross = addGraph(b, cross_target, optimize, linkage, false, options);
    const programs = addZigPrograms(b, cross_target, optimize, cross);
    step.dependOn(&cross.c_lib.step);
    step.dependOn(&programs.tests.step);
    step.dependOn(&programs.smoke.step);
}

/// Windows uses PE/COFF shared libraries despite a `.none` linker kind.
/// WASI has no shared-object loader.
fn targetCarriesSharedObject(target: std.Build.ResolvedTarget) bool {
    if (target.result.os.tag == .windows) return true;
    return std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

fn sharedObjectRefusal(b: *std.Build, target: std.Build.ResolvedTarget) ?[]const u8 {
    if (targetCarriesSharedObject(target)) return null;
    return b.fmt(
        "-Dlinkage=dynamic cannot deliver shared objects for {s}: its OS has no " ++
            "dynamic linker (std.Target.DynamicLinker.kind is .none), so a shared " ++
            "object there is a file nothing can load. No static substitution is " ++
            "made. Build this target with -Dlinkage=static, which is the default.",
        .{@tagName(target.result.os.tag)},
    );
}

fn deliveredLinkage(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    requested: std.builtin.LinkMode,
) std.builtin.LinkMode {
    if (requested == .dynamic) {
        if (sharedObjectRefusal(b, target)) |reason| std.debug.panic("ryu: {s}", .{reason});
    }
    return requested;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(
        std.builtin.LinkMode,
        "linkage",
        "Deliver the native library as a static archive (the default, and " ++
            "what this package has always installed) or as a real shared " ++
            "object. This selects the artifact and nothing else about the " ++
            "compilation: the same sources, the same -std=gnu17 and the same " ++
            "include root either way. No soname is set, because upstream " ++
            "publishes no ABI number, and no export list is generated, because " ++
            "upstream declares no visibility or dllexport macro in either " ++
            "public header. A target whose platform cannot carry a shared object " ++
            "(wasm32-wasi in this package's own matrix; a Windows target can, and " ++
            "does) refuses -Dlinkage=dynamic: for the selected target the build " ++
            "stops at configure time naming it; `check` excludes unsupported " ++
            "matrix targets. Nothing is ever substituted.",
    ) orelse .static;

    const runtime_loaded = b.option(
        bool,
        "runtime",
        "Resolve the native entry points at run time instead of linking them. " ++
            "The facade keeps the same translated header and the same public " ++
            "types; each declared native function becomes a dispatch through " ++
            "one process-lifetime table that an explicit load(source) fills, and " ++
            "the module links no archive. Independent of -Dlinkage, which still " ++
            "decides which artifact this build delivers and installs. Default off, " ++
            "and a linked build is unchanged in every respect.",
    ) orelse false;

    const options: Options = .{
        .generic_128 = b.option(
            bool,
            "generic128",
            "Also build upstream's experimental generic 128-bit shortest converter (ryu/generic_128.c), install ryu/ryu_generic_128.h and translate it, so the facade's `generic128` namespace and the runtime dispatch carry its five converters and FD128_EXCEPTIONAL_EXPONENT as well as the default sixteen. Upstream tags it 'nowindows'; it is off by default and the cross-target check excludes Windows when enabled. Independent of -Dlinkage: it joins whichever artifact that option selected.",
        ) orelse false,
        .runtime_loaded = runtime_loaded,
    };

    const published = addGraph(b, target, optimize, linkage, true, options);
    b.installArtifact(published.c_lib);

    // addInstallFile needs an explicit dependency; installFile attaches itself.
    b.getInstallStep().dependOn(
        &b.addInstallFile(addPkgConfig(b), "lib/pkgconfig/ryu.pc").step,
    );
    installLicenceRecords(b);

    const programs = addZigPrograms(b, target, optimize, published);
    // Compile the smoke example in the default install step, but do not install it.
    b.getInstallStep().dependOn(&programs.smoke.step);

    const smoke_step = b.step("smoke", "Run the smoke example");
    smoke_step.dependOn(&b.addRunArtifact(programs.smoke).step);

    b.step("test", "Run the behavioural tests").dependOn(&b.addRunArtifact(programs.tests).step);

    // Compile the native graph and compatible matrix targets without running them.
    const check_step = b.step(
        "check",
        "Compile the C core, translated interface, tests and smoke example for matrix targets compatible with the selected options",
    );
    if (target.query.isNative()) {
        check_step.dependOn(&published.c_lib.step);
        check_step.dependOn(&programs.tests.step);
        check_step.dependOn(&programs.smoke.step);
        for (check_targets) |query| {
            addTargetCheck(b, check_step, query, optimize, linkage, options);
        }
    } else {
        addTargetCheck(b, check_step, target.query, optimize, linkage, options);
    }

    std.debug.print("ryu: {s}, {s}, {s}\n", .{
        switch (deliveredLinkage(b, target, linkage)) {
            .static => "static archive (default)",
            .dynamic => switch (target.result.os.tag) {
                .windows => "shared object, ryu.dll (upstream declares no export macro; the export table is the link driver's)",
                .macos => "shared object, libryu.dylib",
                else => "shared object, libryu.so (upstream publishes no soname)",
            },
        },
        if (options.generic_128) "with -Dgeneric128" else "(default source closure)",
        if (runtime_loaded)
            "runtime-loaded dispatch (-Druntime=true); no library is linked into the module"
        else
            "linked dispatch (direct calls)",
    });
}
