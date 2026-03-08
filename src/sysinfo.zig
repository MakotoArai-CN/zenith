const std = @import("std");
const builtin = @import("builtin");
const output = @import("output.zig");
const cli = @import("cli.zig");

// ==================== Data Structures ====================

pub const CpuInfo = struct {
    model: [256]u8 = undefined,
    model_len: usize = 0,
    physical_cores: u32 = 0,
    logical_threads: u32 = 0,
    l1_cache_kb: u32 = 0,
    l2_cache_kb: u32 = 0,
    l3_cache_kb: u32 = 0,

    pub fn modelName(self: *const CpuInfo) []const u8 {
        return self.model[0..self.model_len];
    }
};

pub const MemInfo = struct {
    total_bytes: u64 = 0,
    available_bytes: u64 = 0,
    swap_total_bytes: u64 = 0,
    swap_used_bytes: u64 = 0,
};

pub const OsInfo = struct {
    name: [128]u8 = undefined,
    name_len: usize = 0,
    full_name: [256]u8 = undefined,
    full_name_len: usize = 0,
    arch: [32]u8 = undefined,
    arch_len: usize = 0,
    kernel_version: [128]u8 = undefined,
    kernel_version_len: usize = 0,
    hostname: [256]u8 = undefined,
    hostname_len: usize = 0,
    uptime_seconds: u64 = 0,
    timezone: [64]u8 = undefined,
    timezone_len: usize = 0,

    pub fn osName(self: *const OsInfo) []const u8 {
        return self.name[0..self.name_len];
    }
    pub fn fullName(self: *const OsInfo) []const u8 {
        return self.full_name[0..self.full_name_len];
    }
    pub fn archName(self: *const OsInfo) []const u8 {
        return self.arch[0..self.arch_len];
    }
    pub fn hostName(self: *const OsInfo) []const u8 {
        return self.hostname[0..self.hostname_len];
    }
    pub fn kernelVer(self: *const OsInfo) []const u8 {
        return self.kernel_version[0..self.kernel_version_len];
    }
    pub fn timezoneName(self: *const OsInfo) []const u8 {
        return self.timezone[0..self.timezone_len];
    }
};

pub const DiskEntry = struct {
    mount_point: [128]u8 = undefined,
    mount_point_len: usize = 0,
    total_bytes: u64 = 0,
    free_bytes: u64 = 0,

    pub fn mountPoint(self: *const DiskEntry) []const u8 {
        return self.mount_point[0..self.mount_point_len];
    }
};

pub const DiskInfo = struct {
    drives: [16]DiskEntry = undefined,
    drive_count: u8 = 0,
};

pub const VirtInfo = struct {
    hypervisor: [64]u8 = undefined,
    hypervisor_len: usize = 0,

    pub fn hypervisorName(self: *const VirtInfo) []const u8 {
        return self.hypervisor[0..self.hypervisor_len];
    }
};

pub const LoadInfo = struct {
    load_1: f64 = 0,
    load_5: f64 = 0,
    load_15: f64 = 0,
};

pub const SystemInfo = struct {
    cpu: CpuInfo = .{},
    mem: MemInfo = .{},
    os: OsInfo = .{},
    disk: DiskInfo = .{},
    virt: VirtInfo = .{},
    load: LoadInfo = .{},
};

// ==================== Collect ====================

pub fn collect() SystemInfo {
    var info: SystemInfo = .{};

    // OS name + arch (compile-time)
    const os_str = @tagName(builtin.os.tag);
    @memcpy(info.os.name[0..os_str.len], os_str);
    info.os.name_len = os_str.len;

    const arch_str = @tagName(builtin.cpu.arch);
    @memcpy(info.os.arch[0..arch_str.len], arch_str);
    info.os.arch_len = arch_str.len;

    // CPU
    info.cpu.logical_threads = @intCast(std.Thread.getCpuCount() catch 1);
    readCpuModel(&info.cpu);
    readCpuTopology(&info.cpu);
    readCpuCache(&info.cpu);

    // Memory
    readMemory(&info.mem);

    // OS details
    readHostname(&info.os);
    readKernelVersion(&info.os);
    readFullOsName(&info.os);
    readUptime(&info.os);
    readTimezone(&info.os);

    // Disk
    readDiskSpace(&info.disk);

    // Virtualization
    readVirtualization(&info.virt);

    // Load
    readLoad(&info.load);

    return info;
}

// ==================== CPU Model ====================

fn readCpuModel(cpu: *CpuInfo) void {
    switch (builtin.os.tag) {
        .linux => readLinuxCpuModel(cpu),
        .windows, .macos, .freebsd => readCpuModelCpuid(cpu),
        else => setStr(&cpu.model, &cpu.model_len, "Unknown"),
    }
}

fn readLinuxCpuModel(cpu: *CpuInfo) void {
    const file = std.fs.openFileAbsolute("/proc/cpuinfo", .{}) catch {
        readCpuModelCpuid(cpu);
        return;
    };
    defer file.close();
    var buf: [8192]u8 = undefined;
    const n = file.read(&buf) catch {
        readCpuModelCpuid(cpu);
        return;
    };
    var lines = std.mem.splitScalar(u8, buf[0..n], '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "model name")) {
            const colon = std.mem.indexOf(u8, line, ":") orelse continue;
            const model = std.mem.trim(u8, line[colon + 1 ..], " \t");
            setStr(&cpu.model, &cpu.model_len, model);
            return;
        }
    }
    readCpuModelCpuid(cpu);
}

fn readCpuModelCpuid(cpu: *CpuInfo) void {
    const arch = builtin.cpu.arch;
    if (arch != .x86_64 and arch != .x86) {
        setStr(&cpu.model, &cpu.model_len, "Unknown");
        return;
    }
    const ext_max = cpuid(0x80000000);
    if (ext_max.eax < 0x80000004) {
        setStr(&cpu.model, &cpu.model_len, "Unknown");
        return;
    }
    var brand: [48]u8 = undefined;
    inline for (0..3) |i| {
        const leaf: u32 = 0x80000002 + @as(u32, @intCast(i));
        const r = cpuid(leaf);
        const off = i * 16;
        @memcpy(brand[off..][0..4], std.mem.asBytes(&r.eax));
        @memcpy(brand[off + 4 ..][0..4], std.mem.asBytes(&r.ebx));
        @memcpy(brand[off + 8 ..][0..4], std.mem.asBytes(&r.ecx));
        @memcpy(brand[off + 12 ..][0..4], std.mem.asBytes(&r.edx));
    }
    const trimmed = std.mem.trim(u8, &brand, " \x00");
    if (trimmed.len == 0) {
        setStr(&cpu.model, &cpu.model_len, "Unknown");
        return;
    }
    setStr(&cpu.model, &cpu.model_len, trimmed);
}

// ==================== CPU Topology ====================

fn readCpuTopology(cpu: *CpuInfo) void {
    switch (builtin.os.tag) {
        .linux => readLinuxCpuTopology(cpu),
        else => readCpuTopologyCpuid(cpu),
    }
}

fn readLinuxCpuTopology(cpu: *CpuInfo) void {
    // Count unique core IDs from /proc/cpuinfo
    const file = std.fs.openFileAbsolute("/proc/cpuinfo", .{}) catch {
        readCpuTopologyCpuid(cpu);
        return;
    };
    defer file.close();
    var buf: [32768]u8 = undefined;
    const n = file.read(&buf) catch {
        readCpuTopologyCpuid(cpu);
        return;
    };
    var seen_cores: [256]u32 = undefined;
    @memset(&seen_cores, 0xFFFFFFFF);
    var physical: u32 = 0;

    var lines = std.mem.splitScalar(u8, buf[0..n], '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "core id")) {
            const colon = std.mem.indexOf(u8, line, ":") orelse continue;
            const val = std.mem.trim(u8, line[colon + 1 ..], " \t");
            const core_id = std.fmt.parseInt(u32, val, 10) catch continue;
            var found = false;
            for (seen_cores[0..physical]) |sc| {
                if (sc == core_id) {
                    found = true;
                    break;
                }
            }
            if (!found and physical < seen_cores.len) {
                seen_cores[physical] = core_id;
                physical += 1;
            }
        }
    }
    cpu.physical_cores = if (physical > 0) physical else cpu.logical_threads;
}

fn readCpuTopologyCpuid(cpu: *CpuInfo) void {
    if (builtin.cpu.arch != .x86_64 and builtin.cpu.arch != .x86) {
        cpu.physical_cores = cpu.logical_threads;
        return;
    }
    // CPUID leaf 4, subleaf 0: EAX[31:26]+1 = max cores sharing this package
    const r = cpuidEx(4, 0);
    const max_cores = ((r.eax >> 26) & 0x3F) + 1;
    if (max_cores > 0 and max_cores <= cpu.logical_threads) {
        cpu.physical_cores = max_cores;
    } else {
        cpu.physical_cores = cpu.logical_threads;
    }
}

// ==================== CPU Cache ====================

fn readCpuCache(cpu: *CpuInfo) void {
    switch (builtin.os.tag) {
        .linux => {
            readLinuxCpuCache(cpu);
            if (cpu.l1_cache_kb == 0 and cpu.l2_cache_kb == 0) readCpuCacheCpuid(cpu);
        },
        else => readCpuCacheCpuid(cpu),
    }
}

fn readLinuxCpuCache(cpu: *CpuInfo) void {
    const indices = [_][]const u8{
        "/sys/devices/system/cpu/cpu0/cache/index0/size",
        "/sys/devices/system/cpu/cpu0/cache/index1/size",
        "/sys/devices/system/cpu/cpu0/cache/index2/size",
        "/sys/devices/system/cpu/cpu0/cache/index3/size",
    };
    const levels = [_][]const u8{
        "/sys/devices/system/cpu/cpu0/cache/index0/level",
        "/sys/devices/system/cpu/cpu0/cache/index1/level",
        "/sys/devices/system/cpu/cpu0/cache/index2/level",
        "/sys/devices/system/cpu/cpu0/cache/index3/level",
    };

    for (indices, levels) |size_path, level_path| {
        const level = readFileInt(level_path) orelse continue;
        const size_kb = readCacheSizeKb(size_path) orelse continue;
        switch (level) {
            1 => {
                cpu.l1_cache_kb += size_kb;
            },
            2 => cpu.l2_cache_kb = size_kb,
            3 => cpu.l3_cache_kb = size_kb,
            else => {},
        }
    }
}

fn readFileInt(path: []const u8) ?u32 {
    const file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();
    var buf: [32]u8 = undefined;
    const n = file.read(&buf) catch return null;
    const s = std.mem.trim(u8, buf[0..n], " \t\n\r");
    return std.fmt.parseInt(u32, s, 10) catch null;
}

fn readCacheSizeKb(path: []const u8) ?u32 {
    const file = std.fs.openFileAbsolute(path, .{}) catch return null;
    defer file.close();
    var buf: [32]u8 = undefined;
    const n = file.read(&buf) catch return null;
    const s = std.mem.trim(u8, buf[0..n], " \t\n\r");
    // Format: "32K" or "256K" or "12288K"
    if (s.len > 0 and (s[s.len - 1] == 'K' or s[s.len - 1] == 'k')) {
        return std.fmt.parseInt(u32, s[0 .. s.len - 1], 10) catch null;
    }
    if (s.len > 0 and (s[s.len - 1] == 'M' or s[s.len - 1] == 'm')) {
        const mb = std.fmt.parseInt(u32, s[0 .. s.len - 1], 10) catch return null;
        return mb * 1024;
    }
    return std.fmt.parseInt(u32, s, 10) catch null;
}

fn readCpuCacheCpuid(cpu: *CpuInfo) void {
    if (builtin.cpu.arch != .x86_64 and builtin.cpu.arch != .x86) return;

    // Try deterministic cache parameters (leaf 4)
    var subleaf: u32 = 0;
    while (subleaf < 16) : (subleaf += 1) {
        const r = cpuidEx(4, subleaf);
        const cache_type = r.eax & 0x1F;
        if (cache_type == 0) break; // No more caches
        const level = (r.eax >> 5) & 0x7;
        const ways = ((r.ebx >> 22) & 0x3FF) + 1;
        const partitions = ((r.ebx >> 12) & 0x3FF) + 1;
        const line_size = (r.ebx & 0xFFF) + 1;
        const sets = r.ecx + 1;
        const size_bytes = ways * partitions * line_size * sets;
        const size_kb = size_bytes / 1024;
        switch (level) {
            1 => cpu.l1_cache_kb += size_kb,
            2 => cpu.l2_cache_kb = size_kb,
            3 => cpu.l3_cache_kb = size_kb,
            else => {},
        }
    }

    // Fallback: AMD extended CPUID
    if (cpu.l2_cache_kb == 0) {
        const ext = cpuid(0x80000000);
        if (ext.eax >= 0x80000006) {
            const r6 = cpuid(0x80000006);
            cpu.l2_cache_kb = (r6.ecx >> 16) & 0xFFFF;
            const l3_half_mb = (r6.edx >> 18) & 0x3FFF;
            if (l3_half_mb > 0) cpu.l3_cache_kb = l3_half_mb * 512;
        }
    }
}

// ==================== Memory ====================

fn readMemory(mem: *MemInfo) void {
    switch (builtin.os.tag) {
        .linux => readLinuxMemory(mem),
        .windows => readWindowsMemory(mem),
        .macos => readMacosMemory(mem),
        else => {},
    }
}

fn readLinuxMemory(mem: *MemInfo) void {
    const file = std.fs.openFileAbsolute("/proc/meminfo", .{}) catch return;
    defer file.close();
    var buf: [4096]u8 = undefined;
    const n = file.read(&buf) catch return;
    var lines = std.mem.splitScalar(u8, buf[0..n], '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "MemTotal:")) {
            mem.total_bytes = parseMemInfoKb(line["MemTotal:".len..]) * 1024;
        } else if (std.mem.startsWith(u8, line, "MemAvailable:")) {
            mem.available_bytes = parseMemInfoKb(line["MemAvailable:".len..]) * 1024;
        } else if (std.mem.startsWith(u8, line, "SwapTotal:")) {
            mem.swap_total_bytes = parseMemInfoKb(line["SwapTotal:".len..]) * 1024;
        } else if (std.mem.startsWith(u8, line, "SwapFree:")) {
            const free = parseMemInfoKb(line["SwapFree:".len..]) * 1024;
            mem.swap_used_bytes = if (mem.swap_total_bytes > free) mem.swap_total_bytes - free else 0;
        }
    }
}

fn parseMemInfoKb(s: []const u8) u64 {
    const trimmed = std.mem.trim(u8, s, " \t");
    const kb_end = std.mem.indexOf(u8, trimmed, " ") orelse trimmed.len;
    return std.fmt.parseInt(u64, trimmed[0..kb_end], 10) catch 0;
}

fn readWindowsMemory(mem: *MemInfo) void {
    const windows = std.os.windows;
    const MEMORYSTATUSEX = extern struct {
        dwLength: windows.DWORD,
        dwMemoryLoad: windows.DWORD,
        ullTotalPhys: u64,
        ullAvailPhys: u64,
        ullTotalPageFile: u64,
        ullAvailPageFile: u64,
        ullTotalVirtual: u64,
        ullAvailVirtual: u64,
        ullAvailExtendedVirtual: u64,
    };
    const k32 = struct {
        extern "kernel32" fn GlobalMemoryStatusEx(lpBuffer: *MEMORYSTATUSEX) callconv(.winapi) windows.BOOL;
    };
    var ms: MEMORYSTATUSEX = std.mem.zeroes(MEMORYSTATUSEX);
    ms.dwLength = @sizeOf(MEMORYSTATUSEX);
    if (k32.GlobalMemoryStatusEx(&ms) != 0) {
        mem.total_bytes = ms.ullTotalPhys;
        mem.available_bytes = ms.ullAvailPhys;
        mem.swap_total_bytes = ms.ullTotalPageFile;
        const swap_avail = ms.ullAvailPageFile;
        mem.swap_used_bytes = if (ms.ullTotalPageFile > swap_avail) ms.ullTotalPageFile - swap_avail else 0;
    }
}

fn readMacosMemory(mem: *MemInfo) void {
    const mib = [2]c_int{ 6, 24 }; // CTL_HW, HW_MEMSIZE
    var size: u64 = 0;
    var len: usize = @sizeOf(u64);
    const rc = std.posix.system.sysctl(
        @constCast(@ptrCast(&mib)),
        2,
        @ptrCast(&size),
        &len,
        null,
        0,
    );
    if (rc == 0) mem.total_bytes = size;
}

// ==================== Hostname ====================

fn readHostname(os: *OsInfo) void {
    switch (builtin.os.tag) {
        .linux => readLinuxHostname(os),
        .windows => readWindowsHostname(os),
        .macos => readPosixHostname(os),
        else => setStr(&os.hostname, &os.hostname_len, "unknown"),
    }
}

fn readLinuxHostname(os: *OsInfo) void {
    const file = std.fs.openFileAbsolute("/etc/hostname", .{}) catch {
        setStr(&os.hostname, &os.hostname_len, "unknown");
        return;
    };
    defer file.close();
    const n = file.read(&os.hostname) catch {
        setStr(&os.hostname, &os.hostname_len, "unknown");
        return;
    };
    os.hostname_len = std.mem.trim(u8, os.hostname[0..n], " \t\n\r").len;
}

fn readWindowsHostname(os: *OsInfo) void {
    const windows = std.os.windows;
    const k32 = struct {
        extern "kernel32" fn GetComputerNameA(lpBuffer: [*]u8, nSize: *windows.DWORD) callconv(.winapi) windows.BOOL;
    };
    var name_len: windows.DWORD = @intCast(os.hostname.len);
    if (k32.GetComputerNameA(&os.hostname, &name_len) != 0) {
        os.hostname_len = @intCast(name_len);
    } else {
        setStr(&os.hostname, &os.hostname_len, "unknown");
    }
}

fn readPosixHostname(os: *OsInfo) void {
    const rc = std.posix.system.gethostname(@ptrCast(&os.hostname), os.hostname.len);
    if (rc == 0) {
        os.hostname_len = std.mem.indexOfScalar(u8, &os.hostname, 0) orelse os.hostname.len;
    } else {
        setStr(&os.hostname, &os.hostname_len, "unknown");
    }
}

// ==================== Kernel Version ====================

fn readKernelVersion(os: *OsInfo) void {
    switch (builtin.os.tag) {
        .linux => readLinuxKernelVersion(os),
        .windows => readWindowsKernelVersion(os),
        .macos => readMacosKernelVersion(os),
        else => setStr(&os.kernel_version, &os.kernel_version_len, "unknown"),
    }
}

fn readLinuxKernelVersion(os: *OsInfo) void {
    const file = std.fs.openFileAbsolute("/proc/version", .{}) catch {
        setStr(&os.kernel_version, &os.kernel_version_len, "unknown");
        return;
    };
    defer file.close();
    var buf: [512]u8 = undefined;
    const n = file.read(&buf) catch {
        setStr(&os.kernel_version, &os.kernel_version_len, "unknown");
        return;
    };
    const content = buf[0..n];
    const first_space = std.mem.indexOf(u8, content, " ") orelse {
        setStr(&os.kernel_version, &os.kernel_version_len, "unknown");
        return;
    };
    const after = content[first_space + 1 ..];
    const second_space = std.mem.indexOf(u8, after, " ") orelse {
        setStr(&os.kernel_version, &os.kernel_version_len, "unknown");
        return;
    };
    const ver = std.mem.trim(u8, after[0..second_space], " \t\n");
    setStr(&os.kernel_version, &os.kernel_version_len, ver);
}

fn readWindowsKernelVersion(os: *OsInfo) void {
    const windows = std.os.windows;
    var vi: windows.RTL_OSVERSIONINFOW = std.mem.zeroes(windows.RTL_OSVERSIONINFOW);
    vi.dwOSVersionInfoSize = @sizeOf(windows.RTL_OSVERSIONINFOW);
    if (windows.ntdll.RtlGetVersion(&vi) == .SUCCESS) {
        const s = std.fmt.bufPrint(&os.kernel_version, "Windows {d}.{d}.{d}", .{
            vi.dwMajorVersion, vi.dwMinorVersion, vi.dwBuildNumber,
        }) catch {
            setStr(&os.kernel_version, &os.kernel_version_len, "unknown");
            return;
        };
        os.kernel_version_len = s.len;
    } else {
        setStr(&os.kernel_version, &os.kernel_version_len, "unknown");
    }
}

fn readMacosKernelVersion(os: *OsInfo) void {
    const uts = std.posix.uname();
    const release = std.mem.sliceTo(&uts.release, 0);
    if (release.len > 0) {
        setStr(&os.kernel_version, &os.kernel_version_len, release);
    } else {
        setStr(&os.kernel_version, &os.kernel_version_len, "unknown");
    }
}

// ==================== Full OS Name ====================

fn readFullOsName(os: *OsInfo) void {
    switch (builtin.os.tag) {
        .linux => readLinuxOsName(os),
        .windows => readWindowsOsName(os),
        else => setStr(&os.full_name, &os.full_name_len, @tagName(builtin.os.tag)),
    }
}

fn readLinuxOsName(os: *OsInfo) void {
    const file = std.fs.openFileAbsolute("/etc/os-release", .{}) catch {
        setStr(&os.full_name, &os.full_name_len, "Linux");
        return;
    };
    defer file.close();
    var buf: [4096]u8 = undefined;
    const n = file.read(&buf) catch {
        setStr(&os.full_name, &os.full_name_len, "Linux");
        return;
    };
    var lines = std.mem.splitScalar(u8, buf[0..n], '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "PRETTY_NAME=")) {
            var val = line["PRETTY_NAME=".len..];
            if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') {
                val = val[1 .. val.len - 1];
            }
            setStr(&os.full_name, &os.full_name_len, val);
            return;
        }
    }
    setStr(&os.full_name, &os.full_name_len, "Linux");
}

fn readWindowsOsName(os: *OsInfo) void {
    const windows = std.os.windows;
    const advapi32 = struct {
        const HKEY = *opaque {};
        const LSTATUS = windows.LONG;
        extern "advapi32" fn RegOpenKeyExA(hKey: HKEY, lpSubKey: [*:0]const u8, ulOptions: windows.DWORD, samDesired: windows.DWORD, phkResult: *HKEY) callconv(.winapi) LSTATUS;
        extern "advapi32" fn RegQueryValueExA(hKey: HKEY, lpValueName: [*:0]const u8, lpReserved: ?*windows.DWORD, lpType: ?*windows.DWORD, lpData: ?[*]u8, lpcbData: ?*windows.DWORD) callconv(.winapi) LSTATUS;
        extern "advapi32" fn RegCloseKey(hKey: HKEY) callconv(.winapi) LSTATUS;
    };

    const HKEY_LOCAL_MACHINE: advapi32.HKEY = @ptrFromInt(0x80000002);
    const KEY_READ: windows.DWORD = 0x20019;

    var hkey: advapi32.HKEY = undefined;
    if (advapi32.RegOpenKeyExA(HKEY_LOCAL_MACHINE, "SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion", 0, KEY_READ, &hkey) != 0) {
        setStr(&os.full_name, &os.full_name_len, "Windows");
        return;
    }
    defer _ = advapi32.RegCloseKey(hkey);

    var product_name: [128]u8 = undefined;
    var product_len: windows.DWORD = @intCast(product_name.len);
    var display_ver: [32]u8 = undefined;
    var display_len: windows.DWORD = @intCast(display_ver.len);

    const has_product = advapi32.RegQueryValueExA(hkey, "ProductName", null, null, &product_name, &product_len) == 0;
    const has_display = advapi32.RegQueryValueExA(hkey, "DisplayVersion", null, null, &display_ver, &display_len) == 0;

    if (has_product and product_len > 1) {
        const pn = product_name[0 .. product_len - 1]; // exclude null terminator
        if (has_display and display_len > 1) {
            const dv = display_ver[0 .. display_len - 1];
            const s = std.fmt.bufPrint(&os.full_name, "{s} {s} [{s}]", .{ pn, dv, os.archName() }) catch {
                setStr(&os.full_name, &os.full_name_len, pn);
                return;
            };
            os.full_name_len = s.len;
        } else {
            setStr(&os.full_name, &os.full_name_len, pn);
        }
    } else {
        setStr(&os.full_name, &os.full_name_len, "Windows");
    }
}

// ==================== Uptime ====================

fn readUptime(os: *OsInfo) void {
    switch (builtin.os.tag) {
        .linux => readLinuxUptime(os),
        .windows => readWindowsUptime(os),
        else => {},
    }
}

fn readLinuxUptime(os: *OsInfo) void {
    const file = std.fs.openFileAbsolute("/proc/uptime", .{}) catch return;
    defer file.close();
    var buf: [64]u8 = undefined;
    const n = file.read(&buf) catch return;
    const content = buf[0..n];
    const space = std.mem.indexOf(u8, content, " ") orelse content.len;
    const up_str = content[0..space];
    // Parse integer part
    const dot = std.mem.indexOf(u8, up_str, ".") orelse up_str.len;
    os.uptime_seconds = std.fmt.parseInt(u64, up_str[0..dot], 10) catch 0;
}

fn readWindowsUptime(os: *OsInfo) void {
    const k32 = struct {
        extern "kernel32" fn GetTickCount64() callconv(.winapi) u64;
    };
    os.uptime_seconds = k32.GetTickCount64() / 1000;
}

// ==================== Timezone ====================

fn readTimezone(os: *OsInfo) void {
    switch (builtin.os.tag) {
        .linux => readLinuxTimezone(os),
        .windows => readWindowsTimezone(os),
        else => setStr(&os.timezone, &os.timezone_len, "unknown"),
    }
}

fn readLinuxTimezone(os: *OsInfo) void {
    const file = std.fs.openFileAbsolute("/etc/timezone", .{}) catch {
        setStr(&os.timezone, &os.timezone_len, "unknown");
        return;
    };
    defer file.close();
    var buf: [64]u8 = undefined;
    const n = file.read(&buf) catch {
        setStr(&os.timezone, &os.timezone_len, "unknown");
        return;
    };
    const tz = std.mem.trim(u8, buf[0..n], " \t\n\r");
    setStr(&os.timezone, &os.timezone_len, tz);
}

fn readWindowsTimezone(os: *OsInfo) void {
    const windows = std.os.windows;
    const TIME_ZONE_INFORMATION = extern struct {
        Bias: windows.LONG,
        StandardName: [32]u16,
        StandardDate: extern struct { y: u16, m: u16, dow: u16, d: u16, h: u16, min: u16, s: u16, ms: u16 },
        StandardBias: windows.LONG,
        DaylightName: [32]u16,
        DaylightDate: extern struct { y: u16, m: u16, dow: u16, d: u16, h: u16, min: u16, s: u16, ms: u16 },
        DaylightBias: windows.LONG,
    };
    const k32 = struct {
        extern "kernel32" fn GetTimeZoneInformation(lpTimeZoneInformation: *TIME_ZONE_INFORMATION) callconv(.winapi) windows.DWORD;
    };
    var tzi: TIME_ZONE_INFORMATION = std.mem.zeroes(TIME_ZONE_INFORMATION);
    _ = k32.GetTimeZoneInformation(&tzi);
    const bias_minutes = -tzi.Bias;
    const hours = @divTrunc(bias_minutes, 60);
    const mins = @mod(bias_minutes, 60);
    const abs_mins: u32 = if (mins < 0) @intCast(-mins) else @intCast(mins);
    const sign: u8 = if (bias_minutes >= 0) '+' else '-';
    const abs_hours: u32 = if (hours < 0) @intCast(-hours) else @intCast(hours);
    const s = std.fmt.bufPrint(&os.timezone, "UTC{c}{d:0>2}:{d:0>2}", .{
        sign, abs_hours, abs_mins,
    }) catch {
        setStr(&os.timezone, &os.timezone_len, "unknown");
        return;
    };
    os.timezone_len = s.len;
}

// ==================== Disk Space ====================

fn readDiskSpace(disk: *DiskInfo) void {
    switch (builtin.os.tag) {
        .linux => readLinuxDiskSpace(disk),
        .windows => readWindowsDiskSpace(disk),
        else => {},
    }
}

fn readLinuxDiskSpace(disk: *DiskInfo) void {
    const file = std.fs.openFileAbsolute("/proc/mounts", .{}) catch return;
    defer file.close();
    var buf: [8192]u8 = undefined;
    const n = file.read(&buf) catch return;
    var lines = std.mem.splitScalar(u8, buf[0..n], '\n');
    while (lines.next()) |line| {
        if (disk.drive_count >= disk.drives.len) break;
        var fields = std.mem.splitScalar(u8, line, ' ');
        const dev = fields.next() orelse continue;
        const mount = fields.next() orelse continue;
        const fstype = fields.next() orelse continue;
        // Filter: only real filesystems
        if (!std.mem.startsWith(u8, dev, "/dev/")) continue;
        const valid_fs = [_][]const u8{ "ext4", "ext3", "ext2", "xfs", "btrfs", "zfs", "f2fs", "ntfs", "vfat", "exfat" };
        var is_valid = false;
        for (valid_fs) |vf| {
            if (std.mem.eql(u8, fstype, vf)) {
                is_valid = true;
                break;
            }
        }
        if (!is_valid) continue;

        // Use Linux statfs syscall directly
        const LinuxStatfs = extern struct {
            f_type: isize,
            f_bsize: isize,
            f_blocks: isize,
            f_bfree: isize,
            f_bavail: isize,
            f_files: isize,
            f_ffree: isize,
            f_fsid: [2]i32,
            f_namelen: isize,
            f_frsize: isize,
            f_flags: isize,
            f_spare: [4]isize,
        };

        // We need a null-terminated path string for the syscall
        var path_buf: [256]u8 = undefined;
        if (mount.len >= path_buf.len) continue;
        @memcpy(path_buf[0..mount.len], mount);
        path_buf[mount.len] = 0;
        const path_ptr: [*:0]const u8 = @ptrCast(&path_buf);

        var statbuf: LinuxStatfs = undefined;
        const rc = std.os.linux.syscall2(.statfs, @intFromPtr(path_ptr), @intFromPtr(&statbuf));
        const signed_rc: isize = @bitCast(rc);
        if (signed_rc < 0) continue;

        const idx = disk.drive_count;
        const entry = &disk.drives[idx];
        setStr(&entry.mount_point, &entry.mount_point_len, mount);
        const block_size: u64 = @intCast(statbuf.f_bsize);
        entry.total_bytes = block_size * @as(u64, @intCast(statbuf.f_blocks));
        entry.free_bytes = block_size * @as(u64, @intCast(statbuf.f_bavail));
        disk.drive_count += 1;
    }
}

fn readWindowsDiskSpace(disk: *DiskInfo) void {
    const windows = std.os.windows;
    const k32 = struct {
        extern "kernel32" fn GetLogicalDriveStringsA(nBufferLength: windows.DWORD, lpBuffer: [*]u8) callconv(.winapi) windows.DWORD;
        extern "kernel32" fn GetDiskFreeSpaceExA(lpDirectoryName: [*:0]const u8, lpFreeBytesAvailableToCaller: ?*u64, lpTotalNumberOfBytes: ?*u64, lpTotalNumberOfFreeBytes: ?*u64) callconv(.winapi) windows.BOOL;
    };

    var drive_buf: [256]u8 = undefined;
    const len = k32.GetLogicalDriveStringsA(@intCast(drive_buf.len), &drive_buf);
    if (len == 0) return;

    var i: usize = 0;
    while (i < len and disk.drive_count < disk.drives.len) {
        const start = i;
        while (i < len and drive_buf[i] != 0) : (i += 1) {}
        if (i == start) break;
        const drive_str = drive_buf[start..i];
        i += 1; // skip null terminator

        // Build null-terminated string
        var path_buf: [8]u8 = undefined;
        if (drive_str.len >= path_buf.len) continue;
        @memcpy(path_buf[0..drive_str.len], drive_str);
        path_buf[drive_str.len] = 0;
        const path: [*:0]const u8 = @ptrCast(&path_buf);

        var total_bytes: u64 = 0;
        var free_bytes: u64 = 0;
        if (k32.GetDiskFreeSpaceExA(path, null, &total_bytes, &free_bytes) != 0) {
            const idx = disk.drive_count;
            const entry = &disk.drives[idx];
            // Show drive letter (e.g., "C:")
            if (drive_str.len >= 2) {
                setStr(&entry.mount_point, &entry.mount_point_len, drive_str[0..2]);
            } else {
                setStr(&entry.mount_point, &entry.mount_point_len, drive_str);
            }
            entry.total_bytes = total_bytes;
            entry.free_bytes = free_bytes;
            disk.drive_count += 1;
        }
    }
}

// ==================== Virtualization ====================

fn readVirtualization(virt: *VirtInfo) void {
    if (builtin.cpu.arch == .x86_64 or builtin.cpu.arch == .x86) {
        // CPUID leaf 1, ECX bit 31 = hypervisor present
        const r = cpuid(1);
        if ((r.ecx >> 31) & 1 == 1) {
            // Read hypervisor vendor string from leaf 0x40000000
            const hv = cpuid(0x40000000);
            var vendor: [12]u8 = undefined;
            @memcpy(vendor[0..4], std.mem.asBytes(&hv.ebx));
            @memcpy(vendor[4..8], std.mem.asBytes(&hv.ecx));
            @memcpy(vendor[8..12], std.mem.asBytes(&hv.edx));

            if (std.mem.startsWith(u8, &vendor, "Microsoft Hv")) {
                setStr(&virt.hypervisor, &virt.hypervisor_len, "Hyper-V");
            } else if (std.mem.startsWith(u8, &vendor, "VMwareVMware")) {
                setStr(&virt.hypervisor, &virt.hypervisor_len, "VMware");
            } else if (std.mem.startsWith(u8, &vendor, "KVMKVMKVM")) {
                setStr(&virt.hypervisor, &virt.hypervisor_len, "KVM");
            } else if (std.mem.startsWith(u8, &vendor, "XenVMMXenVMM")) {
                setStr(&virt.hypervisor, &virt.hypervisor_len, "Xen");
            } else if (std.mem.startsWith(u8, &vendor, "VBoxVBoxVBox")) {
                setStr(&virt.hypervisor, &virt.hypervisor_len, "VirtualBox");
            } else {
                setStr(&virt.hypervisor, &virt.hypervisor_len, std.mem.trim(u8, &vendor, "\x00 "));
            }
        }
    }

    // Linux: check DMI
    if (builtin.os.tag == .linux and virt.hypervisor_len == 0) {
        const file = std.fs.openFileAbsolute("/sys/class/dmi/id/sys_vendor", .{}) catch return;
        defer file.close();
        var buf: [128]u8 = undefined;
        const n = file.read(&buf) catch return;
        const vendor = std.mem.trim(u8, buf[0..n], " \t\n\r");
        if (std.mem.indexOf(u8, vendor, "QEMU") != null) {
            setStr(&virt.hypervisor, &virt.hypervisor_len, "QEMU/KVM");
        } else if (std.mem.indexOf(u8, vendor, "VMware") != null) {
            setStr(&virt.hypervisor, &virt.hypervisor_len, "VMware");
        } else if (std.mem.indexOf(u8, vendor, "Microsoft") != null) {
            setStr(&virt.hypervisor, &virt.hypervisor_len, "Hyper-V");
        }
    }
}

// ==================== System Load ====================

fn readLoad(load: *LoadInfo) void {
    switch (builtin.os.tag) {
        .linux => readLinuxLoad(load),
        else => {},
    }
}

fn readLinuxLoad(load: *LoadInfo) void {
    const file = std.fs.openFileAbsolute("/proc/loadavg", .{}) catch return;
    defer file.close();
    var buf: [64]u8 = undefined;
    const n = file.read(&buf) catch return;
    var fields = std.mem.splitScalar(u8, buf[0..n], ' ');
    if (fields.next()) |f1| load.load_1 = std.fmt.parseFloat(f64, f1) catch 0;
    if (fields.next()) |f2| load.load_5 = std.fmt.parseFloat(f64, f2) catch 0;
    if (fields.next()) |f3| load.load_15 = std.fmt.parseFloat(f64, f3) catch 0;
}

// ==================== CPUID Helpers ====================

const CpuidResult = struct { eax: u32, ebx: u32, ecx: u32, edx: u32 };

fn cpuid(leaf: u32) CpuidResult {
    return cpuidEx(leaf, 0);
}

fn cpuidEx(leaf: u32, subleaf: u32) CpuidResult {
    var eax: u32 = undefined;
    var ebx: u32 = undefined;
    var ecx: u32 = undefined;
    var edx: u32 = undefined;
    asm volatile ("cpuid"
        : [_eax] "={eax}" (eax),
          [_ebx] "={ebx}" (ebx),
          [_ecx] "={ecx}" (ecx),
          [_edx] "={edx}" (edx),
        : [_leaf] "{eax}" (leaf),
          [_sub] "{ecx}" (subleaf),
    );
    return .{ .eax = eax, .ebx = ebx, .ecx = ecx, .edx = edx };
}

// ==================== Utilities ====================

fn setStr(buf: []u8, len: *usize, src: []const u8) void {
    const copy_len = @min(src.len, buf.len);
    @memcpy(buf[0..copy_len], src[0..copy_len]);
    len.* = copy_len;
}

fn formatUptime(buf: []u8, seconds: u64) []const u8 {
    const days = seconds / 86400;
    const hours = (seconds % 86400) / 3600;
    const mins = (seconds % 3600) / 60;
    return std.fmt.bufPrint(buf, "{d}d {d}h {d}m", .{ days, hours, mins }) catch "?";
}

// ==================== Print ====================

pub fn printInfo(w: *std.Io.Writer, info: *const SystemInfo, lang: cli.Language, caps: output.TermCaps) !void {
    try output.printSectionHeader(w, output.tr(lang, "系统信息", "System Information", "システム情報"), caps);

    try output.printKeyValue(w, output.tr(lang, "主机名", "Hostname", "ホスト名"), info.os.hostName(), caps);
    if (info.os.full_name_len > 0) {
        try output.printKeyValue(w, output.tr(lang, "操作系统", "OS", "OS"), info.os.fullName(), caps);
    } else {
        try output.printKeyValue(w, output.tr(lang, "操作系统", "OS", "OS"), info.os.osName(), caps);
    }
    try output.printKeyValue(w, output.tr(lang, "架构", "Architecture", "アーキテクチャ"), info.os.archName(), caps);
    try output.printKeyValue(w, output.tr(lang, "内核版本", "Kernel", "カーネル"), info.os.kernelVer(), caps);

    // CPU
    try output.printKeyValue(w, output.tr(lang, "CPU 型号", "CPU Model", "CPUモデル"), info.cpu.modelName(), caps);

    var core_buf: [64]u8 = undefined;
    const core_str = std.fmt.bufPrint(&core_buf, "{d} Core(s), {d} Thread(s)", .{
        info.cpu.physical_cores, info.cpu.logical_threads,
    }) catch "?";
    try output.printKeyValue(w, output.tr(lang, "CPU 核心", "CPU Cores", "CPUコア"), core_str, caps);

    if (info.cpu.l1_cache_kb > 0 or info.cpu.l2_cache_kb > 0 or info.cpu.l3_cache_kb > 0) {
        var cache_buf: [128]u8 = undefined;
        const cache_str = blk: {
            if (info.cpu.l3_cache_kb > 0) {
                break :blk std.fmt.bufPrint(&cache_buf, "L1: {d} KB / L2: {d} KB / L3: {d} KB", .{
                    info.cpu.l1_cache_kb, info.cpu.l2_cache_kb, info.cpu.l3_cache_kb,
                }) catch "?";
            } else if (info.cpu.l2_cache_kb > 0) {
                break :blk std.fmt.bufPrint(&cache_buf, "L1: {d} KB / L2: {d} KB", .{
                    info.cpu.l1_cache_kb, info.cpu.l2_cache_kb,
                }) catch "?";
            } else {
                break :blk std.fmt.bufPrint(&cache_buf, "L1: {d} KB", .{info.cpu.l1_cache_kb}) catch "?";
            }
        };
        try output.printKeyValue(w, output.tr(lang, "CPU 缓存", "CPU Cache", "CPUキャッシュ"), cache_str, caps);
    }

    // Virtualization
    if (info.virt.hypervisor_len > 0) {
        try output.printKeyValue(w, output.tr(lang, "虚拟化", "Virtualization", "仮想化"), info.virt.hypervisorName(), caps);
    }

    // Memory
    var mem_buf: [128]u8 = undefined;
    var used_buf: [64]u8 = undefined;
    var total_buf: [64]u8 = undefined;
    const used_bytes = if (info.mem.total_bytes > info.mem.available_bytes) info.mem.total_bytes - info.mem.available_bytes else 0;
    const used_str = output.formatSize(&used_buf, used_bytes);
    const total_str = output.formatSize(&total_buf, info.mem.total_bytes);
    const mem_str = std.fmt.bufPrint(&mem_buf, "{s} / {s}", .{ used_str, total_str }) catch "?";
    try output.printKeyValue(w, output.tr(lang, "内存", "Memory", "メモリ"), mem_str, caps);

    if (info.mem.swap_total_bytes > 0) {
        var swap_buf: [128]u8 = undefined;
        var su_buf: [64]u8 = undefined;
        var st_buf: [64]u8 = undefined;
        const su_str = output.formatSize(&su_buf, info.mem.swap_used_bytes);
        const st_str = output.formatSize(&st_buf, info.mem.swap_total_bytes);
        const swap_str = std.fmt.bufPrint(&swap_buf, "{s} / {s}", .{ su_str, st_str }) catch "?";
        try output.printKeyValue(w, output.tr(lang, "交换分区", "Swap", "スワップ"), swap_str, caps);
    }

    // Disks
    for (info.disk.drives[0..info.disk.drive_count]) |*drive| {
        var disk_buf: [128]u8 = undefined;
        var df_buf: [64]u8 = undefined;
        var dt_buf: [64]u8 = undefined;
        const used_disk = if (drive.total_bytes > drive.free_bytes) drive.total_bytes - drive.free_bytes else 0;
        const df_str = output.formatSize(&df_buf, used_disk);
        const dt_str = output.formatSize(&dt_buf, drive.total_bytes);
        const pct: u64 = if (drive.total_bytes > 0) (used_disk * 100) / drive.total_bytes else 0;
        const disk_str = std.fmt.bufPrint(&disk_buf, "{s} / {s} [{d}%] {s}", .{
            df_str, dt_str, pct, drive.mountPoint(),
        }) catch "?";
        try output.printKeyValue(w, output.tr(lang, "硬盘空间", "Disk", "ディスク"), disk_str, caps);
    }

    // Uptime
    if (info.os.uptime_seconds > 0) {
        var up_buf: [64]u8 = undefined;
        const up_str = formatUptime(&up_buf, info.os.uptime_seconds);
        try output.printKeyValue(w, output.tr(lang, "运行时间", "Uptime", "稼働時間"), up_str, caps);
    }

    // Timezone
    if (info.os.timezone_len > 0) {
        try output.printKeyValue(w, output.tr(lang, "时区", "Timezone", "タイムゾーン"), info.os.timezoneName(), caps);
    }

    // Load
    if (info.load.load_1 > 0 or info.load.load_5 > 0 or info.load.load_15 > 0) {
        var load_buf: [64]u8 = undefined;
        const load_str = std.fmt.bufPrint(&load_buf, "{d:.2} / {d:.2} / {d:.2}", .{
            info.load.load_1, info.load.load_5, info.load.load_15,
        }) catch "?";
        try output.printKeyValue(w, output.tr(lang, "系统负载", "Load Average", "システム負荷"), load_str, caps);
    }
}
