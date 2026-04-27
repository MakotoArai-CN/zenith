const std = @import("std");
const builtin = @import("builtin");
const main = @import("main.zig");
const output = @import("output.zig");
const terminal = @import("terminal.zig");
const compat = @import("compat.zig");

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

const ParseError = error{
    InvalidArgument,
    HelpRequested,
    VersionRequested,
};

// Match an argument against a long flag and an optional short alias.
// Supports `--flag=value` form for value flags (caller checks via consumeValue).
fn argMatches(arg: []const u8, long: []const u8, short: ?[]const u8) bool {
    if (short) |s| {
        if (std.mem.eql(u8, arg, s)) return true;
    }
    if (std.mem.eql(u8, arg, long)) return true;
    if (std.mem.startsWith(u8, arg, long) and arg.len > long.len and arg[long.len] == '=') return true;
    return false;
}

// Returns the value for --flag=value or the next arg for --flag value.
// Advances `*i` past the consumed value if it came from a separate arg.
fn consumeValue(arg: []const u8, long: []const u8, args: []const []const u8, i: *usize) ?[]const u8 {
    if (std.mem.startsWith(u8, arg, long) and arg.len > long.len and arg[long.len] == '=') {
        return arg[long.len + 1 ..];
    }
    if (i.* + 1 >= args.len) return null;
    i.* += 1;
    return args[i.*];
}

pub fn parseArgs(allocator: std.mem.Allocator, args_source: compat.ArgsSource) !Config {
    const argv = try compat.collectArgs(allocator, args_source);
    defer compat.freeArgs(allocator, argv);

    var lang_explicit: ?Language = null;
    var help = false;
    var ver = false;
    var config: Config = .{};

    var i: usize = 0;
    while (i < argv.len) : (i += 1) {
        const a = argv[i];

        if (argMatches(a, "--help", "-h")) {
            help = true;
        } else if (argMatches(a, "--version", "-v")) {
            ver = true;
        } else if (argMatches(a, "--lang", "-l")) {
            const v = consumeValue(a, "--lang", argv, &i) orelse return reportError("--lang requires a value");
            lang_explicit = parseLang(v) orelse return reportError("invalid --lang value");
        } else if (std.mem.eql(u8, a, "--no-cpu")) {
            config.run_cpu = false;
        } else if (std.mem.eql(u8, a, "--no-memory")) {
            config.run_memory = false;
        } else if (std.mem.eql(u8, a, "--no-disk")) {
            config.run_disk = false;
        } else if (std.mem.eql(u8, a, "--no-sysinfo")) {
            config.run_sysinfo = false;
        } else if (std.mem.eql(u8, a, "--no-network")) {
            config.run_network = false;
        } else if (argMatches(a, "--cpu-method", null)) {
            const v = consumeValue(a, "--cpu-method", argv, &i) orelse return reportError("--cpu-method requires a value");
            config.cpu_method = parseCpuMethod(v) orelse .all;
        } else if (argMatches(a, "--threads", null) or argMatches(a, "--cpu-threads", null)) {
            const long = if (std.mem.startsWith(u8, a, "--cpu-threads")) "--cpu-threads" else "--threads";
            const v = consumeValue(a, long, argv, &i) orelse return reportError("--threads requires a value");
            config.cpu_threads = std.fmt.parseInt(u32, v, 10) catch 0;
        } else if (argMatches(a, "--disk-method", null)) {
            const v = consumeValue(a, "--disk-method", argv, &i) orelse return reportError("--disk-method requires a value");
            config.disk_method = parseDiskMethod(v) orelse .all;
        } else if (argMatches(a, "--disk-path", null)) {
            const v = consumeValue(a, "--disk-path", argv, &i) orelse return reportError("--disk-path requires a value");
            config.disk_path = v;
        } else if (argMatches(a, "--disk-size", null)) {
            const v = consumeValue(a, "--disk-size", argv, &i) orelse return reportError("--disk-size requires a value");
            config.disk_size_mb = std.fmt.parseInt(u32, v, 10) catch 128;
        } else if (argMatches(a, "--iterations", null)) {
            const v = consumeValue(a, "--iterations", argv, &i) orelse return reportError("--iterations requires a value");
            config.iterations = std.fmt.parseInt(u32, v, 10) catch 3;
        } else if (argMatches(a, "--time", "-t") or argMatches(a, "--duration", null)) {
            const long = if (std.mem.startsWith(u8, a, "--duration")) "--duration" else "--time";
            const v = consumeValue(a, long, argv, &i) orelse return reportError("--time requires a value");
            config.duration_secs = std.fmt.parseFloat(f64, v) catch 10.0;
        } else if (argMatches(a, "--output", "-o")) {
            const v = consumeValue(a, "--output", argv, &i) orelse return reportError("--output requires a value");
            config.save_file = v;
        } else if (std.mem.eql(u8, a, "--json")) {
            config.json_output = true;
        } else if (std.mem.startsWith(u8, a, "-")) {
            return reportError("unknown option");
        } else {
            return reportError("unexpected positional argument");
        }
    }

    const lang: Language = lang_explicit orelse detectSystemLanguage();

    if (help) {
        printHelp(lang);
        return error.HelpRequested;
    }
    if (ver) {
        printVersion(lang);
        return error.VersionRequested;
    }

    config.language = lang;

    config.cpu_threads = @min(config.cpu_threads, 1024);
    config.disk_size_mb = @max(@min(config.disk_size_mb, 4096), 1);
    config.iterations = @max(@min(config.iterations, 100), 1);
    config.duration_secs = @max(@min(config.duration_secs, 3600.0), 1.0);

    return config;
}

fn reportError(msg: []const u8) error{InvalidArgument} {
    var stderr_buffer: [256]u8 = undefined;
    var stderr_writer = compat.fileWriter(compat.stderrFile(), &stderr_buffer);
    const stderr = &stderr_writer.interface;
    stderr.print("Error: {s}\n", .{msg}) catch {};
    stderr.flush() catch {};
    return error.InvalidArgument;
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
    const env_vars = [_][:0]const u8{ "LC_ALL", "LC_MESSAGES", "LANG" };
    for (env_vars) |name| {
        if (compat.getenv(name)) |val| {
            if (langFromLocale(val)) |lang| return lang;
        }
    }
    return .en;
}

fn detectWindowsLanguage() Language {
    const k32 = struct {
        extern "kernel32" fn GetUserDefaultUILanguage() callconv(.winapi) u16;
    };
    const lang_id = k32.GetUserDefaultUILanguage() & 0xFF;
    return switch (lang_id) {
        0x04 => .zh,
        0x11 => .ja,
        else => .en,
    };
}

fn langFromLocale(locale: []const u8) ?Language {
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
    var stdout_writer = compat.fileWriter(compat.stdoutFile(), &stdout_buffer);
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
        , .{ cyan, reset, main.version, accent, reset, accent, reset }) catch {},
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
        , .{ cyan, reset, main.version, accent, reset, accent, reset }) catch {},
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
        , .{ cyan, reset, main.version, accent, reset, accent, reset }) catch {},
    }
    w.flush() catch {};
}

fn printVersion(lang: Language) void {
    var stdout_buffer: [256]u8 = undefined;
    var stdout_writer = compat.fileWriter(compat.stdoutFile(), &stdout_buffer);
    const w = &stdout_writer.interface;
    switch (lang) {
        .zh => w.print("zenith v{s} - 系统基准测试工具\n", .{main.version}) catch {},
        .en => w.print("zenith v{s} - System Benchmark Tool\n", .{main.version}) catch {},
        .ja => w.print("zenith v{s} - システムベンチマークツール\n", .{main.version}) catch {},
    }
    w.flush() catch {};
}
