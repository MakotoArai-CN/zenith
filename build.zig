const std = @import("std");

const CrossTarget = struct {
    name: []const u8,
    cpu_arch: std.Target.Cpu.Arch,
    os_tag: std.Target.Os.Tag,
};

const cross_targets = [_]CrossTarget{
    // Linux
    .{ .name = "linux-x86_64", .cpu_arch = .x86_64, .os_tag = .linux },
    .{ .name = "linux-aarch64", .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .name = "linux-arm", .cpu_arch = .arm, .os_tag = .linux },
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

    // ===== Default install: build ALL cross-compilation targets =====
    for (cross_targets) |ct| {
        const ct_target = b.resolveTargetQuery(.{
            .cpu_arch = ct.cpu_arch,
            .os_tag = ct.os_tag,
        });

        const ct_clap = b.dependency("clap", .{
            .target = ct_target,
            .optimize = optimize,
        });

        const ct_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = ct_target,
            .optimize = optimize,
        });
        ct_module.addImport("clap", ct_clap.module("clap"));

        const ct_exe = b.addExecutable(.{
            .name = b.fmt("zenith-{s}", .{ct.name}),
            .root_module = ct_module,
        });

        b.installArtifact(ct_exe);
    }

    // ===== Native build for run/test =====
    const native_target = b.standardTargetOptions(.{});

    const native_clap = b.dependency("clap", .{
        .target = native_target,
        .optimize = optimize,
    });

    const native_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = native_target,
        .optimize = optimize,
    });
    native_module.addImport("clap", native_clap.module("clap"));

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
    });
    test_module.addImport("clap", native_clap.module("clap"));

    const exe_unit_tests = b.addTest(.{
        .name = "zenith-test",
        .root_module = test_module,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
