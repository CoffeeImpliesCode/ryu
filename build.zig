// SPDX-License-Identifier: Apache-2.0
//
// This file is fork-authored. `FORK-LICENSE.md` records the grant and on whose
// authority, and `NOTICE.md` carries the file inventory. No line below changes
// a term upstream granted: everything under `ryu/` is upstream's own and is
// dual licensed, Apache-2.0 or BSL-1.0 at the copyright holder's choice
// (`README.upstream.md:35-38`).

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
//!   -Dcpu=...             standard, through `standardTargetOptions`; a Nix
//!                         derivation passes `-Dcpu=baseline` so nothing it
//!                         builds inherits the builder's instruction set
//!   -Dlinkage=...         `static` (the default) or `dynamic`; see below
//!   -Druntime=...         `true` resolves the sixteen (or twenty-one) entry
//!                         points through the platform loader instead of
//!                         linking them; independent of `-Dlinkage`
//!   -Dgeneric128          also build upstream's experimental generic 128-bit
//!                         shortest converter. Off by default; see below.
//!
//! Nothing is downloaded and nothing is installed behind the caller's back.
//! The only compiled C is the five translation units named in
//! `core_sources`, taken from `ryu/` in this tree, and the include root is
//! this repository's root, which is the include root upstream's sources
//! already assume (`ryu/d2s.c:43-45`, `CMakeLists.txt:20-21`).
//!
//! ## Delivery: `-Dlinkage=static|dynamic`
//!
//! `static` is the default and is what this package has always installed:
//! `libryu.a`. `-Dlinkage=dynamic` installs a real shared object instead,
//! `libryu.so`, `libryu.dylib` or `ryu.dll` as the target's format spells it.
//! The option names the *artifact*; nothing here promises a wholly static
//! program, because the compiled core calls `malloc`, `memcpy`, `memset` and
//! `strlen` (`ryu/d2s.c:505-509`, `ryu/d2fixed.c:557-562`) and hands back
//! buffers its caller frees, so it needs a C library at run time either way.
//!
//! The same five (or six, under `-Dgeneric128`) translation units are compiled
//! in both variants, with the same `-std=gnu17` and the same include root. What
//! the shared variant adds is its own requirements: position-independent
//! relocatability on the module, and nothing else, because upstream declares no
//! export control of any kind. That last point is a reading of upstream's own
//! files rather than a choice this build made, and it is worth stating
//! exactly:
//!
//!   * `ryu/ryu.h` and `ryu/ryu_parse.h` decorate none of the sixteen
//!     functions they declare. There is no `RYU_API`, no
//!     `__attribute__((visibility(...)))`, no `__declspec(dllexport)` and no
//!     `extern` import pair in either header, and no macro this build could
//!     define to reach one.
//!   * `CMakeLists.txt:6-18` sets no `C_VISIBILITY_PRESET`, links no version
//!     script and writes no export list, and `CMakeLists.txt:27-28` installs
//!     `ryu/ryu.h` alone with no generated export header beside it.
//!
//! So `-fvisibility=hidden` is not passed: with no declaration carrying
//! `visibility("default")`, it would export *nothing* and the installed object
//! would have no usable surface at all. And no version script and no Win32
//! `.def` file is authored either: either one would be a second, hand-written
//! list of the public names, beside a header that already states them, and it
//! would be this build's invention rather than upstream's. The shared object
//! therefore carries the compiler's default visibility, which is exactly what
//! upstream's own shared build produces (`BUILD_SHARED_LIBS=ON` changes no
//! flag in `CMakeLists.txt`) and which exports all sixteen declared entry
//! points.
//!
//! The one platform where that leaves a question the sources do not answer is
//! Windows: with no `__declspec(dllexport)` anywhere, whether `ryu.dll` gets an
//! export table at all is a property of the link driver, not of upstream, and
//! this build does not guess at it. It is recorded here rather than in
//! `README.zig.md`, which belongs to another role, and the observation that
//! settles it is `zig build -Dtarget=x86_64-windows-gnu -Dlinkage=dynamic`
//! followed by a dump of the produced `ryu.dll`'s export table.
//!
//! **No soname is invented.** `LibraryOptions.version` stays null in both
//! variants, so the shared object is installed under its own name with no
//! `libryu.so.N`. Upstream publishes no ABI number anywhere: `CMakeLists.txt`
//! declares `project(ryu VERSION 2.0)` — which is upstream's C library version,
//! not a shared-object ABI number — and its `install(TARGETS ryu LIBRARY)` rule
//! attaches no `VERSION` or `SOVERSION` property. `blake3` has a real
//! `SOVERSION 0` to write down and does; ryu has none to copy, so the soname
//! here is the only honest one, which is none. `UPSTREAM.md` is where that
//! reading belongs, and this build does not assume it was written.
//!
//! A target whose platform cannot carry a shared object is **refused**, never
//! quietly answered with an archive: `deliveredLinkage` names the OS and stops
//! the build, because a build that hands back a static archive for a request to
//! build a shared object is reporting something it did not do. WASI is the one
//! such target in this package's own six-target `check`, and `wasm32-wasi` has
//! no dynamic linker, so `-Dtarget=wasm32-wasi -Dlinkage=dynamic` stops at
//! configure time exactly as `deliveredLinkage` says it will.
//!
//! Two things are deliberately *not* refusals, and the second one is a fact
//! about Windows rather than a convenience. `zig build check -Dlinkage=dynamic`
//! does not stop over the WASI row: that row becomes an explicit failing step
//! carrying the reason, the other five are still compiled, and nothing is built
//! for the row at all — it is not dropped either, so it cannot pass by
//! omission. And a `windows` target is not in this class, even though
//! `std.Target.DynamicLinker.kind` answers `.none` for it: a PE/COFF image has
//! no interpreter path because its imports are resolved by the loader inside the
//! OS, not because Windows cannot load a DLL. `targetCarriesSharedObject` names
//! the two families separately, so `-Dlinkage=dynamic` compiles `ryu.dll` for
//! this matrix's `x86_64-windows-gnu` cell and refuses only `wasm32-wasi`.
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
//! The five units are the whole of upstream's own core. `CMakeLists.txt:6-18`
//! and `ryu/BUILD:5-21` name the same three plus `ryu/BUILD:23-36` names the
//! two parsers, and `CMakeLists.txt` simply never adds the parser target. One
//! place where "three files" is not the whole answer: `ryu/ryu.h:38-40`
//! declares `d2exp_buffered_n`, `d2exp_buffered` and `d2exp`, and those are
//! defined in `ryu/d2fixed.c:566,809,814` beside the fixed-point writer rather
//! than in a `d2exp.c` of their own. There is no `ryu/d2exp.c` in this tree,
//! so nothing is missing here.
//!
//! `generic_128.c` is the third experimental piece and is *not* built by
//! default. Upstream builds it as a separate target tagged `nowindows`
//! (`ryu/BUILD:38-49`) and gates its own CMake target on the compiler
//! providing `__uint128_t` (`CMakeLists.txt:31-52`). `-Dgeneric128` turns it
//! on for a caller that wants `float_to_fd128` and friends; the header is
//! installed with it. The default graph, and therefore the six-target `check`,
//! never depends on it. It follows `-Dlinkage`: it is compiled into whichever
//! artifact that option selected, and it is the same sixth translation unit in
//! both variants.
//!
//! ## What this package registers, and what it installs
//!
//! Two modules are registered, and they are not the same kind of route.
//! `b.addModule("ryu", …)` publishes the facade; it is the route a dependent
//! imports, and `module.linkLibrary(c_lib)` attaches the compiled archive to
//! that module, so importing it is the whole of what a dependent has to do.
//! The translated header is registered a second time under the package module
//! name `c`; that is the module the facade imports internally and re-exports
//! as `ryu.c`. `dep.module("c")` resolves for a dependent too, and carries
//! the same declarations with no compiled archive behind them, so `ryu.c` is
//! the raw route to build against. `createModule` is what the cross-target
//! graphs use, precisely because registering `ryu` once per target would
//! leave only the last of them reachable.
//!
//! The install closure is one `zig build install --prefix <dir>` away, and the
//! build graph is the only thing that decides any of it — `package.nix` runs
//! this graph with `--prefix $out` rather than copying files itself, so the Nix
//! output and a plain local install are one layout:
//!
//!   lib/libryu.{a,so,dylib}          the artifact; `ryu.dll` under Windows
//!   include/ryu/ryu.h                upstream's stable header
//!   include/ryu/ryu_parse.h          upstream's experimental parser header
//!   include/translate.h              this fork's aggregate, for one include
//!   include/ryu/ryu_generic_128.h    only under `-Dgeneric128`
//!   lib/pkgconfig/ryu.pc             relocatable, `${pcfiledir}`-derived
//!   share/licenses/ryu/…             both upstream grants and every carried
//!                                    provenance record, listed in
//!                                    `licence_records`
//!
//! There is no native tool and no data file to install, and that is a reading
//! of the tree rather than a gap. Ryu ships no tables to load at run time —
//! its power-of-five tables are compile-time headers under `ryu/` — and its
//! benchmarks are program sources (`ryu/benchmark/`: three C++ and one C)
//! that link gtest from `third_party/gtest/`, not libraries. Its nine upstream
//! tests under `ryu/tests/` are C++ gtest programs built by Bazel
//! (`ryu/tests/BUILD`) or by `ryu/Makefile`; none is a library source this
//! graph could compile without a C++20 toolchain and gtest, and none is a
//! program this graph delivers. The vectors the Zig suite checks against are
//! upstream's, transcribed into `testdata/`, and they are fork test fixtures
//! rather than something a C consumer loads.
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
//!
//! ## The runtime-loading seam
//!
//! `-Druntime=true` replaces the dispatch, not the delivery. The facade's `c`
//! import becomes the module `runtime/graph.zig` generates from *this build's
//! own* translation output, so the sixteen entry points a default build
//! declares — or the twenty-one a `-Dgeneric128` build declares — follow from
//! the header this configuration actually selected and neither list is written
//! by hand. The module then links no archive at all, and that is the point: a
//! provider has to arrive through the platform loader when the caller calls
//! `load`, and linking the archive as well would let the linker resolve the
//! same symbols statically and turn the loaded route into a linked one.
//!
//! `-Dlinkage` is orthogonal and keeps meaning exactly what it meant before
//! this option existed. The artifact is still built and installed in the
//! runtime branch, because delivery and dispatch are separate questions: a
//! caller may equally name the provider this tree built or one it did not.
//!
//! One published route differs by configuration, and it differs for a reason.
//! The linked build registers the translation step's module under the package
//! module name `c`, so `dep.module("c")` resolves with no archive behind it.
//! The runtime build does not. Its dispatch already holds the one translation
//! instance — `runtime/graph.zig` names it `c_native` and re-exports the whole
//! namespace from there — and a second instance would compile the same
//! generated header twice and produce two nominally distinct `enum Status`
//! types, one behind the facade's `ryu.c` and one behind a dependent's
//! `dep.module("c")`, with a cast between them. The complete route in that
//! configuration is `dep.module("ryu").c`, which is the dispatch and therefore
//! the same declarations.
//!
//! The other half is the linked build's `rt` import, which is where
//! `LoadSource` and `LoadError` come from there so they are the same types a
//! caller names in either configuration. Exactly one core-module instance
//! exists per build: `runtime/graph.zig`'s `createModule` creates the one the
//! dispatch uses and re-exports the two types from it, so this branch must not
//! create a second one.

const std = @import("std");

/// `build.zig.zon` itself. `@import` of the manifest is how a build script
/// reads `.version` without a second copy of it; `spglib/build.zig:4` and
/// `blake3/build.zig:254` use the same import.
const manifest = @import("build.zig.zon");

/// The runtime-loading build half, owned by the API role.
///
/// `createModule` builds the generated dispatch that replaces
/// `translate.createModule()` under `-Druntime`; it makes the loader-core
/// module itself and re-exports `LoadSource`/`LoadError` from it.
/// `createCoreModule` builds that same core module for the *linked* branch,
/// where there is no dispatch to carry the types and the facade's `rt` import
/// is where they come from.
///
/// The two branches must not both create a core instance. `LoadSource` and
/// `LoadError` are this SDK's public types, so they have to be the same types
/// in one build: a second core module would be a second, nominally distinct
/// `LoadSource`, and `ryu.load(source)` would hand the facade's type to a
/// function expecting the dispatch's. `addGraph` documents the branch and is
/// the only function that calls either of these.
///
/// `runtime/loader.zig`, `runtime/generate.zig`, `runtime/sync.c` and
/// `runtime/sync.h` are the reusable core the driver owns and copies in; they
/// are reached only through this import, so a build without them stops with a
/// missing-file error rather than something subtler.
const runtime_graph = @import("runtime/graph.zig");

/// `build.zig.zon .version`, parsed. The parse is the loud part: a manifest
/// whose `.version` is not a semantic version fails to configure here rather
/// than being silently copied into `ryu.pc` as something else.
///
/// It is the *fork's* version, not upstream's: `2.0.0-dev.4c0618b` carries the
/// pinned commit prefix because upstream's own `project(ryu VERSION 2.0)`
/// (`CMakeLists.txt:2`) describes a C library version this tree is not
/// released as. `UPSTREAM.md` records that distinction, and this file does not
/// present the `.pc` `Version:` as an upstream release number.
const manifest_version = std.SemanticVersion.parse(manifest.version) catch
    @panic("build.zig.zon: .version is not a semantic version");

/// Package id and the name of the C artifact, which is also the name the
/// installed `.pc` and the installed licence directory are derived from.
const lib_name = "ryu";

/// Flags the canonical C sources need on every target.
///
/// `-std=gnu17` pins the dialect instead of inheriting the compiler's
/// default, which has moved between releases. Upstream's sources are C99-era
/// and compile unchanged under `gnu17`; pinning it means a future default
/// cannot silently change how these bytes are parsed.
///
/// Nothing else is passed, in either delivery variant, and that is a finding
/// rather than an omission. Upstream's core converts a `double` by copying its
/// bits (`ryu/common.h:108-112`, `double_to_bits`) and then works in integer
/// arithmetic on `uint64_t`/`__uint128_t`; no result depends on how the
/// compiler rounds, contracts or reassociates floating-point arithmetic, so
/// `-ffp-contract=off` and friends would guard a risk this code does not have.
///
/// The shared variant adds nothing to this list. Visibility is the only flag a
/// shared build would normally need beyond position-independent relocatability,
/// and this library declares no visibility; `Module.pic` carries the
/// relocatability and the header comment on `-Dlinkage` says why the rest is
/// absent rather than this list silently omitting it.
const c_flags = [_][]const u8{
    "-std=gnu17",
};

/// The stable conversion core plus upstream's experimental parsers.
///
/// Every source in `ryu/` spells its includes as `ryu/<name>.h`, so these
/// names are relative to this repository's root and are listed the way the
/// rest of upstream's build files list them (`ryu/BUILD:7-19` for the core,
/// `ryu/BUILD:24-36` for the parsers). This is the one authoritative list: no
/// other file in this package names a translation unit.
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

/// Every carried licence text and provenance record, installed under
/// `share/licenses/ryu/`.
///
/// A private repository removes no upstream obligation, and ryu grants its own
/// body of work twice over: `README.upstream.md:35-38` offers Apache-2.0 or
/// Boost-1.0 for the files in `ryu/` and Apache-2.0 for everything outside it,
/// so both texts ship and `NOTICE.md` says which grant covers what. Two more
/// are upstream's own records, kept beside them: `README.upstream.md` is
/// upstream's README byte for byte, relocated so `README.md` can be this
/// fork's, and `CONTRIBUTORS` is upstream's authorship file. The last three
/// are this fork's: `NOTICE.md` is the file inventory, `FORK-LICENSE.md` the
/// owner-authorised grant for fork-authored additions, and `UPSTREAM.md` the
/// pin and what changed.
///
/// The six `third_party/` texts are a separate matter. None of them is
/// compiled by this graph — `third_party/` holds the Java implementation,
/// its benchmarks and its test harnesses, and `build.zig.zon .paths` keeps the
/// whole directory so the provenance gate compares the pinned tree unchanged —
/// but they are redistributed in the source package and each one governs bytes
/// that ship beside the library. So they are installed too, with their
/// directory structure preserved so a recipient can tell whose terms are whose.
/// `third_party/mersenne_java/` has no licence file of its own (only a
/// `BUILD` file), so there is nothing from it to carry.
///
/// `package.nix` lists the same thirteen paths in `meta.licenseFiles` and
/// installs nothing by hand, so the Nix output and a plain `zig build install`
/// carry the same bytes by the same route.
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
    /// Resolve the native entry points through the platform loader instead of
    /// linking them. Orthogonal to the delivery `linkage`.
    runtime_loaded: bool,
};

/// Builds the C library and the facade for one target.
///
/// `public` selects between the package module set, which is what a dependent
/// reaches through `dep.module("ryu")`, and a private module. A cross-target
/// check needs the private form: modules are registered by name against the
/// whole build, so registering `ryu` once per cross target would leave only
/// the last of them reachable and silently stop checking the rest.
///
/// `requested_linkage` is what the caller asked for. It selects the artifact
/// and nothing else about the compilation: the same sources, the same flags,
/// the same include root, the same `-Dgeneric128` answer. The shared variant's
/// extra requirements — PIC, the export surface, the soname — are resolved
/// once, below, through `deliveredLinkage`, so the library and the
/// declarations printed beside it cannot describe two different linkages.
fn addGraph(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    requested_linkage: std.builtin.LinkMode,
    public: bool,
    options: Options,
) Graph {
    const linkage = deliveredLinkage(b, target, requested_linkage);

    const c_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        // libc, because `ryu/ryu.h` includes <stdint.h>, the sources
        // include <string.h> and <stdlib.h>, and `d2s`, `f2s`, `d2fixed` and
        // `d2exp` allocate the buffers they hand back (`ryu/d2s.c:505-509`,
        // `ryu/d2fixed.c:557-562`).
        .link_libc = true,
        // A shared object is position-independent whether or not this says
        // so; naming it makes the requirement explicit on the module that
        // carries every one of this library's translation units. It is left
        // unset for the static archive, which needs no relocatability and
        // which every gate in this package's recorded history has delivered
        // as it was. `Module.pic` reaches the command line as `-fPIC`.
        .pic = if (linkage == .dynamic) true else null,
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
        // `-DRYU_*` flag is defined here to paper over it. It joins the same
        // module, so it is position-independent under `-Dlinkage=dynamic`
        // exactly as the core units are.
        c_mod.addCSourceFile(.{
            .file = b.path("ryu/generic_128.c"),
            .flags = &c_flags,
        });
    }

    const c_lib = b.addLibrary(.{
        .name = lib_name,
        .linkage = linkage,
        // Deliberately null in the shared variant too: upstream publishes no
        // ABI number to write down, and inventing one is worse than none.
        // `CMakeLists.txt` declares `project(ryu VERSION 2.0)` — the C
        // library's own version — and attaches no `VERSION` or `SOVERSION`
        // property to the target, so `libryu.so` is installed under its own
        // name and carries no soname. `UPSTREAM.md` records the same reading.
        .version = null,
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
    //
    // Nothing about it is linkage-conditional either. Upstream declares no
    // import/export macro in either header, so there is no declaration half
    // to pair with a definition half: a Windows consumer that wants
    // `__declspec(dllimport)` needs a macro upstream does not define, and this
    // build will not invent one. The translation therefore describes the same
    // sixteen functions in both variants, which is the same ABI either way.
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
    // The one macro this package defines for the translation, and only when
    // `-Dgeneric128` is set. `translate.h` puts `ryu/ryu_generic_128.h` behind
    // it, so the translation carries upstream's default sixteen entry points
    // without it and its twenty-one with it. The condition is the option and
    // not a guess about `__uint128_t`: `c_mod` above compiled
    // `ryu/generic_128.c` under exactly the same option, so the declarations
    // and the object behind them cannot disagree.
    if (options.generic_128) {
        translate_c.defineCMacro("RYU_TRANSLATE_GENERIC_128", "1");
    }
    // The package module name `c` is registered for a dependent only in the
    // linked branch. Under `-Druntime` the dispatch already owns the single
    // translation instance, and registering a second one would compile the
    // same generated header twice into two nominally distinct `enum Status`
    // types; `dep.module("ryu").c` is the complete route in that
    // configuration. The header comment above says the same thing.
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
        // A loaded provider has to arrive through the platform loader, so the
        // link line names nothing. Linking the archive as well would let the
        // linker resolve the same symbols statically and the runtime route
        // would quietly be a linked one. The artifact itself is still built and
        // installed above, because delivery and dispatch are separate
        // questions: the whole point of the mode is that a caller may name a
        // provider this tree did not build.
        module.addImport("c", runtime_graph.createModule(b, translate_c, target, optimize));
    } else {
        // The translated header is imported, never registered, in the
        // cross-target case; in the published case `linked_c_module` above is
        // the registration and this is the same module. Transitive linking:
        // `dep.module("ryu")` has to carry the compiled archive, or a dependent
        // would compile the facade against declarations with nothing behind
        // them and fail only at link time.
        module.addImport("c", linked_c_module orelse translate_c.createModule());
        module.addImport("rt", runtime_graph.createCoreModule(b, target, optimize));
        module.linkLibrary(c_lib);
    }

    return .{ .c_lib = c_lib, .module = module };
}

/// Writes `lib/pkgconfig/ryu.pc` and installs it.
///
/// Upstream ships no `.pc` file at all — there is no `ryu.pc.in` anywhere in
/// the pinned tree and no `configure_file` in `CMakeLists.txt` — so unlike
/// BLAKE3, whose `libblake3.pc` is upstream's template field for field, this
/// one is fork-authored and says so in its own first line. What it can still
/// take from upstream is the shape: a consumer asks for `-lryu`, and the
/// linker resolves that name to `libryu.a` or to `libryu.so` by itself, which
/// is why one file is correct for both delivery variants and why it takes no
/// linkage argument. `predicates/build.zig:312-344` is the same reasoning for
/// a library with no upstream template.
///
/// `prefix` is `${pcfiledir}/../..` rather than a substituted path, because
/// this graph does not know where `--prefix` will point when it writes the
/// file. pkg-config resolves `${pcfiledir}` against the `.pc` file it found, so
/// the installed metadata is correct wherever the prefix landed, including a
/// Nix store path that is only known at build time. That spelling needs
/// pkg-config 0.29 or newer, or pkgconf, and the file says so rather than
/// hardcoding `/usr/local`.
///
/// `Cflags:` carries the include path and nothing else. `-std=gnu17` is a
/// requirement of the translation unit that *implements* the conversion, and
/// that unit is compiled here with exactly that flag; a caller's own object
/// file computes no digit.
///
/// `Libs.private:` is `-lc` and states the dependency closure rather than
/// omitting one. The compiled core calls `malloc` (`ryu/d2s.c:505-509`,
/// `ryu/f2s.c:341-346`, `ryu/d2fixed.c:557-562`), `memcpy`, `memset` and
/// `strlen` from `<string.h>`/`<stdlib.h>`; the two parsers use no external
/// function at all. It calls nothing from libm — the `floor_log2` helpers at
/// `ryu/s2d.c:47,54` and `ryu/s2f.c:41,48` are `static inline` and every
/// other `floor` in the tree is a comment or a function name — and no libdl,
/// pthread or other optional dependency. So `-lm` would name a dependency this
/// library does not have, and the shared variant needs nothing beyond `-lc`.
///
/// `Version:` is formatted from `manifest_version`, so the metadata, the
/// manifest and any future record cannot name three different things. It is
/// this fork's `2.0.0-dev.4c0618b` rather than an upstream release: upstream's
/// `project(ryu VERSION 2.0)` describes the C library's own version line, and
/// this tree is a pinned commit of it rather than that release.
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

/// Installs every carried licence text and provenance record under
/// `share/licenses/ryu/`, preserving the `third_party/` directory structure
/// so a recipient can tell whose terms are whose.
///
/// These are copies of files already in this repository, byte for byte;
/// nothing is rewritten, merged or truncated on the way out. `b.installFile`
/// takes a repository path and attaches its step to the install step itself
/// (`lib/std/Build.zig:1675-1677`), so this needs no separate
/// `dependOn`.
fn installLicenceRecords(b: *std.Build) void {
    for (licence_records) |record| {
        b.installFile(record, b.fmt("share/licenses/{s}/{s}", .{ lib_name, record }));
    }
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

/// Compiles the C library, the tests and the smoke example for one target and
/// attaches every one of them to `step`.
///
/// Compiling the tests and the example is what makes this a check of the
/// facade rather than of an unreferenced archive: Zig analyses a function body
/// only when something calls it, and those two files are the package's only
/// callers of the public surface. Nothing is run here, so every result is
/// compile evidence, never a claim that a foreign binary executed.
///
/// `linkage` is the caller's requested delivery, resolved again for this
/// target: the same refusal `addGraph` applies has to hold here too, or a
/// `check -Dtarget=wasm32-wasi -Dlinkage=dynamic` would build an artifact the
/// package module cannot carry.
///
/// A row that cannot carry the requested linkage becomes an explicit failing
/// step carrying the reason, and nothing is compiled for it. That is the honest
/// result of `zig build check -Dlinkage=dynamic`: one refused row, the other
/// five still compiled, and no archive handed back under the flag that asked
/// for a shared object. The row is not dropped, not relabelled and not answered
/// with something else.
///
/// A step rather than a `@panic` here, and the difference is what the two are
/// for. The selected target's own graph has already been refused in
/// `deliveredLinkage` before this runs — `zig build -Dtarget=wasm32-wasi
/// -Dlinkage=dynamic` stops at configure — so this branch is only ever reached
/// for a row nobody named with `-Dtarget=`. Aborting there would take down a
/// native `zig build install`, which is entirely valid, over a target that
/// step never compiles.
fn addTargetCheck(
    b: *std.Build,
    step: *std.Build.Step,
    query: std.Target.Query,
    optimize: std.builtin.OptimizeMode,
    linkage: std.builtin.LinkMode,
    options: Options,
) void {
    const cross_target = b.resolveTargetQuery(query);

    if (linkage == .dynamic) {
        if (sharedObjectRefusal(b, cross_target)) |reason| {
            const label = b.fmt("{s}-{s}", .{
                @tagName(cross_target.result.cpu.arch),
                @tagName(cross_target.result.os.tag),
            });
            step.dependOn(&b.addFail(b.fmt(
                "ryu: check row {s}: {s} No artifact was built for this row, and nothing was substituted for it.",
                .{ label, reason },
            )).step);
            return;
        }
    }

    const cross = addGraph(b, cross_target, optimize, linkage, false, options);
    const programs = addZigPrograms(b, cross_target, optimize, cross);
    step.dependOn(&cross.c_lib.step);
    step.dependOn(&programs.tests.step);
    step.dependOn(&programs.smoke.step);
}

/// Whether this target can carry a shared object at all.
///
/// For most OSes that is exactly what `std.Target.DynamicLinker.kind` answers
/// from the OS tag alone (`lib/std/Target.zig:2345-2402`): the `.arch_os` and
/// `.arch_os_abi` families have a dynamic linker and `.none` does not. WASI is
/// `.none` (`:2385`) and `zig build check` walks a WASI target, so
/// `-Dlinkage=dynamic` has to know what to say there rather than emit a file
/// with a `.so` name that nothing can load.
///
/// Windows is the one `.none` that does carry a shared object, and reading it
/// as "no shared object" is not a conservatism — it refuses this package's own
/// `x86_64-windows-gnu` matrix cell, a target that delivers `ryu.dll` as a
/// matter of course and the only cell here whose image is not ELF. `.windows`
/// is `.none` (`:2380`) because a PE/COFF image has no interpreter path and no
/// PT_INTERP segment at all: its imports are resolved by the loader inside the
/// OS, and the shared object is an input to that loader rather than something
/// an interpreter names. The absence of an ELF interpreter is therefore not the
/// same fact as the absence of a shared object, and the two are read separately
/// here instead of being collapsed into one predicate.
///
/// WASI is deliberately not given that pass. A `.wasm` module has no dynamic
/// linker, no OS loader that resolves its imports at load time, and nothing that
/// would open a second copy of one, so a shared object there is still a file
/// nothing can load.
fn targetCarriesSharedObject(target: std.Build.ResolvedTarget) bool {
    if (target.result.os.tag == .windows) return true;
    return std.Target.DynamicLinker.kind(target.result.os.tag) != .none;
}

/// Why `-Dlinkage=dynamic` cannot be delivered for this target, or `null` when
/// it can.
///
/// A refusal and not a substitution, and there is no third answer. A caller who
/// asked for a shared object either gets one or gets this sentence naming the
/// target that cannot carry it. Handing back `libryu.a` in answer to a request
/// for `libryu.so` — announced by a printed line or not — would be a build
/// reporting something it did not do, and every gate run afterwards would
/// measure that archive rather than the artifact that was asked for.
///
/// The text is deliberately unprefixed and composable, so the configure-time
/// `@panic` in `deliveredLinkage` and the failing check step in
/// `addTargetCheck` cannot describe the same boundary two different ways.
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

/// The linkage this target can carry for a requested one, or a refusal.
///
/// `requested` is `.static` or `.dynamic`; this file never passes anything
/// else. `.dynamic` on a target `sharedObjectRefusal` names — WASI is the one
/// this package's own six-target `check` walks — is refused rather than
/// answered with an archive, and the refusal is a configure-time `@panic` at
/// whatever entry point asked for it, so what a caller gets is a message
/// rather than a wrong artifact.
///
/// Every configuration resolves through this one function, so the artifact,
/// the line printed beside it and the tests compiled against it cannot describe
/// two different linkages.
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

    // Which artifact this build delivers and links. Static is the default and
    // is what this package has always delivered, so every command that exists
    // today still produces the artifact it produced before this option did;
    // adding it changes nothing for a caller who does not pass it.
    //
    // The spelling is the enum's own, so the CLI values are `static` and
    // `dynamic` (`std.builtin.LinkMode`), the same option name spglib, pcre2,
    // lmdb, blake3 and predicates use for their own libraries, deliberately:
    // one option with one set of values across the whole workspace is worth
    // more than a locally invented synonym.
    //
    // `static` names the library artifact. It is not a claim that a program
    // linking it is wholly static: the compiled core calls `malloc`, `free`,
    // `memcpy`, `memset` and `strlen`, so it needs a libc at run time either
    // way, and `ryu.pc`'s `Libs.private: -lc` says so.
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
            "stops at configure time naming it, and inside `check` that one row " ++
            "becomes an explicit failing step. Nothing is ever substituted.",
    ) orelse .static;

    // Which route the facade takes, not which artifact this build delivers.
    // `-Druntime=true` turns every declared entry point into a call through one
    // process-lifetime table an explicit `load(source)` fills, and the module
    // links no archive. It is independent of `-Dlinkage`, which still decides
    // which artifact is built and installed. Default off, and a linked build
    // is unchanged in every respect.
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
            "Also build upstream's experimental generic 128-bit shortest converter (ryu/generic_128.c), install ryu/ryu_generic_128.h and translate it, so the facade's `generic128` namespace and the runtime dispatch carry its five converters and FD128_EXCEPTIONAL_EXPONENT as well as the default sixteen. Upstream tags it 'nowindows'; it is off by default and the cross-target check never builds it. Independent of -Dlinkage: it joins whichever artifact that option selected.",
        ) orelse false,
        .runtime_loaded = runtime_loaded,
    };

    const published = addGraph(b, target, optimize, linkage, true, options);
    b.installArtifact(published.c_lib);

    // The rest of the delivery, not just the artifact. A shared object with no
    // pkg-config metadata, and a package with no licence material beside the
    // binary, are both source drops rather than packages: one leaves a C
    // consumer no `-lryu` to resolve, and the other removes an obligation a
    // private repository does not remove. The build graph owns these paths,
    // and `package.nix` installs nothing by hand — it runs this graph with
    // `--prefix $out` — so the Nix output and a plain local install are one
    // layout rather than two.
    //
    // `addInstallFile` creates the step without attaching it
    // (`lib/std/Build.zig:1698-1700`), which is why the dependency on the
    // install step is written out; `installLicenceRecords` uses
    // `installFile`, which attaches its own.
    b.getInstallStep().dependOn(
        &b.addInstallFile(addPkgConfig(b), "lib/pkgconfig/ryu.pc").step,
    );
    installLicenceRecords(b);

    const programs = addZigPrograms(b, target, optimize, published);
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
        check_step.dependOn(&published.c_lib.step);
        check_step.dependOn(&programs.tests.step);
        check_step.dependOn(&programs.smoke.step);
        for (check_targets) |query| {
            addTargetCheck(b, check_step, query, optimize, linkage, options);
        }
    } else {
        addTargetCheck(b, check_step, target.query, optimize, linkage, options);
    }

    // Which artifact this configuration hands back, and how its symbols are
    // reached, are facts worth reading out of the build rather than inferring
    // from a cache directory. These are configure-time lines, not gate results:
    // nothing has been compiled when they print. `deliveredLinkage` has already
    // refused any combination it cannot carry, so what is printed here is
    // exactly what the build will do.
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