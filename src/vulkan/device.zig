const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = utility.log_scoped;

const Instance = @import("instance.zig").Instance;
const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;
const Surface = @import("surface.zig").Surface;

pub const Device = struct {
    handle: c.VkDevice = null,

    queue_graphics: c.VkQueue = undefined,
    queue_graphics_index: u32 = undefined,

    queue_compute: c.VkQueue = undefined,
    queue_compute_index: u32 = undefined,

    queue_transfer: c.VkQueue = undefined,
    queue_transfer_index: u32 = undefined,

    pub fn init(physical_device: *const PhysicalDevice, surface: *Surface, allocator: std.mem.Allocator) !Device {
        var self = Device{};
        errdefer self.deinit();

        self.selectQueueFamilies(physical_device, surface, allocator) catch {
            log.err("Failed to select queue families", .{});
            return error.FailedToSelectQueueFamilies;
        };

        self.createLogicalDevice(physical_device) catch {
            log.err("Failed to create logical device", .{});
            return error.FailedToCreateLogicalDevice;
        };

        return self;
    }

    pub fn deinit(self: *Device) void {
        // Queues are owned by logical device
        self.destroyLogicalDevice();
        self.* = undefined;
    }

    fn selectQueueFamilies(self: *Device, physical_device: *const PhysicalDevice, surface: *const Surface, allocator: std.mem.Allocator) !void {
        log.info("Selecting queue families...", .{});

        var queue_family_count: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties.?(physical_device.handle, &queue_family_count, null);

        const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
        defer allocator.free(queue_families);
        c.vkGetPhysicalDeviceQueueFamilyProperties.?(physical_device.handle, &queue_family_count, queue_families.ptr);

        var queue_graphics_found = false;
        for (queue_families, 0..) |queue_family, i| {
            if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT == 0)
                continue;

            var present_support: c.VkBool32 = c.VK_FALSE;
            try utility.checkResult(c.vkGetPhysicalDeviceSurfaceSupportKHR.?(physical_device.handle, @intCast(u32, i), surface.handle, &present_support));
            if (present_support == c.VK_FALSE)
                continue;

            self.queue_graphics_index = @intCast(u32, i);
            queue_graphics_found = true;
        }

        if (!queue_graphics_found) {
            log.err("Failed to find graphics queue family", .{});
            return error.FailedToFindGraphicsQueueFamily;
        }

        var queue_compute_found = false;
        for (queue_families, 0..) |queue_family, i| {
            if (queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT == 0)
                continue;

            if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0)
                continue;

            self.queue_compute_index = @intCast(u32, i);
            queue_compute_found = true;
        }

        if (!queue_compute_found) {
            log.err("Failed to find compute queue family", .{});
            return error.FailedToFindComputeQueueFamily;
        }

        var queue_transfer_found = false;
        for (queue_families, 0..) |queue_family, i| {
            if (queue_family.queueFlags & c.VK_QUEUE_TRANSFER_BIT == 0)
                continue;

            if (queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0)
                continue;

            if (queue_family.queueFlags & c.VK_QUEUE_COMPUTE_BIT != 0)
                continue;

            self.queue_transfer_index = @intCast(u32, i);
            queue_transfer_found = true;
        }

        if (!queue_transfer_found) {
            log.err("Failed to find transfer queue family", .{});
            return error.FailedToFindTransferQueueFamily;
        }

        if (self.queue_graphics_index == self.queue_compute_index or
            self.queue_compute_index == self.queue_transfer_index or
            self.queue_transfer_index == self.queue_graphics_index)
        {
            log.err("Failed to find unique queue families", .{});
            return error.FailedToFindUniqueQueueFamilies;
        }
    }

    fn createLogicalDevice(self: *Device, physical_device: *const PhysicalDevice) !void {
        log.info("Creating logical device...", .{});

        const queue_priorities = [1]f32{1.0};
        const queue_create_infos = &[3]c.VkDeviceQueueCreateInfo{
            c.VkDeviceQueueCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .queueFamilyIndex = self.queue_graphics_index,
                .queueCount = 1,
                .pQueuePriorities = &queue_priorities,
            },
            c.VkDeviceQueueCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .queueFamilyIndex = self.queue_compute_index,
                .queueCount = 1,
                .pQueuePriorities = &queue_priorities,
            },
            c.VkDeviceQueueCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .queueFamilyIndex = self.queue_transfer_index,
                .queueCount = 1,
                .pQueuePriorities = &queue_priorities,
            },
        };

        const validation_layers = Instance.getValidationLayers();
        const extensions = getExtensions();
        const features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);

        const create_info = &c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueCreateInfoCount = queue_create_infos.len,
            .pQueueCreateInfos = queue_create_infos,
            .enabledLayerCount = if (comptime std.debug.runtime_safety) @intCast(u32, validation_layers.len) else 0,
            .ppEnabledLayerNames = if (comptime std.debug.runtime_safety) &validation_layers else null,
            .enabledExtensionCount = @intCast(u32, extensions.len),
            .ppEnabledExtensionNames = &extensions,
            .pEnabledFeatures = &features,
        };

        try utility.checkResult(c.vkCreateDevice.?(physical_device.handle, create_info, memory.allocation_callbacks, &self.handle));
        c.volkLoadDevice(self.handle);

        c.vkGetDeviceQueue.?(self.handle, self.queue_graphics_index, 0, &self.queue_graphics);
        c.vkGetDeviceQueue.?(self.handle, self.queue_compute_index, 0, &self.queue_compute);
        c.vkGetDeviceQueue.?(self.handle, self.queue_transfer_index, 0, &self.queue_transfer);
    }

    fn destroyLogicalDevice(self: *Device) void {
        if (self.handle != null) {
            c.vkDestroyDevice.?(self.handle, memory.allocation_callbacks);
        }
    }

    pub fn waitIdle(self: *Device) void {
        utility.checkResult(c.vkDeviceWaitIdle.?(self.handle)) catch unreachable;
    }

    pub fn submit(self: *Device, submit_count: u32, submit_info: *const c.VkSubmitInfo, fence: c.VkFence) !void {
        try utility.checkResult(c.vkQueueSubmit.?(self.queue_graphics, submit_count, submit_info, fence));
    }

    fn getExtensions() [1][*c]const u8 {
        return [_][*c]const u8{
            c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
        };
    }
};
