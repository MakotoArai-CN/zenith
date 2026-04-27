const std = @import("std");
const builtin = @import("builtin");
const output = @import("output.zig");
const cli = @import("cli.zig");
const compat = @import("compat.zig");

// ==================== Data Structures ====================

pub const NetworkInfo = struct {
    public_ip: [64]u8 = undefined,
    public_ip_len: usize = 0,
    isp: [128]u8 = undefined,
    isp_len: usize = 0,
    asn: [64]u8 = undefined,
    asn_len: usize = 0,
    location: [128]u8 = undefined,
    location_len: usize = 0,
    local_ip: [64]u8 = undefined,
    local_ip_len: usize = 0,
    nat_type: NatType = .unknown,

    pub fn publicIp(self: *const NetworkInfo) []const u8 {
        return self.public_ip[0..self.public_ip_len];
    }
    pub fn ispName(self: *const NetworkInfo) []const u8 {
        return self.isp[0..self.isp_len];
    }
    pub fn asnStr(self: *const NetworkInfo) []const u8 {
        return self.asn[0..self.asn_len];
    }
    pub fn locationStr(self: *const NetworkInfo) []const u8 {
        return self.location[0..self.location_len];
    }
    pub fn localIp(self: *const NetworkInfo) []const u8 {
        return self.local_ip[0..self.local_ip_len];
    }
};

pub const NatType = enum {
    none,
    nat,
    unknown,

    pub fn label(self: NatType) []const u8 {
        return switch (self) {
            .none => "Direct",
            .nat => "NAT",
            .unknown => "Unknown",
        };
    }
};

// ==================== Collect ====================

pub fn collect(allocator: std.mem.Allocator) NetworkInfo {
    var info: NetworkInfo = .{};

    // Get local IP
    detectLocalIp(&info);

    // Get public IP + geo info from ip-api.com
    fetchPublicInfo(allocator, &info);

    // Determine NAT type
    if (info.public_ip_len > 0 and info.local_ip_len > 0) {
        const pub_ip = info.publicIp();
        const loc_ip = info.localIp();
        if (std.mem.eql(u8, pub_ip, loc_ip)) {
            info.nat_type = .none;
        } else {
            info.nat_type = .nat;
        }
    }

    return info;
}

// ==================== Local IP Detection ====================

fn detectLocalIp(info: *NetworkInfo) void {
    switch (builtin.os.tag) {
        .windows => detectLocalIpWindows(info),
        else => detectLocalIpPosix(info),
    }
}

fn detectLocalIpPosix(info: *NetworkInfo) void {
    // 0.15 used std.posix.{socket,connect,getsockname,close}; 0.16 stripped
    // those out of std.posix. Use libc directly — they're always linked on
    // platforms that reach this branch (musl on Linux, libSystem on macOS,
    // libc on FreeBSD).
    const c = struct {
        const AF_INET: c_int = 2;
        const SOCK_DGRAM: c_int = 2;
        extern "c" fn socket(domain: c_int, type_: c_int, protocol: c_int) c_int;
        extern "c" fn connect(sockfd: c_int, addr: *const sockaddr_in, addrlen: u32) c_int;
        extern "c" fn getsockname(sockfd: c_int, addr: *sockaddr_in, addrlen: *u32) c_int;
        extern "c" fn close(fd: c_int) c_int;
        const sockaddr_in = extern struct {
            family: u16,
            port: u16,
            addr: [4]u8,
            zero: [8]u8,
        };
    };

    const sock = c.socket(c.AF_INET, c.SOCK_DGRAM, 0);
    if (sock < 0) return;
    defer _ = c.close(sock);

    var dest = c.sockaddr_in{
        .family = c.AF_INET,
        .port = std.mem.nativeToBig(u16, 53),
        .addr = .{ 8, 8, 8, 8 },
        .zero = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
    };
    if (c.connect(sock, &dest, @sizeOf(c.sockaddr_in)) != 0) return;

    var local: c.sockaddr_in = undefined;
    var local_len: u32 = @sizeOf(c.sockaddr_in);
    if (c.getsockname(sock, &local, &local_len) != 0) return;

    const ip_str = std.fmt.bufPrint(&info.local_ip, "{d}.{d}.{d}.{d}", .{
        local.addr[0], local.addr[1], local.addr[2], local.addr[3],
    }) catch return;
    info.local_ip_len = ip_str.len;
}

fn detectLocalIpWindows(info: *NetworkInfo) void {
    const ws2 = struct {
        const SOCKET = usize;
        const INVALID_SOCKET: SOCKET = ~@as(SOCKET, 0);
        const AF_INET: c_int = 2;
        const SOCK_DGRAM: c_int = 2;
        const WSADATA = extern struct {
            wVersion: u16,
            wHighVersion: u16,
            iMaxSockets: u16,
            iMaxUdpDg: u16,
            lpVendorInfo: ?[*]u8,
            szDescription: [257]u8,
            szSystemStatus: [129]u8,
        };
        const sockaddr_in = extern struct {
            family: u16 = AF_INET,
            port: u16 = 0,
            addr: [4]u8 = .{ 0, 0, 0, 0 },
            zero: [8]u8 = .{ 0, 0, 0, 0, 0, 0, 0, 0 },
        };

        extern "ws2_32" fn WSAStartup(wVersionRequested: u16, lpWSAData: *WSADATA) callconv(.winapi) c_int;
        extern "ws2_32" fn WSACleanup() callconv(.winapi) c_int;
        extern "ws2_32" fn socket(af: c_int, sock_type: c_int, protocol: c_int) callconv(.winapi) SOCKET;
        extern "ws2_32" fn closesocket(s: SOCKET) callconv(.winapi) c_int;
        extern "ws2_32" fn connect(s: SOCKET, name: *const sockaddr_in, namelen: c_int) callconv(.winapi) c_int;
        extern "ws2_32" fn getsockname(s: SOCKET, name: *sockaddr_in, namelen: *c_int) callconv(.winapi) c_int;
    };

    var wsa_data: ws2.WSADATA = undefined;
    if (ws2.WSAStartup(0x0202, &wsa_data) != 0) return;
    defer _ = ws2.WSACleanup();

    const sock = ws2.socket(ws2.AF_INET, ws2.SOCK_DGRAM, 0);
    if (sock == ws2.INVALID_SOCKET) return;
    defer _ = ws2.closesocket(sock);

    var dest: ws2.sockaddr_in = .{};
    dest.family = ws2.AF_INET;
    dest.port = std.mem.nativeToBig(u16, 53);
    dest.addr = .{ 8, 8, 8, 8 };

    if (ws2.connect(sock, &dest, @sizeOf(ws2.sockaddr_in)) != 0) return;

    var local: ws2.sockaddr_in = .{};
    var local_len: c_int = @sizeOf(ws2.sockaddr_in);
    if (ws2.getsockname(sock, &local, &local_len) != 0) return;

    const ip_str = std.fmt.bufPrint(&info.local_ip, "{d}.{d}.{d}.{d}", .{
        local.addr[0], local.addr[1], local.addr[2], local.addr[3],
    }) catch return;
    info.local_ip_len = ip_str.len;
}

// ==================== Public IP via HTTP ====================

fn fetchPublicInfo(allocator: std.mem.Allocator, info: *NetworkInfo) void {
    var client: std.http.Client = if (comptime compat.is_zig_016)
        .{ .allocator = allocator, .io = compat.io() }
    else
        .{ .allocator = allocator };
    defer client.deinit();

    var body: [4096]u8 = undefined;
    var writer = std.Io.Writer.fixed(&body);

    const result = client.fetch(.{
        .location = .{ .url = "http://ip-api.com/json/?fields=query,isp,as,city,country" },
        .response_writer = &writer,
    }) catch return;

    if (result.status != .ok) return;

    const n = writer.end;
    if (n == 0) return;

    parseIpApiJson(body[0..n], info);
}

fn parseIpApiJson(data: []const u8, info: *NetworkInfo) void {
    // Simple JSON field extraction without std.json (avoid allocator requirement)
    if (extractJsonString(data, "query")) |ip| {
        setStr(&info.public_ip, &info.public_ip_len, ip);
    }
    if (extractJsonString(data, "isp")) |isp| {
        setStr(&info.isp, &info.isp_len, isp);
    }
    if (extractJsonString(data, "as")) |as_str| {
        setStr(&info.asn, &info.asn_len, as_str);
    }

    // Build location string from city + country
    const city = extractJsonString(data, "city");
    const country = extractJsonString(data, "country");
    if (city != null or country != null) {
        var loc_buf: [128]u8 = undefined;
        const loc = if (city != null and country != null)
            std.fmt.bufPrint(&loc_buf, "{s}, {s}", .{ city.?, country.? }) catch return
        else if (city) |c|
            c
        else
            country.?;
        setStr(&info.location, &info.location_len, loc);
    }
}

fn extractJsonString(data: []const u8, key: []const u8) ?[]const u8 {
    // Search for "key":"value" pattern
    var i: usize = 0;
    while (i + key.len + 3 < data.len) : (i += 1) {
        if (data[i] != '"') continue;
        const key_start = i + 1;
        if (key_start + key.len > data.len) continue;
        if (!std.mem.eql(u8, data[key_start..][0..key.len], key)) continue;
        if (key_start + key.len >= data.len or data[key_start + key.len] != '"') continue;

        // Found key, now find the value
        var j = key_start + key.len + 1;
        // Skip whitespace and colon
        while (j < data.len and (data[j] == ' ' or data[j] == ':' or data[j] == '\t')) : (j += 1) {}
        if (j >= data.len or data[j] != '"') continue;
        j += 1; // skip opening quote
        const val_start = j;
        while (j < data.len and data[j] != '"') : (j += 1) {}
        if (j > val_start) {
            return data[val_start..j];
        }
    }
    return null;
}

// ==================== Print ====================

pub fn printInfo(w: *std.Io.Writer, info: *const NetworkInfo, lang: cli.Language, caps: output.TermCaps) !void {
    try output.printSectionHeader(w, output.tr(lang, "网络信息", "Network Information", "ネットワーク情報"), caps);

    if (info.public_ip_len > 0) {
        try output.printKeyValue(w, output.tr(lang, "公网 IP", "Public IP", "パブリックIP"), info.publicIp(), caps);
    }
    if (info.local_ip_len > 0) {
        try output.printKeyValue(w, output.tr(lang, "本地 IP", "Local IP", "ローカルIP"), info.localIp(), caps);
    }
    try output.printKeyValue(w, output.tr(lang, "NAT 类型", "NAT Type", "NATタイプ"), info.nat_type.label(), caps);

    if (info.isp_len > 0) {
        try output.printKeyValue(w, output.tr(lang, "运营商", "ISP", "ISP"), info.ispName(), caps);
    }
    if (info.asn_len > 0) {
        try output.printKeyValue(w, "ASN", info.asnStr(), caps);
    }
    if (info.location_len > 0) {
        try output.printKeyValue(w, output.tr(lang, "位置", "Location", "所在地"), info.locationStr(), caps);
    }
}

// ==================== Utilities ====================

fn setStr(buf: []u8, len: *usize, src: []const u8) void {
    const copy_len = @min(src.len, buf.len);
    @memcpy(buf[0..copy_len], src[0..copy_len]);
    len.* = copy_len;
}
