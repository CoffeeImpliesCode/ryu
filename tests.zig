//! Behavioural tests for the Ryu facade.
//!
//! There are three kinds of evidence here and they are kept apart on purpose.
//!
//! 1. **Published known answers.** `testdata/` holds, verbatim, the strings
//!    upstream's own gtest cases assert, with the file and line each came
//!    from recorded in the fixture's header. Four tests walk those fixtures
//!    and demand that the facade produce exactly the published bytes. That is
//!    the primary oracle: an independent answer, produced by a different
//!    implementation, not by this code.
//!
//! 2. **An independent parser.** For every published shortest answer, Zig's
//!    own `std.fmt.parseFloat` must read the published string back as the
//!    fixture's own input bit pattern. If a fixture row recorded the wrong
//!    answer, or the wrong input for the right answer, this disagrees with it.
//!    Zig's parser is a completely different implementation from Ryu's.
//!
//! 3. **An independent formatter.** For a curated set of values, Zig's own
//!    `std.fmt` float formatter must agree with the facade digit for digit,
//!    once the two output styles' exponent spelling is normalised. Zig's
//!    shortest formatter is Errol/Grisu and its fixed and scientific
//!    formatters are its own; Ryu is none of those. The curated set is
//!    curated on purpose: see the comment on the tie test for which values
//!    Zig and Ryu deliberately disagree about.
//!
//! The error-path tests are the other half: what the facade refuses, and the
//! fact that a refused call writes nothing at all.
//!
//! No test here pins a version string, an export, a default, or a call that
//! merely does not fail. Every one either reproduces a published answer,
//! cross-checks against a different implementation, or proves a boundary.

const std = @import("std");
const ryu = @import("ryu");

/// A line-oriented reader over one `testdata/` fixture, skipping the `#`
/// header and any blank line.
const Fixture = struct {
    text: []const u8,
    at: usize = 0,

    fn init(comptime path: []const u8) Fixture {
        return .{ .text = @embedFile(path) };
    }

    fn next(self: *Fixture) ?[]const u8 {
        while (self.at < self.text.len) {
            const rest = self.text[self.at..];
            const end = std.mem.indexOfScalar(u8, rest, '\n') orelse rest.len;
            self.at += end + 1;
            const line = std.mem.trim(u8, rest[0..end], " \t\r");
            if (line.len == 0 or line[0] == '#') continue;
            return line;
        }
        return null;
    }
};

fn f64FromSpec(spec: []const u8) !f64 {
    if (std.mem.eql(u8, spec, "zero")) return 0.0;
    if (std.mem.eql(u8, spec, "negzero")) return -0.0;
    if (std.mem.eql(u8, spec, "inf")) return std.math.inf(f64);
    if (std.mem.eql(u8, spec, "neginf")) return -std.math.inf(f64);
    if (std.mem.eql(u8, spec, "nan")) return std.math.nan(f64);
    if (std.mem.startsWith(u8, spec, "bits ")) {
        return @bitCast(try std.fmt.parseInt(u64, spec["bits ".len..], 16));
    }
    if (std.mem.startsWith(u8, spec, "parts ")) {
        var fields = std.mem.splitScalar(u8, spec["parts ".len..], ' ');
        const sign = try std.fmt.parseInt(u8, fields.next().?, 10);
        const exponent = try std.fmt.parseInt(u32, fields.next().?, 10);
        const mantissa = fields.next().?;
        const low = if (std.mem.startsWith(u8, mantissa, "0x"))
            try std.fmt.parseInt(u64, mantissa[2..], 16)
        else
            try std.fmt.parseInt(u64, mantissa, 10);
        return @bitCast((@as(u64, sign) << 63) | (@as(u64, exponent) << 52) | low);
    }
    if (std.mem.startsWith(u8, spec, "lit ")) {
        return std.fmt.parseFloat(f64, spec["lit ".len..]);
    }
    return error.UnknownSpec;
}

fn f32FromSpec(spec: []const u8) !f32 {
    if (std.mem.eql(u8, spec, "zero")) return 0.0;
    if (std.mem.eql(u8, spec, "negzero")) return -0.0;
    if (std.mem.eql(u8, spec, "inf")) return std.math.inf(f32);
    if (std.mem.eql(u8, spec, "neginf")) return -std.math.inf(f32);
    if (std.mem.eql(u8, spec, "nan")) return std.math.nan(f32);
    if (std.mem.startsWith(u8, spec, "bits ")) {
        return @bitCast(try std.fmt.parseInt(u32, spec["bits ".len..], 16));
    }
    // No `parts` form: upstream states no 32-bit case by exponent and
    // mantissa, and an unrecognised form fails loudly rather than silently.
    if (std.mem.startsWith(u8, spec, "lit ")) {
        return std.fmt.parseFloat(f32, spec["lit ".len..]);
    }
    return error.UnknownSpec;
}

/// Whether Zig's shortest spelling and Ryu's are the same string once the one
/// difference between the two styles - Ryu's uppercase exponent marker
/// against Zig's lowercase - is set aside. Nothing else is touched, and
/// nothing is allocated to do it.
fn shortestSpellingMatches(zig: []const u8, ryu_text: []const u8) bool {
    if (zig.len != ryu_text.len) return false;
    for (zig, ryu_text) |want, got| {
        if (want != if (got == 'E') 'e' else got) return false;
    }
    return true;
}

/// Split a scientific string into its mantissa and its exponent as a signed
/// number. Ryu's exponent carries an explicit `+` and at least two digits;
/// Zig's carries neither. Only the number is compared.
fn scientificParts(s: []const u8) !struct { mantissa: []const u8, exponent: i64 } {
    const at = std.mem.indexOfScalar(u8, s, 'e') orelse return error.NoExponentMarker;
    const text = s[at + 1 ..];
    const signed = if (text.len != 0 and text[0] == '+') text[1..] else text;
    return .{ .mantissa = s[0..at], .exponent = try std.fmt.parseInt(i64, signed, 10) };
}

fn expectedParseError(status: []const u8) anyerror {
    if (std.mem.eql(u8, status, "input_too_short")) return error.InputTooShort;
    if (std.mem.eql(u8, status, "input_too_long")) return error.InputTooLong;
    return error.MalformedInput;
}

/// Sentinel used to prove that a refused call wrote nothing.
const untouched: u8 = 0xA5;

fn expectUntouched(buffer: []const u8) !void {
    for (buffer) |byte| {
        if (byte != untouched) return error.WroteIntoARefusedBuffer;
    }
}

/// Demand that `value` at `precision` prints as `fixed` in the fixed-point
/// style and as `scientific` in the scientific one, each into a buffer of
/// exactly the bound that style publishes for that precision.
///
/// The buffers are exactly the bound, not larger, so a bound one byte short of
/// a real answer fails here rather than passing on slack.
fn expectBothPrecisionStyles(
    value: f64,
    precision: u32,
    fixed: []const u8,
    scientific: []const u8,
) !void {
    const fixed_buffer = try std.testing.allocator.alloc(u8, try ryu.fixedCapacity(precision));
    defer std.testing.allocator.free(fixed_buffer);
    try std.testing.expectEqualStrings(fixed, try ryu.format64Fixed(value, precision, fixed_buffer));

    const scientific_buffer = try std.testing.allocator.alloc(u8, try ryu.scientificCapacity(precision));
    defer std.testing.allocator.free(scientific_buffer);
    try std.testing.expectEqualStrings(
        scientific,
        try ryu.format64Scientific(value, precision, scientific_buffer),
    );
}

// --- 1. Published known answers ------------------------------------------------

test "binary64 shortest reproduces every published answer" {
    // The count is here only so a fixture that stopped parsing cannot turn
    // this into a loop that never runs. The assertions are the comparisons.
    var fixture = Fixture.init("testdata/d2s_shortest.txt");
    var seen: usize = 0;
    while (fixture.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const spec = fields.next().?;
        const expected = fields.next().?;
        const value = try f64FromSpec(spec);

        var buffer: [ryu.double_shortest_capacity]u8 = undefined;
        const got = try ryu.format64Shortest(value, &buffer);
        if (!std.mem.eql(u8, expected, got)) {
            std.debug.print("d2s {s}: expected {s}, got {s}\n", .{ spec, expected, got });
            return error.NotThePublishedAnswer;
        }
        seen += 1;
    }
    try std.testing.expectEqual(@as(usize, 132), seen);
}

test "binary32 shortest reproduces every published answer" {
    var fixture = Fixture.init("testdata/f2s_shortest.txt");
    var seen: usize = 0;
    while (fixture.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const spec = fields.next().?;
        const expected = fields.next().?;
        const value = try f32FromSpec(spec);

        var buffer: [ryu.float_shortest_capacity]u8 = undefined;
        const got = try ryu.format32Shortest(value, &buffer);
        if (!std.mem.eql(u8, expected, got)) {
            std.debug.print("f2s {s}: expected {s}, got {s}\n", .{ spec, expected, got });
            return error.NotThePublishedAnswer;
        }
        seen += 1;
    }
    try std.testing.expectEqual(@as(usize, 60), seen);
}

test "binary64 fixed point reproduces every published answer" {
    var fixture = Fixture.init("testdata/d2fixed.txt");
    var seen: usize = 0;
    while (fixture.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const spec = fields.next().?;
        const precision = try std.fmt.parseInt(u32, fields.next().?, 10);
        const expected = fields.next().?;
        const value = try f64FromSpec(spec);

        // Exactly the number of bytes the facade documents as sufficient, so
        // this also proves the published bound is not one byte short of a real
        // answer - the 1075 byte row at precision 1073 is in this fixture.
        const needed = try ryu.fixedCapacity(precision);
        const buffer = try std.testing.allocator.alloc(u8, needed);
        defer std.testing.allocator.free(buffer);

        const got = try ryu.format64Fixed(value, precision, buffer);
        if (!std.mem.eql(u8, expected, got)) {
            std.debug.print("d2fixed {s} p={d}: expected {s}, got {s}\n", .{ spec, precision, expected, got });
            return error.NotThePublishedAnswer;
        }
        seen += 1;
    }
    try std.testing.expectEqual(@as(usize, 134), seen);
}

test "binary64 scientific reproduces every published answer" {
    var fixture = Fixture.init("testdata/d2exp.txt");
    var seen: usize = 0;
    while (fixture.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const spec = fields.next().?;
        const precision = try std.fmt.parseInt(u32, fields.next().?, 10);
        const expected = fields.next().?;
        const value = try f64FromSpec(spec);

        const needed = try ryu.scientificCapacity(precision);
        const buffer = try std.testing.allocator.alloc(u8, needed);
        defer std.testing.allocator.free(buffer);

        const got = try ryu.format64Scientific(value, precision, buffer);
        if (!std.mem.eql(u8, expected, got)) {
            std.debug.print("d2exp {s} p={d}: expected {s}, got {s}\n", .{ spec, precision, expected, got });
            return error.NotThePublishedAnswer;
        }
        seen += 1;
    }
    try std.testing.expectEqual(@as(usize, 134), seen);
}

// --- 2. An independent parser reads the published answers back -----------------

test "every published binary64 shortest answer names the fixture's own value" {
    var fixture = Fixture.init("testdata/d2s_shortest.txt");
    while (fixture.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const spec = fields.next().?;
        const expected = fields.next().?;
        // `nan`, `inf` and `neginf` have no single bit pattern and their
        // published spellings are Ryu's own, not a decimal literal, so there
        // is nothing for an independent parser to check there.
        if (std.mem.eql(u8, spec, "nan") or std.mem.eql(u8, spec, "inf") or
            std.mem.eql(u8, spec, "neginf")) continue;

        const back = try std.fmt.parseFloat(f64, expected);
        const want = try f64FromSpec(spec);
        try std.testing.expectEqual(@as(u64, @bitCast(want)), @as(u64, @bitCast(back)));
    }
}

test "every published binary32 shortest answer names the fixture's own value" {
    var fixture = Fixture.init("testdata/f2s_shortest.txt");
    while (fixture.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const spec = fields.next().?;
        const expected = fields.next().?;
        if (std.mem.eql(u8, spec, "nan") or std.mem.eql(u8, spec, "inf") or
            std.mem.eql(u8, spec, "neginf")) continue;

        const back = try std.fmt.parseFloat(f32, expected);
        const want = try f32FromSpec(spec);
        try std.testing.expectEqual(@as(u32, @bitCast(want)), @as(u32, @bitCast(back)));
    }
}

// --- 3. An independent formatter agrees on the digits -------------------------

test "binary64 shortest agrees with Zig's own shortest formatter" {
    // Zig's `{e}` is Errol/Grisu, Ryu is Ryu. Neither derives from the other,
    // so agreement over this set is evidence about the digits and the
    // exponent, not about a shared implementation.
    const cases = [_]f64{
        0.0,                     -0.0,
        1.0,                     -1.0,
        1.25,                    0.1,
        2.0,                     8.0,
        64.0,                    8388608.0,
        1.0e15,                  1.0e300,
        1.0e-300,                9007199254740992.0,
        5.0e-324,                1.7976931348623157e308,
        2.2250738585072014e-308,
    };
    var buffer: [ryu.double_shortest_capacity]u8 = undefined;
    for (cases) |value| {
        const ours = try ryu.format64Shortest(value, &buffer);
        var zig: [64]u8 = undefined;
        const theirs = try std.fmt.bufPrint(&zig, "{e}", .{value});
        if (!shortestSpellingMatches(theirs, ours)) {
            std.debug.print("shortest {d}: Zig says {s}, ryu says {s}\n", .{ value, theirs, ours });
            return error.FormattersDisagree;
        }
    }
}

test "binary32 shortest agrees with Zig's own shortest formatter" {
    const cases = [_]f32{
        0.0,           -0.0,
        1.0,           -1.0,
        1.25,          0.1,
        2.0,           8.0,
        200.0,         8388608.0,
        1.0e-45,       3.4028235e38,
        1.1754944e-38,
    };
    var buffer: [ryu.float_shortest_capacity]u8 = undefined;
    for (cases) |value| {
        const ours = try ryu.format32Shortest(value, &buffer);
        var zig: [64]u8 = undefined;
        const theirs = try std.fmt.bufPrint(&zig, "{e}", .{value});
        if (!shortestSpellingMatches(theirs, ours)) {
            std.debug.print("shortest {d}: Zig says {s}, ryu says {s}\n", .{ value, theirs, ours });
            return error.FormattersDisagree;
        }
    }
}

test "fixed point agrees with Zig's own formatter away from a tie" {
    // Ties are excluded on purpose, and not because they are hard to predict:
    // Ryu rounds a tie to even and Zig's own source says its Errol path rounds
    // a tie toward zero, which the two published fixtures already pin from the
    // other side (0.375 at precision 2 is Ryu's "0.38"). Agreement is claimed
    // only where the remainder is not exactly one half, which is where the
    // two are required to agree.
    const cases = [_]struct { value: f64, precision: u32 }{
        .{ .value = 0.0, .precision = 4 },
        .{ .value = 1.0, .precision = 3 },
        .{ .value = 1.25, .precision = 2 },
        .{ .value = 1.25, .precision = 3 },
        .{ .value = -0.748046875, .precision = 2 },
        .{ .value = 0.004, .precision = 2 },
        .{ .value = 0.004, .precision = 3 },
        .{ .value = 9.9999, .precision = 3 },
        .{ .value = 299.9999, .precision = 3 },
        .{ .value = 1729.142857142857, .precision = 4 },
        .{ .value = 1.2345678901234567, .precision = 5 },
        .{ .value = 7.018232e-82, .precision = 6 },
    };
    for (cases) |case| {
        const needed = try ryu.fixedCapacity(case.precision);
        const buffer = try std.testing.allocator.alloc(u8, needed);
        defer std.testing.allocator.free(buffer);
        const ours = try ryu.format64Fixed(case.value, case.precision, buffer);

        var zig: [512]u8 = undefined;
        const theirs = try std.fmt.bufPrint(&zig, "{d:.[1]}", .{ case.value, @as(usize, case.precision) });
        if (!std.mem.eql(u8, theirs, ours)) {
            std.debug.print("fixed {d} p={d}: Zig says {s}, ryu says {s}\n", .{
                case.value, case.precision, theirs, ours,
            });
            return error.FormattersDisagree;
        }
    }
}

test "scientific agrees with Zig's own formatter away from a tie" {
    const cases = [_]struct { value: f64, precision: u32 }{
        .{ .value = 1.25, .precision = 2 },
        .{ .value = 1.25, .precision = 5 },
        .{ .value = 9.9999, .precision = 4 },
        .{ .value = 9.9999, .precision = 3 },
        .{ .value = 1729.142857142857, .precision = 5 },
        .{ .value = 1.0e-300, .precision = 6 },
        .{ .value = 1.7976931348623157e308, .precision = 3 },
    };
    for (cases) |case| {
        const needed = try ryu.scientificCapacity(case.precision);
        const buffer = try std.testing.allocator.alloc(u8, needed);
        defer std.testing.allocator.free(buffer);
        const ours = try ryu.format64Scientific(case.value, case.precision, buffer);

        var zig: [512]u8 = undefined;
        const theirs = try std.fmt.bufPrint(&zig, "{e:.[1]}", .{ case.value, @as(usize, case.precision) });

        const ours_parts = try scientificParts(ours);
        const theirs_parts = try scientificParts(theirs);
        if (!std.mem.eql(u8, theirs_parts.mantissa, ours_parts.mantissa) or
            theirs_parts.exponent != ours_parts.exponent)
        {
            std.debug.print("scientific {d} p={d}: Zig says {s}, ryu says {s}\n", .{
                case.value, case.precision, theirs, ours,
            });
            return error.FormattersDisagree;
        }
    }
}

// --- The tie behaviour the published fixtures pin, stated directly ------------

test "a tie rounds to even in both fixed and scientific" {
    // These four come from upstream's own RoundToEvenInteger cases. They are
    // repeated here because they are the one place where Ryu and Zig's own
    // formatter deliberately differ, so a reader of this file can see the
    // disagreement is a known difference and not an accident.
    const cases = [_]struct { value: f64, precision: u32, fixed: []const u8, scientific: []const u8 }{
        .{ .value = 2.5, .precision = 0, .fixed = "2", .scientific = "2e+00" },
        .{ .value = 3.5, .precision = 0, .fixed = "4", .scientific = "4e+00" },
        .{ .value = 2.5, .precision = 1, .fixed = "2.5", .scientific = "2.5e+00" },
        .{ .value = 3.5, .precision = 1, .fixed = "3.5", .scientific = "3.5e+00" },
    };
    for (cases) |case| {
        try expectBothPrecisionStyles(case.value, case.precision, case.fixed, case.scientific);
    }
}

test "a run of nines carries out of the fraction" {
    // `precision` counts the digits after the point in the fixed form and the
    // digits after the leading digit in the scientific one, so a carry out of
    // the fraction needs one more nine than either count can hold. `9.9999`
    // and `299.9999` carry in the integer part as well as the fraction, and
    // `0.99999` is the smallest decimal below one that carries in the
    // scientific style at precision 3 - `0.9999` does not, which is the test
    // below.
    //
    // The expected strings are derived from the exact decimal expansion of
    // each double, not from what the writer produced. `0.99999` is
    // 0.99999000000000004551... as a binary64, so the fourth digit past the
    // point is a 9 that the digits after it cannot un-carry: at precision 3 it
    // rounds up in both styles.
    const cases = [_]struct { value: f64, precision: u32, fixed: []const u8, scientific: []const u8 }{
        .{ .value = 9.9999, .precision = 3, .fixed = "10.000", .scientific = "1.000e+01" },
        .{ .value = 299.9999, .precision = 3, .fixed = "300.000", .scientific = "3.000e+02" },
        .{ .value = 0.99999, .precision = 3, .fixed = "1.000", .scientific = "1.000e+00" },
    };
    for (cases) |case| {
        try expectBothPrecisionStyles(case.value, case.precision, case.fixed, case.scientific);
    }
}

test "a run of nines one digit short of the precision does not carry" {
    // The other side of the same boundary, and the case a reader is most likely
    // to get wrong in the opposite direction. `0.9999` is exactly four
    // significant digits as a binary64 - the nearest double is
    // 0.99990000000000001101... - so a scientific precision of 3, which asks
    // for four significant digits, has nothing to round and the answer keeps
    // every nine. The fixed writer at that precision asks for three digits
    // after the point instead and does carry, which is why the two expected
    // strings differ in shape at the same precision. A precision of 4 asks for
    // five significant digits and pads with a zero. All three answers are the
    // correctly rounded decimal expansion, computed from the value rather than
    // read back from the writer.
    const cases = [_]struct { value: f64, precision: u32, fixed: []const u8, scientific: []const u8 }{
        .{ .value = 0.9999, .precision = 4, .fixed = "0.9999", .scientific = "9.9990e-01" },
        .{ .value = 0.9999, .precision = 3, .fixed = "1.000", .scientific = "9.999e-01" },
    };
    for (cases) |case| {
        try expectBothPrecisionStyles(case.value, case.precision, case.fixed, case.scientific);
    }
}

// --- What the writers do to the caller's buffer -------------------------------

test "the shortest writer stops at the answer and leaves the rest alone" {
    var buffer: [ryu.double_shortest_capacity]u8 = @splat(untouched);
    const got = try ryu.format64Shortest(1.7976931348623157e308, &buffer);
    try std.testing.expectEqualStrings("1.7976931348623157E308", got);
    try expectUntouched(buffer[got.len..]);
}

test "the fixed and scientific writers stop at the answer" {
    const fixed_needed = try ryu.fixedCapacity(17);
    const fixed_buffer = try std.testing.allocator.alloc(u8, fixed_needed);
    defer std.testing.allocator.free(fixed_buffer);
    @memset(fixed_buffer, untouched);
    const fixed_got = try ryu.format64Fixed(1.25, 17, fixed_buffer);
    try std.testing.expectEqualStrings("1.25000000000000000", fixed_got);
    try expectUntouched(fixed_buffer[fixed_got.len..]);

    const scientific_needed = try ryu.scientificCapacity(17);
    const scientific_buffer = try std.testing.allocator.alloc(u8, scientific_needed);
    defer std.testing.allocator.free(scientific_buffer);
    @memset(scientific_buffer, untouched);
    const scientific_got = try ryu.format64Scientific(1.25, 17, scientific_buffer);
    try std.testing.expectEqualStrings("1.25000000000000000e+00", scientific_got);
    try expectUntouched(scientific_buffer[scientific_got.len..]);
}

test "a short buffer is enough when it holds the exact answer" {
    // The boundary being proved is that a buffer exactly as long as this
    // particular answer is accepted, so each buffer is sized to the answer it
    // is given and no byte more. A sign, a point and an exponent marker are
    // all bytes the answer spends, which is why `-1E0` and `1.5E1` need more
    // room than the three byte answers around them.
    var three: [3]u8 = undefined;
    try std.testing.expectEqualStrings("1E0", try ryu.format64Shortest(1.0, &three));
    try std.testing.expectEqualStrings("0E0", try ryu.format64Shortest(0.0, &three));

    var four: [4]u8 = undefined;
    try std.testing.expectEqualStrings("-1E0", try ryu.format64Shortest(-1.0, &four));
    try std.testing.expectEqualStrings("2E2", try ryu.format32Shortest(200.0, &four));

    var five: [5]u8 = undefined;
    try std.testing.expectEqualStrings("1.5E1", try ryu.format64Shortest(15.0, &five));
}

test "a short buffer one byte too short is refused and left untouched" {
    var two: [2]u8 = @splat(untouched);
    try std.testing.expectError(error.BufferTooSmall, ryu.format64Shortest(1.0, &two));
    try expectUntouched(&two);

    var one: [1]u8 = @splat(untouched);
    try std.testing.expectError(error.BufferTooSmall, ryu.format32Shortest(1.0, &one));
    try expectUntouched(&one);
}

test "an empty buffer is refused by all four writers" {
    var empty_buffer: [0]u8 = undefined;
    const empty: []u8 = &empty_buffer;
    try std.testing.expectError(error.BufferTooSmall, ryu.format32Shortest(1.0, empty));
    try std.testing.expectError(error.BufferTooSmall, ryu.format64Shortest(1.0, empty));
    try std.testing.expectError(error.BufferTooSmall, ryu.format64Fixed(1.0, 0, empty));
    try std.testing.expectError(error.BufferTooSmall, ryu.format64Scientific(1.0, 0, empty));
}

test "the precision writers refuse one byte short of their published bound" {
    const fixed_needed = try ryu.fixedCapacity(3);
    const fixed_buffer = try std.testing.allocator.alloc(u8, fixed_needed - 1);
    defer std.testing.allocator.free(fixed_buffer);
    @memset(fixed_buffer, untouched);
    try std.testing.expectError(error.BufferTooSmall, ryu.format64Fixed(1.25, 3, fixed_buffer));
    try expectUntouched(fixed_buffer);

    const scientific_needed = try ryu.scientificCapacity(3);
    const scientific_buffer = try std.testing.allocator.alloc(u8, scientific_needed - 1);
    defer std.testing.allocator.free(scientific_buffer);
    @memset(scientific_buffer, untouched);
    try std.testing.expectError(error.BufferTooSmall, ryu.format64Scientific(1.25, 3, scientific_buffer));
    try expectUntouched(scientific_buffer);
}

// --- The capacity bound --------------------------------------------------------

test "the nine byte special value is the whole bound at the two precisions it sizes" {
    // `-Infinity` is nine bytes - a sign and eight - and upstream writes it in
    // the fixed and the scientific family alike
    // (`ryu/d2fixed.c:349-355`, reached from `ryu/d2fixed.c:375-376` and from
    // `ryu/d2fixed.c:583-584`). At precision 0 and at precision 1 that string
    // is the longest answer either writer can produce: a number at precision 1
    // spends a sign, a digit, a point, one fraction digit, `e`, an exponent
    // sign and three exponent digits, which is eight. So the bound at those
    // two precisions is exactly the special value, and this measures that
    // against the answer itself rather than against the arithmetic that
    // produces the bound.
    for ([_]u32{ 0, 1 }) |precision| {
        try std.testing.expectEqual(@as(usize, 9), try ryu.scientificCapacity(precision));

        // The nine byte buffer is the bound exactly, so this is also an
        // exact-fit case: an answer that fills the whole bound, accepted.
        var nine: [9]u8 = @splat(untouched);
        try std.testing.expectEqualStrings(
            "-Infinity",
            try ryu.format64Scientific(-std.math.inf(f64), precision, &nine),
        );

        const fixed_buffer = try std.testing.allocator.alloc(u8, try ryu.fixedCapacity(precision));
        defer std.testing.allocator.free(fixed_buffer);
        @memset(fixed_buffer, untouched);
        const fixed_got = try ryu.format64Fixed(-std.math.inf(f64), precision, fixed_buffer);
        try std.testing.expectEqualStrings("-Infinity", fixed_got);
        try expectUntouched(fixed_buffer[fixed_got.len..]);

        // One byte short of the answer is refused, and nothing is written.
        var eight: [8]u8 = @splat(untouched);
        try std.testing.expectError(
            error.BufferTooSmall,
            ryu.format64Scientific(-std.math.inf(f64), precision, &eight),
        );
        try expectUntouched(&eight);
    }
}

test "the widest published integer part fits the bound it is measured against" {
    // 1.7976931348623157e308 at precision 0 is 309 digits: the largest finite
    // binary64 has a 309 digit floor, which is what
    // `max_fixed_integer_digits` says.
    const needed = try ryu.fixedCapacity(0);
    const buffer = try std.testing.allocator.alloc(u8, needed);
    defer std.testing.allocator.free(buffer);
    const got = try ryu.format64Fixed(1.7976931348623157e308, 0, buffer);
    try std.testing.expectEqualStrings(
        "179769313486231570814527423731704356798070567525844996598917476803157260780028538760589558632766878171540458953514382464234321326889464182768467546703537516986049910576551282076245490090389328944075868508455133942304583236903222948165808559332123348274797826204144723168738177180919299881250404026184124858368",
        got,
    );
    try std.testing.expectEqual(ryu.max_fixed_integer_digits, got.len);
}

test "a precision no capacity can measure is refused rather than wrapped" {
    // An answer at any precision contains at least the precision digits
    // themselves plus one integer digit, so no honest capacity is smaller than
    // that. A bound that came back below it would be a wrapped number instead
    // of a capacity, and the caller would then hand the writer a buffer far
    // too small for the answer that is about to be written into it - a silent
    // overrun rather than an error.
    const huge = std.math.maxInt(u32);
    const minimum: u64 = @as(u64, huge) + 1;
    const widest: u64 = @as(u64, std.math.maxInt(usize));

    if (minimum > widest) {
        // A target whose `usize` cannot even hold the digits must say so.
        try std.testing.expectError(error.PrecisionTooLarge, ryu.fixedCapacity(huge));
        try std.testing.expectError(error.PrecisionTooLarge, ryu.scientificCapacity(huge));
    } else {
        // Otherwise the whole bound comes back, and it is at least the number
        // of digits the answer has to contain.
        const least: usize = @intCast(minimum);
        try std.testing.expect(try ryu.fixedCapacity(huge) >= least);
        try std.testing.expect(try ryu.scientificCapacity(huge) >= least);
    }
}

test "a precision far past any real answer is printed whole, not cut off" {
    // The widest answers in the published fixtures are 1076 bytes of fixed
    // point and 757 of scientific, both from the smallest subnormal at
    // precision 1074 and 750 - a value with no integer part at all. A value
    // that has one is wider: at precision 1074 the largest finite binary64
    // reaches 309 integer digits, a point and 1074 fraction digits, because
    // upstream writes `precision` fraction digits whatever the value is
    // (`ryu/d2fixed.c:445-448` and `ryu/d2fixed.c:545-548`). A precision far
    // past any of that is still honoured in full, and the answer it produces
    // is exactly as long as the value and the precision say it is: 309 integer
    // digits, a point and 100_000 zeros for the fixed form; one leading digit,
    // a point, 100_000 digits, `e`, `+` and `308` for the scientific one. Both
    // are measured against buffers of exactly the published bound, so this
    // fails if that bound is one byte short of a real answer.
    const precision: u32 = 100_000;
    const value = 1.7976931348623157e308;

    const fixed_needed = try ryu.fixedCapacity(precision);
    const fixed_buffer = try std.testing.allocator.alloc(u8, fixed_needed);
    defer std.testing.allocator.free(fixed_buffer);
    const fixed_got = try ryu.format64Fixed(value, precision, fixed_buffer);
    try std.testing.expectEqual(ryu.max_fixed_integer_digits + 1 + @as(usize, precision), fixed_got.len);
    try std.testing.expectEqual(@as(u8, '.'), fixed_got[ryu.max_fixed_integer_digits]);
    for (fixed_got[ryu.max_fixed_integer_digits + 1 ..]) |byte| {
        if (byte != '0') return error.FractionIsNotZeroPadded;
    }

    const scientific_needed = try ryu.scientificCapacity(precision);
    const scientific_buffer = try std.testing.allocator.alloc(u8, scientific_needed);
    defer std.testing.allocator.free(scientific_buffer);
    const scientific_got = try ryu.format64Scientific(value, precision, scientific_buffer);
    try std.testing.expectEqualStrings("e+308", scientific_got[scientific_got.len - 5 ..]);
    try std.testing.expectEqual(@as(usize, precision) + 7, scientific_got.len);
    try std.testing.expectEqual(@as(u8, '1'), scientific_got[0]);
    try std.testing.expectEqual(@as(u8, '.'), scientific_got[1]);
}

test "negative zero keeps its sign in both precision writers" {
    // The published fixtures carry `zero` and not `negzero` for these two
    // writers, so this is the one signed zero they do not cover. Upstream
    // writes the sign before the digit on the zero path of both
    // (`ryu/d2fixed.c:379-386` and `ryu/d2fixed.c:589-595`), and the
    // scientific writer appends `e+00` to a zero at every precision, so the
    // answer is nine bytes at precision 3 and five at precision 0.
    const cases = [_]struct { precision: u32, fixed: []const u8, scientific: []const u8 }{
        .{ .precision = 3, .fixed = "-0.000", .scientific = "-0.000e+00" },
        .{ .precision = 0, .fixed = "-0", .scientific = "-0e+00" },
    };
    for (cases) |case| {
        try expectBothPrecisionStyles(-0.0, case.precision, case.fixed, case.scientific);
    }
}

// --- The experimental parser ---------------------------------------------------

test "the experimental binary64 parser reproduces every accepted input upstream names" {
    var fixture = Fixture.init("testdata/s2d_parse.txt");
    var seen: usize = 0;
    while (fixture.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const status = fields.next().?;
        const text = fields.next().?;
        const spec = fields.next().?;
        seen += 1;

        if (std.mem.eql(u8, status, "ok")) {
            const got = ryu.experimental.parse64(text);
            const want = try f64FromSpec(spec);
            const value = got catch |err| {
                std.debug.print("s2d {s}: unexpected {s}\n", .{ text, @errorName(err) });
                return error.NotThePublishedAnswer;
            };
            try std.testing.expectEqual(@as(u64, @bitCast(want)), @as(u64, @bitCast(value)));
        } else {
            try std.testing.expectError(expectedParseError(status), ryu.experimental.parse64(text));
        }
    }
    try std.testing.expectEqual(@as(usize, 39), seen);
}

test "the experimental binary32 parser reproduces every accepted input upstream names" {
    var fixture = Fixture.init("testdata/s2f_parse.txt");
    var seen: usize = 0;
    while (fixture.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const status = fields.next().?;
        const text = fields.next().?;
        const spec = fields.next().?;
        seen += 1;

        if (std.mem.eql(u8, status, "ok")) {
            const value = ryu.experimental.parse32(text) catch |err| {
                std.debug.print("s2f {s}: unexpected {s}\n", .{ text, @errorName(err) });
                return error.NotThePublishedAnswer;
            };
            const want = try f32FromSpec(spec);
            try std.testing.expectEqual(@as(u32, @bitCast(want)), @as(u32, @bitCast(value)));
        } else {
            try std.testing.expectError(expectedParseError(status), ryu.experimental.parse32(text));
        }
    }
    try std.testing.expectEqual(@as(usize, 28), seen);
}

test "the experimental parser is a real parse, not the formatter's own output" {
    // Upstream's parser has a documented limit the formatter's shortest output
    // never reaches: at most 17 nonzero mantissa digits. Its own suite pins
    // 18 digits as INPUT_TOO_LONG while the shortest writer happily prints a
    // 17 digit answer for the same value, so the two are genuinely different
    // code paths and this exercises the rejection.
    try std.testing.expectError(
        error.InputTooLong,
        ryu.experimental.parse64("123456789012345678"),
    );
    try std.testing.expectError(
        error.MalformedInput,
        ryu.experimental.parse64("1.25E0 x"),
    );
    // And the shortest answer for 1.25 is the parser's own accepted spelling.
    try std.testing.expectEqual(
        @as(u64, 0x3FF4000000000000),
        @as(u64, @bitCast(try ryu.experimental.parse64("1.25E0"))),
    );
}

test "the two experimental parsers refuse at their own mantissa widths" {
    // Upstream's two parsers do not accept the same grammar, and the difference
    // is one the two documented limits name: `s2d_n` refuses at 17 nonzero
    // mantissa digits (`ryu/s2d.c:100-102`) and `s2f_n` at 9
    // (`ryu/s2f.c:94-96`). A ten digit decimal is therefore an ordinary parse
    // for one and a rejection for the other, and a caller that generalises
    // from `parse64` to `parse32` gets an error it did not expect.
    const nine = "123456789";
    const ten = "1234567890";

    // Nine digits is the last the binary32 parser takes, and the same text
    // parses as both widths.
    try std.testing.expectEqual(@as(f32, 123456792.0), try ryu.experimental.parse32(nine));
    try std.testing.expectEqual(@as(f64, 123456789.0), try ryu.experimental.parse64(nine));

    // The tenth digit is inside `parse64`'s 17 and outside `parse32`'s 9.
    try std.testing.expectEqual(@as(f64, 1234567890.0), try ryu.experimental.parse64(ten));
    try std.testing.expectError(error.InputTooLong, ryu.experimental.parse32(ten));
}
