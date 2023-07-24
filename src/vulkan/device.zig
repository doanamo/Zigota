const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const Instance = @import("instance.zig").Instance;
const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;
const Surface = @import("surface.zig").Surface;

pub const Device = struct {
    pub const Queue = struct {
        type: QueueType = undefined,
        handle: c.VkQueue = null,
        index: u32 = queue_index_invalid,
    };

    pub const QueueType = enum {
        Graphics,
        Compute,
        Transfer,
    };

    const queue_type_count = @typeInfo(QueueType).Enum.fields.len;
    const queue_index_invalid = std.math.maxInt(u32);

    handle: c.VkDevice = null,
    queues: [queue_type_count]Queue = undefined,

    pub fn init(physical_device: *const PhysicalDevice, surface: *Surface) !Device {
        var self = Device{};
        errdefer self.deinit();

        self.selectQueueFamilies(physical_device, surface) catch |err| {
            log.err("Failed to select queue families: {}", .{err});
            return error.FailedToSelectQueueFamilies;
        };

        self.createLogicalDevice(physical_device) catch |err| {
            log.err("Failed to create logical device: {}", .{err});
            return error.FailedToCreateLogicalDevice;
        };

        return self;
    }

    pub fn deinit(self: *Device) void {
        // Queues are owned by logical device
        self.destroyLogicalDevice();
        self.* = undefined;
    }

    fn selectQueueFamilies(self: *Device, physical_device: *const PhysicalDevice, surface: *const Surface) !void {
        log.info("Selecting queue families...", .{});

        var queue_family_count: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties.?(physical_device.handle, &queue_family_count, null);

        const queue_families = try memory.default_allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
        defer memory.default_allocator.free(queue_families);
        c.vkGetPhysicalDeviceQueueFamilyProperties.?(physical_device.handle, &queue_family_count, queue_families.ptr);

        var queue_graphics = self.getQueue(.Graphics);
        for (queue_families, 0..) |queue_family, i| {
            if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT == 0)
                continue;

            var present_support: c.VkBool32 = c.VK_FALSE;
            try check(c.vkGetPhysicalDeviceSurfaceSupportKHR.?(physical_device.handle, @intCast(i), surface.handle, &present_support));
            if (present_support == c.VK_FALSE)
                continue;

            queue_graphics.type = .Graphics;
            queue_graphics.index = @intCast(i);
        }

        if (queue_graphics.index == queue_index_invalid) {
            log.err("Failed to find graphics queue family", .{});
            return error.FailedToFindGraphicsQueueFamily;
        }

        var queue_compute = self.getQueue(.Compute);
        for (queue_families, 0..) |queue_family, i| {
            if (queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT == 0)
                continue;

            if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0)
                continue;

            queue_compute.type = .Compute;
            queue_compute.index = @intCast(i);
        }

        if (queue_compute.index == queue_index_invalid) {
            log.err("Failed to find compute queue family", .{});
            return error.FailedToFindComputeQueueFamily;
        }

        var queue_transfer = self.getQueue(.Transfer);
        for (queue_families, 0..) |queue_family, i| {
            if (queue_family.queueFlags & c.VK_QUEUE_TRANSFER_BIT == 0)
                continue;

            if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0)
                continue;

            if (queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0)
                continue;

            queue_transfer.type = .Transfer;
            queue_transfer.index = @intCast(i);
        }

        if (queue_transfer.index == queue_index_invalid) {
            log.err("Failed to find transfer queue family", .{});
            return error.FailedToFindTransferQueueFamily;
        }

        if (queue_graphics.index == queue_compute.index or
            queue_compute.index == queue_transfer.index or
            queue_transfer.index == queue_graphics.index)
        {
            log.err("Failed to find unique queue families", .{});
            return error.FailedToFindUniqueQueueFamilies;
        }
    }

    fn createLogicalDevice(self: *Device, physical_device: *const PhysicalDevice) !void {
        log.info("Creating logical device...", .{});

        var queue_graphics = self.getQueue(.Graphics);
        var queue_compute = self.getQueue(.Compute);
        var queue_transfer = self.getQueue(.Transfer);

        const queue_priorities = [1]f32{1.0};
        const queue_create_infos = [3]c.VkDeviceQueueCreateInfo{
            c.VkDeviceQueueCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .queueFamilyIndex = queue_graphics.index,
                .queueCount = 1,
                .pQueuePriorities = &queue_priorities,
            },
            c.VkDeviceQueueCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .queueFamilyIndex = queue_compute.index,
                .queueCount = 1,
                .pQueuePriorities = &queue_priorities,
            },
            c.VkDeviceQueueCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .queueFamilyIndex = queue_transfer.index,
                .queueCount = 1,
                .pQueuePriorities = &queue_priorities,
            },
        };

        const validation_layers = Instance.getValidationLayers();
        const extensions = getExtensions();
        const features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);

        var dynamic_rendering_features = c.VkPhysicalDeviceDynamicRenderingFeatures{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_DYNAMIC_RENDERING_FEATURES,
            .pNext = null,
            .dynamicRendering = c.VK_TRUE,
        };

        var synchronization_features = c.VkPhysicalDeviceSynchronization2Features{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_SYNCHRONIZATION_2_FEATURES,
            .pNext = &dynamic_rendering_features,
            .synchronization2 = c.VK_TRUE,
        };

        var timeline_semaphore_features = c.VkPhysicalDeviceTimelineSemaphoreFeatures{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES,
            .pNext = @ptrCast(&synchronization_features),
            .timelineSemaphore = c.VK_TRUE,
        };

        var memory_priority_feature = c.VkPhysicalDeviceMemoryPriorityFeaturesEXT{
            .sType = c.VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_MEMORY_PRIORITY_FEATURES_EXT,
            .pNext = &timeline_semaphore_features,
            .memoryPriority = c.VK_TRUE,
        };

        const create_info = c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = &memory_priority_feature,
            .flags = 0,
            .queueCreateInfoCount = queue_create_infos.len,
            .pQueueCreateInfos = &queue_create_infos,
            .enabledLayerCount = if (std.debug.runtime_safety) @intCast(validation_layers.len) else 0,
            .ppEnabledLayerNames = if (std.debug.runtime_safety) &validation_layers else null,
            .enabledExtensionCount = @intCast(extensions.len),
            .ppEnabledExtensionNames = &extensions,
            .pEnabledFeatures = &features,
        };

        try check(c.vkCreateDevice.?(physical_device.handle, &create_info, memory.vulkan_allocator, &self.handle));
        c.volkLoadDevice(self.handle);

        c.vkGetDeviceQueue.?(self.handle, queue_graphics.index, 0, &queue_graphics.handle);
        c.vkGetDeviceQueue.?(self.handle, queue_compute.index, 0, &queue_compute.handle);
        c.vkGetDeviceQueue.?(self.handle, queue_transfer.index, 0, &queue_transfer.handle);
    }

    fn destroyLogicalDevice(self: *Device) void {
        if (self.handle != null) {
            c.vkDestroyDevice.?(self.handle, memory.vulkan_allocator);
        }
    }

    pub fn waitIdle(self: *Device) void {
        std.debug.assert(self.handle != null);
        check(c.vkDeviceWaitIdle.?(self.handle)) catch unreachable;
    }

    pub fn submit(self: *Device, params: struct {
        queue_type: QueueType,
        submit_count: u32,
        submit_info: *const c.VkSubmitInfo,
        fence: c.VkFence,
    }) !void {
        try check(c.vkQueueSubmit.?(
            self.getQueue(params.queue_type).handle,
            params.submit_count,
            params.submit_info,
            params.fence,
        ));
    }

    pub fn getQueue(self: *Device, queue_type: QueueType) *Queue {
        return &self.queues[@intFromEnum(queue_type)];
    }

    fn getExtensions() [1][*c]const u8 {
        return [_][*c]const u8{
            c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        };
    }
};
