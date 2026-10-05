/* SPDX-License-Identifier: Apache-2.0
 *
 * Fork-authored; that identifier matches the primary upstream grant this
 * fork's own files are under (FORK-LICENSE.md), and it covers nothing under
 * `ryu/`, which is upstream's own dual Apache-2.0/BSL-1.0 material.
 * This is the only new C file this package adds.
 * It contains no declarations of its own: it names the two public headers
 * upstream ships, in upstream's own spelling, so that `pub const c` in the
 * Zig facade is a translation of upstream's published API and nothing else.
 *
 * Why angle brackets, and which headers:
 *
 *   Every source file and every internal header in `ryu/` spells its package
 *   includes as "ryu/<name>.h" (for example `ryu/d2s.c:30,43-45`), which
 *   makes the repository root the include root. Upstream's own CMake does the
 *   same and says so at `CMakeLists.txt:20-21`: this directory is the include
 *   root because the headers are in `ryu/` and are included with that prefix.
 *   Adding the repository root as a plain `-I` path is therefore the upstream
 *   spelling, and the angle brackets here resolve through it exactly as the
 *   quoted includes in the C sources do.
 *
 *   `ryu/ryu.h` is the stable conversion API: the shortest, fixed and
 *   scientific formatters for float and double. It is upstream's only header
 *   that upstream's own install rules publish (`CMakeLists.txt:28`), and it is
 *   dual licensed, Apache-2.0 or Boost-1.0, at the copyright holder's choice
 *   (`README.upstream.md:35-38` — upstream's README, kept byte for byte under
 *   that name, since `README.md` is this fork's).
 *
 *   `ryu/ryu_parse.h` is the string-to-float side, and upstream marks it
 *   experimental in its own first comment: "At this time, it only support up
 *   to 17 non-zero digits in the input, and also does not support all
 *   formats. Use at your own risk." (`ryu/ryu_parse.h:25-27`). This package
 *   builds `s2d.c` and `s2f.c` anyway, so the declarations have to be in
 *   scope here; upstream's CMake simply never installs the experimental
 *   parser. Those limits belong to the API documentation, not to a header this
 *   package rewrites.
 *
 * `ryu/ryu_generic_128.h` is behind `RYU_TRANSLATE_GENERIC_128`, a macro this
 * package defines on the translation line only when `-Dgeneric128` is set, and
 * which a C consumer defines itself before including this header if it wants
 * the same five converters. Upstream builds that unit as a separate target
 * tagged `nowindows` (`ryu/BUILD:38-49`) because it needs `__uint128_t` and a
 * working `long double`, and it is not part of the default conversion core, so
 * a translation naming it unconditionally would describe five functions the
 * default graph does not compile. With the macro undefined the header
 * contributes nothing and the translation is exactly upstream's default
 * sixteen entry points; with it defined the same translation also carries
 * `struct floating_decimal_128`, `FD128_EXCEPTIONAL_EXPONENT` and the five
 * converters of `ryu/ryu_generic_128.h:47-66`, which is the twenty-one a
 * `-Dgeneric128` build dispatches.
 *
 * The condition is the build option itself and nothing inferred from the
 * compiler. `build.zig` compiles `ryu/generic_128.c` under exactly the same
 * option, so the declarations and the object behind them agree by
 * construction; whether the compiler being used accepts `__uint128_t` is its
 * own answer for that target, and nothing here guesses at it or papers over
 * it.
 *
 * The macro name is fork-owned and deliberately carries no `RYU_` prefix.
 * Upstream defines no such macro, so a name that looked like upstream's would
 * be an invented ABI knob that a later upstream release could collide with.
 *
 * All three headers are guarded and all three wrap their declarations in
 * `extern "C"`, so including them together is what upstream's own tests do
 * (`ryu/tests/d2s_test.cc:20` includes ryu.h, `ryu/tests/s2d_test.cc:20`
 * includes ryu_parse.h) and the combination is well defined. The third is
 * conditional and carries its own guard as well, so including it twice - once
 * through this header and once directly - is still well defined.
 *
 * ## The one upstream line this package changes
 *
 * `ryu/ryu.h:24` reads `#include <stdint.h>` here; upstream reads
 * `#include <inttypes.h>`. That include carries exactly one name into the
 * header, `uint32_t`, used in the six `precision` parameters at
 * `ryu/ryu.h:34-40`; no `PRI*` or `SCN*` macro appears anywhere in it, and
 * `uint32_t` is declared by `<stdint.h>` (C99 7.18.1) - the header
 * `<inttypes.h>` includes to reach that same type. No declaration, type,
 * signature or constant changes. Three of the five compiled units include it:
 * `ryu/d2s.c:30`, `ryu/f2s.c:21`, and `ryu/d2fixed.c:26`. The other two
 * include `ryu_parse.h`; the compiled ABI remains upstream's own.
 *
 * The change is load-bearing rather than cosmetic. NetBSD's `<inttypes.h>`
 * closes its declarations with `__END_DECLS`, whose replacement list begins
 * with a `_Pragma`, and the pinned translator reads that `_Pragma` as
 * ordinary tokens - "unknown type name 'pragma'" at `inttypes.h:93` - on all
 * nine NetBSD cells. No compiled unit here depended on that header anyway:
 * each of the five includes `<stdint.h>` itself, and no `RYU_DEBUG` is
 * defined (`build.zig:295-297`), so their own `<inttypes.h>` blocks are out.
 */
 #ifndef RYU_TRANSLATE_H
 #define RYU_TRANSLATE_H

 #include <ryu/ryu.h>
 #include <ryu/ryu_parse.h>

 #ifdef RYU_TRANSLATE_GENERIC_128
 #include <ryu/ryu_generic_128.h>
 #endif

 #endif /* RYU_TRANSLATE_H */