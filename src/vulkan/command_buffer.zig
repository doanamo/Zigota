const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const Vulkan = @import("../vulkan.zig").Vulkan;
const Device = @import("device.zig").Device;
const CommandPool = @import("command_pool.zig").CommandPool;

pub const CommandBuffer = struct {
    vulkan: *Vulkan = undefined,
    handle: c.VkCommandBuffer = null,
    command_pool: c.VkCommandPool = null,

    pub fn init(self: *CommandBuffer, vulkan: *Vulkan, params: struct {
        command_pool: *CommandPool,
        level: c.VkCommandBufferLevel,
    }) !void {
        errdefer self.deinit();

        self.vulkan = vulkan;
        self.command_pool = params.command_pool.handle;

        const allocate_info = c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = params.command_pool.handle,
            .level = params.level,
            .commandBufferCount = 1,
        };

        check(c.vkAllocateCommandBuffers.?(vulkan.device.handle, &allocate_info, &self.handle)) catch |err| {
            log.err("Failed to create command buffer: {}", .{err});
            return error.FailedToCreateCommandBuffer;
        };
    }

    pub fn deinit(self: *CommandBuffer) void {
        if (self.handle != null) {
            c.vkFreeCommandBuffers.?(self.vulkan.device.handle, self.command_pool, 1, &self.handle);
        }

        self.* = .{};
    }
};
