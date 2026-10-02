//! Zig facade over Ryu's canonical C implementation.
//!
//! No part of the algorithm is reimplemented here. Every digit this module
//! returns is produced by the C under `ryu/`, reached through `pub const c`,
//! the module `b.addTranslateC` produces from upstream's `ryu/ryu.h` and
//! `ryu/ryu_parse.h`. `translate.h` is the aggregate header that translation
//! reads, and it names those two headers as upstream ships them. The one
//! disclosed change is a single line of upstream's own: `ryu/ryu.h:24` reads
//! `<stdint.h>` rather than `<inttypes.h>`, for the `uint32_t` that is all
//! that header uses it for. What the facade adds is the part a C header
//! cannot express: a length the compiler checks instead of a length a
//! comment promises, a caller-owned output slice instead of a bare
//! `char*`, an error returned *before* anything is written when the buffer
//! cannot hold the answer, and a written-out capacity bound for the two
//! modes whose output length depends on a caller-supplied precision.
//!
//! ## Allocation
//!
//! There is none. Upstream also publishes `d2s`, `f2s`, `d2fixed` and `d2exp`,
//! each of which `malloc`s and hands back a pointer the caller must `free`;
//! this module calls none of them and instead calls the `*_buffered_n`
//! siblings, which write into a buffer the caller already owns. So the rule
//! about a third-party allocator never arises: buffers in, bytes out, and the
//! caller owns every one of them. Nothing is copied except the bounded copy
//! documented on `format32Shortest`/`format64Shortest`.
//!
//! ## Errors
//!
//! `Error` is the whole taxonomy, and each member is a condition this module
//! actually checks before or instead of calling upstream:
//!
//!   * `BufferTooSmall` - the caller's slice cannot hold the answer. Upstream's
//!     `*_buffered_n` take a bare `char*` and write whatever they like; the
//!     bound is verified here first, so a rejected call writes nothing at all.
//!   * `PrecisionTooLarge` - the `u32` precision's capacity bound does not fit
//!     in this target's `usize`. Reachable on a 32-bit target such as
//!     `wasm32-wasi`, not on a 64-bit one. Also checked before any write.
//!   * `NegativeLength` - upstream's writer returned a negative length. Its own
//!     source has no path that does this; the branch exists so a violation is
//!     an ordinary error a caller can handle rather than a panic or a wrap.
//!   * `TextTooLong` - the text handed to the experimental parser is longer
//!     than the `int` length argument upstream takes.
//!   * `InputTooShort`, `InputTooLong`, `MalformedInput` - upstream's own
//!     parser statuses, surfaced one for one. See `experimental`.
//!
//! ## Output spelling
//!
//! Upstream's two scientific styles are different from each other and both are
//! preserved exactly, because they are the published output of a library whose
//! consumers compare strings:
//!
//!   * `format32Shortest` / `format64Shortest` write `E`, no `+`, and no zero
//!     padding: `1E0`, `5E-324`, `1.7976931348623157E308`. Fixed at
//!     `ryu/d2s.c:400-417` and `ryu/f2s.c:294-303`.
//!   * `format64Scientific` writes `e`, an explicit `+` for a nonnegative
//!     exponent, and at least two exponent digits: `1.25e+00`, `1e+54`,
//!     `4.940656...e-324`. Fixed at `ryu/d2fixed.c:788-804`.
//!
//! The special values are upstream's too, and they differ between the two
//! families: shortest prints `NaN`, `Infinity`, `-Infinity` and `0E0`
//! (`ryu/common.h:86-100`), while the fixed and scientific writers print
//! `nan`, `Infinity`, `-Infinity` and, for zero, `0` / `0.0000e+00`
//! (`ryu/d2fixed.c:331-356`, `ryu/d2fixed.c:434-437`, `ryu/d2fixed.c:585-599`).
//!
//! ## Threading
//!
//! Nothing here is shared. Every entry point is a pure function of its
//! arguments plus a caller-owned buffer, and all state inside Ryu is on the
//! stack of the call, so concurrent calls on different buffers are as safe as
//! the C is.

const std = @import("std");

/// The translated `ryu/ryu.h` and `ryu/ryu_parse.h`, i.e. upstream's ABI
/// exactly as published: the same twelve core functions, the same four
/// parser functions and the same `enum Status`, with `uint32_t` the
/// target's own, taken from the target's own `<stdint.h>`.
///
/// This is the escape hatch for the caller that needs something the facade
/// does not name: `d2s_buffered`, which NUL-terminates in place, or the
/// `malloc`-ing `d2s`/`f2s`/`d2fixed`/`d2exp` whose buffers the caller would
/// then have to `free`. A caller that goes through it gets upstream
/// behaviour with none of the guarantees above, which is the point of it
/// being public.
pub const c = @import("c");

/// Every condition this module refuses, in one closed set.
pub const Error = error{
    /// The caller's slice is shorter than the bound this call can produce.
    /// Nothing was written to it.
    BufferTooSmall,
    /// The `u32` precision's capacity bound does not fit in this target's
    /// `usize`. Nothing was written to the output slice.
    PrecisionTooLarge,
    /// Upstream's writer returned a negative length. Its own source has no
    /// path that does this, so this reports a broken build rather than a
    /// caller mistake, but it is an ordinary error and not a panic.
    NegativeLength,
    /// The text handed to the experimental parser is longer than the `int`
    /// length argument upstream takes (`ryu/s2d.c:71`).
    TextTooLong,
    /// The experimental parser was given no bytes at all
    /// (`INPUT_TOO_SHORT`, `ryu/s2d.c:72-74`).
    InputTooShort,
    /// The experimental parser was given more nonzero mantissa digits than
    /// that width admits - 17 for the binary64 parser (`INPUT_TOO_LONG`,
    /// `ryu/s2d.c:100-102`) and 9 for the binary32 one (`ryu/s2f.c:94-96`) -
    /// or more than 4 exponent digits, which both parsers refuse the same way
    /// (`ryu/s2d.c:120-123`, `ryu/s2f.c:114-117`).
    InputTooLong,
    /// The experimental parser found a byte outside its grammar
    /// (`MALFORMED_INPUT`, `ryu/s2d.c:92-94`, `ryu/s2d.c:117-119` and
    /// `ryu/s2d.c:130-132`).
    MalformedInput,
};

/// Bytes the shortest binary32 writer can ever produce, excluding a
/// terminator.
///
/// Upstream's own `f2s` allocates 16 bytes and NUL-terminates at the returned
/// length (`ryu/f2s.c:341-346`), so 15 is the number upstream itself trusts.
/// It is also what the writer's shape gives: one sign, at most nine
/// significant digits and the point between them, `E`, an optional exponent
/// sign, and at most two exponent digits for a format whose range is
/// 1e-45 .. 3.4e38 (`ryu/f2s.c:233-304`).
pub const float_shortest_capacity: usize = 15;

/// Bytes the shortest binary64 writer can ever produce, excluding a
/// terminator.
///
/// Upstream's own `d2s` allocates 25 bytes and NUL-terminates at the returned
/// length (`ryu/d2s.c:505-509`), so 24 is the number upstream itself trusts.
/// It is also what the writer's shape gives: one sign, at most seventeen
/// significant digits and the point between them, `E`, an optional exponent
/// sign, and at most three exponent digits for a format whose range is
/// 5e-324 .. 1.8e308 (`ryu/d2s.c:314-420`).
pub const double_shortest_capacity: usize = 24;

/// Digits in the integer part of the widest fixed-point answer: the largest
/// finite binary64 is 1.7976931348623157e308, whose floor has 309 digits.
///
/// Upstream's own fixed-point test pins the widest such answer, the 309 digit
/// integer part of the largest finite double, at
/// `ryu/ryu/tests/d2fixed_test.cc` in `D2fixedTest.MinMax`.
pub const max_fixed_integer_digits: usize = 309;

/// Bytes the fixed and scientific writers spend on everything that is not the
/// caller-supplied fraction: one sign, `max_fixed_integer_digits` integer
/// digits, and the point. Used by `fixedCapacity`.
const fixed_overhead: u64 = 1 + max_fixed_integer_digits + 1;

/// Bytes the scientific writer spends on everything that is not the
/// caller-supplied fraction: one sign, one leading digit, the point, `e`, the
/// exponent sign and at most three exponent digits. Used by
/// `scientificCapacity`.
const scientific_overhead: u64 = 1 + 1 + 1 + 1 + 1 + 3;

/// The longest thing the fixed and scientific writers can print that is not a
/// number: `-Infinity`, from `ryu/d2fixed.c:354-355`.
const special_value_capacity: u64 = 9;

/// Bytes `format64Fixed` guarantees are enough for `value` at `precision`.
///
/// The bound is deliberately conservative because the exact length depends on
/// the value: it is one sign, at most `max_fixed_integer_digits` integer
/// digits, one point, and exactly `precision` further digits, which is what
/// `d2fixed_buffered_n` writes for every input
/// (`ryu/d2fixed.c:358-550`: the zero path at 377-389, the `precision == 0`
/// path at 545-548, the general path at 405-437, and the special-value paths
/// at 331-356). No precision is refused: a `u32` is honoured in full.
///
/// Returns `error.PrecisionTooLarge` when the bound does not fit in this
/// target's `usize`, which a 32-bit target can reach and a 64-bit target
/// cannot. The bound is accumulated in `u64` first, so no intermediate
/// expression can wrap on the way.
pub fn fixedCapacity(precision: u32) Error!usize {
    return std.math.cast(usize, fixed_overhead + @as(u64, precision)) orelse
        error.PrecisionTooLarge;
}

/// Bytes `format64Scientific` guarantees are enough for `value` at
/// `precision`.
///
/// The bound is one sign, one leading digit, one point, exactly `precision`
/// further digits, `e`, an exponent sign and up to three exponent digits.
/// Rounding carry does not escape it: upstream prints `9.9999` at precision 3
/// as `1.000e+01`, one digit, a point and three digits, which is `precision`
/// plus two, exactly what the arithmetic below reserves
/// (`ryu/d2fixed.c:615-617` raises the precision by one, `ryu/d2fixed.c:788`
/// writes the marker and `ryu/d2fixed.c:796-804` writes two or three exponent
/// digits). `precision == 0` still leaves room for the nine byte `-Infinity`.
///
/// Returns `error.PrecisionTooLarge` on the same terms as `fixedCapacity`.
pub fn scientificCapacity(precision: u32) Error!usize {
    const bound = @max(scientific_overhead + @as(u64, precision), special_value_capacity);
    return std.math.cast(usize, bound) orelse error.PrecisionTooLarge;
}

/// Format `value` as the shortest binary32 string that reads back as `value`.
///
/// Upstream's spelling is kept whole: `1E0`, `3.4028235E38`, `1E-45`, `NaN`,
/// `Infinity`, `-Infinity`. See the module docs for why the exponent is
/// spelled `E0` and not `e+00`.
///
/// `out` must have room for `float_shortest_capacity` bytes, which is a
/// compile-time constant, unless it is large enough for this particular
/// answer. A buffer at least that large is written into directly and nothing
/// is copied. A smaller one is written through a 15 byte stack temporary and
/// the produced prefix is copied into it, so a caller that knows its value
/// formats to a short string - `"0E0"` into three bytes - without paying for
/// the worst case on every call. A buffer that is small and still too small
/// for the answer returns `error.BufferTooSmall` and is left untouched.
///
/// The returned slice is a subslice of `out` and borrows it; the bytes are
/// *not* NUL-terminated, because the length is already known.
pub fn format32Shortest(value: f32, out: []u8) Error![]u8 {
    if (out.len >= float_shortest_capacity) return shortest32(value, out);
    if (out.len == 0) return error.BufferTooSmall;
    var temp: [float_shortest_capacity]u8 = undefined;
    const produced = try shortest32(value, &temp);
    if (produced.len > out.len) return error.BufferTooSmall;
    @memcpy(out[0..produced.len], produced);
    return out[0..produced.len];
}

/// Format `value` as the shortest binary64 string that reads back as `value`.
///
/// Upstream's spelling is kept whole: `1E0`, `5E-324`,
/// `1.7976931348623157E308`, `NaN`, `Infinity`, `-Infinity`.
///
/// `out` is treated exactly as on `format32Shortest`, with 24 bytes as the
/// constant instead of 15. The returned slice is a subslice of `out` and is
/// not NUL-terminated.
pub fn format64Shortest(value: f64, out: []u8) Error![]u8 {
    if (out.len >= double_shortest_capacity) return shortest64(value, out);
    if (out.len == 0) return error.BufferTooSmall;
    var temp: [double_shortest_capacity]u8 = undefined;
    const produced = try shortest64(value, &temp);
    if (produced.len > out.len) return error.BufferTooSmall;
    @memcpy(out[0..produced.len], produced);
    return out[0..produced.len];
}

/// Format `value` in fixed-point notation with exactly `precision` digits
/// after the point, or none when `precision` is zero.
///
/// Upstream rounds a tie to even, so `2.5` at precision 0 is `2` and `3.5` at
/// precision 0 is `4`, and it carries a run of nines into the integer part, so
/// `9.9999` at precision 3 is `10.000`. Both are upstream's own published
/// answers (`ryu/ryu/tests/d2fixed_test.cc`, `D2fixedTest.RoundToEvenInteger`
/// and `D2fixedTest.Carrying`).
///
/// `out.len` must be at least `fixedCapacity(precision)`, and the check
/// happens before the call, so a refused call writes nothing. The bound does
/// not depend on `value` and there is no shortcut past it: a caller wanting
/// the exact length for one value must give the documented bound.
///
/// `precision` is a `u32` and is honoured over its full range, up to and
/// including `std.math.maxInt(u32)`. Where that bound does not fit in `usize`
/// this returns `error.PrecisionTooLarge` rather than wrapping.
///
/// The returned slice is a subslice of `out` and is not NUL-terminated.
pub fn format64Fixed(value: f64, precision: u32, out: []u8) Error![]u8 {
    const needed = try fixedCapacity(precision);
    if (out.len < needed) return error.BufferTooSmall;
    const len = c.d2fixed_buffered_n(value, precision, mutable(out));
    return out[0..try producedLength(len)];
}

/// Format `value` in scientific notation with exactly `precision` digits
/// after the point, or none when `precision` is zero.
///
/// Upstream's spelling is kept whole: lowercase `e`, an explicit `+` for a
/// nonnegative exponent and at least two exponent digits, so `1.25` at
/// precision 2 is `1.25e+00` and `9.9999` at precision 3 carries to
/// `1.000e+01`. Rounding ties go to even, so `2.5` at precision 0 is `2e+00`
/// and `3.5` at precision 0 is `4e+00`.
///
/// `out.len`, `precision` and the returned subslice are treated exactly as on
/// `format64Fixed`, with `scientificCapacity(precision)` as the bound.
pub fn format64Scientific(value: f64, precision: u32, out: []u8) Error![]u8 {
    const needed = try scientificCapacity(precision);
    if (out.len < needed) return error.BufferTooSmall;
    const len = c.d2exp_buffered_n(value, precision, mutable(out));
    return out[0..try producedLength(len)];
}

/// Upstream's string-to-float parser, which upstream itself calls
/// experimental.
///
/// This is offered because it is real, shipped C API in `ryu/ryu_parse.h`, and
/// it is named `experimental` here because upstream says so in its own header:
/// *"This is an experimental implementation of parsing strings to 64-bit
/// floats using a Ryu-like algorithm. At this time, it only support up to 17
/// non-zero digits in the input, and also does not support all formats. Use at
/// your own risk."* (`ryu/ryu_parse.h:25-27`). Nothing about it is stabilised
/// or re-specified here, and the four `format*` functions above are the
/// stable surface of this module.
///
/// The only things added are a length-carrying signature and one honest error
/// per status. A rejected parse leaves the caller's own value untouched: the
/// result is written to a local and only returned on success, which matters
/// because upstream writes `*result` only on the `m10 == 0` and success paths
/// (`ryu/s2d.c:137-158`, `ryu/s2d.c:218-258`) and returns early without
/// touching it otherwise.
///
/// Empty input is refused as `error.InputTooShort` before the call, which is
/// the status upstream itself returns for it (`ryu/s2d.c:72-74`); the check
/// is here only so the length is never zero in a call that takes a pointer.
pub const experimental = struct {
    /// Parse `text` as a binary64, in the subset upstream's parser accepts.
    ///
    /// Accepted: an optional leading `-`, up to 17 nonzero decimal digits with
    /// an optional point, and an optional `e`/`E` with an optional sign and up
    /// to 4 exponent digits. The whole of `text` must be consumed; a trailing
    /// byte outside that grammar is `error.MalformedInput`. No surrounding
    /// whitespace, no `inf`, no `nan`, no hexadecimal, no `f` suffix.
    ///
    /// Underflow below 1e-324 and overflow above 1e+309 are not errors: they
    /// yield a signed zero and a signed infinity respectively, which is
    /// upstream's own choice (`ryu/s2d.c:149-158`, `ryu/s2d.c:218-222`).
    pub fn parse64(text: []const u8) Error!f64 {
        if (text.len == 0) return error.InputTooShort;
        const len = std.math.cast(c_int, text.len) orelse return error.TextTooLong;
        var out: f64 = undefined;
        try checkStatus(c.s2d_n(immutable(text), len, &out));
        return out;
    }

    /// `parse64` for a binary32, in upstream's own narrower grammar.
    ///
    /// The shape is the same - an optional `-`, nonzero decimal digits with an
    /// optional point, an optional `e`/`E` with an optional sign - and the
    /// exponent limit is the same, but the mantissa limit is upstream's own and
    /// it is not `parse64`'s: `s2f_n` refuses at 9 nonzero mantissa digits
    /// where `s2d_n` refuses at 17 (`ryu/s2f.c:94-96` against
    /// `ryu/s2d.c:100-102`). A 10 digit decimal therefore parses as a binary64
    /// and is `error.InputTooLong` as a binary32. Every other part of the
    /// contract, the underflow and overflow results, and the four statuses, is
    /// as on `parse64`.
    pub fn parse32(text: []const u8) Error!f32 {
        if (text.len == 0) return error.InputTooShort;
        const len = std.math.cast(c_int, text.len) orelse return error.TextTooLong;
        var out: f32 = undefined;
        try checkStatus(c.s2f_n(immutable(text), len, &out));
        return out;
    }
};

/// Map upstream's parser status onto one error per condition it can report.
///
/// `ryu/ryu_parse.h:29-34` declares exactly four statuses. A value outside
/// them is not a condition this module has checked for and has no name for, so
/// it is reported as `error.MalformedInput`: input the parser could not turn
/// into a number is what that status means, and inventing a fifth error for an
/// unreachable value would widen the taxonomy past what the code above it
/// actually tests.
fn checkStatus(status: c_uint) Error!void {
    if (status == c.SUCCESS) return;
    if (status == c.INPUT_TOO_SHORT) return error.InputTooShort;
    if (status == c.INPUT_TOO_LONG) return error.InputTooLong;
    return error.MalformedInput;
}

/// Turn upstream's returned `int` length into a slice length, refusing the
/// value its own source cannot produce.
fn producedLength(len: c_int) Error!usize {
    if (len < 0) return error.NegativeLength;
    return @intCast(len);
}

fn shortest32(value: f32, out: []u8) Error![]u8 {
    const len = c.f2s_buffered_n(value, mutable(out));
    return out[0..try producedLength(len)];
}

fn shortest64(value: f64, out: []u8) Error![]u8 {
    const len = c.d2s_buffered_n(value, mutable(out));
    return out[0..try producedLength(len)];
}

/// A `char*` to `out[0]`, for the `char*` parameters upstream declares.
///
/// Taken from the first element rather than from `out.ptr` because every call
/// site has already established `out.len != 0`, and `&out[0]` is the shape
/// Zig's own standard library casts to a C pointer. Upstream writes through
/// this pointer for the number of bytes it returns, and every caller of
/// `mutable` has checked that its slice is at least that long first.
fn mutable(out: []u8) [*c]u8 {
    return @ptrCast(&out[0]);
}

/// A `const char*` to `text[0]`, for the length-carrying parser parameters
/// upstream declares. Every call site has established `text.len != 0`.
fn immutable(text: []const u8) [*c]const u8 {
    return @ptrCast(&text[0]);
}
