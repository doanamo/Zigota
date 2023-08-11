const c = @import("c.zig");
const std = @import("std");
const utility = @import("vulkan/utility.zig");
const memory = @import("vulkan/memory.zig");
const log = std.log.scoped(.Vulkan);

const Window = @import("glfw/window.zig").Window;
const Instance = @import("vulkan/instance.zig").Instance;
const PhysicalDevice = @import("vulkan/physical_device.zig").PhysicalDevice;
const Surface = @import("vulkan/surface.zig").Surface;
const Device = @import("vulkan/device.zig").Device;
const Swapchain = @import("vulkan/swapchain.zig").Swapchain;
const VmaAllocator = @import("vulkan/vma.zig").VmaAllocator;
const Transfer = @import("vulkan/transfer.zig").Transfer;
const Bindless = @import("vulkan/bindless.zig").Bindless;

pub const Vulkan = struct {
    pub const Config = struct {
        swapchain: Swapchain.Config,
        transfer: Transfer.Config,
    };

    window: *Window = undefined,

    instance: Instance = .{},
    physical_device: PhysicalDevice = .{},
    surface: Surface = .{},
    device: Device = .{},
    vma: VmaAllocator = .{},
    swapchain: Swapchain = .{},
    bindless: Bindless = .{},
    transfer: Transfer = .{},

    pub fn init(self: *Vulkan, window: *Window) !void {
        log.info("Initializing...", .{});
        errdefer self.deinit();

        self.window = window;

        self.instance.init() catch |err| {
            log.err("Failed to initialize instance: {}", .{err});
            return error.FailedToInitializeInstance;
        };

        self.physical_device.init(self) catch |err| {
            log.err("Failed to initialize physical device: {}", .{err});
            return error.FailedToInitializePhysicalDevice;
        };

        self.surface.init(self) catch |err| {
            log.err("Failed to initialize surface: {}", .{err});
            return error.FailedToInitializeSurface;
        };

        self.device.init(self) catch |err| {
            log.err("Failed to initialize device: {}", .{err});
            return error.FailedToInitializeDevice;
        };

        self.vma.init(self) catch |err| {
            log.err("Failed to initialize allocator: {}", .{err});
            return error.FailedToInitializeAllocator;
        };

        self.swapchain.init(self) catch |err| {
            log.err("Failed to initialize swapchain: {}", .{err});
            return error.FailedToInitializeSwapchain;
        };

        self.bindless.init(self) catch |err| {
            log.err("Failed to initialize bindless: {}", .{err});
            return error.FailedToInitializeBindless;
        };

        self.transfer.init(self) catch |err| {
            log.err("Failed to initialize transfer: {}", .{err});
            return error.FailedToInitializeTransfer;
        };
    }

    pub fn deinit(self: *Vulkan) void {
        log.info("Deinitializing...", .{});

        self.device.waitIdle();
        self.transfer.deinit();
        self.bindless.deinit();
        self.swapchain.deinit();
        self.vma.deinit();
        self.device.deinit();
        self.surface.deinit();
        self.physical_device.deinit();
        self.instance.deinit();
        self.* = .{};
    }

    pub fn recreateSwapchain(self: *Vulkan) !void {
        self.device.waitIdle();
        try self.swapchain.recreate();
    }
};
