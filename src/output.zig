const std = @import("std");
const cli = @import("cli.zig");
const terminal = @import("terminal.zig");

pub const TermCaps = terminal.TermCaps;

pub const Color = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const dim = "\x1b[2m";

    pub const miku_cyan = "\x1b[38;2;57;197;187m";
    pub const miku_teal = "\x1b[38;2;0;170;170m";
    pub const miku_dark = "\x1b[38;2;20;120;120m";
    pub const miku_light = "\x1b[38;2;134;220;215m";
    pub const miku_accent = "\x1b[38;2;225;80;126m";
    pub const miku_pink = "\x1b[38;2;238;130;170m";
    pub const miku_white = "\x1b[38;2;230;245;245m";
    pub const miku_gray = "\x1b[38;2;140;180;178m";
    pub const miku_green = "\x1b[38;2;80;200;160m";
    pub const miku_yellow = "\x1b[38;2;230;200;80m";
    pub const miku_red = "\x1b[38;2;220;80;80m";

    pub const bg_miku = "\x1b[48;2;57;197;187m";
    pub const bg_dark = "\x1b[48;2;20;40;40m";
};

// ==================== Terminal-Aware Helpers ====================

fn c(caps: TermCaps, code: []const u8) []const u8 {
    return if (caps.color) code else "";
}

fn contentWidth(caps: TermCaps) u32 {
    const w = if (caps.width > 4) caps.width - 4 else 40;
    return @max(w, 40);
}

// Box-drawing characters with ASCII fallback
fn boxTopLeft(caps: TermCaps) []const u8 {
    return if (caps.unicode) "╔" else "+";
}
fn boxTopRight(caps: TermCaps) []const u8 {
    return if (caps.unicode) "╗" else "+";
}
fn boxBottomLeft(caps: TermCaps) []const u8 {
    return if (caps.unicode) "╚" else "+";
}
fn boxBottomRight(caps: TermCaps) []const u8 {
    return if (caps.unicode) "╝" else "+";
}
fn boxHorizontal(caps: TermCaps) []const u8 {
    return if (caps.unicode) "═" else "=";
}
fn boxVertical(caps: TermCaps) []const u8 {
    return if (caps.unicode) "║" else "|";
}
fn boxSeparator(caps: TermCaps) []const u8 {
    return if (caps.unicode) "─" else "-";
}
fn boxFooter(caps: TermCaps) []const u8 {
    return if (caps.unicode) "═" else "=";
}

// ==================== CJK Display Width ====================

pub fn displayWidth(s: []const u8) u32 {
    var width: u32 = 0;
    var i: usize = 0;
    while (i < s.len) {
        const byte = s[i];
        const seq_len: usize = if (byte < 0x80)
            1
        else if (byte < 0xE0)
            2
        else if (byte < 0xF0)
            3
        else
            4;
        if (i + seq_len > s.len) break;

        if (seq_len == 1) {
            width += 1;
        } else {
            var cp: u21 = switch (seq_len) {
                2 => @as(u21, byte & 0x1F) << 6 | @as(u21, s[i + 1] & 0x3F),
                3 => @as(u21, byte & 0x0F) << 12 | @as(u21, s[i + 1] & 0x3F) << 6 | @as(u21, s[i + 2] & 0x3F),
                4 => @as(u21, byte & 0x07) << 18 | @as(u21, s[i + 1] & 0x3F) << 12 | @as(u21, s[i + 2] & 0x3F) << 6 | @as(u21, s[i + 3] & 0x3F),
                else => 0,
            };
            _ = &cp;
            width += if (isCjkWide(cp)) @as(u32, 2) else @as(u32, 1);
        }
        i += seq_len;
    }
    return width;
}

fn isCjkWide(cp: u21) bool {
    return (cp >= 0x1100 and cp <= 0x115F) or
        (cp >= 0x2E80 and cp <= 0x303E) or
        (cp >= 0x3040 and cp <= 0x33BF) or
        (cp >= 0x3400 and cp <= 0x4DBF) or
        (cp >= 0x4E00 and cp <= 0x9FFF) or
        (cp >= 0xA000 and cp <= 0xA4CF) or
        (cp >= 0xAC00 and cp <= 0xD7AF) or
        (cp >= 0xF900 and cp <= 0xFAFF) or
        (cp >= 0xFE30 and cp <= 0xFE4F) or
        (cp >= 0xFF01 and cp <= 0xFF60) or
        (cp >= 0xFFE0 and cp <= 0xFFE6) or
        (cp >= 0x20000 and cp <= 0x2FA1F);
}

fn writePadded(w: *std.Io.Writer, s: []const u8, target_width: u32) !void {
    try w.print("{s}", .{s});
    const actual = displayWidth(s);
    if (actual < target_width) {
        var remaining = target_width - actual;
        while (remaining > 0) : (remaining -= 1) {
            try w.print(" ", .{});
        }
    }
}

// ==================== Output Functions ====================

pub fn printBanner(w: *std.Io.Writer, caps: TermCaps) !void {
    const inner = contentWidth(caps);
    const ART_WIDTH: u32 = 42;

    if (caps.unicode and inner >= ART_WIDTH) {
        const art = [_][]const u8{
            "     ███████╗███████╗███╗   ██╗██╗████████",
            "     ╚══███╔╝██╔════╝████╗  ██║██║╚══██╔═╝",
            "       ███╔╝ █████╗  ██╔██╗ ██║██║   ██║  ",
            "      ███╔╝  ██╔══╝  ██║╚██╗██║██║   ██║  ",
            "     ███████╗███████╗██║ ╚████║██║   ██║  ",
            "     ╚══════╝╚══════╝╚═╝  ╚═══╝╚═╝   ╚═╝  ",
        };

        try w.print("{s}{s}", .{ c(caps, Color.miku_cyan), c(caps, Color.bold) });

        // Top border
        try printBoxBorder(w, caps, inner, boxTopLeft(caps), boxTopRight(caps));

        // Empty line
        try printBoxRow(w, caps, inner, "");

        // Art lines centered
        for (art) |line| {
            try printBoxRow(w, caps, inner, line);
        }

        // Empty line
        try printBoxRow(w, caps, inner, "");

        // Bottom border
        try printBoxBorder(w, caps, inner, boxBottomLeft(caps), boxBottomRight(caps));

        try w.print("{s}", .{c(caps, Color.reset)});
    }
    try w.print("{s}  ZENITH - System Benchmark Tool v{s}{s}\n\n", .{
        c(caps, Color.miku_light),
        @import("main.zig").version,
        c(caps, Color.reset),
    });
}

fn printBoxBorder(w: *std.Io.Writer, caps: TermCaps, inner: u32, left: []const u8, right: []const u8) !void {
    try w.print("  {s}", .{left});
    var i: u32 = 0;
    while (i < inner) : (i += 1) {
        try w.print("{s}", .{boxHorizontal(caps)});
    }
    try w.print("{s}\n", .{right});
}

fn printBoxRow(w: *std.Io.Writer, caps: TermCaps, inner: u32, content: []const u8) !void {
    const content_w = displayWidth(content);
    const padding = if (inner > content_w) inner - content_w else 0;
    const left_pad = padding / 2;
    const right_pad = padding - left_pad;

    try w.print("  {s}", .{boxVertical(caps)});
    var j: u32 = 0;
    while (j < left_pad) : (j += 1) {
        try w.print(" ", .{});
    }
    if (content.len > 0) {
        try w.print("{s}", .{content});
    }
    var k: u32 = 0;
    while (k < right_pad) : (k += 1) {
        try w.print(" ", .{});
    }
    try w.print("{s}\n", .{boxVertical(caps)});
}

pub fn printSectionHeader(w: *std.Io.Writer, title: []const u8, caps: TermCaps) !void {
    const inner_width = contentWidth(caps);
    const title_len: u32 = displayWidth(title);
    const padding = if (inner_width > title_len) inner_width - title_len else 0;
    const left_pad = padding / 2;
    const right_pad = padding - left_pad;

    try w.print("\n{s}{s}", .{ c(caps, Color.miku_accent), c(caps, Color.bold) });
    try w.print("  {s}", .{boxTopLeft(caps)});
    var i: u32 = 0;
    while (i < inner_width) : (i += 1) {
        try w.print("{s}", .{boxHorizontal(caps)});
    }
    try w.print("{s}\n", .{boxTopRight(caps)});

    try w.print("  {s}", .{boxVertical(caps)});
    var j: u32 = 0;
    while (j < left_pad) : (j += 1) {
        try w.print(" ", .{});
    }
    try w.print("{s}{s}{s}{s}", .{ c(caps, Color.miku_cyan), title, c(caps, Color.miku_accent), c(caps, Color.bold) });
    var k: u32 = 0;
    while (k < right_pad) : (k += 1) {
        try w.print(" ", .{});
    }
    try w.print("{s}\n", .{boxVertical(caps)});

    try w.print("  {s}", .{boxBottomLeft(caps)});
    var l: u32 = 0;
    while (l < inner_width) : (l += 1) {
        try w.print("{s}", .{boxHorizontal(caps)});
    }
    try w.print("{s}{s}\n", .{ boxBottomRight(caps), c(caps, Color.reset) });
}

pub fn printKeyValue(w: *std.Io.Writer, key: []const u8, value: []const u8, caps: TermCaps) !void {
    try w.print("  {s}", .{c(caps, Color.miku_gray)});
    try writePadded(w, key, 20);
    try w.print("{s}{s}{s}{s}\n", .{ c(caps, Color.reset), c(caps, Color.miku_white), value, c(caps, Color.reset) });
}

pub fn printKeyValueFmt(w: *std.Io.Writer, key: []const u8, caps: TermCaps, comptime fmt: []const u8, args: anytype) !void {
    try w.print("  {s}", .{c(caps, Color.miku_gray)});
    try writePadded(w, key, 20);
    try w.print("{s}{s}", .{ c(caps, Color.reset), c(caps, Color.miku_white) });
    try w.print(fmt, args);
    try w.print("{s}\n", .{c(caps, Color.reset)});
}

pub fn printResult(w: *std.Io.Writer, label: []const u8, value: []const u8, unit: []const u8, caps: TermCaps) !void {
    try w.print("  {s}", .{c(caps, Color.miku_light)});
    try writePadded(w, label, 24);
    try w.print("{s}{s}", .{ c(caps, Color.miku_cyan), c(caps, Color.bold) });
    try writePadded(w, value, 16);
    try w.print("{s}{s}{s}\n", .{ c(caps, Color.reset), c(caps, Color.miku_gray), unit });
}

pub fn printScore(w: *std.Io.Writer, label: []const u8, score: f64, caps: TermCaps) !void {
    const clr = if (score >= 8000)
        Color.miku_pink
    else if (score >= 4000)
        Color.miku_cyan
    else if (score >= 2000)
        Color.miku_yellow
    else
        Color.miku_red;

    var score_buf: [32]u8 = undefined;
    const score_str = std.fmt.bufPrint(&score_buf, "{d:.0}", .{score}) catch "?";

    try w.print("  {s}", .{c(caps, Color.miku_light)});
    try writePadded(w, label, 24);
    try w.print("{s}{s}{s}{s} pts{s}\n", .{ c(caps, clr), c(caps, Color.bold), score_str, c(caps, Color.reset), c(caps, Color.miku_gray) });
}

pub fn printSeparator(w: *std.Io.Writer, caps: TermCaps) !void {
    const width = contentWidth(caps);
    try w.print("  {s}", .{c(caps, Color.miku_pink)});
    var i: u32 = 0;
    while (i < width) : (i += 1) {
        try w.print("{s}", .{boxSeparator(caps)});
    }
    try w.print("{s}\n", .{c(caps, Color.reset)});
}

pub fn printFooter(w: *std.Io.Writer, elapsed_s: f64, caps: TermCaps) !void {
    const minutes: u32 = @intFromFloat(elapsed_s / 60.0);
    const seconds: u32 = @intFromFloat(@mod(elapsed_s, 60.0));
    const width = contentWidth(caps);

    try w.print("\n{s}{s}  ", .{ c(caps, Color.miku_accent), c(caps, Color.bold) });
    var i: u32 = 0;
    while (i < width) : (i += 1) {
        try w.print("{s}", .{boxFooter(caps)});
    }
    try w.print("\n{s}", .{c(caps, Color.reset)});
    try w.print("  {s}Duration: {d}m {d}s{s}\n", .{
        c(caps, Color.miku_gray),
        minutes,
        seconds,
        c(caps, Color.reset),
    });
}

pub fn tr(lang: cli.Language, zh: []const u8, en: []const u8, ja: []const u8) []const u8 {
    return switch (lang) {
        .zh => zh,
        .en => en,
        .ja => ja,
    };
}

pub fn formatSize(buf: []u8, bytes: u64) []const u8 {
    const units = [_][]const u8{ "B", "KB", "MB", "GB", "TB" };
    var value: f64 = @floatFromInt(bytes);
    var unit_idx: usize = 0;
    while (value >= 1024.0 and unit_idx < units.len - 1) {
        value /= 1024.0;
        unit_idx += 1;
    }
    const written = std.fmt.bufPrint(buf, "{d:.2} {s}", .{ value, units[unit_idx] }) catch return "???";
    return written;
}

pub fn formatSpeed(buf: []u8, bytes_per_sec: f64) []const u8 {
    const units = [_][]const u8{ "B/s", "KB/s", "MB/s", "GB/s" };
    var value: f64 = bytes_per_sec;
    var unit_idx: usize = 0;
    while (value >= 1024.0 and unit_idx < units.len - 1) {
        value /= 1024.0;
        unit_idx += 1;
    }
    const written = std.fmt.bufPrint(buf, "{d:.2} {s}", .{ value, units[unit_idx] }) catch return "???";
    return written;
}

// ==================== Progress Bar ====================

pub const Progress = struct {
    w: *std.Io.Writer,
    caps: TermCaps,
    step: u32 = 0,
    total: u32,

    pub fn next(self: *Progress, label: []const u8) void {
        self.render(label);
        self.step += 1;
    }

    fn render(self: *Progress, label: []const u8) void {
        const bar_width: u32 = 20;
        const filled: u32 = if (self.total > 0) self.step * bar_width / self.total else 0;
        const percent: u32 = if (self.total > 0) self.step * 100 / self.total else 0;

        // Clear the line
        if (self.caps.color) {
            self.w.print("\x1b[2K\r", .{}) catch return;
        } else {
            self.w.print("\r", .{}) catch return;
        }

        // Bar
        self.w.print("  {s}[", .{c(self.caps, Color.miku_cyan)}) catch return;
        var i: u32 = 0;
        while (i < bar_width) : (i += 1) {
            if (i < filled) {
                self.w.print("{s}", .{if (self.caps.unicode) "█" else "#"}) catch return;
            } else {
                self.w.print("{s}", .{if (self.caps.unicode) "░" else "."}) catch return;
            }
        }

        // Percentage + label
        self.w.print("] {s}{d}%{s}  {s}", .{
            c(self.caps, Color.miku_white),
            percent,
            c(self.caps, Color.reset),
            c(self.caps, Color.miku_gray),
        }) catch return;
        self.w.print("{s}{s}", .{ label, c(self.caps, Color.reset) }) catch return;
        self.w.flush() catch return;
    }

    pub fn clear(self: *Progress) void {
        if (self.caps.color) {
            self.w.print("\x1b[2K\r", .{}) catch return;
        } else {
            self.w.print("\r", .{}) catch return;
            var i: u32 = 0;
            while (i < 80) : (i += 1) {
                self.w.print(" ", .{}) catch return;
            }
            self.w.print("\r", .{}) catch return;
        }
        self.w.flush() catch return;
    }
};
