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
//! fact that a refusal it makes before calling C leaves the caller's buffer
//! byte for byte as it was.
//!
//! Two more kinds of evidence sit alongside those, each only where it can be
//! real. The owned-string tests use upstream's own four allocating entry points
//! and release what they get with the C library's `free`, which is the
//! allocator that produced it; they check the answers and the release path and
//! do not pretend to a leak check, because the test framework's allocator is
//! not the one whose leak this would be. The generic 128-bit tests exist only
//! in a build configured with `-Dgeneric128` and say so when they are skipped.
//!
//! ## The provider in a runtime-loading build
//!
//! `RYU_TEST_PROVIDER` names a shared object exporting the sixteen entry points
//! `ryu/ryu.h` and `ryu/ryu_parse.h` declare, plus the five of
//! `ryu/ryu_generic_128.h` when this build configured `-Dgeneric128`. Every test
//! calls `nativeReady` before it touches the facade, which is a no-op at comptime
//! in a linked build and the one explicit `load` in a runtime-loading one.
//! Nothing is skipped when the variable is unset: a suite that quietly stopped
//! testing because a variable was missing would report success for nothing.
//!
//! No test here pins a version string, an export, a default, or a call that
//! merely does not fail. Every one either reproduces a published answer,
//! cross-checks against a different implementation, or proves a boundary.

const std = @import("std");
const ryu = @import("ryu");

/// A shared object exporting Ryu's entry points, named by the environment in a
/// runtime-loading build.
const provider_variable = "RYU_TEST_PROVIDER";

/// Make the native library usable, once, before a test calls the facade.
///
/// In a linked build the facade is usable already and this is a no-op at
/// comptime. In a runtime-loading build every call into the module goes through
/// a table that `load` fills, so this is where the one explicit load happens.
/// It is safe to call from every test: the contract makes the same request
/// idempotent, and the loader keeps the handle to the end of the process.
///
/// A build that was not told which file to load stops here with the variable's
/// name, rather than reporting a test failure that says nothing about the
/// reason.
fn nativeReady() void {
    if (comptime !ryu.runtime_loaded) return;
    if (ryu.loadedSource() != null) return;

    var buffer: [4096]u8 = undefined;
    const value = std.testing.environ.getAlloc(std.testing.allocator, provider_variable) catch
        missingProvider();
    defer std.testing.allocator.free(value);
    if (value.len == 0 or value.len > buffer.len) missingProvider();
    @memcpy(buffer[0..value.len], value);
    ryu.load(.{ .path = buffer[0..value.len] }) catch |err| {
        std.debug.print(
            "tests.zig: loading " ++ provider_variable ++ " = \"{s}\" failed: {t}\n",
            .{ buffer[0..value.len], err },
        );
        @panic("tests.zig: the provider named by " ++ provider_variable ++
            " did not load; nothing below this line ran");
    };
}

fn missingProvider() noreturn {
    @panic(
        "tests.zig: this is a runtime-loading build and " ++ provider_variable ++
            " is not set. Point it at a shared object exporting the entry " ++
            "points of ryu/ryu.h and ryu/ryu_parse.h, for example the one " ++
            "`zig build -Dlinkage=dynamic` installs, and export it for the whole " ++
            "`zig build` invocation: the build cannot inject a path into a run " ++
            "step's environment.",
    );
}

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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
    var buffer: [ryu.double_shortest_capacity]u8 = @splat(untouched);
    const got = try ryu.format64Shortest(1.7976931348623157e308, &buffer);
    try std.testing.expectEqualStrings("1.7976931348623157E308", got);
    try expectUntouched(buffer[got.len..]);
}

test "the fixed and scientific writers stop at the answer" {
    nativeReady();
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
    nativeReady();
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
    nativeReady();
    var two: [2]u8 = @splat(untouched);
    try std.testing.expectError(error.BufferTooSmall, ryu.format64Shortest(1.0, &two));
    try expectUntouched(&two);

    var one: [1]u8 = @splat(untouched);
    try std.testing.expectError(error.BufferTooSmall, ryu.format32Shortest(1.0, &one));
    try expectUntouched(&one);
}

test "an empty buffer is refused by all four writers" {
    nativeReady();
    var empty_buffer: [0]u8 = undefined;
    const empty: []u8 = &empty_buffer;
    try std.testing.expectError(error.BufferTooSmall, ryu.format32Shortest(1.0, empty));
    try std.testing.expectError(error.BufferTooSmall, ryu.format64Shortest(1.0, empty));
    try std.testing.expectError(error.BufferTooSmall, ryu.format64Fixed(1.0, 0, empty));
    try std.testing.expectError(error.BufferTooSmall, ryu.format64Scientific(1.0, 0, empty));
}

test "the precision writers refuse one byte short of their published bound" {
    nativeReady();
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

test "special scientific outputs fit the minimum-precision buffer" {
    nativeReady();
    // `_MSC_VER` permits "-nan(snan)" (ten bytes); other builds emit "nan".
    // These are source-defined alternatives, not a claim about this host's
    // compiler selecting the MSVC branch (`ryu/d2fixed.c:331-355`).
    const precision = 0;
    const bound = try ryu.scientificCapacity(precision);
    const buffer = try std.testing.allocator.alloc(u8, bound);
    defer std.testing.allocator.free(buffer);
    try std.testing.expectEqualStrings(
        "-Infinity",
        try ryu.format64Scientific(-std.math.inf(f64), precision, buffer),
    );
    const signalling: f64 = @bitCast(@as(u64, 0xfff0000000000001));
    const text = try ryu.format64Scientific(signalling, precision, buffer);
    try std.testing.expect(std.mem.eql(u8, text, "nan") or
        std.mem.eql(u8, text, "-nan(snan)"));

    const short = try std.testing.allocator.alloc(u8, bound - 1);
    defer std.testing.allocator.free(short);
    @memset(short, untouched);
    try std.testing.expectError(
        error.BufferTooSmall,
        ryu.format64Scientific(-std.math.inf(f64), precision, short),
    );
    try expectUntouched(short);
}

test "the widest published integer part fits the bound it is measured against" {
    nativeReady();
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

test "the precision the scientific writer cannot represent is refused, not formatted" {
    nativeReady();
    // `d2exp_buffered_n` raises its own `uint32_t` precision by one before it
    // formats anything (`ryu/d2fixed.c:616`), so `maxInt(u32)` wraps to zero
    // there and the writer hands back a short, wrong answer instead of a long
    // one: `1.0` at `maxInt(u32)` comes back as `0e+00`. The write stays
    // inside the buffer the caller sized, so nothing downstream notices. The
    // capacity query and the writer both refuse that precision, and the refusal
    // happens before `out` is even measured, which is why a buffer far too
    // small for the answer still gets `error.PrecisionTooLarge` rather than
    // `error.BufferTooSmall` and is left exactly as it was.
    const huge = std.math.maxInt(u32);
    try std.testing.expectError(error.PrecisionTooLarge, ryu.scientificCapacity(huge));

    var buffer: [16]u8 = @splat(untouched);
    try std.testing.expectError(
        error.PrecisionTooLarge,
        ryu.format64Scientific(1.0, huge, &buffer),
    );
    try expectUntouched(&buffer);

    // The same for a value whose answer is one of the special strings, which
    // takes a different path inside the writer and does not touch `precision`
    // at all - so the refusal cannot be a by-product of the digit loop.
    try std.testing.expectError(
        error.PrecisionTooLarge,
        ryu.format64Scientific(-std.math.inf(f64), huge, &buffer),
    );
    try expectUntouched(&buffer);
}

test "each precision writer's last accepted precision is its last representable answer" {
    nativeReady();
    // Both writers accumulate into an `int` index and return it
    // (`ryu/d2fixed.c:405` and `ryu/d2fixed.c:617`, declared `int` at
    // `ryu/ryu.h:34` and `ryu/ryu.h:38`), so an answer longer than that return
    // cannot be reported: the index wraps and the caller is handed a length
    // that has nothing to do with what was written. The largest precision that
    // still fits is therefore the width of that return minus whatever the
    // style spends around `precision`, and the two styles have different
    // overheads, so their limits differ. This measures the boundary through
    // the capacity queries, which cost nothing; actually formatting at it
    // would need a two gigabyte buffer, which is not what this suite does.
    const written_max: usize = @intCast(std.math.maxInt(c_int));

    // Each style's overhead, read back out of a precision large enough that
    // the special-value floor does not apply, and checked against the shape
    // the writers have.
    const fixed_overhead = try ryu.fixedCapacity(16) - 16;
    const scientific_overhead = try ryu.scientificCapacity(16) - 16;
    try std.testing.expectEqual(1 + ryu.max_fixed_integer_digits + 1, fixed_overhead);
    try std.testing.expectEqual(@as(usize, 8), scientific_overhead);

    const fixed_last: u32 = @intCast(written_max - fixed_overhead);
    const scientific_last: u32 = @intCast(written_max - scientific_overhead);
    try std.testing.expectEqual(written_max, try ryu.fixedCapacity(fixed_last));
    try std.testing.expectEqual(written_max, try ryu.scientificCapacity(scientific_last));

    // One past each limit is refused, and so is the far end of the `u32`, on
    // every target rather than only where `usize` is too narrow to hold the
    // digits. The writers refuse them the same way, before writing.
    for ([_]u32{ fixed_last + 1, std.math.maxInt(u32) }) |precision| {
        try std.testing.expectError(error.PrecisionTooLarge, ryu.fixedCapacity(precision));
        var buffer: [8]u8 = @splat(untouched);
        try std.testing.expectError(
            error.PrecisionTooLarge,
            ryu.format64Fixed(1.25, precision, &buffer),
        );
        try expectUntouched(&buffer);
    }
    for ([_]u32{ scientific_last + 1, std.math.maxInt(u32) }) |precision| {
        try std.testing.expectError(error.PrecisionTooLarge, ryu.scientificCapacity(precision));
        var buffer: [8]u8 = @splat(untouched);
        try std.testing.expectError(
            error.PrecisionTooLarge,
            ryu.format64Scientific(1.25, precision, &buffer),
        );
        try expectUntouched(&buffer);
    }
}

test "a precision far past any real answer is printed whole, not cut off" {
    nativeReady();
    // The widest answers in the published fixtures are 1076 bytes of fixed
    // point and 757 of scientific, both from the smallest subnormal at
    // precision 1074 and 750 - a value with no integer part at all. A value
    // that has one is wider: at precision 1074 the largest finite binary64
    // reaches 309 integer digits, a point and 1074 fraction digits, because
    // upstream writes `precision` fraction digits whatever the value is
    // (`ryu/d2fixed.c:454-455` and `ryu/d2fixed.c:545-548`). A precision far
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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
    nativeReady();
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

// --- 3. Upstream's allocating entry points, and the allocator boundary -------
//
// These four entry points are real published API with no buffered equivalent,
// so they are exercised against the same published fixtures rather than against
// this module's own buffered answers: a wrong `d2s` would then have to be wrong
// twice, in both the writer under test and the one it is compared to.

test "the allocating shortest writers reproduce every published answer" {
    nativeReady();
    var binary64 = Fixture.init("testdata/d2s_shortest.txt");
    var binary32 = Fixture.init("testdata/f2s_shortest.txt");
    var seen: usize = 0;
    while (binary64.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const value = try f64FromSpec(fields.next().?);
        const expected = fields.next().?;
        const owned = try ryu.format64ShortestOwned(value);
        defer owned.deinit();
        try std.testing.expectEqualStrings(expected, owned.slice());
        // The length this module reports is the position of upstream's own
        // terminator, not a length this module guessed: `d2s` NUL-terminates
        // the 25 bytes it allocated (`ryu/d2s.c:498-508`) and the byte the
        // returned length points at has to be that terminator.
        try std.testing.expectEqual(@as(u8, 0), owned.bytes[owned.len]);
        seen += 1;
    }
    while (binary32.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const value = try f32FromSpec(fields.next().?);
        const expected = fields.next().?;
        const owned = try ryu.format32ShortestOwned(value);
        defer owned.deinit();
        try std.testing.expectEqualStrings(expected, owned.slice());
        try std.testing.expectEqual(@as(u8, 0), owned.bytes[owned.len]);
        seen += 1;
    }
    try std.testing.expectEqual(@as(usize, 132 + 60), seen);
}

test "the allocating precision writers reproduce every published answer" {
    nativeReady();
    // The widest answer in either fixture is 1076 bytes at precision 1074 and
    // 757 at precision 750 (`testdata/d2fixed.txt`, `testdata/d2exp.txt`), and
    // upstream's own buffer for both writers is 2000 bytes
    // (`ryu/d2fixed.c:558`, `ryu/d2fixed.c:815`). Every published row
    // therefore fits, which is what lets one fixture walk stand for all 268 of
    // them.
    var fixed = Fixture.init("testdata/d2fixed.txt");
    var scientific = Fixture.init("testdata/d2exp.txt");
    var seen: usize = 0;
    while (fixed.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const value = try f64FromSpec(fields.next().?);
        const precision = try std.fmt.parseInt(u32, fields.next().?, 10);
        const expected = fields.next().?;
        const owned = try ryu.format64FixedOwned(value, precision);
        defer owned.deinit();
        try std.testing.expectEqualStrings(expected, owned.slice());
        seen += 1;
    }
    while (scientific.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const value = try f64FromSpec(fields.next().?);
        const precision = try std.fmt.parseInt(u32, fields.next().?, 10);
        const expected = fields.next().?;
        const owned = try ryu.format64ScientificOwned(value, precision);
        defer owned.deinit();
        try std.testing.expectEqualStrings(expected, owned.slice());
        seen += 1;
    }
    try std.testing.expectEqual(@as(usize, 134 + 134), seen);
}

test "the owned precision writers refuse a precision upstream's own buffer cannot hold" {
    nativeReady();
    // `d2fixed` and `d2exp` each `malloc(2000)` and check nothing against it
    // (`ryu/d2fixed.c:557-562`, `ryu/d2fixed.c:814-819`), so a precision whose
    // answer does not fit is a buffer overflow inside upstream rather than a
    // long answer. The refusal has to happen here, before the call, and the two
    // bounds differ because the two styles spend different numbers of bytes
    // around the fraction.
    try std.testing.expectError(
        error.PrecisionTooLarge,
        ryu.format64FixedOwned(1.25, ryu.owned_max_fixed_precision + 1),
    );
    try std.testing.expectError(
        error.PrecisionTooLarge,
        ryu.format64ScientificOwned(1.25, ryu.owned_max_scientific_precision + 1),
    );
    try std.testing.expectError(
        error.PrecisionTooLarge,
        ryu.format64FixedOwned(1.25, std.math.maxInt(u32)),
    );
    try std.testing.expectError(
        error.PrecisionTooLarge,
        ryu.format64ScientificOwned(1.25, std.math.maxInt(u32)),
    );

    // The fixed writer's last accepted precision still formats, and on a
    // negative value it fills upstream's buffer to the last byte: a sign, 309
    // integer digits, a point and 1688 fraction digits is 1999 bytes, and the
    // terminator `d2fixed_buffered` writes after it is the 2000th. If the
    // bound were one too high this is where it shows, as an answer that does
    // not come back rather than as a quiet overrun.
    const widest = try ryu.format64FixedOwned(-1.7976931348623157e308, ryu.owned_max_fixed_precision);
    defer widest.deinit();
    try std.testing.expectEqual(@as(usize, 1999), widest.len);
    try std.testing.expectEqual(@as(u8, '-'), widest.slice()[0]);
    try std.testing.expectEqual(@as(u8, '.'), widest.slice()[ryu.max_fixed_integer_digits + 1]);
    // DBL_MAX has no fractional part, so every digit after the point is the
    // zero padding `precision` asked for.
    for (widest.slice()[ryu.max_fixed_integer_digits + 2 ..]) |byte| {
        if (byte != '0') return error.FractionIsNotZeroPadded;
    }
}

// --- 4. The optional generic 128-bit converter --------------------------------
//
// Every test in this section is skipped, and says so, in a build that did not
// configure `-Dgeneric128`: the five entry points were neither compiled into
// the artifact nor translated, and `generic128` is `void` because there is
// nothing there to call. A skipped test is visible in the run; a build that
// quietly tested nothing would not be.

test "the generic converter answers the published shortest spelling" {
    nativeReady();
    if (comptime ryu.generic128 == void) return error.SkipZigTest;

    var out: [ryu.generic128.to_chars_capacity]u8 = undefined;
    // Upstream's own answers for these values, from the generic converter's own
    // suite: ryu/ryu/tests/generic_128_test.cc:265-287, whose local `d2s()`
    // (:249-257) is `double_to_fd128` + `generic_to_chars`, the two calls
    // `shortestChars(f64, ...)` makes. The shortest writer's suite agrees
    // (ryu/ryu/tests/d2s_test.cc:52-53) and so does testdata/d2s_shortest.txt:44.
    // The generic converter spells an exponent the same way - uppercase `E`, no
    // `+`, no padding (ryu/generic_128.c:331-345) - so the same strings hold.
    try std.testing.expectEqualStrings("1.25E0", try ryu.generic128.shortestChars(f64, 1.25, &out));
    try std.testing.expectEqualStrings("0E0", try ryu.generic128.shortestChars(f64, 0.0, &out));
    try std.testing.expectEqualStrings("-0E0", try ryu.generic128.shortestChars(f64, -0.0, &out));
    try std.testing.expectEqualStrings("1.25E0", try ryu.generic128.shortestChars(f32, 1.25, &out));
    try std.testing.expectEqualStrings(
        "1.7976931348623157E308",
        try ryu.generic128.shortestChars(f64, 1.7976931348623157e308, &out),
    );
    try std.testing.expectEqualStrings("5E-324", try ryu.generic128.shortestChars(f64, 5e-324, &out));

    // The typed converters and the bit-pattern route have to agree, because
    // `generic_binary_to_decimal` is the same function `double_to_fd128` calls
    // (`ryu/generic_128.c:61-65`): a disagreement here would mean the three
    // configuration arguments are read in the wrong order.
    const direct = ryu.generic128.fromDouble(1.25);
    const from_bits = ryu.generic128.fromBinary(
        @as(ryu.generic128.Mantissa, @as(u64, @bitCast(@as(f64, 1.25)))),
        52,
        11,
        false,
    );
    try std.testing.expectEqual(direct.mantissa, from_bits.mantissa);
    try std.testing.expectEqual(direct.exponent, from_bits.exponent);
    try std.testing.expectEqual(direct.sign, from_bits.sign);

    // `decimalFor` is the same three converters without the caller naming them,
    // so an f32 cannot reach the binary64 converter and be cast - the mistake
    // upstream's header warns about twice (`ryu/ryu_generic_128.h:29-31`).
    // `0.1f` is shortest as the decimal `0.1`, which double-conversion asserts
    // (`third_party/double-conversion/test/cctest/test-conversions.cc:229-230`),
    // and `ryu/generic_128.c:331-345` spells that `1E-1`.
    try std.testing.expectEqualStrings("1E-1", try ryu.generic128.shortestChars(f32, 0.1, &out));
    try std.testing.expectEqualStrings(
        "1E-1",
        try ryu.generic128.toChars(ryu.generic128.decimalFor(f32, 0.1), &out),
    );
}

test "the generic converter marks the non-finite values the way its writer expects" {
    nativeReady();
    if (comptime ryu.generic128 == void) return error.SkipZigTest;

    var out: [ryu.generic128.to_chars_capacity]u8 = undefined;
    const infinite = ryu.generic128.fromDouble(std.math.inf(f64));
    const negative_infinite = ryu.generic128.fromDouble(-std.math.inf(f64));
    const not_a_number = ryu.generic128.fromDouble(std.math.nan(f64));

    // `FD128_EXCEPTIONAL_EXPONENT` is the only thing that separates these three
    // from an ordinary decimal as far as the writer is concerned
    // (`ryu/generic_128.c:296-298`), so it has to be there for all three and
    // the mantissa has to be zero for the two infinities.
    for ([_]ryu.generic128.Decimal{ infinite, negative_infinite, not_a_number }) |decimal| {
        try std.testing.expectEqual(
            ryu.generic128.exceptional_exponent,
            @as(i32, @intCast(decimal.exponent)),
        );
    }
    try std.testing.expectEqual(@as(ryu.generic128.Mantissa, 0), infinite.mantissa);
    try std.testing.expectEqual(@as(ryu.generic128.Mantissa, 0), negative_infinite.mantissa);
    try std.testing.expect(!infinite.sign);
    try std.testing.expect(negative_infinite.sign);

    // The writer's three spellings, from `copy_special_str`
    // (`ryu/generic_128.c:284-294`): a NaN carries no sign whatever `sign` is,
    // which is why a negative NaN is "NaN" and not "-NaN".
    try std.testing.expectEqualStrings("Infinity", try ryu.generic128.toChars(infinite, &out));
    try std.testing.expectEqualStrings("-Infinity", try ryu.generic128.toChars(negative_infinite, &out));
    try std.testing.expectEqualStrings("NaN", try ryu.generic128.toChars(not_a_number, &out));

    const negative_nan = ryu.generic128.fromDouble(-std.math.nan(f64));
    try std.testing.expectEqualStrings("NaN", try ryu.generic128.toChars(negative_nan, &out));
}

test "the generic converter stops at the answer and refuses a buffer one byte short" {
    nativeReady();
    if (comptime ryu.generic128 == void) return error.SkipZigTest;

    var tight: [6]u8 = undefined;
    try std.testing.expectEqualStrings("1.25E0", try ryu.generic128.shortestChars(f64, 1.25, &tight));

    var one_short: [5]u8 = @splat(untouched);
    try std.testing.expectError(
        error.BufferTooSmall,
        ryu.generic128.shortestChars(f64, 1.25, &one_short),
    );
    try expectUntouched(&one_short);

    var empty_buffer: [0]u8 = undefined;
    try std.testing.expectError(
        error.BufferTooSmall,
        ryu.generic128.shortestChars(f64, 1.25, &empty_buffer),
    );

    // The residue past the answer is the caller's, as on every other writer here.
    var padded: [ryu.generic128.to_chars_capacity]u8 = @splat(untouched);
    const got = try ryu.generic128.shortestChars(f64, 1.25, &padded);
    try std.testing.expectEqualStrings("1.25E0", got);
    try expectUntouched(padded[got.len..]);
}

test "the x87 long double converter reads the format upstream says it reads" {
    nativeReady();
    if (comptime ryu.generic128 == void) return error.SkipZigTest;
    // Upstream's header qualifies this entry point itself: it "likely only
    // works on x86 with specific compilers (clang?)"
    // (`ryu/ryu_generic_128.h:50-51`), because the converter is told 64 mantissa
    // bits, 15 exponent bits and an explicit leading bit
    // (`ryu/generic_128.c:80`) and `memcpy`s a whole `long double` into the
    // bit pattern (`ryu/generic_128.c:70-72`). Those numbers are x87's. So the
    // published answer is checked only where `long double` really is that
    // format, and the test is skipped elsewhere rather than asserting an answer
    // upstream does not promise there.
    // On the pinned Zig the translated header spells that parameter
    // `c_longdouble`, so `LongDouble` is that opaque type rather than `f80` on
    // any target, and Zig cannot spell a value for it at all
    // (`lib/std/zig/c_translation/helpers.zig:387`). The guard is a hard
    // boundary: removing it would not make this test pass, it would not compile.
    if (comptime ryu.generic128.LongDouble != f80) return error.SkipZigTest;

    var out: [ryu.generic128.to_chars_capacity]u8 = undefined;
    try std.testing.expectEqualStrings(
        "1.25E0",
        try ryu.generic128.toChars(ryu.generic128.fromLongDouble(1.25), &out),
    );
    try std.testing.expectEqualStrings(
        "1.25E0",
        try ryu.generic128.shortestChars(ryu.generic128.LongDouble, 1.25, &out),
    );
}
