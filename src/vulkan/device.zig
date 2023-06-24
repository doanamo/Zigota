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
    queue_graphics: c.VkQueue = null,
    queue_graphics_index: u32 = undefined,

    pub fn init(physical_device: *PhysicalDevice, surface: *Surface, allocator: std.mem.Allocator) !Device {
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
        // No need to destroy queues that are owned by physical device
        if (self.handle != null) {
            c.vkDestroyDevice.?(self.handle, memory.vulkan_allocator);
        }

        self.* = undefined;
    }

    fn selectQueueFamilies(self: *Device, physical_device: *PhysicalDevice, surface: *Surface, allocator: std.mem.Allocator) !void {
        // Simplified queue family selection
        // Select first queue that supports both graphics and presentation
        log.info("Selecting queue families...", .{});

        var queue_family_count: u32 = 0;
        c.vkGetPhysicalDeviceQueueFamilyProperties.?(physical_device.handle, &queue_family_count, null);

        const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
        defer allocator.free(queue_families);

        c.vkGetPhysicalDeviceQueueFamilyProperties.?(physical_device.handle, &queue_family_count, queue_families.ptr);

        var found_suitable_queue = false;
        for (queue_families, 0..) |queue_family, i| {
            var graphics_support = queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0;
            var present_support: c.VkBool32 = c.VK_FALSE;

            try utility.checkResult(c.vkGetPhysicalDeviceSurfaceSupportKHR.?(physical_device.handle, @intCast(u32, i), surface.handle, &present_support));

            if (queue_family.queueCount > 0 and graphics_support == true and present_support == c.VK_TRUE) {
                self.queue_graphics_index = @intCast(u32, i);
                found_suitable_queue = true;
                break;
            }
        }

        if (!found_suitable_queue) {
            log.err("Failed to find suitable queue family", .{});
            return error.NoSuitableQueueFamily;
        }
    }

    fn createLogicalDevice(self: *Device, physical_device: *PhysicalDevice) !void {
        log.info("Creating logical device...", .{});

        const queue_priorities = [1]f32{1.0};
        const queue_create_info = c.VkDeviceQueueCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueFamilyIndex = self.queue_graphics_index,
            .queueCount = 1,
            .pQueuePriorities = &queue_priorities,
        };

        const validation_layers = Instance.getValidationLayers();
        const extensions = getExtensions();
        const features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);

        const create_info = &c.VkDeviceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .queueCreateInfoCount = 1,
            .pQueueCreateInfos = &queue_create_info,
            .enabledLayerCount = if (comptime std.debug.runtime_safety) @intCast(u32, validation_layers.len) else 0,
            .ppEnabledLayerNames = if (comptime std.debug.runtime_safety) &validation_layers else null,
            .enabledExtensionCount = @intCast(u32, extensions.len),
            .ppEnabledExtensionNames = &extensions,
            .pEnabledFeatures = &features,
        };

        try utility.checkResult(c.vkCreateDevice.?(physical_device.handle, create_info, memory.vulkan_allocator, &self.handle));

        c.volkLoadDevice(self.handle);
        c.vkGetDeviceQueue.?(self.handle, self.queue_graphics_index, 0, &self.queue_graphics);
    }

    pub fn waitIdle(self: *Device) !void {
        // Null check needed because this function is called from deinit
        if (self.handle != null) {
            try utility.checkResult(c.vkDeviceWaitIdle.?(self.handle));
        }
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
