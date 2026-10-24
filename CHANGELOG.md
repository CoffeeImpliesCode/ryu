# Changelog

- Fix generic-128 `LongDouble` reflection on Zig 0.17.0 and filter cross-target checks by linkage, runtime loading, and generic-128 support.
- Port to Zig 0.17.0.
- Added runtime-dispatch builds with `-Druntime=true` and explicit provider loading through `ryu.load`.
- Exposed the optional generic 128-bit converters to C and Zig with `-Dgeneric128`.
- Added `-Dlinkage=static|dynamic`; static is the default, and unsupported dynamic targets are refused.
- Added Nix static and shared package outputs through `package.nix` and `flake.nix`.
- Precision writers reject capacities beyond C's signed return limit with `PrecisionTooLarge` before writing.
- Replaced `ryu/ryu.h`'s `<inttypes.h>` include with `<stdint.h>` for translator portability; declarations and ABI are unchanged.
- Added a typed Zig facade: buffer writers do not allocate; `Owned` writers return libc allocations that require `free`.
- Added upstream's experimental string-to-float parsers to the built library and installed `ryu/ryu_parse.h`.
- Added the Zig 0.16 `ryu` package with a C library, translated public headers, and install support.
