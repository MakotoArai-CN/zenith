const std = @import("std");
const compat = @import("compat.zig");

pub const Timer = struct {
    start_ns: u64,

    pub fn start() Timer {
        return .{ .start_ns = nowNs() };
    }

    pub fn elapsed(self: Timer) f64 {
        const ns = nowNs() - self.start_ns;
        return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
    }

    pub fn elapsedMs(self: Timer) f64 {
        return self.elapsed() * 1000.0;
    }

    pub fn elapsedNs(self: Timer) u64 {
        return nowNs() - self.start_ns;
    }
};

inline fn nowNs() u64 {
    if (comptime compat.is_zig_016) {
        const ts = std.Io.Clock.now(.awake, compat.io());
        return @intCast(ts.toNanoseconds());
    } else {
        return @intCast(std.time.nanoTimestamp());
    }
}
