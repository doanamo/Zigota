const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = utility.log_scoped;

const Device = @import("device.zig").Device;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;

pub const CommandPool = struct {
    handle: c.VkCommandPool = null,
    device: *Device = undefined,

    pub fn init(self: *CommandPool, device: *Device, queue_type: Device.QueueType) !void {
        self.device = device;
        errdefer self.deinit();

        const create_info = &c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = device.getQueue(queue_type).index,
        };

        utility.checkResult(c.vkCreateCommandPool.?(device.handle, create_info, memory.allocation_callbacks, &self.handle)) catch {
            log.err("Failed to create command pool", .{});
            return error.FailedToCreateCommandPool;
        };
    }

    pub fn deinit(self: *CommandPool) void {
        if (self.handle != null) {
            c.vkDestroyCommandPool.?(self.device.handle, self.handle, memory.allocation_callbacks);
        }
        self.* = undefined;
    }

    pub fn reset(self: *CommandPool) !void {
        try utility.checkResult(c.vkResetCommandPool.?(self.device.handle, self.handle, 0));
    }
};
