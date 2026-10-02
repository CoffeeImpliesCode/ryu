//! A runnable, deterministic demonstration of the Ryu facade.
//!
//! `zig build smoke` runs this. There is no input to supply and no output that
//! depends on the host, the clock or a random seed, so the same lines come out
//! every time.
//!
//! Every expected string below is an answer, not a value this program computed
//! and printed for comparison. Three of them are the assignment's own known
//! answers for the decimal 1.25, and the rest come out of upstream's published
//! suite; the comment on each names which. A mismatch prints both sides and
//! exits non-zero, so this is a check and not a demo.
//!
//! The expected answers are also chosen to pin the parts of upstream's output
//! that are easy to get wrong by accident: the two scientific styles really do
//! have different markings (`1.25E0` from the shortest writer against
//! `1.25e+00` from the precision writer), the special values really do differ
//! between the two families (`NaN` and `Infinity` against `nan`), and a tie
//! really does go to even.
//!
//! There is no allocator here. The two precision writers need a bound that
//! depends on the precision, and for the small precisions this program uses a
//! fixed stack buffer is comfortably past that bound; the exact-bound
//! arithmetic is exercised in the test suite, where a buffer of exactly
//! `fixedCapacity(p)` bytes is handed over for every published answer.

const std = @import("std");
const ryu = @import("ryu");

pub fn main() !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    try w.print("ryu smoke\n", .{});

    // Through the raw escape hatch first, so the line below is the C library
    // that got linked rather than a constant compiled into this program. This
    // is upstream's own entry point, reached through `pub const c`.
    var raw: [ryu.double_shortest_capacity]u8 = undefined;
    const raw_len = ryu.c.d2s_buffered_n(1.25, &raw);
    if (raw_len < 0) return error.NegativeLength;
    try check(w, "c.d2s_buffered_n(1.25)", raw[0..@intCast(raw_len)], "1.25E0");

    // The assignment's three known answers for the decimal 1.25, kept together
    // so the three markings are visible on adjacent lines.
    var shortest: [ryu.double_shortest_capacity]u8 = undefined;
    try check(w, "format64Shortest(1.25)", try ryu.format64Shortest(1.25, &shortest), "1.25E0");

    var precision_buffer: [1024]u8 = undefined;
    try check(w, "format64Fixed(1.25, 3)", try ryu.format64Fixed(1.25, 3, &precision_buffer), "1.250");
    try check(
        w,
        "format64Scientific(1.25, 2)",
        try ryu.format64Scientific(1.25, 2, &precision_buffer),
        "1.25e+00",
    );

    // The shortest writer writes the same answer into a buffer that holds only
    // that answer, so the documentation's "a buffer large enough for this
    // particular answer is enough" claim is shown rather than asserted.
    var tight: [6]u8 = undefined;
    try check(w, "format64Shortest(1.25) into 6 bytes", try ryu.format64Shortest(1.25, &tight), "1.25E0");

    // The special values, from ryu/ryu/tests/d2s_test.cc D2sTest.Basic.
    try check(w, "format64Shortest(0.0)", try ryu.format64Shortest(0.0, &shortest), "0E0");
    try check(w, "format64Shortest(-0.0)", try ryu.format64Shortest(-0.0, &shortest), "-0E0");
    try check(w, "format64Shortest(inf)", try ryu.format64Shortest(std.math.inf(f64), &shortest), "Infinity");
    try check(w, "format64Shortest(-inf)", try ryu.format64Shortest(-std.math.inf(f64), &shortest), "-Infinity");
    try check(w, "format64Shortest(nan)", try ryu.format64Shortest(std.math.nan(f64), &shortest), "NaN");
    try check(w, "format64Fixed(nan, 2)", try ryu.format64Fixed(std.math.nan(f64), 2, &precision_buffer), "nan");

    // The extremes, from D2sTest.MinAndMax and D2sTest.SwitchToSubnormal.
    try check(w, "format64Shortest(5e-324)", try ryu.format64Shortest(5.0e-324, &shortest), "5E-324");
    try check(
        w,
        "format64Shortest(DBL_MAX)",
        try ryu.format64Shortest(1.7976931348623157e308, &shortest),
        "1.7976931348623157E308",
    );
    try check(
        w,
        "format64Shortest(DBL_MIN)",
        try ryu.format64Shortest(2.2250738585072014e-308, &shortest),
        "2.2250738585072014E-308",
    );

    // The 32 bit writer, from F2sTest.MinAndMax, F2sTest.SwitchToSubnormal and
    // F2sTest.OutputLength.
    var shortest32: [ryu.float_shortest_capacity]u8 = undefined;
    try check(w, "format32Shortest(3.4028235e38)", try ryu.format32Shortest(3.4028235e38, &shortest32), "3.4028235E38");
    try check(w, "format32Shortest(1e-45)", try ryu.format32Shortest(1.0e-45, &shortest32), "1E-45");
    try check(w, "format32Shortest(0.1)", try ryu.format32Shortest(0.1, &shortest32), "1E-1");

    // Rounding, from D2fixedTest.RoundToEvenInteger, D2fixedTest.Carrying and
    // D2expTest.Carrying. A tie goes to even, and a run of nines carries.
    try check(w, "format64Fixed(2.5, 0)", try ryu.format64Fixed(2.5, 0, &precision_buffer), "2");
    try check(w, "format64Fixed(3.5, 0)", try ryu.format64Fixed(3.5, 0, &precision_buffer), "4");
    try check(w, "format64Fixed(9.9999, 3)", try ryu.format64Fixed(9.9999, 3, &precision_buffer), "10.000");
    try check(
        w,
        "format64Scientific(9.9999, 3)",
        try ryu.format64Scientific(9.9999, 3, &precision_buffer),
        "1.000e+01",
    );

    // Upstream's experimental parser, from ryu/ryu/tests/s2d_test.cc Basic,
    // MinMax and BadInput. Its statuses are upstream's own.
    try checkBits(w, "experimental.parse64(\"1.25E0\")", try ryu.experimental.parse64("1.25E0"), 1.25);
    try checkBits(w, "experimental.parse64(\"5E-324\")", try ryu.experimental.parse64("5E-324"), 5.0e-324);
    try checkBits(w, "experimental.parse64(\"-0\")", try ryu.experimental.parse64("-0"), -0.0);

    if (ryu.experimental.parse64("123456789012345678")) |value| {
        std.debug.print("expected a rejection from parse64, got {d}\n", .{value});
        return error.SmokeCheckFailed;
    } else |err| {
        try w.print("{s: <44}{s}\n", .{ "experimental.parse64(18 digits)", @errorName(err) });
        if (err != error.InputTooLong) return error.SmokeCheckFailed;
    }

    if (ryu.experimental.parse64("1..1")) |value| {
        std.debug.print("expected a rejection from parse64, got {d}\n", .{value});
        return error.SmokeCheckFailed;
    } else |err| {
        try w.print("{s: <44}{s}\n", .{ "experimental.parse64(\"1..1\")", @errorName(err) });
        if (err != error.MalformedInput) return error.SmokeCheckFailed;
    }

    // The two documented bounds, shown as the numbers the docs state.
    try w.print("{s: <44}{d}\n", .{ "double_shortest_capacity", ryu.double_shortest_capacity });
    try w.print("{s: <44}{d}\n", .{ "float_shortest_capacity", ryu.float_shortest_capacity });
    try w.print("{s: <44}{d}\n", .{ "fixedCapacity(0)", try ryu.fixedCapacity(0) });
    try w.print("{s: <44}{d}\n", .{ "scientificCapacity(0)", try ryu.scientificCapacity(0) });

    try w.print("every answer matched\n", .{});
    try w.flush();
}

/// Print one answer and fail if it is not the expected one.
fn check(w: *std.Io.Writer, what: []const u8, answer: []const u8, expected: []const u8) !void {
    try w.print("{s: <44}{s}\n", .{ what, answer });
    if (!std.mem.eql(u8, expected, answer)) {
        std.debug.print("{s}: expected {s}, the answer is {s}\n", .{ what, expected, answer });
        return error.SmokeCheckFailed;
    }
}

/// Print a parsed value and fail if it is not bit-for-bit the expected one.
fn checkBits(w: *std.Io.Writer, what: []const u8, answer: f64, expected: f64) !void {
    try w.print("{s: <44}{d}\n", .{ what, answer });
    if (@as(u64, @bitCast(answer)) != @as(u64, @bitCast(expected))) {
        std.debug.print("{s}: expected {d}, the answer is {d}\n", .{ what, expected, answer });
        return error.SmokeCheckFailed;
    }
}
