const std = @import("std");
const cli = @import("../cli.zig");
const output = @import("../output.zig");
const timer_mod = @import("../timer.zig");
const sampler_mod = @import("../sampler.zig");

pub const MemoryResult = struct {
    seq_read_speed: f64 = 0,
    seq_write_speed: f64 = 0,
    seq_copy_speed: f64 = 0,
    random_read_speed: f64 = 0,
    latency_ns: f64 = 0,
    total_score: f64 = 0,
};

const TEST_SIZE: usize = 64 * 1024 * 1024;
const LATENCY_ARRAY_SIZE: usize = 1024 * 1024;
const MEM_SCORE_BASE: f64 = 0.1;
const MEM_LATENCY_WEIGHT: f64 = 50.0;

pub fn run(allocator: std.mem.Allocator, config: cli.Config, progress: *output.Progress) !MemoryResult {
    var result: MemoryResult = .{};
    const duration = config.duration_secs;

    progress.next(output.tr(config.language, "内存顺序写入", "Mem Seq Write", "メモリ書込"));
    result.seq_write_speed = try benchSeqWrite(allocator, duration);

    progress.next(output.tr(config.language, "内存顺序读取", "Mem Seq Read", "メモリ読取"));
    result.seq_read_speed = try benchSeqRead(allocator, duration);

    progress.next(output.tr(config.language, "内存顺序拷贝", "Mem Seq Copy", "メモリコピー"));
    result.seq_copy_speed = try benchSeqCopy(allocator, duration);

    progress.next(output.tr(config.language, "内存随机读取", "Mem Random Read", "メモリランダム読取"));
    result.random_read_speed = try benchRandomRead(allocator, duration);

    progress.next(output.tr(config.language, "内存访问延迟", "Mem Latency", "メモリ遅延"));
    result.latency_ns = try benchLatency(allocator, duration);

    const avg_bandwidth = (result.seq_read_speed + result.seq_write_speed + result.seq_copy_speed) / 3.0;
    const bandwidth_score = avg_bandwidth / (1024.0 * 1024.0) * MEM_SCORE_BASE;
    const latency_score = if (result.latency_ns > 0) 1000.0 / result.latency_ns * MEM_LATENCY_WEIGHT else 0;
    result.total_score = bandwidth_score + latency_score;

    return result;
}

fn benchSeqWrite(allocator: std.mem.Allocator, duration_secs: f64) !f64 {
    const buf = try allocator.alloc(u8, TEST_SIZE);
    defer allocator.free(buf);

    // Warmup
    {
        const words: []volatile u64 = @as([*]volatile u64, @ptrCast(@alignCast(buf.ptr)))[0 .. TEST_SIZE / 8];
        for (0..words.len) |i| {
            words[i] = @as(u64, @intCast(i));
        }
    }

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();

    while (global.elapsed() < duration_secs) {
        const t = timer_mod.Timer.start();

        const words: []volatile u64 = @as([*]volatile u64, @ptrCast(@alignCast(buf.ptr)))[0 .. TEST_SIZE / 8];
        for (0..words.len) |i| {
            words[i] = @as(u64, @intCast(i));
        }

        const elapsed = t.elapsed();
        if (elapsed > 0) {
            s.add(@as(f64, @floatFromInt(TEST_SIZE)) / elapsed);
        }
    }
    return s.median();
}

fn benchSeqRead(allocator: std.mem.Allocator, duration_secs: f64) !f64 {
    const buf = try allocator.alloc(u8, TEST_SIZE);
    defer allocator.free(buf);
    @memset(buf, 0xAA);

    // Warmup
    {
        const words: []volatile const u64 = @as([*]volatile const u64, @ptrCast(@alignCast(buf.ptr)))[0 .. TEST_SIZE / 8];
        var sink: u64 = 0;
        for (0..words.len) |i| {
            sink +%= words[i];
        }
        std.mem.doNotOptimizeAway(sink);
    }

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();

    while (global.elapsed() < duration_secs) {
        const t = timer_mod.Timer.start();

        const words: []volatile const u64 = @as([*]volatile const u64, @ptrCast(@alignCast(buf.ptr)))[0 .. TEST_SIZE / 8];
        var sink: u64 = 0;
        for (0..words.len) |i| {
            sink +%= words[i];
        }
        std.mem.doNotOptimizeAway(sink);

        const elapsed = t.elapsed();
        if (elapsed > 0) {
            s.add(@as(f64, @floatFromInt(TEST_SIZE)) / elapsed);
        }
    }
    return s.median();
}

fn benchSeqCopy(allocator: std.mem.Allocator, duration_secs: f64) !f64 {
    const src = try allocator.alloc(u8, TEST_SIZE);
    defer allocator.free(src);
    const dst = try allocator.alloc(u8, TEST_SIZE);
    defer allocator.free(dst);
    @memset(src, 0xBB);

    // Warmup
    @memcpy(dst, src);
    std.mem.doNotOptimizeAway(dst.ptr);

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();

    while (global.elapsed() < duration_secs) {
        const t = timer_mod.Timer.start();
        @memcpy(dst, src);
        std.mem.doNotOptimizeAway(dst.ptr);
        const elapsed = t.elapsed();
        if (elapsed > 0) {
            s.add(@as(f64, @floatFromInt(TEST_SIZE)) / elapsed);
        }
    }
    return s.median();
}

fn benchRandomRead(allocator: std.mem.Allocator, duration_secs: f64) !f64 {
    const arr = try allocator.alloc(u64, LATENCY_ARRAY_SIZE);
    defer allocator.free(arr);

    var prng = std.Random.DefaultPrng.init(12345);
    const random = prng.random();

    for (0..LATENCY_ARRAY_SIZE) |i| {
        arr[i] = random.intRangeAtMost(u64, 0, LATENCY_ARRAY_SIZE - 1);
    }

    // Warmup
    {
        var idx: u64 = 0;
        for (0..LATENCY_ARRAY_SIZE) |_| {
            idx = arr[@intCast(idx % LATENCY_ARRAY_SIZE)];
        }
        std.mem.doNotOptimizeAway(idx);
    }

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();

    while (global.elapsed() < duration_secs) {
        const access_count: usize = LATENCY_ARRAY_SIZE;
        const t = timer_mod.Timer.start();

        var idx: u64 = 0;
        for (0..access_count) |_| {
            idx = arr[@intCast(idx % LATENCY_ARRAY_SIZE)];
        }
        std.mem.doNotOptimizeAway(idx);

        const elapsed = t.elapsed();
        if (elapsed > 0) {
            s.add(@as(f64, @floatFromInt(access_count * 8)) / elapsed);
        }
    }
    return s.median();
}

fn benchLatency(allocator: std.mem.Allocator, duration_secs: f64) !f64 {
    const arr = try allocator.alloc(usize, LATENCY_ARRAY_SIZE);
    defer allocator.free(arr);

    for (0..LATENCY_ARRAY_SIZE) |i| {
        arr[i] = (i + 127) % LATENCY_ARRAY_SIZE;
    }

    // Warmup
    {
        var idx: usize = 0;
        for (0..LATENCY_ARRAY_SIZE) |_| {
            idx = arr[idx];
        }
        std.mem.doNotOptimizeAway(idx);
    }

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();

    while (global.elapsed() < duration_secs) {
        const chase_count: usize = LATENCY_ARRAY_SIZE;
        const t = timer_mod.Timer.start();

        var idx: usize = 0;
        for (0..chase_count) |_| {
            idx = arr[idx];
        }
        std.mem.doNotOptimizeAway(idx);

        const elapsed_ns = t.elapsedNs();
        const latency = @as(f64, @floatFromInt(elapsed_ns)) / @as(f64, @floatFromInt(chase_count));
        if (latency > 0) s.add(latency);
    }

    return s.median();
}

pub fn printResults(w: *std.Io.Writer, result: *const MemoryResult, lang: cli.Language, caps: output.TermCaps) !void {
    try output.printSectionHeader(w, output.tr(lang, "内存测试", "Memory Benchmark", "メモリベンチマーク"), caps);

    var buf1: [64]u8 = undefined;
    var buf2: [64]u8 = undefined;
    var buf3: [64]u8 = undefined;
    var buf4: [64]u8 = undefined;

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
    try output.printResult(
        w,
        output.tr(lang, "顺序拷贝", "Sequential Copy", "シーケンシャルコピー"),
        output.formatSpeed(&buf3, result.seq_copy_speed),
        "",
        caps,
    );
    try output.printResult(
        w,
        output.tr(lang, "随机读取", "Random Read", "ランダム読取"),
        output.formatSpeed(&buf4, result.random_read_speed),
        "",
        caps,
    );

    var lat_buf: [32]u8 = undefined;
    const lat_str = std.fmt.bufPrint(&lat_buf, "{d:.2} ns", .{result.latency_ns}) catch "?";
    try output.printResult(w, output.tr(lang, "访问延迟", "Access Latency", "アクセス遅延"), lat_str, "", caps);

    try output.printSeparator(w, caps);
    try output.printScore(w, output.tr(lang, "内存总分", "Memory Total", "メモリ合計"), result.total_score, caps);
}
