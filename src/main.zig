const std = @import("std");
const builtin = @import("builtin");
const cli = @import("cli.zig");
const runner = @import("runner.zig");
const output = @import("output.zig");
const terminal = @import("terminal.zig");
const sysinfo = @import("sysinfo.zig");
const netinfo = @import("netinfo.zig");
const compat = @import("compat.zig");
const bench_cpu = @import("bench/cpu.zig");
const bench_mem = @import("bench/memory.zig");
const bench_disk = @import("bench/disk.zig");

const build_options = @import("build_options");
pub const version = build_options.version;

// On Zig 0.16, args reach the program via `process.Init.Minimal` passed
// to main. On 0.15 there is no such type, so main takes no parameters
// and parseArgs uses std.process.argsAlloc internally.
pub const main = if (compat.is_zig_016) mainV016 else mainV015;

fn mainV015() !void {
    return runMain({});
}

fn mainV016(init: std.process.Init.Minimal) !void {
    return runMain(init.args);
}

fn runMain(args_source: compat.ArgsSource) !void {
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

    const config = cli.parseArgs(gpa, args_source) catch |err| {
        if (err == error.HelpRequested or err == error.VersionRequested) {
            return;
        }
        return err;
    };

    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = compat.fileWriter(compat.stdoutFile(), &stdout_buffer);
    const stdout = &stdout_writer.interface;

    const caps = terminal.TermCaps.detect();

    runner.run(gpa, stdout, config, caps) catch |err| {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = compat.fileWriter(compat.stderrFile(), &stderr_buffer);
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
