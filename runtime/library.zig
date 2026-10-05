// SPDX-License-Identifier: Apache-2.0
//
//! Ryu's side of the runtime loader: the names its synchronization binding has,
//! and what it requires of a provider beyond resolving its symbols.
//!
//! Everything else about the runtime route is generic. `runtime/loader.zig` is
//! the state machine and the platform layer; `runtime/generate.zig` builds the
//! dispatch from whatever the translation step actually produced;
//! `runtime/graph.zig` wires them together. This file is what makes them Ryu's,
//! and it is the file another SDK replaces.
//!
//! ## What a provider must export
//!
//! **The sixteen default entry points, all of them.** `ryu/ryu.h:26-40` declares
//! twelve and `ryu/ryu_parse.h:36-42` declares four:
//!
//!   `d2s_buffered_n`, `d2s_buffered`, `d2s`, `f2s_buffered_n`,
//!   `f2s_buffered`, `f2s`, `d2fixed_buffered_n`, `d2fixed_buffered`,
//!   `d2fixed`, `d2exp_buffered_n`, `d2exp_buffered`, `d2exp`,
//!   `s2d_n`, `s2d`, `s2f_n`, `s2f`.
//!
//! None of the sixteen is optional and none is excluded. A provider that
//! exports fifteen of them is refused, because the missing one is not a
//! convenience here: each is a published entry point a caller can name through
//! `ryu.c`, and the facade itself calls eight of them.
//!
//! **Five more when the build enables `-Dgeneric128`.** `ryu/ryu_generic_128.h:47-66`
//! declares `float_to_fd128`, `double_to_fd128`, `long_double_to_fd128`,
//! `generic_binary_to_decimal` and `generic_to_chars`. They are in the table
//! in exactly the configurations whose translation step produced them, which is
//! what makes the inventory per-configuration rather than a fixed list: a
//! build with the option off has none of the five to require, and a build with
//! it on requires all five. They are routed, not kept direct - there is no
//! "optional native escape" for a component this build chose to compile.
//!
//! ## The external ABI family
//!
//! Ryu is compiled as ordinary C with no build-configuration macro defined -
//! `RYU_DEBUG` is not among them (`build.zig:295-297`, and the C sources'
//! own headers define nothing else), so the six compile-time tables
//! (`d2s_full_table.h`, `d2s_small_table.h`, `d2fixed_full_table.h`,
//! `f2s_full_table.h`, `digit_table.h`) and every `RYU_*` switch in the sources
//! resolve the same way for any provider. A provider therefore needs:
//!
//!   * the platform C ABI of the target it was built for;
//!   * this target's scalar widths - `double` and `float` in the IEEE-754
//!     binary64/binary32 formats Ryu's `d2d`/`f2d` assume, `int` for every
//!     returned length (`ryu/ryu.h:26,30,34,38`), `unsigned int` for every
//!     `precision` parameter, and `int` for `enum Status` (`ryu/ryu_parse.h:29-34`),
//!     which C requires to be an implementation-defined integer type of its own
//!     size;
//!   * the `struct floating_decimal_128` layout of
//!     `ryu/ryu_generic_128.h:41-45` - `__uint128_t`, then `int32_t`, then
//!     `bool`, with the padding the target's alignment rules put around them -
//!     if and only if `-Dgeneric128` is on. The facade names that layout
//!     through the translated header's own type, never a restatement of it, so
//!     the requirement is that the two agree and nothing is checked about it
//!     here;
//!   * a working `long double` of the width `long_double_to_fd128` reads with
//!     `memcpy` (`ryu/generic_128.c:70-81`): upstream's own header says this
//!     "likely only works on x86 with specific compilers" and that is upstream's
//!     caveat, carried here unchanged;
//!   * **the platform C library's `malloc`/`free` pair**, which is the one that
//!     matters most and is checked below. Four of the entry points allocate
//!     with `malloc` and hand back a `char*` the caller must `free`
//!     (`ryu/d2s.c:506`, `ryu/f2s.c:342`, `ryu/d2fixed.c:558`,
//!     `ryu/d2fixed.c:815`).
//!
//! ## The allocator boundary, and why it is checked rather than asserted
//!
//! The typed owned-string surface (`format64ShortestOwned` and its three
//! siblings in `zig/root.zig`) returns what those four entry points allocated,
//! because a `char*` an API cannot size and an allocator it does not own is not
//! a usable answer. Releasing it has to use the allocator that produced it, and
//! that allocator is the C library's - `malloc` and `free` are the same two
//! functions for a shared object and for the process that opened it, because the
//! dynamic linker resolves both to one libc. So the boundary is a real, nameable
//! fact about this SDK: **free the returned string with the C library's `free`,
//! not with a Zig allocator.** There is no compatible-allocator question to
//! answer, and `OwnedString.deinit` is that `free`.
//!
//! `validate` below establishes it rather than claiming it: it takes the pointer
//! `d2s` returns and releases it with this process's `free`. A provider that
//! statically linked a different allocator faults there instead of handing
//! callers memory they cannot release later. That is the intended failure - it
//! is at load, it names the library, and the alternative is a corrupt free in
//! an unrelated call site much later. It is also the only check here that is
//! not a fact about symbols.
//!
//! ## What is deliberately not checked
//!
//! That the provider is Ryu at all, beyond the single conversion below. There is
//! no version function in either public header - upstream ships none, so
//! there is nothing to ask - and resolving sixteen names does not prove the
//! sixteenth means what this header says. One known answer does: `1.25` is
//! `1.25E0` in upstream's own `D2sTest.Basic` and in the shortest writer's
//! fixed spelling (`ryu/d2s.c:400-417`), so a provider that answers it has the
//! scalar convention, the caller-buffer convention and the output spelling this
//! build was translated against.

const rt = @import("rt");
const std = @import("std");

/// The synchronization this loader calls, bound by exact name.
///
/// The names below are `runtime/sync.h` compiled with `RT_SYNC_PREFIX=ryu_rt`,
/// which is what `runtime/graph.zig` passes. Two spellings of that prefix have
/// to agree: this file names the symbols, and graph.zig defines the macro. A
/// build where they disagree does not link, and that is the whole error report:
/// there is no runtime path that could hide it.
///
/// The core in `runtime/loader.zig` never names a symbol of its own, which is
/// what lets two SDKs, or two configurations of one SDK, hold their own loader
/// state in one process without sharing any of it.
pub const Sync = struct {
    extern fn ryu_rt_lock() void;
    extern fn ryu_rt_unlock() void;
    extern fn ryu_rt_wait() void;
    extern fn ryu_rt_broadcast() void;
    // `unsigned long long`. Declared as u64, which is the same type in every
    // ABI this SDK targets: 64-bit on x86_64, aarch64, riscv64 and wasm32.
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

/// libc's `free`.
///
/// `ryu/ryu_parse.h` and `ryu/ryu.h` declare no allocator function, so nothing
/// in the translated header names this. It is declared here because the one
/// check below releases memory the provider allocated, and that release has to
/// go through the same allocator to mean anything. It is a direct call in both
/// the loader and the facade, and it must stay one: this is the C library the
/// process already links, not a symbol to resolve through the provider.
extern fn free(ptr: ?*anyopaque) void;

/// The loader's configuration for this SDK, given the dispatch that owns the
/// table.
///
/// `dispatch` is the generated module, passed as a type by the dispatch itself
/// so that this file never has to import it. The direction is one-way on
/// purpose: the descriptor knows what the loader needs, the dispatch knows what
/// the header said, and neither imports the other.
pub fn Config(comptime dispatch: type) type {
    return struct {
        /// Named in the pre-load panic, so the message says which library was
        /// reached for before it was loaded.
        pub const library_name = "ryu";

        /// The table the generated dispatch declares, and the symbols it needs
        /// to fill it. Both come from the translated header, not from this file.
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

        /// The one library-specific check, run after every symbol resolved and
        /// before anything is published.
        ///
        /// Three facts, in the order they can fail, each of which is something
        /// a consumer of this SDK depends on:
        ///
        ///   1. the shortest binary64 writer writes into a caller-owned buffer
        ///      and returns its length in the platform `int`;
        ///   2. its output is the answer upstream publishes for that value,
        ///      which fixes the scalar convention and the spelling;
        ///   3. the `malloc`-ing entry point's string is releasable with this
        ///      process's `free`, which is the allocator boundary the typed
        ///      owned-string surface rests on.
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
            // translate-c types `char*` as `[*:c]u8`, so a null return arrives as
            // a null address rather than as an optional pointer. Upstream never
            // checks its own `malloc` (`ryu/d2s.c:506`), so this is the only
            // place the answer can be refused.
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