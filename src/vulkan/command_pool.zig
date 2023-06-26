const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = utility.log_scoped;

const Device = @import("device.zig").Device;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;

pub const CommandPool = struct {
    handle: c.VkCommandPool = null,
    device: *Device = undefined,

    pub fn init(device: *Device) !CommandPool {
        var self = CommandPool{};
        self.device = device;
        errdefer self.deinit();

        const create_info = &c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = device.queue_graphics_index,
        };

        utility.checkResult(c.vkCreateCommandPool.?(device.handle, create_info, memory.vulkan_allocator, &self.handle)) catch {
            log.err("Failed to create command pool", .{});
            return error.FailedToCreateCommandPool;
        };

        return self;
    }

    pub fn deinit(self: *CommandPool) void {
        if (self.handle != null) {
            c.vkDestroyCommandPool.?(self.device.handle, self.handle, memory.vulkan_allocator);
        }
        self.* = undefined;
    }

    pub fn reset(self: *CommandPool) !void {
        try utility.checkResult(c.vkResetCommandPool.?(self.device.handle, self.handle, 0));
    }
};
