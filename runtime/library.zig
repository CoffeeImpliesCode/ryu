// SPDX-License-Identifier: Apache-2.0
//
//! Ryu-specific provider symbols, ABI requirements and load-time validation.
const rt = @import("rt");
const std = @import("std");

/// Ryu's namespaced sync binding; keep `ryu_rt` aligned with `runtime/graph.zig`.
pub const Sync = struct {
    extern fn ryu_rt_lock() void;
    extern fn ryu_rt_unlock() void;
    extern fn ryu_rt_wait() void;
    extern fn ryu_rt_broadcast() void;
    // Matches C `unsigned long long` on the supported targets.
    extern fn ryu_rt_thread_self() u64;

    pub fn lock() void {
        ryu_rt_lock();
    }
    pub fn unlock() void {
        ryu_rt_unlock();
    }
    pub fn wait() void {
        ryu_rt_wait();
    }
    pub fn broadcast() void {
        ryu_rt_broadcast();
    }
    pub fn threadSelf() u64 {
        return ryu_rt_thread_self();
    }
};

/// Call libc's direct `free` for strings allocated by the provider.
extern fn free(ptr: ?*anyopaque) void;

/// Loader descriptor for the generated dispatch table.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Library name used in pre-load diagnostics.
        pub const library_name = "ryu";

        /// Table and symbols generated from the translated header.
        pub const table = dispatch.Table;
        pub const symbols = dispatch.symbols;
        pub const optional_symbols = dispatch.optional_symbols;

        /// The project's namespaced synchronization binding.
        pub const sync = Sync;

        pub fn tablePtr() *table {
            return dispatch.tablePtr();
        }

        pub fn ready() *rt.Ready {
            return &dispatch.ready;
        }

        pub fn assign(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assign(index, dst, address);
        }

        pub inline fn assignOptional(comptime index: usize, dst: *table, address: *const anyopaque) void {
            dispatch.assignOptional(index, dst, address);
        }

        pub inline fn assignMissing(comptime index: usize, dst: *table) void {
            dispatch.assignMissing(index, dst);
        }

        /// Validate buffered output and the provider-owned string before publication.
        /// The results must match, and the string must be releasable with libc.
        pub fn validate(dst: *const table) ?[]const u8 {
            var buf: [32]u8 = @splat(0);
            const len = dst.d2s_buffered_n(1.25, &buf);
            if (len <= 0 or len > buf.len) {
                return "d2s_buffered_n(1.25) returned a length outside the " ++
                    "buffer it was given, so this provider does not write into " ++
                    "a caller's buffer the way ryu/ryu.h:26 declares";
            }
            if (!std.mem.eql(u8, buf[0..@intCast(len)], "1.25E0")) {
                return "d2s_buffered_n(1.25) did not answer \"1.25E0\", the value " ++
                    "upstream's own D2sTest.Basic and ryu/d2s.c:400-417 publish " ++
                    "for it, so this provider is not the library this header " ++
                    "describes";
            }

            const owned = dst.d2s(1.25);
            // A null `char*` is address zero; upstream does not check `malloc` (`ryu/d2s.c:506`).
            if (@intFromPtr(owned) == 0) {
                return "d2s(1.25) returned NULL, so the provider's own allocator " ++
                    "would not satisfy 25 bytes for this process";
            }
            defer free(owned);
            if (!std.mem.eql(u8, std.mem.span(owned), "1.25E0")) {
                return "d2s(1.25) did not answer \"1.25E0\", so the allocating " ++
                    "entry point and the buffered one disagree about the same " ++
                    "value and this provider is not self-consistent";
            }
            return null;
        }
    };
}
