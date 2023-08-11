const std = @import("std");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Config);

const WindowConfig = @import("glfw/window.zig").Window.Config;
const VulkanConfig = @import("vulkan.zig").Vulkan.Config;

pub const Config = struct {
    const path = "config.json";

    window: WindowConfig = undefined,
    vulkan: VulkanConfig = undefined,

    pub fn load(self: *Config) !void {
        const content = std.fs.cwd().readFileAllocOptions(
            memory.default_allocator,
            path,
            utility.megabytes(1),
            null,
            @alignOf(u8),
            null,
        ) catch |err| {
            log.err("Failed to load config from \"{s}\" file: {}", .{ path, err });
            return error.FailedToLoadConfigFile;
        };
        defer memory.default_allocator.free(content);

        var parsed = std.json.parseFromSlice(Config, memory.default_allocator, content, .{}) catch |err| {
            log.err("Failed to parse config from \"{s}\" file: {}", .{ path, err });
            return error.FailedToParseConfigFile;
        };
        defer parsed.deinit();
        self.* = parsed.value;

        log.info("Loaded config from \"{s}\" file", .{path});
    }
};
