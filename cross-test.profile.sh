# cross-test profile for the ryu package.
#
# `cross-test` finds this file by itself when it is run from the package root,
# and sources it as trusted Bash. It is configuration, not a test: everything
# below is a setting the harness already has a default for, written out so the
# gate this package is verified by can be read without reading the harness.
#
# The harness keeps everything that decides what actually runs. The command is
# `zig build test -Dtarget=TARGET` over this package's real build graph, the
# matrix is the published Zig 0.16.0 Tier 1/2 platform table, and QEMU-user,
# Wasmtime, Wine and native execution are chosen by the harness. Nothing here
# replaces a build step, names an artifact, or adds a `zig build` option.
#
# Deliberately absent, and why:
#
#   * CROSS_MATRIX and TARGETS. The matrix is the whole published table. A
#     profile that names a subset still exits zero when the subset is green,
#     which is a narrower gate wearing the same exit code.
#   * cross_build_command / cross_artifact. Those switch the harness out of
#     the standard build into an artifact profile with a hand-written command.
#     The point of this gate is that `zig build test` runs the package's own
#     Zig test binary, over upstream's own C, for the selected target.
#   * Any -D option. In particular `-Dgeneric128` is not passed: the matrix
#     then builds the default source closure, upstream's five stable and
#     experimental core translation units, which is the closure every platform
#     in the table has to compile. `-Dgeneric128` needs `__uint128_t` and a
#     working `long double` (ryu/generic_128.h:42, ryu/generic_128.c:70-73)
#     and upstream itself builds it as a separate target tagged `nowindows`
#     (ryu/BUILD:38-49), so it is a separate gate on its own terms rather
#     than something this one quietly narrows. `-Dlinkage` is not passed for
#     the same reason and not the same shape: the matrix then builds the
#     delivery this package has always shipped, the static archive, the one
#     that has to compile on all 53 platforms. The shared variant is a gate of
#     its own and a narrower one: carrying it at all needs a dynamic linker,
#     and a target without one refuses the option outright rather than
#     substituting an archive, so a matrix carrying both variants would fail
#     its configure step on every platform whose OS has none. The harness also
#     manages -Dtarget, --prefix, --cache-dir, -j, --summary, --color and
#     --test-timeout itself and rejects them in CROSS_BUILD_ARGS, so the
#     optimize mode is the build runner's default. `-Druntime` is not passed for
#     the same reason and one more: a runtime-loaded build resolves its symbols
#     through the platform loader at run time, and which platforms of this table
#     have a loader a test binary can use is this profile's business, not the
#     harness's.
#   * ZIG, CROSS_PREFIX, CROSS_CACHE_DIR or any other path. A profile that
#     names one host's compiler cache or output directory is not a package
#     file; it silently stops working on every other machine.
#   * CROSS_REQUIRE_RUNNERS=1. That flag fails a platform for having no runner
#     on this host. A platform whose runner is absent is already reported as
#     explicit `build_only` coverage, which is a fact and not a pass; demanding
#     a runner would report missing runtimes as broken targets.
#
# Top-level code is limited to variable definitions because the harness sources
# this file more than once per run and expects it to be idempotent.

# The build step `cross-test` runs: the package's own Zig test binary, for the
# target the harness selected. Not `check`, which runs nothing.
CROSS_BUILD_STEP=test

# Seconds allowed for one target's build-and-test. The harness's own default,
# written here because this is the one number a reader of this file needs in
# order to know what a timeout in the log means. It covers compiling the C
# core, the translated aggregate header and the test binary, plus the test run
# itself.
CROSS_BUILD_TIMEOUT=900