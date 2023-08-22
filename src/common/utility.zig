const std = @import("std");

pub fn kilobytes(comptime n: usize) usize {
    return n * 1024;
}

pub fn megabytes(comptime n: usize) usize {
    return n * 1024 * 1024;
}

pub fn gigabytes(comptime n: usize) usize {
    return n * 1024 * 1024 * 1024;
}

pub fn toKilobytes(n: usize) f64 {
    return @as(f64, @floatFromInt(n)) / 1024;
}

pub fn toMegabytes(n: usize) f64 {
    return @as(f64, @floatFromInt(n)) / 1024 / 1024;
}

pub fn toGigabytes(n: usize) f64 {
    return @as(f64, @floatFromInt(n)) / 1024 / 1024 / 1024;
}

pub fn fromKilobytes(n: usize) usize {
    return n * 1024;
}

pub fn fromMegabytes(n: usize) usize {
    return n * 1024 * 1024;
}

pub fn fromGigabytes(n: usize) usize {
    return n * 1024 * 1024 * 1024;
}
