# ryu — IEEE-754 to decimal, from ulfjack/ryu, as a standalone SDK

This repository builds **ulfjack/ryu** at commit
`4c0618b0e44f7ef027ebae05d2cc7812048f7c8f` — upstream's own C sources, from the
`ryu/` directory here — into a native library, and publishes a Zig facade over
upstream's two public headers. Upstream's README is preserved, byte for byte, at
[`README.upstream.md`](README.upstream.md); it is upstream's document and none of
this fork's prose is in it.

No digit this package produces is computed by fork code. Every answer comes from
a call into a compiled upstream translation unit.

| | |
|---|---|
| Upstream | <https://github.com/ulfjack/ryu>, commit `4c0618b0e44f7ef027ebae05d2cc7812048f7c8f` on `master` |
| Upstream version line | `2.0`, at `CMakeLists.txt:2` — upstream's string, not a release this tree claims |
| Package version | `2.0.0-dev.4c0618b` (a SemVer build-metadata suffix cannot hold a commit id, so the prefix rides in the pre-release field) |
| Compiler | Zig **0.16.0**, the real compiler |
| Licence of the native core | `Apache-2.0 OR BSL-1.0` — both texts ship, unmodified |
| Licence of this fork's own files | `Apache-2.0` — [`FORK-LICENSE.md`](FORK-LICENSE.md) |
| Upstream algorithms changed | none |

The sections below are in this order on purpose: what this fork changed in the
native sources, what it changed in the native build, what has actually been run,
and then how to consume the result. The Zig interface has its own document,
[`README.zig.md`](README.zig.md); this one does not duplicate it.

---

## 1. Current native-source deviations

**Exactly one, and it is one line of one upstream header.**

| File | Line | Upstream | Here | Why |
|---|---|---|---|---|
| `ryu/ryu.h` | 24 | `#include <inttypes.h>` | `#include <stdint.h>`, with an inline change notice | The include carries exactly one name into the header, `uint32_t`, used in the six `precision` parameters at `ryu/ryu.h:34-40`. No `PRI*` or `SCN*` macro appears anywhere in it, and `<stdint.h>` declares that same type (C99 7.18.1) — it is the header `<inttypes.h>` includes in order to reach it. |

The reason is load-bearing, not cosmetic. NetBSD's `<inttypes.h>` closes its
declarations with `__END_DECLS`, whose replacement list begins with a
`_Pragma`; the pinned translator reads that `_Pragma` as ordinary tokens —
`unknown type name 'pragma'` — and the platform matrix has nine NetBSD cells,
all of which reached this header through it.

**What did not change.** No declaration, type, signature, constant, prototype,
algorithm or line number; no duplicate of any of them; no upstream C source, no
other header, no test, no licence text, no fixture byte. The header keeps
upstream's copyright block and its per-file Apache-2.0 / Boost dual grant
verbatim (`ryu/ryu.h:1-16`), so the notice travels with the file. Upstream's
bytes for this path are 1360 bytes hashing to
`b7feab0ba1df5e9ef3d602f386592ad152491405e49b408fb21c0e0e9e6bfb16`; this tree's
are 1417 bytes hashing to
`83ed2a4cd2e42cdd351383b5c937e320e47d8e0ea214964a7b8568f974754dae`, and putting
the original include back reproduces upstream's bytes exactly.

That is the whole of the native-source deviation. Two **other** upstream-tracked
paths also differ from the pinned commit, and they are recorded here rather than
left to be discovered, because "the sources are pristine" and "every tracked file
is pristine" are two different claims:

| Path | Nature of the difference |
|---|---|
| `.gitignore` | additive only. Upstream's own list — `bazel-*`, `MODULE.bazel.lock`, `/.eclipse-bin/`, `/project`, `/.lake`, `.vscode/`, `ryu/*.[oa]`, `ryu/tests/*.test` — is kept verbatim; the fork appends `.zig-cache/` and `zig-out/`, each under a comment saying why. No upstream line is changed or removed |
| `README.md` | replaced by this fork's own README, which is what you are reading. Upstream's bytes are preserved, unedited, at `README.upstream.md` and are still hashed there under that name |

Every other upstream-tracked path is byte-identical to the pinned commit. All
three differences appear in `NOTICE.md`, in `UPSTREAM.md` and in the
excluded-paths section of `UPSTREAM.sha256`, so a pinned-commit diff has three
paths to name and this repository has already named all three.

**Every source that is built is built.** `ryu/d2s.c`, `ryu/f2s.c`,
`ryu/d2fixed.c`, `ryu/s2d.c` and `ryu/s2f.c` are compiled on every build;
`ryu/generic_128.c` is the sixth, behind `-Dgeneric128`. No source is dropped,
no compile diagnostic is suppressed and no real dependency is replaced.

## 2. Current native-build deviations

Build-only. No native byte and no declared behaviour is touched.

| Deviation | Upstream | Here | Why |
|---|---|---|---|
| Upstream's experimental parsers are compiled | `CMakeLists.txt:6-18` lists `f2s.c`, `d2s.c` and `d2fixed.c` and nothing else; `CMakeLists.txt:28` installs only `ryu/ryu.h` | `ryu/s2d.c` and `ryu/s2f.c` are compiled too and `ryu/ryu_parse.h` is installed beside `ryu/ryu.h` | The string-to-float direction is real published API (`ryu/ryu_parse.h:24-40`). A fork that dropped it would not be the same library. The parsers are upstream's experimental components and are named as such |
| `generic_128` joins the library | a separate CMake target `generic_128`, installed as its own library (`CMakeLists.txt:37-47`) | `-Dgeneric128` compiles the same unit into the same library and installs its header | One SDK, one library. Off by default, because upstream's own target is gated on the compiler providing `__uint128_t` (`CMakeLists.txt:31-52`) and tagged `nowindows` (`ryu/BUILD:38-49`, "The code does not compile on Windows") |
| The dialect is pinned | upstream compiles with whatever default the toolchain has | exactly one C flag, `-std=gnu17` | Upstream's sources are C99-era and compile unchanged under it. Nothing else is passed, and that is a finding rather than an omission: the core converts a `double` by copying its bits (`ryu/common.h:108-112`) and then works in integer arithmetic on `uint64_t`/`__uint128_t`, so no result depends on how the compiler rounds, contracts or reassociates floating point. `-ffp-contract=off` and its relatives would guard a risk this code does not have |
| Linkage is a choice, not a constant | `add_library` follows `BUILD_SHARED_LIBS`, which CMake defaults to OFF | `-Dlinkage=static` (the default, unchanged) or `-Dlinkage=dynamic` | The static default is this package's pre-existing policy and upstream's CMake default alike, so nothing about a default build moved |
| No system-library mode | — | none, and it is recorded as **not satisfied with a reason** | An installed ryu publishes `ryu/ryu.h` and never publishes `ryu/ryu_parse.h` (`CMakeLists.txt:28`, `:6-18`), so it cannot supply this package's surface. Linking one anyway would mean translating this tree's headers against an ABI of unknown age, which compiles and then misbehaves quietly. See `UPSTREAM.md`, "System-library mode" |

**The shared object carries no ABI number, and that is upstream's shape.** No
soname, no version script and no export list, because upstream publishes none:
`CMakeLists.txt:2` is `project(ryu VERSION 2.0)` — the library's version line,
not an ABI number — the target carries no `VERSION` or `SOVERSION`, and neither
public header declares a visibility or dllexport macro. Every symbol is therefore
exported by default. Nothing here invents a versioning policy upstream does not
have, and no document in this repository states an ABI number for this library.

### History

Dated history for every one of these, with the receipt each one was observed
with, is in [`CHANGELOG.md`](CHANGELOG.md) — thirty-five numbered entries,
never renumbered — and the reasoning, including the work that went wrong, is in
[`FORK-NOTES.md`](FORK-NOTES.md). The one-line header deviation is entries 23
and 25; the README relocation is entry 28 and `FORK-NOTES.md` note 16; the nine
red NetBSD cells the header answers are `FORK-NOTES.md` note 15 with
`CHANGELOG.md` entry 24.

## 3. Current build / run / test matrix

Three kinds of statement are separated here on purpose. **Historical** rows
were run by the workspace driver on an earlier state of this tree and are
evidence for the *shape* of the gate, not for the tree as it stands.
**Current** rows were run on this tree and say what they printed. **Pending**
rows are what this wave changed and that no gate has looked at yet.

### 3a. Historical observed evidence

Run by the driver with the pinned 0.16.0 compiler, `--summary all`, on the tree as
it stood with the current one-line header deviation in place and before this
wave's changes. Every count below is the count of the run named in its row.

| Gate | Observed result | Receipt |
|---|---|---|
| `test`, `smoke`, `install` — Debug | exit 0 — `Build Summary: 11/11 steps succeeded; 28/28 tests passed`, install prefix outside the repository | `local://foundation-cross-test-final-ryu-native-Debug.log` |
| `test`, `smoke` — ReleaseSafe | exit 0 — `Build Summary: 9/9 steps succeeded; 28/28 tests passed` | `local://foundation-cross-test-final-ryu-native-ReleaseSafe.log` |
| `smoke`, standalone | exit 0; every printed answer matched its published expectation, including both signed zeroes, both infinities, `NaN` shortest vs `nan` fixed, `5E-324`, `DBL_MAX`, `DBL_MIN`, the subnormal float `1E-45`, the ties `2.5 → 2` and `3.5 → 4`, the carry `9.9999 → 10.000`, and the refusals `InputTooLong` and `MalformedInput` | the Debug log above |
| source `consumer/` | exit 0 — `Build Summary: 6/6 steps succeeded`. Native, through `.path = ".."`; not an installed-C-artifact proof | `local://foundation-cross-test-final-ryu-native-consumer.log` |
| `check`, six cross targets | exit 0 for all six, compile-only, default five-unit graph | `local://foundation-cross-test-final-baseline.json`, `cells[]` where `sdk: ryu` |
| `cross-test`, full 53-cell matrix | exit 0 — **20 pass, 0 fail, 33 `build_only`, 0 partial**, `run_id` `20261002-080415-53964-27076`. All 53 cells compiled; the 20 with a runner each ran the full 28-test suite, 560 executed tests. The 33 without a runtime are compile coverage and are never counted as passes — **all nine NetBSD cells are among them** | `local://foundation-cross-test-final-current-ryu.json` and its 53 per-cell logs |
| `cross-test --list` | exit 0, 53 targets; `--no-profile --list` names the same 53, so `cross-test.profile.sh` restricts the table to none of them | `local://foundation-cross-test-profile-ryu-list_profile.log` |
| installed C surface | exit 0, **before** the header deviation: `<ryu/ryu.h>` and `<ryu/ryu_parse.h>` resolve and link on their own against the installed archive; the four `malloc`-returning formatters are used and each result freed; both parser widths in both the `_n` and the `strlen` form; the published roundings `0.125 → 0.12`, `0.375 → 0.38`, `2.5 → 2`, `3.5 → 4`, and three refused inputs each leaving its sentinel untouched. **No run of this gate against the patched header is recorded** | `local://foundation-expansion-ryu-installed-C-surface-isolated-cache-191.log` |
| `-Dgeneric128`, native build and installed C surface | exit 0, **before** the header deviation. The installed `ryu/ryu_generic_128.h` and the archive agree on `float`, `double` and `long double` `1.25 → 1.25E0`; on an independent IEEE binary128 built as `16383 << 112` or-ed with `1 << 110`, positive and with the sign bit set; and on both signed zeroes | `local://foundation-expansion-ryu-generic128-C-surface-corrected-227.log` |

`build_only` is a platform that compiled and could not be executed on that host.
It is never a pass, and this SDK's platform matrix never converts one into one.

### 3b. This wave: what the driver observed, and what is still pending

The first two rows are what this package's own gates printed on **this** tree on
2026-10-04, and they are kept exactly as they printed, counts included. Every
row after them was run by the workspace driver on this same tree in five later
waves, each named by its epoch: the two default-configuration 8-cell waves of
2026-10-04, the full-53-target run and the compile-only whole-graph baseline,
and the two `-Dgeneric128=true` waves. A count is always the count of the run
named in its row, and a receipt is named by its epoch id plus its per-SDK
receipt file so the workspace root ledger can be joined on it.

**Two numbers, never one.** Every wave row carries the `zig build` command's own
exit code and summary line *and* the driver's strict verdict, and they do not
have to agree: `skipped-tests` is not `pass`, so a cell whose command exits 0
can still leave the driver's `not_passed` column non-zero and its wrapper exit
1. That is not a contradiction and neither number is the other one. The same
holds for `build_only`, which is compile coverage and never a pass.

**The headline result of this wave is sixteen partials, not sixteen passes.**
With `-Dgeneric128=true` the driver ran sixteen cells — eight native and eight
runtime-loaded, Debug / ReleaseSafe / ReleaseFast / ReleaseSmall × static /
dynamic. **All sixteen built and ran with zero failures**, each printing
`35/36 tests passed (1 skipped)` because of exactly one skip, always the same
site, `tests.zig:1172`, guarded `if (comptime ryu.generic128.LongDouble != f80)
return error.SkipZigTest;`. That skip is an opaque C `long double` ABI guard:
the translated C type is not the x86 `f80` spelling Zig uses, so the test
declines to compare across an ABI it cannot see through, and the receipt
attributes it `"bucket": "abi_guard"`, `"abi_guard_sites": 1`,
`"other_sites": 0`, `"feature_off_sites_could_fire": false`, `"partial": true`.
It is a bounded, attributed partial — **not** 36/36, and not green. What these
waves do not prove is stated in each row and in the pending table below: no
foreign target compiles the optional sixth unit, and no provider this tree did
not build has ever been loaded.

| Gate | Observed result | Receipt |
|---|---|---|
| `test smoke install -Druntime=false`, both linkages, four optimize modes | **exit 0 for all eight** — `Build Summary: 26/26 steps succeeded; 33/37 tests passed (4 skipped)` in each. Each configure line names its own configuration (`shared object, libryu.so (upstream publishes no soname)` or `static archive (default)`, then `linked dispatch (direct calls)`), and `install` wrote the whole closure into a `--prefix` outside this repository with no missing-file step | `local://foundation-current-native-index.json`, rows `ryu-current-native-{dynamic,static}-{Debug,ReleaseSafe,ReleaseFast,ReleaseSmall}` |
| `test smoke install -Druntime=true`, both linkages, four optimize modes, provider named by `RYU_PROVIDER` | **exit 1 for all eight** — `Build Summary: 25/27 steps succeeded (1 failed); 0/37 tests passed (37 crashed)` in each. The build, the dispatch generation, `smoke` and `install` all succeeded: `smoke` resolved the provider it was given and printed its checked answers in every mode. The `test` step is the only step that failed, and for one reason: `tests.zig` requires a **second** variable, `RYU_TEST_PROVIDER`, which those runs did not export, so every test aborts on that precondition instead of skipping itself. An unset variable is not a finding about the route. A replay needs **both** `RYU_PROVIDER` and `RYU_TEST_PROVIDER` exported for the whole `zig build` invocation — a build cannot inject a path into a run step's environment | `local://foundation-current-failures-ryu.json`, same eight label pairs |
| the same loaded route with the provider named by **basename** through the platform loader (`--system <name>`, that is `LoadSource.system`) | **Not covered above, and not claimed.** The 2026-10-04 runs resolved a provider named by **absolute path**, which is what `RYU_PROVIDER` names; nothing in this repository has yet named one by basename, and no row above should be read as covering it | — |
| an **external** provider — an ryu this tree did not build | **A boundary, not coverage: no independent external provider was accepted on this host.** The host library inventory contains no entry whose name contains `ryu`, so there is no external ryu to load here at all; the only provider that can satisfy this SDK's sixteen required entry points is this tree's own source-built `libryu.so`. The route wave says so in its own numbers — `external_successes_observed: 0`, `own_routes_counted_as_external: []`, `refusals_observed: 7`, `own_provider_route_passed: true`. Every external candidate was an **expected refusal**, a library that does not export the surface, including the wrong-family object that is present, `/lib64/libdouble-conversion.so.3`, which opens and is then refused for missing symbols. A refusal shows the loader discriminates; it is not this SDK covered by anything it did not build | epoch `20261004T232439Z`, `ryu-index.json`; `acceptance-plans/ryu.json`, `boundaries[]` and `expected_rejections[]` |
| the same two routes in the **default** configuration (`-Dgeneric128` off), native, both linkages × four optimize modes | **exit 0 in all eight, and a partial in every one.** Each cell prints `Build Summary: 26/26 steps succeeded; 32/36 tests passed (4 skipped)` and the driver records `status: skipped-tests`, never `pass`: the four skips are the generic-128 tests, which cannot run in a default build because the option is off, so this wave does not exercise the optional unit at all. `fail: 0`, `not_passed: 8`, wrapper exit 1 | epoch `20261004T233628757747Z-69351`, rows `ryu-native-final-{static,dynamic}-{Debug,ReleaseSafe,ReleaseFast,ReleaseSmall}` |
| the same **default** configuration on the runtime-loaded route, provider named by **both** `RYU_PROVIDER` and `RYU_TEST_PROVIDER` | **exit 0 in all eight, and a partial in every one**: `Build Summary: 27/27 steps succeeded; 32/36 tests passed (4 skipped)`, `status: skipped-tests` throughout. This is the replay the row above needed — with both variables exported the loaded `test` step runs to completion instead of aborting on its precondition — and the provider is this tree's own `libryu.so` (`kind: own`). The four skips are the same feature-off ones, not a failure of the route | epoch `20261004T232823091897Z-23133`, rows `ryu-loaded-final-{static,dynamic}-{Debug,ReleaseSafe,ReleaseFast,ReleaseSmall}` |
| **`-Dgeneric128=true`**, native, both linkages × four optimize modes | **Eight cells: exit 0 in all eight, zero failures, one skip each — and all eight partial.** Command `zig build test smoke install -Doptimize=<mode> -Dlinkage=<static\|dynamic> -Druntime=false -Dgeneric128=true -j8 --summary all`; each prints `Build Summary: 26/26 steps succeeded; 35/36 tests passed (1 skipped)`, `smoke` ends `every answer matched`, and `install` writes `include/ryu/ryu_generic_128.h` into its approved prefix (`generic128_header_installed: true`). The one skip is always `tests.zig:1172`, and `skip_attribution` reads `expected_skipped: 1`, `reachable_sites: 1`, `other_sites: 0`, `bucket: abi_guard`, `partial: true`. The compiled-input closure held (`identical: true`). `totals`: `executed: 8`, `fail: 0`, `pass: 0`, `skipped_tests_abi_guard: 8`, `not_passed: 8`, wrapper exit 1 | epoch `20261005T014407332917Z-66097-ryu-native`, `run.json` and the eight `ryu-native-generic128-*` per-cell receipts |
| **`-Dgeneric128=true`**, runtime-loaded, the same eight configurations, provider this tree's own `libryu.so` from the wave above's dynamic prefixes | **The other eight cells: the same shape, same one skip, same attribution.** `exit 0` in all eight, `Build Summary: 27/27 steps succeeded; 35/36 tests passed (1 skipped)` in each, `status: skipped-tests`, `bucket: abi_guard`, `partial: true`, `generic128_header_installed: true`, closure `identical: true`; `totals` again `fail: 0`, `pass: 0`, `skipped_tests_abi_guard: 8`, `not_passed: 8`, wrapper exit 1. Both provider variables name one shared object per mode | epoch `20261005T015048544771Z-69523-ryu-loaded`, `run.json` and the eight `ryu-loaded-generic128-*` per-cell receipts |
| Gate | State |
|---|---|
| `-Dlinkage=dynamic` — shared native delivery, all four optimize modes | **Observed on this tree, exit 0 in all four modes** — the first block above; the shared object those runs installed is the artifact this option selects, and each configure line names it. A target that cannot carry one **refuses** the option rather than falling back to an archive: `wasm32-wasi` stops at configure time with a sentence naming the target and saying `No static substitution is made` (`sharedObjectRefusal` in `build.zig`), and inside `check` that same refusal becomes an explicit failing step rather than a silent archive (`addTargetCheck` in `build.zig`). That refusal is `SOURCE-CONFIRMED`; no `wasm32-wasi` row has been run |
| The installed closure: library, public headers, `lib/pkgconfig/ryu.pc`, `share/licenses/ryu/` | **Partly observed.** Every gate in the block above ran `install` into an approved prefix outside this repository and no install step failed, which is the build graph writing the artifact, the headers (`build.zig:535-540`), `lib/pkgconfig/ryu.pc` (`build.zig:957-959`) and the licence records (`build.zig:702-704`). What is still **PENDING-VERIFICATION** is the assertion half: `package.nix` re-checks that closure and fails the derivation if anything promised is missing, and no `nix` command has been run in this tree |
| `-Dlinkage=static` — re-run of the historical native rows after this wave's build-graph changes | **Observed on this tree, exit 0 in all four modes** — the static half of the first block above, `26/26 steps succeeded` with the default five-unit closure. The historical rows in § 3a stay as they were observed |
| The six-target `check` matrix after this wave's changes | **Observed, compile-only, exit 0, `failed: false`.** The whole-graph `check` step in one invocation, no `-Dtarget`, covering the six required triples: `20261005T014547Z-797a73f2`, receipt `baseline-ryu-check-2026-10-05T01-45-53.904710+00-00.json`. It records `runtime_pass_claimed: false` under **every** exit code, so it is compile evidence and nothing about runtime. It is still the **default five-unit graph** and says nothing about `-Dgeneric128` |
| The 53-cell `cross-test` matrix after this wave's changes | **Observed on this tree, exit 0 — 53 targets: 20 runtime PASS, 33 `build_only`, 0 fail, 0 partial**, driver receipt `ryu-53-target-8.json` in epoch `20261004T221720228710Z-45046`, run with `--jobs 8 --build-jobs 8`, `source_unchanged: true`, `jobs_honoured: true`. **A green "53 targets built" run is not 53 runtime passes.** The 33 cells without a runner compiled and were not executed; `build_only` is never a pass. Across the whole 23-SDK cohort those 53 targets are 1219 cells: 366 runtime PASS, 687 build-only, 102 build-fail, 64 runtime-fail — so "all 53 passed" is a statement about no run in this cohort |
| The runtime-loaded route: startup, the pre-initialization call, failure and refusal, explicit retry, idempotence, provider change, and the allocator check at load time | **The route exists and is `SOURCE-CONFIRMED` throughout**: `-Druntime=true` is declared in `build.zig`, `runtime/graph.zig` builds the generated dispatch, `zig/root.zig` publishes `runtime_loaded`, `load`, `loadedSource`, `LoadSource` and `LoadError`, and `smoke.zig`, `tests.zig` and `consumer/src/main.zig` all drive it. **Observed on this tree, and partial rather than green**: with **both** `RYU_PROVIDER` and `RYU_TEST_PROVIDER` exported, the loaded `test` step now runs to completion in all eight configurations — four skips each in the default configuration, one attributed ABI skip each under `-Dgeneric128=true` — so the 2026-10-04 red block above is superseded for the `test` step and kept as history. **Still `PENDING-VERIFICATION`**: any provider this tree did not build — none exists on this host — and therefore every claim that depends on one |
| Installed C consumers and fetched, filtered Zig consumers against the current `.paths` | **PENDING-VERIFICATION.** The historical materialised-package rows are for a tree whose bytes have since moved, and are recorded in `README.zig.md` under "Verification status" |
| `sha256sum -c UPSTREAM.sha256`, in the checkout | **observed 2026-10-04: 38 records, 38 `OK`, exit 0.** The record went red mid-wave when the build role was still editing `translate.h`, and the digest was deliberately not refreshed over a file in flight. It moved once that role declared the file final, with the change attributed in `UPSTREAM.sha256` and `CHANGELOG.md` entry 32: `translate.h` is fork-authored, its change was comment-only, and no Group A–E digest moved. An integrity-record replay, not a build, test or matrix gate |
| the same record **inside a fetched, filtered copy** | **PENDING-VERIFICATION.** A checkout can hold a file the manifest does not list, so the in-checkout replay does not show that `README.upstream.md` survives `.paths`. `build.zig.zon` now lists it; running the check inside a fetched copy is what would prove it |
| The Nix derivations: `static`, `shared`, their install layouts and their output dependency records | **PENDING-VERIFICATION.** `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml` and `.envrc` landed in this wave; no `nix` or `devenv` command has been run in it |
| The devenv shell entering cleanly and cheaply | **PENDING-VERIFICATION.** Same |
| `check -Dgeneric128=true` for any target | **NOT RUN, and still not.** The optional sixth unit has never been compiled for a foreign target. Upstream tags it `nowindows` and gates its CMake target on `__uint128_t`, so a matrix result for it would be a finding rather than a formality. The green `check` rows above are the **default five-unit graph** and say nothing about it |
| `.github/workflows/verify.yml` | **Whole CI never executed.** One excerpt of it — the one-line native include reversal — was run locally and is what § 1 quotes |
| system mode | **Not applicable.** There is no system mode to run; see § 2 |

The driver owns the result fields. Nothing in this repository moves one.

## 4. Consuming it

### 4a. From Zig, as a dependency

```toml
# your build.zig.zon
.dependencies = .{
    .ryu = .{ .url = "<this repository>", .hash = "<the hash your fetch prints>" },
},
```

```zig
// your build.zig
const ryu = b.dependency("ryu", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("ryu", ryu.module("ryu"));
```

To reach Ryu through the loader instead of the link line, ask the dependency
for that configuration and name the provider before the first call:

```zig
const ryu = b.dependency("ryu", .{ .target = target, .optimize = optimize, .runtime = true });
exe.root_module.addImport("ryu", ryu.module("ryu"));
```

```zig
// your main, before anything reaches upstream
if (comptime ryu.runtime_loaded) try ryu.load(.{ .path = "/path/to/libryu.so" });
```

The module then carries no archive, and `dep.module("c")` does not resolve in
that configuration — the dispatch already holds the one translation instance.
`README.zig.md` documents the route, the failure modes and the evidence.

In the default linked configuration, `b.dependency("ryu", …).module("c")` is the
raw route: the same translated
declarations with no archive attached, which is what you want if you are already
linking the native library yourself. The facade is documented in full, with its
buffer contracts, precision bounds, error set and output spellings, in
[`README.zig.md`](README.zig.md).

### 4b. From C, against an installed tree

`zig build install --prefix <dir>` installs the library, the public headers and
the aggregate header:

```
<dir>/include/ryu/ryu.h            upstream's stable conversion API
<dir>/include/ryu/ryu_parse.h      upstream's experimental parsers
<dir>/include/translate.h          the aggregate of the two, as one include
<dir>/lib/libryu.a                 or libryu.so / libryu.dylib under -Dlinkage=dynamic
```

`translate.h` is the whole header closure: it includes `ryu/ryu.h` and
`ryu/ryu_parse.h` and declares nothing of its own. Under `-Dgeneric128`,
`include/ryu/ryu_generic_128.h` is installed beside them.

This is the complete set of native functions the selected headers declare, and a
raw consumer reaches all of them:

| Header | Functions | Contract |
|---|---|---|
| `ryu/ryu.h` | `d2s_buffered_n`, `d2s_buffered`, `d2s`, `f2s_buffered_n`, `f2s_buffered`, `f2s`, `d2fixed_buffered_n`, `d2fixed_buffered`, `d2fixed`, `d2exp_buffered_n`, `d2exp_buffered`, `d2exp` | `*_buffered_n` writes exactly *N* bytes and does **not** terminate; `*_buffered` writes *N* bytes plus `'\0'` at `[N]`; the four `char*`-returning forms allocate with libc `malloc` (`ryu/d2s.c:506`, `ryu/f2s.c:342`, `ryu/d2fixed.c:558`, `ryu/d2fixed.c:815`), terminate, and return the allocated pointer itself, so the caller frees it with libc `free` |
| `ryu/ryu_parse.h` | `s2d_n`, `s2d`, `s2f_n`, `s2f` | return `enum Status` (`SUCCESS`, `INPUT_TOO_SHORT`, `INPUT_TOO_LONG`, `MALFORMED_INPUT`). Experimental, and upstream says so: up to 17 nonzero digits, not all formats, use at your own risk (`ryu/ryu_parse.h:25-27`) |
| `ryu/ryu_generic_128.h` — installed and translated with `-Dgeneric128` | `float_to_fd128`, `double_to_fd128`, `long_double_to_fd128`, `generic_binary_to_decimal`, `generic_to_chars` | needs `__uint128_t`; upstream limits its own claim to x86 with specific compilers (`ryu/ryu_generic_128.h:50-51`). Upstream passes `explicitLeadingBit = true` only for `long double` (`ryu/generic_128.c:80`) and `false` everywhere else. `translate.h` includes this header behind `RYU_TRANSLATE_GENERIC_128`, which `build.zig` defines only when the option is set, so a `-Dgeneric128` build translates **twenty-one** entry points rather than sixteen and publishes the five to Zig as well as to C |

The Zig facade calls the allocation-free subset — `d2s_buffered_n`,
`f2s_buffered_n`, `d2fixed_buffered_n`, `d2exp_buffered_n`, `s2d_n`, `s2f_n` —
because it returns subslices of buffers the caller owns. **The `char*`-returning
four are part of the native surface and stay part of it**: any dispatch table,
linked or runtime-loaded, covers all sixteen functions the selected headers
declare — twenty-one with `-Dgeneric128` — and crossing into libc
`malloc`/`free` is a property those four carry rather than something a route
may quietly narrow. `README.zig.md` records the same enumeration against the
Zig side, and against the Zig surface as well: the four `format*Owned`
functions call those four upstream entry points on purpose, and what they
return must be released with the C library's `free`
(`OwnedString.deinit`), never with a Zig allocator.

### 4c. Building here

```
zig build                      # build the C library and compile the smoke example
zig build test                 # run the behavioural tests
zig build smoke                # run the deterministic smoke example
zig build check                # compile for the six-target matrix, running nothing
zig build install --prefix DIR # install the library and its public headers
zig build -Dlinkage=dynamic    # the shared variant
zig build -Druntime=true       # the runtime-loaded route: no archive linked, one explicit ryu.load
zig build -Dgeneric128=true    # upstream's experimental generic 128-bit converter
cross-test                     # the full published platform matrix
```

`check` compiles `tests.zig` and `smoke.zig` for every target in the matrix
rather than reflecting over the module, because Zig analyses a function body only
when something calls it. That is a standing obligation on those two files, not on
the build script: every public declaration in `zig/root.zig` needs a call site in
one of them or `check` stops covering it. A passing `check` is compile evidence,
never a claim that a foreign binary ran.

### 4d. Nix, and the development environment

Canonical development is **devenv**:

```
devenv shell        # or: direnv allow, with the .envrc in this directory
```

The shell carries tools only — the Zig compiler, `pkg-config`, `make`, `git` —
and deliberately does **not** carry this SDK, because entering a shell must not
require building the library you came to work on. `devenv tasks` names the
supported entry points: `sdk:build`, `sdk:test`, `sdk:smoke`, `sdk:check`,
`sdk:install`, `sdk:matrix`.

Each of those six runs from this SDK's own directory and carries this
workspace's three flags — `-j8`, an explicit `--cache-dir`, `--summary all` —
with that cache at `$ZIG_LOCAL_CACHE_DIR/ryu`. `sdk:build` and `sdk:install`
also install to `$ZIG_LOCAL_CACHE_DIR/ryu-prefix`, so a canonical run writes
neither `.zig-cache/` nor `zig-out/` into this repository. Each body places the
cache itself, before the compiler runs, and not only `enterShell`: because
`devenv tasks run --mode single` never reaches the shell hook. So
`ZIG_LOCAL_CACHE_DIR` is the caller's if one was exported, else
`$XDG_CACHE_HOME`, else `$TMPDIR`, and a task with none of the three set stops
rather than choosing a location. There is no `/tmp` default and no host path.
`sdk:matrix` runs the same `cross-test` this directory's
`cross-test.profile.sh` configures, with `--jobs 8 --build-jobs 8`.

The packaged forms are lazy `devenv` outputs, so nothing is realised until you
ask for one:

```
devenv build outputs.static     # the SDK's existing linkage policy
devenv build outputs.shared     # -Dlinkage=dynamic
nix build path:.#static         # the same derivation through the flake
nix build path:.#shared
```

`package.nix` is one source-only derivation consumed by both `devenv.nix` and
`flake.nix`. It imports no sibling, fetches nothing at build time, names no host
path, and calls `zig build install` rather than placing `include/` and `lib/` by
hand — the build graph owns every installed file, including the public headers,
`lib/pkgconfig/ryu.pc` and the licence record under `share/licenses/ryu/`. The
derivation asserts that closure afterwards and fails the build if anything
promised is missing, so a partial install cannot ship quietly. `Libs.private` in
`ryu.pc` is `-lc` and nothing else: the core calls `malloc`, `free`, `memcpy`
and `strlen`, and uses no `libm`, `libdl` or threading symbol.

**The lock, answered from this tree rather than from habit.** This directory
ships `flake.lock`, and it pins exactly the nixpkgs rev `flake.nix` names
(`c7def046b9a883d46974757852106483d741586f`), so a flake build here has a locked
input and does not have to write one; `path:.` is only needed to read the flake
from somewhere that is not a checkout. There is no `devenv.lock`: this
repository pins that environment in `devenv.yaml` instead, and none is invented
for it. One thing about the lock is a manifest fact rather than a Nix one, and
it is recorded rather than assumed either way: `flake.lock` is **not** listed in
`build.zig.zon` `.paths`, so a dependent who fetches this package as a Zig
dependency receives `flake.nix` without the lock beside it.

Two evaluation guards in `flake.nix` cover failures that are silent rather than
loud. The compiler is asserted at `0.16.0`, matching `build.zig.zon`'s
`minimum_zig_version`, so a future nixpkgs cannot repoint the `0.16` alias at
something else. And `stdenv.hostPlatform.system` is asserted equal to
`stdenv.buildPlatform.system`, because `zig build` runs with no `-Dtarget` and
resolves the host: Nix cross-compilation would install the build machine's
native library under the host's name. Native remote builders stay valid, which
is why the guard compares platforms rather than naming a system.

The derivation does not run the behavioural suite: those gates are recorded with
receipts elsewhere, and a package build that silently ran `zig build test` would
make an unowned gate look owned.

**No closure is claimed to be wholly static.** The static variant is a static
`libryu.a` plus a C-runtime dependency; that is the whole of it.

## 5. Everything else

| File | What it is |
|---|---|
| [`README.upstream.md`](README.upstream.md) | upstream's README, byte for byte. Not fork prose |
| [`README.zig.md`](README.zig.md) | the Zig interface in full: routes, API, buffer contracts, precision bounds, error set, output spellings, build modes, verification status, testing approach, integrity |
| [`NOTICE.md`](NOTICE.md) | upstream's per-path grants, the six `third_party/` works under six sets of terms, the Apache-2.0 obligations, and every file this fork changed |
| [`FORK-LICENSE.md`](FORK-LICENSE.md) | the grant for the files this fork authored, the owner authorization behind it, and the paths it covers and excludes |
| [`UPSTREAM.md`](UPSTREAM.md) | the pin, the archive receipt, the import mechanism, the system-mode argument, and what is shipped unmodified |
| [`UPSTREAM.sha256`](UPSTREAM.sha256) | 38 SHA-256 records over the bytes this package compiles, installs, tests against or publishes terms for. Replay with `sha256sum -c UPSTREAM.sha256` from the repository root |
| [`CHANGELOG.md`](CHANGELOG.md) | 35 numbered fork-only divergences with their receipts |
| [`FORK-NOTES.md`](FORK-NOTES.md) | what went wrong, and what was decided, in a shape a later wave can reuse |
| [`LICENSE-Apache2`](LICENSE-Apache2), [`LICENSE-Boost`](LICENSE-Boost) | upstream's two alternative grants, shipped whole and unedited |

Upstream's Java port (`src/`), its Lean 4 port (`lean/`), the table generators
(`scripts/`) and the six vendored `third_party/` corpora are carried in this
tree for provenance and audit. This package compiles none of them, links none of
them, and regenerates no table. `UPSTREAM.md` says what each one is and under
which terms.
