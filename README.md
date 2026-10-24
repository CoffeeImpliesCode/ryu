# ryu

Zig package for ulfjack/ryu 2.0, pinned at commit `4c0618b0e44f7ef027ebae05d2cc7812048f7c8f`.
It builds upstream's C converters and exposes a Zig facade and native library.

## Source deviations

| File | Change | Reason |
|---|---|---|
| `ryu/ryu.h` | Replace `<inttypes.h>` with `<stdint.h>` for `uint32_t`. | NetBSD's `<inttypes.h>` expands `__END_DECLS` to a `_Pragma` that the pinned translator cannot parse. |

No upstream C implementation, declaration, or algorithm is changed.

## Build deviations

- Compile upstream's five primary units: `d2s.c`, `f2s.c`, `d2fixed.c`, `s2d.c`, and `s2f.c`. The two experimental parsers are included in this library although upstream's CMake target omits them.
- `-Dgeneric128=true` adds upstream's experimental `generic_128.c` and header as a sixth unit; it is off by default.
- Compile as `gnu17`. The build offers static or shared delivery and a generated runtime dispatch; it does not offer system-library mode because an installed upstream library omits the parser API.
- `-Druntime=true` changes calls to use an explicitly loaded provider. The selected native artifact is still built and installed.
- No shared-library ABI version is assigned; upstream declares no ABI number.

## Support matrix

| Gate | Targets | Coverage |
|---|---|---|
| `check` | `x86_64-linux-gnu`, `aarch64-linux-gnu`, `aarch64-macos-none`, `x86_64-windows-gnu`, `riscv64-linux-gnu`, `wasm32-wasi` | Compile-only; filtered by the selected options below. |
| `cross-test` | Zig 0.17.0's published target table | Runs tests where a runner is available; other targets are build-only. |

`wasm32-wasi` has no dynamic linker, so `-Dlinkage=dynamic` is refused there rather than replaced by a static archive. Upstream marks the optional generic-128 unit `nowindows`; it requires compiler support for `__uint128_t`, and its `long double` converter is ABI-dependent.

With `-Dlinkage=dynamic` or `-Druntime=true`, `check` excludes `wasm32-wasi`. Runtime loading is unavailable on WASI, Emscripten, and freestanding targets. With `-Dgeneric128=true`, `check` excludes Windows and compiles the optional converters on the remaining targets.

## Consumption

In `build.zig.zon` (local checkout example):

```zig
.dependencies = .{
    .ryu = .{ .path = "../ryu" },
},
```

In `build.zig`:

```zig
const dep = b.dependency("ryu", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("ryu", dep.module("ryu"));
```

The `ryu` module carries artifact `ryu`: `libryu.a` by default, or `libryu.so`, `libryu.dylib`, or `ryu.dll` with `-Dlinkage=dynamic`. The facade exposes the translated C declarations as `ryu.c`. The separate `c` module is available only in linked builds and does not carry the library by itself.

Build options:

- `-Dlinkage=static|dynamic`; default `static`.
- `-Druntime=true`; resolve the provider with `ryu.load(.{ .path = "/path/to/libryu.so" })` before the first call.
- `-Dgeneric128=true`; add the optional generic 128-bit converters.
