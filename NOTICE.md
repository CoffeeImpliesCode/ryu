# NOTICE

## Upstream work

Ryu is the work of **Ulf Adams** and contributors. The copyright notices the
carried files carry for themselves:

| File | Notice |
|---|---|
| `ryu/ryu.h:1` | `Copyright 2018 Ulf Adams` |
| `ryu/ryu_parse.h:1` | `Copyright 2019 Ulf Adams` |
| `src/main/java/info/adams/ryu/RyuDouble.java:1` | `Copyright 2018 Ulf Adams` |

`CONTRIBUTORS` names three people: Ulf Adams `<ulfjack@google.com>`, Stephan T.
Lavavej `<stl@microsoft.com>`, Alexander Bolz `<alexbolz@web.de>`.

Upstream repository: `https://github.com/ulfjack/ryu`. This fork builds commit
`4c0618b0e44f7ef027ebae05d2cc7812048f7c8f` on `master`. `CMakeLists.txt:2`
declares upstream's own version line, `project(ryu VERSION 2.0 LANGUAGES C)`;
that is upstream's version string, not a release this tree is claimed to be.

## The grants, and which one applies to which path

Upstream states the grant in prose, at `README.md:35-38`:

> All code outside of third_party/ is copyrighted by Ulf Adams and
> contributors, and may be used freely in accordance with the Apache 2.0
> license. Alternatively, the files in the ryu/ directory may be used freely in
> accordance with the Boost 1.0 license.

Both texts ship in this repository, byte for byte, and are not edited,
shortened, merged or restated here:

| File | Grant |
|---|---|
| `LICENSE-Apache2` | Apache License, Version 2.0 |
| `LICENSE-Boost` | Boost Software License, Version 1.0 |

The grant is **per path**, and that distinction is the part a downstream has to
get right:

| Path | Grant | Why |
|---|---|---|
| `ryu/` — the C core, the experimental parsers, the generic 128-bit pair, every header | **Apache-2.0 OR BSL-1.0** | the alternative is granted for "the files in the `ryu/` directory" (`README.md:37-38`), and each public header repeats the dual grant per file (`ryu/ryu.h:3-12`, `ryu/ryu_parse.h:3-12`). One file in this group is altered by one line — `ryu/ryu.h:24` — under both of these terms, without narrowing either; see "What this fork changed" |
| `src/` — upstream's Java port | **Apache-2.0 only** | outside `ryu/`, so the Boost alternative does not reach it; every file carries the Apache header alone (`src/main/java/info/adams/ryu/RyuDouble.java:2-14`) |
| `scripts/`, `lean/`, `lakefile.toml`, `lake-manifest.json`, `lean-toolchain` — the table generators and the Lean 4 port | **Apache-2.0** | same reasoning |
| `CMakeLists.txt`, `MODULE.bazel`, `.bazelrc`, `.bazelversion`, `.classpath`, `run_benchmark_linux.sh`, `run_benchmark.bat`, `.github/workflows/presubmit.yml`, `README.md`, `CONTRIBUTORS` | **Apache-2.0** | same reasoning |
| `third_party/` | **six separate works under their own terms** — see the next section | "All code outside of third_party/" excludes them from upstream's own grant |

* Everything this fork did **not** write stays under upstream's own per-path
  grant. This fork narrows nothing and re-grants nothing; a downstream may take
  Apache-2.0 or Boost-1.0 for the `ryu/` core, and Apache-2.0 for everything
  else.
* The fork-authored Zig build graph, aggregate header, facade, tests, example,
  consumer package, cross-test harness profile, fixture transcriptions and
  documentation carry no stated licence. Their status is **unassigned**; no
  licence may be inferred from the upstream licence texts. The earlier Apache-2.0
  offer over these files was
  unsupported and is withdrawn. Upstream's per-path grants above are unchanged.

This repository is a private downstream. That removes no obligation: the
copyright notices, both licence texts, and this file travel with the source and
with any binary or archive built from it.

## `third_party/` — six works, six sets of terms

Nothing in this package compiles, links, installs or reads any of these; they
are vendored because upstream's own Java and Bazel suites use them and because
they are part of the pinned tree. They ship in `.paths` and are not in
`UPSTREAM.sha256`, because the record covers what this package builds and tests
while the pristine-commit diff in `.github/workflows/verify.yml` covers every
upstream-tracked byte including these. Their conditions travel with the tree all
the same, and this section exists so nobody has to rediscover them:

| Directory | Work and terms | Where the terms are |
|---|---|---|
| `third_party/gtest` | GoogleTest, BSD 3-clause, `Copyright 2008, Google Inc.`, with the no-endorsement clause | `third_party/gtest/LICENSE` |
| `third_party/junit` | JUnit 4.12 under the **Eclipse Public License 1.0**. The same directory also carries `hamcrest-core-1.3.jar` and `hamcrest` is not covered by that file's terms | `third_party/junit/LICENSE` |
| `third_party/mersenne` | Test data: GNU Free Documentation License **OR** CC BY-NC-SA 3.0 Unported, per the directory licence; the NonCommercial condition belongs to the CC alternative, not the GFDL alternative. `random.h` separately carries Apache-2.0 | `third_party/mersenne/LICENSE:1-4`; `third_party/mersenne/random.h:1-13` |
| `third_party/mersenne_java` | The Java generator carries an explicit Apache-2.0 source header; it does not inherit the neighbouring data directory's terms | `third_party/mersenne_java/java/info/adams/random/MersenneTwister.java:1-16` |
| `third_party/jaffer` | Aubrey Jaffer's permission notice with retained copyright, warranty disclaimer and no-name-in-advertising condition, **plus Apache-2.0** for Heng Yuan's Java code; no alternative-selector is invented | `third_party/jaffer/LICENSE:1-30` and its full Apache text; `third_party/jaffer/java/org/yuanheng/cookjson/DoubleUtils.java:1-15` |
| `third_party/double-conversion` | the V8 project's double-conversion library, BSD 3-clause, `Copyright 2006-2011, the V8 project authors` | `third_party/double-conversion/LICENSE`, duplicated verbatim in `third_party/double-conversion/COPYING` |

JUnit and the Mersenne data have terms distinct from the Apache/Boost core.
The Java generator's source header is its explicit grant despite the absence
of a separate directory licence file. All supplied notices stay unchanged;
this inventory records the per-file grants rather than assigning one term
to an entire directory.

## Credits upstream records, which are not grants

`README.md` credits the line of work this algorithm came from and the proof it
rests on, and this fork drops none of it: the problem of shortest round-trip-safe
decimal output was posed by White and Steele and named "Dragon"
(`README.md:51-54`), with the paper's own correctness proof at `README.md:78-79`.
`README.md:81-86` lists other independent implementations (Scala, Rust, and
others); they are credits, not sources, and nothing from them is in this tree.

## Apache-2.0 obligations for this fork's own files

`LICENSE-Apache2` §4 requires a copy of the licence (shipped as
`LICENSE-Apache2`, unmodified), prominent change notices in modified files
(`ryu/ryu.h:24`), supplemented by the change table and `CHANGELOG.md` (§4(b)),
retention of upstream's notices (§4(c)), and, for works that carry a `NOTICE`
file, that copies include the attribution above (§4(d), this file).

**§4(c) notices are retained, including in the modified header.** One upstream header,
`ryu/ryu.h`, is altered by one line, and that is disclosed in the table below
rather than left to be discovered. Nothing else is edited: no upstream C source,
no other header, no test, no licence text and no fixture byte. The altered
header keeps upstream's own copyright line and its per-file dual grant verbatim,
so the notice travels with the file.

### Patent grant

`LICENSE-Apache2` §3 grants a perpetual Contributor patent licence, subject to
its terms. Licences granted to **You** for the Work terminate on the date You file patent litigation alleging that the Work or an incorporated Contribution infringes a patent. This
fork has added no algorithm: `zig/root.zig` calls `d2s_buffered_n`,
`f2s_buffered_n`, `d2fixed_buffered_n`, `d2exp_buffered_n`, `s2d_n` and `s2f_n`
and returns what they return, and the only work added on top is buffer bounds,
casts, capacity arithmetic and error mapping. Upstream's shortest-conversion
proof is the one the patent grant attaches to, and this distribution modifies the
packaging, not the conversion.

### The alternative grants are not narrowed

A downstream that takes Boost-1.0 for the `ryu/` core instead of Apache-2.0
removes no obligation of its own, because the attribution, both licence texts
and the change statement here are required by the Apache-2.0 path and are kept
for either. `.github/workflows/verify.yml`'s provenance job checks that both
texts are present and each carries its own title, precisely so that a later edit
cannot quietly reduce the shipped alternatives to one.

## What this fork changed

**Two upstream-tracked files are edited, and both are disclosed here rather than
claimed as pristine.** `UPSTREAM.sha256` records the SHA-256 of the bytes this
package compiles, installs, tests against or publishes terms for — 38 records,
one of them, `ryu/ryu.h`, hashed at its altered digest with upstream's own
digest printed beside it at `UPSTREAM.sha256:112-114` (also `:49`).
The current source/fetched replay and consumer results are driver-owned:
`FORKS.json.cross_test_wave.materialized_packages` and
`local://foundation-cross-test-package-regression.json`. Earlier receipts
126 and 287 are history for earlier header/record states.
The workflow runs the integrity check and explicitly verifies the one-line
header reversal to the pinned upstream digest. That reversal excerpt was
observed locally; **no whole CI job has been run**, and none is claimed.

| File | Change |
|---|---|
| `ryu/ryu.h` | **one line at `:24`: upstream `<inttypes.h>`, current `<stdint.h>` plus an inline Foundation-fork notice.** Upstream: 1360 bytes, `b7feab0ba1df5e9ef3d602f386592ad152491405e49b408fb21c0e0e9e6bfb16`; current: 1417 bytes, `83ed2a4cd2e42cdd351383b5c937e320e47d8e0ea214964a7b8568f974754dae`. Copyright, licence paragraphs and all declarations are unchanged; the file remains Apache-2.0 **OR** Boost-1.0. Its sole imported type is `uint32_t`, used in the **six** precision parameters at `ryu/ryu.h:34-40`; no `PRI*` or `SCN*` macro is used. `<stdint.h>` declares that same type. Removing the unused include avoids NetBSD's `__END_DECLS` `_Pragma` translation failure without copied prototypes, fabricated headers, changed algorithms or target-specific native branches. Full scope and original/current digests are in `UPSTREAM.sha256` and `UPSTREAM.md` |
| `.gitignore` | upstream's own ignore list — `bazel-*`, `MODULE.bazel.lock`, `/.eclipse-bin/`, `/project`, `/.lake`, `.vscode/`, `ryu/*.[oa]`, `ryu/tests/*.test` — is kept verbatim and unedited; the fork appends `.zig-cache/` and `zig-out/`, each under a comment saying why. Because the file is therefore not byte-identical to upstream's, it is deliberately absent from `UPSTREAM.sha256` and from `verify.yml`'s diff list, and the append is recorded here instead. `ryu/ryu.h` is hashed, not excluded |

Everything else this fork adds is new, in new files and new regions:

| File | What it is |
|---|---|
| `build.zig` | Zig 0.16 build: compiles upstream's five C units (six with `-Dgeneric128`), installs `libryu.a` plus `ryu/ryu.h`, `ryu/ryu_parse.h` and `translate.h`, and defines the `test`, `smoke` and `check` steps |
| `build.zig.zon` | package manifest, dependency-free, `.paths` = what a dependent receives |
| `translate.h` | the only new C file: an aggregate header that includes the two upstream public headers and declares nothing of its own, translated for whichever target is being built. It includes `ryu/ryu.h` as altered above — the one-line deviation in this table is therefore part of what a translation sees — and says so in its own comment |
| `zig/root.zig` | the Zig facade: the four formatters, the two experimental parsers, the capacity bounds, the error set, and `pub const c` for the complete translated surface |
| `tests.zig` | 28 behavioural tests: six fixtures transcribed from upstream's own gtest suites, cross-checks against Zig's independent parser and formatter, and the buffer-boundary and rounding-invariant cases |
| `testdata/*.txt` | the six fixtures. **Fork-authored transcriptions**: every data row is a literal string upstream asserts in `ryu/tests/*.cc`, with the file and line it came from recorded in the fixture's own header. They are not upstream files and upstream ships no such files |
| `smoke.zig` | the deterministic example behind `zig build smoke`; it checks its own answers and exits non-zero on any mismatch |
| `consumer/` | a separate package that depends on this one by relative path and runs it |
| `cross-test.profile.sh` | harness settings only: `cross-test` discovers it from the package root and it names the standard `test` step over the full published platform matrix. It contains no upstream byte, builds nothing and grants nothing |
| `.github/workflows/verify.yml` | this fork's own verification workflow: immutable-source integrity, native, install layout, cross matrix, consumer, and licence-and-provenance. Upstream's `presubmit.yml` is left untouched and unretargeted |
| `UPSTREAM.md`, `UPSTREAM.sha256`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md` | provenance, integrity and fork documentation |

## Correctness notes that survive from upstream

* **The two scientific styles are different, and callers compare strings.**
  The shortest writer prints `1.25E0`, `5E-324`, `1.7976931348623157E308`
  (`ryu/d2s.c:400-417`, `ryu/f2s.c:294-303`); the precision writers print
  `1.25e+00`, an explicit `+` and at least two exponent digits
  (`ryu/d2fixed.c:788-804`).
* **The special values are spelled differently in the two families.** Shortest
  prints `NaN`, `Infinity`, `-Infinity`, `0E0` (`ryu/common.h:86-100`).
  Fixed/scientific special values use `ryu/d2fixed.c:331-356`; their zero spellings use `:434-437` and `:585-599`.
* **Ties round to even and a run of nines carries.** `2.5` at precision 0 is `2`
  and `3.5` is `4`; `9.9999` at precision 3 is `10.000` in fixed form and
  `1.000e+01` in scientific form. These are upstream's own published answers,
  from `D2fixedTest.RoundToEvenInteger` and `D2fixedTest.Carrying`.
* **Do not cast before converting.** Upstream says so in its own README
  (`README.md:16-17`): shortest conversion depends on the precision of the
  source type. `format64Shortest` takes an `f64` and `format32Shortest` takes an
  `f32` for that reason; converting a `float` by widening it to `double` and
  calling the binary64 writer gives a different, longer string.
* **The parsers are experimental and say so.** `ryu/ryu_parse.h:25-27`: "At this
  time, it only support up to 17 non-zero digits in the input, and also does not
  support all formats. Use at your own risk." The two widths do not even share a
  grammar: `s2d_n` refuses at 17 nonzero mantissa digits and `s2f_n` at 9.