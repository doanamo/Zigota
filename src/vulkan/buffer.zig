const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const VmaAllocator = @import("vma.zig").VmaAllocator;

pub const Buffer = struct {
    handle: c.VkBuffer = null,
    allocation: c.VmaAllocation = null,
    size: usize = 0,

    pub fn init(self: *Buffer, vma: *VmaAllocator, params: struct {
        size: usize,
        usage_flags: c.VkBufferUsageFlags,
        sharing_mode: c.VkSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        memory_usage: c.VmaMemoryUsage = c.VMA_MEMORY_USAGE_AUTO,
        memory_flags: c.VmaPoolCreateFlags = 0,
    }) !void {
        log.info("Creating buffer... (size {} bytes)", .{params.size});
        self.size = params.size;
        errdefer self.deinit(vma);

        const buffer_create_info = c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = params.size,
            .usage = params.usage_flags,
            .sharingMode = params.sharing_mode,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        const allocation_create_info = c.VmaAllocationCreateInfo{
            .flags = params.memory_flags,
            .usage = params.memory_usage,
            .requiredFlags = 0,
            .preferredFlags = 0,
            .memoryTypeBits = 0,
            .pool = null,
            .pUserData = null,
            .priority = 0,
        };

        var allocation_info: c.VmaAllocationInfo = undefined;
        try check(c.vmaCreateBuffer(vma.handle, &buffer_create_info, &allocation_create_info, &self.handle, &self.allocation, &allocation_info));
    }

    pub fn deinit(self: *Buffer, vma: *VmaAllocator) void {
        if (self.handle != null) {
            c.vmaDestroyBuffer(vma.handle, self.handle, self.allocation);
        }
        self.* = undefined;
    }

    pub fn map(self: *Buffer, vma: *VmaAllocator) ![]u8 {
        var data: ?*anyopaque = undefined;
        try check(c.vmaMapMemory(vma.handle, self.allocation, &data));
        return @as([*]u8, @ptrCast(@alignCast(data)))[0..self.size];
    }

    pub fn unmap(self: *Buffer, vma: *VmaAllocator) void {
        c.vmaUnmapMemory(vma.handle, self.allocation);
    }

    pub fn upload(self: *Buffer, vma: *VmaAllocator, data: []const u8, offset: usize) !void {
        const mapped_data = try self.map(vma);
        defer self.unmap(vma);

        @memcpy(mapped_data[offset .. offset + data.len], data);
    }

    pub fn flush(self: *Buffer, vma: *VmaAllocator, offset: usize, size: usize) !void {
        try check(c.vmaFlushAllocation(vma.handle, self.allocation, offset, size));
    }
};
