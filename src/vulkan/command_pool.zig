const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = utility.log_scoped;

const Device = @import("device.zig").Device;

pub const CommandPool = struct {
    handle: c.VkCommandPool = null,

    pub fn init(device: *Device) !CommandPool {
        var self = CommandPool{};
        errdefer self.deinit();

        self.createCommandPool(device) catch {
            log.err("Failed to create command pool", .{});
            return error.FailedToCreateVulkanCommandPool;
        };

        return self;
    }

    pub fn deinit(self: *CommandPool, device: *Device) void {
        if (self.handle != null) {
            c.vkDestroyCommandPool.?(device.handle, self.handle, memory.vulkan_allocator);
        }

        self.* = undefined;
    }

    fn createCommandPool(self: *CommandPool, device: *Device) !void {
        log.info("Creating command pool...", .{});

        const create_info = &c.VkCommandPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
            .pNext = null,
            .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
            .queueFamilyIndex = device.queue_graphics_index,
        };

        try utility.checkResult(c.vkCreateCommandPool.?(device.handle, create_info, memory.vulkan_allocator, &self.handle));
    }
};
