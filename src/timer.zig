const std = @import("std");

pub const Timer = struct {
    start_time: std.time.Instant,

    pub fn start() Timer {
        return .{
            .start_time = std.time.Instant.now() catch unreachable,
        };
    }

    pub fn elapsed(self: Timer) f64 {
        const now = std.time.Instant.now() catch unreachable;
        const ns = now.since(self.start_time);
        return @as(f64, @floatFromInt(ns)) / 1_000_000_000.0;
    }

    pub fn elapsedMs(self: Timer) f64 {
        return self.elapsed() * 1000.0;
    }

    pub fn elapsedNs(self: Timer) u64 {
        const now = std.time.Instant.now() catch unreachable;
        return now.since(self.start_time);
    }
};