const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const Device = @import("device.zig").Device;

pub const DescriptorPool = struct {
    handle: c.VkDescriptorPool = null,
    device: *Device = undefined,

    pub fn init(device: *Device, params: struct {
        max_set_count: u32,
        uniform_buffer_count: u32,
    }) !DescriptorPool {
        var self = DescriptorPool{};
        errdefer self.deinit();

        self.device = device;

        const pool_create_info = c.VkDescriptorPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .maxSets = params.max_set_count,
            .poolSizeCount = 1,
            .pPoolSizes = &c.VkDescriptorPoolSize{
                .type = c.VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER,
                .descriptorCount = params.uniform_buffer_count,
            },
        };

        check(c.vkCreateDescriptorPool.?(self.device.handle, &pool_create_info, memory.vulkan_allocator, &self.handle)) catch |err| {
            log.err("Failed to create descriptor pool: {}", .{err});
            return error.FailedToCreateDescriptorPool;
        };

        return self;
    }

    pub fn deinit(self: *DescriptorPool) void {
        if (self.handle != null) {
            c.vkDestroyDescriptorPool.?(self.device.handle, self.handle, memory.vulkan_allocator);
        }
        self.* = undefined;
    }
};
