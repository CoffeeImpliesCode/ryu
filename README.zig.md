# ryu — IEEE-754 to decimal in Zig, over upstream's C

This package compiles **ulfjack/ryu at commit
`4c0618b0e44f7ef027ebae05d2cc7812048f7c8f`** — upstream's own C sources, from
the `ryu/` directory in this repository — into a native library, a static
archive or a real shared object, translates upstream's two public headers (a
third one under `-Dgeneric128`), and publishes a Zig facade over that
translation.

Upstream's bytes are carried as upstream wrote them with exactly one disclosed
exception, a single `#include` line in `ryu/ryu.h`. The section below is that
exception in full; `NOTICE.md` records it as this fork's Apache-2.0 §4(b)
statement of changes.

Nothing here reimplements the algorithm. Every digit this package prints is
produced by a call into a compiled upstream translation unit, and the raw C
surface is reachable directly through `pub const c`.

## Requirements

Zig **0.16.0**, the real compiler. In this workspace the bare `zig` on `PATH` is
a version dispatcher that needs a version-bearing `build.zig`; the compiler the
2026-10-04 native and loaded rows below were run with is at

```
/home/tmp2/gertullj/cache/zig/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/zig
```

Earlier rows in this file were run with an earlier on-disk copy of the same
pinned version, under a different cache path. Which copy ran which gate is a
fact about the receipt, so every row below names the run it came from rather
than one compiler path for all of them.

Nothing is downloaded, no host `configure` value is read, and no installed
library is used: the only compiled C is the units named in `build.zig`'s
`core_sources`.

## Deviations from upstream

There is exactly one, and it is one line of one upstream header.

**What changed.** `ryu/ryu.h:24` reads `#include <stdint.h>` in this tree and
`#include <inttypes.h>` at commit `4c0618b0e44f7ef027ebae05d2cc7812048f7c8f`.

**Why.** That include exists for exactly one name, `uint32_t`, used in the six
`precision` parameters at `ryu/ryu.h:34-40`. No `PRI*` or `SCN*` macro appears
anywhere in the header, and `uint32_t` is declared by `<stdint.h>` (C99 7.18.1)
— the header `<inttypes.h>` includes in order to reach that same type. The
replacement is therefore type-preserving, and it is load-bearing rather than
cosmetic: NetBSD's `<inttypes.h>` closes its declarations with `__END_DECLS`,
whose replacement list begins with a `_Pragma`, and the pinned translator reads
that `_Pragma` as ordinary tokens.

```
…/lib/libc/include/generic-netbsd/inttypes.h:93:1: error: unknown type name 'pragma'
```

That is one observed failure on each of the nine NetBSD cells in the platform
matrix, recorded in `FORK-NOTES.md` note 15 with the receipts.

**What did not change.** No declaration, type, signature, constant, prototype or
algorithm, and no duplicate of any of them. The header keeps upstream's
copyright block and its per-file Apache-2.0 / Boost dual grant verbatim
(`ryu/ryu.h:1-16`), and neither `LICENSE-Apache2` nor `LICENSE-Boost` is
edited. Upstream's bytes for this path are 1360 bytes hashing to
`b7feab0ba1df5e9ef3d602f386592ad152491405e49b408fb21c0e0e9e6bfb16`; this
tree's are 1417 bytes hashing to
`83ed2a4cd2e42cdd351383b5c937e320e47d8e0ea214964a7b8568f974754dae`, and the
two differ by that one include and its inline change notice, nothing else.

**Which translation units see it.** Three of the five compiled units include
this header — `ryu/d2s.c:30`, `ryu/f2s.c:21`, `ryu/d2fixed.c:26`. The two
parsers include `ryu/ryu_parse.h` instead (`ryu/s2d.c:18`, `ryu/s2f.c:18`),
which declares no integer type at all, and each already includes `<stdint.h>`
itself (`ryu/s2d.c:22`, `ryu/s2f.c:22`); their own `<inttypes.h>` blocks sit
inside `#ifdef RYU_DEBUG`, and this build defines no `RYU_DEBUG`. So the
compiled ABI is upstream's own on every target, and the edit takes a header the
compiled units never needed out of the translation closure instead of putting
anything in its place.

**No workaround ships with it.** `build.zig` compiles one graph from one root
header for every target and defines no `RYU_*` macro and no per-target
conditional (`build.zig:295-297`), and the tree contains no fork-authored
stand-in for `<inttypes.h>` or for any other libc header.

**Status.** `observed` on the patched header, on every gate this package has
run since: the native rows below (28/28 in Debug and in ReleaseSafe, smoke,
install, consumer) and the corrected full-matrix run, which exits 0 with **20
cells passing at 28 tests each, 33 cells compiled and recorded `build_only`, 0
failing** — including all nine NetBSD cells, which now compile and are recorded
as `build_only` because this host has no NetBSD runtime, not because they
passed a test. Receipts are named in "Verification status".

## Commands

| Command | What it does |
|---|---|
| `zig build` | compiles upstream's five primary C units — six with `-Dgeneric128` — installs `libryu.a` plus `ryu/ryu.h`, `ryu/ryu_parse.h` and `translate.h` into `zig-out/`, and compiles the example |
| `zig build test` | runs `tests.zig`: the six fixtures, the cross-checks against Zig's own float code, and the buffer and rounding boundaries |
| `zig build test -Doptimize=ReleaseSafe` | the same suite with the optimizer on |
| `zig build smoke` | runs `smoke.zig`, which prints each answer, checks it against a published expectation and exits non-zero on any mismatch |
| `zig build check` | compiles the C core, the translated interface, `tests.zig` and `smoke.zig` for all six required targets, running nothing |
| `zig build check -Dtarget=<triple>` | the same for one target |
| `zig build -Dgeneric128=true` | additionally compiles `ryu/generic_128.c` as a sixth unit, installs `ryu/ryu_generic_128.h`, and translates that header as well — so the option is not a C-surface one: the five converters reach a Zig consumer through `ryu.c`, through the facade's `generic128` namespace, and as five more entry points a runtime-loaded build requires from its provider. Off by default, and compiled for the native target only so far |
| `cd consumer && zig build run` | the same library, consumed by a package that did not write it. `consumer/build.zig` forwards the library's `-Dlinkage`, `-Dgeneric128` and `-Druntime` options, and it passes the caller's own program arguments to its `run` step, so `zig build run -- --provider <file>` reaches `consumer/src/main.zig`. It adds no `--cache-dir`, `--global-cache-dir`, `--prefix`, job count or summary flag of its own |
| `zig build -Dlinkage=dynamic` | builds the shared variant instead of the static one. `static` is the default and is this package's pre-existing policy, and it is also what upstream's own CMake produces, since `CMakeLists.txt:6` uses `add_library` without a `SHARED` keyword and follows `BUILD_SHARED_LIBS`, which CMake defaults to OFF |
| `zig build -Druntime=true` | resolves the same entry points through the platform loader instead of linking them: the module carries no archive, and one explicit `ryu.load(.{ .path = … })` or `ryu.load(.{ .system = … })` is what makes the library usable. Independent of `-Dlinkage`, which still decides which artifact is built and installed. Off by default, and a linked build is unchanged in every respect |
| `devenv shell` (or `direnv allow`, with the `.envrc` here) | enters the canonical development environment. Tools only — the Zig compiler, `pkg-config`, `make`, `git` — and deliberately **not** this SDK, because entering a shell must not require building the library you came to work on. `devenv tasks` lists `sdk:build`, `sdk:test`, `sdk:smoke`, `sdk:check`, `sdk:install`, `sdk:matrix` |
| `devenv build outputs.static` / `outputs.shared` | the packaged SDK, built lazily from the same `package.nix` the flake uses. Nothing is realised until one of them is asked for |
| `nix build path:.#static` / `path:.#shared` | the same derivation through the flake. `flake.lock` sits beside `flake.nix` and pins the nixpkgs rev it names, so a flake build in this directory has a locked input and writes none; `path:.` is only needed to read the flake from somewhere that is not a checkout. `-Dgeneric128` is a build-graph option, not a packaging variant, so it has no flake attribute |

Add `-j8 --summary all` and `--cache-dir <dir>` as your workspace does. The six
targets `check` covers are `x86_64-linux-gnu`, `aarch64-linux-gnu`,
`aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu` and
`wasm32-wasi`.

**Why `check` compiles the test and example roots.** Zig analyses a function body
only when something calls it, so compiling the C archive proves nothing about
the facade and reflecting over the module proves nothing either.
`tests.zig` and `smoke.zig` are this package's only callers of the public
surface, which makes them what `check` compiles. Every public declaration in
`zig/root.zig` must be called from one of those two files or `check` stops
covering it. A passing `check` is compile evidence; nothing runs for a foreign
target.

### The full platform matrix

The six targets `check` covers are a compile-only gate that runs nothing. The
gate that runs this package's own Zig tests on every platform in Zig 0.16.0's
published Tier 1/2 table — 53 of them, including the 32-bit and big-endian
ones that list does not reach — is `cross-test`, run from the package root:

```
cross-test
```

`cross-test` discovers `cross-test.profile.sh` in this directory on its own.
That profile is settings only: it names the standard `test` step and nothing
else. No target list, no `-Dtarget`, no `-Doptimize`, no `-Dgeneric128`, no
artifact hooks, no host path. For each platform the harness runs
`zig build test -Dtarget=TARGET` over the default source closure — upstream's
five primary C units, the same graph any other `-Dtarget` produces — executes
the resulting binary where a native or emulator runner exists, and records
explicit `build_only` coverage — compiled, not executed — where none does.
`build_only` is never counted as a pass, and `check` is not a substitute for
this: it produces no test result at all.

Two things this gate deliberately does not decide. `-Dgeneric128` stays off, so
the matrix builds the same closure on every platform; that option is a separate
gate on its own terms, because upstream builds it as a separate target tagged
`nowindows` (`ryu/BUILD:38-49`) and its header asks for `__uint128_t`
(`ryu/ryu_generic_128.h:42`) and a working `long double`
(`ryu/generic_128.c:70-73`). And a platform with no runner on the host is
reported as `build_only`, which is a fact about the host and not a pass.

That command has been run twice and both runs are recorded. The pre-deviation
tree exited 1 with 20 cells passing, 24 recorded as `build_only` and 9 failing,
all nine on the same NetBSD translation failure named in § "Deviations from
upstream". The corrected run over the patched header exits 0 with **20 pass, 0
fail, 33 `build_only`, 0 partial** over all 53 cells: every cell compiles, the
20 that have a runner on this host each ran the full 28-test suite — 560
executed tests — and the nine NetBSD cells moved from `fail` to `build_only`,
which is compile coverage and not a pass.

## Importing it

In your `build.zig.zon`:

```zig
.dependencies = .{
    .ryu = .{ .path = "../ryu" },
},
```

In your `build.zig`:

```zig
const dep = b.dependency("ryu", .{
    .target = target,
    .optimize = optimize,
});

const exe_mod = b.createModule(.{
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});
exe_mod.addImport("ryu", dep.module("ryu"));
```

`dep.module("ryu")` carries the compiled archive with it, so the module alone is
enough; nothing else has to be linked. The library's own C requirement comes
with it, and a dependent does not repeat `link_libc`.

### The supported routes, and the ones that merely resolve

Four routes reach this package's bytes, and they are not equally supported:

| Route | What it is | Supported |
|---|---|---|
| `dep.module("ryu")`, then `@import("ryu")` | the facade, with the compiled archive linked into whatever imports it | yes — this is the route to build against |
| `ryu.c` inside that module | the translated `ryu/ryu.h` and `ryu/ryu_parse.h`, reached through the facade | yes — this is the documented escape hatch to upstream's own declarations |
| `dep.module("c")` | the same translated module, registered a second time under the package module name `c` by `build.zig`'s `addModule` rather than its private `createModule`, so it resolves for a dependent | it resolves and carries the same declarations, but no compiled archive, so it links nothing on its own. Build against `ryu` or `ryu.c`, not this. **In a `-Druntime=true` build it does not resolve at all** (`build.zig:579-587`): the dispatch already holds the one translation instance, and a second instance would compile the same generated header twice into two nominally distinct `enum Status` types |
| the installed `libryu.a` plus `include/ryu/ryu.h`, `include/ryu/ryu_parse.h` and `include/translate.h` | what `zig build` installs, for a C consumer | yes, for C. There is no system-library mode, so no installed ryu is ever linked in its place |
| a runtime-loaded provider — this SDK's own shared library, or a compatible external one — named explicitly by absolute path or by basename | one dispatch table per configured module instance, resolved once, then ordinary module calls | yes, under `-Druntime=true`. This is the route `build.zig` declares (`build.zig:914-930`), wires through `runtime/graph.zig` (`build.zig:604-623`) and fills from this build's own translation output with `runtime/generate.zig`; `ryu.load` is the call, and each of the sixteen entry points — twenty-one with `-Dgeneric128` — is a call through that table afterwards. `zig/root.zig` publishes `runtime_loaded`, `load`, `loadedSource`, `LoadSource` and `LoadError` in both configurations, and this package's own `smoke.zig`, `tests.zig` and `consumer/src/main.zig` all drive it. Its evidence and its gaps are in "Verification status" and in `README.md` § 3b |

`ryu` and `c` are both registered against the whole build, which is why
`build.zig` gives the six-target `check` a private module instead: registering
`ryu` once per cross target would leave only the last of them reachable.
Registration is reachability, not intent, and it carries no linkage of its own —
only `addModule("ryu", …)` is followed by `linkLibrary`, which is why the module
that links the archive is the one a dependent should import.

Both of those are linked-configuration facts. Under `-Druntime=true` only `ryu`
is registered, for the reason the row above gives.

### The raw route in full, and what the delivered dispatch covers

`translate.h` is the aggregate this package translates, and it includes two
upstream headers unconditionally — `ryu/ryu.h` and `ryu/ryu_parse.h` — plus a
third when the build configured `-Dgeneric128`. The first two declare **sixteen
functions**. That is the header-declared route of a default build, and it is
worth writing out because the facade reaches only six of them and a reader
should not have to infer the rest from the headers:

| Header | Functions | Ownership and termination |
|---|---|---|
| `ryu/ryu.h` | `d2s_buffered_n`, `d2s_buffered`, `d2s`, `f2s_buffered_n`, `f2s_buffered`, `f2s`, `d2fixed_buffered_n`, `d2fixed_buffered`, `d2fixed`, `d2exp_buffered_n`, `d2exp_buffered`, `d2exp` | `*_buffered_n` returns the byte count and writes exactly that many bytes, **without** a terminator. `*_buffered` writes the same bytes plus `'\0'` at `[N]`. The four `char*`-returning forms allocate through libc `malloc` — `ryu/d2s.c:506` (25 bytes), `ryu/f2s.c:342` (16), `ryu/d2fixed.c:558` and `:815` (2000 each) — terminate, and return the allocated pointer itself, so the caller releases it with libc `free`, not with a Zig allocator |
| `ryu/ryu_parse.h` | `s2d_n`, `s2d`, `s2f_n`, `s2f` | each returns `enum Status`, whose enumerators are `SUCCESS`, `INPUT_TOO_SHORT`, `INPUT_TOO_LONG`, `MALFORMED_INPUT`. `_n` takes an explicit length; the others take `strlen`-style input. On a refusal the output parameter is left untouched |

`ryu/ryu_generic_128.h` is in that set **only under `-Dgeneric128`**.
`translate.h` puts it behind `RYU_TRANSLATE_GENERIC_128` (`translate.h:96-98`),
a fork-owned macro — upstream defines no such macro, so a name that looked like
upstream's would be an ABI knob a later release could collide with — and
`build.zig` defines it on the translation line exactly when the option is set
(`build.zig:569-578`). That is the same option that compiles
`ryu/generic_128.c` into the library (`build.zig:508-520`) and installs its
header (`build.zig:538-540`), so the declarations and the object behind them
cannot disagree, and the condition is the option itself rather than a guess
about `__uint128_t`. The route is therefore **sixteen** functions by default and
**twenty-one** with `-Dgeneric128`, and the five extra ones —
`float_to_fd128`, `double_to_fd128`, `long_double_to_fd128`,
`generic_binary_to_decimal`, `generic_to_chars` — arrive with
`struct floating_decimal_128` and `FD128_EXCEPTIONAL_EXPONENT`. They reach a
consumer three ways in that configuration: from C through the installed header,
through `ryu.c` in Zig, and through the facade's `generic128` namespace, which
is `void` — not a struct of stubs — in a build that did not configure the
option, because there nothing was compiled and nothing was translated
(`zig/root.zig:840-863`).

**What the delivered dispatch carries.** The facade calls the allocation-free
subset — `d2s_buffered_n`, `f2s_buffered_n`, `d2fixed_buffered_n`,
`d2exp_buffered_n`, `s2d_n`, `s2f_n` — because it hands back a subslice of a
buffer the caller already owns. The other **ten** are in the table all the
same, and they are there because the table is generated from this build's own
translation output rather than from a list written by hand: `d2s`, `f2s`,
`d2fixed`, `d2exp`, `d2s_buffered`, `f2s_buffered`, `d2fixed_buffered` and
`d2exp_buffered` write into or return memory they manage themselves, and
`s2d`, `s2f` differ from their `_n` siblings only in taking a
`strlen`-computed length. All sixteen are **required** from a provider and none
is optional (`runtime/library.zig:14-25`): a candidate exporting fifteen is
refused rather than used, because each is a published entry point a caller can
name through `ryu.c`. The same inventory gains the five generic-128 converters
in a `-Dgeneric128` build (`runtime/library.zig:27-34`), routed like the rest
rather than kept as an optional native escape. Crossing into libc
`malloc`/`free` is a property four of them carry rather than something a route
may quietly drop.

The four allocating functions also fix what the dispatch must assume about its
provider: the allocation happens in the **C runtime the provider was linked
against**, not in whatever allocator the calling Zig program happens to use. A
caller that releases one of those pointers with anything other than that same
runtime's `free` is corrupting a heap it does not own. On this route the
release is exercised rather than merely documented: `runtime/library.zig`'s
load-time `validate` takes what `d2s` returns from a candidate and releases it
with this process's `free`, and it runs after every symbol has resolved and
before any table is published. That is a behavioural probe and not an allocator
identity check: it refuses a candidate whose allocating answer cannot be
released that way or disagrees with its buffered one. On the Zig side
the four `format*Owned` functions cross the same boundary deliberately, and
`OwnedString.deinit` is the only thing allowed to release what they return.
What is still unexercised is recorded as such in "Verification status": the
loaded route's `test` step has not yet run with a provider named, so no loaded
gate has yet crossed that boundary with a real answer to check.

## Using it

```zig
const ryu = @import("ryu");

pub fn main() !void {
    // Shortest round-trip form. `double_shortest_capacity` is a compile-time
    // constant, so a buffer that size cannot fail on length.
    var shortest: [ryu.double_shortest_capacity]u8 = undefined;
    std.debug.print("{s}\n", .{try ryu.format64Shortest(1.25, &shortest)}); // 1.25E0

    // The precision writers take a precision, so their bound depends on it.
    var precision_buffer: [1024]u8 = undefined;
    std.debug.print("{s}\n", .{try ryu.format64Fixed(1.25, 3, &precision_buffer)}); // 1.250
    std.debug.print("{s}\n", .{try ryu.format64Scientific(1.25, 2, &precision_buffer)}); // 1.25e+00

    // A caller that wants the fewest bytes asks for the bound first. The buffer
    // handed over is exactly that bound, which the library promises is enough.
    const exact = try std.heap.page_allocator.alloc(u8, try ryu.fixedCapacity(3));
    defer std.heap.page_allocator.free(exact);
    std.debug.print("{s}\n", .{try ryu.format64Fixed(1.25, 3, exact)}); // 1.250

    // binary32 has its own writer. Do not widen a float and use the binary64
    // one: shortest depends on the precision of the source type.
    var shortest32: [ryu.float_shortest_capacity]u8 = undefined;
    std.debug.print("{s}\n", .{try ryu.format32Shortest(0.1, &shortest32)}); // 1E-1

    // Upstream's experimental parser.
    std.debug.print("{d}\n", .{try ryu.experimental.parse64("1.25E0")}); // 1.25

    // The raw C surface, for anything the facade does not name. This is
    // upstream's own declaration, reached through the translated header.
    var raw: [ryu.double_shortest_capacity]u8 = undefined;
    const written = ryu.c.d2s_buffered_n(1.25, &raw);
    if (written < 0) return error.NegativeLength;
    std.debug.print("{s}\n", .{raw[0..@intCast(written)]}); // 1.25E0
}
```

`smoke.zig` is the runnable version of this, with every expected string checked
rather than merely printed, and `consumer/src/main.zig` is the same thing across
a package boundary.

In a `-Druntime=true` build the same code needs one call before anything else
reaches upstream, and that is the whole of the difference a consumer sees:

```zig
const ryu = @import("ryu");

pub fn main() !void {
    if (comptime ryu.runtime_loaded) {
        try ryu.load(.{ .path = "/path/to/libryu.so" });
        // .{ .system = "libryu.so" } hands a basename to the platform loader
        // instead. The two never fall back to one another.
    }
    var out: [ryu.double_shortest_capacity]u8 = undefined;
    std.debug.print("{s}\n", .{try ryu.format64Shortest(1.25, &out)}); // 1.25E0
}
```

`ryu.runtime_loaded` is a comptime constant, so `comptime` is what keeps the
call out of a linked build entirely — there `load` is a comptime panic rather
than a no-op, because a linked build has no provider and no table to fill. The
provider is reached, never guessed. This package's own `smoke.zig` and
`consumer/src/main.zig` read it from `--provider <file>`, `--system <name>` or
`RYU_PROVIDER`, and the test suite reads `RYU_TEST_PROVIDER`. The two run steps
`build.zig` starts, for `smoke` and for `test`, are `addRunArtifact` steps that
forward no arguments, so those two programs read the environment. The consumer
package is the one that takes program arguments: its own `run` step forwards
the caller's `b.args`, so `zig build run -- --provider <file>` reaches
`consumer/src/main.zig`.

## The API

Everything the facade names is read out of upstream's own declarations, and each
declaration's comment in `zig/root.zig` cites the header and line it came from.

| Declaration | What it is |
|---|---|
| `format64Shortest(value: f64, out: []u8) Error![]u8` | the shortest binary64 string that reads back as `value` (`d2s_buffered_n`) |
| `format32Shortest(value: f32, out: []u8) Error![]u8` | the same for binary32 (`f2s_buffered_n`) |
| `format64Fixed(value: f64, precision: u32, out: []u8) Error![]u8` | fixed point with exactly `precision` digits after the point (`d2fixed_buffered_n`), for `precision` up to `2147483336` |
| `format64Scientific(value: f64, precision: u32, out: []u8) Error![]u8` | scientific with exactly `precision` digits after the leading digit (`d2exp_buffered_n`), for `precision` up to `2147483639` |
| `experimental.parse64(text: []const u8) Error!f64` | upstream's string-to-binary64 parser (`s2d_n`) |
| `experimental.parse32(text: []const u8) Error!f32` | upstream's string-to-binary32 parser (`s2f_n`) |
| `fixedCapacity(precision: u32) Error!usize` | bytes `format64Fixed` guarantees are enough, or `error.PrecisionTooLarge` above its precision limit |
| `scientificCapacity(precision: u32) Error!usize` | bytes `format64Scientific` guarantees are enough, or `error.PrecisionTooLarge` above its precision limit |
| `double_shortest_capacity: usize` = 24 | bytes the binary64 shortest writer can ever produce |
| `float_shortest_capacity: usize` = 15 | bytes the binary32 shortest writer can ever produce |
| `max_fixed_integer_digits: usize` = 309 | digits in the integer part of the widest binary64 |
| `pub const c` | the complete translated surface — `ryu/ryu.h` and `ryu/ryu_parse.h`, plus `ryu/ryu_generic_128.h` in a `-Dgeneric128` build — and the supported raw route, the one that arrives with the archive attached. Under `-Druntime=true` the same namespace comes from the generated dispatch instead, with the same nominal types |
| `format64ShortestOwned(value: f64) Error!OwnedString` | `d2s`: the NUL-terminated string upstream allocated through libc `malloc`. Release it with `OwnedString.deinit` — the C library's `free` — and with nothing else |
| `format32ShortestOwned(value: f32) Error!OwnedString` | `f2s`, same contract |
| `format64FixedOwned(value: f64, precision: u32) Error!OwnedString` | `d2fixed`, same contract, bounded by `owned_max_fixed_precision` |
| `format64ScientificOwned(value: f64, precision: u32) Error!OwnedString` | `d2exp`, same contract, bounded by `owned_max_scientific_precision` |
| `pub const OwnedString` | the one thing in this module that owns memory: upstream's pointer, its length, and a `deinit` that is the C library's `free` and not a Zig allocator's |
| `generic128` | upstream's `ryu/ryu_generic_128.h` as a typed namespace — `Decimal`, `Mantissa`, `LongDouble`, `exceptional_exponent`, `to_chars_capacity`, and the converters `fromFloat`, `fromDouble`, `fromLongDouble`, `fromBinary`, `decimalFor`, `shortestChars`, `toChars` — in a build configured with `-Dgeneric128`, and `void` in a build that did not |
| `runtime_loaded: bool` | which configuration this build is, at comptime: `false` for a linked build, `true` under `-Druntime=true`. One source file can branch on it and have only the branch it chose analyzed |
| `load(source: LoadSource) LoadError!void` | the one call that makes a runtime-loaded build usable. A comptime panic in a linked build, which is what `runtime_loaded` is there for |
| `loadedSource() ?LoadSource` | the request that succeeded, or `null` when nothing has loaded; always `null` in a linked build |
| `LoadSource` | `.{ .path = "/absolute/path" }` or `.{ .system = "basename" }`. No fallback from one to the other, no search path of our own, no implicit provider, and no unload or reset afterwards |
| `LoadError` | `EmptySource`, `SourceTooLong`, `InvalidSource`, `UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch`, `ReentrantLoad` (`runtime/loader.zig:77-116`) |
| `pub const Error` | the closed set of conditions this module refuses |

The two `double_shortest_capacity` and `float_shortest_capacity` numbers are
upstream's own: `d2s` allocates 25 bytes and NUL-terminates at the returned
length (`ryu/d2s.c:505-509`), `f2s` allocates 16 (`ryu/f2s.c:341-345`), so 24
and 15 exclude the terminator.

### Buffers, and what a caller owns

* The returned slice is a **subslice of the buffer you passed** and borrows it,
  so a later write to that buffer changes those bytes. It is not
  NUL-terminated, and no terminator byte is written: the length is already
  known. Everything in the buffer past the returned slice keeps whatever you
  had there.
* **The buffer writers allocate nothing; the `Owned` writers allocate on
  purpose.** Upstream also publishes `d2s`, `f2s`, `d2fixed` and `d2exp`, each
  of which `malloc`s and hands back a pointer the caller must `free`. The five
  buffer writers above call the `*_buffered_n` siblings and never allocate, so
  the third-party-allocator rule never arises for them. The four
  `format*Owned` functions are the deliberate exception and the whole reason
  that rule is written down: they call exactly those four upstream entry
  points (`ryu/f2s.c:342`, `ryu/d2s.c:506`, `ryu/d2fixed.c:558` and `:815`),
  and the memory they return belongs to the C library that produced it.
  `OwnedString.deinit` is that library's `free` and is not a Zig allocator's —
  under `-Druntime=true` it is the **provider's** `free`, and the loader's
  `validate` releases a candidate's allocating answer with this process's `free`
  before it publishes a table (`runtime/library.zig`, `validate`). Releasing one
  of those pointers with a Zig allocator corrupts a heap the caller does not own.
* A buffer at least `double_shortest_capacity` long is written into directly.
  A shorter one is written through a stack temporary of that size and the
  produced prefix is copied in, so `"0E0"` fits in three bytes without paying
  for the worst case on every call. A buffer that is both short and too short
  for the answer returns `error.BufferTooSmall` **and writes nothing**.
* `format64Fixed` and `format64Scientific` require `out.len` to be at least
  their bound, checked before the call, so a refused call writes nothing. The
  precision check runs before that one, so an unsupported precision is
  `error.PrecisionTooLarge` rather than `error.BufferTooSmall` whatever the
  buffer looks like — and what is left untouched is still the buffer you
  handed over.
* The one error that arrives *after* a writer has run is `error.NegativeLength`.
  Your buffer then holds what upstream wrote into it, none of it usable, so
  discard the whole buffer rather than reading a prefix of it.

### Precision, and the bounds

`precision` is a `u32`, and it is **not** honoured over its full range. The
limit comes from upstream rather than from this facade: both precision writers
accumulate their output into a signed `int index` and return that index
(`ryu/d2fixed.c:405` for `d2fixed_buffered_n`, `ryu/d2fixed.c:617` for
`d2exp_buffered_n`; both declared `int` at `ryu/ryu.h:34` and `ryu/ryu.h:38`).
A precision large enough to carry that index past `maxInt(c_int)` wraps it, so
the caller is handed a length that has nothing to do with what was written —
negative across one range of precisions, small and plausible across another.
Each style therefore accepts `precision` only up to `maxInt(c_int)` minus
whatever that style spends around the precision, and refuses above it:

```zig
const fixed_overhead: u64 = 1 + max_fixed_integer_digits + 1;  // sign, integer digits, point
const scientific_overhead: u64 = 1 + 1 + 1 + 1 + 1 + 3;        // sign, digit, point, e, sign, exponent
const special_value_capacity: u64 = 10;                        // "-nan(snan)"; "-Infinity" is 9
const max_written_bytes: u64 = @intCast(std.math.maxInt(c_int));

pub fn fixedCapacity(precision: u32) Error!usize {
    if (@as(u64, precision) + fixed_overhead > max_written_bytes) return error.PrecisionTooLarge;
    return std.math.cast(usize, fixed_overhead + @as(u64, precision)) orelse
        error.PrecisionTooLarge;
}

pub fn scientificCapacity(precision: u32) Error!usize {
    const bound = @max(scientific_overhead + @as(u64, precision), special_value_capacity);
    if (bound > max_written_bytes) return error.PrecisionTooLarge;
    return std.math.cast(usize, bound) orelse error.PrecisionTooLarge;
}
```

That is `2147483336` for `format64Fixed` and `2147483639` for
`format64Scientific`, on every target rather than only where `usize` is too
narrow to hold the digits. The check runs before `out` is even measured and
before any C is called, so a refused precision leaves your buffer byte for byte
as it was, in every optimize mode; it is an ordinary comparison, not an
assertion. Both bounds accumulate in `u64` first, so no intermediate
expression can wrap on the way, and both return `error.PrecisionTooLarge`
rather than a truncated length.

The scientific writer has a second limit of its own, and it is why that style
never had the full `u32` range to lose: `d2exp_buffered_n` raises its own
`uint32_t` precision by one before it formats anything (`ryu/d2fixed.c:616`),
so `maxInt(u32)` wraps to zero inside it and the precision the caller asked for
disappears. A native exercise of this package's own facade at that precision is
recorded in `local://foundation-zig-api-audit.md`: `1.0` came back as `0e+00`,
inside the buffer the caller had sized, so nothing downstream would have
noticed. The `int` index above is the same failure reached from the fixed side,
and one bound catches both.

The scientific bound never falls below ten bytes, because `-Infinity` and
`-nan(snan)` both have to fit at precision 0; see the output-spelling section
below for which of the two a given target can actually be handed.

Rounding carry does not escape the
arithmetic bound either: `9.9999` at precision 3 prints `1.000e+01`, one digit,
a point and three digits, which is `precision` plus two.

### The errors

`Error` has seven members and each is a comparison the code actually made:

| Error | When |
|---|---|
| `BufferTooSmall` | the slice is shorter than the bound this call can produce. Nothing was written |
| `PrecisionTooLarge` | `precision` is above what the writer can represent, so its capacity bound would exceed the `int` width upstream returns a length in, or would not fit in this target's `usize`. Checked before `out` is measured and before any C is called, so nothing was written. Reachable on every target, not only a narrow `usize` |
| `NegativeLength` | upstream's writer returned a negative length. Every return in it is a nonnegative index and the bounds above keep those indices inside the `int` they are returned as, so this reports a broken build rather than a caller mistake, and it is an ordinary error rather than a panic. Unlike the two capacity failures it arrives *after* the writer has run: your buffer holds what upstream wrote into it, none of it usable |
| `TextTooLong` | the text given to a parser is longer than the `int` length argument upstream takes (`ryu/s2d.c:71`) |
| `InputTooShort`, `InputTooLong`, `MalformedInput` | upstream's own parser statuses, one for one (`ryu/ryu_parse.h:29-34`) |

A rejected parse leaves your value untouched: the result is written to a local
and returned only on success, which matters because upstream writes `*result`
only on its `m10 == 0` and success paths (`ryu/s2d.c:137-158`,
`ryu/s2d.c:218-258`) and returns early without touching it otherwise.

### The experimental parser

Upstream marks it experimental in its own header (`ryu/ryu_parse.h:25-27`): "At
this time, it only support up to 17 non-zero digits in the input, and also does
not support all formats. Use at your own risk." Nothing about it is stabilised
here, and it is named `experimental` because upstream says so.

The grammar, in the subset both widths accept:

* an optional leading `-`;
* nonzero decimal digits with an optional point — **no surrounding whitespace,
  no `inf`, no `nan`, no hexadecimal, no `f` suffix**;
* an optional `e` or `E`, an optional sign, and at most 4 exponent digits;
* the whole of `text` must be consumed. A trailing byte outside the grammar is
  `error.MalformedInput`.

The two widths do **not** share a mantissa limit, and that is upstream's, not
this facade's:

| | binary64 (`s2d_n`) | binary32 (`s2f_n`) |
|---|---|---|
| nonzero mantissa digits refused at | 17 (`ryu/s2d.c:100-102`) | 9 (`ryu/s2f.c:94-96`) |
| exponent digits refused at | 4 (`ryu/s2d.c:120-123`) | 4 (`ryu/s2f.c:114-117`) |
| empty input | `error.InputTooShort` (`ryu/s2d.c:72-74`) | `error.InputTooShort` (`ryu/s2f.c:66-68`) |

So `"123456789"` parses at both widths, and `"1234567890"` is an ordinary parse
as a binary64 and `error.InputTooLong` as a binary32. Underflow below 1e-324 and
overflow above 1e+309 are **not** errors: they produce a signed zero and a signed
infinity respectively, which is upstream's own choice (`ryu/s2d.c:149-158`,
`ryu/s2d.c:218-222`).

### Output spelling, which is published and must not be normalised

Upstream's two scientific styles differ from each other and both are preserved
exactly, because consumers compare strings:

| | shortest | fixed / scientific |
|---|---|---|
| exponent marker | `E`, no `+`, no zero padding: `1E0`, `5E-324` (`ryu/d2s.c:400-417`) | `e`, explicit `+`, at least two exponent digits: `1.25e+00` (`ryu/d2fixed.c:788-804`) |
| NaN | `NaN` | `nan` |
| infinity | `Infinity`, `-Infinity` | `Infinity`, `-Infinity` |
| zero | `0E0`, `-0E0` | `0`, or `0.00e+00` in scientific |

The `nan` in that table has a second spelling. Upstream's shared special-string
helper has an `_MSC_VER` half that prints a NaN whose quiet bit is clear as
`nan(snan)` rather than `nan`, so a signed signalling NaN would come back as
the ten byte `-nan(snan)` there and the three byte `nan` on the other half
(`ryu/d2fixed.c:332-344`; the non-MSVC half is `ryu/d2fixed.c:345-355`). Which
half a target compiles is the compiler's answer, not yours, and upstream's own
comment on that branch is an open question rather than an answer
(`ryu/d2fixed.c:333`) — the `#if` is on `_MSC_VER` itself, so a mingw-w64 target
can take either half and nothing in this package decides it.

This is read out of the source at the pinned commit. No binary built for a
target that takes the `_MSC_VER` half has been run here, so this package makes
no claim about what such a target actually prints; the bound named in the
precision section above is sized for the wider of the two spellings because
that is the conservative choice for a caller who cannot tell, not because an
overrun has been observed. The cost of that choice is one byte, and only at
precision 0 and 1, where the bound would otherwise be nine; from precision 2
the arithmetic bound is larger than either spelling and the constant is not
what decides.

Rounding is round-to-nearest, ties to even, with a run of nines carried:
`2.5` at precision 0 is `2`, `3.5` is `4`, and `9.9999` at precision 3 is
`10.000` fixed and `1.000e+01` scientific.

### Widths

Shortest exists at both widths. Fixed and scientific exist for binary64 only —
upstream publishes no `f2fixed` or `f2exp`, and none is written here. A caller
with a `float` that needs fixed or scientific output has no upstream answer to
wrap.

## Build modes

* **Bundled, the only mode.** Upstream's C is compiled from this repository for
  whatever target is being built. There is no download, no system include path
  and no installed library behind the caller's back.
* **System mode: not offered, and recorded as not satisfied rather than as
  vacuous.** There is no `b.systemIntegrationOption`. Upstream's own install
  rules publish `ryu/ryu.h` and, on a compiler with `__uint128_t`,
  `ryu/ryu_generic_128.h` (`CMakeLists.txt:28`, `:46-47`), and never publish
  `ryu/ryu_parse.h`; the parsers are not in the CMake library target at all
  (`CMakeLists.txt:6-18`). An installed ryu therefore cannot supply this
  package's surface, and a mode that linked it would be translating this tree's
  headers against an ABI of unknown age — the quiet failure the fork rules
  forbid. `UPSTREAM.md` § "System-library mode" has the full argument.
* **`-Dlinkage=static|dynamic`, the delivery mode.** `static` is the default and
  is what this package has always installed; it is also what upstream's CMake
  produces, since `CMakeLists.txt:6` carries no `SHARED` keyword. `dynamic`
  installs a real shared object. The option selects the artifact and nothing
  else: same sources, same `-std=gnu17`, same include root either way. A target
  that cannot carry a shared object **refuses** `-Dlinkage=dynamic` rather than
  answering it with an archive. `wasm32-wasi` is the one cell in this package's
  own six-target matrix that does, because `std.Target.DynamicLinker.kind` is
  `.none` there, and the build stops at configure time naming the target with
  the build's own sentence:

  ```
  -Dlinkage=dynamic cannot deliver shared objects for wasi: its OS has no dynamic linker (std.Target.DynamicLinker.kind is .none), so a shared object there is a file nothing can load. No static substitution is made. Build this target with -Dlinkage=static, which is the default.
  ```

  That refusal is the whole answer (`build.zig:844-853`, raised as a
  configure-time panic at `:867-876`, and inside `check` as an explicit failing
  step rather than as an archive). A Windows target is **not** in that set:
  `targetCarriesSharedObject` reads a `.none` dynamic linker on PE/COFF as a
  loader that does exist, so this matrix's `x86_64-windows-gnu` cell does build
  `ryu.dll` under `-Dlinkage=dynamic` (`build.zig:826-829`). The shared object
  has **no soname, no version script and no export list**: upstream publishes no
  ABI number (`CMakeLists.txt:2` is a version *line*), no `VERSION`/`SOVERSION`,
  and no visibility or dllexport macro in either public header, so every symbol
  is exported by default. Nothing in this package invents a versioning policy
  upstream does not have.
* **`-Druntime=true`, the dispatch mode, and independent of `-Dlinkage`.** It
  changes how an entry point is reached, not what is built: the artifact is
  still compiled and installed exactly as `-Dlinkage` decided, while the module
  a dependent imports links no archive at all and every declared native
  function becomes a call through one process-lifetime table. That table is
  generated from *this build's own* translation output — `runtime/generate.zig`
  reads what the translation step actually produced and `runtime/graph.zig`
  wires it in — so the sixteen entry points of a default build, or the
  twenty-one of a `-Dgeneric128` build, follow from the header this
  configuration selected and neither list is written by hand
  (`build.zig:245-262`). A provider arrives when the caller calls `ryu.load`,
  by absolute path or by basename; nothing is searched for, nothing is guessed,
  and nothing is linked as a second way in. Default off, and a linked build is
  unchanged in every respect. Linking the archive into a module that imports
  this dispatch is the one mistake that matters: the linker would resolve the
  same symbols statically and the runtime route would silently be a linked one
  (`runtime/graph.zig:26-31`).
* **`-Dgeneric128`, optional, and compiled for the native target only.**
  Compiles `ryu/generic_128.c` as a sixth unit, installs
  `ryu/ryu_generic_128.h` for a C caller that wants `float_to_fd128` and
  friends, **and translates that header too**, so the option is not a C-surface
  one: the same five converters are published to Zig through `ryu.c`, through
  the facade's `generic128` namespace, and as five more entries that a
  runtime-loaded build requires from its provider. Upstream tags that unit
  `nowindows` (`ryu/BUILD:38-49`) and gates its CMake target on `__uint128_t`
  (`CMakeLists.txt:31-52`); this build asks the compiler for the target being
  built and defines no `-DRYU_*` flag for that unit to paper over the answer.
  The six-target `check` never depends on it — the twelve green `check` rows
  below (six targets, run twice) are the five-unit graph and carry no claim
  about this one, and `check -Dgeneric128=true` has never been run for any
  target. Two of its rows are
  native observations and are recorded as exactly that: upstream's own header
  says `long_double` "likely only works on x86 with specific compilers"
  (`ryu/ryu_generic_128.h:50-51`) because the x87 80-bit layout stores the
  leading bit explicitly, which is the one layout where upstream passes
  `explicitLeadingBit = true` (`ryu/generic_128.c:70-81`).

## Verification status

Observed runs in this workspace. Every build row below was run by the driver
with the pinned 0.16.0 compiler and `--summary all`; the integrity,
pristine-diff and `zig fetch` rows name the tool that ran them instead. Every
status below is read out of the named receipt; nothing here is predicted. This
table is the authoritative gate state for this package — `FORK-NOTES.md` § 0
carries the run history and says why each state is the state it is, and none
of the other records repeats either.

Every test count in that table is the count of the run named in that row, and
every one of those rows stays exactly as it was observed. The behavioural suite
has changed since those runs: it gained precision-boundary tests, and the
owned-string allocator loop was later removed under the test policy
(`CHANGELOG.md` entry 12). Those counts describe the suite as it stood at the run
that printed them, and no historical row in the table is a count of the tree in
front of you. **A current total does now exist, and it is in the last rows of
the table rather than above them**: the current default-configuration waves
print `32/36` and the current `-Dgeneric128=true` waves print `35/36`, each with
its skips named in its row. Neither is a clean suite, and this table states no
total of its own.

**Read this table with the current-pending list beside it.** Most rows below were
observed on the tree as it stood *before* the contract-migration wave: shared
delivery, the runtime-loaded route, the Nix and devenv packaging and the
relocated README were all added afterwards, and those rows are evidence about a
tree that no longer exists in that form. The last six rows are the newest
evidence here: driver waves run on this tree on 2026-10-04 and 2026-10-05, each
named by its epoch. The two loaded-runtime rows of 2026-10-04 further up are red
for exactly one reason, named in their rows, and those driver waves supersede
them — they exported the second variable those runs did not, and the loaded
`test` step then ran to completion in all eight configurations.
`README.md` § 3b is the rest of the pending list, row for row. A historical row
is not a pass on the tree in front of you, and a `skipped-tests` cell is not a
pass either: every driver row below states both the `zig build` exit code and
the driver's own strict verdict, and the two do not have to agree.

| Gate | State | Receipt |
|---|---|---|
| `test`, `smoke` and `install`, Debug | **observed, exit 0 — `Build Summary: 11/11 steps succeeded; 28/28 tests passed`.** Current run includes the inline native change notice and corrected aggregate citation; the earlier stable and first patched-header rounds remain history. Install prefix is outside the repository | `local://foundation-cross-test-final-ryu-native-Debug.log`; earlier `local://foundation-cross-test-stable-ryu-native-Debug.log` and `local://foundation-cross-test-ryu-native-Debug.log` |
| `test` and `smoke`, ReleaseSafe | **observed, exit 0 — `Build Summary: 9/9 steps succeeded; 28/28 tests passed`.** Same current header and unchanged golden outputs, with optimisation enabled; no install step in this command | `local://foundation-cross-test-final-ryu-native-ReleaseSafe.log`; earlier `local://foundation-cross-test-stable-ryu-native-ReleaseSafe.log` |
| `smoke`, on its own | **observed, exit 0** as part of the Debug row above. Every printed answer matched its published expectation: both signed zeroes, both infinities, `NaN` in shortest and `nan` in fixed, `5E-324`, `DBL_MAX`, `DBL_MIN`, the subnormal float `1E-45`, the ties `2.5 → 2` and `3.5 → 4`, the carry `9.9999 → 10.000`, and the refusals `InputTooLong` and `MalformedInput` | the Debug log above; the standalone pre-deviation run is `…-final-smoke-93.log` |
| consumer | **observed, exit 0 — `Build Summary: 6/6 steps succeeded`.** Native source-dependent consumer through `.path = ".."`, current annotated header; not an installed-C-artifact proof | `local://foundation-cross-test-final-ryu-native-consumer.log`; earlier `local://foundation-cross-test-stable-ryu-native-consumer.log` |
| install | **observed, exit 0** as the `install` step of the Debug row, 11/11 steps, into an approved prefix outside the repository. The in-tree `zig-out/` install of record is `…-final-install-101.log` (exit 0, 6/6 steps) and the prefix install of record `…-installed-artifact-gruenau8-177.log`; both predate the header deviation, and the archive was compiled rather than reused in the prefix run | those three |
| installed C surface | **observed, exit 0, before the header deviation.** `<ryu/ryu.h>` and `<ryu/ryu_parse.h>` resolve and link on their own against the installed `libryu.a`; the four `malloc`-returning formatters are used and each result is freed, both parser widths in both the `_n` and the `strlen` form, the published roundings `0.125 → 0.12`, `0.375 → 0.38`, `2.5 → 2`, `3.5 → 4`, and three refused inputs each leaving its sentinel value untouched. No run of this gate against the patched header is recorded | `local://foundation-expansion-ryu-installed-C-surface-isolated-cache-191.log` |
| `check`, six cross targets | **observed, exit 0 for all six on the current annotated header**, default five-unit graph, compile-only. Earlier pre-deviation and first patched-header rounds remain historical receipts | `local://foundation-cross-test-final-baseline.json`, `cells[]` entries `sdk: ryu`; `local://foundation-cross-test-final-baseline-ryu-<target>.log` |
| Source and fetched `sha256sum -c UPSTREAM.sha256` | Final current-record checks belong to the driver-owned package closure; the earlier 38-record green receipt checked pre-deviation bytes and is history | `FORKS.json.cross_test_wave.materialized_packages.ryu`; `local://foundation-cross-test-package-regression.json` |
| `git diff --exit-code 4c0618b0… -- ryu src third_party scripts lean LICENSE-Apache2 LICENSE-Boost` | **historical.** Exit 0 with empty output, run directly by the driver rather than through CI, over those seven path groups — on the tree as it stood before the deviation, when every path it names was byte-identical to the pinned commit. On the patched tree `ryu/ryu.h` differs by the disclosed line; that comparison has not been re-run here, and no claim is made for the other six path groups beyond what the record states | `local://foundation-expansion-ryu-pinned-native-pristine-diff-270.log` (pre-deviation) |
| `zig fetch` (materialised package) | **historical, pre-deviation.** Exit 0, printing `ryu-2.0.0-dev.4c0618b-R0zYELvxcAFVJPiXdq8VFwYeo8snAY1LtpoTMccR3abs`, from a scratch build root outside this repository with `--global-cache-dir` pointing at the driver's own package cache. That identity is a function of the package bytes, which the deviation and this file's own edits have since moved, so it names the tree as it stood and not this one; no current identity is asserted anywhere above. A fresh package round runs once the documentation settles | `local://foundation-expansion-ryu-external-driver-package-fetch-327.log` |
| `sha256sum -c UPSTREAM.sha256` **inside the materialised package** | **historical, pre-deviation.** Exit 0, all 38 records `OK` on the bytes as they stood then. The claim it made — every path the record names is present in the filtered copy a dependent receives, which an in-checkout run cannot show — is unchanged in shape, but it has not been re-made against the current record | `local://foundation-expansion-ryu-materialized-package-integrity-336.log` |
| consumer, materialised package | **historical, pre-deviation.** Exit 0 — `zig build run -j8` from inside the fetched copy rather than from this tree, so `consumer/`'s relative `.path` resolved against a package this repository's build graph never produced, ending `every answer matched the published values` | `local://foundation-expansion-ryu-materialized-package-consumer-343.log` |
| `zig fetch` from the package source root | **superseded.** exit 1, `error: unable to copy directory '/vol/fob-vol7/mi19/gertullj/foundation-libs/ryu': IllegalFileTypeInPackage`. The passing row above is the same absolute package path fetched from an external scratch build root; no byte of this tree changed between the two, and no cause is asserted here for the difference | `local://foundation-expansion-ryu-materialized-package-fetch-263.log` |
| `-Dgeneric128`, native build | **observed, exit 0 before the header deviation**, 6/6 steps, both into `zig-out/` (`…-generic128-proof-116.log`) and into an approved prefix outside the repository (`…-generic128-installed-artifact-195.log`). No `-Dgeneric128` run against the patched header is recorded | those two |
| `-Dgeneric128`, installed C surface | **observed, exit 0 before the header deviation.** The installed `ryu/ryu_generic_128.h` and the archive carrying it agree on `float`, `double` and `long double` `1.25 → 1.25E0`; on an independent IEEE binary128, built as exponent field `16383 << 112` or-ed with fraction `1 << 110`, once positive and once with the sign bit set, giving `1.25 → 1.25E0` and `-1.25 → -1.25E0`; and on both signed zeroes. The run ends `the installed ryu_generic_128.h and libryu.a agree on every value above`. The unit includes `ryu/ryu_generic_128.h`, not `ryu/ryu.h`, so the deviation does not touch it — but that is a source reading, not a re-run | `local://foundation-expansion-ryu-generic128-C-surface-corrected-227.log` |
| `check -Dgeneric128=true`, any target | **NOT RUN.** The optional sixth unit has never been compiled for a foreign target. Upstream tags it `nowindows` (`ryu/BUILD:38-49`) and gates its CMake target on `__uint128_t` (`CMakeLists.txt:31-52`), so a matrix result for it would be a finding, not a formality. The twelve green `check` rows above (six targets, run twice) are the **default five-unit graph** and say nothing about this one | — |
| `.github/workflows/verify.yml` | **Whole CI never executed.** The current one-line native reversal excerpt was executed locally: current annotated `<stdint.h>` line restores the exact pristine `<inttypes.h>` line, yielding the original 1,360-byte header and SHA-256 `b7feab0ba1df5e9ef3d602f386592ad152491405e49b408fb21c0e0e9e6bfb16`. This proves that excerpt, not the entire workflow or every Git-history gate | `local://foundation-cross-test-evidence.json`, auxiliary check `ryu-native-include-notice-reversal` |
| system mode | not applicable — there is no system mode to run. See "Build modes" | — |
| `bash -n cross-test.profile.sh` | **observed, exit 0** — the profile parses | `local://foundation-cross-test-profile-ryu-syntax.log` |
| `cross-test --list` from the package root | **observed, exit 0 — 53 targets**, and `--no-profile --list` names the same 53, so the profile restricts the table to none of them. All 24 profile-verification commands across the eight additions are exit 0 in the aggregate receipt | `local://foundation-cross-test-profile-ryu-list_profile.log`, `-list_no_profile.log`; aggregate `local://foundation-cross-test-profile-verification.json` |
| `cross-test`, full 53-cell matrix, **before** the header deviation | **observed, exit 1 — 20 pass, 9 fail, 24 `build_only`, 0 partial.** All nine failures are one translation failure of NetBSD's `<inttypes.h>`, the diagnostic quoted in § "Deviations from upstream", one per NetBSD cell: `aarch64`, `aarch64_be`, `arm`, `armeb`, `mips`, `mipsel`, `powerpc`, `x86`, `x86_64`. The native cell compiled and ran the suite, 28/28, and the 32-bit and big-endian rows the six-target `check` never reached were compiled here. This is the receipt the deviation answers | `local://foundation-cross-test-evidence.json`, `checks[]` entry `library: ryu`, `stage: matrix`; per-cell logs `local://foundation-cross-test-matrix-ryu-<target>.log` |
| `cross-test`, full 53-cell matrix, **after** the header deviation | **observed, exit 0 — 20 pass, 0 fail, 33 `build_only`, 0 partial**, harness `run_id` `20261002-053059-41494-21055`, every one of the 53 cells compiled. The 20 cells with a runner each ran the full 28-test suite, 560 executed tests in all; the 33 without one are recorded `build_only`, which is compile coverage and never counted as a pass. **All nine NetBSD cells are among those 33**: they compile now, and this host has no NetBSD runtime to execute them | `local://foundation-cross-test-corrected-ryu.json` (summary), `local://foundation-cross-test-corrected-ryu-<target>.log` (53 per-cell logs) |
| `cross-test`, full 53-cell matrix, **current inline change notice** | **observed, exit 0 — 20 pass, 0 fail, 33 `build_only`, 0 partial**, `run_id` `20261002-080415-53964-27076`, build deadline 3,600 seconds, four jobs per build, two targets concurrently. All 53 cells compiled; all 20 runnable Linux cells passed 28 tests each. The earlier corrected run above remains history | `local://foundation-cross-test-final-current-ryu.json`; `local://foundation-cross-test-final-current-ryu-<target>.log` |
| `test smoke install -Druntime=true`, four optimize modes, both linkages, provider named by `RYU_PROVIDER` | **observed, exit 1 for all eight.** The build, the dispatch generation and `install` succeeded, and `smoke` resolved the provider it was given and printed its checked answers in every mode; the `test` step is the only step that failed. Each run reports `Build Summary: 25/27 steps succeeded (1 failed); 0/37 tests passed (37 crashed)`, because `tests.zig` requires a second variable, `RYU_TEST_PROVIDER`, which those runs did not export, and every test aborts on that precondition rather than skipping itself. A missing environment variable is not a finding about the route, and it is recorded as it was observed | `local://foundation-current-failures-ryu.json`, labels `ryu-current-loaded-{dynamic,static}-{Debug,ReleaseSafe,ReleaseFast,ReleaseSmall}` |
| the same tree linked rather than loaded, `-Druntime=false`, both linkages, four optimize modes | **observed, exit 0 for all eight** — `Build Summary: 26/26 steps succeeded; 33/37 tests passed (4 skipped)` in each. The four skips are the generic-128 tests, which exist only in a build configured with `-Dgeneric128` and say so when they are skipped (`tests.zig:35-36`); these runs configured the default five-unit closure. Each configure line names its own configuration, `linked dispatch (direct calls)` here | the `ryu-current-*` rows of `local://foundation-current-native-index.json` |
| `build test smoke install`, **default** configuration, native, both linkages × four optimize modes | **partial, 8 of 8 cells.** Each command exits 0 and prints `Build Summary: 26/26 steps succeeded; 32/36 tests passed (4 skipped)`; the driver records `status: skipped-tests` on every cell, with `pass: 0`, `fail: 0`, `not_passed: 8` and a wrapper exit of 1. The four skips are the generic-128 tests, which exist only in a `-Dgeneric128=true` build, so this wave cannot exercise the optional unit at all | epoch `20261004T233628757747Z-69351`, rows `ryu-native-final-*` of `run.json` and their per-cell receipts |
| the same, runtime-loaded, provider named by **both** `RYU_PROVIDER` and `RYU_TEST_PROVIDER`, this tree's own `libryu.so` | **partial, 8 of 8 cells**: `Build Summary: 27/27 steps succeeded; 32/36 tests passed (4 skipped)` in each, `status: skipped-tests` throughout, `fail: 0`, `not_passed: 8`. This is the replay the 2026-10-04 row asked for, and it ran — with both variables exported the loaded `test` step executes instead of aborting on its precondition. The four skips are the same feature-off ones and say nothing about the route | epoch `20261004T232823091897Z-23133`, rows `ryu-loaded-final-*` of `run.json` |
| **`-Dgeneric128=true`**, native, both linkages × four optimize modes | **partial, 8 of 8 cells, and the current result for this option.** `zig build test smoke install -Doptimize=<mode> -Dlinkage=<static\|dynamic> -Druntime=false -Dgeneric128=true -j8 --summary all`: **exit 0 in all eight**, `Build Summary: 26/26 steps succeeded; 35/36 tests passed (1 skipped)` in each, `smoke` ending `every answer matched`, `install` carrying `include/ryu/ryu_generic_128.h` into its approved prefix (`generic128_header_installed: true`), compiled-input closure `identical: true`. **The one skip is always the same site, `tests.zig:1172`**, guarded `if (comptime ryu.generic128.LongDouble != f80) return error.SkipZigTest;`, and `skip_attribution` reads `expected_skipped: 1`, `reachable_sites: 1`, `other_sites: 0`, `feature_off_sites_could_fire: false`, `bucket: abi_guard`, `partial: true` — the translated C `long double` is not the x86 `f80` spelling Zig uses, so the test declines to compare across an ABI it cannot see through. `totals`: `fail: 0`, `pass: 0`, `skipped_tests_abi_guard: 8`, `not_passed: 8`, wrapper exit 1 | epoch `20261005T014407332917Z-66097-ryu-native`, `run.json` `totals` and `skip_site_buckets`, and the eight `ryu-native-generic128-*` cell receipts |
| **`-Dgeneric128=true`**, runtime-loaded, the same eight configurations, provider this tree's own `libryu.so` from that wave's dynamic prefixes | **partial, the other 8 of the 16 cells.** **exit 0 in all eight**, `Build Summary: 27/27 steps succeeded; 35/36 tests passed (1 skipped)` in each, the same single skip at `tests.zig:1172`, the same `bucket: abi_guard` and `partial: true`, the same `generic128_header_installed: true` and `closure_diff.identical: true`; `fail: 0`, `not_passed: 8`, wrapper exit 1 | epoch `20261005T015048544771Z-69523-ryu-loaded`, `run.json` and the eight `ryu-loaded-generic128-*` cell receipts |
| whole-graph `check`, **compile-only**, no `-Dtarget`, the six required triples | **observed, exit 0, `failed: false`.** A compile-only row: `runtime_pass_claimed: false` is recorded under **every** exit code, so a green baseline proves compilation and nothing about runtime. It is still the **default five-unit graph** and says nothing about `-Dgeneric128` | epoch `20261005T014547Z-797a73f2`, receipt `baseline-ryu-check-2026-10-05T01-45-53.904710+00-00.json` |
| `cross-test`, full 53-target matrix, on this tree | **observed, exit 0 — 53 targets: 20 runtime PASS, 33 `build_only`, 0 fail, 0 partial**, `--jobs 8 --build-jobs 8`, `source_unchanged: true`, `jobs_honoured: true`. **This is not 53 runtime passes.** A green "53 targets built" line is not 53 test passes: the 33 `build_only` cells compiled and had no runtime available, and `build_only` is never counted as a pass. Across the 23-SDK cohort the same 53 targets are 1219 cells — 366 runtime PASS, 687 build-only, 102 build-fail, 64 runtime-fail. The three rows above are earlier runs on earlier trees | epoch `20261004T221720228710Z-45046`, receipt `ryu-53-target-8.json` and its 53 per-cell logs |

Every `…-…` prefix above is `local://foundation-expansion-ryu`. The
cross-test-wave receipts this table also names are
`local://foundation-cross-test-*`.

**What the loaded rows needed, and what the replay then printed.** Both
variables have to be exported for the whole `zig build` invocation, because a
build cannot inject a path into a run step's environment: `RYU_PROVIDER` for
`smoke` and `RYU_TEST_PROVIDER` for `test`, both naming the same shared object.
The 2026-10-04 runs exported the first and not the second; the driver waves
exported both, and the loaded `test` step then ran to completion in all eight
configurations. The 2026-10-04 rows stay exactly as they were observed.

**Sixteen cells, sixteen partials — and the two numbers do not conflict.** Each
of the sixteen `-Dgeneric128=true` cells has a `zig build` exit code of 0 and a
driver strict verdict of `skipped-tests`, so the driver's own wrapper exits 1
for every one of them: a partial is not a pass, and the build command
succeeding is a different measurement from the verdict. `35/36` is one skip
short of `36/36`, and nothing in this file writes the latter.

**The boundary those sixteen cells do not cross.** No independent external
provider was exercised: the route wave of epoch `20261004T232439Z` records
`external_successes_observed: 0`, `own_routes_counted_as_external: []` and
`refusals_observed: 7`, so the only provider that ever satisfied this SDK's
surface was this tree's own source-built `libryu.so` and every external
candidate was an expected refusal. `check -Dgeneric128=true` has still never
been run for any foreign target, so the optional sixth unit has native
evidence and no other. No foreign byte has been delivered or verified either:
this SDK's delivery-candidate file is a candidate analysis, and the
twelve-byte foreign criteria it names have not been executed.

**The materialised package, and what those rows proved.** `zig fetch` copied
this package, as `.paths` filters it, into the driver's package cache, and
running `sha256sum -c UPSTREAM.sha256` **inside that copy** and getting all 38
records `OK` is the `.paths` closure claim, a different claim from the in-tree
row: a checkout can hold a file the manifest does not list, so a green check
here would not show that the record is still checkable where a dependent
actually keeps it. That copy carried every compiled unit, every header in
`ryu/`, the nine upstream test sources the fixtures were transcribed from, both
licence texts, `README.upstream.md`, `CONTRIBUTORS`, the six fixtures and
`translate.h`.

Those three rows are **history now**, and for a reason that belongs in the
record rather than in a footnote: the identity `zig fetch` prints is a function
of the package bytes, the deviation and this file's own edits both moved those
bytes. Final filtered fetch, source/fetched integrity and fetched-consumer
results are recorded after documentation settles in the workspace ledger's
`cross_test_wave.materialized_packages.ryu` and
`local://foundation-cross-test-package-regression.json`. This file does not
quote a final identity: its own bytes contribute to that identity.

The consumer built and ran from inside that filtered copy, with its own
`--cache-dir`, so nothing was reused from this tree's build outputs. **No
registry, no remote, no publication**: the fetch is over a local absolute path,
nothing here resolves a URL, a registry, a git remote or a published hash, no
publication has been authorised, and that identity string is what this compiler
printed for the directory as it stood — not a hash a downstream can fetch today.
The `-Dgeneric128` rows above are unchanged by any of this: that consumer built
the **default five-unit graph**, and nothing here adds a generic-128 claim for
the fetched copy or for any foreign target.

**The direct diff and the CI job are different claims.** The pristine diff was
run by hand over the seven path groups named in its row and was clean — before
the header deviation, when that claim was true. The job itself has still never
run, and it compares more than that hand-run diff did: among the upstream paths
the job covers and the direct diff does not are `CMakeLists.txt`, `README.md`,
`CONTRIBUTORS`, `MODULE.bazel`, `.bazelrc`, `.bazelversion`, `.classpath`,
`lean-toolchain` and `run_benchmark_linux.sh`. Its pinned-commit step now admits
**three** differing upstream paths: `.gitignore`, this fork's `ryu/ryu.h`, and
`README.md`, which this fork replaced with its own README while preserving
upstream's bytes unedited at `README.upstream.md`. A following step holds the
`ryu/ryu.h` one to the recorded pristine and patched digests and to the one-line
shape of the difference. A green hand-run diff is not a green job, and this
table reports neither as one.

The installed layout is present in this tree's `zig-out/`: `lib/libryu.a`,
`include/translate.h`, `include/ryu/ryu.h`, `include/ryu/ryu_parse.h`, and with
`-Dgeneric128` `include/ryu/ryu_generic_128.h` beside them. That directory was
written by the pre-deviation install of record, so the `ryu.h` in it still reads
`<inttypes.h>`; the install on the patched header went to an approved prefix
outside this repository. Run `zig build install` to refresh the in-tree copy.

**One claim this file made is withdrawn.** The first run of the optional
128-bit C gate was red, and the gate was wrong rather than the library
(`local://foundation-expansion-ryu-generic128-C-surface-before-correction-208.log`,
exit 1):

```
binary128 1.25: got "5E-1" (4 bytes), want "1.25E0"
binary128 -1.25: got "-5E-1" (5 bytes), want "-1.25E0"
FAILED
```

The gate handed `generic_binary_to_decimal` `explicitLeadingBit = true` for a
layout that is IEEE binary128. Binary128 has an **implicit** leading bit, so
that argument made the converter read `1.25` as `0.5`. Upstream passes `false`
for float and double (`ryu/generic_128.c:55`, `:64`) and `true` only for
`long double`, whose x87 layout is the explicit-bit case
(`ryu/generic_128.c:80`). The repair changed that one argument and nothing
else — no expected value, no buffer size, no upstream byte — and the same gate
then ran green. `FORK-NOTES.md` § 11 has the lesson.

Earlier red gates are kept as history rather than as current state, because a
red receipt is the evidence for the diagnosis it supports, and every one of
them describes files as they stood at the time: `…-initial-debug-18.log` (a
`c_int` where translate-c had produced `c_uint`), `…-repaired-debug-26.log`
(5 failures of 26), `…-current-debug-50.log` and
`…-current-releasesafe-58.log` (the same single wrong expected row, in a
29-test suite), `…-current-consumer-67.log` and `…-final-consumer-102.log` (two
compile errors in the consumer, in turn), `…-installed-C-surface-182.log` (a
stale cache, and a `-Wcomment` warning raised by this fork's own `translate.h`)
and `…-generic128-C-surface-before-correction-208.log` above. Each is written
up in `FORK-NOTES.md`, and the 53-cell `cross-test` run of the pre-deviation
tree is kept the same way: its nine red cells are the observation the header
deviation answers, and that run says nothing about the patched header.

## Testing approach

The primary oracle is an **independent** known answer, never this library's own
output. `testdata/` holds six files, transcribed verbatim from upstream's own
gtest suites, with the source file and line of every row recorded in the
fixture's own header:

| Fixture | Rows | Source of every row |
|---|---|---|
| `d2s_shortest.txt` | 132 | `ASSERT_D2S(...)` in `ryu/tests/d2s_test.cc` |
| `f2s_shortest.txt` | 60 | `ASSERT_F2S(...)` in `ryu/tests/f2s_test.cc` |
| `d2fixed.txt` | 134 | `EXPECT_FIXED(...)` in `ryu/tests/d2fixed_test.cc` |
| `d2exp.txt` | 134 | `EXPECT_EXP(...)` in `ryu/tests/d2fixed_test.cc` |
| `s2d_parse.txt` | 39 | `EXPECT_S2D(...)` and the BadInput case in `ryu/tests/s2d_test.cc` |
| `s2f_parse.txt` | 28 | `EXPECT_S2F(...)` in `ryu/tests/s2f_test.cc`; upstream has no rejected-input test for the binary32 parser, so its rejected rows are read out of `ryu/s2f.c`'s own status returns, cited by line |

527 rows in total. Nothing in them was computed by this fork.

Three independent checks sit on top of that corpus, and they are different kinds
of evidence:

1. **An independent parser.** Zig's `std.fmt.parseFloat` must read every
   published shortest answer back as that row's own input bit pattern. A row
   that recorded the wrong answer, or the wrong input for the right answer,
   disagrees with itself here.
2. **An independent formatter.** Zig's own `std.fmt` float formatter must agree
   digit for digit with this facade, once the two styles' exponent spelling is
   normalised. Zig's shortest formatter is Errol/Grisu and Ryu is Ryu; neither
   derives from the other. Ties are excluded from that comparison on purpose and
   for a stated reason: Ryu rounds a tie to even and Zig's own Errol path rounds
   toward zero, which is exactly the disagreement two of the fixture rows pin.
3. **Boundaries and invariants.** A buffer exactly as long as an answer is
   accepted and a buffer one byte short is refused with the caller's bytes
   untouched; the writers stop at the answer and leave the rest of the buffer
   alone; the widest special-value spelling upstream can emit is formatted
   into a buffer of exactly the published bound, at the two precisions where
   that bound is the special value; each precision writer's last accepted
   precision is the one whose answer still fits the `int` it returns a length
   in, and the next precision and `maxInt(u32)` are refused by both capacity
   queries and both writers with the caller's bytes untouched; a tie goes to
   even; a run of nines carries out of the fraction at one precision and does
   not one digit short of it.

There is no same-code round trip anywhere in the suite, and nothing here pins a
version string, an export, a default or a call that merely does not fail.

## Integrity

```
sha256sum -c UPSTREAM.sha256
```

38 records, 2689946 bytes: the compiled units, every header in `ryu/`, the nine
upstream test sources the fixtures were transcribed from, both licence texts
plus `README.upstream.md` and `CONTRIBUTORS`, the six fixtures, and
`translate.h`. The file's own header states per group why each path is in it,
why the excluded paths are out, and — since the header deviation — exactly which
line `ryu/ryu.h`
differs by, with upstream's digest and this tree's printed side by side
(`UPSTREAM.sha256:112-114`, with the baseline also at `:49`). `verify.yml` replays the command as the
first step of its native job, before anything is built, and that job has still
never been executed here.

The last run of the command against this tree reports all 38 records `OK`
(`local://foundation-expansion-ryu-corrected-header-current-integrity-287.log`),
and it describes the **pre-deviation** bytes. The record has since been
re-derived with `ryu/ryu.h` at its patched digest, so the replay that matches
the current tree is `PENDING-VERIFICATION`: no command has produced it here.

The digests are hashes of this working tree, not Git object ids, and what the
record can no longer be paired with is the older claim that the paths it names
are byte-identical to commit `4c0618b0e44f7ef027ebae05d2cc7812048f7c8f`. One of
them, `ryu/ryu.h`, deliberately is not, and the record says so in its own header
instead of hiding it. The direct `git diff --exit-code` over `ryu`, `src`,
`third_party`, `scripts`, `lean`, `LICENSE-Apache2` and `LICENSE-Boost` was
clean when the driver ran it over the pre-deviation tree
(`local://foundation-expansion-ryu-pinned-native-pristine-diff-270.log`, exit 0,
empty output); on the patched tree that comparison reports `ryu/ryu.h`, and
nothing else is claimed here because it has not been re-run. The workflow's own
job — every tracked path, and the pinned commit an ancestor of `HEAD` — is a
different and still unrun check; see "Verification status".

`UPSTREAM.sha256` is listed in `build.zig.zon` `.paths` beside every other fork
record, so a dependent who fetches the package receives the fingerprint too and
the check above is replayable in an unpacked package. That was observed once, on
the package `zig fetch` materialised from this tree before the deviation
(`local://foundation-expansion-ryu-materialized-package-integrity-336.log`, all
38 records `OK`, so every path the record names is present in the filtered copy
a dependent receives). It is the one gate in this section that has to be
re-made for the current record rather than merely re-read.

## Licence

Upstream's native core is `Apache-2.0 OR BSL-1.0`: everything outside
`third_party/` is Apache-2.0, and the files in `ryu/` may alternatively be used
under Boost-1.0 (`README.upstream.md:35-38`). Both texts ship verbatim as
`LICENSE-Apache2` and `LICENSE-Boost`. Upstream's Java port, everything else
outside `ryu/`, and the six vendored `third_party/` corpora are **not** covered
by the Boost alternative; `NOTICE.md` records which grant applies to which path,
what each third-party corpus is under, and the Apache-2.0 obligations this fork
discharges. The one altered upstream file, `ryu/ryu.h`, stays under both of
upstream's grants and carries its own copyright block and dual grant verbatim:
the edit changes an include, not a term, and neither licence text is touched.
**The files this fork authored carry `Apache-2.0`**, granted by this
repository's owner for fork-authored additions and matched to this project's
primary upstream term. `FORK-LICENSE.md` records the authorization, the SPDX
identifier, every path the grant covers and every path it excludes; no upstream
author is credited for them and no personal identity is invented for them.
Choosing Apache-2.0 for them **retains** the Boost-1.0 alternative for the
`ryu/` core rather than consuming it: a downstream may take Boost-1.0 for the
core and Apache-2.0 for the fork's additions, and both texts ship either way.

One partial overlap is recorded rather than left to inference: this fork appends
two lines to upstream's `.gitignore`. Those two lines are fork-authored; every
line upstream wrote in that file keeps upstream's Apache-2.0 and none of them is
changed or removed.

## See also

* `UPSTREAM.md` — the pin, the archive receipt, the import, and the system-mode
  argument.
* `NOTICE.md` — attribution, per-path licence, and every file this fork adds or
  edits.
* `CHANGELOG.md` — numbered fork-only divergences.
* `FORK-NOTES.md` — the problems met, in the shape a later wave can reuse.
* `README.md` — the canonical order: native-source deviations, native-build
  deviations and their dated history, the current build/run/test matrix with
  historical evidence separated from what is pending, and consumption.
* `README.upstream.md` — upstream's README, byte for byte. Every line reference
  in this file to upstream's own prose resolves against that file, not against
  this package's README.
* `FORK-LICENSE.md` — the grant for the files this fork authored, and the paths
  it covers and excludes.
* `UPSTREAM.sha256` — 38 digests over the bytes this package compiles, installs,
  tests against or publishes terms for.