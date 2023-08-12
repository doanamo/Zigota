const std = @import("std");
const c = @import("../c/c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const Vulkan = @import("vulkan.zig").Vulkan;
const VmaAllocator = @import("vma.zig").VmaAllocator;
const Bindless = @import("bindless.zig").Bindless;

pub const Buffer = struct {
    vulkan: *Vulkan = undefined,
    handle: c.VkBuffer = null,
    allocation: c.VmaAllocation = null,
    bindless_id: Bindless.IdentifierType = Bindless.invalid_id,
    usage_flags: c.VkBufferUsageFlags = undefined,
    size: usize = undefined,

    pub fn init(self: *Buffer, vulkan: *Vulkan, params: struct {
        size: usize,
        usage_flags: c.VkBufferUsageFlags,
        sharing_mode: c.VkSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        memory_usage: c.VmaMemoryUsage = c.VMA_MEMORY_USAGE_AUTO,
        memory_flags: c.VmaPoolCreateFlags = 0,
        memory_priority: f32 = 0.0,
        bindless: bool = false,
    }) !void {
        errdefer self.deinit();

        self.vulkan = vulkan;
        self.usage_flags = params.usage_flags;
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
        check(c.vmaCreateBuffer(vulkan.vma.handle, &buffer_create_info, &allocation_create_info, &self.handle, &self.allocation, &allocation_info)) catch |err| {
            log.err("Failed to create buffer ({} bytes): {}", .{ params.size, err });
            return error.FailedToCreateBuffer;
        };

        if (params.bindless) {
            self.bindless_id = try vulkan.bindless.registerResource(self);
            std.debug.assert(self.bindless_id != Bindless.invalid_id);
        }

        log.info("Created {s} ({} bytes)", .{ self.getName(), params.size });
    }

    pub fn deinit(self: *Buffer) void {
        if (self.bindless_id != Bindless.invalid_id) {
            self.vulkan.bindless.unregisterResource(self, self.bindless_id);
        }

        if (self.handle != null) {
            c.vmaDestroyBuffer(self.vulkan.vma.handle, self.handle, self.allocation);
        }

        self.* = .{};
    }

    pub fn map(self: *Buffer) ![]u8 {
        std.debug.assert(self.allocation != null);

        var data: ?*anyopaque = undefined;
        try check(c.vmaMapMemory(self.vulkan.vma.handle, self.allocation, &data));
        return @as([*]u8, @ptrCast(@alignCast(data)))[0..self.size];
    }

    pub fn unmap(self: *Buffer) void {
        std.debug.assert(self.allocation != null);
        c.vmaUnmapMemory(self.vulkan.vma.handle, self.allocation);
    }

    pub fn upload(self: *Buffer, data: []const u8, offset: usize) !void {
        const mapped_data = try self.map();
        defer self.unmap();

        std.debug.assert(offset + data.len <= self.size);
        @memcpy(mapped_data[offset..][0..data.len], data);
    }

    pub fn flush(self: *Buffer, offset: usize, size: usize) !void {
        std.debug.assert(self.allocation != null);
        try check(c.vmaFlushAllocation(self.vulkan.vma.handle, self.allocation, offset, size));
    }

    pub fn getName(self: *Buffer) []const u8 {
        if (self.usage_flags & c.VK_BUFFER_USAGE_TRANSFER_SRC_BIT != 0) {
            return "staging buffer";
        } else if (self.usage_flags & c.VK_BUFFER_USAGE_VERTEX_BUFFER_BIT != 0) {
            return "vertex buffer";
        } else if (self.usage_flags & c.VK_BUFFER_USAGE_INDEX_BUFFER_BIT != 0) {
            return "index buffer";
        } else if (self.usage_flags & c.VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT != 0) {
            return "uniform buffer";
        } else {
            return "buffer";
        }
    }
};
