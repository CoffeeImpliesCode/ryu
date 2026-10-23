# Zig facade API

## Buffer writers

| Function | Result |
|---|---|
| `format32Shortest(value: f32, out: []u8)` | Shortest round-trip binary32. |
| `format64Shortest(value: f64, out: []u8)` | Shortest round-trip binary64. |
| `format64Fixed(value: f64, precision: u32, out: []u8)` | Fixed notation with `precision` digits after the point. |
| `format64Scientific(value: f64, precision: u32, out: []u8)` | Scientific notation with `precision` digits after the leading digit. |

Each returns `Error![]u8`, a borrowed subslice of `out`. The bytes are not NUL-terminated; the buffer writers allocate nothing. Shortest capacities are `float_shortest_capacity = 15` and `double_shortest_capacity = 24`, excluding a terminator. `max_fixed_integer_digits = 309`.

`fixedCapacity(precision)` and `scientificCapacity(precision)` return the required byte bounds. Fixed precision is limited to `2147483336`; scientific precision to `2147483639`. The checks run before writing. A refused buffer or precision leaves `out` unchanged; `NegativeLength` is reported after the C writer runs, so discard that buffer.

## Owned strings

| Function | Upstream entry point |
|---|---|
| `format32ShortestOwned(value: f32)` | `f2s` |
| `format64ShortestOwned(value: f64)` | `d2s` |
| `format64FixedOwned(value: f64, precision: u32)` | `d2fixed` |
| `format64ScientificOwned(value: f64, precision: u32)` | `d2exp` |

These return `Error!OwnedString`. Upstream allocates the NUL-terminated bytes with the provider's C `malloc`; release them only with `OwnedString.deinit`, which calls that C library's `free`. `owned_max_fixed_precision` and `owned_max_scientific_precision` give the accepted owned-writer limits.

## Experimental parsers

- `experimental.parse64(text: []const u8) Error!f64` accepts up to 17 nonzero decimal digits.
- `experimental.parse32(text: []const u8) Error!f32` accepts up to 9 nonzero decimal digits.

Both accept an optional leading minus, optional decimal point, and optional `e` or `E` exponent with sign and at most four digits. They reject whitespace, hexadecimal, `inf`, `nan`, suffixes, and trailing bytes. The API is upstream's experimental parser surface.

## Raw and optional APIs

`c` re-exports the translated C declarations. It includes the two public headers and, when configured, the generic-128 header.

`generic128` is upstream's generic 128-bit converter namespace when available, and `void` otherwise. Its public members are:

- Types and constants: `Decimal`, `Mantissa`, `LongDouble`, `exceptional_exponent`, `to_chars_capacity` (53 bytes).
- Conversion: `fromFloat`, `fromDouble`, `fromLongDouble`, `fromBinary`, `decimalFor`, `shortestChars`, `toChars`.

Use the converter for the input's actual type; do not cast between floating-point types. `LongDouble` reflects the target's translated C type, and upstream limits the reliability of that converter to particular platforms and compilers.

## Runtime loading

| Declaration | Contract |
|---|---|
| `runtime_loaded: bool` | Comptime indicator for the runtime-loaded configuration. |
| `LoadSource` | `.path` requires an absolute path; `.system` accepts a library basename. The forms do not fall back to each other. |
| `load(source: LoadSource) LoadError!void` | Open, resolve, and validate the provider before routed calls. A linked build panics if called. |
| `loadedSource() ?LoadSource` | Successful request, or `null` before loading and in linked builds. |

`LoadError` is `EmptySource`, `SourceTooLong`, `InvalidSource`, `UnsupportedTarget`, `OpenFailed`, `MissingSymbol`, `ValidationFailed`, `ProviderMismatch`, or `ReentrantLoad`. Successful handles remain loaded for the process lifetime; there is no unload or reset.

## Errors and output

`Error` is the closed set `BufferTooSmall`, `PrecisionTooLarge`, `NegativeLength`, `TextTooLong`, `InputTooShort`, `InputTooLong`, and `MalformedInput`. Parser status errors preserve upstream's four outcomes: too short, too long, malformed, or success.

Shortest output uses uppercase `E` without a plus sign or exponent padding (`1.25E0`); fixed and scientific output use lowercase `e`, an explicit exponent sign, and at least two exponent digits (`1.25e+00`). Rounding is to nearest, ties to even. Shortest supports binary32 and binary64; fixed and scientific support binary64 only.
