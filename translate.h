/* Aggregate header for translate-c.
 *
 * This file is fork-authored and is the only new C file this package adds.
 * It contains no declarations of its own: it names the two public headers
 * upstream ships, in upstream's own spelling, so that `pub const c` in the
 * Zig facade is a translation of upstream's published API and nothing else.
 *
 * Why angle brackets and why two headers:
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
 *   (`README.md:35-38`).
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
 * `ryu/ryu_generic_128.h` is deliberately absent, and `-Dgeneric128` does not
 * put it here. Upstream builds it as a separate target tagged `nowindows`
 * (`ryu/BUILD:38-49`) because it needs `__uint128_t` and a working
 * `long double`, and it is not part of the default conversion core. That
 * option compiles `ryu/generic_128.c` and installs its header for a C caller
 * that wants it; the Zig facade in `zig/root.zig` publishes no generic 128-bit
 * symbol, so no declaration here would be translated for it.
 *
 * Both headers are guarded and both wrap their declarations in `extern "C"`,
 * so including them together is what upstream's own tests do
 * (`ryu/tests/d2s_test.cc:20` includes ryu.h, `ryu/tests/s2d_test.cc:20`
 * includes ryu_parse.h) and the combination is well defined.
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
 * defined (`build.zig:118-120`), so their own `<inttypes.h>` blocks are out.
 */

#ifndef RYU_TRANSLATE_H
#define RYU_TRANSLATE_H

#include <ryu/ryu.h>
#include <ryu/ryu_parse.h>

#endif /* RYU_TRANSLATE_H */