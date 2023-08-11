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

    pub const Heap = struct {
        instance: Instance = .{},
        physical_device: PhysicalDevice = .{},
        surface: Surface = .{},
        device: Device = .{},
        vma: VmaAllocator = .{},
        swapchain: Swapchain = .{},
        bindless: Bindless = .{},
        transfer: Transfer = .{},
    };

    heap: ?*Heap = null,

    pub fn init(window: *Window) !Vulkan {
        log.info("Initializing...", .{});

        var self = Vulkan{};
        errdefer self.deinit();

        self.heap = try memory.default_allocator.create(Heap);
        var heap = self.heap orelse unreachable;
        heap.* = .{};

        heap.instance = Instance.init() catch |err| {
            log.err("Failed to initialize instance: {}", .{err});
            return error.FailedToInitializeInstance;
        };

        heap.physical_device = PhysicalDevice.init(&heap.instance) catch |err| {
            log.err("Failed to initialize physical device: {}", .{err});
            return error.FailedToInitializePhysicalDevice;
        };

        heap.surface = Surface.init(window, &heap.instance, &heap.physical_device) catch |err| {
            log.err("Failed to initialize surface: {}", .{err});
            return error.FailedToInitializeSurface;
        };

        heap.device = Device.init(&heap.physical_device, &heap.surface) catch |err| {
            log.err("Failed to initialize device: {}", .{err});
            return error.FailedToInitializeDevice;
        };

        heap.vma = VmaAllocator.init(&heap.instance, &heap.physical_device, &heap.device) catch |err| {
            log.err("Failed to initialize allocator: {}", .{err});
            return error.FailedToInitializeAllocator;
        };

        heap.swapchain = Swapchain.init(window, &heap.surface, &heap.device, &heap.vma) catch |err| {
            log.err("Failed to initialize swapchain: {}", .{err});
            return error.FailedToInitializeSwapchain;
        };

        heap.bindless = Bindless.init(&heap.device) catch |err| {
            log.err("Failed to initialize bindless: {}", .{err});
            return error.FailedToInitializeBindless;
        };

        heap.transfer = Transfer.init(&heap.device, &heap.vma, &heap.bindless) catch |err| {
            log.err("Failed to initialize transfer: {}", .{err});
            return error.FailedToInitializeTransfer;
        };

        return self;
    }

    pub fn deinit(self: *Vulkan) void {
        log.info("Deinitializing...", .{});

        if (self.heap) |heap| {
            heap.device.waitIdle();

            heap.transfer.deinit();
            heap.bindless.deinit();
            heap.swapchain.deinit();
            heap.vma.deinit();
            heap.device.deinit();
            heap.surface.deinit();
            heap.physical_device.deinit();
            heap.instance.deinit();

            memory.default_allocator.destroy(heap);
        }
        self.* = undefined;
    }

    pub fn get(self: *Vulkan, comptime T: type) *T {
        std.debug.assert(self.heap != null);

        inline for (@typeInfo(Heap).Struct.fields) |field| {
            if (field.type == T) {
                return &@field(self.heap.?, field.name);
            }
        } else {
            @compileError("Vulkan object does not contain field of type '" ++ @typeName(@TypeOf(T)) ++ "'");
        }
    }

    pub fn recreateSwapchain(self: *Vulkan) !void {
        self.heap.?.device.waitIdle();
        try self.heap.?.swapchain.recreate();
    }

    pub fn waitIdle(self: *Vulkan) void {
        if (self.heap) |heap| {
            heap.device.waitIdle();
        }
    }
};
