const std = @import("std");
const c = @import("../c/c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const Vulkan = @import("vulkan.zig").Vulkan;
const VmaAllocator = @import("vma.zig").VmaAllocator;

pub const Image = struct {
    vulkan: *Vulkan = undefined,
    handle: c.VkImage = null,
    allocation: c.VmaAllocation = undefined,
    usage_flags: c.VkImageUsageFlags = 0,

    pub fn init(self: *Image, vulkan: *Vulkan, params: struct {
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
    }) !void {
        errdefer self.deinit();

        self.vulkan = vulkan;
        self.usage_flags = params.usage_flags;

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
        check(c.vmaCreateImage(vulkan.vma.handle, &image_create_info, &allocation_create_info, &self.handle, &self.allocation, &allocation_info)) catch |err| {
            log.err("Failed to create image: {}", .{err});
            return error.FailedToCreateImage;
        };

        log.info("Created {s} ({} bytes)", .{ self.getName(), allocation_info.size });
    }

    pub fn deinit(self: *Image) void {
        if (self.handle != null) {
            c.vmaDestroyImage(self.vulkan.vma.handle, self.handle, self.allocation);
        }

        self.* = .{};
    }

    pub fn getName(self: *Image) []const u8 {
        if (self.usage_flags & c.VK_IMAGE_USAGE_TRANSFER_SRC_BIT != 0) {
            return "staging image";
        } else if (self.usage_flags & c.VK_IMAGE_USAGE_SAMPLED_BIT != 0) {
            return "sampled image";
        } else if (self.usage_flags & c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT != 0) {
            return "color attachment image";
        } else if (self.usage_flags & c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT != 0) {
            return "depth stencil attachment image";
        } else {
            return "image";
        }
    }
};
