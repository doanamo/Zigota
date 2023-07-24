const std = @import("std");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const Window = @import("../glfw/window.zig").Window;
const Instance = @import("instance.zig").Instance;
const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;

pub const Surface = struct {
    handle: c.VkSurfaceKHR = null,
    instance: *Instance = undefined,
    physical_device: *const PhysicalDevice = undefined,
    capabilities: c.VkSurfaceCapabilitiesKHR = undefined,
    present_modes: []c.VkPresentModeKHR = &.{},

    pub fn init(window: *Window, instance: *Instance, physical_device: *const PhysicalDevice) !Surface {
        var self = Surface{};
        errdefer self.deinit();

        self.instance = instance;
        self.physical_device = physical_device;

        self.createWindowSurface(window, instance) catch |err| {
            log.err("Failed to create window surface: {}", .{err});
            return error.FailedToCreatenWindowSurface;
        };

        return self;
    }

    pub fn deinit(self: *Surface) void {
        self.destroyWindowSurface();
        self.* = undefined;
    }

    fn createWindowSurface(self: *Surface, window: *Window, instance: *Instance) !void {
        log.info("Creating window surface...", .{});

        try check(c.glfwCreateWindowSurface(instance.handle, window.handle, memory.vulkan_allocator, &self.handle));
        try self.updateCapabilities();

        var present_mode_count: u32 = 0;
        try check(c.vkGetPhysicalDeviceSurfacePresentModesKHR.?(self.physical_device.handle, self.handle, &present_mode_count, null));

        self.present_modes = try memory.default_allocator.alloc(c.VkPresentModeKHR, present_mode_count);
        try check(c.vkGetPhysicalDeviceSurfacePresentModesKHR.?(self.physical_device.handle, self.handle, &present_mode_count, self.present_modes.ptr));
    }

    fn destroyWindowSurface(self: *Surface) void {
        if (self.present_modes.len != 0) {
            memory.default_allocator.free(self.present_modes);
        }
        if (self.handle != null) {
            c.vkDestroySurfaceKHR.?(self.instance.handle, self.handle, memory.vulkan_allocator);
        }
    }

    pub fn updateCapabilities(self: *Surface) !void {
        // This is exposed because it needs to be called at least once
        // after resizing window to avoid Vulkan validation layer errors
        std.debug.assert(self.handle != null);
        std.debug.assert(self.physical_device.handle != null);
        try check(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR.?(self.physical_device.handle, self.handle, &self.capabilities));
    }
};
