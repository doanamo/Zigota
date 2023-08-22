const std = @import("std");
const c = @import("../cimport/c.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = std.log.scoped(.Vulkan);

const Window = @import("../glfw/window.zig").Window;
const Instance = @import("instance.zig").Instance;
const PhysicalDevice = @import("physical_device.zig").PhysicalDevice;
const Surface = @import("surface.zig").Surface;
const Device = @import("device.zig").Device;
const Swapchain = @import("swapchain.zig").Swapchain;
const VmaAllocator = @import("vma.zig").VmaAllocator;
const Transfer = @import("transfer.zig").Transfer;
const Bindless = @import("bindless.zig").Bindless;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;

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
        log.info("Initializing vulkan...", .{});
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
        log.info("Deinitializing vulkan...", .{});

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

    pub fn beginFrame(self: *Vulkan) !Swapchain.ImageInfo {
        try self.transfer.submit();
        self.bindless.updateDescriptorSet();

        return self.swapchain.acquireNextImage() catch |err| {
            if (err == error.SwapchainOutOfDate) {
                try self.recreateSwapchain();
                return error.SkipFrameRender;
            }
            return err;
        };
    }

    pub fn endFrame(self: *Vulkan, params: struct {
        swapchain_image: *const Swapchain.ImageInfo,
        command_buffers: []*const CommandBuffer,
    }) !void {
        const submit_wait_semaphores = [_]c.VkSemaphore{
            self.transfer.finished_semaphore,
            params.swapchain_image.available_semaphore,
        };

        const submit_wait_sempahore_values = [_]u64{
            self.transfer.finished_semaphore_index,
            0,
        };

        const submit_wait_stages = [_]c.VkPipelineStageFlags{
            c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        };

        var submit_command_buffers = try memory.frame_allocator.alloc(c.VkCommandBuffer, params.command_buffers.len);
        defer memory.frame_allocator.free(submit_command_buffers);

        for (params.command_buffers, 0..) |command_buffer, i| {
            submit_command_buffers[i] = command_buffer.handle;
        }

        const submit_signal_semaphores = [_]c.VkSemaphore{
            params.swapchain_image.finished_semaphore,
        };

        const timeline_semaphore_submit_info = c.VkTimelineSemaphoreSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO,
            .pNext = null,
            .waitSemaphoreValueCount = submit_wait_sempahore_values.len,
            .pWaitSemaphoreValues = &submit_wait_sempahore_values,
            .signalSemaphoreValueCount = 0,
            .pSignalSemaphoreValues = null,
        };

        const submit_info = c.VkSubmitInfo{
            .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
            .pNext = &timeline_semaphore_submit_info,
            .waitSemaphoreCount = submit_wait_semaphores.len,
            .pWaitSemaphores = &submit_wait_semaphores,
            .pWaitDstStageMask = &submit_wait_stages,
            .commandBufferCount = @intCast(submit_command_buffers.len),
            .pCommandBuffers = submit_command_buffers.ptr,
            .signalSemaphoreCount = submit_signal_semaphores.len,
            .pSignalSemaphores = &submit_signal_semaphores,
        };

        try self.device.submit(.{
            .queue_type = .Graphics,
            .submit_count = 1,
            .submit_info = &submit_info,
            .fence = params.swapchain_image.inflight_fence,
        });

        const present_info = c.VkPresentInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
            .pNext = null,
            .waitSemaphoreCount = submit_signal_semaphores.len,
            .pWaitSemaphores = &submit_signal_semaphores,
            .swapchainCount = 1,
            .pSwapchains = &self.swapchain.handle,
            .pImageIndices = &params.swapchain_image.index,
            .pResults = null,
        };

        self.swapchain.present(&present_info) catch |err| {
            if (err == error.SwapchainOutOfDate or err == error.SwapchainSuboptimal) {
                try self.recreateSwapchain();
                return error.SkipFrameRender;
            }
            return err;
        };
    }
};
