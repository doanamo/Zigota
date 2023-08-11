const std = @import("std");
const root = @import("root");
const c = @import("../c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

const Window = @import("../glfw/window.zig").Window;
const Surface = @import("surface.zig").Surface;
const Device = @import("device.zig").Device;
const VmaAllocator = @import("vma.zig").VmaAllocator;
const CommandBuffer = @import("command_buffer.zig").CommandBuffer;
const Image = @import("image.zig").Image;

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
    vma: *VmaAllocator = undefined,

    images: std.ArrayListUnmanaged(c.VkImage) = .{},
    image_views: std.ArrayListUnmanaged(c.VkImageView) = .{},
    image_format: c.VkFormat = undefined,
    color_space: c.VkColorSpaceKHR = undefined,
    extent: c.VkExtent2D = undefined,

    depth_stencil_image: Image = .{},
    depth_stencil_image_view: c.VkImageView = null,
    depth_stencil_image_format: c.VkFormat = undefined,

    max_inflight_frames: u32 = undefined,
    image_available_semaphores: std.ArrayListUnmanaged(c.VkSemaphore) = .{},
    frame_finished_semaphores: std.ArrayListUnmanaged(c.VkSemaphore) = .{},
    frame_inflight_fences: std.ArrayListUnmanaged(c.VkFence) = .{},
    frame_index: u32 = 0,

    pub fn init(self: *Swapchain, window: *Window, surface: *Surface, device: *Device, vma: *VmaAllocator) !void {
        errdefer self.deinit();

        self.window = window;
        self.surface = surface;
        self.device = device;
        self.vma = vma;

        self.createSwapchain() catch |err| {
            log.err("Failed to create swapchain: {}", .{err});
            return error.FailedToCreateSwapchain;
        };

        self.createImageViews(false) catch |err| {
            log.err("Failed to create image views: {}", .{err});
            return error.FailedToCreateImageViews;
        };

        self.createDepthStencilBuffer(false) catch |err| {
            log.err("Failed to create depth stencil buffer: {}", .{err});
            return error.FailedToCreateDepthStencilBuffer;
        };

        self.createImageSynchronization() catch |err| {
            log.err("Failed to create image synchronization: {}", .{err});
            return error.FailedToCreateImageSynchronization;
        };
    }

    pub fn deinit(self: *Swapchain) void {
        self.destroyImageSynchronization();
        self.destroyDepthStencilBuffer(false);
        self.destroyImageViews(false);
        self.destroySwapchain();
        self.* = .{};
    }

    fn createSwapchain(self: *Swapchain) !void {
        // Simplified surface format and present mode selection
        // Hardcoded swapchain preferences with most common support across most platforms
        log.info("Creating swapchain...", .{});
        const config = root.config.vulkan.swapchain;

        self.extent = c.VkExtent2D{
            .width = self.window.width,
            .height = self.window.height,
        };

        self.image_format = c.VK_FORMAT_B8G8R8A8_SRGB;
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

        try check(c.vkCreateSwapchainKHR.?(self.device.handle, &create_info, memory.vulkan_allocator, &self.handle));
    }

    fn destroySwapchain(self: *Swapchain) void {
        if (self.handle != null) {
            c.vkDestroySwapchainKHR.?(self.device.handle, self.handle, memory.vulkan_allocator);
            self.handle = null;
        }
    }

    fn createImageViews(self: *Swapchain, recreating: bool) !void {
        log.info("Creating swapchain image views...", .{});
        errdefer self.destroyImageViews(recreating);

        var image_count: u32 = 0;
        try check(c.vkGetSwapchainImagesKHR.?(self.device.handle, self.handle, &image_count, null));
        self.max_inflight_frames = image_count;

        try self.images.resize(memory.default_allocator, image_count);
        try check(c.vkGetSwapchainImagesKHR.?(self.device.handle, self.handle, &image_count, self.images.items.ptr));

        try self.image_views.ensureTotalCapacityPrecise(memory.default_allocator, image_count);
        for (self.images.items) |image| {
            const create_info = c.VkImageViewCreateInfo{
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
            try check(c.vkCreateImageView.?(self.device.handle, &create_info, memory.vulkan_allocator, &image_view));
            try self.image_views.append(memory.default_allocator, image_view);
        }
    }

    fn destroyImageViews(self: *Swapchain, recreating: bool) void {
        for (self.image_views.items) |image_view| {
            c.vkDestroyImageView.?(self.device.handle, image_view, memory.vulkan_allocator);
        }

        if (recreating) {
            self.image_views.clearRetainingCapacity();
            self.images.clearRetainingCapacity();
        } else {
            self.image_views.deinit(memory.default_allocator);
            self.images.deinit(memory.default_allocator);
        }
    }

    fn createDepthStencilBuffer(self: *Swapchain, recreating: bool) !void {
        log.info("Creating swapchain depth stencil buffer...", .{});
        errdefer self.destroyDepthStencilBuffer(recreating);

        self.depth_stencil_image_format = c.VK_FORMAT_D32_SFLOAT_S8_UINT;
        try self.depth_stencil_image.init(self.vma, .{
            .format = self.depth_stencil_image_format,
            .extent = .{
                .width = self.extent.width,
                .height = self.extent.height,
                .depth = 1,
            },
            .usage_flags = c.VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
            .memory_flags = c.VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT,
            .memory_priority = 1.0,
        });

        const image_view_create_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = self.depth_stencil_image.handle,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = self.depth_stencil_image_format,
            .components = c.VkComponentMapping{
                .r = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .g = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .b = c.VK_COMPONENT_SWIZZLE_IDENTITY,
                .a = c.VK_COMPONENT_SWIZZLE_IDENTITY,
            },
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_DEPTH_BIT | c.VK_IMAGE_ASPECT_STENCIL_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        try check(c.vkCreateImageView.?(self.device.handle, &image_view_create_info, memory.vulkan_allocator, &self.depth_stencil_image_view));
    }

    fn destroyDepthStencilBuffer(self: *Swapchain, recreating: bool) void {
        if (self.depth_stencil_image_view != null) {
            c.vkDestroyImageView.?(self.device.handle, self.depth_stencil_image_view, memory.vulkan_allocator);
        }
        self.depth_stencil_image.deinit();

        if (recreating) {
            self.depth_stencil_image_view = null;
            self.depth_stencil_image = .{};
        }
    }

    fn createImageSynchronization(self: *Swapchain) !void {
        log.info("Creating swapchain image synchronization...", .{});

        try self.image_available_semaphores.ensureTotalCapacityPrecise(memory.default_allocator, self.max_inflight_frames);
        try self.frame_finished_semaphores.ensureTotalCapacityPrecise(memory.default_allocator, self.max_inflight_frames);
        try self.frame_inflight_fences.ensureTotalCapacityPrecise(memory.default_allocator, self.max_inflight_frames);

        for (0..self.max_inflight_frames) |_| {
            const semaphore_create_info = &c.VkSemaphoreCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
                .pNext = null,
                .flags = 0,
            };

            var image_available_semaphore: c.VkSemaphore = null;
            try check(c.vkCreateSemaphore.?(self.device.handle, semaphore_create_info, memory.vulkan_allocator, &image_available_semaphore));
            try self.image_available_semaphores.append(memory.default_allocator, image_available_semaphore);

            var frame_finished_semaphore: c.VkSemaphore = null;
            try check(c.vkCreateSemaphore.?(self.device.handle, semaphore_create_info, memory.vulkan_allocator, &frame_finished_semaphore));
            try self.frame_finished_semaphores.append(memory.default_allocator, frame_finished_semaphore);

            const fence_create_info = &c.VkFenceCreateInfo{
                .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
                .pNext = null,
                .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
            };

            var frame_inflight_fence: c.VkFence = null;
            try check(c.vkCreateFence.?(self.device.handle, fence_create_info, memory.vulkan_allocator, &frame_inflight_fence));
            try self.frame_inflight_fences.append(memory.default_allocator, frame_inflight_fence);
        }
    }

    fn destroyImageSynchronization(self: *Swapchain) void {
        for (self.image_available_semaphores.items) |semaphore| {
            c.vkDestroySemaphore.?(self.device.handle, semaphore, memory.vulkan_allocator);
        }

        for (self.frame_finished_semaphores.items) |semaphore| {
            c.vkDestroySemaphore.?(self.device.handle, semaphore, memory.vulkan_allocator);
        }

        for (self.frame_inflight_fences.items) |fence| {
            c.vkDestroyFence.?(self.device.handle, fence, memory.vulkan_allocator);
        }

        self.image_available_semaphores.deinit(memory.default_allocator);
        self.frame_finished_semaphores.deinit(memory.default_allocator);
        self.frame_inflight_fences.deinit(memory.default_allocator);
    }

    pub fn recreate(self: *Swapchain) !void {
        log.info("Recreating swapchain...", .{});
        std.debug.assert(self.handle != null);

        try self.surface.updateCapabilities();

        self.destroyDepthStencilBuffer(true);
        self.destroyImageViews(true);
        self.destroySwapchain();

        try self.createSwapchain();
        try self.createImageViews(true);
        try self.createDepthStencilBuffer(true);
    }

    pub fn acquireNextImage(self: *Swapchain) !struct {
        index: u32,
        available_semaphore: c.VkSemaphore,
        finished_semaphore: c.VkSemaphore,
        inflight_fence: c.VkFence,
    } {
        std.debug.assert(self.handle != null);
        std.debug.assert(self.device.handle != null);

        try check(c.vkWaitForFences.?(self.device.handle, 1, &self.frame_inflight_fences.items[self.frame_index], c.VK_TRUE, std.math.maxInt(u64)));

        var image_index: u32 = 0;
        const result = c.vkAcquireNextImageKHR.?(self.device.handle, self.handle, std.math.maxInt(u64), self.image_available_semaphores.items[self.frame_index], null, &image_index);

        switch (result) {
            c.VK_SUCCESS, c.VK_SUBOPTIMAL_KHR => {
                try check(c.vkResetFences.?(self.device.handle, 1, &self.frame_inflight_fences.items[self.frame_index]));

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

    pub fn recordLayoutTransitions(self: *Swapchain, command_buffer: *CommandBuffer, image_index: u32) void {
        std.debug.assert(self.handle != null);

        const color_attachment_layout_transition = c.VkImageMemoryBarrier2{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .pNext = null,
            .srcStageMask = c.VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,
            .srcAccessMask = 0,
            .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .oldLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
            .newLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .image = self.images.items[image_index],
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        const color_present_layout_transition = c.VkImageMemoryBarrier2{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2,
            .pNext = null,
            .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
            .srcAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
            .dstStageMask = c.VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT,
            .dstAccessMask = 0,
            .oldLayout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
            .newLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
            .srcQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .dstQueueFamilyIndex = c.VK_QUEUE_FAMILY_IGNORED,
            .image = self.images.items[image_index],
            .subresourceRange = c.VkImageSubresourceRange{
                .aspectMask = c.VK_IMAGE_ASPECT_COLOR_BIT,
                .baseMipLevel = 0,
                .levelCount = 1,
                .baseArrayLayer = 0,
                .layerCount = 1,
            },
        };

        const image_memory_barries = &[_]c.VkImageMemoryBarrier2{
            color_attachment_layout_transition,
            color_present_layout_transition,
        };

        c.vkCmdPipelineBarrier2.?(command_buffer.handle, &c.VkDependencyInfo{
            .sType = c.VK_STRUCTURE_TYPE_DEPENDENCY_INFO,
            .pNext = null,
            .dependencyFlags = 0,
            .memoryBarrierCount = 0,
            .pMemoryBarriers = null,
            .bufferMemoryBarrierCount = 0,
            .pBufferMemoryBarriers = null,
            .imageMemoryBarrierCount = image_memory_barries.len,
            .pImageMemoryBarriers = image_memory_barries.ptr,
        });
    }

    pub fn present(self: *Swapchain, present_info: *const c.VkPresentInfoKHR) !void {
        std.debug.assert(self.handle != null);
        std.debug.assert(self.device.handle != null);

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
