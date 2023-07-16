const std = @import("std");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Config);

const WindowConfig = @import("glfw/window.zig").Window.Config;
const VulkanConfig = @import("vulkan.zig").Vulkan.Config;

pub const Config = struct {
    window: WindowConfig = undefined,
    vulkan: VulkanConfig = undefined,

    pub fn init(self: *Config) !void {
        log.info("Loading config from file...", .{});

        const content = try std.fs.cwd().readFileAllocOptions(
            memory.default_allocator,
            "config.json",
            utility.megabytes(1),
            null,
            @alignOf(u8),
            null,
        );
        defer memory.default_allocator.free(content);

        var parsed = try std.json.parseFromSlice(Config, memory.default_allocator, content, .{});
        defer parsed.deinit();

        self.* = parsed.value;
    }
};
