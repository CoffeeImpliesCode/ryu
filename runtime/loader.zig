// SPDX-License-Identifier: Apache-2.0
//
//! Loads a native provider and publishes its symbols to routed calls.
//! Failed attempts publish nothing; successful providers remain loaded for the process.

const std = @import("std");
const builtin = @import("builtin");

/// Select an absolute path or system-loader name; invalid forms return `InvalidSource`.
/// Requests do not fall back from one form to the other.
pub const LoadSource = union(enum) {
    /// Absolute shared-library path; relative paths are invalid.
    path: []const u8,
    /// Basename for platform search; separators and NUL bytes are invalid.
    system: []const u8,
};

/// Errors returned by `load`.
pub const LoadError = error{
    /// Empty path or name, rejected before platform lookup.
    EmptySource,
    /// Request exceeds `max_source_len`; the loader never truncates it.
    SourceTooLong,
    /// Relative path, system name with a path component, or embedded NUL.
    InvalidSource,
    /// Target has no dynamic library loader.
    UnsupportedTarget,
    /// Platform refused the request or could not load its dependencies.
    OpenFailed,
    /// Provider lacks a required translated symbol; the candidate is closed.
    MissingSymbol,
    /// SDK-specific provider validation failed; the candidate is closed.
    ValidationFailed,
    /// A different provider already succeeded or is loading.
    ProviderMismatch,
    /// The thread already inside a load attempt called `load` recursively.
    ReentrantLoad,
};

/// The longest request the loader will remember, in bytes.
pub const max_source_len = 32768;

/// Fixed request buffer retained for the process lifetime.
const SourceRecord = struct {
    tag: enum(u8) { none = 0, path, system } = .none,
    len: u32 = 0,
    bytes: [max_source_len]u8 = undefined,

    /// Store a request under the loader lock.
    fn set(self: *SourceRecord, request: LoadSource) void {
        const text = switch (request) {
            .path => |p| p,
            .system => |s| s,
        };
        @memcpy(self.bytes[0..text.len], text);
        self.len = @intCast(text.len);
        self.tag = switch (request) {
            .path => .path,
            .system => .system,
        };
    }

    /// Reconstruct the remembered request; returned bytes borrow this record.
    pub fn source(self: *const SourceRecord) ?LoadSource {
        const text = self.bytes[0..self.len];
        return switch (self.tag) {
            .none => null,
            .path => .{ .path = text },
            .system => .{ .system = text },
        };
    }
};

/// Compare request kind and bytes without path normalization.
pub fn eqlSource(a: LoadSource, b: LoadSource) bool {
    return switch (a) {
        .path => |pa| switch (b) {
            .path => |pb| std.mem.eql(u8, pa, pb),
            .system => false,
        },
        .system => |sa| switch (b) {
            .system => |sb| std.mem.eql(u8, sa, sb),
            .path => false,
        },
    };
}

fn validateSource(source: LoadSource) LoadError!void {
    const text = switch (source) {
        .path => |p| p,
        .system => |s| s,
    };
    if (text.len == 0) return error.EmptySource;
    if (text.len > max_source_len) return error.SourceTooLong;
    if (std.mem.indexOfScalar(u8, text, 0) != null) return error.InvalidSource;
    switch (source) {
        .path => {
            const absolute = if (builtin.os.tag == .windows)
                switch (std.fs.path.getWin32PathType(u8, text)) {
                    .drive_absolute, .unc_absolute, .local_device, .root_local_device => true,
                    .relative, .rooted, .drive_relative => false,
                }
            else
                std.fs.path.isAbsolutePosix(text);
            if (!absolute) return error.InvalidSource;
        },
        .system => {
            for (text) |byte| {
                if (std.fs.path.isSep(byte)) return error.InvalidSource;
                if (builtin.os.tag == .windows and byte == ':') return error.InvalidSource;
            }
        },
    }
}

/// State of a configured dispatch table.
pub const Phase = enum(u8) {
    /// No successful load; a failed attempt leaves this retryable state.
    not_loaded = 0,
    /// A thread is filling the table.
    loading = 1,
    /// The table is published and routed calls may use it.
    ready = 2,
};

/// Readiness flag for routed table access.
/// Publish with release ordering and read with acquire ordering.
pub const Ready = struct {
    phase: std.atomic.Value(u8) = .init(@backingInt(Phase.not_loaded)),

    /// Acquire-check whether a load completed.
    pub fn isReady(self: *const Ready) bool {
        return self.phase.load(.acquire) == @backingInt(Phase.ready);
    }

    /// Read the current phase.
    pub fn state(self: *const Ready) Phase {
        return @fromBackingInt(@intCast(self.phase.load(.acquire)));
    }

    /// Publish a phase with release ordering.
    pub fn set(self: *Ready, value: Phase) void {
        self.phase.store(@backingInt(value), .release);
    }
};

/// Required provider export kind, determining the type stored in the table.
pub const SymbolKind = enum {
    /// Function pointer with the translated header's exact type.
    function,
    /// Provider-owned object address; never copy the data.
    data,
};

/// Required export name and kind.
pub const Symbol = struct {
    /// Name as declared in the translated header.
    name: [:0]const u8,
    /// Kind of value stored in the table.
    kind: SymbolKind,
};

/// Panic by library and symbol if called before a successful load, in every mode.
pub fn panicNotReady(library: []const u8, comptime symbol: []const u8) noreturn {
    std.debug.panic(
        "{s}: {s} was called before this module was loaded; call " ++
            "load({{ .path = \"...\" }}) or load({{ .system = \"...\" }}) first",
        .{ library, symbol },
    );
}

/// Whether the target has a supported dynamic library loader.
pub const supported_target: bool = switch (builtin.os.tag) {
    .wasi, .emscripten, .freestanding => false,
    else => true,
};

/// Loader for one configured table; `Config` supplies symbols, assignment, sync and validation.
/// Retains successful providers; duplicate loads are idempotent, failures can be retried.
pub fn Loader(comptime Config: type) type {
    return struct {
        const LoaderType = @This();

        /// The table type this loader fills, for the configuration's own use.
        pub const table_type = Config.table;

        /// In-flight attempt or waiter-drain record, if any.
        attempt: ?Attempt = null,

        /// Request copy; accessed under lock before publication.
        request: SourceRecord = .{},

        /// Thread-safe load; same-request calls share an attempt, and failures can be retried.
        /// Conflicting providers return `ProviderMismatch`; recursive calls return `ReentrantLoad`.
        pub fn load(self: *LoaderType, source: LoadSource) LoadError!void {
            try validateSource(source);
            // After publication, same-request calls avoid the lock.
            if (Config.ready().isReady()) return self.accept(source);

            Config.sync.lock();
            while (true) {
                switch (Config.ready().state()) {
                    .ready => {
                        Config.sync.unlock();
                        return self.accept(source);
                    },
                    .loading => {
                        const attempt = &self.attempt.?;
                        if (attempt.owner == Config.sync.threadSelf()) {
                            Config.sync.unlock();
                            return error.ReentrantLoad;
                        }
                        if (!eqlSource(self.request.source().?, source)) {
                            Config.sync.unlock();
                            return error.ProviderMismatch;
                        }
                        // Join the active attempt and return its result.
                        attempt.waiters += 1;
                        while (Config.ready().state() == .loading) Config.sync.wait();
                        const result = attempt.result;
                        attempt.waiters -= 1;
                        // Keep the record until every waiter takes its result.
                        Config.sync.broadcast();
                        Config.sync.unlock();
                        return result;
                    },
                    .not_loaded => {
                        // Wait for the previous attempt's waiters to drain.
                        if (self.attempt != null) {
                            Config.sync.wait();
                            continue;
                        }
                        break;
                    },
                }
            }

            self.request.set(source);
            self.attempt = .{ .owner = Config.sync.threadSelf() };
            Config.ready().set(.loading);
            Config.sync.unlock();

            // Open outside the lock; constructors must not wait on a thread calling `load`.
            const outcome = runAttempt(self.request.source().?);
            const succeeded = if (outcome) |_| true else |_| false;

            Config.sync.lock();
            self.attempt.?.result = outcome;
            Config.ready().set(if (succeeded) .ready else .not_loaded);
            // Publish this attempt's result to its attached waiters.
            Config.sync.broadcast();
            // Keep the record until every waiter has consumed the result.
            while (self.attempt.?.waiters > 0) Config.sync.wait();
            self.attempt = null;
            // Wake callers waiting to start a retry.
            Config.sync.broadcast();
            Config.sync.unlock();

            return outcome;
        }

        /// Return the successful request or null before a successful load.
        /// The retained request is valid for the process lifetime.
        pub fn loadedSource(self: *const LoaderType) ?LoadSource {
            if (!Config.ready().isReady()) return null;
            return self.request.source();
        }

        fn accept(self: *const LoaderType, source: LoadSource) LoadError!void {
            // `load` checks readiness with acquire ordering before calling this.
            const published = self.request.source() orelse unreachable;
            if (eqlSource(published, source)) return;
            return error.ProviderMismatch;
        }

        /// Open, resolve and validate without the lock; close candidates on failure.
        fn runAttempt(source: LoadSource) LoadError!void {
            const handle = platform.open(source) catch |err| return err;

            var retain = false;
            defer if (!retain) platform.close(handle);

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |_, index| {
                    Config.assignMissing(index, Config.tablePtr());
                }
            }

            inline for (Config.symbols, 0..) |symbol, index| {
                const address = platform.lookup(handle, symbol.name) orelse
                    return error.MissingSymbol;
                Config.assign(index, Config.tablePtr(), address);
            }

            if (@hasDecl(Config, "optional_symbols")) {
                inline for (Config.optional_symbols, 0..) |symbol, index| {
                    if (platform.lookup(handle, symbol.name)) |address| {
                        Config.assignOptional(index, Config.tablePtr(), address);
                    }
                }
            }

            if (@hasDecl(Config, "validate")) {
                if (Config.validate(Config.tablePtr())) |refusal| {
                    std.debug.print("{s}: refusing this provider: {s}\n", .{
                        Config.library_name,
                        refusal,
                    });
                    return error.ValidationFailed;
                }
            }

            // Keep the handle alive because table pointers refer to it.
            retain = true;
        }
    };
}

/// One load attempt and its attached waiters.
const Attempt = struct {
    /// Identity of the thread running the attempt, for the reentrancy check.
    owner: u64,
    /// Result written before the table leaves `loading`.
    result: LoadError!void = error.OpenFailed,
    /// Attached waiters; retain the record until all have consumed the result.
    waiters: usize = 0,
};

/// Maximum accepted Windows path length in UTF-16 code units.
const windows_path_units = 32768;

const platform = if (builtin.os.tag == .windows)
    Windows
else if (supported_target)
    Unix
else
    NoLoader;

const NoLoader = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        _ = source;
        return error.UnsupportedTarget;
    }
    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        _ = handle;
        _ = name;
        return null;
    }
    fn close(handle: *anyopaque) void {
        _ = handle;
    }
};

const Unix = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget };

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        var buffer: [max_source_len + 1]u8 = undefined;
        @memcpy(buffer[0..text.len], text);
        buffer[text.len] = 0;
        // `RTLD_NOW` reports missing dependencies at load; `RTLD_LOCAL` avoids global symbol leakage.
        return std.c.dlopen(
            // `dlopen` requires a sentinel-terminated path.
            buffer[0..text.len :0].ptr,
            .{ .NOW = true, .GLOBAL = false },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return std.c.dlsym(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = std.c.dlclose(handle);
    }
};

const kernel32 = struct {
    extern "kernel32" fn LoadLibraryExW(
        file_name: [*:0]const u16,
        file: ?*anyopaque,
        flags: u32,
    ) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn GetProcAddress(module: *anyopaque, name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
    extern "kernel32" fn FreeLibrary(module: *anyopaque) callconv(.winapi) i32;
};

const Windows = struct {
    const OpenError = error{ OpenFailed, UnsupportedTarget, SourceTooLong };

    /// Search standard DLL directories and, for paths, the named directory.
    const load_library_search_default_dirs: u32 = 0x0000_1000;
    const load_library_search_dll_load_dir: u32 = 0x0000_0100;

    fn open(source: LoadSource) OpenError!*anyopaque {
        const text = switch (source) {
            .path => |p| p,
            .system => |s| s,
        };
        if (text.len > windows_path_units) return error.SourceTooLong;
        var buffer: [windows_path_units + 1]u16 = undefined;
        const units = std.unicode.utf8ToUtf16Le(buffer[0..text.len], text) catch
            return error.OpenFailed;
        buffer[units] = 0;
        return kernel32.LoadLibraryExW(
            buffer[0..units :0],
            null,
            load_library_search_default_dirs | switch (source) {
                .path => load_library_search_dll_load_dir,
                .system => @as(u32, 0),
            },
        ) orelse error.OpenFailed;
    }

    fn lookup(handle: *anyopaque, name: [:0]const u8) ?*const anyopaque {
        return kernel32.GetProcAddress(handle, name.ptr);
    }

    fn close(handle: *anyopaque) void {
        _ = kernel32.FreeLibrary(handle);
    }
};
