# ryu — IEEE-754 to decimal in Zig, over upstream's C

This package compiles **ulfjack/ryu at commit
`4c0618b0e44f7ef027ebae05d2cc7812048f7c8f`** — upstream's own C sources, from
the `ryu/` directory in this repository — into a static C library, translates
upstream's two public headers, and publishes a Zig facade over that
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
a version dispatcher that needs a version-bearing `build.zig`; the compiler
every gate below was run with is at

```
/home/tmp/gertullj/zig-global-cache/p/N-V-__8AAFFSVRWqblwBIcA-Yqv-u7sbjsJoww8K0mWaHbmJ/zig
```

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
conditional (`build.zig:244-263`), and the tree contains no fork-authored
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
| `zig build -Dgeneric128` | additionally compiles `ryu/generic_128.c` as a sixth unit and installs `ryu/ryu_generic_128.h`. Off by default, C surface only, and compiled for the native target only so far |
| `cd consumer && zig build run` | the same library, consumed by a package that did not write it |

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

## The API

Everything the facade names is read out of upstream's own declarations, and each
declaration's comment in `zig/root.zig` cites the header and line it came from.

| Declaration | What it is |
|---|---|
| `format64Shortest(value: f64, out: []u8) Error![]u8` | the shortest binary64 string that reads back as `value` (`d2s_buffered_n`) |
| `format32Shortest(value: f32, out: []u8) Error![]u8` | the same for binary32 (`f2s_buffered_n`) |
| `format64Fixed(value: f64, precision: u32, out: []u8) Error![]u8` | fixed point with exactly `precision` digits after the point (`d2fixed_buffered_n`) |
| `format64Scientific(value: f64, precision: u32, out: []u8) Error![]u8` | scientific with exactly `precision` digits after the leading digit (`d2exp_buffered_n`) |
| `experimental.parse64(text: []const u8) Error!f64` | upstream's string-to-binary64 parser (`s2d_n`) |
| `experimental.parse32(text: []const u8) Error!f32` | upstream's string-to-binary32 parser (`s2f_n`) |
| `fixedCapacity(precision: u32) Error!usize` | bytes `format64Fixed` guarantees are enough |
| `scientificCapacity(precision: u32) Error!usize` | bytes `format64Scientific` guarantees are enough |
| `double_shortest_capacity: usize` = 24 | bytes the binary64 shortest writer can ever produce |
| `float_shortest_capacity: usize` = 15 | bytes the binary32 shortest writer can ever produce |
| `max_fixed_integer_digits: usize` = 309 | digits in the integer part of the widest binary64 |
| `pub const c` | the complete translated `ryu/ryu.h` and `ryu/ryu_parse.h` |
| `pub const Error` | the closed set of conditions this module refuses |

The two `double_shortest_capacity` and `float_shortest_capacity` numbers are
upstream's own: `d2s` allocates 25 bytes and NUL-terminates at the returned
length (`ryu/d2s.c:505-509`), `f2s` allocates 16 (`ryu/f2s.c:341-346`), so 24
and 15 exclude the terminator.

### Buffers, and what a caller owns

* The returned slice is a **subslice of the buffer you passed**, and it is not
  NUL-terminated. The length is already known, so no terminator is written.
* **There is no allocation anywhere in the facade.** Upstream also publishes
  `d2s`, `f2s`, `d2fixed` and `d2exp`, each of which `malloc`s and hands back a
  pointer the caller must `free`; this module calls none of them and calls the
  `*_buffered_n` siblings instead. The third-party-allocator rule never arises.
* A buffer at least `double_shortest_capacity` long is written into directly.
  A shorter one is written through a stack temporary of that size and the
  produced prefix is copied in, so `"0E0"` fits in three bytes without paying
  for the worst case on every call. A buffer that is both short and too short
  for the answer returns `error.BufferTooSmall` **and writes nothing**.
* `format64Fixed` and `format64Scientific` require `out.len` to be at least
  their bound, checked before the call, so a refused call writes nothing.

### Precision, and the bounds

`precision` is a `u32` and is honoured over its full range, up to and including
`maxInt(u32)`. No precision is refused for being large. What can be refused is
the arithmetic around it:

```zig
const fixed_overhead: u64 = 1 + max_fixed_integer_digits + 1;  // sign, integer digits, point
const scientific_overhead: u64 = 1 + 1 + 1 + 1 + 1 + 3;        // sign, digit, point, e, sign, exponent
const special_value_capacity: u64 = 9;                         // "-Infinity"

pub fn fixedCapacity(precision: u32) Error!usize {
    return std.math.cast(usize, fixed_overhead + @as(u64, precision)) orelse
        error.PrecisionTooLarge;
}

pub fn scientificCapacity(precision: u32) Error!usize {
    const bound = @max(scientific_overhead + @as(u64, precision), special_value_capacity);
    return std.math.cast(usize, bound) orelse error.PrecisionTooLarge;
}
```

Both accumulate in `u64` first, so no intermediate expression can wrap on the
way, and both return `error.PrecisionTooLarge` rather than a truncated length.
That error is reachable on a 32-bit target such as `wasm32-wasi` and not on a
64-bit one. The scientific bound never falls below nine bytes because
`-Infinity` is nine (`ryu/d2fixed.c:354-355`) and has to fit at precision 0.
Rounding carry does not escape it either: `9.9999` at precision 3 prints
`1.000e+01`, one digit, a point and three digits, which is `precision` plus two.

### The errors

`Error` has seven members and each is a comparison the code actually made:

| Error | When |
|---|---|
| `BufferTooSmall` | the slice is shorter than the bound this call can produce. Nothing was written |
| `PrecisionTooLarge` | the `u32` precision's capacity bound does not fit in this target's `usize`. Nothing was written |
| `NegativeLength` | upstream's writer returned a negative length. Its own source has no such path, so this reports a broken build rather than a caller mistake, and it is an ordinary error rather than a panic |
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
* **`-Dgeneric128`, optional, and compiled for the native target only.**
  Compiles `ryu/generic_128.c` as a sixth unit and installs
  `ryu/ryu_generic_128.h` for a C caller that wants `float_to_fd128` and
  friends. Upstream tags that unit `nowindows` (`ryu/BUILD:38-49`) and gates
  its CMake target on `__uint128_t` (`CMakeLists.txt:31-52`); this build asks
  the compiler for the target being built and defines no `RYU_*` macro to
  paper over the answer. The Zig facade publishes **no** generic 128-bit
  symbol, so `-Dgeneric128` is a C-surface option only, and the six-target
  `check` never depends on it — the twelve green `check` rows below (six
  targets, run twice) are the five-unit graph and carry no claim about this
  one, and `check -Dgeneric128=true` has never been run for any target. Two of
  its rows are
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

Every `…-…` prefix above is `local://foundation-expansion-ryu`. The
cross-test-wave receipts this table also names are
`local://foundation-cross-test-*`.

**The materialised package, and what those rows proved.** `zig fetch` copied
this package, as `.paths` filters it, into the driver's package cache, and
running `sha256sum -c UPSTREAM.sha256` **inside that copy** and getting all 38
records `OK` is the `.paths` closure claim, a different claim from the in-tree
row: a checkout can hold a file the manifest does not list, so a green check
here would not show that the record is still checkable where a dependent
actually keeps it. That copy carried every compiled unit, every header in
`ryu/`, the nine upstream test sources the fixtures were transcribed from, both
licence texts, `README.md`, `CONTRIBUTORS`, the six fixtures and `translate.h`.

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
two differing upstream paths, `.gitignore` and this fork's `ryu/ryu.h`, and a
following step holds that second one to the recorded pristine and patched
digests and to the one-line shape of the difference. A green hand-run diff is
not a green job, and this table reports neither as one.

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
   alone; the nine byte special value sizes the scientific bound at the two
   precisions where it does; a precision no capacity can express is refused
   rather than wrapped; a tie goes to even; a run of nines carries out of the
   fraction at one precision and does not one digit short of it.

There is no same-code round trip anywhere in the suite, and nothing here pins a
version string, an export, a default or a call that merely does not fail.

## Integrity

```
sha256sum -c UPSTREAM.sha256
```

38 records, 2689946 bytes: the compiled units, every header in `ryu/`, the nine
upstream test sources the fixtures were transcribed from, both licence texts
plus `README.md` and `CONTRIBUTORS`, the six fixtures, and `translate.h`. The
file's own header states per group why each path is in it, why the excluded
paths are out, and — since the header deviation — exactly which line `ryu/ryu.h`
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
under Boost-1.0 (`README.md:35-38`). Both texts ship verbatim as
`LICENSE-Apache2` and `LICENSE-Boost`. Upstream's Java port, everything else
outside `ryu/`, and the six vendored `third_party/` corpora are **not** covered
by the Boost alternative; `NOTICE.md` records which grant applies to which path,
what each third-party corpus is under, and the Apache-2.0 obligations this fork
discharges. The one altered upstream file, `ryu/ryu.h`, stays under both of
upstream's grants and carries its own copyright block and dual grant verbatim:
the edit changes an include, not a term, and neither licence text is touched.
The fork-authored files have no stated licence: their status is unassigned, and
no grant may be inferred from the upstream licence texts.

## See also

* `UPSTREAM.md` — the pin, the archive receipt, the import, and the system-mode
  argument.
* `NOTICE.md` — attribution, per-path licence, and every file this fork adds or
  edits.
* `CHANGELOG.md` — numbered fork-only divergences.
* `FORK-NOTES.md` — the problems met, in the shape a later wave can reuse.