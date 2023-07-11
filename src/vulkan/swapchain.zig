const std = @import("std");
const root = @import("root");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = utility.log_scoped;

const Window = @import("../glfw/window.zig").Window;
const Surface = @import("surface.zig").Surface;
const Device = @import("device.zig").Device;

pub const Swapchain = struct {
    pub const PresentMode = enum(c.VkPresentModeKHR) {
        Immediate = c.VK_PRESENT_MODE_IMMEDIATE_KHR,
        Mailbox = c.VK_PRESENT_MODE_MAILBOX_KHR,
        Fifo = c.VK_PRESENT_MODE_FIFO_KHR,
        FifoRelaxed = c.VK_PRESENT_MODE_FIFO_RELAXED_KHR,
    };

    pub const Config = struct {
        present_mode: PresentMode,
    };

    handle: c.VkSwapchainKHR = null,
    window: *Window = undefined,
    surface: *Surface = undefined,
    device: *Device = undefined,
    allocator: std.mem.Allocator = undefined,

    images: std.ArrayListUnmanaged(c.VkImage) = .{},
    image_views: std.ArrayListUnmanaged(c.VkImageView) = .{},
    image_format: c.VkFormat = undefined,
    color_space: c.VkColorSpaceKHR = undefined,
    extent: c.VkExtent2D = undefined,

    max_inflight_frames: u32 = undefined,
    image_available_semaphores: std.ArrayListUnmanaged(c.VkSemaphore) = .{},
    frame_finished_semaphores: std.ArrayListUnmanaged(c.VkSemaphore) = .{},
    frame_inflight_fences: std.ArrayListUnmanaged(c.VkFence) = .{},
    frame_index: u32 = 0,

    pub fn init(self: *Swapchain, window: *Window, surface: *Surface, device: *Device, allocator: std.mem.Allocator) !void {
        self.window = window;
        self.surface = surface;
        self.device = device;
        self.allocator = allocator;
        errdefer self.deinit();

        self.createSwapchain() catch {
            log.err("Failed to create swapchain", .{});
            return error.FailedToCreateSwapchain;
        };

        self.createImageViews(false) catch {
            log.err("Failed to create image views", .{});
            return error.FailedToCreateImageViews;
        };

        self.createImageSynchronization() catch {
            log.err("Failed to create image synchronization", .{});
            return error.FailedToCreateImageSynchronization;
        };
    }

    pub fn deinit(self: *Swapchain) void {
        self.destroyImageSynchronization();
        self.destroyImageViews(false);
        self.destroySwapchain();
        self.* = undefined;
    }

    fn createSwapchain(self: *Swapchain) !void {
        // Simplified surface format and present mode selection
        // Hardcoded swapchain preferences with most common support across most platforms
        log.info("Creating swapchain...", .{});
        errdefer self.destroySwapchain();

        const config = root.config.vulkan.swapchain;

        self.extent = c.VkExtent2D{
            .width = self.window.width,
            .height = self.window.height,
        };

        self.image_format = c.VK_FORMAT_B8G8R8A8_UNORM;
        self.color_space = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;

        const present_mode = for (self.surface.present_modes) |supported_mode| {
            const mode = @intFromEnum(config.present_mode);
            if (supported_mode == mode) {
                break mode;
            }
        } else blk: {
            log.warn("Present mode {s} not supported, falling back to Fifo", .{@tagName(config.present_mode)});
            break :blk c.VK_PRESENT_MODE_FIFO_KHR;
        };

        const create_info = c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .pNext = null,
            .flags = 0,
            .surface = self.surface.handle,
            .minImageCount = 2,
            .imageFormat = self.image_format,
            .imageColorSpace = self.color_space,
            .imageExtent = self.extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .preTransform = self.surface.capabilities.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = present_mode,
            .clipped = c.VK_TRUE,
            .oldSwapchain = null,
        };

        try utility.checkResult(c.vkCreateSwapchainKHR.?(self.device.handle, &create_info, memory.allocation_callbacks, &self.handle));
    }

    fn destroySwapchain(self: *Swapchain) void {
        if (self.handle != null) {
            c.vkDestroySwapchainKHR.?(self.device.handle, self.handle, memory.allocation_callbacks);
            self.handle = null;
        }
    }

    fn createImageViews(self: *Swapchain, recreating: bool) !void {
        log.info("Creating swapchain image views...", .{});
        errdefer self.destroyImageViews(recreating);

        var image_count: u32 = 0;
        try utility.checkResult(c.vkGetSwapchainImagesKHR.?(self.device.handle, self.handle, &image_count, null));
        self.max_inflight_frames = image_count;

        try self.images.resize(self.allocator, image_count);
        try utility.checkResult(c.vkGetSwapchainImagesKHR.?(self.device.handle, self.handle, &image_count, self.images.items.ptr));

        try self.image_views.ensureTotalCapacityPrecise(self.allocator, image_count);
        for (self.images.items) |image| {
            const create_info = &c.VkImageViewCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
                .pNext = null,
                .flags = 0,
                .image = image,
                .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
                .format = self.image_format,
                .components = c.VkComponentMapping{
                    .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                    .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                },
                .subresourceRange = c.VkImageSubresourceRange{
                    .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                    .baseMipLevel = 0,
                    .levelCount = 1,
                    .baseArrayLayer = 0,
                    .layerCount = 1,
                },
            };

            var image_view: c.VkImageView = null;
            try utility.checkResult(c.vkCreateImageView.?(self.device.handle, create_info, memory.allocation_callbacks, &image_view));
            try self.image_views.append(self.allocator, image_view);
        }
    }

    fn destroyImageViews(self: *Swapchain, recreating: bool) void {
        for (self.image_views.items) |image_view| {
            c.vkDestroyImageView.?(self.device.handle, image_view, memory.allocation_callbacks);
        }

        if (recreating) {
            self.image_views.clearRetainingCapacity();
            self.images.clearRetainingCapacity();
        } else {
            self.image_views.deinit(self.allocator);
            self.images.deinit(self.allocator);
        }
    }

    fn createImageSynchronization(self: *Swapchain) !void {
        log.info("Creating swapchain image synchronization...", .{});

        try self.image_available_semaphores.ensureTotalCapacityPrecise(self.allocator, self.max_inflight_frames);
        try self.frame_finished_semaphores.ensureTotalCapacityPrecise(self.allocator, self.max_inflight_frames);
        try self.frame_inflight_fences.ensureTotalCapacityPrecise(self.allocator, self.max_inflight_frames);

        for (0..self.max_inflight_frames) |_| {
            const semaphore_create_info = &c.VkSemaphoreCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
            };

            var image_available_semaphore: c.VkSemaphore = null;
            try utility.checkResult(c.vkCreateSemaphore.?(self.device.handle, semaphore_create_info, memory.allocation_callbacks, &image_available_semaphore));
            try self.image_available_semaphores.append(self.allocator, image_available_semaphore);

            var frame_finished_semaphore: c.VkSemaphore = null;
            try utility.checkResult(c.vkCreateSemaphore.?(self.device.handle, semaphore_create_info, memory.allocation_callbacks, &frame_finished_semaphore));
            try self.frame_finished_semaphores.append(self.allocator, frame_finished_semaphore);

            const fence_create_info = &c.VkFenceCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                .pNext = null,
                .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
            };

            var frame_inflight_fence: c.VkFence = null;
            try utility.checkResult(c.vkCreateFence.?(self.device.handle, fence_create_info, memory.allocation_callbacks, &frame_inflight_fence));
            try self.frame_inflight_fences.append(self.allocator, frame_inflight_fence);
        }
    }

    fn destroyImageSynchronization(self: *Swapchain) void {
        for (self.image_available_semaphores.items) |semaphore| {
            c.vkDestroySemaphore.?(self.device.handle, semaphore, memory.allocation_callbacks);
        }

        for (self.frame_finished_semaphores.items) |semaphore| {
            c.vkDestroySemaphore.?(self.device.handle, semaphore, memory.allocation_callbacks);
        }

        for (self.frame_inflight_fences.items) |fence| {
            c.vkDestroyFence.?(self.device.handle, fence, memory.allocation_callbacks);
        }

        self.image_available_semaphores.deinit(self.allocator);
        self.frame_finished_semaphores.deinit(self.allocator);
        self.frame_inflight_fences.deinit(self.allocator);
    }

    pub fn recreate(self: *Swapchain) !void {
        log.info("Recreating swapchain...", .{});
        try self.surface.updateCapabilities();

        self.destroyImageViews(true);
        self.destroySwapchain();

        try self.createSwapchain();
        try self.createImageViews(true);
    }

    pub fn acquireNextImage(self: *Swapchain) !struct {
        index: u32,
        available_semaphore: c.VkSemaphore,
        finished_semaphore: c.VkSemaphore,
        inflight_fence: c.VkFence,
    } {
        try utility.checkResult(c.vkWaitForFences.?(self.device.handle, 1, &self.frame_inflight_fences.items[self.frame_index], c.VK_TRUE, std.math.maxInt(u64)));

        var image_index: u32 = 0;
        const result = c.vkAcquireNextImageKHR.?(self.device.handle, self.handle, std.math.maxInt(u64), self.image_available_semaphores.items[self.frame_index], null, &image_index);

        switch (result) {
            c.VK_SUCCESS, c.VK_SUBOPTIMAL_KHR => {
                try utility.checkResult(c.vkResetFences.?(self.device.handle, 1, &self.frame_inflight_fences.items[self.frame_index]));

                return .{
                    .index = image_index,
                    .available_semaphore = self.image_available_semaphores.items[self.frame_index],
                    .finished_semaphore = self.frame_finished_semaphores.items[self.frame_index],
                    .inflight_fence = self.frame_inflight_fences.items[self.frame_index],
                };
            },
            c.VK_ERROR_OUT_OF_DATE_KHR => {
                log.warn("Swapchain is out of date", .{});
                return error.SwapchainOutOfDate;
            },
            else => {
                log.err("Failed to acquire next swapchain image", .{});
                return error.SwapchainAcquireNextImageFailed;
            },
        }
    }

    pub fn present(self: *Swapchain, present_info: *const c.VkPresentInfoKHR) !void {
        const result = c.vkQueuePresentKHR.?(self.device.getQueue(.Graphics).handle, present_info);

        switch (result) {
            c.VK_SUCCESS, c.VK_SUBOPTIMAL_KHR => {
                self.frame_index = (self.frame_index + 1) % self.max_inflight_frames;

                if (result == c.VK_SUBOPTIMAL_KHR) {
                    log.warn("Swapchain is suboptimal", .{});
                    return error.SwapchainSuboptimal;
                }
            },
            c.VK_ERROR_OUT_OF_DATE_KHR => {
                log.warn("Swapchain is out of date", .{});
                return error.SwapchainOutOfDate;
            },
            else => {
                log.err("Failed to present swapchain", .{});
                return error.SwapchainPresentFailed;
            },
        }
    }
};
