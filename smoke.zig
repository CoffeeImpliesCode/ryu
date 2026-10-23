//! Deterministic smoke executable for Ryu's Zig facade and upstream C API.
//! Runtime-loaded runs require an explicit provider; owned results use C `free`.
//!

const std = @import("std");
const ryu = @import("ryu");

/// Load the named file through the platform loader.
const provider_flag = "--provider";
/// Load the named library by basename through the platform loader.
const system_flag = "--system";
/// Environment variable used when the build cannot pass provider arguments.
const provider_variable = "RYU_PROVIDER";

/// A provider request and its original form for display.
const ProviderRequest = struct {
    /// The source passed to `load`.
    source: ryu.LoadSource,
    /// Whether this request came from a file path or system name.
    how: []const u8,
    /// The provider name exactly as supplied.
    name: []const u8,
};

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const w = &stdout.interface;

    try w.print("ryu smoke\n", .{});

    // Load explicitly before any upstream call in runtime mode.
    if (comptime ryu.runtime_loaded) {
        const request = try resolveSource(init);
        ryu.load(request.source) catch |err| {
            std.debug.print(
                "ryu smoke: loading the {s} \"{s}\" failed: {t}\n",
                .{ request.how, request.name, err },
            );
            return error.ProviderDidNotLoad;
        };
        if (ryu.loadedSource() == null) return error.ProviderDidNotLoad;
        try w.print("{s: <44}{s} {s}\n", .{ "loaded", request.how, request.name });
    }

    // Call upstream directly to include the raw C API in this check.
    var raw: [ryu.double_shortest_capacity]u8 = undefined;
    const raw_len = ryu.c.d2s_buffered_n(1.25, &raw);
    if (raw_len < 0) return error.NegativeLength;
    try check(w, "c.d2s_buffered_n(1.25)", raw[0..@intCast(raw_len)], "1.25E0");

    // Known outputs for 1.25 expose all three formatting styles.
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

    // An exact-size buffer verifies the shortest writer needs no extra byte.
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

    // Binary32 extremes from upstream's fixtures.
    var shortest32: [ryu.float_shortest_capacity]u8 = undefined;
    try check(w, "format32Shortest(3.4028235e38)", try ryu.format32Shortest(3.4028235e38, &shortest32), "3.4028235E38");
    try check(w, "format32Shortest(1e-45)", try ryu.format32Shortest(1.0e-45, &shortest32), "1E-45");
    try check(w, "format32Shortest(0.1)", try ryu.format32Shortest(0.1, &shortest32), "1E-1");

    // Upstream rounds ties to even and carries runs of nines.
    try check(w, "format64Fixed(2.5, 0)", try ryu.format64Fixed(2.5, 0, &precision_buffer), "2");
    try check(w, "format64Fixed(3.5, 0)", try ryu.format64Fixed(3.5, 0, &precision_buffer), "4");
    try check(w, "format64Fixed(9.9999, 3)", try ryu.format64Fixed(9.9999, 3, &precision_buffer), "10.000");
    try check(
        w,
        "format64Scientific(9.9999, 3)",
        try ryu.format64Scientific(9.9999, 3, &precision_buffer),
        "1.000e+01",
    );

    // Release upstream-owned results with the C library's `free`.
    {
        const shortest_owned = try ryu.format64ShortestOwned(1.25);
        defer shortest_owned.deinit();
        try check(w, "format64ShortestOwned(1.25)", shortest_owned.slice(), "1.25E0");

        const fixed_owned = try ryu.format64FixedOwned(1.25, 3);
        defer fixed_owned.deinit();
        try check(w, "format64FixedOwned(1.25, 3)", fixed_owned.slice(), "1.250");

        const scientific_owned = try ryu.format64ScientificOwned(1.25, 2);
        defer scientific_owned.deinit();
        try check(w, "format64ScientificOwned(1.25, 2)", scientific_owned.slice(), "1.25e+00");

        const shortest32_owned = try ryu.format32ShortestOwned(1.25);
        defer shortest32_owned.deinit();
        try check(w, "format32ShortestOwned(1.25)", shortest32_owned.slice(), "1.25E0");
    }

    // Owned precision writers refuse answers that exceed upstream's 2000-byte allocation.
    if (ryu.format64FixedOwned(1.25, ryu.owned_max_fixed_precision + 1)) |owned| {
        owned.deinit();
        std.debug.print("format64FixedOwned(1.25, max+1): expected a refusal\n", .{});
        return error.SmokeCheckFailed;
    } else |err| {
        try w.print("{s: <44}{s}\n", .{ "format64FixedOwned(1.25, max+1)", @errorName(err) });
        if (err != error.PrecisionTooLarge) return error.SmokeCheckFailed;
    }
    if (ryu.format64ScientificOwned(1.25, ryu.owned_max_scientific_precision + 1)) |owned| {
        owned.deinit();
        std.debug.print("format64ScientificOwned(1.25, max+1): expected a refusal\n", .{});
        return error.SmokeCheckFailed;
    } else |err| {
        try w.print("{s: <44}{s}\n", .{ "format64ScientificOwned(1.25, max+1)", @errorName(err) });
        if (err != error.PrecisionTooLarge) return error.SmokeCheckFailed;
    }

    // Exercise the experimental parser against upstream's accepted and rejected inputs.
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

    // The generic converter exists only when `-Dgeneric128` is enabled.
    if (comptime ryu.generic128 != void) {
        var generic: [ryu.generic128.to_chars_capacity]u8 = undefined;
        try check(
            w,
            "generic128.shortestChars(f64, 1.25)",
            try ryu.generic128.shortestChars(f64, 1.25, &generic),
            "1.25E0",
        );
        try check(
            w,
            "generic128.shortestChars(f32, 1.25)",
            try ryu.generic128.shortestChars(f32, 1.25, &generic),
            "1.25E0",
        );
        try check(
            w,
            "generic128.shortestChars(f64, DBL_MAX)",
            try ryu.generic128.shortestChars(f64, 1.7976931348623157e308, &generic),
            "1.7976931348623157E308",
        );
        try check(
            w,
            "generic128.shortestChars(f64, inf)",
            try ryu.generic128.shortestChars(f64, std.math.inf(f64), &generic),
            "Infinity",
        );
        try w.print("{s: <44}{d}\n", .{ "generic128.to_chars_capacity", ryu.generic128.to_chars_capacity });
        try w.print("{s: <44}{d}\n", .{ "generic128.exceptional_exponent", ryu.generic128.exceptional_exponent });
    }

    // Print the published buffer capacities for each writer.
    try w.print("{s: <44}{d}\n", .{ "double_shortest_capacity", ryu.double_shortest_capacity });
    try w.print("{s: <44}{d}\n", .{ "float_shortest_capacity", ryu.float_shortest_capacity });
    try w.print("{s: <44}{d}\n", .{ "fixedCapacity(0)", try ryu.fixedCapacity(0) });
    try w.print("{s: <44}{d}\n", .{ "scientificCapacity(0)", try ryu.scientificCapacity(0) });
    try w.print("{s: <44}{d}\n", .{ "owned_max_fixed_precision", ryu.owned_max_fixed_precision });
    try w.print("{s: <44}{d}\n", .{ "owned_max_scientific_precision", ryu.owned_max_scientific_precision });

    try w.print("every answer matched\n", .{});
    try w.flush();
}

/// Resolves an explicit file or system-library request from arguments or environment.
/// Missing and empty sources are rejected; neither form falls back to the other.
fn resolveSource(init: std.process.Init) !ProviderRequest {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const flag = args[index];
        const is_path = std.mem.eql(u8, flag, provider_flag);
        const is_system = std.mem.eql(u8, flag, system_flag);
        if (!is_path and !is_system) {
            std.debug.print("ryu smoke: unknown argument '{s}'\n", .{flag});
            return error.UnknownArgument;
        }
        // Accept `--flag value` and `--flag=value` without fallback.
        const value = inlineValue(flag) orelse if (index + 1 < args.len) args[index + 1] else {
            std.debug.print("ryu smoke: {s} needs a value\n", .{flag});
            return error.ProviderNotNamed;
        };
        if (value.len == 0) {
            std.debug.print("ryu smoke: {s} was given an empty value\n", .{flag});
            return error.ProviderNotNamed;
        }
        return if (is_path)
            .{ .source = .{ .path = value }, .how = provider_flag, .name = value }
        else
            .{ .source = .{ .system = value }, .how = system_flag, .name = value };
    }
    if (init.environ_map.get(provider_variable)) |value| {
        if (value.len == 0) {
            std.debug.print("ryu smoke: {s} is set but empty\n", .{provider_variable});
            return error.ProviderNotNamed;
        }
        return .{
            .source = .{ .path = value },
            .how = provider_variable,
            .name = value,
        };
    }
    std.debug.print(
        "ryu smoke: this is a runtime-loading build and no provider was named.\n" ++
            "Pass {s} <file>, or {s} <basename>, or export {s}.\n",
        .{ provider_flag, system_flag, provider_variable },
    );
    return error.ProviderNotNamed;
}

/// Returns an inline flag value, or null when the value is a separate argument.
fn inlineValue(flag: []const u8) ?[]const u8 {
    const prefix = if (std.mem.startsWith(u8, flag, provider_flag))
        provider_flag
    else if (std.mem.startsWith(u8, flag, system_flag))
        system_flag
    else
        return null;
    if (flag.len <= prefix.len or flag[prefix.len] != '=') return null;
    return flag[prefix.len + 1 ..];
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
