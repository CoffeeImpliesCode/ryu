// SPDX-License-Identifier: Apache-2.0
//
//! Zig facade over Ryu's canonical C implementation.
//!
//! No part of the algorithm is reimplemented here. Every digit this module
//! returns is produced by the C under `ryu/`, reached through `pub const c`,
//! the module `b.addTranslateC` produces from upstream's `ryu/ryu.h` and
//! `ryu/ryu_parse.h` - and, in a build configured with `-Dgeneric128`, from
//! `ryu/ryu_generic_128.h` as well. `translate.h` is the aggregate header that
//! translation reads, and it names those headers as upstream ships them. The
//! one disclosed change is a single line of upstream's own: `ryu/ryu.h:24`
//! reads `<stdint.h>` rather than `<inttypes.h>`, for the `uint32_t` that is
//! all that header uses it for. What the facade adds is the part a C header
//! cannot express: a length the compiler checks instead of a length a
//! comment promises, a caller-owned output slice instead of a bare `char*`, an
//! error returned *before* anything is written when the buffer cannot hold the
//! answer or the precision is one the writer cannot represent, a written-out
//! capacity bound for the two modes whose output length depends on a
//! caller-supplied precision, and ownership for the four entry points that
//! hand back a string instead of a length.
//!
//! ## Using it
//!
//! ```zig
//! const std = @import("std");
//! const ryu = @import("ryu");
//!
//! pub fn main() !void {
//!     var shortest: [ryu.double_shortest_capacity]u8 = undefined;
//!     const text = try ryu.format64Shortest(1.25, &shortest);
//!     var scientific: [32]u8 = undefined;
//!     const precise = try ryu.format64Scientific(1.25, 2, &scientific);
//!     std.debug.print("{s} {s}\n", .{ text, precise });
//! }
//! ```
//!
//! `text` is a subslice of `shortest` and dies with it. Nothing here is
//! allocated and nothing has to be released; the caller owns every buffer it
//! passes. The four `*Owned` functions are the exception, and they are named
//! for it: they allocate through upstream's own `malloc`, and they hand back an
//! `OwnedString` whose `deinit` is the C library's `free`.
//!
//! ## Import and raw routes
//!
//! `dep.module("ryu")` is the supported import, and it is also what carries
//! the compiled archive, so a dependent that asks for it links nothing else.
//! Upstream's own declarations are reached from inside it as `ryu.c`. The
//! build registers that same translated module a second time, under the
//! package module name `c`, so `dep.module("c")` resolves for a dependent as
//! well; it is the same declarations with no compiled archive behind them, so
//! `ryu.c` is the route that links. A C consumer links the installed
//! `libryu.a` with `include/ryu/ryu.h` and `include/translate.h`. There is no
//! system-library mode, so no installed ryu is ever linked in its place.
//!
//! Written against Zig 0.16.0, which `build.zig.zon` names as the floor. The
//! targets this module is compiled for are the six `zig build check` names in
//! `build.zig`; nothing in it is target-conditional, and nothing in it depends
//! on `-Dgeneric128` except `generic128` itself, which is `void` in a build that
//! did not configure it.
//!
//! ## Two configurations: linked and runtime-loaded
//!
//! This module is built in one of two shapes, and `runtime_loaded` says which
//! at comptime.
//!
//! *Linked* is the default. The C library is linked, `c` is the translated
//! header, and every call below is a direct call into the archive: no table,
//! no readiness check, no loader state.
//!
//! *Runtime-loaded* is opt-in, with `-Druntime=true`. The archive is not
//! linked; `c` is a dispatch generated from the same translation step's output
//! by `runtime/generate.zig`, and all sixteen entry points `ryu/ryu.h:26-40` and
//! `ryu/ryu_parse.h:36-42` declare - plus the five of
//! `ryu/ryu_generic_128.h:47-66` when that build configured `-Dgeneric128` -
//! are resolved through the platform loader when the caller calls
//!
//! ```zig
//! try ryu.load(.{ .path = "/usr/lib/libryu.so" });
//! ```
//!
//! before using anything else. A call into a module that has not loaded stops
//! the program with a message naming the function, in every optimization mode,
//! because there is no partial table to fall back on. The load itself reports a
//! missing file, a provider that does not export what the header declares, a
//! provider whose allocator is not this process's, a request that cannot be
//! honoured because a different provider already won, or a reentrant call, as
//! errors rather than as a different library being loaded instead.
//!
//! The provider is reached, never guessed. `.path` names a file and `.system`
//! names a library for the platform loader; neither falls back to the other,
//! the module has no unload and no reset, and it keeps the handle and its own
//! copy of the request to the end of the process.
//!
//! The full route, per configuration, is in `runtime/graph.zig`, and what a
//! provider has to be is in `runtime/library.zig`: the sixteen (or twenty-one)
//! names, this target's scalar widths, `enum Status` as an `int`-sized integer,
//! the `struct floating_decimal_128` layout, and - the one that is checked
//! rather than asserted - a `malloc`/`free` pair this process can also use.
//!
//! ## Allocation
//!
//! Two answers, and the difference is upstream's, not a preference here.
//!
//! The buffer functions - `format32Shortest`, `format64Shortest`,
//! `format64Fixed`, `format64Scientific`, `generic128.toChars` - allocate
//! nothing. They call the `*_buffered_n` entry points, which write into a
//! buffer the caller already owns, so the rule about a third-party allocator
//! never arises: buffers in, bytes out, and the caller owns every one of them.
//! Nothing is copied except the bounded copy documented on
//! `format32Shortest`/`format64Shortest`.
//!
//! The owned functions - `format32ShortestOwned`, `format64ShortestOwned`,
//! `format64FixedOwned`, `format64ScientificOwned` - call the four upstream
//! entry points that `malloc` (`ryu/d2s.c:506`, `ryu/f2s.c:342`,
//! `ryu/d2fixed.c:558`, `ryu/d2fixed.c:815`) and hand the allocation back
//! wrapped, with its length. That crosses a real allocator boundary and this
//! module names it rather than glossing it: the memory is the C library's, and
//! **it must be released with the C library's `free`, which is exactly what
//! `OwnedString.deinit` does.** It is not a Zig allocator and must not be given
//! to one. For a shared object and for the process that opened it, `malloc` and
//! `free` are the same two functions, because the dynamic linker resolves both
//! to one libc; `runtime/library.zig` establishes that at load time instead of
//! taking it on trust. The test framework cannot supply a leak oracle across
//! that boundary, so these tests check the answers and the release path, not
//! that a counter went back to zero.
//!
//! ## Errors
//!
//! `Error` is the whole taxonomy, and each member is a condition this module
//! actually checks before or instead of calling upstream:
//!
//!   * `BufferTooSmall` - the caller's slice cannot hold the answer. Upstream's
//!     `*_buffered_n` take a bare `char*` and write whatever they like; the
//!     bound is verified here first, so a rejected call writes nothing at all.
//!   * `PrecisionTooLarge` - `precision` is above what the writer can
//!     represent, because the answer would be longer than the `int` upstream
//!     returns its length in, because the bound does not fit in this target's
//!     `usize`, or - for the two `*Owned` precision writers - because upstream
//!     allocated that writer's buffer itself and this precision would not fit
//!     in it. `format64Scientific` has one more reason to refuse: upstream
//!     raises its own `uint32_t` precision by one, so `std.math.maxInt(u32)`
//!     wraps there and returns a wrong answer rather than a long one. Reachable
//!     on every target, and checked before `out` is measured and before any C
//!     runs, so a rejected call writes nothing.
//!   * `NegativeLength` - upstream's writer returned a negative length. Every
//!     such return is a nonnegative index and the bounds above keep those
//!     indices inside the `int` they are returned as, so this reports a broken
//!     build rather than a caller mistake; it is an ordinary error and not a
//!     panic. It is the one error here that arrives after upstream has
//!     written, and the buffer holds bytes the caller must discard.
//!   * `OutOfMemory` - one of the four `malloc`-ing entry points returned NULL.
//!     Upstream never checks its own `malloc`, so this module does; it is the
//!     only condition an owned-string call has that a buffered one cannot have.
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
//!     `ryu/d2s.c:400-417` and `ryu/f2s.c:290-303`.
//!   * `format64Scientific` writes `e`, an explicit `+` for a nonnegative
//!     exponent, and at least two exponent digits: `1.25e+00`, `1e+54`,
//!     `4.940656...e-324`. Fixed at `ryu/d2fixed.c:788-804`.
//!
//! The special values are upstream's too, and they differ between the two
//! families: shortest prints `NaN`, `Infinity`, `-Infinity` and `0E0`
//! (`ryu/common.h:86-100`), while the fixed and scientific writers print
//! `nan`, `Infinity`, `-Infinity` and, for zero, `0` / `0.0000e+00`
//! (`ryu/d2fixed.c:377-389`, `ryu/d2fixed.c:585-599`, and the shared special
//! string helper at `ryu/d2fixed.c:331-356`). That helper carries two
//! spellings for a NaN, because its `_MSC_VER` half prints a payload with the
//! quiet bit clear as `nan(snan)` rather than `nan`, and upstream's own
//! comment there is an open question rather than an answer
//! (`ryu/d2fixed.c:332-344`). That `#if` is on `_MSC_VER` itself, so which
//! half a target compiles is the compiler's answer and a caller cannot know
//! it, which is why the bounds below are sized for the wider of the two. Both
//! halves are read out of the source here; no target that compiles the
//! `_MSC_VER` half has been exercised, and the one byte that costs is only
//! spent where the arithmetic bound is smaller than either spelling.
//!
//! ## The optional generic 128-bit converter
//!
//! Upstream's third component is off by default and is not part of the
//! conversion core: `-Dgeneric128` compiles `ryu/generic_128.c` and translates
//! `ryu/ryu_generic_128.h`, which is what upstream's own `BUILD` builds as a
//! separate target tagged `nowindows` (`ryu/BUILD:38-49`). It is a shortest
//! converter for *any* IEEE-compatible format up to 128 bits, driven through
//! the raw bit pattern rather than through a native type.
//!
//! `generic128` is that component's typed surface, and it is `void` in a build
//! that did not configure `-Dgeneric128` - not an empty struct and not a set of
//! stubs, because there is nothing there to call. When it is not `void` it
//! names upstream's own `struct floating_decimal_128` rather than a
//! restatement of it, so the layout, the `__uint128_t` width and the `bool` are
//! whatever the target's translation produced, which is what keeps the two
//! nominally identical across the linked and runtime-loaded configurations.
//!
//! ## Threading
//!
//! Nothing here is shared. Every entry point is a pure function of its
//! arguments plus a caller-owned buffer, and all state inside Ryu is on the
//! stack of the call, so concurrent calls on different buffers are as safe as
//! the C is. In a runtime-loaded build the loader is shared and does its own
//! locking; `load` is safe to call from any thread and from more than one at a
//! time, and every other function in this module is as thread-safe as the C it
//! calls.

const std = @import("std");

/// The translated `ryu/ryu.h` and `ryu/ryu_parse.h`, i.e. upstream's ABI
/// exactly as published: the same twelve core functions, the same four
/// parser functions and the same `enum Status`, with `uint32_t` the
/// target's own, taken from the target's own `<stdint.h>`. In a build
/// configured with `-Dgeneric128` it also carries the five entry points and
/// the `struct floating_decimal_128` of `ryu/ryu_generic_128.h`.
///
/// This is the escape hatch for the caller that needs something the facade
/// does not name: `d2s_buffered`, which NUL-terminates in place, or the
/// `malloc`-ing `d2s`/`f2s`/`d2fixed`/`d2exp` whose buffers the caller would
/// then have to `free` itself. A caller that goes through it gets upstream
/// behaviour with none of the guarantees above, which is the point of it
/// being public.
///
/// The build registers this same translated module a second time, under the
/// package module name `c`, so `dep.module("c")` resolves for a dependent. It
/// carries these declarations and no compiled archive, which is why `ryu.c` -
/// the same module reached through the facade, which does link the archive -
/// is the route to build against.
///
/// In a runtime-loading build this module is a generated dispatch instead of
/// the translation step's own output. It publishes the same namespace: every
/// type and constant is re-exported from the translated header rather than
/// restated, so `floating_decimal_128` is the same nominal type either way and
/// nothing here needs a cast. What differs is how a name reaches the library.
/// In the linked configuration it is a direct call; in the runtime-loaded one
/// it is a call through a table that `load` fills, and a call before that fill
/// stops the program with a message naming the function. `runtime_loaded` says
/// which configuration this build is, at comptime.
pub const c = @import("c");

/// The loader core, which is where a linked build's two public types come from.
///
/// It is imported only by the linked configuration. In a runtime-loading build
/// the dispatch carries its own copy of the same declarations, and this module
/// is never referenced, so it is never resolved and never compiled. Either way
/// there is exactly one `LoadSource` and one `LoadError` in a build, which is
/// what keeps them one type for a consumer that names them.
const rt = @import("rt");

/// Whether this module was configured to resolve its native symbols at run
/// time.
///
/// False for the ordinary build, where the C library is linked and `c` is the
/// translated header itself. True when the build generated a dispatch that
/// resolves the same symbols through the platform loader, in which case `load`
/// is the call that makes the library usable.
///
/// It is a comptime constant, so a consumer can write two different code paths
/// and have only the one it chose analyzed.
pub const runtime_loaded: bool = if (@hasDecl(c, "rt_runtime_loaded")) c.rt_runtime_loaded else false;

/// Which native library `load` should open.
///
/// `.path` is an explicit file path and `.system` is an explicit name for the
/// platform loader. There is no path-to-system fallback and no implicit
/// fallback of any kind; a request that cannot be honoured is an error, not a
/// different library.
pub const LoadSource = if (runtime_loaded) c.LoadSource else rt.LoadSource;

/// Every way `load` can decline.
///
/// Declared here, in the module a consumer imports, rather than only inside the
/// loader: the caller names the failure it is handling.
pub const LoadError = if (runtime_loaded) c.LoadError else rt.LoadError;

/// Load the native library this module dispatches to.
///
/// In a runtime-loading build this is the whole contract: call it once, then
/// use this module as if it were linked. Calling it again with the same request
/// succeeds and changes nothing; calling it with a different request after a
/// success is `ProviderMismatch`, and the library already in use stays in use.
/// A failed attempt publishes nothing and can be retried explicitly, by
/// calling this again: there is no automatic retry, and no implicit second
/// source.
///
/// It keeps the process handle and its own copy of the request to the end of
/// the process. There is no unload and no reset, because the table is
/// process-global state that other code may already have called through.
///
/// Safe to call from any thread. A thread that arrives while an attempt for the
/// same request is in flight waits for that attempt and gets its result,
/// whatever it was. A call from the thread that is running the attempt is
/// `ReentrantLoad` rather than a deadlock.
///
/// In a linked build there is no provider, no table and nothing to resolve, so
/// this stops the program with a message saying so instead of quietly
/// succeeding. `runtime_loaded` is false there, so a consumer that supports
/// both configurations can tell the two apart at comptime instead of meeting
/// this at run time.
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

/// The request that succeeded, or null when nothing has loaded yet.
///
/// The answer is the loader's own retained copy and stays valid for the life of
/// the process. Null in a linked build, which has no request.
pub fn loadedSource() ?LoadSource {
    if (comptime !runtime_loaded) return null;
    return c.loadedSource();
}

/// The C library's `free`, the only allocator allowed to release an
/// `OwnedString`.
///
/// Upstream's four allocating entry points call `malloc`
/// (`ryu/d2s.c:506`, `ryu/f2s.c:342`, `ryu/d2fixed.c:558`,
/// `ryu/d2fixed.c:815`) with no allocator argument, so the memory they return
/// belongs to the C library and to nothing else. This is the same `free` a C
/// caller would use on the same pointer, and `runtime/library.zig` declares it
/// for the same reason. It is declared here rather than reached through
/// `std.c` so that the one allocation boundary in this module is visible at the
/// place it is crossed.
extern fn free(ptr: ?*anyopaque) void;

/// Every condition this module refuses, in one closed set.
pub const Error = error{
    /// The caller's slice is shorter than the bound this call can produce.
    /// Nothing was written to it.
    BufferTooSmall,
    /// `precision` is above what this call's writer can represent: the bound
    /// it would produce is longer than the `int` upstream returns a length
    /// in, it does not fit in this target's `usize`, or - for the two `*Owned`
    /// precision writers only - upstream allocated that writer's own 2000 byte
    /// buffer (`ryu/d2fixed.c:558`, `ryu/d2fixed.c:815`) and this precision
    /// would not fit in it. Checked before the output slice is measured and
    /// before any C runs, so nothing was written to it, and a call that
    /// returns this never also returns `error.BufferTooSmall`.
    PrecisionTooLarge,
    /// Upstream's writer returned a negative length. Every return in
    /// `d2s_buffered_n`, `f2s_buffered_n`, `d2fixed_buffered_n` and
    /// `d2exp_buffered_n` is a nonnegative index, and the precision bounds
    /// this module publishes keep those indices inside the `int` they are
    /// returned as, so this reports a broken build rather than a caller
    /// mistake. It is an ordinary error and not a panic.
    ///
    /// Unlike the two capacity failures, this one arrives after the writer has
    /// run: `out` then holds the bytes upstream wrote into it, none of which
    /// the caller can use, and the whole of `out` must be discarded.
    NegativeLength,
    /// One of the four `malloc`-ing entry points returned NULL.
    ///
    /// `d2s`, `f2s`, `d2fixed` and `d2exp` allocate with no check
    /// (`ryu/d2s.c:505-509` and the other three are the same shape), so this is
    /// the one condition an owned-string call has that a buffered one cannot
    /// have. It is checked before the pointer is wrapped, so there is nothing to
    /// release when it is returned. Upstream's shortest writers ask for 25 and
    /// 16 bytes and its precision writers for 2000, so on a target whose
    /// `malloc` refuses those this is a real answer rather than a theoretical
    /// one, and nothing else reports it.
    OutOfMemory,
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
/// length (`ryu/f2s.c:341-345`), so 15 is the number upstream itself trusts.
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

/// The widest answer either precision writer can report, in bytes.
///
/// Upstream accumulates each answer into a signed `int index` and returns that
/// index (`ryu/d2fixed.c:405` and `ryu/d2fixed.c:617`, both declared `int` at
/// `ryu/ryu.h:34` and `ryu/ryu.h:38`). A precision that carries the index
/// past this width wraps it, so the writer hands back a length unrelated to
/// what it wrote - negative across one range of precisions, small and
/// plausible across another. Both bounds are the width of that return rather
/// than the full `u32` range of the precision itself.
const max_written_bytes: u64 = @intCast(std.math.maxInt(c_int));

/// The longest thing the fixed and scientific writers can print that is not a
/// number. Upstream's shared helper has two spellings for it: on the
/// non-MSVC half `-Infinity`, nine bytes (`ryu/d2fixed.c:345-355`), and on the
/// `_MSC_VER` half `-nan(snan)`, ten (`ryu/d2fixed.c:332-344`). The `#if` is
/// on `_MSC_VER` itself, so which half a target compiles is the compiler's
/// answer and a caller cannot know it, which makes the wider of the two the
/// only bound that is safe without one. Both halves are read out of the source
/// here; no target that compiles the `_MSC_VER` half has been exercised. The
/// cost is one byte, and only where the arithmetic bound is smaller: this is
/// what `scientificCapacity` returns at precision 0 and 1.
const special_value_capacity: u64 = 10;

/// Bytes `format64Fixed` guarantees are enough for `value` at `precision`, or
/// `error.PrecisionTooLarge`.
///
/// The bound is deliberately conservative because the exact length depends on
/// the value: it is one sign, at most `max_fixed_integer_digits` integer
/// digits, one point, and exactly `precision` further digits, which is what
/// the finite-value paths of `d2fixed_buffered_n` require
/// (`ryu/d2fixed.c:358-550`: zero at 377-389, the `e2 >= 0` arm at 545-548,
/// and integer/fraction work at 405-544). Special values use 331-356 and
/// ignore the requested fraction length.
///
/// `precision` is accepted up to `2147483336`, which is `max_written_bytes`
/// less this style's overhead. Above that the writer's `int` index cannot
/// hold the answer, so the returned length would be a wrapped number rather
/// than a capacity, and a caller sizing a buffer from it would hand the
/// writer a buffer far shorter than what it is about to write. Above it this
/// returns `error.PrecisionTooLarge` instead, on every target, before
/// anything is written. The bound is accumulated in `u64` first, so no
/// intermediate expression can wrap on the way, and it must still fit in this
/// target's `usize`.
pub fn fixedCapacity(precision: u32) Error!usize {
    if (@as(u64, precision) + fixed_overhead > max_written_bytes) return error.PrecisionTooLarge;
    return std.math.cast(usize, fixed_overhead + @as(u64, precision)) orelse
        error.PrecisionTooLarge;
}

/// Bytes `format64Scientific` guarantees are enough for `value` at
/// `precision`, or `error.PrecisionTooLarge`.
///
/// The bound is one sign, one leading digit, one point, exactly `precision`
/// further digits, `e`, an exponent sign and up to three exponent digits.
/// Rounding carry does not escape it: upstream prints `9.9999` at precision 3
/// as `1.000e+01`, one digit, a point and three digits, which is `precision`
/// plus two, exactly what the arithmetic below reserves
/// (`ryu/d2fixed.c:615-617` raises the precision by one, `ryu/d2fixed.c:788`
/// writes the marker and `ryu/d2fixed.c:796-804` writes two or three exponent
/// digits). The bound never falls below `special_value_capacity`, which is
/// what an answer at precision 0 or 1 can be.
///
/// `precision` is accepted up to `2147483639`, which is `max_written_bytes`
/// less this style's overhead, and refused above it with
/// `error.PrecisionTooLarge` for the same reason and on the same terms as
/// `fixedCapacity`.
pub fn scientificCapacity(precision: u32) Error!usize {
    const bound = @max(scientific_overhead + @as(u64, precision), special_value_capacity);
    if (bound > max_written_bytes) return error.PrecisionTooLarge;
    return std.math.cast(usize, bound) orelse error.PrecisionTooLarge;
}

/// Bytes upstream's two allocating precision writers ask its `malloc` for
/// (`ryu/d2fixed.c:558` and `ryu/d2fixed.c:815`, both `malloc(2000)`).
///
/// This is upstream's buffer, not one this module owns or can grow, and it is
/// the whole difference between a buffered precision writer and an owned one:
/// `format64Fixed` measures the caller's slice and refuses a short one, while
/// `d2fixed` hands the writer a fixed 2000 bytes it allocated itself and checks
/// nothing. A precision whose answer does not fit in that is a buffer overflow
/// inside upstream, so the two `*Owned` precision writers refuse it here
/// instead, before the call. The shortest writers are not affected: `d2s`
/// allocates 25 (`ryu/d2s.c:506`) and `f2s` 16 (`ryu/f2s.c:342`), each of which
/// is the full worst case of its own format plus a terminator - see
/// `double_shortest_capacity` and `float_shortest_capacity`.
const owned_heap_capacity: u64 = 2000;

/// The largest precision `format64FixedOwned` accepts, or
/// `error.PrecisionTooLarge` above it.
///
/// `owned_heap_capacity` bytes have to hold the answer and the NUL byte
/// `d2fixed_buffered` writes after it (`ryu/d2fixed.c:552-555`), so the widest
/// answer is `owned_heap_capacity - 1` bytes: one sign, up to
/// `max_fixed_integer_digits` integer digits, one point and exactly `precision`
/// further digits. Solving for `precision` gives this bound, and it is more than
/// a million times below the `int` limit `fixedCapacity` enforces, so the
/// `*_buffered_n` writer's own limit never reaches it and this one always binds
/// first for an owned call.
pub const owned_max_fixed_precision: u32 = @intCast((owned_heap_capacity - 1) - fixed_overhead);

/// The largest precision `format64ScientificOwned` accepts, or
/// `error.PrecisionTooLarge` above it.
///
/// The same arithmetic with `scientific_overhead`: one sign, one leading digit,
/// one point, `precision` digits, `e`, an exponent sign and up to three
/// exponent digits. The special-value bound is not a second constraint on the
/// precision - `special_value_capacity` is ten bytes whatever `precision` is,
/// and ten is under this limit on its own - so the arithmetic bound is the one
/// that binds.
pub const owned_max_scientific_precision: u32 = @intCast((owned_heap_capacity - 1) - scientific_overhead);

/// A NUL-terminated string one of upstream's `malloc`-ing entry points
/// produced: the only thing in this module that owns memory.
///
/// Four of the sixteen entry points return a `char*` the caller must `free`
/// rather than a length into a buffer the caller already has. They are real,
/// published API, and for a caller that wants a string they are the only way to
/// get one; this type is what makes them usable without restating what upstream
/// already knows about them.
///
/// ## The allocator
///
/// The memory is the C library's: `d2s`, `f2s`, `d2fixed` and `d2exp` call
/// `malloc` with no allocator argument and hand the pointer back
/// (`ryu/d2s.c:505-509`, `ryu/f2s.c:341-345`, `ryu/d2fixed.c:557-562`,
/// `ryu/d2fixed.c:814-819`). `deinit` therefore uses the C library's `free`,
/// which is the same function a C caller would use on the same pointer. A Zig
/// allocator must never be given these bytes, and this module's own test
/// framework cannot report a leak across the boundary - which is why the tests
/// for these four check the answers and the release path and say so.
pub const OwnedString = struct {
    /// Where upstream wrote it. The byte at `len` is upstream's own terminator
    /// and is still there, because none of the four is asked not to write one.
    bytes: [*c]u8,
    /// Its length in bytes, without the terminator.
    len: usize,

    /// The characters, without the terminator.
    ///
    /// Borrowed, like every slice this module returns: the bytes belong to this
    /// value and are released by `deinit`, so the slice cannot outlive it. Use
    /// it before releasing and do not keep it.
    pub fn slice(self: OwnedString) []u8 {
        return self.bytes[0..self.len];
    }

    /// Release the allocation with the C library's `free`.
    ///
    /// Once this returns, `bytes` and `slice` are dangling. Calling it twice is
    /// a double free, exactly as it would be in C; there is no flag here,
    /// because adding one would move the cost of a mistake onto every caller to
    /// protect against one the type system cannot see anyway.
    pub fn deinit(self: OwnedString) void {
        free(@ptrCast(self.bytes));
    }
};

/// Wrap one of upstream's `malloc`-ing returns, refusing the NULL it never
/// checks.
///
/// translate-c types `char*` as `[*:c]u8`, so a null return arrives here as a
/// null address rather than as an optional pointer, and `@intFromPtr` is how it
/// is seen. `std.mem.span` then finds the terminator upstream wrote, which is
/// how the length is known: none of the four entry points returns one.
fn own(raw: [*c]u8) Error!OwnedString {
    if (@intFromPtr(raw) == 0) return error.OutOfMemory;
    return .{ .bytes = raw, .len = std.mem.span(raw).len };
}

/// `format32Shortest` as an owned string: `f2s`, upstream's allocating form.
///
/// The answer is upstream's own - the same bytes, in the same spelling, as the
/// buffered writer produces - and this call returns them NUL-terminated and
/// owned. `f2s` allocates 16 bytes (`ryu/f2s.c:342`), which is the full worst
/// case of the shortest binary32 format plus a terminator, so there is no
/// precision and nothing to refuse but `error.OutOfMemory`.
///
/// Release it with `OwnedString.deinit`, which is the C library's `free` and
/// not a Zig allocator's.
pub fn format32ShortestOwned(value: f32) Error!OwnedString {
    return own(c.f2s(value));
}

/// `format64Shortest` as an owned string: `d2s`, upstream's allocating form.
///
/// As `format32ShortestOwned`, with `d2s`'s own 25 bytes
/// (`ryu/d2s.c:506`) and no precision. The spelling is upstream's and is the
/// same one `format64Shortest` produces: `1E0`, `5E-324`,
/// `1.7976931348623157E308`, `NaN`, `Infinity`, `-Infinity`.
pub fn format64ShortestOwned(value: f64) Error!OwnedString {
    return own(c.d2s(value));
}

/// `format64Fixed` as an owned string: `d2fixed`, upstream's allocating form.
///
/// The rounding, the spelling and the special values are upstream's and are
/// the ones `format64Fixed` documents, because both go through
/// `d2fixed_buffered_n`. What differs is the buffer, and with it the bound:
/// `d2fixed` allocated its own 2000 bytes and checks nothing against them, so
/// a `precision` above `owned_max_fixed_precision` is
/// `error.PrecisionTooLarge` here, before the call, instead of an overflow
/// inside it. That refusal is the reason this function exists in this shape
/// rather than as a thin call.
///
/// Release it with `OwnedString.deinit`.
pub fn format64FixedOwned(value: f64, precision: u32) Error!OwnedString {
    if (precision > owned_max_fixed_precision) return error.PrecisionTooLarge;
    return own(c.d2fixed(value, precision));
}

/// `format64Scientific` as an owned string: `d2exp`, upstream's allocating
/// form.
///
/// As `format64FixedOwned`, with `scientific_overhead` in place of
/// `fixed_overhead`: the bound is `owned_max_scientific_precision`, the writer
/// is `d2exp` over the same `d2exp_buffered_n`, and the spelling is upstream's
/// lowercase `e` with an explicit `+` for a nonnegative exponent. Note that the
/// `std.math.maxInt(u32)` wrap in `ryu/d2fixed.c:616` is out of reach here
/// long before the heap bound refuses it, so the only refusal is the buffer's.
pub fn format64ScientificOwned(value: f64, precision: u32) Error!OwnedString {
    if (precision > owned_max_scientific_precision) return error.PrecisionTooLarge;
    return own(c.d2exp(value, precision));
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
/// The returned slice is a subslice of `out` and borrows it, so a later write
/// to `out` changes those bytes. It is *not* NUL-terminated and no terminator
/// byte is written, because the length is already known; `out` past the
/// returned slice keeps whatever the caller had there, on every path.
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
/// constant instead of 15, and the returned slice carries the same borrowing
/// and termination contract.
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
/// `precision` is a `u32` but is not honoured over its full range. Above
/// `2147483336` this returns `error.PrecisionTooLarge`, and it does so before
/// `out` is measured at all, so a precision that is refused is
/// `error.PrecisionTooLarge` rather than `error.BufferTooSmall` whatever the
/// buffer looks like, and `out` keeps every byte it had.
///
/// The returned slice is a subslice of `out` and borrows it, so a later write
/// to `out` changes those bytes. It is not NUL-terminated and no terminator
/// byte is written. The one error that arrives after upstream has written is
/// `error.NegativeLength`; `out` then holds what upstream put there, none of
/// it usable, and the whole of `out` must be discarded.
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
/// `out.len` is treated exactly as on `format64Fixed`, with
/// `scientificCapacity(precision)` as the bound, the returned subslice carries
/// the same borrowing and termination contract, and the residue after an error
/// is the same. `precision` is accepted up to `2147483639` and refused above
/// it with `error.PrecisionTooLarge`, before `out` is measured; upstream's own
/// `++precision` (`ryu/d2fixed.c:616`) would otherwise wrap at
/// `std.math.maxInt(u32)` and return a wrong, short answer rather than a long
/// one.
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
/// your own risk."* (`ryu/ryu_parse.h:24-27`). Nothing about it is stabilised
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

/// True when this build translated `ryu/ryu_generic_128.h`, which is what
/// `-Dgeneric128` is for.
///
/// All five entry points or none of them. A header that declared some of them
/// and not the others is not a configuration this build produces: the option
/// compiles `ryu/generic_128.c` and the header together, so there is no partial
/// component to publish half of, and the count that `runtime/generate.zig`
/// resolved is the same sixteen or twenty-one.
const has_generic_128 = @hasDecl(c, "float_to_fd128") and
    @hasDecl(c, "double_to_fd128") and
    @hasDecl(c, "long_double_to_fd128") and
    @hasDecl(c, "generic_binary_to_decimal") and
    @hasDecl(c, "generic_to_chars");

/// Upstream's optional generic 128-bit shortest converter, or `void` in a build
/// that did not configure `-Dgeneric128`.
///
/// It is `void` and not a struct of stubs: in a default build none of the five
/// entry points was compiled into the artifact and none was translated, so
/// there is nothing here to call and a struct of functions that cannot work
/// would be a lie with a signature on it. A consumer that supports both builds
/// can branch on it at comptime, the way this declaration branches on the
/// header's own declarations.
pub const generic128 = if (has_generic_128) Generic128 else void;

/// The typed surface of `ryu/ryu_generic_128.h`. See `generic128`.
///
/// Upstream calls this "a generic 128-bit implementation of float to shortest
/// conversion ... It can handle any IEEE-compatible floating-point type up to
/// 128 bits" (`ryu/ryu_generic_128.h:27-36`), and the one instruction that
/// matters to a caller is the warning above it: use the `*_to_fd128` function
/// for the type you have, and **do not cast your input to another floating-point
/// type**. `fromBinary` is the escape it names, for a type upstream has no
/// converter for.
const Generic128 = struct {
    /// Upstream's `struct floating_decimal_128` (`ryu/ryu_generic_128.h:41-45`),
    /// as the target's translation produced it: `__uint128_t mantissa`,
    /// `int32_t exponent`, `bool sign`.
    ///
    /// This is upstream's type and not a copy of it, which is what keeps the
    /// struct's layout, its 128-bit field and its padding the same nominal
    /// thing in the linked configuration, in the runtime-loaded one and in the
    /// C library the provider was built from. Nothing here recomputes it.
    pub const Decimal = c.floating_decimal_128;

    /// The `mantissa` field's type as this target spelled `__uint128_t`.
    ///
    /// Read out of the translated struct rather than written as `u128`, because
    /// `__uint128_t` is not a standard C type and a translator is free to
    /// represent it however it does. Whatever it chose is what a value read
    /// from a `Decimal` is, and what `fromBinary` takes.
    pub const Mantissa = @FieldType(Decimal, "mantissa");

    /// `long double` as this target spelled it.
    ///
    /// Taken from the one parameter upstream declares rather than from a type
    /// name, because "long double" means 64, 80 or 128 bits depending on the
    /// target and on the compiler, and upstream says so itself
    /// (`ryu/ryu_generic_128.h:50-51`: this "likely only works on x86 with
    /// specific compilers"). That caveat is upstream's and is carried here
    /// unchanged: this is the type the declaration was translated to, not a
    /// promise that `long_double_to_fd128` works everywhere.
    ///
    /// On the pinned Zig that translation reads `long_double_to_fd128(d:
    /// c_longdouble)`, so `LongDouble` is Zig's opaque C `long double` and not
    /// `f80` on any target, and Zig has no way to write a value for it
    /// (`lib/std/zig/c_translation/helpers.zig:387`). That is this route's
    /// honest cost. The x87 answer stays reachable the other two ways upstream
    /// offers it: `fromBinary` with upstream's own 64/15/explicit triple
    /// (`ryu/generic_128.c:80`), and C, where `long double` is the language's.
    pub const LongDouble = @typeInfo(@TypeOf(c.long_double_to_fd128)).@"fn".params[0].type.?;

    /// `FD128_EXCEPTIONAL_EXPONENT` (`ryu/ryu_generic_128.h:38`), the
    /// exponent upstream's own converter puts in a `Decimal` for an infinity or
    /// a NaN (`ryu/generic_128.c:108`). `toChars` recognises it and prints
    /// `NaN` or `Infinity` instead of digits.
    pub const exceptional_exponent: i32 = @intCast(c.FD128_EXCEPTIONAL_EXPONENT);

    /// Bytes `generic_to_chars` can ever write, excluding a terminator.
    ///
    /// Upstream's own bound (`ryu/ryu_generic_128.h:62-65`), kept as written:
    /// sign + 39 mantissa digits + point + `E` + exponent sign + 10 exponent
    /// digits = 53. `generic_to_chars` writes no terminator
    /// (`ryu/generic_128.h:59-61`), so a buffer of exactly this size is enough
    /// and one byte less is not.
    pub const to_chars_capacity: usize = 53;

    /// The decimal for a `float`, through `float_to_fd128`.
    pub fn fromFloat(value: f32) Decimal {
        return c.float_to_fd128(value);
    }

    /// The decimal for a `double`, through `double_to_fd128`.
    pub fn fromDouble(value: f64) Decimal {
        return c.double_to_fd128(value);
    }

    /// The decimal for a `long double`, through `long_double_to_fd128`.
    ///
    /// See `LongDouble` for upstream's own caveat about this one.
    pub fn fromLongDouble(value: LongDouble) Decimal {
        return c.long_double_to_fd128(value);
    }

    /// The decimal for a floating-point type upstream has no converter for,
    /// through `generic_binary_to_decimal`.
    ///
    /// `mantissa_bits` is the width of the mantissa *excluding* the implicit
    /// leading bit, except for a format that carries one explicitly, which is
    /// what `explicit_leading_bit` says: upstream passes `false` for binary32
    /// and binary64 and `true` for x87 `long double`
    /// (`ryu/generic_128.c:55,64,80`). Getting either wrong produces a wrong
    /// answer rather than an error, which is why upstream's header warns twice
    /// and why these three arguments are not optional here.
    pub fn fromBinary(
        bits: Mantissa,
        mantissa_bits: u32,
        exponent_bits: u32,
        explicit_leading_bit: bool,
    ) Decimal {
        return c.generic_binary_to_decimal(bits, mantissa_bits, exponent_bits, explicit_leading_bit);
    }

    /// The decimal for `value`, choosing the converter for its own type.
    ///
    /// This is upstream's instruction made mechanical: a `f32` goes through
    /// `float_to_fd128`, a `f64` through `double_to_fd128` and a `LongDouble`
    /// through `long_double_to_fd128`, and nothing is cast on the way. Any
    /// other type does not compile here; use `fromBinary` with that type's own
    /// bit pattern, which is the route upstream's header points at for a
    /// floating-point type the compiler does not define.
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

    /// `value` in the shortest decimal spelling that reads back as `value`, into
    /// a caller-owned buffer.
    ///
    /// `out` is treated exactly as on `format64Shortest`: at least
    /// `to_chars_capacity` bytes is written into directly and nothing is
    /// copied, a smaller buffer is written through a 53 byte stack temporary
    /// and the produced prefix is copied into it, and a buffer that is small
    /// and still too small is `error.BufferTooSmall` with `out` untouched.
    /// The returned slice borrows `out` and is not NUL-terminated.
    ///
    /// The spelling is upstream's and is not the shortest writer's: an
    /// uppercase `E`, no `+` on a nonnegative exponent and no exponent padding,
    /// so `1.25` is `1.25E0` and `1e-45` is `1E-45`
    /// (`ryu/generic_128.c:325-344`). An infinity or a NaN is `Infinity` or
    /// `NaN`, and a NaN carries no sign (`ryu/generic_128.c:284-294`).
    pub fn shortestChars(comptime T: type, value: T, out: []u8) Error![]u8 {
        return toChars(decimalFor(T, value), out);
    }

    /// `generic_to_chars`: a `Decimal` written as characters into `out`.
    ///
    /// The same buffer contract as `shortestChars`, against
    /// `to_chars_capacity`.
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
