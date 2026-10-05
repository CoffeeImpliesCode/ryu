# FORK-LICENSE.md — the licence of this fork's own additions

Upstream's terms for the code it wrote are in `NOTICE.md` and are unchanged by
anything in this file. This file records exactly one thing: the grant that
applies to the files **this fork authored**, which upstream's own grant does not
reach.

## The grant

| | |
|---|---|
| SPDX identifier | `Apache-2.0` |
| Grant text | `LICENSE-Apache2` in this repository, already shipped whole and unedited |
| Text digest | `c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4` (`UPSTREAM.sha256`, Group D) |
| Basis | the repository owner's direct authorization for a per-project licence on fork-authored additions, matching this project's primary upstream term |

## The authorization

The owner authorized, for this repository and this wave, that fork-authored
additions carry a stated licence chosen per project and matched to the project's
primary upstream terms where appropriate. The record of that decision is the
workspace contract `local://foundation-contract-implementation.md` ("Licence
authorization") and `foundation-libs/AGENTS.md` §8. It is a decision by the
owner of this fork. It is not a permission from Ulf Adams or from any other
upstream contributor, and it does not need to be: no upstream term covers a file
upstream did not write.

**No individual copyright holder is named for these additions, and none is
invented here.** Upstream's authors are Ulf Adams and the contributors listed in
`CONTRIBUTORS` (`NOTICE.md`, "Upstream work"); the files below are not theirs and
are not attributed to them anywhere in this repository. Copyright in the
fork-authored files is held by whoever owns this fork.

## Why Apache-2.0 and not Boost-1.0

This project's primary upstream term is Apache-2.0: upstream's own prose grants
"all code outside of third_party/" under the Apache License 2.0 and offers the
Boost Software License 1.0 as an **alternative for the files in the `ryu/`
directory** (`README.upstream.md:35-38`, the relocated upstream README). The
single licensed surface of this package is the compiled `ryu/` core, so its
primary term is the one the fork's own additions match.

Choosing Apache-2.0 is also the only choice that keeps the Apache obligation
machinery intact for the whole tree: §4's change-statement and `NOTICE`
obligations attach to the one-file native deviation (`ryu/ryu.h:24`) and to
these additions at the same time, instead of splitting the tree between two
licences with different notice duties.

**The alternative is retained, not consumed.** Nothing here removes a
downstream's choice of Boost-1.0 for `ryu/`. A downstream may take:

* `ryu/` under **BSL-1.0** (or Apache-2.0) as upstream grants, and this fork's
  additions under Apache-2.0 — a mixed tree, which is what the choice produces;
* the whole tree under Apache-2.0, treating the two Apache-2.0 grants as
  compatible and the `ryu/` Boost alternative as unexercised.

Both texts stay in the repository either way. `LICENSE-Boost` is shipped, is not
edited, and is checked by the provenance job in
`.github/workflows/verify.yml` precisely so a later edit cannot quietly reduce
the shipped alternatives to one.

## What the grant covers

Every file in this repository that this fork wrote, in new files and in new
regions:

| Path | What it is |
|---|---|
| `build.zig`, `build.zig.zon` | the Zig build graph and package manifest |
| `translate.h` | the aggregate header that includes upstream's two public headers and declares nothing of its own |
| `zig/root.zig` | the Zig facade over the translated surface |
| `runtime/` | the runtime-loading core and this library's generated dispatch, when that work lands |
| `tests.zig`, `smoke.zig` | the behavioural suite and the deterministic example |
| `testdata/*.txt` | the six transcribed fixtures |
| `consumer/` | the external consumer package |
| `cross-test.profile.sh` | `cross-test` harness settings |
| `.github/workflows/verify.yml` | this fork's own verification workflow |
| `package.nix`, `flake.nix`, `devenv.nix`, `devenv.yaml`, `.envrc` | the standalone Nix and devenv packaging |
| `README.md`, `README.zig.md`, `CHANGELOG.md`, `FORK-NOTES.md`, `UPSTREAM.md`, `UPSTREAM.sha256`, `NOTICE.md`, `FORK-LICENSE.md` | the fork's documentation, provenance and integrity records |

One partial overlap is called out rather than left to inference: the fork appends
two lines to upstream's `.gitignore` (`.zig-cache/`, `zig-out/`, each under a
comment). Those two lines are fork-authored and fall under this grant; every line
upstream wrote in that file stays under upstream's Apache-2.0, and no upstream
line is changed or removed.

## What the grant does not do

* It does not grant anything upstream did not already grant, and it narrows no
  upstream alternative.
* It does not cover `LICENSE-Apache2`, `LICENSE-Boost`, `CONTRIBUTORS`,
  `README.upstream.md`, `ryu/`, `src/`, `scripts/`, `lean/`, `third_party/`,
  `CMakeLists.txt`, `MODULE.bazel`, `.bazelrc`, `.bazelversion`, `.classpath`,
  `run_benchmark_linux.sh`, `run_benchmark.bat`,
  `.github/workflows/presubmit.yml` or any other upstream-tracked byte. Those
  keep their own per-path grants; `NOTICE.md` names each one.
* It does not make this tree single-licensed. `third_party/` alone carries six
  separate works under six separate sets of terms (`NOTICE.md`, "`third_party/` —
  six works, six sets of terms"), and the `ryu/` Boost alternative is still on
  the table.
* It is not a publication grant. This repository is a private downstream, and
  being private removes no obligation: the notices, both licence texts and
  `NOTICE.md` travel with the source and with any binary or archive built from it.

## Apache-2.0 obligations this fork satisfies

| Obligation | Where |
|---|---|
| §4(a) a copy of the licence | `LICENSE-Apache2`, shipped unmodified |
| §4(b) modified files carry prominent change notices; the change is stated | the inline notice at `ryu/ryu.h:24`, the change tables in `NOTICE.md` and `UPSTREAM.md`, and every numbered entry in `CHANGELOG.md` |
| §4(c) retain upstream notices | every upstream copyright and grant block is carried verbatim; `ryu/ryu.h` keeps its own copyright line and its per-file Apache-2.0/Boost dual grant (`ryu/ryu.h:1-16`) alongside the changed line |
| §4(d) `NOTICE` attribution, where the work carries one | `NOTICE.md`, which reproduces upstream's attribution and this fork's per-path inventory |
| §3 patent grant and its termination | see `NOTICE.md`, "Patent grant" |

The §3 patent grant terminates, for **You**, the licences granted to You for the
Work on the date You file patent litigation alleging that the Work or an
incorporated Contribution infringes a patent. This fork added no algorithm: the
facade calls upstream's functions and returns what they return. The full
statement is in `NOTICE.md` and is not restated here.

## Superseded record

Earlier revisions of `NOTICE.md` recorded the fork-authored files as
**unassigned**, and recorded an earlier Apache-2.0 offer over them as withdrawn.
That was the state before the owner's authorization. It described the past, not
the present grant. The upstream per-path grants recorded there were never
affected and are unchanged.
