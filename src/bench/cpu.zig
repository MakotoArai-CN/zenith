const std = @import("std");
const cli = @import("../cli.zig");
const output = @import("../output.zig");
const timer_mod = @import("../timer.zig");
const sampler_mod = @import("../sampler.zig");

pub const CpuResult = struct {
    prime_single_score: f64 = 0,
    prime_multi_score: f64 = 0,
    matrix_single_score: f64 = 0,
    matrix_multi_score: f64 = 0,
    total_score: f64 = 0,
    thread_count: u32 = 0,
    prime_single_ops: f64 = 0,
    prime_multi_ops: f64 = 0,
    matrix_single_ops: f64 = 0,
    matrix_multi_ops: f64 = 0,
};

const PRIME_LIMIT: u64 = 100_000;
const MATRIX_SIZE: usize = 128;
const PRIME_BASE_SCORE: f64 = 1.0;
const MATRIX_BASE_SCORE: f64 = 100.0;

pub fn run(allocator: std.mem.Allocator, config: cli.Config, progress: *output.Progress) !CpuResult {
    var result: CpuResult = .{};
    const thread_count: u32 = if (config.cpu_threads == 0)
        @intCast(std.Thread.getCpuCount() catch 1)
    else
        config.cpu_threads;
    result.thread_count = thread_count;

    const run_prime = config.cpu_method == .prime or config.cpu_method == .all;
    const run_matrix = config.cpu_method == .matrix or config.cpu_method == .all;

    if (run_prime) {
        progress.next(output.tr(config.language, "CPU 质数单核", "CPU Prime Single", "CPU 素数シングル"));
        result.prime_single_ops = benchPrimeSingle(config.duration_secs);
        result.prime_single_score = result.prime_single_ops * PRIME_BASE_SCORE;

        progress.next(output.tr(config.language, "CPU 质数多核", "CPU Prime Multi", "CPU 素数マルチ"));
        result.prime_multi_ops = try benchPrimeMulti(allocator, config.duration_secs, thread_count);
        result.prime_multi_score = result.prime_multi_ops * PRIME_BASE_SCORE;
    }

    if (run_matrix) {
        progress.next(output.tr(config.language, "CPU 矩阵单核", "CPU Matrix Single", "CPU 行列シングル"));
        result.matrix_single_ops = benchMatrixSingle(allocator, config.duration_secs) catch 0;
        result.matrix_single_score = result.matrix_single_ops * MATRIX_BASE_SCORE;

        progress.next(output.tr(config.language, "CPU 矩阵多核", "CPU Matrix Multi", "CPU 行列マルチ"));
        result.matrix_multi_ops = benchMatrixMulti(allocator, config.duration_secs, thread_count) catch 0;
        result.matrix_multi_score = result.matrix_multi_ops * MATRIX_BASE_SCORE;
    }

    result.total_score = result.prime_single_score + result.prime_multi_score +
        result.matrix_single_score + result.matrix_multi_score;

    return result;
}

noinline fn countPrimes(limit: u64) u64 {
    if (limit < 2) return 0;
    var count: u64 = 0;
    var n: u64 = 2;
    while (n <= limit) : (n += 1) {
        if (isPrime(n)) {
            count += 1;
        }
    }
    return count;
}

fn isPrime(n: u64) bool {
    if (n < 2) return false;
    if (n < 4) return true;
    if (n % 2 == 0 or n % 3 == 0) return false;
    var i: u64 = 5;
    while (i * i <= n) {
        if (n % i == 0 or n % (i + 2) == 0) return false;
        i += 6;
    }
    return true;
}

fn benchPrimeSingle(duration_secs: f64) f64 {
    var limit: u64 = PRIME_LIMIT;

    // Warmup
    const warmup = countPrimes(@as(*volatile u64, @ptrCast(&limit)).*);
    std.mem.doNotOptimizeAway(warmup);

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();

    while (global.elapsed() < duration_secs) {
        const t = timer_mod.Timer.start();
        // Volatile read prevents the optimizer from constant-folding countPrimes
        const count = countPrimes(@as(*volatile u64, @ptrCast(&limit)).*);
        std.mem.doNotOptimizeAway(count);
        const elapsed = t.elapsed();
        if (elapsed > 0) {
            s.add(1.0 / elapsed);
        }
    }
    return s.median();
}

fn primeWorker(ctx: *PrimeWorkerCtx) void {
    const count = countPrimes(ctx.limit);
    std.mem.doNotOptimizeAway(count);
    ctx.done = true;
}

const PrimeWorkerCtx = struct {
    limit: u64,
    done: bool = false,
};

fn benchPrimeMulti(allocator: std.mem.Allocator, duration_secs: f64, thread_count: u32) !f64 {
    // Warmup: one round
    {
        var contexts: std.ArrayListUnmanaged(PrimeWorkerCtx) = .empty;
        defer contexts.deinit(allocator);
        try contexts.ensureTotalCapacity(allocator, thread_count);

        var threads: std.ArrayListUnmanaged(std.Thread) = .empty;
        defer threads.deinit(allocator);
        try threads.ensureTotalCapacity(allocator, thread_count);

        var i: u32 = 0;
        while (i < thread_count) : (i += 1) {
            contexts.appendAssumeCapacity(.{ .limit = PRIME_LIMIT });
            const ctx = &contexts.items[contexts.items.len - 1];
            const thread = std.Thread.spawn(.{}, primeWorker, .{ctx}) catch continue;
            threads.appendAssumeCapacity(thread);
        }
        for (threads.items) |thread| {
            thread.join();
        }
    }

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();

    while (global.elapsed() < duration_secs) {
        var contexts: std.ArrayListUnmanaged(PrimeWorkerCtx) = .empty;
        defer contexts.deinit(allocator);
        try contexts.ensureTotalCapacity(allocator, thread_count);

        var threads: std.ArrayListUnmanaged(std.Thread) = .empty;
        defer threads.deinit(allocator);
        try threads.ensureTotalCapacity(allocator, thread_count);

        const t = timer_mod.Timer.start();

        var i: u32 = 0;
        while (i < thread_count) : (i += 1) {
            contexts.appendAssumeCapacity(.{ .limit = PRIME_LIMIT });
            const ctx = &contexts.items[contexts.items.len - 1];
            const thread = std.Thread.spawn(.{}, primeWorker, .{ctx}) catch continue;
            threads.appendAssumeCapacity(thread);
        }

        for (threads.items) |thread| {
            thread.join();
        }

        const elapsed = t.elapsed();
        if (elapsed > 0) {
            const ops = @as(f64, @floatFromInt(threads.items.len)) / elapsed;
            s.add(ops);
        }
    }
    return s.median();
}

fn matrixMultiply(allocator: std.mem.Allocator, size: usize) !f64 {
    const a = try allocator.alloc(f64, size * size);
    defer allocator.free(a);
    const b = try allocator.alloc(f64, size * size);
    defer allocator.free(b);
    const c = try allocator.alloc(f64, size * size);
    defer allocator.free(c);

    var prng = std.Random.DefaultPrng.init(42);
    const random = prng.random();

    for (0..size * size) |idx| {
        a[idx] = random.float(f64) * 2.0 - 1.0;
        b[idx] = random.float(f64) * 2.0 - 1.0;
        c[idx] = 0;
    }

    const t = timer_mod.Timer.start();

    for (0..size) |i| {
        for (0..size) |k| {
            const a_ik = a[i * size + k];
            for (0..size) |j| {
                c[i * size + j] += a_ik * b[k * size + j];
            }
        }
    }
    std.mem.doNotOptimizeAway(c.ptr);

    const elapsed = t.elapsed();
    const flops = 2.0 * @as(f64, @floatFromInt(size)) *
        @as(f64, @floatFromInt(size)) * @as(f64, @floatFromInt(size));
    if (elapsed > 0) {
        return flops / elapsed / 1_000_000_000.0;
    }
    return 0;
}

fn benchMatrixSingle(allocator: std.mem.Allocator, duration_secs: f64) !f64 {
    // Warmup
    _ = try matrixMultiply(allocator, MATRIX_SIZE);

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();

    while (global.elapsed() < duration_secs) {
        const gflops = try matrixMultiply(allocator, MATRIX_SIZE);
        if (gflops > 0) s.add(gflops);
    }
    return s.median();
}

const MatrixWorkerCtx = struct {
    allocator: std.mem.Allocator,
    size: usize,
    result: f64 = 0,
};

fn matrixWorker(ctx: *MatrixWorkerCtx) void {
    ctx.result = matrixMultiply(ctx.allocator, ctx.size) catch 0;
}

fn benchMatrixMulti(allocator: std.mem.Allocator, duration_secs: f64, thread_count: u32) !f64 {
    // Warmup
    {
        var contexts: std.ArrayListUnmanaged(MatrixWorkerCtx) = .empty;
        defer contexts.deinit(allocator);
        try contexts.ensureTotalCapacity(allocator, thread_count);

        var threads: std.ArrayListUnmanaged(std.Thread) = .empty;
        defer threads.deinit(allocator);
        try threads.ensureTotalCapacity(allocator, thread_count);

        var i: u32 = 0;
        while (i < thread_count) : (i += 1) {
            contexts.appendAssumeCapacity(.{ .allocator = allocator, .size = MATRIX_SIZE });
            const ctx = &contexts.items[contexts.items.len - 1];
            const thread = std.Thread.spawn(.{}, matrixWorker, .{ctx}) catch continue;
            threads.appendAssumeCapacity(thread);
        }
        for (threads.items) |thread| {
            thread.join();
        }
    }

    var s = sampler_mod.Sampler{};
    const global = timer_mod.Timer.start();

    while (global.elapsed() < duration_secs) {
        var contexts: std.ArrayListUnmanaged(MatrixWorkerCtx) = .empty;
        defer contexts.deinit(allocator);
        try contexts.ensureTotalCapacity(allocator, thread_count);

        var threads: std.ArrayListUnmanaged(std.Thread) = .empty;
        defer threads.deinit(allocator);
        try threads.ensureTotalCapacity(allocator, thread_count);

        var i: u32 = 0;
        while (i < thread_count) : (i += 1) {
            contexts.appendAssumeCapacity(.{
                .allocator = allocator,
                .size = MATRIX_SIZE,
            });
            const ctx = &contexts.items[contexts.items.len - 1];
            const thread = std.Thread.spawn(.{}, matrixWorker, .{ctx}) catch continue;
            threads.appendAssumeCapacity(thread);
        }

        for (threads.items) |thread| {
            thread.join();
        }

        var total_gflops: f64 = 0;
        for (contexts.items) |ctx| {
            total_gflops += ctx.result;
        }

        if (total_gflops > 0) s.add(total_gflops);
    }
    return s.median();
}

pub fn printResults(w: *std.Io.Writer, result: *const CpuResult, lang: cli.Language, caps: output.TermCaps) !void {
    try output.printSectionHeader(w, output.tr(lang, "CPU 测试", "CPU Benchmark", "CPUベンチマーク"), caps);

    var buf: [32]u8 = undefined;
    const thread_str = std.fmt.bufPrint(&buf, "{d}", .{result.thread_count}) catch "?";
    try output.printKeyValue(w, output.tr(lang, "测试线程数", "Thread Count", "スレッド数"), thread_str, caps);

    try output.printSeparator(w, caps);

    if (result.prime_single_score > 0) {
        try output.printScore(w, output.tr(lang, "质数单核得分", "Prime Single", "素数シングル"), result.prime_single_score, caps);
        try output.printScore(w, output.tr(lang, "质数多核得分", "Prime Multi", "素数マルチ"), result.prime_multi_score, caps);
    }
    if (result.matrix_single_score > 0) {
        var gflops_buf: [32]u8 = undefined;
        const single_str = std.fmt.bufPrint(&gflops_buf, "{d:.3} GFLOPS", .{result.matrix_single_ops}) catch "?";
        try output.printResult(w, output.tr(lang, "矩阵单核", "Matrix Single", "行列シングル"), single_str, "", caps);

        var gflops_buf2: [32]u8 = undefined;
        const multi_str = std.fmt.bufPrint(&gflops_buf2, "{d:.3} GFLOPS", .{result.matrix_multi_ops}) catch "?";
        try output.printResult(w, output.tr(lang, "矩阵多核", "Matrix Multi", "行列マルチ"), multi_str, "", caps);

        try output.printScore(w, output.tr(lang, "矩阵单核得分", "Matrix Single Score", "行列シングルスコア"), result.matrix_single_score, caps);
        try output.printScore(w, output.tr(lang, "矩阵多核得分", "Matrix Multi Score", "行列マルチスコア"), result.matrix_multi_score, caps);
    }

    try output.printSeparator(w, caps);
    try output.printScore(w, output.tr(lang, "CPU 总分", "CPU Total", "CPU合計"), result.total_score, caps);
}
