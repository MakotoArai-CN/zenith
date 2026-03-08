const std = @import("std");
const builtin = @import("builtin");
const cli = @import("../cli.zig");
const output = @import("../output.zig");
const timer_mod = @import("../timer.zig");
const sampler_mod = @import("../sampler.zig");

pub const DiskResult = struct {
    seq_write_speed: f64 = 0,
    seq_read_speed: f64 = 0,
    rand_write_iops: f64 = 0,
    rand_read_iops: f64 = 0,
    total_score: f64 = 0,
};

const BLOCK_SIZE: usize = 1024 * 1024;
const RANDOM_BLOCK_SIZE: usize = 4096;
const RANDOM_OPS_COUNT: usize = 4096;
const DISK_SCORE_FACTOR: f64 = 0.5;
const IOPS_SCORE_FACTOR: f64 = 0.005;

pub fn run(allocator: std.mem.Allocator, config: cli.Config, progress: *output.Progress) !DiskResult {
    var result: DiskResult = .{};
    const size_bytes = @as(usize, config.disk_size_mb) * 1024 * 1024;
    const run_seq = config.disk_method == .sequential or config.disk_method == .all;
    const run_rand = config.disk_method == .random or config.disk_method == .all;

    // Resolve disk path: on Windows /tmp doesn't exist, fall back to a valid temp directory
    const disk_path = resolveDiskPath(config.disk_path);

    if (run_seq) {
        progress.next(output.tr(config.language, "磁盘顺序写入", "Disk Seq Write", "ディスク書込"));
        result.seq_write_speed = try benchSeqWrite(allocator, disk_path, size_bytes, config.duration_secs);

        progress.next(output.tr(config.language, "磁盘顺序读取", "Disk Seq Read", "ディスク読取"));
        result.seq_read_speed = try benchSeqRead(allocator, disk_path, size_bytes, config.duration_secs);
    }

    if (run_rand) {
        progress.next(output.tr(config.language, "磁盘随机写入", "Disk Rand Write", "ディスクランダム書込"));
        result.rand_write_iops = try benchRandWrite(allocator, disk_path, config.duration_secs);

        progress.next(output.tr(config.language, "磁盘随机读取", "Disk Rand Read", "ディスクランダム読取"));
        result.rand_read_iops = try benchRandRead(allocator, disk_path, size_bytes, config.duration_secs);
    }

    const seq_score = (result.seq_write_speed + result.seq_read_speed) / (1024.0 * 1024.0) * DISK_SCORE_FACTOR;
    const iops_score = (result.rand_write_iops + result.rand_read_iops) * IOPS_SCORE_FACTOR;
    result.total_score = seq_score + iops_score;

    return result;
}

fn resolveDiskPath(path: []const u8) []const u8 {
    // Verify the target directory exists and is accessible
    var dir = std.fs.cwd().openDir(path, .{}) catch {
        // Directory doesn't exist (e.g. /tmp on Windows), try platform temp dir
        if (comptime builtin.os.tag == .windows) {
            return resolveWindowsTemp();
        }
        return ".";
    };
    dir.close();
    return path;
}

fn resolveWindowsTemp() []const u8 {
    const State = struct {
        var buf: [512]u8 = undefined;
        var resolved: ?[]const u8 = null;
    };
    if (State.resolved) |p| return p;
    const k32 = struct {
        extern "kernel32" fn GetTempPathA(nBufferLength: u32, lpBuffer: [*]u8) callconv(.winapi) u32;
    };
    const len = k32.GetTempPathA(@intCast(State.buf.len), &State.buf);
    if (len > 0 and len < State.buf.len) {
        var end: usize = @intCast(len);
        // Remove trailing separators
        while (end > 0 and (State.buf[end - 1] == '\\' or State.buf[end - 1] == '/')) {
            end -= 1;
        }
        State.resolved = State.buf[0..end];
        return State.resolved.?;
    }
    State.resolved = ".";
    return ".";
}

fn getTestFilePath(buf: []u8, base_path: []const u8) []const u8 {
    const suffix = "/zenith_bench.tmp";
    const total = base_path.len + suffix.len;
    if (total > buf.len) return "zenith_bench.tmp";
    @memcpy(buf[0..base_path.len], base_path);
    @memcpy(buf[base_path.len..total], suffix);
    return buf[0..total];
}

fn benchSeqWrite(allocator: std.mem.Allocator, path: []const u8, size_bytes: usize, duration_secs: f64) !f64 {
    const block = try allocator.alloc(u8, BLOCK_SIZE);
    defer allocator.free(block);
    @memset(block, 0xCD);

    var path_buf: [512]u8 = undefined;
    const test_path = getTestFilePath(&path_buf, path);

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();

    while (global.elapsed() < duration_secs) {
        const file = std.fs.cwd().createFile(test_path, .{ .truncate = true }) catch return 0;
        defer file.close();
        defer std.fs.cwd().deleteFile(test_path) catch {};

        const t = timer_mod.Timer.start();
        var written: usize = 0;
        while (written < size_bytes) {
            const to_write = @min(BLOCK_SIZE, size_bytes - written);
            _ = file.write(block[0..to_write]) catch break;
            written += to_write;
        }

        if (builtin.os.tag == .linux) {
            _ = std.posix.system.fdatasync(file.handle);
        }

        const elapsed = t.elapsed();
        if (elapsed > 0) {
            s.add(@as(f64, @floatFromInt(written)) / elapsed);
        }
    }
    return s.median();
}

fn benchSeqRead(allocator: std.mem.Allocator, path: []const u8, size_bytes: usize, duration_secs: f64) !f64 {
    const write_block = try allocator.alloc(u8, BLOCK_SIZE);
    defer allocator.free(write_block);
    @memset(write_block, 0xAB);

    var path_buf: [512]u8 = undefined;
    const test_path = getTestFilePath(&path_buf, path);

    // Prepare test file
    {
        const wf = std.fs.cwd().createFile(test_path, .{ .truncate = true }) catch return 0;
        defer wf.close();
        var written: usize = 0;
        while (written < size_bytes) {
            const to_write = @min(BLOCK_SIZE, size_bytes - written);
            _ = wf.write(write_block[0..to_write]) catch break;
            written += to_write;
        }
    }
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const read_block = try allocator.alloc(u8, BLOCK_SIZE);
    defer allocator.free(read_block);

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();

    while (global.elapsed() < duration_secs) {
        const file = std.fs.cwd().openFile(test_path, .{}) catch return 0;
        defer file.close();

        const t = timer_mod.Timer.start();
        var total_read: usize = 0;
        while (true) {
            const bytes_read = file.read(read_block) catch break;
            if (bytes_read == 0) break;
            total_read += bytes_read;
        }
        std.mem.doNotOptimizeAway(read_block.ptr);

        const elapsed = t.elapsed();
        if (elapsed > 0) {
            s.add(@as(f64, @floatFromInt(total_read)) / elapsed);
        }
    }
    return s.median();
}

fn benchRandWrite(allocator: std.mem.Allocator, path: []const u8, duration_secs: f64) !f64 {
    const block = try allocator.alloc(u8, RANDOM_BLOCK_SIZE);
    defer allocator.free(block);
    @memset(block, 0xEF);

    var path_buf: [512]u8 = undefined;
    const test_path = getTestFilePath(&path_buf, path);

    const file_size: usize = RANDOM_BLOCK_SIZE * RANDOM_OPS_COUNT;

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();
    var round: u32 = 0;

    while (global.elapsed() < duration_secs) {
        const file = std.fs.cwd().createFile(test_path, .{ .truncate = true }) catch return 0;
        defer file.close();
        defer std.fs.cwd().deleteFile(test_path) catch {};

        const fill = allocator.alloc(u8, file_size) catch return 0;
        defer allocator.free(fill);
        @memset(fill, 0);
        _ = file.write(fill) catch return 0;

        var prng = std.Random.DefaultPrng.init(@intCast(round));
        const random = prng.random();

        const t = timer_mod.Timer.start();
        var ops: usize = 0;
        while (ops < RANDOM_OPS_COUNT) : (ops += 1) {
            const max_blocks = file_size / RANDOM_BLOCK_SIZE;
            const offset = random.intRangeAtMost(usize, 0, max_blocks - 1) * RANDOM_BLOCK_SIZE;
            file.seekTo(@intCast(offset)) catch break;
            _ = file.write(block) catch break;
        }

        if (builtin.os.tag == .linux) {
            _ = std.posix.system.fdatasync(file.handle);
        }

        const elapsed = t.elapsed();
        if (elapsed > 0) {
            s.add(@as(f64, @floatFromInt(ops)) / elapsed);
        }
        round += 1;
    }
    return s.median();
}

fn benchRandRead(allocator: std.mem.Allocator, path: []const u8, size_bytes: usize, duration_secs: f64) !f64 {
    const write_block = try allocator.alloc(u8, BLOCK_SIZE);
    defer allocator.free(write_block);
    @memset(write_block, 0xCC);

    var path_buf: [512]u8 = undefined;
    const test_path = getTestFilePath(&path_buf, path);

    // Prepare test file
    {
        const wf = std.fs.cwd().createFile(test_path, .{ .truncate = true }) catch return 0;
        defer wf.close();
        var written: usize = 0;
        while (written < size_bytes) {
            const to_write = @min(BLOCK_SIZE, size_bytes - written);
            _ = wf.write(write_block[0..to_write]) catch break;
            written += to_write;
        }
    }
    defer std.fs.cwd().deleteFile(test_path) catch {};

    const read_block = try allocator.alloc(u8, RANDOM_BLOCK_SIZE);
    defer allocator.free(read_block);

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();
    var round: u32 = 0;

    while (global.elapsed() < duration_secs) {
        const file = std.fs.cwd().openFile(test_path, .{}) catch return 0;
        defer file.close();

        var prng = std.Random.DefaultPrng.init(@intCast(round + 100));
        const random = prng.random();
        const max_blocks = size_bytes / RANDOM_BLOCK_SIZE;

        const t = timer_mod.Timer.start();
        var ops: usize = 0;
        while (ops < RANDOM_OPS_COUNT) : (ops += 1) {
            const offset = random.intRangeAtMost(usize, 0, max_blocks - 1) * RANDOM_BLOCK_SIZE;
            file.seekTo(@intCast(offset)) catch break;
            _ = file.read(read_block) catch break;
        }
        std.mem.doNotOptimizeAway(read_block.ptr);

        const elapsed = t.elapsed();
        if (elapsed > 0) {
            s.add(@as(f64, @floatFromInt(ops)) / elapsed);
        }
        round += 1;
    }
    return s.median();
}

pub fn printResults(w: *std.Io.Writer, result: *const DiskResult, lang: cli.Language, caps: output.TermCaps) !void {
    try output.printSectionHeader(w, output.tr(lang, "磁盘测试", "Disk Benchmark", "ディスクベンチマーク"), caps);

    if (result.seq_write_speed > 0 or result.seq_read_speed > 0) {
        var buf1: [64]u8 = undefined;
        var buf2: [64]u8 = undefined;
        try output.printResult(
            w,
            output.tr(lang, "顺序写入", "Sequential Write", "シーケンシャル書込"),
            output.formatSpeed(&buf1, result.seq_write_speed),
            "",
            caps,
        );
        try output.printResult(
            w,
            output.tr(lang, "顺序读取", "Sequential Read", "シーケンシャル読取"),
            output.formatSpeed(&buf2, result.seq_read_speed),
            "",
            caps,
        );
    }

    if (result.rand_write_iops > 0 or result.rand_read_iops > 0) {
        var iops_buf1: [32]u8 = undefined;
        var iops_buf2: [32]u8 = undefined;
        const w_str = std.fmt.bufPrint(&iops_buf1, "{d:.0} IOPS", .{result.rand_write_iops}) catch "?";
        const r_str = std.fmt.bufPrint(&iops_buf2, "{d:.0} IOPS", .{result.rand_read_iops}) catch "?";
        try output.printResult(w, output.tr(lang, "随机写入", "Random Write", "ランダム書込"), w_str, "", caps);
        try output.printResult(w, output.tr(lang, "随机读取", "Random Read", "ランダム読取"), r_str, "", caps);
    }

    try output.printSeparator(w, caps);
    try output.printScore(w, output.tr(lang, "磁盘总分", "Disk Total", "ディスク合計"), result.total_score, caps);
}
