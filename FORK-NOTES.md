# Fork notes

## Source changes

| Path | Change and reason |
|---|---|
| `ryu/ryu.h` | Uses `<stdint.h>` instead of `<inttypes.h>` for `uint32_t`; NetBSD's `__END_DECLS` expansion contains a `_Pragma` that translate-c cannot parse. |
| `translate.h` | Adds a translation root for the formatter and parser headers, with generic-128 declarations enabled only alongside that build option. |
| `zig/root.zig` | Adds typed formatting and parsing wrappers with bounded buffers, Zig errors, and release of C-owned strings. |
| `runtime/generate.zig` | Generates typed dispatch from the selected translate-c output and rejects declarations it cannot route. |
| `runtime/graph.zig` | Wires the generated dispatch, translated module, and loader while sharing loader types. |
| `runtime/library.zig` | Defines required Ryu exports and checks provider output and allocator compatibility before publication. |
| `runtime/loader.zig` | Adds explicit file or system-library loading; failed attempts publish nothing, and successful providers stay loaded for the process. |
| `runtime/sync.h` | Declares namespaced lock, wait, broadcast, and thread-identity functions for the loader. |
| `runtime/sync.c` | Implements loader synchronization for Windows and POSIX, with a single-threaded WASI/Emscripten backend. |
| `tests.zig` | Adds Zig facade tests using encoded fixtures and parse/format cross-checks. |
| `smoke.zig` | Adds a smoke executable for the C API, facade, parser, and optional runtime provider. |
| `consumer/src/main.zig` | Adds a separate-package example for module imports, formatting, and owned results. |

The only change inside upstream's `ryu/` tree is the include in `ryu/ryu.h`; upstream conversion algorithms and declarations are unchanged.

## Build graph

- `build.zig` replaces upstream's build targets with a Zig package graph. The default library compiles five C units, including the two parser units omitted by upstream's CMake target.
- `-Dgeneric128=true` adds upstream's optional `generic_128.c`, installs its header, and enables matching translate-c declarations.
- The linked facade imports translated C declarations and links the native library. Runtime mode generates dispatch from the same translation and does not link the archive into the facade module; the native artifact is still built and installed.
- The install graph adds C headers, generated pkg-config metadata, and licence records. `test` and `smoke` run the package roots; `check` compiles them.

## Platform boundaries

- Runtime loading is unavailable on WASI, Emscripten, and freestanding targets. Dynamic artifact selection also requires an OS dynamic linker; unsupported targets fail instead of receiving a static substitute.
- The core has portable arithmetic paths without `__uint128_t`; some 32-bit compiler combinations use slower division helpers.
- The optional generic-128 unit requires compiler support for `__uint128_t` and is marked `nowindows` upstream. Its `long double` conversion depends on the native ABI; upstream limits it to some x86/compiler combinations, and translated `c_longdouble` is opaque to the Zig facade.
