# FORK-NOTES.md — what actually went wrong, and what was decided

Problems met while packaging ulfjack/ryu as a Zig 0.16 package, and the
decisions they forced. Written in the shape a later wave can reuse: **condition,
symptom, cause, fix, what it is bound to**. Statuses are the workspace's:
`OBSERVED` (a driver run printed it, receipt named), `SOURCE-CONFIRMED` (read out
of a file, never executed), `PENDING-VERIFICATION` (landed, no gate has looked at
it), `NOT RUN` (no receipt exists at all).

The entries below are in three kinds. Five are mistakes this fork made in its own
files — two hand-written rounding expectations, a call and then a bit-cast in a
dependent example, a `/*` inside its own comment, and a layout argument in its
own C gate — and every one was found by a red gate rather than by review. Two
are gaps rather than mistakes: a deleted test that no gate had yet counted, and
a fingerprint that was shipped nowhere and replayed by nothing. Note 14 is a
gate that had never been run, and note 15 is neither kind at all: its failure
was in an SDK header this tree never needed, and what it took was one disclosed
line rather than a workaround. `README.zig.md` § "Verification status" holds
the authoritative current gate table; the ledger in § 0 below is the run history
behind it.

---

## 0. Every gate this package has ever run

| # | Command (after `zig`; rows 1–21 with `-j8 --summary all` and a per-target `--cache-dir`, rows 22–28 against an approved prefix outside the repository with their own cache directories, rows 29–37 from the cross-test wave with their own cache directories and, where the harness supplies them, `--prefix`, `--build-runner` and `--libc-runtimes`, and row 38 from the six-target baseline round, one `build check` per triple with its own cache directory and its own prefix outside the repository) | When | Exit | Receipt |
|---|---|---|---|---|
| 1 | `build test -Doptimize=Debug` | 2026-10-01T15:47:03Z | 1 | `local://foundation-expansion-ryu-initial-debug-18.log` |
| 2 | `build test -Doptimize=Debug` | 2026-10-01T16:11:00Z | 1 | `local://foundation-expansion-ryu-repaired-debug-26.log` |
| 3 | `build test -Doptimize=Debug` | 2026-10-01T17:16:21Z | 1 | `local://foundation-expansion-ryu-current-debug-50.log` |
| 4 | `build smoke` | 2026-10-01T17:16:31Z | 0 | `local://foundation-expansion-ryu-current-smoke-52.log` |
| 5 | `build` | 2026-10-01T17:16:36Z | 0 | `local://foundation-expansion-ryu-current-install-56.log` |
| 6 | `build test -Doptimize=ReleaseSafe` | 2026-10-01T17:16:37Z | 1 | `local://foundation-expansion-ryu-current-releasesafe-58.log` |
| 7 | `build run` in `consumer/` | 2026-10-01T17:18:28Z | 1 | `local://foundation-expansion-ryu-current-consumer-67.log` |
| 7a | `build smoke` | 2026-10-01T18:01:48Z | 0 | `local://foundation-expansion-ryu-latest-smoke-85.log` |
| 8 | `build smoke` | 2026-10-01T18:12:46Z | 0 | `local://foundation-expansion-ryu-final-smoke-93.log` |
| 9 | `build test -Doptimize=Debug` | 2026-10-01T18:12:46Z | 0 | `local://foundation-expansion-ryu-final-debug-95.log` |
| 10 | `build test -Doptimize=ReleaseSafe` | 2026-10-01T18:12:47Z | 0 | `local://foundation-expansion-ryu-final-releasesafe-99.log` |
| 11 | `build` | 2026-10-01T18:13:05Z | 0 | `local://foundation-expansion-ryu-final-install-101.log` |
| 12 | `build run` in `consumer/` | 2026-10-01T18:13:05Z | 1 | `local://foundation-expansion-ryu-final-consumer-102.log` |
| 13 | `build run` in `consumer/` | 2026-10-01T18:21:47Z | 0 | `local://foundation-expansion-ryu-consumer-repair-proof-113.log` |
| 14 | `build -Dgeneric128=true` | 2026-10-01T18:21:47Z | 0 | `local://foundation-expansion-ryu-generic128-proof-116.log` |
| 15 | `sha256sum -c UPSTREAM.sha256` | 2026-10-01T18:42:01Z | 0 | `local://foundation-expansion-ryu-immutable-source-integrity-126.log` |
| 16 | `build check -Dtarget=x86_64-linux-gnu` | 2026-10-01T18:45:41Z | 0 | `local://foundation-expansion-ryu-matrix-x86_64-linux-gnu-134.log` |
| 17 | `build check -Dtarget=aarch64-linux-gnu` | 2026-10-01T18:45:43Z | 0 | `local://foundation-expansion-ryu-matrix-aarch64-linux-gnu-135.log` |
| 18 | `build check -Dtarget=aarch64-macos-none` | 2026-10-01T18:45:48Z | 0 | `local://foundation-expansion-ryu-matrix-aarch64-macos-none-138.log` |
| 19 | `build check -Dtarget=x86_64-windows-gnu` | 2026-10-01T18:45:52Z | 0 | `local://foundation-expansion-ryu-matrix-x86_64-windows-gnu-141.log` |
| 20 | `build check -Dtarget=riscv64-linux-gnu` | 2026-10-01T18:45:56Z | 0 | `local://foundation-expansion-ryu-matrix-riscv64-linux-gnu-144.log` |
| 21 | `build check -Dtarget=wasm32-wasi` | 2026-10-01T18:46:01Z | 0 | `local://foundation-expansion-ryu-matrix-wasm32-wasi-147.log` |
| 22 | `build --prefix <approved>`, outside the repository | 2026-10-01T20:50:06Z | 0 | `local://foundation-expansion-ryu-installed-artifact-gruenau8-177.log` |
| 23 | installed C surface, `zig cc` outside the build graph | 2026-10-01T20:52:52Z | 1 | `local://foundation-expansion-ryu-installed-C-surface-182.log` |
| 24 | `build --prefix <approved>`, after the `translate.h` comment fix | 2026-10-01T21:06:00Z | 0 | `local://foundation-expansion-ryu-installed-headers-comment-corrected-186.log` |
| 25 | installed C surface, isolated local cache | 2026-10-01T21:07:55Z | 0 | `local://foundation-expansion-ryu-installed-C-surface-isolated-cache-191.log` |
| 26 | `build -Dgeneric128=true --prefix <approved>` | 2026-10-01T21:12:17Z | 0 | `local://foundation-expansion-ryu-generic128-installed-artifact-195.log` |
| 27 | installed generic-128 C surface, before correction | 2026-10-01T21:28:06Z | 1 | `local://foundation-expansion-ryu-generic128-C-surface-before-correction-208.log` |
| 28 | installed generic-128 C surface, corrected | 2026-10-01T21:41:14Z | 0 | `local://foundation-expansion-ryu-generic128-C-surface-corrected-227.log` |
| 29 | `build test smoke install -Doptimize=Debug`, on the patched `ryu/ryu.h` | 2026-10-02T05:31:06Z | 0 | `local://foundation-cross-test-ryu-native-Debug.log` |
| 30 | `build test smoke -Doptimize=ReleaseSafe`, same tree | 2026-10-02T05:31:13Z | 0 | `local://foundation-cross-test-ryu-native-ReleaseSafe.log` |
| 31 | `build run` in `consumer/`, same tree | 2026-10-02T05:31:49Z | 0 | `local://foundation-cross-test-ryu-native-consumer.log` |
| 32 | `bash -n cross-test.profile.sh`, then `cross-test --list` and `cross-test --no-profile --list` | 2026-10-02 | 0, 0, 0 | `local://foundation-cross-test-profile-ryu-syntax.log`, `-list_profile.log`, `-list_no_profile.log` |
| 33 | `cross-test`, full published matrix, on the **pre-deviation** tree | 2026-10-02T04:02:36Z | 1 | `local://foundation-cross-test-evidence.json`, `checks[]` entry `library: ryu`, `stage: matrix`; per-cell logs `local://foundation-cross-test-matrix-ryu-<target>.log` |
| 34 | `cross-test`, full published matrix, on the patched tree (`run_id` `20261002-053059-41494-21055`) | 2026-10-02T05:30:59Z | 0 | `local://foundation-cross-test-corrected-ryu.json`, with 53 per-cell logs as `local://foundation-cross-test-corrected-ryu-<target>.log` |
| 35 | `build test smoke install -Doptimize=Debug`, stable native round on the same patched `ryu/ryu.h` | 2026-10-02T06:45:39Z | 0 | `local://foundation-cross-test-stable-ryu-native-Debug.log` |
| 36 | `build test smoke -Doptimize=ReleaseSafe`, same round | 2026-10-02T06:45:39Z | 0 | `local://foundation-cross-test-stable-ryu-native-ReleaseSafe.log` |
| 37 | `build run` in `consumer/`, same round | 2026-10-02T06:45:39Z | 0 | `local://foundation-cross-test-stable-ryu-native-consumer.log` |
| 38 | `build check -Dtarget=<triple> -Doptimize=Debug`, the same six triples as rows 16–21, workspace baseline round | 2026-10-02T06:20:42Z–06:32:06Z | 0, 0, 0, 0, 0, 0 | `local://foundation-cross-test-baseline-before-sdk-corrections.json`, `cells[]` entries `sdk: ryu`; per-target logs `local://foundation-cross-test-baseline-ryu-<target>.log` |
| 39 | `cross-test`, full published matrix, current inline native change notice and corrected aggregate citation (`run_id` `20261002-080415-53964-27076`) | 2026-10-02T08:04:15Z | 0; 20 pass, 33 build-only, no fail or partial | `local://foundation-cross-test-final-current-ryu.json`; `local://foundation-cross-test-final-current-ryu-<target>.log` |
| 40 | Current native Debug test/smoke/install, ReleaseSafe test/smoke, source consumer | 2026-10-02 | 0, 0, 0; 28/28 tests each mode | `local://foundation-cross-test-final-native-ryu.json`; `local://foundation-cross-test-final-ryu-native-{Debug,ReleaseSafe,consumer}.log` |
| 41 | Current explicit six-target compile-only baseline | 2026-10-02 | 0 for all six | `local://foundation-cross-test-final-baseline.json`; `local://foundation-cross-test-final-baseline-ryu-<target>.log` |
| 42 | Current workflow one-line native-header reversal excerpt | 2026-10-02 | 0; pristine 1,360-byte header and pinned SHA reproduced | `local://foundation-cross-test-evidence.json`, auxiliary check `ryu-native-include-notice-reversal` |
| 43 | Filtered fetch, source/fetched record checks and materialised consumer after SDK documentation freezes | driver-owned closure | Per-gate status and final identity are outside this package | `FORKS.json.cross_test_wave.materialized_packages.ryu`; `local://foundation-cross-test-package-regression.json` |

This is the complete run history, in order. The current state of each gate is
the table in `README.zig.md` § "Verification status"; every red row above
describes files as they stood at that moment, not as they stand now.

Rows 29–38 are the cross-test wave and they changed what earlier rows mean.
Rows 29–31 are the first native runs on the patched `ryu/ryu.h`, and rows
35–37 are the same three gates re-run later that day in the stable round, on
the same patched header and with the same counts, so the native evidence
stands twice over. Row 38 re-ran the six compile-only `check` cells of rows
16–21 against that same patched header, six for six at 6/6 steps, so those
rows are no longer pre-deviation only. Every other row above them still
describes the pre-deviation tree: rows 9, 10, 25 (the installed C surface) and
the four `-Dgeneric128` rows 14, 26, 27 and 28 have not been re-run on the
patched header, and row 15's `sha256sum -c` replayed the record as it stood
before the record was re-derived. Rows 33 and 34 are the two full-matrix runs,
before and after the change; row 33 is the observation that produced the change
and row 34 is what the change was worth.

Two things have still never been run and no row above covers them:
`zig build check -Dgeneric128=true` for any target, and any execution of this
repository's own `.github/workflows/verify.yml`. The twelve `check` rows — six
of them twice — are the **default five-unit graph**; the optional sixth unit
has been compiled and run here for the native target only, and only before the
header change. Row 23 is red for two unrelated reasons at once, which note 12
unpacks. Row 7a is an intermediate smoke re-run kept in order rather than
renumbered around; the numbers after it are the ones the notes below cite.

---

## 1. translate-c gave the parser status `c_uint`, and `c_int` did not fit it

**Condition.** Upstream's `s2d_n`/`s2f_n` return `enum Status`
(`ryu/ryu_parse.h:29-34`), and the facade maps that status onto its own error
set through a private helper.

**Symptom.** The first native test gate did not compile:

```
zig/root.zig:318:32: error: expected type 'c_int', found 'c_uint'
       try checkStatus(c.s2d_n(immutable(text), len, &out));
                       ~~~~~~~^~~~~~~~~~~~~~~~~~~~~~~~~~~~
zig/root.zig:318:32: note: signed 32-bit int cannot represent all possible unsigned 32-bit values
```

**Cause.** The helper's parameter was written as `c_int` from the habit of C
integer returns, and translate-c had chosen `c_uint` for the enumerator type.

**Fix.** The helper takes `c_uint` (`zig/root.zig:352`), matching the
translation.

**Bound to.** The pinned Zig's translate-c and this header. Any wrapper over an
enumerated status has to read the translated type rather than assume one; the
error text names the type it wanted and the note names why the other is wrong,
so this is diagnosable from the diagnostic alone.

**Status.** `OBSERVED` (receipt 1). Repaired before receipt 2.

---

## 2. An oracle is only an oracle if its input side can be decoded

**Condition.** The known-answer fixtures carry upstream's *input specifications*
verbatim next to the expected strings — `zero`, `negzero`, `bits <hex>`, `parts
<sign> <exponent> <mantissa>`, `lit <decimal>` — so that a row is checkable in
both directions.

**Symptom.** Two tests in receipt 2 failed with `error.UnknownSpec` from the
decoder: `tests.test.binary64 shortest reproduces every published answer` and
`tests.test.binary32 shortest reproduces every published answer`.

**Cause.** The decoder knew some of that grammar and not all of it. The grammar
is not this fork's invention — it is upstream's own test helpers
(`int64Bits2Double(0x...)` at `d2s_test.cc:27`, `ieeeParts2Double` at
`d2s_test.cc:29-33`) — and transcribing the rows without transcribing the
helpers produced rows the fork could not read back.

**Fix.** The decoder implements the full documented spec grammar, including
`parts` with either a decimal or a `0x` mantissa, and fails loudly
(`error.UnknownSpec`) on anything else rather than guessing.

**Bound to.** Any package whose fixtures are transcriptions rather than a
vendored corpus. If a row cannot be turned back into the value it was written
for, the fixture is a string-comparison test with extra steps.

**Status.** `OBSERVED` (receipt 2). Both tests are among the 28 that passed in
receipts 9 and 10.

---

## 3. Significant digits come from the value, not from the decimal literal

**Condition.** Two tests pin what happens when a run of nines sits exactly at the
edge of a precision: one where it carries, one where it does not.

**Symptom.** First, in receipt 2:

```
error: 'tests.test.a run of nines carries out of the fraction' failed:
       expected this output: 1.000e+00
       instead found this:   9.999e-01
```

Then, in receipts 3 and 6, after that was repaired:

```
error: 'tests.test.a run of nines one digit short of the precision does not carry' failed:
       expected this output: 9.9999e-01
       instead found this:   9.9990e-01
```

**Cause.** Two different miscounts of the same fact, both in the expected
strings and neither in the library.

* `0.9999` is **exactly four** significant digits as a binary64 — the nearest
  double is `0.99990000000000001101…`. A scientific precision of 3 asks for
  four significant digits, so there is nothing to round and the answer keeps
  every nine: `9.999e-01`. The carry belongs to `0.99999`, which is
  `0.99999000000000004551…` and does round up at precision 3, in both styles.
* A precision of 4 asks for **five** significant digits. Four exist and the
  fifth is a padded zero: `9.9990e-01`. Expecting `9.9999e-01` was asking for
  four digits where five were requested.

In scientific notation, `precision` counts the digits *after the leading digit*,
so it is `precision + 1` significant digits; in fixed notation it counts the
digits after the point. The two writers therefore carry differently at the same
`precision`, which is why the same value has answers of different shapes in the
same test row.

**Fix.** Every expected string in those tests is derived from the exact decimal
expansion of the double, and the derivation is written in the comment above the
table (`tests.zig:441-445`, `:458-467`).

**Bound to.** Any test that writes a rounding expectation by hand. The defect is
not specific to Ryu — it is what happens when a hand-worked decimal is used in
place of the value's exact expansion — and it survives into ReleaseSafe, where
the two receipts 3 and 6 show the identical failure.

**Status.** `OBSERVED` for the failures and `OBSERVED` closed: the corrected
expectation is in the 28/28 that receipts 9 and 10 report. `9.9990e-01` is not
a loosened expectation — it is the correctly rounded expansion of a four-digit
value asked for five significant digits, and the width of that claim is what
made the old row look plausible.

---

## 4. A test that pins a capacity constant is a wiring test, not a boundary

**Condition.** `scientificCapacity` exists so a caller can size a buffer exactly;
its arithmetic is an implementation detail that a reader can recompute from the
comment.

**Symptom.** Receipt 2, fifth failure:

```
error: 'tests.test.the capacity bound is one sign, the widest integer part, a point and precision' failed:
       expected 10, found 9
```

**Cause.** The test asserted the value of the formula (`overhead + precision`,
where the special value is 9 bytes and `max` had not been applied at that
precision). Restating a constant this fork owns is the kind of test the fixture
policy deletes anyway.

**Fix.** The test that remains asserts the property instead: the nine byte
special value is the whole bound at the two precisions where it is, and a real
`-Infinity` answer fits in a buffer of exactly that size
(`tests.zig:560`, "the nine byte special value is the whole bound at the two
precisions it sizes"). The constants stay published in `zig/root.zig` for a
caller to plan against; nothing re-derives them in a test.

**Bound to.** Any published capacity constant. Bound a public constant by what
it admits, never by how it was computed.

**Status.** `OBSERVED` (receipt 2), repaired.

---

## 5. A short-buffer test must measure its buffer against its own answer

**Condition.** The shortest writers accept a buffer shorter than the worst case
when that buffer holds this particular answer — the documented copy-through-a-
stack-temporary path.

**Symptom.** Receipt 2, fourth failure, from inside the facade:

```
/vol/.../zig/root.zig:231:33: 0x12821d1 in format64Shortest (root.zig)
        if (produced.len > out.len) return error.BufferTooSmall;
/vol/.../tests.zig:481:48: 0x1282ed6 in test.a short buffer is enough when it holds the exact answer
    try std.testing.expectEqualStrings("-1E0", try ryu.format64Shortest(-1.0, &three));
```

**Cause.** The buffer and the expected answer disagreed about the length. The
facade was right to refuse: `-1E0` is three bytes and the buffer was shorter.

**Fix.** Every test of this property now sizes each buffer to the answer it is
handed and no byte more, so the test proves the property instead of a length
someone typed.

**Bound to.** Any wrapper with a length contract. A test that says "a buffer
this size is enough" has to derive the size from the answer, or it is testing
the arithmetic of whoever wrote it.

**Status.** `OBSERVED` (receipt 2), repaired, and green in receipts 9 and 10.

---

## 6. `&` on a slice expression is a pointer to a slice

**Condition.** The consumer proves the module contract from outside the package,
so it must write the call the way a dependent would.

**Symptom.** Receipt 7, a compile error, not a wrong answer:

```
src/main.zig:100:70: error: expected array of 'u8', found '[]u8'
       try ryu.format64Fixed(one_and_a_quarter, 3, &precision_buffer[0..try ryu.fixedCapacity(3)]),
                                                    ^~~~~~~~~~~~~~~~~^~~~~~~~~~~
```

**Cause.** `&` applied to `array[0..n]` with a runtime `n` yields a `*[]u8`, not
a `[]u8`. The address-of is not what "pass a slice of exactly this many bytes"
means; the slice is.

**Fix.** The slice is passed as a slice (`consumer/src/main.zig:100`), which is
also what makes the call site true to its own comment — the consumer spends
exactly the bound it was told about.

**Bound to.** Zig, and the habit of carrying an `&` from C. A dependent example
that does not compile teaches the wrong lesson even when the library is fine.

**Status.** `OBSERVED` (receipt 7), and `OBSERVED` closed (receipt 13). A
second compile error in the same consumer came next — `src/main.zig:108:57:
error: cannot @bitCast from 'comptime_float'` (receipt 12) — and was repaired as
well; receipt 13 is the run that saw both repairs in place.

---

## 7. Deleting a test changes the denominator of every receipt that counted

**Condition.** Receipts 3 and 6 each report `28 pass, 1 fail (29 total)`. One
of those tests has since been removed as a copy/alias check.

**Symptom.** Not a failure — a change in what a receipt can mean. A reader who
compares "29 total" against the current suite sees 28 and has to work out which
number moved and why.

**Cause.** A suite's size is part of what a red receipt reports, and a policy
removal changes it.

**Fix.** `README.zig.md`'s gate table reports the current count as 28/28 and its
earlier-red paragraph names receipts 3 and 6 as a 29-test suite, so no receipt
is silently read as describing the present one. Exactly one test left the suite
between them: the copy/alias check. Nothing that asserted a behaviour of the
library was removed.

**Bound to.** Any receipt that reports a count. When a gate's denominator changes,
every receipt with that denominator is historical, not current.

**Status.** `OBSERVED`. Receipts 9 and 10 both report `28 pass (28 total)`, so
the removal is behind a gate rather than only behind `CHANGELOG.md` entry 12.

---

## 8. The compile-only gate's coverage is a property of its caller files

**Condition.** Zig analyses a function body only when something calls it, so
compiling the C archive, or reflecting over the module, proves nothing about the
facade.

**Symptom.** Not a failure — the question of what `check` actually covers.

**Cause.** Compile coverage for a Zig API comes from call sites, and this package
has exactly two: `tests.zig` and `smoke.zig`.

**Fix.** `check` compiles both roots for every target, and `build.zig:74-87`
states the standing obligation: every public declaration in `zig/root.zig` must
be called from one of them, or `check` stops covering it. Namespacing is not a
call — a function reached through a public namespace still needs its own call
site, because the namespace has no body to analyse.

**Bound to.** This package's choice to make `check` compile the two roots. It
applies to any package whose gate proves the facade by compiling callers, and it
interacts directly with lesson 7: removing a test can silently remove the only
call site of a public declaration.

**Status.** `SOURCE-CONFIRMED`, and now `OBSERVED`: `check` ran green for all
six targets (receipts 16–21), so the coverage claim has compile evidence
behind it for the default graph. No foreign binary is executed by any of them,
and none of them builds the optional 128-bit unit.

---

## 9. `sha256sum -c` ignores comment lines, so a record can state its own scope

**Condition.** An integrity record that is only a list of digests says nothing
about *which* bytes it covers or how they were produced, and a reader who has to
guess will eventually guess wrong.

**Symptom.** None — a design decision taken before writing the file, checked
once so the record could be written in the form it was wanted in.

**Cause.** If `sha256sum -c` refused comment lines, the record would have to be
either bare (and silent about its own scope) or split across two files.

**Fix.** One file, `#`-prefixed header, then one `<hex>  <path>` line per
record. Verified on this machine against GNU coreutils 9.6: `sha256sum -c`
exits 0 on a file whose first line is a comment, and `sha256sum -c --strict`
does too.

**Bound to.** GNU coreutils as observed here. A different implementation may
reject a comment line, so the check to replay is the plain `sha256sum -c
UPSTREAM.sha256`, and a tool that complains about the header can be handed
`grep -v '^#' UPSTREAM.sha256` instead.

**Status.** `OBSERVED` for the behaviour, probed directly; for the record's own
38 digests, both by re-deriving them from the written file and by replaying
`sha256sum -c UPSTREAM.sha256` against this tree, which reports all 38 records
`OK` (receipt 15).

---

## 10. A working-tree digest is not a commit proof

**Condition.** This fork must show that upstream's bytes are untouched, and the
only check available without a fetch is over the bytes in the working tree.

**Symptom.** None. The failure mode was avoided by writing the limitation into
the record itself rather than leaving it to the reader.

**Cause.** A SHA-256 of a file says which bytes this tree holds. It says nothing
about whether those bytes are the ones upstream published, which is a statement
about a commit and needs a commit.

**Fix.** Two mechanisms, kept apart and each described in its own words.
`UPSTREAM.sha256` is the working-tree fingerprint, computed with Bun's crypto
over raw bytes and no shell or git hashing at all.
`.github/workflows/verify.yml`'s licence-and-provenance job is the
pristine-commit proof: it diffs every path the pinned commit tracks against that
commit, requires that commit to be an ancestor of HEAD, and permits exactly the
named differences the records justify — `.gitignore`, additively, and since note
15 `ryu/ryu.h`, which a second step holds to its recorded pristine and patched
digests and to the one-line shape of the difference. The archive receipt in
`UPSTREAM.md` is the third leg, for a machine that can re-fetch.

**Bound to.** Any fork that ships a checksum record. State the subject of the
hash in the same sentence as the hash, or a later reader will read a working-tree
fingerprint as provenance.

**Status.** `SOURCE-CONFIRMED` for the record; the replay is `OBSERVED`
(receipt 15, over the record as it stood then — open item 5) and the
commit-level job is `NOT RUN`.

---

## 11. The gate was wrong about the layout, and the library was right

**Condition.** `-Dgeneric128` is a C-surface option, so its gate is a C program
that includes the installed `ryu/ryu_generic_128.h`, links the installed archive
and calls the five functions that header declares. One of them,
`generic_binary_to_decimal`, takes the layout as four arguments rather than
knowing it: `bits`, `mantissaBits`, `exponentBits` and `explicitLeadingBit`
(`ryu/ryu_generic_128.h:56-57`). Everything the gate asserts about a layout is
this fork's claim, not upstream's.

**Symptom.** The gate's first run was red (receipt 27), on two rows out of
seven, and the two named conversions above them were already right:

```
binary128 1.25: got "5E-1" (4 bytes), want "1.25E0"
binary128 -1.25: got "-5E-1" (5 bytes), want "-1.25E0"
```

**Cause.** The gate passed `explicitLeadingBit = true`. IEEE binary128 has an
**implicit** leading bit: one sign bit, fifteen exponent bits with bias 16383,
112 stored fraction bits. `1.25` is `1.01b × 2^0`, so its bits are the exponent
field 16383 and the fraction `1 << 110` — exactly what the gate built — and the
flag then told the converter to read the stored `0.01b` as the entire mantissa,
which is `0.5`. Upstream's own code settles the question without argument:
`float_to_fd128` and `double_to_fd128` pass `false` (`ryu/generic_128.c:55`,
`:64`), and `long_double_to_fd128` passes `true` (`:80`) because the x87 80-bit
layout keeps that bit in the significand and counts it in
`LONG_DOUBLE_MANTISSA_BITS 64`.

**Fix.** That one argument is now `false`. Nothing else changed: the same bit
patterns, the same expected strings, the same buffer, and no upstream byte
touched. Receipt 28 is the same gate, run again.

**Bound to.** Any layout-parameterised upstream entry point. The gate was
testing this fork's claim about a layout, and the claim was wrong while the
code was right — a red receipt from a hand-written argument is not evidence
about the library. Two corollaries belong with it. The `long double` row is a
**native-platform observation**: upstream's own header says it "likely only
works on x86 with specific compilers" (`ryu/ryu_generic_128.h:50-51`), so that
row is stated for the x86_64 GNU/Linux machine that ran it and for no other.
And the buffer is an ordinary bound, not a fitted one: `generic_to_chars` writes
without a terminator and returns the count, and its header puts the worst case
at 53 characters (`ryu/ryu_generic_128.h:59-66`), so the gate takes the count
first, refuses anything outside `1 <= written < sizeof buffer`, and terminates
the string itself.

**Status.** `OBSERVED` red (receipt 27), `OBSERVED` closed (receipt 28).

---

## 12. One red log, two unrelated causes, neither of them the library

**Condition.** The installed C surface is compiled and run from outside the
build graph, with `zig cc` against an approved prefix and two translation units
that include the installed headers directly. A gate like that can fail for
reasons that have nothing to do with the facade, and it can fail for two at
once.

**Symptom.** Receipt 23, exit 1, and both causes are in the same log:

```
install/include/translate.h:14:61: warning: '/*' within block comment [-Wcomment]
   14 |  *   because the headers are in ryu/ and are included as ryu/*.h". Adding that
      |                                                             ^
1 warning generated.
direct_headers.c:1:1: error: CacheCheckFailed
```

**Cause.** The warning is this fork's own: `translate.h` is a `/* … */` comment
that quoted the include spelling as `ryu/*.h`, and the `*/` inside that literal
closed the comment early and then began a nested one. The error is not the
library's and not a compile failure at all — `CacheCheckFailed` is a cache
identity check refusing to reuse a `zig cc` local cache directory whose
manifest no longer matched a file that had just been rewritten.

**Fix.** The include spelling in that comment is written `ryu/<name>.h` now,
which contains no `*` immediately followed by `/`, and the re-install is
receipt 24 with the warning gone. The surface was then re-run against a fresh
local cache and passed in full (receipt 25): both headers resolve and link on
their own, the four `malloc`-returning formatters are used and each result is
freed, both parser widths are called in both their `_n` and their `strlen`
forms, the published roundings hold, and each refused input leaves the
caller's sentinel value untouched.

**Bound to.** Any fork-authored header that documents an include spelling inside
a comment, and any gate that reuses one cache directory across an edit. A red
log with a warning above a hard error is two diagnoses, not one; read to the
first line and the second cause survives into the next attempt.

**Status.** `OBSERVED` (receipt 23), repaired, `OBSERVED` closed (receipt 25).

---

## 13. The fingerprint was not in the package, and nothing replayed it

**Condition.** `UPSTREAM.sha256` is the fork's working-tree fingerprint and
`verify.yml` is the only thing that can prove the tree equals the pinned commit.
The first draft of both records left the fingerprint out of the package and left
the workflow trusting the commit diff alone.

**Symptom.** Not a failure — two gaps, both found by reading the files back.

**Cause.** They are independent halves of one claim. The pristine-commit diff
fails when an upstream path differs from the commit; the digest record fails
when any of the 38 hashed bytes moves here whatever a commit says. Shipping the
record without listing it in `.paths` means a dependent receives a claim it
cannot replay, and a workflow that never runs `sha256sum -c` means CI never
replays it either.

**Fix.** Both closed. `"UPSTREAM.sha256"` is listed in `build.zig.zon` `.paths`
beside every other fork record, and `verify.yml` runs
`sha256sum -c UPSTREAM.sha256` as the first step of its native job, before
anything is built (`.github/workflows/verify.yml:77-81`). The record has also
been replayed in this workspace against this tree: 38 records, every one `OK`
(receipt 15).

**Bound to.** Any fork that ships a checksum record and any workflow that
carries a provenance claim. Note lesson 9 if a `sha256sum` implementation ever
objects to the header lines.

**Status.** `OBSERVED` for the replay (receipt 15, over the record as it stood
then — open item 5); `SOURCE-CONFIRMED` for the manifest line and the workflow
step, both read out of the current files.

---

## 14. What the 32-bit and big-endian platforms in the full matrix depend on

**Condition.** `zig build check` covers six targets (`build.zig`,
`check_targets`), all of them 64-bit except `wasm32-wasi`. The full `cross-test`
matrix names platforms this package has never been compiled for, including
`x86-linux`, `x86-netbsd`, `x86-openbsd`, `x86-windows`, `arm`, `armeb`, `thumb`,
`thumbeb`, `hexagon`, `riscv32`, `mips`, `mips64`, `powerpc`, `powerpc64` and
`s390x`. Every one of those is 32-bit or big-endian, or both, and the question
they raise is the same one: upstream's core is written in integer arithmetic on
`uint64_t` and `uint128_t`, and `__uint128_t` is not a 32-bit facility. That was
read out of the sources before any of those platforms was compiled.

**Findings — `SOURCE-CONFIRMED`, read out of source, not executed.**

* *`__uint128_t` is guarded everywhere it is used, and every guard has a
  complete portable branch.* `ryu/d2s_intrinsics.h:28-36` defines `HAS_UINT128`
  only when the compiler reports `__SIZEOF_INT128__`; `:62-96` is the fallback,
  and it is 32×32→64 arithmetic on `uint64_t`, not a stub. The three
  `mulShift` families sit behind
  `#if defined(HAS_UINT128) / #elif defined(HAS_64_BIT_INTRINSICS) / #else`
  (`ryu/d2s_intrinsics.h:257` onward), and `ryu/d2fixed.c:50-193` repeats the
  same three-way shape for `umul256`, `umul256_hi` and `uint128_mod1e9`. A
  32-bit target takes the `#else` branches, which are ordinary C.
* *`RYU_32_BIT_PLATFORM` is narrower than its name, and that is a speed choice
  rather than a correctness one.* It is defined only for `_M_IX86` and `_M_ARM`
  (`ryu/common.h:24-25`), so clang on a 32-bit target does **not** get it. What
  that changes is which division helper is used — `ryu/d2s_intrinsics.h:103-189`
  offers `umulh`-based `div5`/`div10`/`div100`/`div1e8`/`div1e9`/`mod1e9` under
  the macro and `x / 5`, `x / 10`, … outside it — and which shift formulation
  `mulShift32` uses (`ryu/f2s_intrinsics.h:77-98`). Both spellings compute the
  same value; upstream's comment at `ryu/d2s_intrinsics.h:112-121` says the
  macro's purpose is to stop compilers emitting 64-bit division library calls.
  A 32-bit clang target is therefore slower and not wrong, and this fork defines
  nothing to paper over it.
* *Nothing depends on byte order.* `float_to_bits` and `double_to_bits` are
  `memcpy` into a `uint32_t`/`uint64_t` (`ryu/common.h:99-105`), never a pointer
  cast or a union, and the algorithm that follows is integer-only. A grep for
  `__BYTE_ORDER__`, `_MSC_VER`, `__GNUC__`, `__clang__` and `__builtin_` across
  `ryu/*.c` and `ryu/*.h` finds only the four `#ifdef __clang__` /
  `#if defined(_MSC_VER)` fast-path guards and the two `__builtin_clz*` helpers
  at `ryu/s2d.c:55` and `ryu/s2f.c:49`, none of which reads an endian macro.
* *`-Dgeneric128` stays out of the default closure, deliberately.* `build.zig`
  compiles `ryu/generic_128.c` only under that option, and `translate.h:34-40`
  explains why its header is absent from the aggregate: `pub const c` therefore
  never names a 128-bit symbol on any target. Upstream builds the same unit as a
  separate target tagged `nowindows` (`ryu/BUILD:38-49`) and gates it on the
  compiler providing `__uint128_t` (`CMakeLists.txt:31-52`), and
  `ryu/generic_128.h:23` is an unconditional
  `typedef __uint128_t uint128_t;` with `ryu/generic_128.c:70-73` `memcpy`ing a
  `long double` into it. Turning the option on for the whole matrix would make
  it a statement about every 32-bit target at once; leaving it off keeps the
  matrix one honest closure. Nothing in this fork substitutes a stub for it: the
  file that ships is upstream's, unmodified.
* *The Zig side has nothing target-conditional in it.* `zig/root.zig` reaches
  `c.d2s_buffered_n` and friends through the translated header and does no
  arithmetic of its own beyond slice bounds and `std.math.cast` on lengths.
  `tests.zig:35-36` embeds every fixture with `@embedFile`, so the suite reads
  no file at run time and the harness does not have to map a working directory
  for it. The oracles are exact string comparisons against literals transcribed
  from upstream's own gtest cases, plus cross-checks against
  `std.fmt.parseFloat` and `std.fmt`'s float writers — both deterministic for
  IEEE-754 binary32 and binary64, which every platform in the table has. No test
  was added, removed or re-pinned for any of the above.

**Status.** `OBSERVED`, and the section above held. `cross-test` (`CHANGELOG.md`
entry 22) compiled the whole published table for this package twice, once
before and once after the header change of note 15: 44 cells compiled and
20 cells ran the suite in the first run, and all 53 cells compiled in the
second, with 20 cells running 28 tests each. Not one compile error came out of
the 32-bit or big-endian rows — `x86-linux`, `arm-linux`, `armeb-linux`,
`thumb-linux`, `thumbeb-linux`, `riscv32-linux`, `hexagon-linux`,
`aarch64_be-linux`, `s390x-linux`, `powerpc-linux`, `powerpc64le-linux` and the
rest all built. The one failure the matrix produced was not about any of this:
it was note 15. Open item 4 below is unaffected: `-Dgeneric128` still has no
foreign compile.

**Targets bound.** The `HAS_UINT128` / `HAS_64_BIT_INTRINSICS` guards as they
stand at commit `4c0618b0e44f7ef027ebae05d2cc7812048f7c8f`; Zig 0.16.0. Both are
re-read, not recalled, before any of this is relied on again.

---

## 15. The nine red cells were an SDK header, not Ryu

**Condition.** The full-matrix gate of entry 22 translates the aggregate header
for every one of the 53 cells, and `translate.h` includes `ryu/ryu.h`. At commit
`4c0618b0e44f7ef027ebae05d2cc7812048f7c8f` that header reads
`#include <inttypes.h>` at line 24.

**Symptom.** Receipt 33, exit 1: **20 pass, 9 fail, 24 `build_only`**. All nine
failures were the same one, and they were every NetBSD cell in the table —
`aarch64`, `aarch64_be`, `arm`, `armeb`, `mips`, `mipsel`, `powerpc`, `x86`,
`x86_64`:

```
error: translation failure
…/lib/libc/include/generic-netbsd/inttypes.h:93:1: error: unknown type name 'pragma'
…/lib/libc/include/generic-netbsd/inttypes.h:93:1: error: expected ';', found 'an identifier'
…
error: 5 compilation errors
```

**Cause.** NetBSD's `<inttypes.h>` closes its declarations with `__END_DECLS`,
whose replacement list begins with a `_Pragma`, and translate-c reads that
`_Pragma` as ordinary tokens. The header is the SDK's. Nothing in Ryu's own code
is involved: no compiled unit reached that header except through `ryu.h`, and
the 44 non-NetBSD cells that include the same `ryu.h` compiled cleanly against
their own `<inttypes.h>`. So this was a target's libc header meeting a
translator, not a defect in the library and not a defect in this fork.

**Fix.** One line. `ryu/ryu.h:24` includes `<stdint.h>` with an inline change
notice. It supplies `uint32_t`, used in the six `precision` parameters
at `ryu/ryu.h:34-40`. No `PRI*` or `SCN*` macro appears anywhere in the header,
and `uint32_t` is declared by `<stdint.h>` (C99 7.18.1) — the header
`<inttypes.h>` includes in order to reach that same type. No declaration, type,
signature, constant, prototype or algorithm changes, and no prototype is copied
or duplicated: each function is still declared exactly once, inside the
header's own `extern "C"` block. Upstream's bytes for this path are 1360 bytes
hashing to `b7feab0ba1df5e9ef3d602f386592ad152491405e49b408fb21c0e0e9e6bfb16`;
the patched file is 1417 bytes hashing to
`83ed2a4cd2e42cdd351383b5c937e320e47d8e0ea214964a7b8568f974754dae`.

**Why the change is bounded to the translation closure.** Three of the five
compiled units include `ryu/ryu.h` — `ryu/d2s.c:30`, `ryu/f2s.c:21`,
`ryu/d2fixed.c:26`. The two parsers include `ryu/ryu_parse.h` instead
(`ryu/s2d.c:18`, `ryu/s2f.c:18`), which declares no integer type at all, and
each already includes `<stdint.h>` itself (`ryu/s2d.c:22`, `ryu/s2f.c:22`); their
own `<inttypes.h>` blocks sit inside `#ifdef RYU_DEBUG`, and this build defines
no `RYU_DEBUG` (`build.zig:118-120`). So the compiled ABI is upstream's own on
every target, and the header was the only route to the SDK header that this tree
does not need.

**What was deliberately not done.** No fork-authored replacement for
`<inttypes.h>` or for any other libc header ships in this tree, no per-target
conditional exists in `build.zig` (one graph, one root header, no `RYU_*` macro
defined, `build.zig:244-263`), and nothing upstream published was dropped to
make the failure go away. A conditional workaround was rejected rather than
shipped; this line is the whole change, and `UPSTREAM.sha256`, `NOTICE.md` and
`README.zig.md` all name it rather than working around it.

**Bound to.** Any fork that translates a target's libc headers with the pinned
Zig. The lesson is the shape of it: when a matrix gate fails on exactly the
platforms of one OS family, read the path in the diagnostic before reading the
library. A header that a fork never needed in its closure is a portability
limit of the SDK, and the smallest honest fix is to stop pulling it in — not to
patch the SDK, shadow it, or exclude the platform. Two boundaries travel with
it. `<stdint.h>` is C99 7.18.1 and the dialect here is `-std=gnu17`
(`CHANGELOG.md` entry 3), so the replacement is inside the declared language; and
the nine NetBSD cells now compile, which is not the same claim as the nine
running — this host has no NetBSD runtime, so all nine are recorded `build_only`.

**Status.** `OBSERVED` red (receipt 33) and `OBSERVED` closed (receipt 34):
20 pass, 0 fail, 33 `build_only`, 0 partial over all 53 cells, exit 0. The nine
NetBSD cells compile; they are among the 33 `build_only` and no NetBSD test was
executed. Natively on the patched header, receipts 29–31 are exit 0 with 28/28
in both optimize modes, and receipts 35–37 re-ran the same three gates in the
stable round with the same counts. Receipt 38 re-ran the six compile-only
`check` cells of `CHANGELOG.md` entry 15 against the patched header: six for
six, 6/6 steps, exit 0. Current annotated-header receipts 39–42 supersede
those source-sensitive matrix, native and baseline results. The record replay
and fresh materialised package result are driver-owned, under receipt 43.

---

## What is still open

Recorded here and in `CHANGELOG.md` so that nothing is lost. Two items were
open when this file was first written and are closed now:

1. ~~**`build.zig.zon` `.paths` needs `"UPSTREAM.sha256"`.**~~ **Closed.**
   `build.zig.zon:80` lists it beside every other fork record, so a dependent
   who fetches the package receives the fingerprint and the "checkable in an
   unpacked package" claim in `UPSTREAM.md` is true. Note 13.
2. ~~**Consider a `sha256sum -c UPSTREAM.sha256` step in `verify.yml`.**~~
   **Closed, and not merely considered.** The native job runs it first, before
   any build, at `.github/workflows/verify.yml:77-81`, and the record has been
   replayed here (receipt 15, 38 records `OK`).

Two ongoing scope notes and two driver-owned closure records:

3. **The fixture row counts live in `tests.zig`** (`132`, `60`, `134`, `134`,
   `39`, `28`, pinned by an assertion at the end of each replay test). They are
   the one place a truncated or re-transcribed fixture would be caught, and
   they must move together with any upstream re-sync.
4. **`-Dgeneric128` has still never been compiled for a foreign target.** It is
   compiled, installed and exercised from a real C consumer on the native
   target (receipts 14, 26, 27 and 28), and the default graph deliberately does
   not depend on it, so none of the twelve green `check` rows covers it. If a
   later wave wants that coverage it needs its own compile attempts per target —
   upstream tags the unit `nowindows` (`ryu/BUILD:38-49`) and gates its CMake
   target on `__uint128_t` (`CMakeLists.txt:31-52`), so at least one matrix
   target is expected to fail for it and that failure has to be recorded as a
   result, not skipped.

5. **Current source and fetched record integrity are driver-owned.** Receipt
   15 describes the pre-deviation record. Final current-record checks are
   `FORKS.json.cross_test_wave.materialized_packages.ryu` and
   `local://foundation-cross-test-package-regression.json`, not that historical
   green receipt.
6. **The earlier materialised package is historical.** Final filtered fetch,
   in-package integrity and consumer results live under the same driver-owned
   closure. This document deliberately does not quote a current identity:
   its own bytes contribute to the identity. The current six-target
   compile-only baseline is closed by receipt 41, and the full 53-cell
   matrix by receipt 39: 20 Linux cells execute 28 tests each; 33 cells compile
   without an available runtime.