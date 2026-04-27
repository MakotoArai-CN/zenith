//! Compatibility shim: bridges Zig 0.15.* and 0.16.* standard library
//! differences. Pre-0.16, file IO sat under `std.fs` and methods were
//! called directly on `File`. 0.16 moved all blocking IO to `std.Io.Dir`
//! and `std.Io.File`, with each operation taking an `Io` parameter.
//!
//! This module exposes a minimal unified surface that the rest of the
//! codebase can use without comptime branching at every call site.

const std = @import("std");
const builtin = @import("builtin");

pub const is_zig_016 = builtin.zig_version.major == 0 and builtin.zig_version.minor >= 16;

pub const File = if (is_zig_016) std.Io.File else std.fs.File;
pub const Dir = if (is_zig_016) std.Io.Dir else std.fs.Dir;

/// Get the global Io instance (0.16) or void (0.15).
pub inline fn io() if (is_zig_016) std.Io else void {
    if (is_zig_016) {
        return std.Io.Threaded.global_single_threaded.io();
    } else {
        return {};
    }
}

pub inline fn cwd() Dir {
    if (is_zig_016) return Dir.cwd();
    return std.fs.cwd();
}

pub inline fn stdoutFile() File {
    if (is_zig_016) return File.stdout();
    return std.fs.File.stdout();
}

pub inline fn stderrFile() File {
    if (is_zig_016) return File.stderr();
    return std.fs.File.stderr();
}

pub inline fn fileWriter(file: File, buffer: []u8) if (is_zig_016) File.Writer else std.fs.File.Writer {
    if (is_zig_016) return file.writer(io(), buffer);
    return file.writer(buffer);
}

pub inline fn fileClose(file: File) void {
    if (is_zig_016) {
        file.close(io());
    } else {
        file.close();
    }
}

pub inline fn fileRead(file: File, buf: []u8) !usize {
    if (is_zig_016) {
        // Use streaming read; read up to buf.len bytes, returns 0 at EOF.
        return file.readStreaming(io(), &.{buf});
    } else {
        return file.read(buf);
    }
}

pub inline fn fileWrite(file: File, bytes: []const u8) !usize {
    if (is_zig_016) {
        try file.writeStreamingAll(io(), bytes);
        return bytes.len;
    } else {
        return file.write(bytes);
    }
}

pub inline fn fileSeekTo(file: File, offset: u64) !void {
    if (is_zig_016) {
        // 0.16 doesn't expose direct File.seekTo; create a writer with no
        // buffer and use seekToUnbuffered.
        var w = file.writer(io(), &.{});
        try w.seekToUnbuffered(offset);
    } else {
        try file.seekTo(offset);
    }
}

pub const OpenReadFlags = struct {};

pub inline fn openFileAbs(path: []const u8) !File {
    if (is_zig_016) {
        return Dir.openFileAbsolute(io(), path, .{});
    } else {
        return std.fs.openFileAbsolute(path, .{});
    }
}

pub inline fn createFileCwd(path: []const u8, truncate: bool) !File {
    if (is_zig_016) {
        return cwd().createFile(io(), path, .{ .truncate = truncate });
    } else {
        return std.fs.cwd().createFile(path, .{ .truncate = truncate });
    }
}

pub inline fn openFileCwd(path: []const u8) !File {
    if (is_zig_016) {
        return cwd().openFile(io(), path, .{});
    } else {
        return std.fs.cwd().openFile(path, .{});
    }
}

pub inline fn deleteFileCwd(path: []const u8) !void {
    if (is_zig_016) {
        try cwd().deleteFile(io(), path);
    } else {
        try std.fs.cwd().deleteFile(path);
    }
}

pub inline fn openDirCwd(path: []const u8) !Dir {
    if (is_zig_016) {
        return cwd().openDir(io(), path, .{});
    } else {
        return std.fs.cwd().openDir(path, .{});
    }
}

pub inline fn dirClose(dir: *Dir) void {
    if (is_zig_016) {
        dir.close(io());
    } else {
        dir.close();
    }
}

pub inline fn cwdReadLink(path: []const u8, buf: []u8) ![]u8 {
    if (comptime is_zig_016) {
        const n = try cwd().readLink(io(), path, buf);
        return buf[0..n];
    } else {
        return std.fs.cwd().readLink(path, buf);
    }
}

/// Returns an owned slice of argv (excluding argv[0]). Caller must call freeArgs.
/// On Zig 0.16, requires the `Args` value from main's `process.Init.Minimal` param.
pub fn collectArgs(allocator: std.mem.Allocator, raw_args: anytype) ![]const []const u8 {
    if (comptime is_zig_016) {
        var list: std.ArrayList([]const u8) = .empty;
        errdefer {
            for (list.items) |s| allocator.free(s);
            list.deinit(allocator);
        }
        var it = try raw_args.iterateAllocator(allocator);
        defer it.deinit();
        _ = it.skip(); // skip argv[0]
        while (it.next()) |arg| {
            const copy = try allocator.dupe(u8, arg);
            errdefer allocator.free(copy);
            try list.append(allocator, copy);
        }
        return list.toOwnedSlice(allocator);
    } else {
        return collectArgs015(allocator);
    }
}

fn collectArgs015(allocator: std.mem.Allocator) ![]const []const u8 {
    const all = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, all);
    const out = try allocator.alloc([]const u8, if (all.len > 0) all.len - 1 else 0);
    errdefer allocator.free(out);
    for (out, 0..) |*dst, i| {
        dst.* = try allocator.dupe(u8, all[i + 1]);
    }
    return out;
}

pub fn freeArgs(allocator: std.mem.Allocator, args: []const []const u8) void {
    for (args) |s| allocator.free(s);
    allocator.free(args);
}

/// Type-erased "args source" passed to parseArgs. On 0.15 it's `void`; on 0.16
/// it's `std.process.Args`.
pub const ArgsSource = if (is_zig_016) std.process.Args else void;

pub inline fn defaultArgsSource() ArgsSource {
    if (is_zig_016) return std.process.Args{ .vector = &.{} };
    return {};
}

/// Returns whether stdout is connected to a terminal.
pub fn stdoutIsTty() bool {
    if (comptime is_zig_016) {
        return stdoutFile().isTty(io()) catch false;
    } else {
        return std.posix.isatty(std.posix.STDOUT_FILENO);
    }
}

/// Look up an environment variable. Works on POSIX via libc; returns null on Windows.
pub fn getenv(name: [*:0]const u8) ?[]const u8 {
    if (builtin.os.tag == .windows) return null;
    if (comptime is_zig_016) {
        const c = struct {
            extern "c" fn getenv(n: [*:0]const u8) ?[*:0]const u8;
        };
        const ptr = c.getenv(name) orelse return null;
        return std.mem.sliceTo(ptr, 0);
    } else {
        return std.posix.getenv(std.mem.sliceTo(name, 0));
    }
}

/// Convert a Windows BOOL return to a Zig bool. 0.15 used c_int, 0.16 uses an
/// enum; this hides the difference at call sites.
pub inline fn winBool(b: anytype) bool {
    const T = @TypeOf(b);
    if (@typeInfo(T) == .@"enum") return b.toBool();
    return b != 0;
}
