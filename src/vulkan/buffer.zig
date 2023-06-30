const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");

const VmaAllocator = memory.VmaAllocator;

pub const Buffer = struct {
    pub const Config = struct {
        element_size: u32,
        element_count: u32,
        usage: c.VkBufferUsageFlags,
        sharing_mode: c.VkSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        memory_usage: c.VmaMemoryUsage = c.VMA_MEMORY_USAGE_AUTO,
    };

    handle: c.VkBuffer = null,
    allocation: c.VmaAllocation = null,
    element_size: u32 = undefined,
    element_count: u32 = undefined,

    pub fn init(vma: *VmaAllocator, config: *const Config) !Buffer {
        var self: Buffer = .{};
        self.element_size = config.element_size;
        self.element_count = config.element_count;
        errdefer self.deinit(vma);

        const buffer_create_info = &c.VkBufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .size = config.element_size * config.element_count,
            .usage = config.usage,
            .sharingMode = config.sharing_mode,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
        };

        const allocation_create_info = &c.VmaAllocationCreateInfo{
            .flags = c.VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
            .usage = config.memory_usage,
            .requiredFlags = 0,
            .preferredFlags = 0,
            .memoryTypeBits = 0,
            .pool = null,
            .pUserData = null,
            .priority = 0,
        };

        try utility.checkResult(c.vmaCreateBuffer(vma.handle, buffer_create_info, allocation_create_info, &self.handle, &self.allocation, null));

        return self;
    }

    pub fn deinit(self: *Buffer, vma: *VmaAllocator) void {
        if (self.handle != null) {
            c.vmaDestroyBuffer(vma.handle, self.handle, self.allocation);
        }
        self.* = undefined;
    }

    pub fn map(self: *Buffer, vma: *VmaAllocator, comptime T: type) ![]T {
        std.debug.assert(self.element_size == @sizeOf(T));

        var data: ?*anyopaque = undefined;
        try utility.checkResult(c.vmaMapMemory(vma.handle, self.allocation, &data));
        return @ptrCast([*]T, @alignCast(4, data))[0..self.element_count];
    }

    pub fn unmap(self: *Buffer, vma: *VmaAllocator) void {
        c.vmaUnmapMemory(vma.handle, self.allocation);
    }

    pub fn upload(self: *Buffer, vma: *VmaAllocator, comptime T: type, elements: []const T) !void {
        std.debug.assert(self.element_count >= elements.len);

        var mapped_elements = try self.map(vma, T);
        defer self.unmap(vma);

        @memcpy(mapped_elements, elements);
    }
};
