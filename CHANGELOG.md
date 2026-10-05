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

**Status.** `source-confirmed` (the section `build.zig` heads "Why there is no
`b.systemIntegrationOption`", `UPSTREAM.md` § "System-library mode"). Not
applicable, so no gate can be run for it and none is claimed.

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

**Test-policy amendment — PENDING-VERIFICATION.** Removed the entire owned-string
allocator loop: it asserted only nonempty lengths and an iteration count, not
allocator ownership. Existing known-answer, round-trip, error and ownership
tests remain unchanged; no literals were re-pinned. No API, native or allocator
code changed. The driver must run the final SDK tests and smoke. No current test
total is claimed here or in `README.md` § 3b: every count in these documents is
the number a named run printed, and the next one is the driver's.

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
conditional (`build.zig:295-297`); this tree adds no stand-in for
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

## 27. Zig API contract alignment — 2026-10-03

**Condition.** Precision is `u32`, but both precision writers accumulate and
return a signed C `int` byte count. A `usize` capacity alone is not that bound.

**Fix.** Accumulate capacities in `u64`, check the native signed-length limit,
then check `usize`. Return `PrecisionTooLarge` before buffer checks or writes:
fixed precision is at most 2147483336 and scientific precision at most
2147483639. Scientific capacity is also at least ten bytes for the longest
source-defined special spelling. Keep allocation, caller-buffer borrows,
partial-work failures and raw/linkage routes explicit.

**Verification and bound.** Zig 0.16.0, native Linux x86-64: install,
tests in all four modes, smoke, package consumer and module example pass.
The compile-only `check` matrix passes. Separate four-mode consumers check
accepted/rejected signed-length boundaries without huge allocations, untouched
output on refusal, negative infinity and rounding carry. The `_MSC_VER`
ten-byte spelling is source-confirmed, not exercised on this host.
Native writer, header and generated bytes are unchanged.

---

## 28. Replaced `README.md` and preserved upstream's README

`README.md` in this repository was upstream's README, byte for byte: 343 lines,
`20572708ea26d19fd596f1c4a44097dbcb491cdf0517024d68bbb5d622d0ac93`. It is now
this fork's README, and **upstream's bytes are preserved, not discarded**, at
`README.upstream.md`, which carries that exact digest. The relocation moves a
path and not a byte.

The new `README.md` is in the canonical order: current native-source deviations;
current native-build deviations with a dated history link; the current
build/run/test matrix; consumption. The Zig interface keeps its own document,
`README.zig.md`, and the new README points at it instead of duplicating it.

**Consequence one, and it is the reason this is not a rename.** `README.md` is
now a **third** upstream-tracked path that differs from the pinned commit, beside
`ryu/ryu.h` and `.gitignore`. Every pinned-commit diff has to name all three.
`UPSTREAM.md` ("Import mechanism", "Divergence policy") and `NOTICE.md` name
them; the workflow's own exception list is build-role work and is listed in this
wave's hand-off.

**Consequence two, and it is the one that could silently rot.** This repository
cited upstream's README prose in eleven places across five files, always as
`README.md:NN`. Left alone, every one of them would now point at fork prose with
an upstream line number. All eleven were renamed to `README.upstream.md:NN` with
the line numbers unchanged: `translate.h:23`, `.github/workflows/verify.yml:537`
and `build.zig.zon:75` are build/CI-role files and are in the hand-off; this
role's own files — `UPSTREAM.md`, `NOTICE.md`, `README.zig.md` — are done.

`UPSTREAM.sha256`'s Group D line moved with the bytes, same digest:
`20572708…  README.upstream.md`. The record still has 38 paths over 2689946
bytes, unchanged, and the file's header now explains the third excluded
upstream-tracked path rather than claiming the record is complete over a tree
whose `README.md` no longer hashes.

**Status.** The relocation and the citation renames are `SOURCE-CONFIRMED` in
this working copy. One thing was observed: `sha256sum -c UPSTREAM.sha256` from
the repository root reports **38 records, 38 `OK`, exit 0**, with
`20572708…  README.upstream.md` passing under its new path. That is an in-checkout
record replay and nothing more — it is not a build, test or matrix gate, and it
does not establish the fetched-copy half of the record's claim. Everything else
here is `PENDING-VERIFICATION`: the filtered fetch, the in-copy replay, the
consumers, and the pinned-commit diff with three named exceptions. No result is
claimed beyond the replay above.

## 29. Granted a licence to this fork's own files — `Apache-2.0`

`FORK-LICENSE.md` is new. The repository owner authorized a per-project licence
for fork-authored additions, matched to the project's primary upstream term;
this project records `Apache-2.0` (SPDX `Apache-2.0`) and points at the
`LICENSE-Apache2` text already shipped, so there is no second copy of the licence
and no restatement of it.

Three things the record is careful about, because each was a way to be wrong:

* **The Boost alternative is retained, not consumed.** Apache-2.0 was chosen for
  the fork's additions because it is this project's primary upstream term
  (`README.upstream.md:35-38`), and because it keeps §3 and §4 attaching to the
  one-file native deviation and to the fork's files at the same time. Nothing
  removes a downstream's choice of Boost-1.0 for the `ryu/` core; that choice
  yields a mixed tree, which is what upstream's own wording produces.
* **No individual is named.** Upstream's authors are Ulf Adams and the three
  people in `CONTRIBUTORS`; none of them wrote these files and none of them is
  credited for them. No personal copyright identity is invented to fill the gap.
* **The tree is not reduced to one label.** `NOTICE.md` keeps its per-path
  inventory and its six `third_party/` works under six sets of terms. One
  partial overlap is called out rather than inferred: the two lines this fork
  appends to upstream's `.gitignore` are fork-authored, and every line upstream
  wrote there is unchanged.

`NOTICE.md`'s earlier record — fork-authored files **unassigned**, with an
earlier Apache-2.0 offer recorded as withdrawn — described the state before this
authorization. It is marked as history in both files and not deleted, because
"the tree never had a stated licence" and "the tree now has one" are different
claims and the transition is part of the record.

**Status.** `PENDING-VERIFICATION`. Documentation only; no build, test or gate
was run for this entry and none is claimed. The SPDX identifier was supplied to
the native role before any fork-authored build file was written.

## 30. Added standalone Nix and devenv packaging

Five new files: `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml` and
`.envrc`. No upstream byte and no native algorithm is touched.

**`package.nix`** is one source-only derivation, `{lib, stdenv, zig, pkg-config,
linkage ? "static", generic128 ? false}`, consumed by both entry points through
`pkgs.callPackage`. It filters this repository's own build output, VCS metadata
and development state out of `src`; fetches nothing, imports no sibling, names no
host path and reads no `builtins.getEnv`. It calls `zig build install --prefix
"$out"` with `-Dcpu=baseline`, one `-Doptimize` and `-Dlinkage`, both Zig caches
under `$TMPDIR`, and `-j "${NIX_BUILD_CORES:-1}"`; then asserts the installed
closure, resolving the graph's `ryu.pc` with `pkg-config` so a partial install
fails the build instead of shipping quietly.

**The build graph owns every installed file** — library, public headers,
`lib/pkgconfig/ryu.pc`, licence record. `package.nix` writes none of them and
restates no C flag, so there is one writer per path and one list of C flags.

**`flake.nix`** exposes `packages.<system>.static` and `.shared` — two calls to
one file, differing only in `linkage` — plus `.default` (this SDK's existing
static policy), and a `devShells.default` carrying tools only. `-Dgeneric128` is
a build-graph option, not a packaging variant, and has no flake attribute. Two
guards cover silent failures: `zig_0_16.version == "0.16.0"`, and
`stdenv.hostPlatform.system == stdenv.buildPlatform.system`, because `zig build`
runs without `-Dtarget` and resolves the host. Native remote builders stay
valid; Nix cross-compilation is refused.

**`devenv.nix`** carries tools only in `packages`, and exposes the same
derivation as lazy `outputs.static`, `outputs.shared` and `outputs.default`, so
`devenv build outputs.static` is the packaging route and nothing is realised on
shell entry. Tasks are namespaced `sdk:*` with real `exec` commands.

All of the Zig setup hook's phases are disabled (`dontConfigure`, `dontBuild`,
`dontCheck`, plus `dontSetZigDefaultFlags` and `dontAddPrefix`), so the hook
cannot build a second time with different flags. Disabling `zigCheckPhase` also
keeps `zig build test` out of the package build: behavioural gates are recorded
with receipts elsewhere, and a derivation that ran them would make an unowned
gate look owned.

Inputs are pinned and locks are not authored here: the flake pins
`github:NixOS/nixpkgs/c7def046b9a883d46974757852106483d741586f` and
`devenv.yaml` pins
`github:cachix/devenv-nixpkgs/c2f38fe7f9e04d9aadd354d380f2bd40531d9737`.
`flake.lock` and `devenv.lock` are the workspace driver's files and are not in
`.paths` either.

**Corrected by entry 33.** `flake.lock` is in this directory, and it pins
`c7def046b9a883d46974757852106483d741586f` — the rev `flake.nix` names above.
There is no `devenv.lock`. The claim that this repository owns no lock was true
when it was written and is not true of the tree now.

**Status.** `PENDING-VERIFICATION` throughout: **no `nix` or `devenv` command
has been run against any of these files**, and the installed closure this entry
describes is `build.zig`'s to produce, not yet produced. `README.md` § 3b and
`UPSTREAM.md` say the same. No closure is claimed to be wholly static: the static
variant is a static `libryu.a` plus a C-runtime dependency, which is the whole of
it.

## 31. Recorded the linkage option and the full header-declared route

`build.zig` hard-coded `.linkage = .static`. The linkage option `-Dlinkage=static
| dynamic` is a build-role edit; this entry records it here because the
documentation states its contract and its default, and because the documentation
must not describe a flag that does not exist.

**Default preserved.** `static`. Upstream's own `add_library` (`CMakeLists.txt:6`)
carries no `SHARED` keyword and so follows `BUILD_SHARED_LIBS`, which CMake
defaults to OFF — the Zig package's static default and upstream's CMake default
agree, so nothing about a default build moved. `-Dgeneric128` is preserved
exactly as it was: a bool option, off by default, installing
`ryu/ryu_generic_128.h`, and never passed by `cross-test`, by `package.nix`, by
`flake.nix`'s default or by the devenv shell.

**The raw route, enumerated.** `translate.h` selects exactly two upstream
headers, `ryu/ryu.h` and `ryu/ryu_parse.h`, and together they declare **sixteen**
functions. The facade calls six of them — `d2s_buffered_n`, `f2s_buffered_n`,
`d2fixed_buffered_n`, `d2exp_buffered_n`, `s2d_n`, `s2f_n` — because it returns
a subslice of a buffer the caller owns. The other ten are part of the native
surface regardless: `d2s`, `f2s`, `d2fixed` and `d2exp` allocate through libc
`malloc` (`ryu/d2s.c:506`, `ryu/f2s.c:342`, `ryu/d2fixed.c:558` and `:815`),
terminate, and return the allocated pointer itself, so the caller frees it with
that runtime's `free` and not with a Zig allocator. A dispatch table that
covered only the allocation-free six would be a narrower library wearing this
one's name, and crossing into libc `malloc`/`free` is a property those four
carry rather than something a route may quietly drop.

`ryu/ryu_generic_128.h` is **not** in that set. `translate.h` excludes it
deliberately, so none of its five functions is translated and no Zig symbol is
generated for them; under `-Dgeneric128` they are reachable from C against the
installed tree and from nowhere else.

**Status.** The flag has since landed: `build.zig:897-912` declares
`-Dlinkage=static|dynamic` with `.static` the default. Neither `-Dlinkage` nor
the shared variant has been built, run or installed. The enumeration above is
`SOURCE-CONFIRMED` from the two headers as they stand; the runtime-loaded route
that would have to carry it does not exist in this repository yet, and no claim
is made about it. Entry 32 covers the landed build graph.

**Superseded in part by entry 33.** The runtime-loaded route named here as
absent exists (`-Druntime=true`, `runtime/`, `ryu.load`), and
`ryu/ryu_generic_128.h` is translated under `-Dgeneric128` rather than
reachable only from an installed C tree. Nothing else in this entry moves: the
sixteen-function enumeration of the default closure and the four `malloc`ing
entry points are exactly as recorded above.

---

## 32. Native delivery landed; `translate.h` digest re-derived

**What the build role landed in `build.zig`.** `-Dlinkage=static|dynamic` with
`.static` preserved as the default (`:739-752`), resolving per target so a
platform with no dynamic linker takes a static archive under
`-Dlinkage=dynamic` and says so on its configure line; `-Dgeneric128` unchanged
and now explicitly orthogonal to linkage (`:755-759`); `lib/pkgconfig/ryu.pc`
generated by the graph with `prefix=${pcfiledir}/../..` and `Libs.private: -lc`
(`:587-608`, installed at `:779`); the thirteen licence and provenance files
installed under `share/licenses/ryu/` with the `third_party/` structure
preserved (`:611-621`). `build.zig.zon` `.paths` carries the relocated README and
the packaging files, and `verify.yml` names three differing upstream paths, checks
`README.upstream.md` against upstream's digest, and asserts `README.md` is *not*
that digest. Entries 28, 30 and 31 are therefore landed in source.

**One honest boundary this SDK has no answer for, by construction.** Upstream
publishes no ABI number — `CMakeLists.txt:2` is `project(ryu VERSION 2.0)`, the C
library's version line — its target carries no `VERSION`/`SOVERSION`, and neither
public header declares a visibility or dllexport macro. So the shared object has
**no soname, no version script and no export list**, and every symbol is exported
by default. That is upstream's own shape, carried through rather than invented
away, and no document here describes an ABI number or an export list for this
library.

**`translate.h`, and why its digest moved twice.** The owning role's edits had
turned the record red mid-flight; the digest was deliberately not refreshed over
an in-progress file. With the file final, Group F's line moved from `049973a7…`
to `b8273a8217ca5c67435eb33ccae1f88182b6b2113cbc0d574931d391b5de24cc` and the
38-path total from 2689946 to 2690247 bytes. The changes are comment-only and are
attributed in `UPSTREAM.sha256`'s header and in Group F: an SPDX header
(`Apache-2.0`, covering this fork's own file and nothing under `ryu/`), the
`README.md:35-38` → `README.upstream.md:35-38` citation rename from entry 28, and
a stale `build.zig` line citation corrected to `build.zig:295-297`. The include
guard, the two `#include` lines and every byte a C consumer sees are unchanged.

**This is a fork-authored wrapper record, not a native one.** `translate.h` is
Group F. No Group A, B, C, D or E digest moved, and no native C source, header,
test, fixture or licence byte changed: `ryu/` remains upstream's bytes except
the one disclosed include line, and the digest refresh covers the fork's own
translation wrapper, which is a legitimate thing for a fork checksum to track.

**Status.** `PENDING-VERIFICATION`. Nothing here has been built, run or
installed. `sha256sum -c UPSTREAM.sha256` reports 38 records, 38 `OK`, exit 0 in
this working copy after the re-derivation — an integrity-record replay, not a
build, test or matrix gate, and not the fetched-copy half of that record's claim.

**A defect this role found, reported, and the owning role closed.** The first
correction to that stale citation read `build.zig:289-291`; those lines are the
comment preceding `c_flags`, and the construct the sentence rests on is
`build.zig:295-297`. The claim was true and the citation landed six lines short,
which is why a search for `c_flags` did not catch it. This role reported both
ranges rather than editing a file whose digest it had just re-derived; the
owning role corrected line 69 to `build.zig:295-297` and the digest moved again
to the value above. `FORK-NOTES.md` note 17.

**Corrected by entry 33.** One clause above is not what the delivered graph
does. `-Dlinkage=dynamic` on a platform with no dynamic linker is **refused**,
at configure time and with the build's own sentence ending `No static
substitution is made` (`build.zig:844-853`, `:867-876`), rather than answered
with a static archive. The refusal is the honest answer; a substitution would
have been a build reporting something it did not do. The rest of this entry —
the `.pc` file, the licence record, the `translate.h` digest history and the
`build.zig.zon` `.paths` work — stands.

---

## 33. The runtime route, the generic-128 translation, and four claims that outlived their source

**What is in the tree, stated as source rather than as a plan.** `-Druntime=true`
(`build.zig:914-930`) replaces the dispatch without changing delivery:
`runtime/graph.zig`'s `createModule` builds the generated dispatch in place of
`translate.createModule()`, the module links no archive at all
(`build.zig:604-623`), and the artifact is still compiled and installed exactly
as `-Dlinkage` decided. The sixteen (or twenty-one) entry points come from what
the translation step actually produced, not from a hand-written list.
`zig/root.zig` publishes `runtime_loaded`, `load`, `loadedSource`, `LoadSource`
and `LoadError` in both configurations (`zig/root.zig:267-326`), and
`smoke.zig`, `tests.zig` and `consumer/src/main.zig` each name a provider
explicitly: `--provider <file>`, `--system <name>`, or `RYU_PROVIDER` /
`RYU_TEST_PROVIDER` for the two run steps `build.zig` starts without arguments.
The consumer package's own `run` step is the one that takes program arguments:
`consumer/build.zig` forwards the caller's `b.args`, so
`zig build run -- --provider <file>` reaches `consumer/src/main.zig`.

`translate.h` carries `ryu/ryu_generic_128.h` behind the fork-owned macro
`RYU_TRANSLATE_GENERIC_128`, which `build.zig` defines on the translation line
under exactly the option that compiles `ryu/generic_128.c` and installs its
header (`build.zig:508-540`, `:569-578`). A `-Dgeneric128` build therefore
translates and dispatches **twenty-one** entry points and publishes the five
converters to Zig through `ryu.c` and through the `generic128` namespace;
a default build is still sixteen and `generic128` is `void`.

**Four sentences in this repository's own documentation had fallen behind that
source.** Each was a present-tense claim a reader would act on, not a historical
one, so each is corrected in place rather than annotated and left standing.

1. `README.zig.md`'s route table called the runtime-loaded provider "**not in
   this repository yet.** No table, no loader and no `runtime/` exists here".
   Six files under `runtime/` exist, `build.zig` declares and threads the
   option, and three of this package's own programs drive the route.
2. The same file said `wasm32-wasi` "takes a static archive under
   `-Dlinkage=dynamic`". It refuses, and says so
   (`build.zig:844-853`). Documenting a substitution where the build refuses is
   the quiet failure this fork's rules forbid, so the passage now quotes the
   refusal, including `No static substitution is made`.
3. The same file said "The Zig facade publishes **no** generic 128-bit symbol".
   That was true when written and stopped being true when the header began to
   be translated; `-Dgeneric128` is not a C-surface option.
4. The same file said "There is no allocation anywhere in the facade", while
   `format32ShortestOwned`, `format64ShortestOwned`, `format64FixedOwned` and
   `format64ScientificOwned` call `f2s`, `d2s`, `d2fixed` and `d2exp` — the four
   upstream `malloc` entry points — and return memory only the C library's
   `free` may release (`zig/root.zig:566-657`). A caller who trusted that
   sentence would hand a libc pointer to a Zig allocator and corrupt a heap it
   does not own. The buffer writers remain allocation-free; the `Owned` writers
   are the deliberate exception, and the documents now separate the two.

`README.md` § 3b, `README.zig.md`'s API table and build modes, `NOTICE.md`'s file
table and `FORK-NOTES.md` carry the same corrections. `NOTICE.md` also records
the six `runtime/` files and `sync.c`, which its table did not yet name.

**Status.** `SOURCE-CONFIRMED` for the whole of the first half. `OBSERVED` for
the second: the driver ran `test smoke install` on this tree on 2026-10-04 in
eight linked configurations — **exit 0 for all eight**, `Build Summary: 26/26
steps succeeded; 33/37 tests passed (4 skipped)` in each, the four skips being
the generic-128 tests in a build that did not configure `-Dgeneric128` — and in
eight `-Druntime=true` configurations across both linkages and all four
optimize modes, **all eight exiting 1** with `25/27 steps succeeded (1 failed);
0/37 tests passed (37 crashed)`. In each of those eight the build, the dispatch
generation, `smoke` and `install` succeeded and `smoke` printed `loaded
RYU_PROVIDER <path>`; the single failure is `tests.zig`'s own precondition, which
requires `RYU_TEST_PROVIDER`, unset in those runs.

**What is still unobserved, and is not written up as a pass.** No loaded `test`
step has yet run against a named provider, so this entry claims no green
behavioural suite on the runtime route; the replay that exports both variables
arrives as its own row with its own receipt. No `wasm32-wasi` gate has run, so
the refusal above is source-read rather than observed. No external ryu exists on
this host at all, so external-provider coverage is recorded as absent rather
than filled with a look-alike; a shared object that converts binary64 but does
not export these sixteen is refused, and that refusal is the documented
boundary, not a substitute for one.

**And the lock.** `README.md` § 4d, `NOTICE.md` and entry 30 above all said this
repository owns no lock and that `flake.lock` and `devenv.lock` belong to the
driver. `flake.lock` is in this directory and pins the rev `flake.nix` names;
there is no `devenv.lock`, and none was invented for one. `build.zig.zon`
`.paths` still does not list `flake.lock`, so a filtered fetch carries the flake
without its lock. That is recorded here as a fact about the manifest, not
asserted as a defect and not silently described the other way.

## 34. Gave the six canonical devenv tasks a root, an external cache, an external prefix, the three recipe flags and the matrix job counts

**What changed.** `devenv.nix`, `README.md` § 4d. No task was renamed, added or
removed: `sdk:build`, `sdk:test`, `sdk:smoke`, `sdk:check`, `sdk:install` and
`sdk:matrix` are the same six names entry 30 and README § 4d already published.
No build file, no Zig surface, no fixture, no licence byte and no upstream
record moved.

Each body now begins `cd <sdkRoot> || exit 1`, where `sdkRoot =
builtins.toString ./.` rendered through `lib.escapeShellArg`. `./.` in an
expression is resolved relative to the module that writes it, so a task finds
this SDK whatever directory the shell was entered from — the driver enters from
a scratch project holding no `build.zig` and no `cross-test.profile.sh`.
`builtins.toString` and not `"${./.}"`: the interpolated form copies this whole
tree into the read-only Nix store, which is a second frozen SDK rather than the
working tree the tasks build and matrix over. `|| exit 1` because a body that
continued after a failed `cd` would build in the caller's directory.

All five `zig build` bodies now carry this workspace's three flags and nothing
optional among them (`AGENTS.md:157-159`): `-j8`, an explicit
`--cache-dir "$ZIG_LOCAL_CACHE_DIR/ryu"` and `--summary all`. The two that install
also pass `--prefix "$ZIG_LOCAL_CACHE_DIR/ryu-prefix"`: `sdk:build`, because a
bare `zig build` *is* the install step here (`build.zig:942` attaches the
artifact, `:957-960` the generated pkg-config file and licence records, `:967` the
smoke example), and `sdk:install` by name. So neither writes `zig-out/` here.
`sdk:test`, `sdk:smoke` and `sdk:check` depend on no install step
(`build.zig:973-998`) and are given no prefix they do not need.
`sdk:matrix` is `cross-test --jobs 8 --build-jobs 8` — two separate flags, each
with its own value, and the two the tool parses as `CLI_JOBS` and
`CLI_BUILD_JOBS`.
`-j` is not one of them: the harness manages it itself and rejects it in
`CROSS_BUILD_ARGS` (`cross-test.profile.sh:39-40`), and this SDK's profile
names no compiler cache or output directory either, so the matrix body passes
it neither.

**The cache is filled in the body, not only in `enterShell`.** `devenv tasks run
--mode single` does not source the shell hook, so a fill that lived only in
`enterShell` would leave a task running `zig build --cache-dir "$ZIG_LOCAL_CACHE_DIR/ryu"`
with the variable unset — which reaches the compiler as `--cache-dir "/ryu"`, a
path this file does not get to invent and a worse outcome than the SDK-local
`.zig-cache` default it replaced. The `cd` and the fill are therefore the first
lines of every task body itself: a caller-exported `ZIG_LOCAL_CACHE_DIR` or
`ZIG_GLOBAL_CACHE_DIR` is kept exactly as it is, a missing one is derived from
`$XDG_CACHE_HOME` else `$TMPDIR`, only a directory chosen that way is created,
and with neither exported the task names what is missing and exits non-zero
*before* the compiler runs. `enterShell` keeps the same fill, in the same order
and to the same sub-paths, because an interactive `zig build` wants the location
too; there it warns and continues rather than refusing to open a shell. No
`/tmp`, `/var/tmp`, store path, host path or account appears in this file, and no
new `ZIGLOCAL`-style alias was introduced.

**Status.** `PENDING-VERIFICATION`. Nothing here has been run: no devenv, zig,
cross-test or Nix command was executed over this change, and the six task
bodies above are read out of `devenv.nix` rather than out of a receipt.

## 35. Corrected two of this fork's own generic-128 expectations, and ran the option with it on

**Condition.** `-Dgeneric128` is off by default, so in a default build the
optional unit is not compiled and its four Zig tests skip themselves on
`ryu.generic128 == void`. Until this wave no gate in this repository had ever
put the option on for a `zig build test`, so that suite had never executed. The
first run that did — the driver's `-Dgeneric128=true` native wave, epoch
`20261004T232718759106Z-40382` — was red in all eight cells, and both of its
failures were this fork's mistake rather than a defect in Ryu's conversion.

**Symptom.** `Build Summary: 24/26 steps succeeded (1 failed); 33/36 tests
passed (1 skipped, 2 failed)` in every cell, `totals` `pass: 0`, `fail: 8`,
`not_passed: 8`, wrapper exit 1. `smoke` was green and `install` was green in
the same cells, so the failure was confined to two assertions inside
`tests.zig` and was neither a compile failure nor a smoke failure.

**Cause, twice.** `tests.zig:1063` demanded `"1E-324"` for
`generic128.shortestChars(f64, 5e-324, …)`. That string is a transcription of
the C++ literal `1e-324`, which is below half the smallest binary64 subnormal
and so underflows to `0.0` at translation time — it is not a subnormal at all.
The smallest binary64 subnormal's shortest round-tripping decimal is `5E-324`,
and that is the answer upstream's own suites publish for it
(`ryu/ryu/tests/generic_128_test.cc:275`, `ryu/ryu/tests/d2s_test.cc:51-53`,
`ryu/testdata/d2s_shortest.txt:44`), through the very function pair the generic
route calls (`ryu/generic_128.c:61-65`, `:331-345`). And `tests.zig:1114`
asserted `expect(infinite.sign)` on a **positive** infinity;
`generic_binary_to_decimal` copies the IEEE sign bit and nothing else
(`ryu/generic_128.c:94`, `:105-111`), so for `+inf` that bit is `0`. Upstream
asserts the same (`generic_128_test.cc:242-247`), and that one test was also
self-contradictory: four lines on it demanded `"Infinity"` with no minus sign
from the same value, which is the same field's decision
(`ryu/generic_128.c:289-291`).

**Change.** Two assertion lines, in `tests.zig` only: `1E-324` → `5E-324`, and
`expect(infinite.sign)` → `expect(!infinite.sign)`. No library, header or
algorithm moved; no expectation was re-pinned to whatever the code printed; no
test was deleted; `zig/root.zig` gains a doc comment and nothing executable. Two
further edits in the same pass change only comments and citations. No upstream C
source, header, table, test, fixture or licence byte changed, no `build.zig`
option moved, and `UPSTREAM.sha256` covers none of the files this entry touches.

**The one skip that remains, and why removing it is not the fix.**
`tests.zig:1172` skips itself — `if (comptime ryu.generic128.LongDouble != f80)
return error.SkipZigTest;` — because on the pinned Zig the translated header
spells that parameter `c_longdouble`, so `LongDouble` is Zig's opaque C `long
double` and not `f80` on **any** target, x86_64 included, and Zig has no way to
write a value for it at all (`lib/std/zig/c_translation/helpers.zig:387`).
Deleting the guard would not make the test pass; it would not compile. This is a
hard ABI/typing boundary and it stays. The x87 answer is not lost: it is
reachable from C, where `long double` is the language's own type (the installed
C surface rows of entries 7 and 18), and from Zig through `fromBinary` with
upstream's own 64-mantissa-bit, 15-exponent-bit, explicit-leading-bit triple
(`ryu/generic_128.c:80`).

**Status — applied, and re-gated as sixteen partials, not sixteen passes.**
With `-Dgeneric128=true` the driver ran sixteen cells on this tree: eight
native (`-Druntime=false`) and eight runtime-loaded (`-Druntime=true`),
Debug / ReleaseSafe / ReleaseFast / ReleaseSmall × static / dynamic.
**All sixteen built and ran with zero failures**, each printing
`35/36 tests passed (1 skipped)`, each with the one `tests.zig:1172` skip above
and no other: the native cells report `26/26 steps succeeded`, the loaded cells
`27/27`, both at command exit 0, `smoke` ends `every answer matched`, and
`install` carries `include/ryu/ryu_generic_128.h` into its approved prefix
(`generic128_header_installed: true`) with the compiled-input closure
`identical: true`. The attribution agrees cell for cell — `expected_skipped: 1`,
`reachable_sites: 1`, `other_sites: 0`, `feature_off_sites_could_fire: false`,
`bucket: abi_guard`, `partial: true`.

**The two numbers do not conflict, and neither is a green suite.** The `zig
build` command exits 0; the driver's strict verdict is `skipped-tests`, so its
wrapper exits 1 for all sixteen and each wave's `totals` read `pass: 0`,
`fail: 0`, `skipped_tests_abi_guard: 8`, `not_passed: 8`. A partial is not a
pass. **`36/36` is not what happened** and neither is 16 of 16 green. Receipts:
epoch `20261005T014407332917Z-66097-ryu-native` (`run.json` plus the eight
`ryu-native-generic128-*` cells) and epoch `20261005T015048544771Z-69523-ryu-loaded`
(the same shape, eight `ryu-loaded-generic128-*` cells, the provider being this
tree's own `libryu.so` from that first wave's dynamic prefixes).

**The default-configuration waves stay partials of the other kind.** Epochs
`20261004T233628757747Z-69351` (native) and `20261004T232823091897Z-23133`
(runtime-loaded, both provider variables exported) each ran eight cells at
`32/36`, four feature-off skips, `status: skipped-tests` throughout, because the
option is off there and its suite cannot run. They prove the default closure in
all eight configurations; they say nothing about the option.

**What this entry does not claim.** `check -Dgeneric128=true` has still never
been run for any foreign target: all sixteen cells above are the native target,
so the optional sixth unit has native evidence and none elsewhere, and entry 7's
and entry 22's "not run for a foreign target" lines are unchanged. No
independent external provider was exercised — the route wave of epoch
`20261004T232439Z` records `external_successes_observed: 0` and
`own_routes_counted_as_external: []`, with every external candidate an expected
refusal. The full 53-target matrix on this tree is **20 runtime PASS, 33
`build_only`, 0 fail** (epoch `20261004T221720228710Z-45046`, receipt
`ryu-53-target-8.json`) and the whole-graph `check` baseline is compile-only,
exit 0, `runtime_pass_claimed: false` (epoch `20261005T014547Z-797a73f2`); neither
is a full-suite runtime pass, and `build_only` is never a pass. And no foreign
byte has been delivered or verified: this SDK's delivery-candidate file is a
candidate analysis, and the twelve-byte foreign criteria it names have not been
executed.
