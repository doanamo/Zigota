const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const log = utility.log_scoped;

const Device = @import("device.zig").Device;
const CommandPool = @import("command_pool.zig").CommandPool;

pub const CommandBuffer = struct {
    handle: c.VkCommandBuffer = null,

    pub fn init(device: *Device, command_pool: *CommandPool, level: c.VkCommandBufferLevel) !CommandBuffer {
        var self = CommandBuffer{};
        errdefer self.deinit(device, command_pool);

        const allocate_info = &c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = command_pool.handle,
            .level = level,
            .commandBufferCount = 1,
        };

        utility.checkResult(c.vkAllocateCommandBuffers.?(device.handle, allocate_info, &self.handle)) catch {
            log.err("Failed to create command buffer", .{});
            return error.FailedToCreateCommandBuffer;
        };

        return self;
    }

    pub fn deinit(self: *CommandBuffer, device: *Device, command_pool: *CommandPool) void {
        if (self.handle != null) {
            c.vkFreeCommandBuffers.?(device.handle, command_pool.handle, 1, &self.handle);
        }
        self.* = undefined;
    }
};
