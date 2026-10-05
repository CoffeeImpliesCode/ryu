// SPDX-License-Identifier: Apache-2.0
//
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
//!
//! ## The provider, in a runtime-loading build
//!
//! A dependent that reaches Ryu through a loader rather than through the link
//! line has to say which file that is; nothing here guesses. `--provider
//! <file>` and `--provider=<file>` name one, `--system <name>` hands a basename
//! to the platform loader, and `RYU_PROVIDER` in the environment names a file
//! for a run step that cannot be given arguments. In a linked build none of the
//! three is read and the archive is already in the binary; in a
//! runtime-loading build one of them is required, and this program fails rather
//! than falling back to whatever linkage it was built with.

const std = @import("std");
const ryu = @import("ryu");

/// Load the named file through the platform loader.
const provider_flag = "--provider";
/// Load the named library by basename through the platform loader.
const system_flag = "--system";
/// The environment's alternative to `provider_flag`, for a run step the build
/// cannot pass arguments to.
const provider_variable = "RYU_PROVIDER";

/// The decimal this consumer is built around. It is the value the assignment
/// names, and it is exactly representable in both binary32 and binary64, so
/// its three spellings are all exact and none of them depends on rounding.
const one_and_a_quarter: f64 = 1.25;

/// What the command line or the environment asked for, and how it asked.
const ProviderRequest = struct {
    /// The request `load` is given.
    source: ryu.LoadSource,
    /// Which of the two forms it came in as, for the one line printed about it.
    how: []const u8,
    /// The name exactly as given, which is what a reader needs to see.
    name: []const u8,
};

pub fn main(init: std.process.Init) !void {
    var buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writerStreaming(init.io, &buffer);
    const w = &stdout.interface;

    try w.print("ryu consumer\n", .{});

    // The one explicit load, before anything reaches upstream. No-op at comptime
    // in a linked build.
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

    // Through the raw escape hatch first, so this line is the C entry point
    // that was linked into this binary rather than a constant compiled into the
    // source. It is also the proof that `pub const c` survives the module
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

    // The same answers through the allocating entry points, which hand back a
    // string the caller owns and releases with the C library's `free`. That is
    // the only memory this consumer has to release, and it is the only thing in
    // the published surface that crosses an allocator boundary.
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

    // The boundary a dependent has to be able to trust: the precision the
    // scientific writer cannot represent is refused across the package
    // boundary, by the capacity query and by the writer, before anything is
    // written. Upstream's own `d2exp_buffered_n` raises its `uint32_t`
    // precision by one first, so `maxInt(u32)` wraps there and the answer that
    // comes back is wrong rather than long - which is why this is a refusal
    // and not a documented limit the caller has to remember.
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

    // The other boundary the allocating writers add: upstream allocated their
    // own 2000 byte buffer and checks nothing against it, so a precision that
    // does not fit in it is refused here rather than overrunning there.
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

    // Upstream's experimental parser, reached across the module boundary, from
    // ryu/ryu/tests/s2d_test.cc Basic.
    const parsed = try ryu.experimental.parse64("1.25E0");
    try w.print("{s: <44}{d}\n", .{ "experimental.parse64(\"1.25E0\")", parsed });
    if (@as(u64, @bitCast(parsed)) != @as(u64, @bitCast(one_and_a_quarter))) {
        std.debug.print("experimental.parse64(\"1.25E0\"): expected 1.25, got {d}\n", .{parsed});
        return error.ConsumerCheckFailed;
    }

    // The optional generic 128-bit converter, in a build configured with
    // `-Dgeneric128`. It is `void` otherwise, so this block does not exist
    // there rather than failing.
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

/// The provider to load, from the arguments or the environment.
///
/// `--provider` is a file and `--system` is a basename for the platform loader,
/// and neither falls back to the other. An empty value is a caller mistake
/// rather than a missing file, so it is refused here rather than handed on.
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
        // Both spellings are accepted: `--provider <file>` and
        // `--provider=<file>` name the same request, and neither form falls
        // back to the other flag.
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

/// The value inside a `--provider=<value>` or `--system=<value>` argument.
///
/// Null when the argument is the bare flag, which means the value is the next
/// argument - the two spellings name the same request and the flag is not
/// matched twice.
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
        return error.ConsumerCheckFailed;
    }
}