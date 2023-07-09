const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = utility.log_scoped;

const Device = @import("device.zig").Device;

pub const DescriptorPool = struct {
    device: *Device = undefined,
    handle: c.VkDescriptorPool = null,

    pub fn init(self: *DescriptorPool, device: *Device, params: struct {
        max_set_count: u32,
        uniform_buffer_count: u32,
    }) !void {
        self.device = device;
        errdefer self.deinit();

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

        utility.checkResult(c.vkCreateDescriptorPool.?(self.device.handle, &pool_create_info, memory.allocation_callbacks, &self.handle)) catch {
            log.err("Failed to create descriptor pool", .{});
            return error.FailedToCreateDescriptorPool;
        };
    }

    pub fn deinit(self: *DescriptorPool) void {
        if (self.handle != null) {
            c.vkDestroyDescriptorPool.?(self.device.handle, self.handle, memory.allocation_callbacks);
        }
        self.* = undefined;
    }
};
