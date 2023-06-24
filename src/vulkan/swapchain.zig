const std = @import("std");
const c = @import("../c.zig");
const glfw = @import("../glfw.zig");
const utility = @import("utility.zig");
const memory = @import("memory.zig");
const log = utility.log_scoped;

const Surface = @import("surface.zig").Surface;
const Device = @import("device.zig").Device;

pub const Swapchain = struct {
    pub const PresentMode = enum(c.VkPresentModeKHR) {
        Immediate = c.VK_PRESENT_MODE_IMMEDIATE_KHR,
        Mailbox = c.VK_PRESENT_MODE_MAILBOX_KHR,
        Fifo = c.VK_PRESENT_MODE_FIFO_KHR,
        FifoRelaxed = c.VK_PRESENT_MODE_FIFO_RELAXED_KHR,
    };

    const present_mode = PresentMode.Immediate;

    handle: c.VkSwapchainKHR = null,
    images: ?[]c.VkImage = null,
    image_views: ?[]c.VkImageView = null,
    image_format: c.VkFormat = undefined,
    color_space: c.VkColorSpaceKHR = undefined,
    extent: c.VkExtent2D = undefined,

    max_inflight_frames: u32 = undefined,
    image_available_semaphores: ?[]c.VkSemaphore = null,
    frame_finished_semaphores: ?[]c.VkSemaphore = null,
    frame_inflight_fences: ?[]c.VkFence = null,
    frame_index: u32 = 0,

    pub fn init(window: *glfw.Window, surface: *Surface, device: *Device, allocator: std.mem.Allocator) !Swapchain {
        var self = Swapchain{};
        errdefer self.deinit(device, allocator);

        self.createSwapchain(window, surface, device) catch {
            log.err("Failed to create swapchain", .{});
            return error.FailedToCreateSwapchain;
        };

        self.createImageViews(device, allocator) catch {
            log.err("Failed to create image views", .{});
            return error.FailedToCreateImageViews;
        };

        self.createImageSynchronization(device, allocator) catch {
            log.err("Failed to create image synchronization", .{});
            return error.FailedToCreateImageSynchronization;
        };

        return self;
    }

    pub fn deinit(self: *Swapchain, device: *Device, allocator: std.mem.Allocator) void {
        self.destroyImageSynchronization(device, allocator);
        self.destroyImageViews(device, allocator);
        self.destroySwapchain(device);
        self.* = undefined;
    }

    fn createSwapchain(self: *Swapchain, window: *glfw.Window, surface: *Surface, device: *Device) !void {
        // Simplified surface format and present mode selection
        // Hardcoded swapchain preferences with most common support across most platforms
        log.info("Creating swapchain...", .{});

        self.extent = c.VkExtent2D{
            .width = window.width,
            .height = window.height,
        };

        self.image_format = c.VK_FORMAT_B8G8R8A8_UNORM;
        self.color_space = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;

        const create_info = &c.VkSwapchainCreateInfoKHR{
            .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
            .pNext = null,
            .flags = 0,
            .surface = surface.handle,
            .minImageCount = 2,
            .imageFormat = self.image_format,
            .imageColorSpace = self.color_space,
            .imageExtent = self.extent,
            .imageArrayLayers = 1,
            .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
            .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
            .queueFamilyIndexCount = 0,
            .pQueueFamilyIndices = null,
            .preTransform = surface.capabilities.currentTransform,
            .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
            .presentMode = @enumToInt(present_mode),
            .clipped = c.VK_TRUE,
            .oldSwapchain = null,
        };

        try utility.checkResult(c.vkCreateSwapchainKHR.?(device.handle, create_info, memory.vulkan_allocator, &self.handle));
    }

    fn destroySwapchain(self: *Swapchain, device: *Device) void {
        if (self.handle != null) {
            c.vkDestroySwapchainKHR.?(device.handle, self.handle, memory.vulkan_allocator);
        }
    }

    fn createImageViews(self: *Swapchain, device: *Device, allocator: std.mem.Allocator) !void {
        var image_count: u32 = 0;
        try utility.checkResult(c.vkGetSwapchainImagesKHR.?(device.handle, self.handle, &image_count, null));

        self.images = try allocator.alloc(c.VkImage, image_count);
        try utility.checkResult(c.vkGetSwapchainImagesKHR.?(device.handle, self.handle, &image_count, self.images.?.ptr));

        self.image_views = try allocator.alloc(c.VkImageView, image_count);
        for (self.image_views.?) |*image| {
            image.* = null;
        }

        for (self.images.?, 0..) |image, i| {
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

            try utility.checkResult(c.vkCreateImageView.?(device.handle, create_info, memory.vulkan_allocator, &self.image_views.?[i]));
        }

        self.max_inflight_frames = image_count;
    }

    fn destroyImageViews(self: *Swapchain, device: *Device, allocator: std.mem.Allocator) void {
        if (self.image_views != null) {
            for (self.image_views.?) |image_view| {
                if (image_view != null) {
                    c.vkDestroyImageView.?(device.handle, image_view, memory.vulkan_allocator);
                }
            }

            allocator.free(self.image_views.?);
        }

        if (self.images != null) {
            allocator.free(self.images.?);
        }
    }

    fn createImageSynchronization(self: *Swapchain, device: *Device, allocator: std.mem.Allocator) !void {
        log.info("Creating image synchronization...", .{});

        self.image_available_semaphores = try allocator.alloc(c.VkSemaphore, self.max_inflight_frames);
        self.frame_finished_semaphores = try allocator.alloc(c.VkSemaphore, self.max_inflight_frames);
        self.frame_inflight_fences = try allocator.alloc(c.VkFence, self.max_inflight_frames);

        for (0..self.max_inflight_frames) |i| {
            self.image_available_semaphores.?[i] = null;
            self.frame_finished_semaphores.?[i] = null;
            self.frame_inflight_fences.?[i] = null;
        }

        for (0..self.max_inflight_frames) |i| {
            const semaphore_create_info = &c.VkSemaphoreCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
            };

            try utility.checkResult(c.vkCreateSemaphore.?(device.handle, semaphore_create_info, memory.vulkan_allocator, &self.image_available_semaphores.?[i]));
            try utility.checkResult(c.vkCreateSemaphore.?(device.handle, semaphore_create_info, memory.vulkan_allocator, &self.frame_finished_semaphores.?[i]));

            const fence_create_info = &c.VkFenceCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                .pNext = null,
                .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
            };

            try utility.checkResult(c.vkCreateFence.?(device.handle, fence_create_info, memory.vulkan_allocator, &self.frame_inflight_fences.?[i]));
        }
    }

    fn destroyImageSynchronization(self: *Swapchain, device: *Device, allocator: std.mem.Allocator) void {
        if (self.image_available_semaphores != null) {
            for (self.image_available_semaphores.?) |semaphore| {
                if (semaphore != null) {
                    c.vkDestroySemaphore.?(device.handle, semaphore, memory.vulkan_allocator);
                }
            }

            allocator.free(self.image_available_semaphores.?);
        }

        if (self.frame_finished_semaphores != null) {
            for (self.frame_finished_semaphores.?) |semaphore| {
                if (semaphore != null) {
                    c.vkDestroySemaphore.?(device.handle, semaphore, memory.vulkan_allocator);
                }
            }

            allocator.free(self.frame_finished_semaphores.?);
        }

        if (self.frame_inflight_fences != null) {
            for (self.frame_inflight_fences.?) |fence| {
                if (fence != null) {
                    c.vkDestroyFence.?(device.handle, fence, memory.vulkan_allocator);
                }
            }

            allocator.free(self.frame_inflight_fences.?);
        }
    }

    pub fn recreate(self: *Swapchain, window: *glfw.Window, device: *Device, surface: *Surface, allocator: std.mem.Allocator) !void {
        log.info("Recreating swapchain...", .{});

        self.destroyImageViews(device, allocator);
        self.destroySwapchain(device);

        try self.createSwapchain(window, surface, device);
        try self.createImageViews(device, allocator);
    }

    pub fn acquireNextImage(self: *Swapchain, device: *Device) !struct {
        index: u32,
        available_semaphore: c.VkSemaphore,
        finished_semaphore: c.VkSemaphore,
        inflight_fence: c.VkFence,
    } {
        try utility.checkResult(c.vkWaitForFences.?(device.handle, 1, &self.frame_inflight_fences.?[self.frame_index], c.VK_TRUE, std.math.maxInt(u64)));

        var image_index: u32 = 0;
        const result = c.vkAcquireNextImageKHR.?(device.handle, self.handle, std.math.maxInt(u64), self.image_available_semaphores.?[self.frame_index], null, &image_index);

        switch (result) {
            c.VK_SUCCESS, c.VK_SUBOPTIMAL_KHR => {
                try utility.checkResult(c.vkResetFences.?(device.handle, 1, &self.frame_inflight_fences.?[self.frame_index]));

                return .{
                    .index = image_index,
                    .available_semaphore = self.image_available_semaphores.?[self.frame_index],
                    .finished_semaphore = self.frame_finished_semaphores.?[self.frame_index],
                    .inflight_fence = self.frame_inflight_fences.?[self.frame_index],
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

    pub fn present(self: *Swapchain, device: *Device, present_info: *const c.VkPresentInfoKHR) !void {
        const result = c.vkQueuePresentKHR.?(device.queue_graphics, present_info);

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
