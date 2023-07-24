const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const Instance = @import("instance.zig").Instance;
const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;
const Device = @import("device.zig").Device;

pub const VmaAllocator = struct {
    handle: c.VmaAllocator = null,

    pub fn init(instance: *Instance, physical_device: *PhysicalDevice, device: *Device) !VmaAllocator {
        log.info("Creating memory allocator...", .{});

        var self = VmaAllocator{};
        errdefer self.deinit();

        const vulkan_functions = c.VmaVulkanFunctions{
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

        const allocator_create_info = c.VmaAllocatorCreateInfo{
            .flags = 0,
            .physicalDevice = physical_device.handle,
            .device = device.handle,
            .preferredLargeHeapBlockSize = 0,
            .pAllocationCallbacks = memory.vulkan_allocator,
            .pDeviceMemoryCallbacks = null,
            .pHeapSizeLimit = null,
            .pVulkanFunctions = &vulkan_functions,
            .instance = instance.handle,
            .vulkanApiVersion = Instance.api_version,
            .pTypeExternalMemoryHandleTypes = null,
        };

        check(c.vmaCreateAllocator(&allocator_create_info, &self.handle)) catch |err| {
            log.err("Failed to create memory allocator: {}", .{err});
            return error.FailedToCreateMemoryAllocator;
        };

        return self;
    }

    pub fn deinit(self: *VmaAllocator) void {
        if (self.handle != null) {
            c.vmaDestroyAllocator(self.handle);
        }
    }
};
