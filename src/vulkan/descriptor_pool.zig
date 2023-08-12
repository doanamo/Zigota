const std = @import("std");
const c = @import("../c/c.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const Vulkan = @import("vulkan.zig").Vulkan;
const Device = @import("device.zig").Device;

pub const DescriptorPool = struct {
    vulkan: *Vulkan = undefined,
    handle: c.VkDescriptorPool = null,

    pub fn init(self: *DescriptorPool, vulkan: *Vulkan, params: struct {
        max_set_count: u32,
        pool_sizes: []const c.VkDescriptorPoolSize,
        flags: c.VkDescriptorPoolCreateFlags = 0,
    }) !void {
        errdefer self.deinit();

        self.vulkan = vulkan;

        const pool_create_info = c.VkDescriptorPoolCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
            .pNext = null,
            .flags = params.flags,
            .maxSets = params.max_set_count,
            .poolSizeCount = @intCast(params.pool_sizes.len),
            .pPoolSizes = params.pool_sizes.ptr,
        };

        check(c.vkCreateDescriptorPool.?(vulkan.device.handle, &pool_create_info, memory.vulkan_allocator, &self.handle)) catch |err| {
            log.err("Failed to create descriptor pool: {}", .{err});
            return error.FailedToCreateDescriptorPool;
        };
    }

    pub fn deinit(self: *DescriptorPool) void {
        if (self.handle != null) {
            c.vkDestroyDescriptorPool.?(self.vulkan.device.handle, self.handle, memory.vulkan_allocator);
        }

        self.* = .{};
    }
};
