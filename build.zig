const std = @import("std");

const version = "1.0.4";

const CrossTarget = struct {
    name: []const u8,
    cpu_arch: std.Target.Cpu.Arch,
    os_tag: std.Target.Os.Tag,
    abi_override: ?std.Target.Abi = null,
};

const cross_targets = [_]CrossTarget{
    // Linux
    .{ .name = "linux-x86_64", .cpu_arch = .x86_64, .os_tag = .linux },
    .{ .name = "linux-aarch64", .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .name = "linux-arm", .cpu_arch = .arm, .os_tag = .linux, .abi_override = .musleabihf },
    .{ .name = "linux-riscv64", .cpu_arch = .riscv64, .os_tag = .linux },
    .{ .name = "linux-s390x", .cpu_arch = .s390x, .os_tag = .linux },
    .{ .name = "linux-ppc64le", .cpu_arch = .powerpc64le, .os_tag = .linux },
    .{ .name = "linux-i386", .cpu_arch = .x86, .os_tag = .linux },
    .{ .name = "linux-loongarch64", .cpu_arch = .loongarch64, .os_tag = .linux },
    // Windows
    .{ .name = "windows-x86_64", .cpu_arch = .x86_64, .os_tag = .windows },
    .{ .name = "windows-i386", .cpu_arch = .x86, .os_tag = .windows },
    .{ .name = "windows-aarch64", .cpu_arch = .aarch64, .os_tag = .windows },
    // macOS
    .{ .name = "macos-x86_64", .cpu_arch = .x86_64, .os_tag = .macos },
    .{ .name = "macos-aarch64", .cpu_arch = .aarch64, .os_tag = .macos },
    // FreeBSD
    .{ .name = "freebsd-x86_64", .cpu_arch = .x86_64, .os_tag = .freebsd },
};

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{});

    const build_options = b.addOptions();
    build_options.addOption([]const u8, "version", version);
    const build_options_module = build_options.createModule();

    // ===== Default install: build ALL cross-compilation targets =====
    for (cross_targets) |ct| {
        const ct_target = b.resolveTargetQuery(.{
            .cpu_arch = ct.cpu_arch,
            .os_tag = ct.os_tag,
            .abi = ct.abi_override orelse if (ct.os_tag == .linux) .musl else null,
        });

        const ct_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = ct_target,
            .optimize = optimize,
            .link_libc = ct.os_tag != .windows,
        });
        ct_module.addImport("build_options", build_options_module);

        const static_linkage: ?std.builtin.LinkMode = switch (ct.os_tag) {
            .linux => .static,
            else => null,
        };

        const ct_exe = b.addExecutable(.{
            .name = b.fmt("zenith-{s}", .{ct.name}),
            .root_module = ct_module,
            .linkage = static_linkage,
        });

        b.installArtifact(ct_exe);
    }

    // ===== Native build for run/test =====
    const native_target = b.standardTargetOptions(.{});

    const native_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = native_target,
        .optimize = optimize,
        .link_libc = native_target.result.os.tag != .windows,
    });
    native_module.addImport("build_options", build_options_module);

    const native_exe = b.addExecutable(.{
        .name = "zenith",
        .root_module = native_module,
    });

    // "run" step: build and run native binary
    const run_cmd = b.addRunArtifact(native_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run zenith benchmark (native)");
    run_step.dependOn(&run_cmd.step);

    // "test" step: run unit tests (native)
    const test_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = native_target,
        .optimize = optimize,
        .link_libc = native_target.result.os.tag != .windows,
    });
    test_module.addImport("build_options", build_options_module);

    const exe_unit_tests = b.addTest(.{
        .name = "zenith-test",
        .root_module = test_module,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
