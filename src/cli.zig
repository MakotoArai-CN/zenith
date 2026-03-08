const std = @import("std");
const builtin = @import("builtin");
const clap = @import("clap");
const main = @import("main.zig");
const output = @import("output.zig");
const terminal = @import("terminal.zig");

pub const Language = enum {
    en,
    zh,
    ja,
};

pub const CpuMethod = enum {
    prime,
    matrix,
    all,
};

pub const DiskMethod = enum {
    sequential,
    random,
    all,
};

pub const Config = struct {
    language: Language = .en,
    run_cpu: bool = true,
    run_memory: bool = true,
    run_disk: bool = true,
    run_sysinfo: bool = true,
    run_network: bool = true,
    cpu_method: CpuMethod = .all,
    cpu_threads: u32 = 0,
    disk_method: DiskMethod = .all,
    disk_path: []const u8 = "/tmp",
    disk_size_mb: u32 = 128,
    iterations: u32 = 3,
    duration_secs: f64 = 10.0,
    save_file: ?[]const u8 = null,
    json_output: bool = false,
};

pub fn parseArgs(allocator: std.mem.Allocator) !Config {
    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Show help message
        \\-v, --version          Show version
        \\-l, --lang <LANG>      Language: en, zh, ja (default: en)
        \\    --no-cpu           Skip CPU benchmark
        \\    --no-memory        Skip memory benchmark
        \\    --no-disk          Skip disk benchmark
        \\    --no-sysinfo       Skip system information
        \\    --no-network       Skip network information
        \\    --cpu-method <M>   CPU method: prime, matrix, all (default: all)
        \\    --threads <N>      Thread count, 0=auto (default: 0)
        \\    --cpu-threads <N>  Alias for --threads
        \\    --disk-method <M>  Disk method: sequential, random, all (default: all)
        \\    --disk-path <P>    Disk test path (default: /tmp)
        \\    --disk-size <N>    Disk test size in MB (default: 128)
        \\    --iterations <N>   Iterations per test (default: 3)
        \\-t, --time <N>         Duration per test in seconds (default: 10)
        \\    --duration <N>     Alias for --time
        \\-o, --output <FILE>    Save results to file
        \\    --json             Output in JSON format
        \\
    );

    var diag: clap.Diagnostic = .{};
    var res = clap.parse(clap.Help, &params, .{
        .LANG = clap.parsers.string,
        .M = clap.parsers.string,
        .N = clap.parsers.string,
        .P = clap.parsers.string,
        .FILE = clap.parsers.string,
    }, .{ .allocator = allocator, .diagnostic = &diag }) catch |err| {
        var stderr_buffer: [4096]u8 = undefined;
        var stderr_writer = std.fs.File.stderr().writer(&stderr_buffer);
        const stderr = &stderr_writer.interface;
        diag.report(stderr, err) catch {};
        stderr.flush() catch {};
        return error.InvalidArgument;
    };
    defer res.deinit();

    // Detect language: explicit flag > system language > en
    const lang: Language = if (res.args.lang) |lang_str| parseLang(lang_str) orelse .en else detectSystemLanguage();

    if (res.args.help != 0) {
        printHelp(lang);
        return error.HelpRequested;
    }

    if (res.args.version != 0) {
        printVersion(lang);
        return error.VersionRequested;
    }

    var config: Config = .{};
    config.language = lang;

    if (res.args.@"no-cpu" != 0) config.run_cpu = false;
    if (res.args.@"no-memory" != 0) config.run_memory = false;
    if (res.args.@"no-disk" != 0) config.run_disk = false;
    if (res.args.@"no-sysinfo" != 0) config.run_sysinfo = false;
    if (res.args.@"no-network" != 0) config.run_network = false;

    if (res.args.@"cpu-method") |m| {
        config.cpu_method = parseCpuMethod(m) orelse .all;
    }
    // --threads and --cpu-threads both set cpu_threads
    if (res.args.threads) |t| {
        config.cpu_threads = std.fmt.parseInt(u32, t, 10) catch 0;
    }
    if (res.args.@"cpu-threads") |t| {
        config.cpu_threads = std.fmt.parseInt(u32, t, 10) catch 0;
    }
    if (res.args.@"disk-method") |m| {
        config.disk_method = parseDiskMethod(m) orelse .all;
    }
    if (res.args.@"disk-path") |p| {
        config.disk_path = p;
    }
    if (res.args.@"disk-size") |s| {
        config.disk_size_mb = std.fmt.parseInt(u32, s, 10) catch 128;
    }
    if (res.args.iterations) |i| {
        config.iterations = std.fmt.parseInt(u32, i, 10) catch 3;
    }
    // -t/--time and --duration both set duration_secs
    if (res.args.time) |d| {
        config.duration_secs = std.fmt.parseFloat(f64, d) catch 10.0;
    }
    if (res.args.duration) |d| {
        config.duration_secs = std.fmt.parseFloat(f64, d) catch 10.0;
    }

    // Input validation: clamp to safe ranges
    config.cpu_threads = @min(config.cpu_threads, 1024);
    config.disk_size_mb = @max(@min(config.disk_size_mb, 4096), 1);
    config.iterations = @max(@min(config.iterations, 100), 1);
    config.duration_secs = @max(@min(config.duration_secs, 3600.0), 1.0);
    if (res.args.output) |o| {
        config.save_file = o;
    }
    if (res.args.json != 0) config.json_output = true;

    return config;
}

fn parseLang(s: []const u8) ?Language {
    if (std.mem.eql(u8, s, "en")) return .en;
    if (std.mem.eql(u8, s, "zh")) return .zh;
    if (std.mem.eql(u8, s, "ja")) return .ja;
    return null;
}

fn detectSystemLanguage() Language {
    switch (builtin.os.tag) {
        .windows => return detectWindowsLanguage(),
        else => return detectPosixLanguage(),
    }
}

fn detectPosixLanguage() Language {
    // Check LANG, LC_ALL, LC_MESSAGES environment variables
    const env_vars = [_][]const u8{ "LC_ALL", "LC_MESSAGES", "LANG" };
    for (env_vars) |name| {
        if (std.posix.getenv(name)) |val| {
            if (langFromLocale(val)) |lang| return lang;
        }
    }
    return .en;
}

fn detectWindowsLanguage() Language {
    const k32 = struct {
        extern "kernel32" fn GetUserDefaultUILanguage() callconv(.winapi) u16;
    };
    const lang_id = k32.GetUserDefaultUILanguage() & 0xFF; // primary language ID
    return switch (lang_id) {
        0x04 => .zh, // Chinese
        0x11 => .ja, // Japanese
        else => .en,
    };
}

fn langFromLocale(locale: []const u8) ?Language {
    // Match patterns like "zh_CN.UTF-8", "ja_JP", "en_US", "zh", "ja"
    if (locale.len >= 2) {
        if (std.mem.startsWith(u8, locale, "zh")) return .zh;
        if (std.mem.startsWith(u8, locale, "ja")) return .ja;
    }
    return null;
}

fn parseCpuMethod(s: []const u8) ?CpuMethod {
    if (std.mem.eql(u8, s, "prime")) return .prime;
    if (std.mem.eql(u8, s, "matrix")) return .matrix;
    if (std.mem.eql(u8, s, "all")) return .all;
    return null;
}

fn parseDiskMethod(s: []const u8) ?DiskMethod {
    if (std.mem.eql(u8, s, "sequential")) return .sequential;
    if (std.mem.eql(u8, s, "random")) return .random;
    if (std.mem.eql(u8, s, "all")) return .all;
    return null;
}

fn printHelp(lang: Language) void {
    var stdout_buffer: [8192]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const w = &stdout_writer.interface;
    const caps = terminal.TermCaps.detect();

    const cyan = if (caps.color) output.Color.miku_cyan else "";
    const accent = if (caps.color) output.Color.miku_accent else "";
    const reset = if (caps.color) output.Color.reset else "";

    switch (lang) {
        .zh => w.print(
            \\{s}zenith{s} - 系统基准测试工具 v{s}
            \\
            \\{s}用法:{s} zenith [选项]
            \\
            \\{s}选项:{s}
            \\  -h, --help             显示帮助信息
            \\  -v, --version          显示版本号
            \\  -l, --lang <LANG>      语言: en, zh, ja (默认: en)
            \\      --no-cpu           跳过 CPU 测试
            \\      --no-memory        跳过内存测试
            \\      --no-disk          跳过磁盘测试
            \\      --no-sysinfo       跳过系统信息
            \\      --no-network       跳过网络信息
            \\      --cpu-method <M>   CPU 测试方式: prime, matrix, all (默认: all)
            \\      --threads <N>      线程数, 0=自动 (默认: 0)
            \\      --disk-method <M>  磁盘测试: sequential, random, all (默认: all)
            \\      --disk-path <P>    磁盘测试路径 (默认: /tmp)
            \\      --disk-size <N>    磁盘测试大小 MB (默认: 128)
            \\      --iterations <N>   每项测试迭代次数 (默认: 3)
            \\  -t, --time <N>         每项测试持续时间秒 (默认: 10)
            \\  -o, --output <FILE>    保存结果到文件
            \\      --json             JSON 格式输出
            \\
        , .{
            cyan,
            reset,
            main.version,
            accent,
            reset,
            accent,
            reset,
        }) catch {},
        .en => w.print(
            \\{s}zenith{s} - System Benchmark Tool v{s}
            \\
            \\{s}Usage:{s} zenith [options]
            \\
            \\{s}Options:{s}
            \\  -h, --help             Show this help message
            \\  -v, --version          Show version
            \\  -l, --lang <LANG>      Language: en, zh, ja (default: en)
            \\      --no-cpu           Skip CPU benchmark
            \\      --no-memory        Skip memory benchmark
            \\      --no-disk          Skip disk benchmark
            \\      --no-sysinfo       Skip system information
            \\      --no-network       Skip network information
            \\      --cpu-method <M>   CPU method: prime, matrix, all (default: all)
            \\      --threads <N>      Thread count, 0=auto (default: 0)
            \\      --disk-method <M>  Disk: sequential, random, all (default: all)
            \\      --disk-path <P>    Disk test path (default: /tmp)
            \\      --disk-size <N>    Disk test size in MB (default: 128)
            \\      --iterations <N>   Iterations per test (default: 3)
            \\  -t, --time <N>         Duration per test in seconds (default: 10)
            \\  -o, --output <FILE>    Save results to file
            \\      --json             JSON output format
            \\
        , .{
            cyan,
            reset,
            main.version,
            accent,
            reset,
            accent,
            reset,
        }) catch {},
        .ja => w.print(
            \\{s}zenith{s} - システムベンチマークツール v{s}
            \\
            \\{s}使い方:{s} zenith [オプション]
            \\
            \\{s}オプション:{s}
            \\  -h, --help             ヘルプを表示
            \\  -v, --version          バージョンを表示
            \\  -l, --lang <LANG>      言語: en, zh, ja (デフォルト: en)
            \\      --no-cpu           CPUベンチマークをスキップ
            \\      --no-memory        メモリベンチマークをスキップ
            \\      --no-disk          ディスクベンチマークをスキップ
            \\      --no-sysinfo       システム情報をスキップ
            \\      --no-network       ネットワーク情報をスキップ
            \\      --cpu-method <M>   CPU方式: prime, matrix, all (デフォルト: all)
            \\      --threads <N>      スレッド数, 0=自動 (デフォルト: 0)
            \\      --disk-method <M>  ディスク: sequential, random, all (デフォルト: all)
            \\      --disk-path <P>    ディスクテストパス (デフォルト: /tmp)
            \\      --disk-size <N>    ディスクテストサイズ MB (デフォルト: 128)
            \\      --iterations <N>   テスト毎の反復回数 (デフォルト: 3)
            \\  -t, --time <N>         テスト毎の実行時間秒 (デフォルト: 10)
            \\  -o, --output <FILE>    結果をファイルに保存
            \\      --json             JSON形式で出力
            \\
        , .{
            cyan,
            reset,
            main.version,
            accent,
            reset,
            accent,
            reset,
        }) catch {},
    }
    w.flush() catch {};
}

fn printVersion(lang: Language) void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
    const w = &stdout_writer.interface;
    switch (lang) {
        .zh => w.print("zenith v{s} - 系统基准测试工具\n", .{main.version}) catch {},
        .en => w.print("zenith v{s} - System Benchmark Tool\n", .{main.version}) catch {},
        .ja => w.print("zenith v{s} - システムベンチマークツール\n", .{main.version}) catch {},
    }
    w.flush() catch {};
}
