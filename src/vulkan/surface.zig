const std = @import("std");
const c = @import("../c.zig");
const glfw = @import("../glfw.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = utility.log_scoped;

const Instance = @import("instance.zig").Instance;
const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;

pub const Surface = struct {
    handle: c.VkSurfaceKHR = null,
    capabilities: c.VkSurfaceCapabilitiesKHR = undefined,

    pub fn init(window: *glfw.Window, instance: *Instance, physical_device: *PhysicalDevice) !Surface {
        var self = Surface{};
        errdefer self.deinit(instance);

        self.createWindowSurface(window, instance, physical_device) catch {
            log.err("Failed to create window surface", .{});
            return error.FailedToCreatenWindowSurface;
        };

        return self;
    }

    pub fn deinit(self: *Surface, instance: *Instance) void {
        if (self.handle != null) {
            c.vkDestroySurfaceKHR.?(instance.handle, self.handle, memory.vulkan_allocator);
        }

        self.* = undefined;
    }

    fn createWindowSurface(self: *Surface, window: *glfw.Window, instance: *Instance, physical_device: *PhysicalDevice) !void {
        log.info("Creating window surface...", .{});

        try utility.checkResult(c.glfwCreateWindowSurface(instance.handle, window.handle, memory.vulkan_allocator, &self.handle));
        try self.updateCapabilities(physical_device);
    }

    pub fn updateCapabilities(self: *Surface, physical_device: *PhysicalDevice) !void {
        try utility.checkResult(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR.?(physical_device.handle, self.handle, &self.capabilities));
    }
};
