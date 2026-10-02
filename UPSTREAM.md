# UPSTREAM.md — what this fork is a fork of

## Upstream

| | |
|---|---|
| Project | Ryu, routines that convert IEEE-754 binary floats to decimal strings in shortest, fixed `%f` and scientific `%e` form |
| Canonical repository | `https://github.com/ulfjack/ryu.git` |
| Pinned ref | a commit on `master`; upstream publishes no tag this pin is taken from |
| Pinned commit | `4c0618b0e44f7ef027ebae05d2cc7812048f7c8f` |
| Version line upstream declares | `2.0`, at `CMakeLists.txt:2` (`project(ryu VERSION 2.0 LANGUAGES C)`) |
| Licence of the native core | `Apache-2.0 OR BSL-1.0` |
| Copyright | `Copyright 2018 Ulf Adams` in `ryu/ryu.h:1`, `Copyright 2019 Ulf Adams` in `ryu/ryu_parse.h:1` |

**The pin is a master commit, not the `v2.0` release.** The workspace delivery
record names it exactly that way and calls out the older `v2.0` pin as stale
(`local://foundation-expansion-delivery.md`, "Full candidate dispositions"), and
`local://foundation-expansion-sources.json` records `"ref"` and `"commit"` as the
same value, `4c0618b0e44f7ef027ebae05d2cc7812048f7c8f`. `CMakeLists.txt:2` is
upstream's own version line and is reported above for what it is; it is not a
claim that this tree is the `v2.0` release. Because a SemVer build-metadata
suffix cannot carry a commit id, `build.zig.zon` pins the prefix in the
pre-release field: `.version = "2.0.0-dev.4c0618b"`.

Where each of the rest comes from, read out of the carried tree:

* The licence is `README.md:35-38`: "All code outside of third_party/ is
  copyrighted by Ulf Adams and contributors, and may be used freely in accordance
  with the Apache 2.0 license. Alternatively, the files in the ryu/ directory may
  be used freely in accordance with the Boost 1.0 license." Both texts ship
  whole and unedited as `LICENSE-Apache2` and `LICENSE-Boost`, and the two public
  headers carry the same dual grant per file (`ryu/ryu.h:3-12`,
  `ryu/ryu_parse.h:3-12`). `NOTICE.md` records which grant applies to which
  path, and what that means for the Java tree.
* The authors are `CONTRIBUTORS`, three lines: Ulf Adams `<ulfjack@google.com>`,
  Stephan T. Lavavej `<stl@microsoft.com>`, Alexander Bolz `<alexbolz@web.de>`.
* `README.md:78-79` points at the correctness proof: the PLDI'18 paper, with
  upstream's own citation link. Nothing in this fork re-derives that result.

**Tag signature: not verified here.** No GPG key was consulted and no git
command was run while this file was written. Treat the commit id and the archive
digest below as provenance anchors, not as a signature check.

## Archive receipt

The workspace delivery record `local://foundation-expansion-source-archives.json`
holds a SHA-256 receipt for the deterministic `git archive` stream of the **full
tree** at that commit. For this library it reads, verbatim:

```
4218f6e9b0e98414919b53d27d17f1748ee11e28caf127da3a48117803790d13  -
```

The trailing `-` is `sha256sum`'s name for standard input: the digest is of the
archive stream as it was piped past the hasher, not of any file in this
repository. The driver recorded it when the fork was imported. Replaying it
needs a clone:

```
git -C <clone> archive --format=tar 4c0618b0e44f7ef027ebae05d2cc7812048f7c8f | sha256sum
```

The output must read
`4218f6e9b0e98414919b53d27d17f1748ee11e28caf127da3a48117803790d13  -`.

## Import mechanism

A full clone of the canonical repository, so upstream's Git history is present.
This fork adds no patch series on top of that history: the Zig package is a set
of new files in new regions, and exactly two upstream-tracked files are edited
rather than one.

* `.gitignore` gains appended ignore entries for this fork's Zig caches
  (`NOTICE.md`). No line upstream wrote there is changed or removed, and two
  appended lines are the whole of the difference.
* `ryu/ryu.h:24` reads `#include <stdint.h>` here and `#include <inttypes.h>`
  at commit `4c0618b0e44f7ef027ebae05d2cc7812048f7c8f`. That include carries
  one name into the header, `uint32_t`, used in the six `precision` parameters
  at `ryu/ryu.h:34-40`, and no `PRI*` or `SCN*` macro; `<stdint.h>` declares
  the same type (C99 7.18.1) and is the header `<inttypes.h>` includes to reach
  it. The reason is portability, not preference: NetBSD's `<inttypes.h>` closes
  its declarations with `__END_DECLS`, whose replacement list starts with a
  `_Pragma` the pinned translator reads as ordinary tokens, which is what the
  nine NetBSD cells of the platform matrix hit.

That header edit is one line. `UPSTREAM.sha256` keeps upstream's digest for the
path beside this tree's, and `verify.yml` requires upstream's bytes to reappear
when that one include is put back. No other upstream-tracked path differs from
the pinned commit.

## What this fork is

A Zig package that compiles upstream's **real C implementation** from the `ryu/`
directory in this repository into a static C library, translates upstream's two
public headers for Zig through one fork-authored aggregate header, and publishes
a small Zig facade over that translation. No digit this package prints is
computed by Zig code: every answer comes from a call into a compiled upstream
translation unit, reachable directly through `pub const c`.

Compiled on every build, listed in `build.zig` `core_sources` and named the way
upstream's own `ryu/BUILD:7-19` and `:24-36` name them:

| Source | What it is |
|---|---|
| `ryu/d2s.c` | shortest binary64 |
| `ryu/f2s.c` | shortest binary32 |
| `ryu/d2fixed.c` | fixed-point **and** scientific binary64 (`d2fixed_buffered_n`, `d2exp_buffered_n`) |
| `ryu/s2d.c`, `ryu/s2f.c` | upstream's experimental string-to-float parsers |

Upstream's CMake library target does not contain the two parsers
(`CMakeLists.txt:6-18`) and never installs `ryu/ryu_parse.h`
(`CMakeLists.txt:28`). This fork builds and installs them anyway: a fork that
silently dropped them would not be the same library, and the parsers are the only
published way to get the string-to-float direction out of Ryu.

`ryu/generic_128.c` is the third experimental piece and is **not** built by
default. `-Dgeneric128` compiles it and installs `ryu/ryu_generic_128.h`.
Upstream builds it as a separate target tagged `nowindows` (`ryu/BUILD:38-49`,
whose comment at `:47` says "The code does not compile on Windows") and gates its
CMake target on the compiler providing `__uint128_t` (`CMakeLists.txt:31-52`).
Nothing in this package defines a `RYU_*` macro to paper over that: whether the
compiler for the target being built has `__uint128_t` and a working `long double`
is the compiler's answer for that target.

It has been compiled, installed and driven from a real C consumer on the native
x86_64 GNU/Linux target, and never for a foreign one; the six-target `check` is
the default five-unit graph and covers none of it. Its `long double` entry point
is also the one layout with an **explicit** leading bit — upstream passes
`explicitLeadingBit = true` there and `false` for float, double and any IEEE
binary it is handed (`ryu/generic_128.c:55`, `:64`, `:80`) — which is the reason
upstream's own header limits its claim to x86 with specific compilers
(`ryu/ryu_generic_128.h:50-51`).

The C is compiled with exactly one flag, `-std=gnu17`, and that is a decision
rather than an omission: upstream's core copies a `double` by its bits
(`ryu/common.h:108-112`) and then works in integer arithmetic, so no result
depends on how the compiler rounds, contracts or reassociates floating point.
See `FORK-NOTES.md`.

## The Java implementation, and how it differs

`src/main/java/info/adams/ryu/` holds upstream's own Java port of the shortest
conversion (`RyuFloat`, `RyuDouble`). It is **not** part of the native core this
package builds, and this fork compiles none of it.

* **Licence.** Every Java file carries only the Apache-2.0 header, for example
  `src/main/java/info/adams/ryu/RyuDouble.java:1-14`. The Boost alternative is
  granted for "the files in the `ryu/` directory" (`README.md:35-38`), so the
  Java tree is Apache-2.0 and has no Boost grant behind it. The distinction is
  recorded here and in `NOTICE.md` because the two choices are per-path, not
  per-project.
* **Behaviour.** Upstream records that the Java implementation "differs from the
  output of `Double.toString` in some cases: sometimes the output is shorter
  (which is arguably more accurate) and sometimes the output may differ in the
  precise digits output" (`README.md:69-72`, linking issue 83), and that while
  the Java specification requires at least two digits, "We may change the Java
  implementation in the future to support both" (`README.md:74-76`).

Consequences for a caller of **this** package: none of the Java behaviour is
reachable through the Zig facade or through the installed C headers, and no
answer in this package's fixtures or tests comes from Java. Conversely, a caller
who wants the Java port wants upstream's `src/` tree and its own build; the files
are carried here unmodified in `.paths` for provenance and audit, and this fork
builds, links and installs none of them.

`lean/` and `scripts/` are the same kind of carried-but-not-built material: a
Lean 4 port and the C/Python/Perl generators that produced the checked-in
tables. The build compiles none of them and regenerates no table.

## System-library mode

**Not offered, and recorded as not satisfied rather than as vacuous.**

There is deliberately no `b.systemIntegrationOption` in `build.zig` and no system
branch. The Build owner recorded the reasoning at `build.zig:47-72`; the
underlying facts, all readable in this tree, are:

* Upstream's own install rules publish `ryu/ryu.h` (`CMakeLists.txt:28`) and, on
  a compiler with `__uint128_t`, `ryu/ryu_generic_128.h`
  (`CMakeLists.txt:46-47`). They never publish `ryu/ryu_parse.h`, and
  `s2d.c`/`s2f.c` are not in the CMake library target at all
  (`CMakeLists.txt:6-18`).
* An installed ryu therefore cannot supply this package's published surface. A
  system mode would have to compile the parsers from this tree and link
  formatting against the installed library, which is a fork-specific hybrid with
  no upstream precedent — and translating this tree's headers against an older
  installed library is exactly the failure mode the fork rules forbid: a bundled
  header newer than the installed ABI compiles and then misbehaves quietly.
* No installed ryu was found on the machine this package was built on: a file
  search of `/usr/include` for `ryu*` and of `/usr/lib` for `libryu*` returned
  nothing, checked 2026-10-01 before any build was attempted
  (`build.zig:54-57`). That is an observation about one machine, not a claim about
  every distribution.

So the honest statement is "this fork has no system mode and cannot honestly
grow one", which is different from the header-only case where the mode is
undefined for a structural reason. A caller who wants an installed ryu links it
directly; a caller who wants these parsers needs this tree.

## What is upstream's and is shipped unmodified

Everything named in `build.zig.zon` `.paths` that this fork did not write, with
the two exceptions named under "Import mechanism" called out where they sit:
`.gitignore` gains two appended lines, and `ryu/ryu.h` carries the one patched
include. Every other path below is byte-identical to the pinned commit.

| Path | What it is |
|---|---|
| `ryu/` | upstream's whole C directory, except that `ryu/ryu.h` carries the one patched include: the five compiled units, the generic 128-bit pair, all twelve headers including the checked-in power-of-five and bit tables the build never regenerates, `ryu/BUILD`, `ryu/Makefile`, `ryu/benchmark/`, and `ryu/tests/` |
| `ryu/tests/` | upstream's own gtest suite, carried whole. It is the source of every expected string in `testdata/`, is not compiled here (it needs gtest and a C++ compiler), and none of it is deleted |
| `src/` | upstream's Java port and its test tree. Carried, not built; Apache-2.0 |
| `third_party/` | six vendored corpora that only upstream's Java and Bazel suites use — gtest, junit, mersenne, mersenne_java, jaffer, double-conversion. Each carries its own licence and each is recorded in `NOTICE.md`; none is compiled or linked here |
| `scripts/` | the C/Python/Perl generators that produced the checked-in tables |
| `lean/`, `lean-toolchain`, `lakefile.toml`, `lake-manifest.json` | upstream's Lean 4 port |
| `CMakeLists.txt`, `MODULE.bazel`, `.bazelrc`, `.bazelversion`, `.classpath`, `run_benchmark_linux.sh`, `run_benchmark.bat` | upstream's other build entry points, kept and not retargeted |
| `.github/` | upstream's own `presubmit.yml`, byte-identical, driving Bazel on upstream's runners, plus this fork's `verify.yml` |
| `LICENSE-Apache2`, `LICENSE-Boost`, `README.md`, `CONTRIBUTORS` | upstream's licence terms, README and authorship record |
| `.gitignore` | upstream's ignore list, with two appended lines (see `NOTICE.md`) |

`build.zig.zon` `.paths` deliberately omits nothing that `build.zig` needs:
`zig/root.zig`, `tests.zig`, `smoke.zig`, `consumer/`, `testdata/` and
`translate.h` are all listed, so a dependent that fetches the package receives a
buildable, testable library rather than an archive with no header and no
examples.

## Integrity

`UPSTREAM.sha256` holds 38 records, one `<hex>  <path>` line each, in
`sha256sum` format: the SHA-256 of every byte this package compiles, installs,
tests against or publishes terms for. Thirty hash upstream's own bytes exactly
as the pinned commit ships them. One, `ryu/ryu.h`, hashes this fork's patched
bytes and keeps upstream's digest for the same path beside it; six are
`testdata/` fixtures, which have no upstream counterpart; one is
`translate.h`, which this fork wrote. The set is six groups — the six compiled
units, all twelve headers in `ryu/`, all nine upstream test sources that the
fixtures transcribe, the two licence texts plus the two files that state the
grant and name the authors, the six fixtures, and the fork's one shipped C
header. Check it from the repository root with:

```
sha256sum -c UPSTREAM.sha256
```

The `#`-prefixed header of that file states, per group, why each path is in it
and why the excluded paths are out. Every path it names is shipped in `.paths`,
so the same command works in a cloned repository *and* in an unpacked package
fetched by a dependent. Comment lines are skipped by `sha256sum -c`: verified
against GNU coreutils 9.6 on this machine, with and without `--strict`.

**How the digests were produced.** Each file was read as raw bytes with Bun's
`Bun.file(path).arrayBuffer()` and hashed with SHA-256 through
`new Bun.CryptoHasher("sha256")`, on 2026-10-01. No shell hashing command and no
git command produced any line. All 38 records were then re-derived from the
written file and compared byte-for-byte against the files it names.

The same comparison was repeated on 2026-10-02 by re-reading those 38 files and
re-hashing them: 38 records over 2689837 bytes, no mismatch, no duplicate and
no missing or extra path, every digest unchanged. The 2688626-byte total this
paragraph carried until then was stale; the record set itself did not move.

The later `translate.h` citation correction says **three** of the five compiled
units include `ryu/ryu.h`; `s2d.c` and `s2f.c` include `ryu_parse.h`. That
comment-only edit adds 50 bytes, bringing the current record to **2689887
bytes**. Only Group F's `translate.h` digest was re-derived for that edit;
native declarations, algorithms and fixtures did not change.

The inline change notice on the existing `ryu/ryu.h:24` adds another 59 bytes
without shifting any line: the current total is **2689946 bytes**, and the
1417-byte header hashes to
`83ed2a4cd2e42cdd351383b5c937e320e47d8e0ea214964a7b8568f974754dae`.
The provenance workflow restores that entire include-and-notice line to
upstream's include before checking the original digest.

**What the record establishes.** If it validates, the bytes a build compiles,
the headers it installs, the oracle sources the fixtures were transcribed from
and the licence terms this package ships are exactly the bytes it pins, and any
later edit to one of those 38 files fails the check loudly. For `ryu/ryu.h` the
pinned bytes are this fork's patched ones rather than upstream's, which is why
the record carries both digests for that path and why the pinned-commit diff
checks that deviation on its own.

**What it does not establish.** It is not a signature, not a Git object id, and
not a re-derivation from commit `4c0618b0e44f7ef027ebae05d2cc7812048f7c8f`: it
is a hash of **this working tree**. That the tree differs from that commit in
exactly two paths is established elsewhere, and neither leg of that has been run
in this workspace — by the pinned-commit diff in `.github/workflows/verify.yml`
(every path the pinned commit tracks must be byte-identical to it, with two
named exceptions: `.gitignore`, which may only gain lines, and `ryu/ryu.h`,
which must revert to upstream's bytes when `#include <inttypes.h>` is put back)
and, on a fresh machine, by the archive digest above. The two are complementary
and neither substitutes for the other: this record fails if a hashed byte moves
here whatever a commit says, and the commit diff fails if a third upstream path
differs from the commit whatever this record says.

**Packaging note.** `UPSTREAM.sha256` is a new file at the package root and is
listed in `build.zig.zon` `.paths` beside every other fork record, so a
dependent who fetches the package receives it and the check above is replayable
in an unpacked package.

**Replay status.** The command has been run against this tree and reports 38
records and no failures
(`local://foundation-expansion-ryu-immutable-source-integrity-126.log`), and
`verify.yml` replays it as the first step of its native job, before any build
(`.github/workflows/verify.yml:77-81`). The gate table for this package is
`README.zig.md` § "Verification status"; `CHANGELOG.md` entries 14–18 and
`FORK-NOTES.md` notes 11–13 carry the rest of this wave.

## Divergence policy

Exactly two upstream-tracked files are edited, and each edit is bounded:

* `.gitignore`, additively, so the fork's own `.zig-cache/` and `zig-out/` stay
  out of commits and out of the package. Two lines are appended; no line
  upstream wrote there changes or goes away.
* `ryu/ryu.h`, by the one include at line 24 described under "Import
  mechanism": `#include <inttypes.h>` upstream, `#include <stdint.h>` here. It
  is a portability fix with an observed cause, and it moves no declaration,
  type, signature, constant or algorithm.

Nothing else upstream is edited, moved, reformatted or deleted — not a source
file, not another header, not a test, not a licence text, not a fixture, and
not upstream's CI. The mechanism that enforces this is `verify.yml`'s
licence-and-provenance job: it diffs every path the pinned commit tracks against
that commit and fails on any path other than those two, then fixes the shape of
each in a step of its own. `.gitignore` may only gain lines. `ryu/ryu.h` must
hash to this tree's recorded digest and must hash to upstream's recorded digest
once that one include is put back, so a header edited anywhere else, or edited
by one line more, fails twice over.

## Synchronising with a new upstream release

1. `git fetch upstream`, check out the new commit, and re-read the licence grant
   in `README.md` — it is a prose paragraph, not a machine-readable marker, and
   it is the only place the Boost alternative is granted.
2. Replace `ryu/`, `src/`, `scripts/`, `third_party/`, `lean/` and the root
   build files wholesale from the new commit. Do not hand-patch upstream files
   to make a build problem go away. The one patch this fork carries is the
   include line in "Divergence policy"; a rebase re-derives it from that record
   or drops it, and never grows a second one.
3. Re-read `CMakeLists.txt` and `ryu/BUILD` and compare them with
   `build.zig`'s `core_sources`, `installed_headers` and `check_targets`. Those
   three lists are the only places this package enumerates upstream's own build,
   and a release is exactly what moves them.
4. Re-read every upstream line number cited in `zig/root.zig`,
   `build.zig`, `tests.zig` and this file. They are load-bearing: they are how a
   claim about upstream's behaviour can be checked at all.
5. Re-transcribe `testdata/` from the new `ryu/tests/*.cc` and refresh
   `UPSTREAM.sha256` over the same 38 paths. Then re-run the fixture row counts
   in `tests.zig` (`132`, `60`, `134`, `134`, `39`, `28`) and update them if
   upstream added or dropped a case.
6. Bump `.version` in `build.zig.zon`, update the pinned commit here, in
   `README.zig.md` and in `verify.yml`, and add one numbered `CHANGELOG.md`
   entry.

## See also

* `NOTICE.md` — attribution, the per-path licence choice, every file this fork
  adds or edits, and the obligations that apply to them.
* `README.zig.md` — how to build, import and call the package, and the observed
  gate state.
* `CHANGELOG.md` — numbered fork-only divergences.
* `FORK-NOTES.md` — the problems met while doing this, in the shape a later wave
  can reuse.
* `UPSTREAM.sha256` — the fingerprint itself, and how to replay it.