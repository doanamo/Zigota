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
