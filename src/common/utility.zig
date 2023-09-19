const std = @import("std");
const builtin = @import("builtin");

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

pub fn findExecutable(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    const arguments: []const []const u8 = if (builtin.os.tag == .windows)
        &[_][]const u8{ "where", name }
    else
        &[_][]const u8{ "which", name };

    var process = std.ChildProcess.init(arguments, allocator);
    process.stderr_behavior = .Close;
    process.stdout_behavior = .Pipe;
    process.stdin_behavior = .Close;
    try process.spawn();

    const output = try process.stdout.?.readToEndAlloc(allocator, 1024);
    errdefer allocator.free(output);

    switch (try process.wait()) {
        .Exited => |code| {
            if (code != 0)
                return error.NotFound;
        },
        else => return error.ProcessFailed,
    }

    const path = std.mem.trimRight(u8, output, " \t\r\n");
    return if (path.len != 0) path else error.NotFound;
}
