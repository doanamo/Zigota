const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const Device = @import("device.zig").Device;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;

pub const CommandPool = struct {
    handle: c.VkCommandPool = null,
    device: *Device = undefined,

    pub fn init(self: *CommandPool, device: *Device, params: struct {
        queue: Device.QueueType,
        flags: c.VkCommandPoolCreateFlags = 0,
    }) !void {
        errdefer self.deinit();

        self.device = device;

        const create_info = c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = params.flags,
            .queueFamilyIndex = device.getQueue(params.queue).index,
        };

        check(c.vkCreateCommandPool.?(device.handle, &create_info, memory.vulkan_allocator, &self.handle)) catch |err| {
            log.err("Failed to create command pool: {}", .{err});
            return error.FailedToCreateCommandPool;
        };
    }

    pub fn deinit(self: *CommandPool) void {
        if (self.handle != null) {
            c.vkDestroyCommandPool.?(self.device.handle, self.handle, memory.vulkan_allocator);
        }
        self.* = .{};
    }

    pub fn reset(self: *CommandPool) !void {
        try check(c.vkResetCommandPool.?(self.device.handle, self.handle, 0));
    }
};
