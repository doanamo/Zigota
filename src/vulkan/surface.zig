const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = utility.log_scoped;

const Window = @import("../glfw/window.zig").Window;
const Instance = @import("instance.zig").Instance;
const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;

pub const Surface = struct {
    allocator: std.mem.Allocator = undefined,
    handle: c.VkSurfaceKHR = null,
    instance: *Instance = undefined,
    physical_device: *const PhysicalDevice = undefined,
    capabilities: c.VkSurfaceCapabilitiesKHR = undefined,
    present_modes: []c.VkPresentModeKHR = &.{},

    pub fn init(self: *Surface, window: *Window, instance: *Instance, physical_device: *const PhysicalDevice, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        self.instance = instance;
        self.physical_device = physical_device;
        errdefer self.deinit();

        self.createWindowSurface(window, instance) catch {
            log.err("Failed to create window surface", .{});
            return error.FailedToCreatenWindowSurface;
        };
    }

    pub fn deinit(self: *Surface) void {
        self.destroyWindowSurface();
        self.* = undefined;
    }

    fn createWindowSurface(self: *Surface, window: *Window, instance: *Instance) !void {
        log.info("Creating window surface...", .{});

        try utility.checkResult(c.glfwCreateWindowSurface(instance.handle, window.handle, memory.allocation_callbacks, &self.handle));
        try self.updateCapabilities();

        var present_mode_count: u32 = 0;
        try utility.checkResult(c.vkGetPhysicalDeviceSurfacePresentModesKHR.?(self.physical_device.handle, self.handle, &present_mode_count, null));

        self.present_modes = try self.allocator.alloc(c.VkPresentModeKHR, present_mode_count);
        try utility.checkResult(c.vkGetPhysicalDeviceSurfacePresentModesKHR.?(self.physical_device.handle, self.handle, &present_mode_count, self.present_modes.ptr));
    }

    fn destroyWindowSurface(self: *Surface) void {
        if (self.present_modes.len != 0) {
            self.allocator.free(self.present_modes);
        }
        if (self.handle != null) {
            c.vkDestroySurfaceKHR.?(self.instance.handle, self.handle, memory.allocation_callbacks);
        }
    }

    pub fn updateCapabilities(self: *Surface) !void {
        // This is exposed because it needs to be called at least once
        // after resizing window to avoid Vulkan validation layer errors
        try utility.checkResult(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR.?(self.physical_device.handle, self.handle, &self.capabilities));
    }
};
