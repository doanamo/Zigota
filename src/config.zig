const std = @import("std");
const utility = @import("utility.zig");
const log = std.log.scoped(.Config);

const WindowConfig = @import("glfw/window.zig").WindowConfig;

pub const Config = struct {
    window: WindowConfig = .{},

    pub fn init(self: *Config, allocator: std.mem.Allocator) !void {
        log.info("Loading config from file...", .{});

        const content = try std.fs.cwd().readFileAllocOptions(
            allocator,
            "config.json",
            utility.megabytes(1),
            null,
            @alignOf(u8),
            null,
        );
        defer allocator.free(content);

        self.* = try std.json.parseFromSlice(Config, allocator, content, .{});
    }
};
