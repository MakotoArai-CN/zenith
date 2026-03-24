const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");
const runner = @import("runner.zig");
const output = @import("output.zig");
const terminal = @import("terminal.zig");
const sysinfo = @import("sysinfo.zig");
const netinfo = @import("netinfo.zig");
const bench_cpu = @import("bench/cpu.zig");
const bench_mem = @import("bench/memory.zig");
const bench_disk = @import("bench/disk.zig");

const build_options = @import("build_options");
pub const version = build_options.version;

pub fn main() !void {
    var gpa_state: std.heap.DebugAllocator(.{}) = .init;
    const gpa, const is_debug = gpa: {
        break :gpa switch (builtin.mode) {
            .Debug, .ReleaseSafe => .{ gpa_state.allocator(), true },
            .ReleaseFast, .ReleaseSmall => .{ std.heap.smp_allocator, false },
        };
    };
    defer if (is_debug) {
        _ = gpa_state.deinit();
    };

    const config = cli.parseArgs(gpa) catch |err| {
        if (err == error.HelpRequested or err == error.VersionRequested) {
            return;
        }
        return err;
    };

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const stdout = &stdout_writer.interface;

    const caps = terminal.TermCaps.detect();

    runner.run(gpa, stdout, config, caps) catch |err| {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
        const stderr = &stderr_writer.interface;
        try stderr.print("Error: {s}\n", .{@errorName(err)});
        try stderr.flush();
        return err;
    };

    try stdout.flush();
}

test "main module compiles" {
    _ = cli;
    _ = runner;
    _ = output;
    _ = terminal;
    _ = @import("sampler.zig");
    _ = sysinfo;
    _ = netinfo;
    _ = bench_cpu;
    _ = bench_mem;
    _ = bench_disk;
}