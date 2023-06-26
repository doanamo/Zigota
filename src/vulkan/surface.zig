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
    instance: *Instance = undefined,
    physical_device: *const PhysicalDevice = undefined,
    capabilities: c.VkSurfaceCapabilitiesKHR = undefined,

    pub fn init(window: *glfw.Window, instance: *Instance, physical_device: *const PhysicalDevice) !Surface {
        var self = Surface{};
        self.instance = instance;
        self.physical_device = physical_device;
        errdefer self.deinit();

        self.createWindowSurface(window, instance) catch {
            log.err("Failed to create window surface", .{});
            return error.FailedToCreatenWindowSurface;
        };

        return self;
    }

    pub fn deinit(self: *Surface) void {
        self.destroyWindowSurface();
        self.* = undefined;
    }

    fn createWindowSurface(self: *Surface, window: *glfw.Window, instance: *Instance) !void {
        log.info("Creating window surface...", .{});
        try utility.checkResult(c.glfwCreateWindowSurface(instance.handle, window.handle, memory.vulkan_allocator, &self.handle));
        try self.updateCapabilities();
    }

    fn destroyWindowSurface(self: *Surface) void {
        if (self.handle != null) {
            c.vkDestroySurfaceKHR.?(self.instance.handle, self.handle, memory.vulkan_allocator);
        }
    }

    pub fn updateCapabilities(self: *Surface) !void {
        try utility.checkResult(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR.?(self.physical_device.handle, self.handle, &self.capabilities));
    }
};
