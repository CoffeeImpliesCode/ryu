# NOTICE

## Upstream attribution

Ryu is the work of Ulf Adams and contributors. Upstream repository: `https://github.com/ulfjack/ryu`; pinned commit: `4c0618b0e44f7ef027ebae05d2cc7812048f7c8f` on `master`. Upstream declares version `2.0` in `CMakeLists.txt`.

| File | Copyright |
|---|---|
| `ryu/ryu.h` | Copyright 2018 Ulf Adams |
| `ryu/ryu_parse.h` | Copyright 2019 Ulf Adams |
| `src/main/java/info/adams/ryu/RyuDouble.java` | Copyright 2018 Ulf Adams |

`CONTRIBUTORS` names Ulf Adams `<ulfjack@google.com>`, Stephan T. Lavavej `<stl@microsoft.com>`, and Alexander Bolz `<alexbolz@web.de>`.

Upstream's grant, from `README.upstream.md`:

> All code outside of third_party/ is copyrighted by Ulf Adams and
> contributors, and may be used freely in accordance with the Apache 2.0
> license. Alternatively, the files in the ryu/ directory may be used freely in
> accordance with the Boost 1.0 license.

The complete licence texts ship unmodified as `LICENSE-Apache2` and `LICENSE-Boost`.

## Licence by path

| Path | Licence | Scope |
|---|---|---|
| `ryu/` | Apache-2.0 OR BSL-1.0 | Upstream C core, parsers, generic 128-bit code, and headers; upstream's alternative grant covers this directory. `ryu/ryu.h` has the one disclosed include-line change. |
| `src/` | Apache-2.0 | Upstream Java port; outside `ryu/`, so the Boost alternative does not apply. |
| `scripts/`, `lean/`, `lakefile.toml`, `lake-manifest.json`, `lean-toolchain` | Apache-2.0 | Upstream generators and Lean port. |
| `.gitignore`, `CMakeLists.txt`, `MODULE.bazel`, `.bazelrc`, `.bazelversion`, `.classpath`, `run_benchmark_linux.sh`, `run_benchmark.bat`, `README.upstream.md`, `CONTRIBUTORS`, and other upstream files outside `third_party/` | Apache-2.0 | Covered by upstream's grant for code outside `third_party/`. |
| Fork-authored files listed in `FORK-LICENSE.md` | Apache-2.0 | Covered by the repository owner's grant; this does not change the upstream grants. |
| `third_party/` | Separate terms | See the per-directory table below. |

The upstream `ryu/` grant remains available under either Apache-2.0 or BSL-1.0. Fork-authored additions are Apache-2.0. `FORK-LICENSE.md` defines their exact scope and exclusions. The two appended `.gitignore` entries, `.zig-cache/` and `zig-out/`, are fork-authored; upstream's lines remain unchanged.

## Upstream path changes

| File | Change |
|---|---|
| `ryu/ryu.h` | The upstream `<inttypes.h>` include is replaced by `<stdint.h>`; the line also carries the fork change notice. The upstream copyright and dual licence remain. |
| `.gitignore` | Appends `.zig-cache/` and `zig-out/`; no upstream line is changed or removed. |
| `README.md` | Replaced by the fork README. Upstream's original README is preserved byte-for-byte as `README.upstream.md`. |

## `third_party/` licences

| Directory | Work and terms | Licence notice |
|---|---|---|
| `third_party/gtest` | GoogleTest, BSD 3-Clause; Copyright 2008, Google Inc. | `third_party/gtest/LICENSE` |
| `third_party/junit` | JUnit 4.12, Eclipse Public License 1.0. `hamcrest-core-1.3.jar` is also present and is not covered by this file's terms. | `third_party/junit/LICENSE` |
| `third_party/mersenne` | Test data, GFDL OR CC BY-NC-SA 3.0 Unported; the NonCommercial condition applies to the CC alternative only. `random.h` is separately Apache-2.0. | `third_party/mersenne/LICENSE`; `third_party/mersenne/random.h` |
| `third_party/mersenne_java` | Java generator with an Apache-2.0 source header; it does not inherit the data directory's terms. | `third_party/mersenne_java/java/info/adams/random/MersenneTwister.java` |
| `third_party/jaffer` | Aubrey Jaffer's permission notice with retained copyright, warranty disclaimer, and no-name-in-advertising condition; Apache-2.0 for Heng Yuan's Java code. No alternative selector is stated. | `third_party/jaffer/LICENSE` and `third_party/jaffer/java/org/yuanheng/cookjson/DoubleUtils.java` |
| `third_party/double-conversion` | V8 double-conversion library, BSD 3-Clause; Copyright 2006-2011, the V8 project authors. | `third_party/double-conversion/LICENSE` and `COPYING` |

Upstream's README credits White and Steele's Dragon work and correctness proof. It lists Scala, Rust, and other independent implementations as related work, not as code sources.
