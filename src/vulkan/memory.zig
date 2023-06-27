pub usingnamespace @import("../memory.zig");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const log = utility.log_scoped;

const Instance = @import("instance.zig").Instance;
const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;
const Device = @import("device.zig").Device;

pub const vulkan_allocator = &c.VkAllocationCallbacks{
    .pUserData = null,
    .pfnAllocation = &vulkanAllocationCallback,
    .pfnReallocation = &vulkanReallocationCallback,
    .pfnFree = &vulkanFreeCallback,
    .pfnInternalAllocation = null,
    .pfnInternalFree = null,
};

fn vulkanAllocationCallback(
    user_data: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: c.VkSystemAllocationScope,
) callconv(.C) ?*anyopaque {
    _ = allocation_scope;
    _ = user_data;
    return c.mi_malloc_aligned(size, alignment);
}

fn vulkanReallocationCallback(
    user_data: ?*anyopaque,
    old_allocation: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: c.VkSystemAllocationScope,
) callconv(.C) ?*anyopaque {
    _ = allocation_scope;
    _ = user_data;
    return c.mi_realloc_aligned(old_allocation, size, alignment);
}

fn vulkanFreeCallback(user_data: ?*anyopaque, allocation: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    c.mi_free(allocation);
}

pub const VmaAllocator = struct {
    handle: c.VmaAllocator = null,

    pub fn init(instance: *Instance, physical_device: *PhysicalDevice, device: *Device) !VmaAllocator {
        log.info("Creating allocator...", .{});

        var self = VmaAllocator{};
        errdefer self.deinit();

        const vulkan_functions = &c.VmaVulkanFunctions{
            .vkGetInstanceProcAddr = c.vkGetInstanceProcAddr,
            .vkGetDeviceProcAddr = c.vkGetDeviceProcAddr,
            .vkGetPhysicalDeviceProperties = c.vkGetPhysicalDeviceProperties,
            .vkGetPhysicalDeviceMemoryProperties = c.vkGetPhysicalDeviceMemoryProperties,
            .vkAllocateMemory = c.vkAllocateMemory,
            .vkFreeMemory = c.vkFreeMemory,
            .vkMapMemory = c.vkMapMemory,
            .vkUnmapMemory = c.vkUnmapMemory,
            .vkFlushMappedMemoryRanges = c.vkFlushMappedMemoryRanges,
            .vkInvalidateMappedMemoryRanges = c.vkInvalidateMappedMemoryRanges,
            .vkBindBufferMemory = c.vkBindBufferMemory,
            .vkBindImageMemory = c.vkBindImageMemory,
            .vkGetBufferMemoryRequirements = c.vkGetBufferMemoryRequirements,
            .vkGetImageMemoryRequirements = c.vkGetImageMemoryRequirements,
            .vkCreateBuffer = c.vkCreateBuffer,
            .vkDestroyBuffer = c.vkDestroyBuffer,
            .vkCreateImage = c.vkCreateImage,
            .vkDestroyImage = c.vkDestroyImage,
            .vkCmdCopyBuffer = c.vkCmdCopyBuffer,
            .vkGetBufferMemoryRequirements2KHR = c.vkGetBufferMemoryRequirements2,
            .vkGetImageMemoryRequirements2KHR = c.vkGetImageMemoryRequirements2,
            .vkBindBufferMemory2KHR = c.vkBindBufferMemory2,
            .vkBindImageMemory2KHR = c.vkBindImageMemory2,
            .vkGetPhysicalDeviceMemoryProperties2KHR = c.vkGetPhysicalDeviceMemoryProperties2,
            .vkGetDeviceBufferMemoryRequirements = c.vkGetDeviceBufferMemoryRequirements,
            .vkGetDeviceImageMemoryRequirements = c.vkGetDeviceImageMemoryRequirements,
        };

        const allocator_create_info = &c.VmaAllocatorCreateInfo{
            .flags = 0,
            .physicalDevice = physical_device.handle,
            .device = device.handle,
            .preferredLargeHeapBlockSize = 0,
            .pAllocationCallbacks = vulkan_allocator,
            .pDeviceMemoryCallbacks = null,
            .pHeapSizeLimit = null,
            .pVulkanFunctions = vulkan_functions,
            .instance = instance.handle,
            .vulkanApiVersion = Instance.api_version,
            .pTypeExternalMemoryHandleTypes = null,
        };

        try utility.checkResult(c.vmaCreateAllocator(allocator_create_info, &self.handle));

        return self;
    }

    pub fn deinit(self: *VmaAllocator) void {
        if (self.handle != null) {
            c.vmaDestroyAllocator(self.handle);
        }
    }
};
