const std = @import("std");
const c = @import("../cimport/c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const Vulkan = @import("vulkan.zig").Vulkan;
const Window = @import("../glfw/window.zig").Window;
const Instance = @import("instance.zig").Instance;
const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;

pub const Surface = struct {
    vulkan: *Vulkan = undefined,
    handle: c.VkSurfaceKHR = null,
    capabilities: c.VkSurfaceCapabilitiesKHR = undefined,
    present_modes: []c.VkPresentModeKHR = &.{},

    pub fn init(self: *Surface, vulkan: *Vulkan) !void {
        errdefer self.deinit();

        self.vulkan = vulkan;

        self.createWindowSurface() catch |err| {
            log.err("Failed to create window surface: {}", .{err});
            return error.FailedToCreatenWindowSurface;
        };
    }

    pub fn deinit(self: *Surface) void {
        self.destroyWindowSurface();
        self.* = .{};
    }

    fn createWindowSurface(self: *Surface) !void {
        log.info("Creating window surface...", .{});

        try check(c.glfwCreateWindowSurface(self.vulkan.instance.handle, self.vulkan.window.handle, memory.vulkan_allocator, &self.handle));
        try self.updateCapabilities();

        var present_mode_count: u32 = 0;
        try check(c.vkGetPhysicalDeviceSurfacePresentModesKHR.?(self.vulkan.physical_device.handle, self.handle, &present_mode_count, null));

        self.present_modes = try memory.default_allocator.alloc(c.VkPresentModeKHR, present_mode_count);
        try check(c.vkGetPhysicalDeviceSurfacePresentModesKHR.?(self.vulkan.physical_device.handle, self.handle, &present_mode_count, self.present_modes.ptr));
    }

    fn destroyWindowSurface(self: *Surface) void {
        if (self.present_modes.len != 0) {
            memory.default_allocator.free(self.present_modes);
        }
        if (self.handle != null) {
            c.vkDestroySurfaceKHR.?(self.vulkan.instance.handle, self.handle, memory.vulkan_allocator);
        }
    }

    pub fn updateCapabilities(self: *Surface) !void {
        // This is exposed because it needs to be called at least once
        // after resizing window to avoid Vulkan validation layer errors
        std.debug.assert(self.handle != null);
        try check(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR.?(self.vulkan.physical_device.handle, self.handle, &self.capabilities));
    }
};
