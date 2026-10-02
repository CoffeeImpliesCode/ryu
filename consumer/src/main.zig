//! Consumes the `ryu` package the way an outside project would.
//!
//! Everything here goes through the published surface only: `dep.module` in
//! `build.zig`, and `@import("ryu")` here. No path reaches into the library's
//! own tree, so if this builds and produces the answers below, the module
//! contract is real.
//!
//! Every expected string is upstream's published answer for that exact value,
//! from the gtest cases in `ryu/ryu/tests/`; the comment on each names which.
//! They are independent of what the library just did, so a mismatch is a real
//! fault rather than a restatement of it. Any mismatch exits non-zero.
//!
//! The answers are printed even when they match, because the two scientific
//! styles and the two spellings of the special values are the part of this
//! library a reader is most likely to doubt without seeing them.

const std = @import("std");
const ryu = @import("ryu");

/// The decimal this consumer is built around. It is the value the assignment
/// names, and it is exactly representable in both binary32 and binary64, so
/// its three spellings are all exact and none of them depends on rounding.
const one_and_a_quarter: f64 = 1.25;

pub fn main() !void {
    var threaded: std.Io.Threaded = .init(std.heap.page_allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(io, &buffer);
    const w = &stdout.interface;

    try w.print("ryu consumer\n", .{});

    // Through the raw escape hatch first, so this line is the C entry point
    // that was linked into this binary rather than a constant compiled into
    // the source. It is also the proof that `pub const c` survives the module
    // boundary: an outside package reaches upstream's own declaration.
    var raw: [ryu.double_shortest_capacity]u8 = undefined;
    const raw_len = ryu.c.d2s_buffered_n(one_and_a_quarter, &raw);
    if (raw_len < 0) return error.NegativeLength;
    try check(w, "c.d2s_buffered_n(1.25)", raw[0..@intCast(raw_len)], "1.25E0");

    // The three known answers for 1.25, on adjacent lines so the difference
    // between the two exponent styles is visible in the output.
    var shortest: [ryu.double_shortest_capacity]u8 = undefined;
    try check(w, "format64Shortest(1.25)", try ryu.format64Shortest(one_and_a_quarter, &shortest), "1.25E0");

    var precision_buffer: [1024]u8 = undefined;
    try check(
        w,
        "format64Fixed(1.25, 3)",
        try ryu.format64Fixed(one_and_a_quarter, 3, &precision_buffer),
        "1.250",
    );
    try check(
        w,
        "format64Scientific(1.25, 2)",
        try ryu.format64Scientific(one_and_a_quarter, 2, &precision_buffer),
        "1.25e+00",
    );

    var shortest32: [ryu.float_shortest_capacity]u8 = undefined;
    try check(
        w,
        "format32Shortest(1.25)",
        try ryu.format32Shortest(one_and_a_quarter, &shortest32),
        "1.25E0",
    );

    // The special values, which differ between the two families, from
    // ryu/ryu/tests/d2s_test.cc D2sTest.Basic and ryu/d2fixed.c:331-356.
    try check(w, "format64Shortest(0.0)", try ryu.format64Shortest(0.0, &shortest), "0E0");
    try check(w, "format64Shortest(-0.0)", try ryu.format64Shortest(-0.0, &shortest), "-0E0");
    try check(w, "format64Shortest(inf)", try ryu.format64Shortest(std.math.inf(f64), &shortest), "Infinity");
    try check(w, "format64Shortest(nan)", try ryu.format64Shortest(std.math.nan(f64), &shortest), "NaN");
    try check(w, "format64Fixed(inf, 2)", try ryu.format64Fixed(std.math.inf(f64), 2, &precision_buffer), "Infinity");
    try check(w, "format64Scientific(0.0, 2)", try ryu.format64Scientific(0.0, 2, &precision_buffer), "0.00e+00");

    // The extremes, from D2sTest.MinAndMax and D2sTest.SwitchToSubnormal.
    try check(w, "format64Shortest(5e-324)", try ryu.format64Shortest(5.0e-324, &shortest), "5E-324");
    try check(
        w,
        "format64Shortest(DBL_MAX)",
        try ryu.format64Shortest(1.7976931348623157e308, &shortest),
        "1.7976931348623157E308",
    );

    // Rounding, from D2fixedTest.RoundToEvenInteger and D2fixedTest.Carrying.
    try check(w, "format64Fixed(3.5, 0)", try ryu.format64Fixed(3.5, 0, &precision_buffer), "4");
    try check(w, "format64Fixed(9.9999, 3)", try ryu.format64Fixed(9.9999, 3, &precision_buffer), "10.000");

    // A caller-owned buffer that is exactly the documented bound. The bound is
    // a promise the consumer can plan against, so the consumer spends the
    // exact number of bytes it is told to and no more.
    try check(
        w,
        "format64Fixed into exactly fixedCapacity(3) bytes",
        try ryu.format64Fixed(one_and_a_quarter, 3, precision_buffer[0..try ryu.fixedCapacity(3)]),
        "1.250",
    );

    // Upstream's experimental parser, reached across the module boundary, from
    // ryu/ryu/tests/s2d_test.cc Basic.
    const parsed = try ryu.experimental.parse64("1.25E0");
    try w.print("{s: <44}{d}\n", .{ "experimental.parse64(\"1.25E0\")", parsed });
    if (@as(u64, @bitCast(parsed)) != @as(u64, @bitCast(one_and_a_quarter))) {
        std.debug.print("experimental.parse64(\"1.25E0\"): expected 1.25, got {d}\n", .{parsed});
        return error.ConsumerCheckFailed;
    }

    try w.print("every answer matched the published values\n", .{});
    try w.flush();
}

/// Print one answer and fail if it is not the expected one.
fn check(w: *std.Io.Writer, what: []const u8, answer: []const u8, expected: []const u8) !void {
    try w.print("{s: <44}{s}\n", .{ what, answer });
    if (!std.mem.eql(u8, expected, answer)) {
        std.debug.print("{s}: expected {s}, the answer is {s}\n", .{ what, expected, answer });
        return error.ConsumerCheckFailed;
    }
}
