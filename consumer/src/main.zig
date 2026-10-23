// SPDX-License-Identifier: Apache-2.0
//
//! Runtime-loaded builds require an explicit provider request or `RYU_PROVIDER`.

const std = @import("std");
const ryu = @import("ryu");

const provider_flag = "--provider";
const system_flag = "--system";
const provider_variable = "RYU_PROVIDER";

const one_and_a_quarter: f64 = 1.25;

const ProviderRequest = struct {
    source: ryu.LoadSource,
    how: []const u8,
    name: []const u8,
};

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const w = &stdout.interface;

    try w.print("ryu consumer\n", .{});

    if (comptime ryu.runtime_loaded) {
        const request = try resolveSource(init);
        ryu.load(request.source) catch |err| {
            std.debug.print(
                "ryu consumer: loading the {s} \"{s}\" failed: {t}\n",
                .{ request.how, request.name, err },
            );
            return error.ProviderDidNotLoad;
        };
        if (ryu.loadedSource() == null) return error.ProviderDidNotLoad;
        try w.print("{s: <44}{s} {s}\n", .{ "loaded", request.how, request.name });
    }

    var raw: [ryu.double_shortest_capacity]u8 = undefined;
    const raw_len = ryu.c.d2s_buffered_n(one_and_a_quarter, &raw);
    if (raw_len < 0) return error.NegativeLength;
    try check(w, "c.d2s_buffered_n(1.25)", raw[0..@intCast(raw_len)], "1.25E0");

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

    // Owned results use C `free`, wrapped by `deinit`.
    {
        const shortest_owned = try ryu.format64ShortestOwned(one_and_a_quarter);
        defer shortest_owned.deinit();
        try check(w, "format64ShortestOwned(1.25)", shortest_owned.slice(), "1.25E0");

        const fixed_owned = try ryu.format64FixedOwned(one_and_a_quarter, 3);
        defer fixed_owned.deinit();
        try check(w, "format64FixedOwned(1.25, 3)", fixed_owned.slice(), "1.250");

        const scientific_owned = try ryu.format64ScientificOwned(one_and_a_quarter, 2);
        defer scientific_owned.deinit();
        try check(w, "format64ScientificOwned(1.25, 2)", scientific_owned.slice(), "1.25e+00");
    }

    // Special-value answers from upstream's `D2sTest.Basic` and `d2fixed.c:331-356`.
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

    try check(
        w,
        "format64Fixed into exactly fixedCapacity(3) bytes",
        try ryu.format64Fixed(one_and_a_quarter, 3, precision_buffer[0..try ryu.fixedCapacity(3)]),
        "1.250",
    );

    // `d2exp_buffered_n` increments a `u32` precision; reject the maximum before it wraps.
    // The capacity query and writer must refuse it without changing the buffer.
    if (ryu.scientificCapacity(std.math.maxInt(u32))) |_| {
        std.debug.print("scientificCapacity(maxInt(u32)): expected a refusal\n", .{});
        return error.ConsumerCheckFailed;
    } else |err| {
        if (err != error.PrecisionTooLarge) {
            std.debug.print("scientificCapacity(maxInt(u32)): expected PrecisionTooLarge, got {s}\n", .{@errorName(err)});
            return error.ConsumerCheckFailed;
        }
    }

    var refused: [16]u8 = @splat(0xA5);
    if (ryu.format64Scientific(one_and_a_quarter, std.math.maxInt(u32), &refused)) |answer| {
        std.debug.print("format64Scientific(1.25, maxInt(u32)): expected a refusal, got {s}\n", .{answer});
        return error.ConsumerCheckFailed;
    } else |err| {
        if (err != error.PrecisionTooLarge) {
            std.debug.print("format64Scientific(1.25, maxInt(u32)): expected PrecisionTooLarge, got {s}\n", .{@errorName(err)});
            return error.ConsumerCheckFailed;
        }
    }
    for (refused) |byte| {
        if (byte != 0xA5) {
            std.debug.print("format64Scientific(1.25, maxInt(u32)): wrote into a refused buffer\n", .{});
            return error.ConsumerCheckFailed;
        }
    }
    try w.print("{s: <44}{s}\n", .{ "format64Scientific(1.25, maxInt(u32))", "PrecisionTooLarge" });

    if (ryu.format64FixedOwned(one_and_a_quarter, ryu.owned_max_fixed_precision + 1)) |owned| {
        owned.deinit();
        std.debug.print("format64FixedOwned(1.25, max+1): expected a refusal\n", .{});
        return error.ConsumerCheckFailed;
    } else |err| {
        if (err != error.PrecisionTooLarge) {
            std.debug.print("format64FixedOwned(1.25, max+1): expected PrecisionTooLarge, got {s}\n", .{@errorName(err)});
            return error.ConsumerCheckFailed;
        }
    }
    try w.print("{s: <44}{s}\n", .{ "format64FixedOwned(1.25, max+1)", "PrecisionTooLarge" });

    // Upstream's experimental parser answer (`s2d_test.cc: Basic`).
    const parsed = try ryu.experimental.parse64("1.25E0");
    try w.print("{s: <44}{d}\n", .{ "experimental.parse64(\"1.25E0\")", parsed });
    if (@as(u64, @bitCast(parsed)) != @as(u64, @bitCast(one_and_a_quarter))) {
        std.debug.print("experimental.parse64(\"1.25E0\"): expected 1.25, got {d}\n", .{parsed});
        return error.ConsumerCheckFailed;
    }

    // This API exists only when `-Dgeneric128` is enabled.
    if (comptime ryu.generic128 != void) {
        var generic: [ryu.generic128.to_chars_capacity]u8 = undefined;
        try check(
            w,
            "generic128.shortestChars(f64, 1.25)",
            try ryu.generic128.shortestChars(f64, one_and_a_quarter, &generic),
            "1.25E0",
        );
        try check(
            w,
            "generic128.shortestChars(f32, 1.25)",
            try ryu.generic128.shortestChars(f32, @as(f32, one_and_a_quarter), &generic),
            "1.25E0",
        );
    }

    try w.print("every answer matched the published values\n", .{});
    try w.flush();
}

/// Resolve `--provider`, `--system` or `RYU_PROVIDER`; empty values are rejected.
fn resolveSource(init: std.process.Init) !ProviderRequest {
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    var index: usize = 1;
    while (index < args.len) : (index += 1) {
        const flag = args[index];
        const is_path = std.mem.eql(u8, flag, provider_flag);
        const is_system = std.mem.eql(u8, flag, system_flag);
        if (!is_path and !is_system) {
            std.debug.print("ryu consumer: unknown argument '{s}'\n", .{flag});
            return error.UnknownArgument;
        }
        // Accept separated and `=` flag values without crossing between flags.
        const value = inlineValue(flag) orelse if (index + 1 < args.len) args[index + 1] else {
            std.debug.print("ryu consumer: {s} needs a value\n", .{flag});
            return error.ProviderNotNamed;
        };
        if (value.len == 0) {
            std.debug.print("ryu consumer: {s} was given an empty value\n", .{flag});
            return error.ProviderNotNamed;
        }
        return if (is_path)
            .{ .source = .{ .path = value }, .how = provider_flag, .name = value }
        else
            .{ .source = .{ .system = value }, .how = system_flag, .name = value };
    }
    if (init.environ_map.get(provider_variable)) |value| {
        if (value.len == 0) {
            std.debug.print("ryu consumer: {s} is set but empty\n", .{provider_variable});
            return error.ProviderNotNamed;
        }
        return .{
            .source = .{ .path = value },
            .how = provider_variable,
            .name = value,
        };
    }
    std.debug.print(
        "ryu consumer: this is a runtime-loading build and no provider was named.\n" ++
            "Pass {s} <file>, or {s} <basename>, or export {s}.\n",
        .{ provider_flag, system_flag, provider_variable },
    );
    return error.ProviderNotNamed;
}

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

fn check(w: *std.Io.Writer, what: []const u8, answer: []const u8, expected: []const u8) !void {
    try w.print("{s: <44}{s}\n", .{ what, answer });
    if (!std.mem.eql(u8, expected, answer)) {
        std.debug.print("{s}: expected {s}, the answer is {s}\n", .{ what, expected, answer });
        return error.ConsumerCheckFailed;
    }
}
