const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);

const Device = @import("device.zig").Device;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;

pub const CommandPool = struct {
    handle: c.VkCommandPool = null,
    device: *Device = undefined,

    pub fn init(self: *CommandPool, device: *Device, params: struct {
        queue: Device.QueueType,
        flags: c.VkCommandPoolCreateFlags = 0,
    }) !void {
        self.device = device;
        errdefer self.deinit();

        const create_info = c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = params.flags,
            .queueFamilyIndex = device.getQueue(params.queue).index,
        };

        utility.checkResult(c.vkCreateCommandPool.?(device.handle, &create_info, memory.vulkan_allocator, &self.handle)) catch {
            log.err("Failed to create command pool", .{});
            return error.FailedToCreateCommandPool;
        };
    }

    pub fn deinit(self: *CommandPool) void {
        if (self.handle != null) {
            c.vkDestroyCommandPool.?(self.device.handle, self.handle, memory.vulkan_allocator);
        }
        self.* = undefined;
    }

    pub fn createBuffer(self: *CommandPool, level: c.VkCommandBufferLevel) !CommandBuffer {
        var command_buffer = CommandBuffer{};
        try command_buffer.init(self.device, self, level);
        return command_buffer;
    }

    pub fn reset(self: *CommandPool) !void {
        try utility.checkResult(c.vkResetCommandPool.?(self.device.handle, self.handle, 0));
    }
};
