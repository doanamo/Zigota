const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");

const Device = @import("device.zig").Device;
const CommandPool = @import("command_pool.zig").CommandPool;

pub const CommandBuffer = struct {
    handle: c.VkCommandBuffer,

    pub fn init(device: *Device, command_pool: *CommandPool, level: c.VkCommandBufferLevel) !CommandBuffer {
        const allocate_info = &c.VkCommandBufferAllocateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
            .pNext = null,
            .commandPool = command_pool.handle,
            .level = level,
            .commandBufferCount = 1,
        };

        var command_buffer: c.VkCommandBuffer = undefined;
        try utility.checkResult(c.vkAllocateCommandBuffers.?(device.handle, allocate_info, &command_buffer));

        return CommandBuffer{
            .handle = command_buffer,
        };
    }

    pub fn deinit(self: *CommandBuffer, device: *Device, command_pool: *CommandPool) void {
        c.vkFreeCommandBuffers.?(device.handle, command_pool.handle, 1, &self.handle);
        self.* = undefined;
    }
};
