const c = @import("c.zig");
const std = @import("std");
const utility = @import("vulkan/utility.zig");
const memory = @import("vulkan/memory.zig");
const log = utility.log_scoped;

const Window = @import("glfw/window.zig").Window;
const Instance = @import("vulkan/instance.zig").Instance;
const PhysicalDevice = @import("vulkan/physical_device.zig").PhysicalDevice;
const Surface = @import("vulkan/surface.zig").Surface;
const Device = @import("vulkan/device.zig").Device;
const VmaAllocator = @import("vulkan/vma.zig").VmaAllocator;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;
const Transfer = @import("vulkan/transfer.zig").Transfer;

pub const Vulkan = struct {
    pub const Config = struct {
        swapchain: Swapchain.Config = .{},
    };

    allocator: std.mem.Allocator = undefined,

    instance: Instance = .{},
    physical_device: PhysicalDevice = .{},
    surface: Surface = .{},
    device: Device = .{},
    vma: VmaAllocator = .{},
    swapchain: Swapchain = .{},
    transfer: Transfer = .{},

    pub fn init(self: *Vulkan, window: *Window, allocator: std.mem.Allocator) !void {
        log.info("Initializing...", .{});
        self.allocator = allocator;
        errdefer self.deinit();

        try self.instance.init(allocator);
        try self.physical_device.init(&self.instance, allocator);
        try self.surface.init(window, &self.instance, &self.physical_device);
        try self.device.init(&self.physical_device, &self.surface, allocator);
        try self.vma.init(&self.instance, &self.physical_device, &self.device);
        try self.swapchain.init(window, &self.surface, &self.device, allocator);
        try self.transfer.init(&self.device, &self.vma, allocator);
    }

    pub fn deinit(self: *Vulkan) void {
        log.info("Deinitializing...", .{});

        self.device.waitIdle();

        self.transfer.deinit();
        self.swapchain.deinit();
        self.vma.deinit();
        self.device.deinit();
        self.surface.deinit();
        self.physical_device.deinit();
        self.instance.deinit();
    }

    pub fn recreateSwapchain(self: *Vulkan) !void {
        self.device.waitIdle();
        try self.swapchain.recreate();
    }
};
