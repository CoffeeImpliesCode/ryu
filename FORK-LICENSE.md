# Fork licence scope

Upstream's terms for its own code are in `NOTICE.md` and are unchanged. This file records the separate grant for fork-authored files and regions only.

## Grant

| Field | Value |
|---|---|
| SPDX identifier | `Apache-2.0` |
| Grant text | `LICENSE-Apache2` in this repository, shipped whole and unedited |
| Text digest | `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4` (`UPSTREAM.sha256`, Group D) |

The owner authorized, for this repository and this wave, that fork-authored additions carry a stated licence chosen per project and matched to the project's primary upstream terms where appropriate.

No individual copyright holder is named for these additions, and none is invented here. Upstream's authors are Ulf Adams and the contributors listed in `CONTRIBUTORS`; `NOTICE.md` records their attribution. The files below are not theirs and are not attributed to them anywhere in this repository. Copyright in the fork-authored files is held by whoever owns this fork.

## Upstream alternatives

Upstream states that its code outside `third_party/` is under Apache-2.0 and offers Boost Software License 1.0 as an alternative for files in `ryu/` (`README.upstream.md`). This fork's additions carry Apache-2.0; they do not change either upstream grant. A downstream may use `ryu/` under BSL-1.0 or Apache-2.0 while using these additions under Apache-2.0, or use the whole tree under Apache-2.0.

## Covered files

This grant covers every file written by the fork, including fork-authored regions in mixed files:

| Path | Fork-authored content |
|---|---|
| `build.zig`, `build.zig.zon` | Zig build graph and package manifest |
| `translate.h` | Aggregate header including upstream's two public headers; it declares nothing of its own |
| `zig/root.zig` | Zig facade over the translated surface |
| `runtime/` | Runtime-loading core and generated dispatch, when that work lands |
| `tests.zig`, `smoke.zig` | Behavioural suite and deterministic example |
| `testdata/*.txt` | Six transcribed fixtures |
| `consumer/` | External consumer package |
| `cross-test.profile.sh` | `cross-test` harness settings |
| `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` | Standalone Nix and devenv packaging |
| `README.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `FORK-LICENSE.md` | Fork documentation, provenance, and integrity records |

The fork adds two lines to upstream's `.gitignore`: `.zig-cache/` and `zig-out/`, each under a comment. Those lines are covered by this grant; every upstream-written line remains under upstream's Apache-2.0 and is unchanged.

## Excluded files and terms

This grant does not cover `LICENSE-Apache2`, `LICENSE-Boost`, `CONTRIBUTORS`, `README.upstream.md`, `ryu/`, `src/`, `scripts/`, `lean/`, `third_party/`, `CMakeLists.txt`, `MODULE.bazel`, `.bazelrc`, `.bazelversion`, `.classpath`, `run_benchmark_linux.sh`, `run_benchmark.bat`, or other upstream-tracked bytes. These retain their own per-path grants; `NOTICE.md` records them. `third_party/` contains six separate works under six sets of terms, and `ryu/` retains upstream's BSL-1.0 alternative.

The §3 patent grant terminates, for **You**, the licences granted to You for the
Work on the date You file patent litigation alleging that the Work or an
incorporated Contribution infringes a patent.
