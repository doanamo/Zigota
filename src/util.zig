const std = @import("std");

pub fn range(len: usize) []const u0 {
    // NOTE Will be made obsolete with Zig 0.11.0
    return @as([*]u0, undefined)[0..len];
}

pub fn kilobytes(comptime n: usize) usize {
    return n * 1024;
}

pub fn megabytes(comptime n: usize) usize {
    return n * 1024 * 1024;
}

pub fn gigabytes(comptime n: usize) usize {
    return n * 1024 * 1024 * 1024;
}
