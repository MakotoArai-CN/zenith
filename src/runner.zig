const std = @import("std");
const cli = @import("cli.zig");
const output = @import("output.zig");
const compat = @import("compat.zig");
const sysinfo = @import("sysinfo.zig");
const netinfo = @import("netinfo.zig");
const bench_cpu = @import("bench/cpu.zig");
const bench_mem = @import("bench/memory.zig");
const bench_disk = @import("bench/disk.zig");
const timer_mod = @import("timer.zig");

// ==================== Adding New Benchmark Modules ====================
//
// To add a new benchmark module (e.g. database, network throughput):
//
// 1. Create src/bench/xxx.zig with:
//    - pub const XxxResult = struct { ..., total_score: f64 = 0 };
//    - pub fn run(allocator: Allocator, config: cli.Config, progress: *output.Progress) !XxxResult
//      Use config.duration_secs with timer + sampler for duration-based median
//    - pub fn printResults(w: *Io.Writer, result: *const XxxResult,
//                          lang: cli.Language, caps: output.TermCaps) !void
//
// 2. Import here:
//    const bench_xxx = @import("bench/xxx.zig");
//
// 3. Add a config flag in cli.zig:
//    run_xxx: bool = true,
//    Add --no-xxx flag to parseParamsComptime and parseArgs
//
// 4. Add a block below following the existing pattern:
//    if (config.run_xxx) {
//        const xxx_result = try bench_xxx.run(allocator, config);
//        try bench_xxx.printResults(w, &xxx_result, config.language, caps);
//        total_score += xxx_result.total_score;
//        score_count += 1;
//        try w.flush();
//    }
// ==================================================================

pub fn run(allocator: std.mem.Allocator, w: *std.Io.Writer, config: cli.Config, caps: output.TermCaps) !void {
    const global_timer = timer_mod.Timer.start();

    try output.printBanner(w, caps);
    try w.flush();

    if (config.run_sysinfo) {
        const info = sysinfo.collect();
        try sysinfo.printInfo(w, &info, config.language, caps);
        try w.flush();
    }

    if (config.run_network) {
        const net = netinfo.collect(allocator);
        try netinfo.printInfo(w, &net, config.language, caps);
        try w.flush();
    }

    var total_score: f64 = 0;
    var score_count: u32 = 0;

    // Count total benchmark steps for progress bar
    var total_steps: u32 = 0;
    if (config.run_cpu) {
        if (config.cpu_method == .prime or config.cpu_method == .all) total_steps += 2; // single + multi
        if (config.cpu_method == .matrix or config.cpu_method == .all) total_steps += 2; // single + multi
    }
    if (config.run_memory) total_steps += 5; // seq_write, seq_read, seq_copy, random_read, latency
    if (config.run_disk) {
        if (config.disk_method == .sequential or config.disk_method == .all) total_steps += 2; // seq_write, seq_read
        if (config.disk_method == .random or config.disk_method == .all) total_steps += 2; // rand_write, rand_read
    }

    var progress = output.Progress{ .w = w, .caps = caps, .total = total_steps };

    if (config.run_cpu) {
        const cpu_result = try bench_cpu.run(allocator, config, &progress);
        progress.clear();
        try bench_cpu.printResults(w, &cpu_result, config.language, caps);
        total_score += cpu_result.total_score;
        score_count += 1;
        try w.flush();
    }

    if (config.run_memory) {
        const mem_result = try bench_mem.run(allocator, config, &progress);
        progress.clear();
        try bench_mem.printResults(w, &mem_result, config.language, caps);
        total_score += mem_result.total_score;
        score_count += 1;
        try w.flush();
    }

    if (config.run_disk) {
        const disk_result = bench_disk.run(allocator, config, &progress) catch |err| {
            progress.clear();
            try output.printSectionHeader(w, output.tr(config.language, "磁盘测试", "Disk Benchmark", "ディスクベンチマーク"), caps);
            try output.printKeyValue(w, "Status", @errorName(err), caps);
            try w.flush();
            return;
        };
        progress.clear();
        try bench_disk.printResults(w, &disk_result, config.language, caps);
        total_score += disk_result.total_score;
        score_count += 1;
        try w.flush();
    }

    try printSummary(w, total_score, score_count, config.language, caps);

    const elapsed = global_timer.elapsed();
    try output.printFooter(w, elapsed, caps);
    try w.flush();

    if (config.save_file) |path| {
        try saveResults(path);
    }
}

fn printSummary(w: *std.Io.Writer, total_score: f64, score_count: u32, lang: cli.Language, caps: output.TermCaps) !void {
    if (score_count == 0) return;

    try output.printSectionHeader(w, output.tr(lang, "综合评分", "Overall Score", "総合スコア"), caps);
    try output.printScore(w, output.tr(lang, "综合得分", "Total Score", "総合得点"), total_score, caps);
}

fn saveResults(path: []const u8) !void {
    const file = try compat.createFileCwd(path, true);
    defer compat.fileClose(file);
    _ = try compat.fileWrite(file, "Zenith Benchmark Results\n");
}
