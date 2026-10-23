// SPDX-License-Identifier: Apache-2.0
//
//! Typed, allocation-aware Zig facade over Ryu's canonical C implementation.
//! Caller buffers stay caller-owned; upstream-owned strings use C `free`.
//!
const std = @import("std");

/// Translated upstream declarations; runtime-loaded builds expose generated dispatch here.
/// Raw C calls retain upstream behavior, while the facade adds checked wrappers.
pub const c = @import("c");

/// Loader core used to expose the same public loading types in linked builds.
const rt = @import("rt");

/// True when this build requires an explicit runtime load before native calls.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Explicit provider file path or platform-loader name; no fallback is used.
/// Paths must be absolute; system names are basenames.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Errors returned by explicit provider loads.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Loads the runtime provider; same-source calls are idempotent, and mismatches return `ProviderMismatch`.
/// Failures return `LoadError`; linked builds panic, and successful providers stay loaded for process lifetime.
pub fn load(source: LoadSource) LoadError!void {
    if (comptime !runtime_loaded) {
        std.debug.panic(
            "ryu: load was called on a linked build; this module is not " ++
                "runtime-loaded, so there is no library to load. Build with " ++
                "runtime loading configured, or do not call load.",
            .{},
        );
    }
    return c.load(source);
}

/// Returns the retained successful provider request, or `null` if none is loaded.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

// Deallocator paired with upstream's `malloc`-owned strings.

/// Every condition this module refuses, in one closed set.
extern fn free(ptr: ?*anyopaque) void;
pub const Error = error{
    /// The supplied output buffer cannot hold the result; it remains unchanged.
    BufferTooSmall,
    /// The requested precision cannot be represented safely; rejected before C writes.
    PrecisionTooLarge,
    /// Upstream returned an invalid negative length; discard any bytes it wrote.
    NegativeLength,
    /// An upstream `malloc` call returned null.
    OutOfMemory,
    /// Input length does not fit upstream's `int` parameter.
    TextTooLong,
    /// The experimental parser received empty input.
    InputTooShort,
    /// The parser rejected the mantissa or exponent length.
    InputTooLong,
    /// The experimental parser rejected the input grammar.
    MalformedInput,
};

/// Maximum binary32 shortest output size, excluding a terminator.
pub const float_shortest_capacity: usize = 15;

/// Maximum binary64 shortest output size, excluding a terminator.
pub const double_shortest_capacity: usize = 24;

/// Maximum integer digits in a fixed binary64 result.
pub const max_fixed_integer_digits: usize = 309;

const fixed_overhead: u64 = 1 + max_fixed_integer_digits + 1;

const scientific_overhead: u64 = 1 + 1 + 1 + 1 + 1 + 3;

/// Largest output length upstream's signed `int` return can represent.
const max_written_bytes: u64 = @intCast(std.math.maxInt(c_int));

/// Conservative special-value bound covering upstream's compiler-specific NaN spellings.
const special_value_capacity: u64 = 10;

/// Returns the conservative caller-buffer size for fixed output at `precision`.
/// Returns `error.PrecisionTooLarge` when the output length cannot be represented.
pub fn fixedCapacity(precision: u32) Error!usize {
    if (@as(u64, precision) + fixed_overhead > max_written_bytes) return error.PrecisionTooLarge;
    return std.math.cast(usize, fixed_overhead + @as(u64, precision)) orelse
        error.PrecisionTooLarge;
}

/// Returns the conservative caller-buffer size for scientific output at `precision`.
/// Returns `error.PrecisionTooLarge` when the output length cannot be represented.
pub fn scientificCapacity(precision: u32) Error!usize {
    const bound = @max(scientific_overhead + @as(u64, precision), special_value_capacity);
    if (bound > max_written_bytes) return error.PrecisionTooLarge;
    return std.math.cast(usize, bound) orelse error.PrecisionTooLarge;
}

// Maximum buffer size used by upstream's owned precision writers.
const owned_heap_capacity: u64 = 2000;

/// Largest precision accepted by `format64FixedOwned`.
pub const owned_max_fixed_precision: u32 = @intCast((owned_heap_capacity - 1) - fixed_overhead);

/// Largest precision accepted by `format64ScientificOwned`.
pub const owned_max_scientific_precision: u32 = @intCast((owned_heap_capacity - 1) - scientific_overhead);

/// A NUL-terminated string allocated by upstream; release it with `deinit()`.
/// Its storage belongs to the C library, not a Zig allocator.
pub const OwnedString = struct {
    /// C-owned NUL-terminated bytes.
    bytes: [*c]u8,
    /// String length in bytes, excluding the terminator.
    len: usize,

    /// Borrows the string bytes; do not use the slice after `deinit()`.
    pub fn slice(self: OwnedString) []u8 {
        return self.bytes[0..self.len];
    }

    /// Releases the C allocation with `free`; do not pass it to a Zig allocator.
    pub fn deinit(self: OwnedString) void {
        free(@ptrCast(self.bytes));
    }
};

/// Wraps an upstream-owned string; null returns `error.OutOfMemory`.
fn own(raw: [*c]u8) Error!OwnedString {
    if (@intFromPtr(raw) == 0) return error.OutOfMemory;
    return .{ .bytes = raw, .len = std.mem.span(raw).len };
}

/// Allocates upstream's binary32 shortest string; release it with `deinit()`.
/// Returns `OutOfMemory` if C `malloc` fails.
pub fn format32ShortestOwned(value: f32) Error!OwnedString {
    return own(c.f2s(value));
}

/// Allocates upstream's binary64 shortest string; release it with `deinit()`.
/// Returns `OutOfMemory` if C `malloc` fails.
pub fn format64ShortestOwned(value: f64) Error!OwnedString {
    return own(c.d2s(value));
}

/// Returns an upstream-owned fixed string; excessive precision returns `PrecisionTooLarge`.
/// Release with `OwnedString.deinit()`; a null C allocation returns `OutOfMemory`.
pub fn format64FixedOwned(value: f64, precision: u32) Error!OwnedString {
    if (precision > owned_max_fixed_precision) return error.PrecisionTooLarge;
    return own(c.d2fixed(value, precision));
}

/// Returns an upstream-owned scientific string; excessive precision returns `PrecisionTooLarge`.
/// Release with `OwnedString.deinit()`; a null C allocation returns `OutOfMemory`.
pub fn format64ScientificOwned(value: f64, precision: u32) Error!OwnedString {
    if (precision > owned_max_scientific_precision) return error.PrecisionTooLarge;
    return own(c.d2exp(value, precision));
}

/// Writes shortest binary32 text into caller-owned `out` and returns a borrowed, non-NUL-terminated slice.
/// Returns `BufferTooSmall` if needed; `NegativeLength` may follow an upstream write.
pub fn format32Shortest(value: f32, out: []u8) Error![]u8 {
    if (out.len >= float_shortest_capacity) return shortest32(value, out);
    if (out.len == 0) return error.BufferTooSmall;
    var temp: [float_shortest_capacity]u8 = undefined;
    const produced = try shortest32(value, &temp);
    if (produced.len > out.len) return error.BufferTooSmall;
    @memcpy(out[0..produced.len], produced);
    return out[0..produced.len];
}

/// Writes shortest binary64 text into caller-owned `out` and returns a borrowed, non-NUL-terminated slice.
/// Returns `BufferTooSmall` if needed; `NegativeLength` may follow an upstream write.
pub fn format64Shortest(value: f64, out: []u8) Error![]u8 {
    if (out.len >= double_shortest_capacity) return shortest64(value, out);
    if (out.len == 0) return error.BufferTooSmall;
    var temp: [double_shortest_capacity]u8 = undefined;
    const produced = try shortest64(value, &temp);
    if (produced.len > out.len) return error.BufferTooSmall;
    @memcpy(out[0..produced.len], produced);
    return out[0..produced.len];
}

/// Writes fixed-point text with `precision` digits into caller-owned `out`; the returned slice borrows it.
/// Size with `fixedCapacity`; errors are `BufferTooSmall`, `PrecisionTooLarge`, or `NegativeLength`.
pub fn format64Fixed(value: f64, precision: u32, out: []u8) Error![]u8 {
    const needed = try fixedCapacity(precision);
    if (out.len < needed) return error.BufferTooSmall;
    const len = c.d2fixed_buffered_n(value, precision, mutable(out));
    return out[0..try producedLength(len)];
}

/// Writes scientific text with `precision` digits into caller-owned `out`; the returned slice borrows it.
/// Size with `scientificCapacity`; errors are `BufferTooSmall`, `PrecisionTooLarge`, or `NegativeLength`.
pub fn format64Scientific(value: f64, precision: u32, out: []u8) Error![]u8 {
    const needed = try scientificCapacity(precision);
    if (out.len < needed) return error.BufferTooSmall;
    const len = c.d2exp_buffered_n(value, precision, mutable(out));
    return out[0..try producedLength(len)];
}

/// Exposes upstream's experimental string parsers with length-safe inputs and mapped status errors.
/// Accepted grammar and underflow/overflow behavior remain upstream-defined.
pub const experimental = struct {
    /// Parses optional `-`, up to 17 nonzero digits, an optional point, and signed `e`/`E` exponent up to 4 digits.
    /// Other text returns `Error`; underflow produces signed zero and overflow signed infinity.
    pub fn parse64(text: []const u8) Error!f64 {
        if (text.len == 0) return error.InputTooShort;
        const len = std.math.cast(c_int, text.len) orelse return error.TextTooLong;
        var out: f64 = undefined;
        try checkStatus(c.s2d_n(immutable(text), len, &out));
        return out;
    }

    /// Parses optional `-`, up to 9 nonzero digits, an optional point, and signed `e`/`E` exponent up to 4 digits.
    /// Other text returns `Error`; underflow produces signed zero and overflow signed infinity.
    pub fn parse32(text: []const u8) Error!f32 {
        if (text.len == 0) return error.InputTooShort;
        const len = std.math.cast(c_int, text.len) orelse return error.TextTooLong;
        var out: f32 = undefined;
        try checkStatus(c.s2f_n(immutable(text), len, &out));
        return out;
    }
};

/// Maps the parser's four statuses to the facade's corresponding errors.
fn checkStatus(status: c_uint) Error!void {
    if (status == c.SUCCESS) return;
    if (status == c.INPUT_TOO_SHORT) return error.InputTooShort;
    if (status == c.INPUT_TOO_LONG) return error.InputTooLong;
    return error.MalformedInput;
}

// True only when the complete optional generic-128 API was translated.
const has_generic_128 = @hasDecl(c, "float_to_fd128") and
    @hasDecl(c, "double_to_fd128") and
    @hasDecl(c, "long_double_to_fd128") and
    @hasDecl(c, "generic_binary_to_decimal") and
    @hasDecl(c, "generic_to_chars");

/// Optional generic 128-bit converter; `void` when `-Dgeneric128` is disabled.
pub const generic128 = if (has_generic_128) Generic128 else void;

/// Typed wrapper around upstream's optional generic 128-bit converter.
const Generic128 = struct {
    /// The translated upstream `floating_decimal_128` type and layout.
    pub const Decimal = c.floating_decimal_128;

    /// The translated type of `Decimal.mantissa`.
    pub const Mantissa = @FieldType(Decimal, "mantissa");

    /// Target's translated C `long double` type.
    /// Upstream warns conversion support may depend on the compiler and platform.
    pub const LongDouble = @typeInfo(@TypeOf(c.long_double_to_fd128)).@"fn".params[0].type.?;

    /// Sentinel exponent used by upstream to encode infinity or NaN.
    pub const exceptional_exponent: i32 = @intCast(c.FD128_EXCEPTIONAL_EXPONENT);

    /// Maximum bytes written by `toChars`, excluding a terminator.
    pub const to_chars_capacity: usize = 53;

    /// The decimal for a `float`, through `float_to_fd128`.
    pub fn fromFloat(value: f32) Decimal {
        return c.float_to_fd128(value);
    }

    /// The decimal for a `double`, through `double_to_fd128`.
    pub fn fromDouble(value: f64) Decimal {
        return c.double_to_fd128(value);
    }

    /// Converts target `LongDouble`; support follows upstream's platform caveat.
    pub fn fromLongDouble(value: LongDouble) Decimal {
        return c.long_double_to_fd128(value);
    }

    /// Converts a raw floating-point bit pattern with upstream's generic converter.
    /// `mantissa_bits` excludes the implicit bit; set `explicit_leading_bit` accordingly.
    pub fn fromBinary(
        bits: Mantissa,
        mantissa_bits: u32,
        exponent_bits: u32,
        explicit_leading_bit: bool,
    ) Decimal {
        return c.generic_binary_to_decimal(bits, mantissa_bits, exponent_bits, explicit_leading_bit);
    }

    /// Converts `f32`, `f64`, or `LongDouble` through its matching upstream routine.
    /// Other types fail to compile; use `fromBinary` for custom formats.
    pub fn decimalFor(comptime T: type, value: T) Decimal {
        if (T == f32) return c.float_to_fd128(value);
        if (T == f64) return c.double_to_fd128(value);
        if (T == LongDouble) return c.long_double_to_fd128(value);
        @compileError(
            "generic128.decimalFor: upstream has no converter for " ++ @typeName(T) ++
                ". Cast it to f32, f64 or LongDouble only if the conversion is " ++
                "exact - ryu/ryu_generic_128.h:29-31 says not to cast at all - " ++
                "and otherwise pass its own bit pattern to fromBinary.",
        );
    }

    /// Writes a value's shortest decimal form into caller-owned `out`; the result borrows it.
    /// Returns `BufferTooSmall` or `NegativeLength`; spelling follows upstream.
    pub fn shortestChars(comptime T: type, value: T, out: []u8) Error![]u8 {
        return toChars(decimalFor(T, value), out);
    }

    /// Writes a `Decimal` into caller-owned `out` and returns a borrowed slice.
    /// Errors are `BufferTooSmall` or `NegativeLength`.
    pub fn toChars(value: Decimal, out: []u8) Error![]u8 {
        if (out.len >= to_chars_capacity) return writeChars(value, out);
        if (out.len == 0) return error.BufferTooSmall;
        var temp: [to_chars_capacity]u8 = undefined;
        const produced = try writeChars(value, &temp);
        if (produced.len > out.len) return error.BufferTooSmall;
        @memcpy(out[0..produced.len], produced);
        return out[0..produced.len];
    }

    fn writeChars(value: Decimal, out: []u8) Error![]u8 {
        const len = c.generic_to_chars(value, mutable(out));
        return out[0..try producedLength(len)];
    }
};

/// Converts upstream's returned C `int` length to `usize`, rejecting negatives.
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

/// Converts a non-empty mutable slice to the C pointer required by upstream.
fn mutable(out: []u8) [*c]u8 {
    return @ptrCast(&out[0]);
}

/// Converts non-empty input text to the C pointer required by upstream.
fn immutable(text: []const u8) [*c]const u8 {
    return @ptrCast(&text[0]);
}
