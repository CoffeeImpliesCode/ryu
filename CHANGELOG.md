# CHANGELOG — fork-only divergences

Upstream's history lives in its own repository. This file records **only** what
this fork changed relative to ulfjack/ryu at commit
`4c0618b0e44f7ef027ebae05d2cc7812048f7c8f`, and it is written so a re-sync can
replay it. Numbers are stable identifiers; never renumber them.

Statuses are the workspace's: **observed** means the driver ran a gate and the
output is in the named receipt; **pending** means the change has landed and no
gate has looked at it yet; **not run** means no receipt exists at all.

## 1. Added the Zig 0.16 package

`build.zig`, `build.zig.zon`, `translate.h`, `zig/root.zig`, `tests.zig`,
`smoke.zig`, `consumer/`, `.github/workflows/verify.yml`, `UPSTREAM.md`,
`UPSTREAM.sha256`, `NOTICE.md`, `README.zig.md`, `FORK-NOTES.md` and this file
are new. New module: `ryu`. New artifact: `libryu.a`, plus the installed
`ryu/ryu.h`, `ryu/ryu_parse.h` and `translate.h`. `build.zig.zon` declares no
dependencies and nothing is downloaded. This entry touches no upstream byte;
the one upstream byte this fork ever changes is the `#include` line recorded in
entry 23.

**Status.** `observed` for the artifact and the install layout
(`local://foundation-expansion-ryu-final-install-101.log`, exit 0, 6/6 steps;
the four files are present in this tree's `zig-out/`), and again into an
approved prefix outside the repository, where the archive was compiled rather
than reused
(`local://foundation-expansion-ryu-installed-artifact-gruenau8-177.log`).

## 2. Compiled upstream's parsers too, and installed their header

Upstream's CMake library target contains `f2s.c`, `d2s.c` and `d2fixed.c` and
nothing else (`CMakeLists.txt:6-18`), and its install rule publishes only
`ryu/ryu.h` (`CMakeLists.txt:28`). This fork compiles `ryu/s2d.c` and
`ryu/s2f.c` as well and installs `ryu/ryu_parse.h` beside it, because the
string-to-float direction is real published API (`ryu/ryu_parse.h:24-40`) and a
fork that dropped it would not be the same library. The parsers are upstream's
experimental components and the facade names them `experimental` for exactly
the reason upstream's own header states.

**Status.** `observed` — the C library builds with all five units, natively
(entry 1's receipts) and for each of the six cross targets (entry 15).

## 3. Pinned the dialect to `-std=gnu17` and passed nothing else

Upstream's sources are C99-era and compile unchanged under `gnu17`. Pinning it
means a future compiler default cannot silently change how these bytes are
parsed.

Nothing else is passed, and that is a finding rather than an omission: the core
converts a `double` by copying its bits (`ryu/common.h:108-112`,
`double_to_bits`) and then works in integer arithmetic on `uint64_t` and
`__uint128_t`, so no result depends on how the compiler rounds, contracts or
reassociates floating-point arithmetic. `-ffp-contract=off` and its relatives
would guard a risk this code does not have.

**Status.** `observed` on the native target and on all six cross targets, every
one of those receipts from before entry 23's one-line header change. Never
applied to a `-Dgeneric128` build for a foreign target, because no such build
has been attempted.

## 4. Declared no system-library mode, and said so

**Decision.** There is no `b.systemIntegrationOption` and no system branch. An
installed ryu publishes `ryu/ryu.h` and never publishes `ryu/ryu_parse.h`
(`CMakeLists.txt:28`, `:6-18`), so it cannot supply this package's surface; a
mode that linked it anyway would be translating this tree's headers against an
ABI of unknown age, which compiles and then misbehaves quietly. The rule is
recorded as **not satisfied with a reason**, not as vacuous-in-the-way-a-
header-only-library-is.

**Status.** `source-confirmed` (`build.zig:47-72`, `UPSTREAM.md` § "System-library
mode"). Not applicable, so no gate can be run for it and none is claimed.

## 5. Transcribed upstream's published answers into six fixtures

`testdata/` holds 527 data rows transcribed verbatim from upstream's own gtest
suites, with the source file and line of every row recorded in each fixture's
header. Nothing in them was computed by this fork, and upstream ships no such
files. One upstream case is deliberately not copied: `f2s_test.cc`'s
`#ifndef _WIN32` arm around `7.038531E-26f`, where upstream records an MSVC
*compiler* rounding difference and expects the other answer everywhere else;
Zig parses float literals with its own correctly rounded parser on every target,
so the non-Windows arm is the answer here and the reason is written down in the
fixture header.

**Status.** `observed` for the four fixture-replay tests, which are among the 28
tests that passed in both
`local://foundation-expansion-ryu-final-debug-95.log` and
`local://foundation-expansion-ryu-final-releasesafe-99.log`.

## 6. Added the Zig facade over the translated header

`zig/root.zig` publishes the four formatters, the two experimental parsers, the
capacity bounds and `pub const c` — the complete translation of upstream's two
public headers. It adds the three things a C header cannot express: a length the
compiler checks, a caller-owned output slice instead of a bare `char*`, and an
error returned *before* anything is written when the buffer cannot hold the
answer.

**Allocation: none.** Upstream also publishes `d2s`, `f2s`, `d2fixed` and
`d2exp`, each of which `malloc`s and hands back a pointer the caller must
`free`. This facade calls none of them; it calls the `*_buffered_n` siblings, so
buffers go in and bytes come out and the caller owns every buffer.

**Status.** `observed` — `local://foundation-expansion-ryu-final-smoke-93.log`,
exit 0, every printed answer matched its published expectation and the run ended
`every answer matched`.

## 7. Added `-Dgeneric128` as an off-by-default option

`-Dgeneric128` compiles `ryu/generic_128.c` and installs
`ryu/ryu_generic_128.h`. Upstream builds the same unit as a separate target
tagged `nowindows` (`ryu/BUILD:38-49`) and gates its CMake target on
`__uint128_t` (`CMakeLists.txt:31-52`). No `RYU_*` macro is defined here to
paper over a target that lacks it: the question is asked of the compiler being
used for the target being built. The Zig facade publishes no generic 128-bit
symbol, so this is a C-surface option only, and the default graph — and
therefore the six-target `check` — never depends on it.

**Status.** `observed`, natively. The option builds and installs
(`…-ryu-generic128-proof-116.log`, `…-ryu-generic128-installed-artifact-195.log`,
both exit 0), and its installed header and archive are exercised from a real C
consumer (`…-ryu-generic128-C-surface-corrected-227.log`, exit 0; entries 7 and
18). **Not run for any foreign target** — upstream tags the unit `nowindows`
(`ryu/BUILD:38-49`) — and the six-target `check` never builds it, so no cross
target result may be read as covering it.

## 8. Wrote this fork's own CI and left upstream's alone

`.github/workflows/verify.yml` is new and names only this repository: native
build, install-layout assertion, Debug and ReleaseSafe tests, smoke, a native
compile-only `check`, one `check` job per cross target, the consumer package,
and a licence-and-provenance job that diffs every path the pinned commit tracks
against that commit. Upstream's `.github/workflows/presubmit.yml` is carried
byte-identical and drives Bazel on upstream's runners; nothing here inherits
from it or is retargeted at it.

**Status.** **Not run.** No execution of this repository's CI has produced
anything, and the workflow says so in its own header. Two of its steps — the
installed-header C surface and the six-target `check` jobs — were run by hand in
this workspace and are recorded as entries 15 and 16. Its licence-and-provenance
job reads git history that no run here has touched; the pristine diff it
performs has since been run directly over seven path groups — entry 21, which
also lists what the job still does that the direct diff did not. Entry 23
changed that job's pinned-commit step, which now admits `ryu/ryu.h` as a second
named difference and adds a step that proves the deviation is exactly one line.

## 9. Appended two ignore lines, one of the two upstream edits

`.gitignore` keeps every upstream entry verbatim — `bazel-*`,
`MODULE.bazel.lock`, `/.eclipse-bin/`, `/project`, `/.lake`, `.vscode/`,
`ryu/*.[oa]`, `ryu/tests/*.test` — and gains two appended lines, `.zig-cache/`
and `zig-out/`, each under a comment saying why. Because the file is therefore
not byte-identical to upstream's, it is deliberately absent from
`UPSTREAM.sha256` and is one of the two names `verify.yml`'s pinned-commit step
admits; the other is `ryu/ryu.h`, added by entry 23.

**Status.** `source-confirmed` from the file. The rule that no line was removed
is enforced by `verify.yml`, which has not run.

## 10. Carried the commit in the manifest version string

`build.zig.zon` pins `.version = "2.0.0-dev.4c0618b"`. The pin is a commit on
`master`, not the `v2.0` release tag the delivery record rejects as stale, and a
SemVer build-metadata suffix cannot hold a commit id, so the prefix rides in the
pre-release field. Upstream's own version line is `project(ryu VERSION 2.0)`
(`CMakeLists.txt:2`) and is reported as upstream's, not adopted as this tree's.

**Status.** `observed` — the manifest resolves and the build runs.

## 11. Added the provenance, integrity and documentation set

`UPSTREAM.md` (pin, archive receipt, import, system-mode argument, sync
procedure), `UPSTREAM.sha256` (38 records, 2689837 bytes, `sha256sum -c`
replayable), `NOTICE.md` (per-path licence choice, the six `third_party/`
corpora and their terms, Apache-2.0 obligations, every file this fork adds),
`README.zig.md` (build, import, use, gate state), `FORK-NOTES.md` (the lessons)
and this file.

**Status.** `observed` for the record itself: all 38 digests were re-derived
from the written file and compared against the files they name — no mismatch,
no duplicate, no missing or extra path — and `sha256sum -c UPSTREAM.sha256` has
since been run against this tree and reports all 38 records `OK`
(`local://foundation-expansion-ryu-immutable-source-integrity-126.log`). That
receipt predates entry 17's `translate.h` correction; the current record of the
whole file is entry 19, and 126 is history rather than verification of the
header this package now ships. The other half of the integrity story is now
recorded separately: a **direct** `git diff --exit-code` against the pinned
commit has run (entry 21), which is itself history since entry 23 changed one
upstream header line. The workflow step that replays it has not run and is
not reported as having run.

**Outstanding integration step: closed**, and recorded as its own entry below so
the numbering stays stable. `UPSTREAM.sha256` is now listed in `build.zig.zon`
`.paths` beside every other fork record, and the workflow replays the record
before it builds anything.

## 12. Corrected three of this fork's own expectations, and removed one test

Each of these was this fork's mistake, not a defect in Ryu's conversion, and
each was found by a red gate rather than by review.

* **Fixture specs the decoder could not read.** `d2s_shortest.txt` and
  `f2s_shortest.txt` carry upstream's input specifications verbatim —
  `zero`, `negzero`, `bits <hex>`, `parts <sign> <exponent> <mantissa>`, `lit
  <decimal>` — and the decoder knew only part of that grammar, so the two
  fixture tests failed with `error.UnknownSpec`
  (`local://foundation-expansion-ryu-repaired-debug-26.log`).
* **`0.9999` at precision 3 in scientific form.** The expected string was
  `1.000e+00`; the library produced `9.999e-01` and was right. `0.9999` is
  exactly four significant digits as a binary64, so a scientific precision of 3
  — four significant digits — has nothing to round. The carry case belongs to
  `0.99999`, which is `0.99999000000000004551…` and does round up (same
  receipt).
* **`0.9999` at precision 4 in scientific form.** The expected string was
  `9.9999e-01`; the library produced `9.9990e-01` and was right again. Precision
  4 asks for five significant digits and the value has four, so the fifth is a
  padded zero
  (`local://foundation-expansion-ryu-current-debug-50.log` and
  `local://foundation-expansion-ryu-current-releasesafe-58.log`).
* **Removed.** A test that only compared a returned slice with the buffer it was
  passed — a copy/alias check, which the fixture policy forbids as evidence.

**Status.** `observed`, closed. All three corrections are in the suite that
reported `28/28` in both
`local://foundation-expansion-ryu-final-debug-95.log` and
`local://foundation-expansion-ryu-final-releasesafe-99.log`. The suite is 28
tests and the two red receipts quoted above describe the 29-test suite they were
run against, which is what makes them history rather than current state. Exactly
one test left the suite between those receipts and these two: the copy/alias
check named above (`FORK-NOTES.md` note 7). The capacity-constant test of
`FORK-NOTES.md` note 4 had already been replaced by a property test before
receipt 2 and is not part of the difference. The precision-4 expectation that
survived, `9.9990e-01`, is the correctly rounded expansion of a four-digit value
asked for five significant digits, and it now stands behind two green runs
rather than a debate.

## 13. Fixed the consumer's address-of on a runtime-length slice

`consumer/src/main.zig` passed `&precision_buffer[0..try ryu.fixedCapacity(3)]`
to a `[]u8` parameter. `&` on a slice expression is a `*[]u8`, not a slice, and
the consumer failed to compile
(`local://foundation-expansion-ryu-current-consumer-67.log`, exit 1). The slice
is now passed as a slice, which is also what makes "exactly the documented
bound" true at the call site.

**Status.** `observed`, closed —
`local://foundation-expansion-ryu-consumer-repair-proof-113.log`, exit 0,
ending `every answer matched the published values`. A second compile error in the
same consumer (`cannot @bitCast from 'comptime_float'`, receipt
`…-final-consumer-102.log`) was repaired after that red receipt and before this
one, so both repairs stand behind the same green run.

## 14. Made the integrity record part of the package and of CI

Two integration steps that earlier drafts of this file listed as outstanding are
now closed. `"UPSTREAM.sha256"` is listed in `build.zig.zon` `.paths` beside
every other fork record, so a dependent who fetches the package receives the
fingerprint and the check is replayable in an unpacked package; and
`.github/workflows/verify.yml` runs `sha256sum -c UPSTREAM.sha256` as the first
step of its native job, before anything is built (`.github/workflows/verify.yml:77-81`).

**Status.** `observed` for the record — the command reports 38 records and no
failures (`local://foundation-expansion-ryu-immutable-source-integrity-126.log`,
exit 0, superseded for the current tree by entry 19); `source-confirmed` for the
manifest line and the workflow step, read out of the current files. The
workflow's pristine-commit diff is still unrun; a direct `git diff --exit-code`
against the pinned commit is recorded at entry 21.

## 15. Ran the six cross-target `check` compiles

`zig build check -Dtarget=<triple>` was run once per required target, each with
its own `--cache-dir`. Each compiles the C core, the translated header,
`tests.zig` and `smoke.zig` and runs nothing.

| Target | Exit | Receipt |
|---|---|---|
| `x86_64-linux-gnu` | 0, 6/6 steps | `…-ryu-matrix-x86_64-linux-gnu-134.log` |
| `aarch64-linux-gnu` | 0, 6/6 steps | `…-ryu-matrix-aarch64-linux-gnu-135.log` |
| `aarch64-macos-none` | 0, 6/6 steps | `…-ryu-matrix-aarch64-macos-none-138.log` |
| `x86_64-windows-gnu` | 0, 6/6 steps | `…-ryu-matrix-x86_64-windows-gnu-141.log` |
| `riscv64-linux-gnu` | 0, 6/6 steps | `…-ryu-matrix-riscv64-linux-gnu-144.log` |
| `wasm32-wasi` | 0, 6/6 steps | `…-ryu-matrix-wasm32-wasi-147.log` |

Every `…-ryu-` prefix above is `local://foundation-expansion-ryu`.

These six are the **default five-unit graph**. `-Dgeneric128` is not in it, no
cross target has ever compiled the optional sixth unit, and a compile-only pass
for a foreign target is compile evidence and nothing more — no foreign binary
was executed.

**Status.** `observed` — all six exit 0, one receipt each, and all six were
re-run on the patched header by entry 24's baseline round, six for six at 6/6
steps. Entry 23's corrected matrix run compiled all six triples on the patched
header and executed three of them; the other three have no runner on this host.

## 16. Proved the installed C surface from outside the build graph

The installed tree was built into an approved prefix outside the repository, and
a C program compiled with `zig cc` against it included `<ryu/ryu.h>` and
`<ryu/ryu_parse.h>` directly and ran. It calls upstream's `malloc`-returning
`d2s`, `f2s`, `d2fixed` and `d2exp` and frees every result, both parser widths
in both their `_n` and their `strlen` forms, the published roundings
(`0.125 → 0.12`, `0.375 → 0.38`, `2.5 → 2`, `3.5 → 4`), and three refused inputs,
each of which leaves the caller's sentinel value untouched. That is the honest
ownership story for both halves of the API: the C functions allocate and the
caller frees, while the Zig facade allocates nothing and writes into the buffer
it was handed.

**Status.** `observed`, exit 0
(`local://foundation-expansion-ryu-installed-C-surface-isolated-cache-191.log`),
ending `the installed ryu headers and libryu.a agree on every value above`. The
first attempt at this gate was red for two unrelated reasons, neither of them the
library; `FORK-NOTES.md` note 12 has both.

## 17. Fixed a nested comment in this fork's own `translate.h`

`translate.h` quoted the include spelling as `ryu/*.h` inside a `/* … */`
comment. The `*/` inside that literal closed the comment early and opened
another one, so a C consumer of the installed header compiled it with
`translate.h:14:61: warning: '/*' within block comment [-Wcomment]`
(`local://foundation-expansion-ryu-installed-C-surface-182.log`). The spelling is
now written `ryu/<name>.h`, which contains no `*` immediately followed by `/`, so
the installed header is warning-free. No upstream byte is involved: this is a
new file this fork added, and `translate.h` is one of the 38 records in
`UPSTREAM.sha256` precisely because it is fork-authored and therefore this fork's
to fix.

**Status.** `observed` — the re-install is exit 0
(`local://foundation-expansion-ryu-installed-headers-comment-corrected-186.log`)
and the surface compiled from it is green (entry 16).

## 18. Withdrew a wrong `explicitLeadingBit` argument from the 128-bit C gate

The `-Dgeneric128` C gate has to describe the layout it hands
`generic_binary_to_decimal`. It described IEEE binary128 with
`explicitLeadingBit = true`, and binary128's leading bit is implicit, so the
converter read the stored fraction as the whole mantissa and the first run failed
with `binary128 1.25: got "5E-1"` and `binary128 -1.25: got "-5E-1"`
(`local://foundation-expansion-ryu-generic128-C-surface-before-correction-208.log`,
exit 1). Upstream's own code is the authority and is unambiguous:
`float_to_fd128` and `double_to_fd128` pass `false` (`ryu/generic_128.c:55`,
`:64`) and only `long_double_to_fd128` passes `true` (`:80`), because the x87
80-bit layout keeps that bit in the significand.

The argument is now `false` and nothing else changed: the bit patterns were
already right — `16383 << 112 | 1 << 110` for `1.25`, and the same value with
bit 127 set for `-1.25` — as were the expected strings and the buffer. No
upstream byte was touched, and no algorithm changed. `FORK-NOTES.md` note 11 has
the lesson, including why the `long double` row is stated for the native x86_64
machine and for no other platform.

**Status.** `observed` — the corrected gate exits 0
(`local://foundation-expansion-ryu-generic128-C-surface-corrected-227.log`):
`float`, `double` and `long double` `1.25` all print `1.25E0`, both binary128
rows print `1.25E0` and `-1.25E0`, and both signed zeroes print `0E0` and `-0E0`.

The comment correction in entry 17 changed fork-authored `translate.h`.
`UPSTREAM.sha256` now hashes its current bytes; the driver replayed all 38
records successfully in
`local://foundation-expansion-ryu-corrected-header-current-integrity-287.log`.
The earlier receipt 126 remains history, not verification of this changed
header — and so does 287, since entry 23 re-derived the record again for the
one upstream header line this fork changes.

`NOTICE.md` and `README.zig.md` no longer offer Apache-2.0 for fork-authored
files. No owner authorised that grant. Their licence is unassigned; the carried
upstream Apache-2.0 and Boost grants and their obligations are unchanged.

## 20. Fetched this package and consumed the materialised copy

`zig fetch` was run over this package's absolute path from a separate scratch
build root outside this repository, that root carrying its own `build.zig` and
`build.zig.zon`, with `--global-cache-dir` pointing at the driver's own package
cache. It exits 0 and prints the package identity:

```
ryu-2.0.0-dev.4c0618b-R0zYELvxcAFVJPiXdq8VFwYeo8snAY1LtpoTMccR3abs
```

What it copied is the manifest-filtered package — exactly what `build.zig.zon`
`.paths` names, and nothing else from this tree. Two gates then ran against
that copy rather than against this working tree.

* **`sha256sum -c UPSTREAM.sha256` inside the materialised package** — exit 0,
  all 38 records `OK`, `translate.h` included, so the refreshed own-header
  digest of entry 19 is verified on the bytes a dependent receives and not only
  in this checkout. This is the `.paths` closure claim, and entry 11's in-tree
  run cannot make it: a checkout can hold a file the manifest does not list, so
  the record has to be checked where a dependent keeps it.
* **`consumer/` built and run from inside the materialised copy** — exit 0,
  with its own `--cache-dir` so nothing was reused from this tree's build
  outputs. The consumer's relative `.path` dependency resolved against a
  package this repository's build graph never produced, so the boundary
  crossed here is the one a dependent crosses. The receipt ends
  `every answer matched the published values`, including the fixed-point write
  into a buffer of exactly `fixedCapacity(3)` bytes.

The materialised consumer built the **default five-unit graph**. Nothing in
this entry adds a `-Dgeneric128` claim for the fetched copy or for any foreign
target: entries 7 and 18 and the `-Dgeneric128` rows in `README.zig.md`,
including its `NOT RUN` cross-target row, are unchanged.

Nothing in this entry is a publication claim. The fetch is over a local
absolute path: no URL, registry, git remote or published hash was resolved, no
publication has been authorised, and the identity string above is what this
compiler printed for this directory — not a hash a downstream can fetch today.

**The earlier failure is kept as history.** Run from the package source root,
the same absolute path failed with
`error: unable to copy directory '/vol/fob-vol7/mi19/gertullj/foundation-libs/ryu': IllegalFileTypeInPackage`
(`…-ryu-materialized-package-fetch-263.log`, exit 1). No byte of this tree
changed between the two runs; the working directory did. Which of those
differences made the difference is not established here, and nothing is
generalised from it to any other tree, host or filesystem.

**Status.** `observed` — the fetch
(`local://foundation-expansion-ryu-external-driver-package-fetch-327.log`, exit
0, identity recorded verbatim), the in-package integrity run
(`…-ryu-materialized-package-integrity-336.log`, exit 0) and the in-package
consumer (`…-ryu-materialized-package-consumer-343.log`, exit 0). **All three
are history as of entry 23**: the identity `zig fetch` prints is a function of
the package bytes, and those bytes have since moved. A fresh package round runs
once the documentation settles; no current package identity or in-package
digest is asserted until it does.

## 21. Ran the pristine-commit diff directly, and left the CI job unrun

The diff the workflow's `licence-and-provenance` job performs was run by hand
over this fork's carried source trees and both licence texts:

```
git diff --exit-code 4c0618b0e44f7ef027ebae05d2cc7812048f7c8f -- \
    ryu src third_party scripts lean LICENSE-Apache2 LICENSE-Boost
```

It exits 0 with empty output: every path that command names is byte-identical
to the pinned commit in this working tree. It is read-only — it changed nothing,
and no fixture, no upstream byte and no expected value was touched to obtain
it. **That was true of the tree as it stood then**; entry 23 changed
`ryu/ryu.h` afterwards, so on the current tree the same command reports that
one path.

**This is not the job, and it does not stand in for it.** The job compares
*every* path the pinned commit tracks and admits exactly two differing ones —
`.gitignore` (this entry) and `ryu/ryu.h` (entry 23) — checks that the pinned
commit is an ancestor of `HEAD`, checks that the fork records are present and
non-empty, greps both licence texts for their own titles, and holds
`ryu/ryu.h` to its recorded patched and pristine digests and to the one-line
shape of the difference (`.github/workflows/verify.yml:565-575`, `:615-649`).
Among the upstream paths the job covers and this direct diff does not are
`CMakeLists.txt`, `README.md`, `CONTRIBUTORS`, `MODULE.bazel`, `.bazelrc`,
`.bazelversion`, `.classpath`, `lean-toolchain` and
`run_benchmark_linux.sh`.

**The job itself has still never been executed**: no run of this repository's
CI has produced anything, `.gitignore`'s add-only rule is still enforced by
nothing here, and this entry does not change that. A green hand-run diff is not
a green job.

**Status.** `observed` for the direct diff
(`local://foundation-expansion-ryu-pinned-native-pristine-diff-270.log`, exit 0,
empty output) — as history, because entry 23 changed `ryu/ryu.h` after that
run. `not run` for the `licence-and-provenance` job, as it was before.

---

## 22. Gave the package a full-matrix `cross-test` gate, and checked the core against 32-bit and big-endian targets

**Condition.** Every cross-target gate so far is `zig build check`, which
compiles and runs nothing, and its six targets are all 64-bit apart from
`wasm32-wasi`. The gate that executes `tests.zig` per platform had no
configuration in this package at all, and the platforms it names include rows
the six-target list never reaches — `x86-linux`, `thumbeb-linux`,
`riscv32-linux`, `hexagon-linux` on one side, `aarch64_be-linux`,
`s390x-linux`, `powerpc-linux` on the other. Every one of those is 32-bit or
big-endian, and upstream's core is integer arithmetic on `uint64_t` and
`__uint128_t`, which is exactly the property a 32-bit target puts in question.

**Change.** `cross-test.profile.sh` is new and is listed in
`build.zig.zon` `.paths`. It is settings only, and deliberately almost empty:
`CROSS_BUILD_STEP=test` and `CROSS_BUILD_TIMEOUT=900`, both the harness's own
defaults written out so the gate is readable without reading the harness. It
sets no `CROSS_MATRIX` and no `TARGETS`, so the matrix is the whole published
Zig 0.16.0 Tier 1/2 table; it passes no `-Doption` at all — no `-Dtarget`, no
`-Doptimize`, and **no `-Dgeneric128`**, which keeps every platform on the same
default closure of upstream's five primary C units; it names no compiler, cache
or output path; it defines no `cross_build_command` or `cross_artifact`, so the
harness stays in its standard `zig build test` mode over this package's own
graph; and it does not set `CROSS_REQUIRE_RUNNERS=1`, because a platform with no
runner on the host is already recorded as explicit `build_only` coverage and
demanding a runner would report a missing runtime as a broken target.

`build.zig` needed no functional change to serve it. `build()` resolves
`-Dtarget` into the same graph the host build uses, and the `test` step calls
`b.addRunArtifact` on that graph unconditionally, which is what the harness
needs in order to decide per target between running the binary, prefixing an
emulator, and skipping the run while keeping the compile dependencies. Only the
module doc comment changed.

**What was checked, and what it found — `SOURCE-CONFIRMED`, see `FORK-NOTES.md`
§ 14.** `__uint128_t` is guarded everywhere upstream uses it
(`ryu/d2s_intrinsics.h:28-36`, and the three-way
`HAS_UINT128` / `HAS_64_BIT_INTRINSICS` / `#else` guards at `:257` onward and
`ryu/d2fixed.c:50-193`), and every guard's fallback is complete 32×32→64
arithmetic rather than a stub. `RYU_32_BIT_PLATFORM` (`ryu/common.h:24-25`) is
defined only for `_M_IX86` and `_M_ARM`, so a clang 32-bit target does not get
it; what that changes is which division helper is used, not any result.
`float_to_bits` and `double_to_bits` go through `memcpy`
(`ryu/common.h:99-105`), so nothing depends on byte order. `-Dgeneric128` stays
out of the default closure, as it always has, and the file that ships is
upstream's unmodified `ryu/generic_128.c` — no stub was substituted for it.

**What did not change.** No upstream C source, header, table, test, licence or
fixture byte is touched **by this entry**, and `UPSTREAM.sha256` still describes
the same 38 records; entry 23 is the one line that does change an upstream byte,
and it names itself, its digests and every record that has to change with it.
The six-target `check` matrix is exactly as it was. `tests.zig` still holds the
same 28 behavioural tests; none was added, removed or re-pinned, because nothing
observable changed and a declaration or wiring test would not be one. Open item
4 in `FORK-NOTES.md` § "What is still open" is unchanged: `-Dgeneric128` still
has no foreign compile. The profile carries no licence grant of its own and is
recorded in `NOTICE.md` among the fork-authored files.

**Status: `observed` for the pre-deviation tree, and the finding is what entry 23
answers.** The run happened: exit 1 over all 53 cells, **20 pass, 9 fail, 24
`build_only`, 0 partial**, and every one of the nine failures is the same NetBSD
`<inttypes.h>` translation failure (`local://foundation-cross-test-evidence.json`,
`checks[]` entry `library: ryu`, `stage: matrix`; per-cell logs
`local://foundation-cross-test-matrix-ryu-<target>.log`). It is also the first
gate in this package's history to compile any of the 32-bit or big-endian cells
the six-target list never reached — `x86-linux`, `thumbeb-linux`,
`riscv32-linux`, `hexagon-linux`, `aarch64_be-linux`, `s390x-linux`,
`powerpc-linux` among them — and the native cell ran the full 28-test suite.
The profile itself was checked first: `bash -n cross-test.profile.sh` exit 0 and
`cross-test --list` exit 0 naming all 53 targets, with `--no-profile --list`
naming the same 53 (`local://foundation-cross-test-profile-verification.json`).
The corrected run over the patched header closed those nine cells: see entry 23.

---

## 23. Changed one `#include` line in `ryu/ryu.h`, and disclosed it in every record

**Condition.** Entry 22's gate translates the aggregate header for each of the 53
cells, and `translate.h` includes `ryu/ryu.h`, which at commit
`4c0618b0e44f7ef027ebae05d2cc7812048f7c8f` reads `#include <inttypes.h>` at
line 24.

**Symptom.** Nine cells failed — the whole NetBSD side of the table — each with
one translation failure, while the other 44 cells were unaffected:

```
error: translation failure
…/lib/libc/include/generic-netbsd/inttypes.h:93:1: error: unknown type name 'pragma'
…/lib/libc/include/generic-netbsd/inttypes.h:93:1: error: expected ';', found 'an identifier'
…
error: 5 compilation errors
```

**Cause.** NetBSD's `<inttypes.h>` closes its declarations with `__END_DECLS`,
whose replacement list begins with a `_Pragma`, and the pinned translator reads
that `_Pragma` as ordinary tokens. That header is the SDK's, not Ryu's, so the
failure is a portability limit of the target's libc headers rather than a defect
in the library or in this fork's own code.

**Change.** One line: `ryu/ryu.h:24` now reads `#include <stdint.h>`. That
include exists for exactly one name, `uint32_t`, used in the six `precision`
parameters at `ryu/ryu.h:34-40`. No `PRI*` or `SCN*` macro appears anywhere in
the header, and `uint32_t` is declared by `<stdint.h>` (C99 7.18.1) — the header
`<inttypes.h>` includes in order to reach that same type. No declaration, type,
signature, constant, prototype or algorithm changes, and no prototype is copied
or duplicated anywhere: the header still declares each function exactly once,
inside its own `extern "C"` block. Upstream's bytes for this path are 1360 bytes
hashing to `b7feab0ba1df5e9ef3d602f386592ad152491405e49b408fb21c0e0e9e6bfb16`;
the earlier include-only file was 1358 bytes hashing to
`c8985bae57bd8d00306a8e03a4f0a406539e5ba5d7f7df4e0a41c6ab0e058654`, before
the inline notice made it 1417 bytes with current digest in `UPSTREAM.sha256`.

**Bounded to the translation closure.** Three of the five compiled units include
this header — `ryu/d2s.c:30`, `ryu/f2s.c:21`, `ryu/d2fixed.c:26`. The two
parsers include `ryu/ryu_parse.h` instead (`ryu/s2d.c:18`, `ryu/s2f.c:18`),
which declares no integer type at all, and each already includes `<stdint.h>`
itself (`ryu/s2d.c:22`, `ryu/s2f.c:22`); their own `<inttypes.h>` blocks sit
inside `#ifdef RYU_DEBUG`, and this build defines no `RYU_DEBUG`. The compiled
ABI is therefore upstream's own on every target.

**No workaround ships with it.** `build.zig` still builds one graph from one
root header for every target and defines no `RYU_*` macro and no per-target
conditional (`build.zig:244-263`); this tree adds no stand-in for
`<inttypes.h>` or for any other libc header, and it drops nothing upstream
published. A per-target workaround was rejected rather than shipped, so the
record above is the whole change.

**Consequences for the other records.** `UPSTREAM.sha256` hashes `ryu/ryu.h` at
its patched digest and keeps upstream's beside it (`UPSTREAM.sha256:112-114`,
with the baseline also at `:49`). The pristine-diff claims of entries 11, 20 and 21 are historical
rather than current: that diff was clean before this change, and run over `ryu`
now it reports this one path by design. `.github/workflows/verify.yml`'s
licence-and-provenance job was updated with it: its pinned-commit step now
admits `ryu/ryu.h` as the second named difference after `.gitignore`, and a
following step proves that the file is upstream's recorded pristine bytes with
exactly the `<inttypes.h>` include put back
(`.github/workflows/verify.yml:565-575`, `:615-649`) — so the admission is a
shape check, not permission to rewrite the file. The job itself remains `not
run`. `NOTICE.md` records the altered file, and `README.zig.md` § "Deviations
from upstream" states it for a reader.

**Status.** `observed` natively on the patched header:
`build test smoke install -Doptimize=Debug` exit 0, `11/11 steps succeeded`,
28/28, ending `every answer matched`
(`local://foundation-cross-test-ryu-native-Debug.log`, re-run by entry 24);
`build test smoke
-Doptimize=ReleaseSafe` exit 0, `9/9 steps succeeded`, 28/28
(`…-ryu-native-ReleaseSafe.log`, re-run by entry 24); `build run` in
`consumer/` exit 0, ending
`every answer matched the published values` (`…-ryu-native-consumer.log`,
re-run by entry 24). The
same suite is still 28 tests; nothing was added, removed or re-pinned.
**observed** on the full matrix as well: the corrected run exits 0 over all 53
cells with **20 pass, 0 fail, 33 `build_only`, 0 partial** (harness `run_id`
`20261002-053059-41494-21055`,
`local://foundation-cross-test-corrected-ryu.json`, with 53 per-cell logs beside
it as `local://foundation-cross-test-corrected-ryu-<target>.log`). Every cell
compiles, the 20 cells with a runner each ran the whole 28-test suite — 560
executed tests — and the nine NetBSD cells are among the 33 `build_only`, which
is compile coverage on a host with no NetBSD runtime and not a test pass.
**PENDING-VERIFICATION** for what that run cannot restore: `sha256sum -c
UPSTREAM.sha256` against the re-derived record has not been replayed since the
record moved, and the in-package integrity and consumer rows of entry 20 have
to be re-made, because the package bytes have moved since that fetch. The
six-target `check` rows are no longer in that list: entry 24 re-ran all six
triples on the patched header, six for six at 6/6 steps.

The `-Dgeneric128` native receipts of entries 7 and 18 are pre-deviation too;
the optional sixth unit includes `ryu/ryu_generic_128.h` and not `ryu/ryu.h`,
so nothing here predicts its behaviour on the patched header, and no
`-Dgeneric128` run against that header is recorded.

---

## 24. Re-ran the native and six-target gates on the patched header

Two rounds of this package's own gates ran after entry 23 and both are green, so
entry 23's `observed` state is not resting on a single run.

**The stable native round.** The same three commands entry 23 recorded, run
again on the same patched tree with their own cache directories and a `--prefix`
outside this repository:

| Command | Exit | Result | Receipt |
|---|---|---|---|
| `build test smoke install -Doptimize=Debug` | 0 | `11/11 steps succeeded; 28/28 tests passed`, `every answer matched` | `local://foundation-cross-test-stable-ryu-native-Debug.log` |
| `build test smoke -Doptimize=ReleaseSafe` | 0 | `9/9 steps succeeded; 28/28 tests passed`, `every answer matched` | `local://foundation-cross-test-stable-ryu-native-ReleaseSafe.log` |
| `build run` in `consumer/` | 0 | `6/6 steps succeeded`, `every answer matched the published values` | `local://foundation-cross-test-stable-ryu-native-consumer.log` |

`FORK-NOTES.md` § 0 records these as receipts 35–37, beside the entry 23 runs
they repeat (receipts 29–31). Both sets report the same 28 tests in both
optimize modes; no test was added, removed or re-pinned between them.

**The six-target baseline round.** `zig build check -Dtarget=<triple>
-Doptimize=Debug -j8 --summary all --color off` was run once per triple over the
same six targets as entry 15, each with its own `--cache-dir` and its own
`--prefix`, both outside this repository, inside a workspace-wide round taken
over every SDK in this tree by `baseline-regression.py`:

| Target | Exit | Receipt |
|---|---|---|
| `x86_64-linux-gnu` | 0, 6/6 steps | `local://foundation-cross-test-baseline-ryu-x86_64-linux-gnu.log` |
| `aarch64-linux-gnu` | 0, 6/6 steps | `…-ryu-aarch64-linux-gnu.log` |
| `aarch64-macos-none` | 0, 6/6 steps | `…-ryu-aarch64-macos-none.log` |
| `x86_64-windows-gnu` | 0, 6/6 steps | `…-ryu-x86_64-windows-gnu.log` |
| `riscv64-linux-gnu` | 0, 6/6 steps | `…-ryu-riscv64-linux-gnu.log` |
| `wasm32-wasi` | 0, 6/6 steps | `…-ryu-wasm32-wasi.log` |

The aggregate is `local://foundation-cross-test-baseline-before-sdk-corrections.json`
(`cells[]`, `sdk: ryu`); `FORK-NOTES.md` § 0 records it as receipt 38. `check`
compiles and runs nothing, so this is compile evidence on the patched header for
all six, exactly like the entry 15 rows it repeats — not a foreign test result.
Of the six, entry 23's corrected matrix run executed three
(`x86_64-linux`, `aarch64-linux`, `riscv64-linux`); `aarch64-macos`,
`x86_64-windows` and `wasm32-wasi` have no runner on this host and are recorded
`build_only` there.

**What this entry does not claim.** The `sha256sum -c UPSTREAM.sha256` replay
against the re-derived record and the fresh materialised-package round of entry
20 are still outstanding, exactly as entry 23 left them; no foreign BSD, Darwin,
Windows or WASI runner exists on this host, so `build_only` rows stay compile
coverage. `zig build check -Dgeneric128=true` has still never been run for any
target, and this repository's own `.github/workflows/verify.yml` has still never
been executed. No byte of `ryu/`, `src/`, `third_party/`, the licence texts or
the fixtures was touched by either round, and no upstream byte was restored to
make a gate pass.

---

## 25. Kept the native change notice in the changed line

`ryu/ryu.h:24` now carries a prominent Foundation-fork change notice beside
the already-disclosed `<stdint.h>` include. It is still one changed line;
no copyright, grant, declaration, algorithm or line number moves. The
1417-byte header hashes to
`83ed2a4cd2e42cdd351383b5c937e320e47d8e0ea214964a7b8568f974754dae`.
Executing the workflow's exact one-line reversal reconstructs upstream's
1360 bytes and
`b7feab0ba1df5e9ef3d602f386592ad152491405e49b408fb21c0e0e9e6bfb16`.

The aggregate's comment now correctly names **three** compiled users of
`ryu/ryu.h`, not five; the parsers include `ryu_parse.h`. Group B and Group F
digests were re-derived, with the same 38 paths now totalling 2689946 bytes.

Fresh native commands are observed green: Debug `test smoke install`
11/11 steps and 28/28, ReleaseSafe `test smoke` 9/9 and 28/28, and the source
consumer 6/6, all exit 0. Receipts:
`local://foundation-cross-test-final-ryu-native-Debug.log`,
`local://foundation-cross-test-final-ryu-native-ReleaseSafe.log`, and
`local://foundation-cross-test-final-ryu-native-consumer.log`.
The newest explicit-target baseline is also 6/6, each 6/6 steps, in
`local://foundation-cross-test-final-baseline.json`.

Final matrix and materialised-package results belong to the workspace
ledger's `cross_test_wave`; final identities are deliberately outside these
package-local documents. Older receipts remain historical, and no new
generic128, system-mode, CI or publication result is claimed.

## 26. Corrected provenance and retained per-file licence descriptions

Current header size/digest now agree everywhere: 1417 bytes and
`83ed2a4cd2e42cdd351383b5c937e320e47d8e0ea214964a7b8568f974754dae`.
The six `uint32_t precision` declarations and source quotation/output ranges
are cited accurately. Native declarations and algorithms do not change.

The retained Mersenne data's GFDL/CC alternative is separated from Apache
`random.h` and the Java generator. Jaffer's permission notice and Yuan's
Apache text are both recorded. Apache §3 terminates the recipient's patent
licences on that recipient's specified litigation filing, not on a
Contributor's suit. All upstream notice/licence bytes remain unchanged.

Code-file edits are only comment/citation text, with source-line count and
noncomment bytes unchanged. Fresh affected native commands and the final
38-record source/fetched package closure belong to the external root ledger.

The fresh replay found the fork-authored `translate.h` record still naming its
pre-correction comment bytes. That record now names
`049973a764b4359234bb05087dbea5504deabdb10bd36f27b06f088da22c3ea3`;
the 38 paths, native-header record, declarations and noncomment bytes remain
unchanged. The failed 37/38 replay is retained as history, not claimed green.
