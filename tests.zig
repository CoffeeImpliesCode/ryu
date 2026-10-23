//! Behavioral tests for Ryu's facade against upstream fixtures and independent implementations.
//! Runtime-loading tests require `RYU_TEST_PROVIDER`; linked builds need no provider.
//!

const std = @import("std");
const ryu = @import("ryu");

/// Loads the explicit provider before tests use the runtime-loaded facade.
/// Linked builds need no setup; a missing provider is an error, not a skipped test.
const provider_variable = "RYU_TEST_PROVIDER";
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

/// Reads a line-oriented fixture, skipping its header and blank lines.
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

/// Compares shortest strings after normalizing only the exponent marker.
fn shortestSpellingMatches(zig: []const u8, ryu_text: []const u8) bool {
    if (zig.len != ryu_text.len) return false;
    for (zig, ryu_text) |want, got| {
        if (want != if (got == 'E') 'e' else got) return false;
    }
    return true;
}

/// Splits scientific text into a mantissa and signed exponent.
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

/// Sentinel byte for checking that rejected calls leave output untouched.
const untouched: u8 = 0xA5;

fn expectUntouched(buffer: []const u8) !void {
    for (buffer) |byte| {
        if (byte != untouched) return error.WroteIntoARefusedBuffer;
    }
}

/// Checks both precision styles against their exact published capacity bounds.
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

test "binary64 shortest reproduces every published answer" {
    nativeReady();
    // The count prevents an empty or unparsed fixture from passing.
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

        // Exact-sized buffers exercise the documented capacity bound.
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

test "every published binary64 shortest answer names the fixture's own value" {
    nativeReady();
    var fixture = Fixture.init("testdata/d2s_shortest.txt");
    while (fixture.next()) |line| {
        var fields = std.mem.splitSequence(u8, line, "\t");
        const spec = fields.next().?;
        const expected = fields.next().?;
        // Special values have no unique bit pattern for the independent parser to verify.
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

test "binary64 shortest agrees with Zig's own shortest formatter" {
    nativeReady();
    // Zig's formatter is independent of Ryu, so matching digits cross-check both.
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
    // Exclude ties: Ryu rounds them to even, while Zig's formatter rounds toward zero.
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

test "a tie rounds to even in both fixed and scientific" {
    nativeReady();
    // Upstream fixtures pin the intentional tie-rounding difference.
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
    // Exact binary64 inputs here exercise carries across the decimal point in both styles.
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
    // At `0.9999`, fixed precision 3 carries while scientific precision 3 retains four significant digits.
    const cases = [_]struct { value: f64, precision: u32, fixed: []const u8, scientific: []const u8 }{
        .{ .value = 0.9999, .precision = 4, .fixed = "0.9999", .scientific = "9.9990e-01" },
        .{ .value = 0.9999, .precision = 3, .fixed = "1.000", .scientific = "9.999e-01" },
    };
    for (cases) |case| {
        try expectBothPrecisionStyles(case.value, case.precision, case.fixed, case.scientific);
    }
}

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
    // Exact-sized buffers verify the minimum accepted output length.
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

test "special scientific outputs fit the minimum-precision buffer" {
    nativeReady();
    // Include the 10-byte MSVC NaN spelling without claiming this compiler selects it.
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
    // DBL_MAX has 309 integer digits, even at precision zero.
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
    // Upstream increments `u32` precision; reject its maximum before the increment wraps.
    const huge = std.math.maxInt(u32);
    try std.testing.expectError(error.PrecisionTooLarge, ryu.scientificCapacity(huge));

    var buffer: [16]u8 = @splat(untouched);
    try std.testing.expectError(
        error.PrecisionTooLarge,
        ryu.format64Scientific(1.0, huge, &buffer),
    );
    try expectUntouched(&buffer);

    // Special values bypass the digit loop but must still reject excessive precision.
    try std.testing.expectError(
        error.PrecisionTooLarge,
        ryu.format64Scientific(-std.math.inf(f64), huge, &buffer),
    );
    try expectUntouched(&buffer);
}

test "each precision writer's last accepted precision is its last representable answer" {
    nativeReady();
    // Capacity is bounded by upstream's signed-`int` length, not the full `u32` range.
    const written_max: usize = @intCast(std.math.maxInt(c_int));

    // Measure each style's fixed overhead above the special-value floor.
    const fixed_overhead = try ryu.fixedCapacity(16) - 16;
    const scientific_overhead = try ryu.scientificCapacity(16) - 16;
    try std.testing.expectEqual(1 + ryu.max_fixed_integer_digits + 1, fixed_overhead);
    try std.testing.expectEqual(@as(usize, 8), scientific_overhead);

    const fixed_last: u32 = @intCast(written_max - fixed_overhead);
    const scientific_last: u32 = @intCast(written_max - scientific_overhead);
    try std.testing.expectEqual(written_max, try ryu.fixedCapacity(fixed_last));
    try std.testing.expectEqual(written_max, try ryu.scientificCapacity(scientific_last));

    // One-past-limit precisions must fail before writing.
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
    // Large fixed and scientific outputs exercise the bounds at precision 100,000.
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
    // The fixtures omit negative zero for these two precision writers.
    const cases = [_]struct { precision: u32, fixed: []const u8, scientific: []const u8 }{
        .{ .precision = 3, .fixed = "-0.000", .scientific = "-0.000e+00" },
        .{ .precision = 0, .fixed = "-0", .scientific = "-0e+00" },
    };
    for (cases) |case| {
        try expectBothPrecisionStyles(-0.0, case.precision, case.fixed, case.scientific);
    }
}

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
    // The parser rejects 18 nonzero mantissa digits; shortest formatting accepts 17.
    try std.testing.expectError(
        error.InputTooLong,
        ryu.experimental.parse64("123456789012345678"),
    );
    try std.testing.expectError(
        error.MalformedInput,
        ryu.experimental.parse64("1.25E0 x"),
    );
    // The parser also accepts the shortest spelling for 1.25.
    try std.testing.expectEqual(
        @as(u64, 0x3FF4000000000000),
        @as(u64, @bitCast(try ryu.experimental.parse64("1.25E0"))),
    );
}

test "the two experimental parsers refuse at their own mantissa widths" {
    nativeReady();
    // The binary32 parser accepts at most 9 nonzero mantissa digits; binary64 accepts 17.
    const nine = "123456789";
    const ten = "1234567890";

    // Nine digits are accepted by both widths.
    try std.testing.expectEqual(@as(f32, 123456792.0), try ryu.experimental.parse32(nine));
    try std.testing.expectEqual(@as(f64, 123456789.0), try ryu.experimental.parse64(nine));

    // The tenth digit exceeds only the binary32 parser's limit.
    try std.testing.expectEqual(@as(f64, 1234567890.0), try ryu.experimental.parse64(ten));
    try std.testing.expectError(error.InputTooLong, ryu.experimental.parse32(ten));
}

// Owned-string tests cover the C allocation boundary and upstream's published answers.

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
        // Upstream's returned length points at its NUL terminator.
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
    // Every published precision fixture fits upstream's 2000-byte owned buffer.
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
    // Reject precision that could overflow upstream's fixed 2000-byte owned buffer.
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

    // The maximum accepted fixed precision uses 1999 data bytes plus the terminator.
    const widest = try ryu.format64FixedOwned(-1.7976931348623157e308, ryu.owned_max_fixed_precision);
    defer widest.deinit();
    try std.testing.expectEqual(@as(usize, 1999), widest.len);
    try std.testing.expectEqual(@as(u8, '-'), widest.slice()[0]);
    try std.testing.expectEqual(@as(u8, '.'), widest.slice()[ryu.max_fixed_integer_digits + 1]);
    // The fractional part is zero padding because DBL_MAX is integral.
    for (widest.slice()[ryu.max_fixed_integer_digits + 2 ..]) |byte| {
        if (byte != '0') return error.FractionIsNotZeroPadded;
    }
}

// These tests run only when the optional generic128 component is compiled.

test "the generic converter answers the published shortest spelling" {
    nativeReady();
    if (comptime ryu.generic128 == void) return error.SkipZigTest;

    var out: [ryu.generic128.to_chars_capacity]u8 = undefined;
    // These expected strings are published by Ryu's generic and binary64 shortest suites.
    try std.testing.expectEqualStrings("1.25E0", try ryu.generic128.shortestChars(f64, 1.25, &out));
    try std.testing.expectEqualStrings("0E0", try ryu.generic128.shortestChars(f64, 0.0, &out));
    try std.testing.expectEqualStrings("-0E0", try ryu.generic128.shortestChars(f64, -0.0, &out));
    try std.testing.expectEqualStrings("1.25E0", try ryu.generic128.shortestChars(f32, 1.25, &out));
    try std.testing.expectEqualStrings(
        "1.7976931348623157E308",
        try ryu.generic128.shortestChars(f64, 1.7976931348623157e308, &out),
    );
    try std.testing.expectEqualStrings("5E-324", try ryu.generic128.shortestChars(f64, 5e-324, &out));

    // `fromBinary` must match typed conversion when format widths and leading-bit flags agree.
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

    // `decimalFor` selects the matching width-specific converter without widening.
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

    // The sentinel exponent marks exceptional values; infinities also require zero mantissas.
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

    // Upstream prints NaN without a sign, regardless of the stored sign bit.
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
    // Upstream warns that long-double conversion is compiler/platform-specific.
    // Test only when the translated type is `f80`; otherwise Zig cannot construct it.
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
