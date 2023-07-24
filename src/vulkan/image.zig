const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const VmaAllocator = @import("vma.zig").VmaAllocator;

pub const Image = struct {
    handle: c.VkImage = null,
    allocation: c.VmaAllocation = undefined,
    vma: *VmaAllocator = undefined,

    pub fn init(vma: *VmaAllocator, params: struct {
        format: c.VkFormat,
        extent: c.VkExtent3D,
        usage_flags: c.VkImageUsageFlags,
        mip_levels: u32 = 1,
        array_layers: u32 = 1,
        dimmensions: c.VkImageType = c.VK_IMAGE_TYPE_2D,
        sharing_mode: c.VkSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        memory_usage: c.VmaMemoryUsage = c.VMA_MEMORY_USAGE_AUTO,
        memory_flags: c.VmaPoolCreateFlags = 0,
        memory_priority: f32 = 0.0,
    }) !Image {
        var self = Image{};
        errdefer self.deinit();

        self.vma = vma;

        const image_create_info = c.VkImageCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .imageType = params.dimmensions,
            .format = params.format,
            .extent = params.extent,
            .mipLevels = params.mip_levels,
            .arrayLayers = params.array_layers,
            .samples = c.VK_SAMPLE_COUNT_1_BIT,
            .tiling = c.VK_IMAGE_TILING_OPTIMAL,
            .usage = params.usage_flags,
            .sharingMode = params.sharing_mode,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
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
        check(c.vmaCreateImage(vma.handle, &image_create_info, &allocation_create_info, &self.handle, &self.allocation, &allocation_info)) catch {
            log.err("Failed to create image", .{});
            return error.FailedToCreateImage;
        };

        return self;
    }

    pub fn deinit(self: *Image) void {
        if (self.handle != null) {
            c.vmaDestroyImage(self.vma.handle, self.handle, self.allocation);
        }
        self.* = undefined;
    }
};
