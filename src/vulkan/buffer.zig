const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const VmaAllocator = @import("vma.zig").VmaAllocator;

pub const Buffer = struct {
    handle: c.VkBuffer = null,
    allocation: c.VmaAllocation = undefined,
    vma: *VmaAllocator = undefined,
    size: usize = 0,

    pub fn init(vma: *VmaAllocator, params: struct {
        size: usize,
        usage_flags: c.VkBufferUsageFlags,
        sharing_mode: c.VkSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        memory_usage: c.VmaMemoryUsage = c.VMA_MEMORY_USAGE_AUTO,
        memory_flags: c.VmaPoolCreateFlags = 0,
        memory_priority: f32 = 0.0,
    }) !Buffer {
        var self = Buffer{};
        errdefer self.deinit();

        self.vma = vma;
        self.size = params.size;

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
            .priority = params.memory_priority,
        };

        var allocation_info: c.VmaAllocationInfo = undefined;
        check(c.vmaCreateBuffer(vma.handle, &buffer_create_info, &allocation_create_info, &self.handle, &self.allocation, &allocation_info)) catch {
            log.err("Failed to create buffer (size {} bytes)", .{params.size});
            return error.FailedToCreateBuffer;
        };

        log.info("Created buffer (size {} bytes)", .{params.size});
        return self;
    }

    pub fn deinit(self: *Buffer) void {
        if (self.handle != null) {
            c.vmaDestroyBuffer(self.vma.handle, self.handle, self.allocation);
        }
        self.* = undefined;
    }

    pub fn map(self: *Buffer) ![]u8 {
        std.debug.assert(self.vma.handle != null);
        std.debug.assert(self.allocation != null);

        var data: ?*anyopaque = undefined;
        try check(c.vmaMapMemory(self.vma.handle, self.allocation, &data));
        return @as([*]u8, @ptrCast(@alignCast(data)))[0..self.size];
    }

    pub fn unmap(self: *Buffer) void {
        std.debug.assert(self.vma.handle != null);
        std.debug.assert(self.allocation != null);
        c.vmaUnmapMemory(self.vma.handle, self.allocation);
    }

    pub fn upload(self: *Buffer, data: []const u8, offset: usize) !void {
        const mapped_data = try self.map();
        defer self.unmap();

        std.debug.assert(offset + data.len <= self.size);
        @memcpy(mapped_data[offset .. offset + data.len], data);
    }

    pub fn flush(self: *Buffer, offset: usize, size: usize) !void {
        std.debug.assert(self.vma.handle != null);
        std.debug.assert(self.allocation != null);
        try check(c.vmaFlushAllocation(self.vma.handle, self.allocation, offset, size));
    }
};
