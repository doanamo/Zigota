const c = @import("c.zig");
const std = @import("std");
const util = @import("util.zig");
const glfw = @import("glfw.zig");

var allocator: std.mem.Allocator = undefined;
const log_scoped = std.log.scoped(.Vulkan);

const validation_layers = &[_][*]const u8{
    "VK_LAYER_KHRONOS_validation",
    "VK_LAYER_KHRONOS_synchronization2",
};

const device_extensions = &[_][*]const u8{
    c.VK_KHR_SWAPCHAIN_EXTENSION_NAME,
};

var allocation_callbacks: c.VkAllocationCallbacks = undefined;
var physical_device_properties: c.VkPhysicalDeviceProperties = undefined;
var physical_device_features: c.VkPhysicalDeviceFeatures = undefined;
var surface_capabilities: c.VkSurfaceCapabilitiesKHR = undefined;
var swapchain_extent: c.VkExtent2D = undefined;
var swapchain_image_format: c.VkFormat = undefined;
var swapchain_color_space: c.VkColorSpaceKHR = undefined;
var queue_graphics_index: u32 = undefined;
var max_inflight_frames: u32 = undefined;

var last_result = c.VK_SUCCESS;
var instance: c.VkInstance = null;
var debug_callback: c.VkDebugReportCallbackEXT = null;
var surface: c.VkSurfaceKHR = null;
var physical_device: c.VkPhysicalDevice = null;
var device: c.VkDevice = null;
var queue_graphics: c.VkQueue = null;
var swapchain: c.VkSwapchainKHR = null;
var swapchain_images: ?[]c.VkImage = null;
var swapchain_image_views: ?[]c.VkImageView = null;
var command_pool: c.VkCommandPool = null;

var command_buffers: ?[]c.VkCommandBuffer = null;
var image_available_semaphores: ?[]c.VkSemaphore = null;
var render_finished_semaphores: ?[]c.VkSemaphore = null;
var frame_inflight_fences: ?[]c.VkFence = null;
var frame_current: u32 = 0;

var render_pass: c.VkRenderPass = null;
var framebuffers: ?[]c.VkFramebuffer = null;
var pipeline_layout: c.VkPipelineLayout = null;
var pipeline_graphics: c.VkPipeline = null;

fn allocationCallback(
    user_data: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: c.VkSystemAllocationScope,
) callconv(.C) ?*anyopaque {
    _ = allocation_scope;
    _ = user_data;
    return c.mi_malloc_aligned(size, alignment);
}

fn reallocationCallback(
    user_data: ?*anyopaque,
    old_allocation: ?*anyopaque,
    size: usize,
    alignment: usize,
    allocation_scope: c.VkSystemAllocationScope,
) callconv(.C) ?*anyopaque {
    _ = allocation_scope;
    _ = user_data;
    return c.mi_realloc_aligned(old_allocation, size, alignment);
}

fn freeCallback(user_data: ?*anyopaque, allocation: ?*anyopaque) callconv(.C) void {
    _ = user_data;
    c.mi_free(allocation);
}

pub fn checkResult(result: c.VkResult) !void {
    last_result = result;

    switch (result) {
        c.VK_SUCCESS => return,
        else => {
            if (std.debug.runtime_safety) {
                std.debug.panic("Vulkan error: {s} (code: {})", .{
                    c.vkResultToString(result),
                    result,
                });
            }
            return error.VulkanError;
        },
    }
}

pub fn init(window: glfw.Window, custom_allocator: std.mem.Allocator) !void {
    log_scoped.info("Initializing...", .{});
    errdefer deinit();

    allocator = custom_allocator;
    allocation_callbacks = c.VkAllocationCallbacks{
        .pUserData = null,
        .pfnAllocation = &allocationCallback,
        .pfnReallocation = &reallocationCallback,
        .pfnFree = &freeCallback,
        .pfnInternalAllocation = null,
        .pfnInternalFree = null,
    };

    createInstance() catch {
        log_scoped.err("Failed to create instance", .{});
        return error.FailedToCreateVulkanInstance;
    };

    createDebugCallback() catch {
        log_scoped.err("Failed to create debug callback", .{});
        return error.FailedToCreateVulkanDebugCallback;
    };

    selectPhysicalDevice() catch {
        log_scoped.err("Failed to select physical device", .{});
        return error.FailedToSelectVulkanPhysicalDevice;
    };

    createWindowSurface(window) catch {
        log_scoped.err("Failed to create window surface", .{});
        return error.FailedToCreateVulkanWindowSurface;
    };

    selectQueueFamilies() catch {
        log_scoped.err("Failed to select queue families", .{});
        return error.FailedToSelectVulkanQueueFamilies;
    };

    createLogicalDevice() catch {
        log_scoped.err("Failed to create logical device", .{});
        return error.FailedToCreateVulkanLogicalDevice;
    };

    createSwapchain(window) catch {
        log_scoped.err("Failed to create swapchain", .{});
        return error.FailedToCreateVulkanSwapchain;
    };

    createCommandPool() catch {
        log_scoped.err("Failed to create command pool", .{});
        return error.FailedToCreateVulkanCommandPool;
    };

    createCommandBuffers() catch {
        log_scoped.err("Failed to create command buffers", .{});
        return error.FailedToCreateVulkanCommandBuffers;
    };

    createRenderSynchronization() catch {
        log_scoped.err("Failed to create render synchronization", .{});
        return error.FailedToCreateVulkanRenderSynchronization;
    };

    createRenderPass() catch {
        log_scoped.err("Failed to create render pass", .{});
        return error.FailedToCreateVulkanRenderPass;
    };

    createFramebuffers() catch {
        log_scoped.err("Failed to create framebuffers", .{});
        return error.FailedToCreateVulkanFramebuffers;
    };

    createGraphicsPipeline() catch {
        log_scoped.err("Failed to create graphics pipeline", .{});
        return error.FailedToCreateVulkanGraphicsPipeline;
    };

    var version: u32 = 0;
    try checkResult(c.vkEnumerateInstanceVersion(&version));
    log_scoped.info("Initialized version {}.{}.{}", .{
        c.VK_VERSION_MAJOR(version),
        c.VK_VERSION_MINOR(version),
        c.VK_VERSION_PATCH(version),
    });
}

pub fn deinit() void {
    log_scoped.info("Deinitializing...", .{});

    if (device != null) {
        _ = c.vkDeviceWaitIdle(device);
    }

    // createGraphicsPipeline()
    if (pipeline_graphics != null) {
        c.vkDestroyPipeline(device, pipeline_graphics, &allocation_callbacks);
        pipeline_graphics = null;
    }

    if (pipeline_layout != null) {
        c.vkDestroyPipelineLayout(device, pipeline_layout, &allocation_callbacks);
        pipeline_layout = null;
    }

    // createFramebuffers()
    if (framebuffers != null) {
        for (framebuffers.?) |framebuffer| {
            if (framebuffer != null) {
                c.vkDestroyFramebuffer(device, framebuffer, &allocation_callbacks);
            }
        }

        allocator.free(framebuffers.?);
        framebuffers = null;
    }

    // createRenderPass()
    if (render_pass != null) {
        c.vkDestroyRenderPass(device, render_pass, &allocation_callbacks);
        render_pass = null;
    }

    // createRenderSynchronization()
    if (render_finished_semaphores != null) {
        for (render_finished_semaphores.?) |semaphore| {
            if (semaphore != null) {
                c.vkDestroySemaphore(device, semaphore, &allocation_callbacks);
            }
        }

        allocator.free(render_finished_semaphores.?);
        render_finished_semaphores = null;
    }

    if (image_available_semaphores != null) {
        for (image_available_semaphores.?) |semaphore| {
            if (semaphore != null) {
                c.vkDestroySemaphore(device, semaphore, &allocation_callbacks);
            }
        }

        allocator.free(image_available_semaphores.?);
        image_available_semaphores = null;
    }

    if (frame_inflight_fences != null) {
        for (frame_inflight_fences.?) |fence| {
            if (fence != null) {
                c.vkDestroyFence(device, fence, &allocation_callbacks);
            }
        }

        allocator.free(frame_inflight_fences.?);
        frame_inflight_fences = null;
    }

    // createCommandBuffers()
    if (command_buffers != null) {
        c.vkFreeCommandBuffers(device, command_pool, @intCast(u32, command_buffers.?.len), command_buffers.?.ptr);
        allocator.free(command_buffers.?);
        command_buffers = null;
    }

    // createCommandPool()
    if (command_pool != null) {
        c.vkDestroyCommandPool(device, command_pool, &allocation_callbacks);
        command_pool = null;
    }

    // createSwapchain()
    if (swapchain_image_views != null) {
        for (swapchain_image_views.?) |image_view| {
            if (image_view != null) {
                c.vkDestroyImageView(device, image_view, &allocation_callbacks);
            }
        }

        allocator.free(swapchain_image_views.?);
        swapchain_image_views = null;
    }

    if (swapchain_images != null) {
        allocator.free(swapchain_images.?);
        swapchain_images = null;
    }

    if (swapchain != null) {
        c.vkDestroySwapchainKHR(device, swapchain, &allocation_callbacks);
        swapchain = null;
    }

    swapchain_extent = undefined;
    swapchain_color_space = undefined;
    swapchain_image_format = undefined;
    max_inflight_frames = undefined;

    // createLogicalDevice()
    if (device != null) {
        c.vkDestroyDevice(device, &allocation_callbacks);
        device = null;
    }

    // selectQueueFamily()
    queue_graphics_index = undefined;
    queue_graphics = null;

    // createSurface()
    if (surface != null) {
        c.vkDestroySurfaceKHR(instance, surface, &allocation_callbacks);
        surface = null;
    }

    surface_capabilities = undefined;

    // selectPhysicalDevice()
    physical_device_properties = undefined;
    physical_device_features = undefined;
    physical_device = null;

    // createDebugCallback()
    if (debug_callback != null) {
        c.vkDestroyDebugReportCallbackEXT(instance, debug_callback, &allocation_callbacks);
        debug_callback = null;
    }

    // createInstance()
    if (instance != null) {
        c.vkDestroyInstance(instance, &allocation_callbacks);
        instance = null;
    }

    // init()
    allocator = undefined;
    last_result = c.VK_SUCCESS;
}

fn getRequiredInstanceExtensions() ![][*c]const u8 {
    var extensions = std.ArrayList([*c]const u8).init(allocator);
    defer extensions.deinit();

    var glfw_extension_count: u32 = 0;
    var glfw_extensions = c.glfwGetRequiredInstanceExtensions(&glfw_extension_count);
    try extensions.appendSlice(glfw_extensions[0..glfw_extension_count]);

    if (std.debug.runtime_safety) {
        try extensions.append(c.VK_EXT_DEBUG_REPORT_EXTENSION_NAME);
    }

    return extensions.toOwnedSlice();
}

fn createInstance() !void {
    log_scoped.info("Creating instance...", .{});

    const application_info = c.VkApplicationInfo{
        .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pNext = null,
        .pApplicationName = "Game",
        .applicationVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .pEngineName = "Custom",
        .engineVersion = c.VK_MAKE_VERSION(1, 0, 0),
        .apiVersion = c.VK_API_VERSION_1_3,
    };

    const extensions = try getRequiredInstanceExtensions();
    defer allocator.free(extensions);

    const create_info = c.VkInstanceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .pApplicationInfo = &application_info,
        .enabledLayerCount = if (std.debug.runtime_safety) @intCast(u32, validation_layers.len) else 0,
        .ppEnabledLayerNames = if (std.debug.runtime_safety) validation_layers else null,
        .enabledExtensionCount = @intCast(u32, extensions.len),
        .ppEnabledExtensionNames = extensions.ptr,
    };

    try checkResult(c.vkCreateInstance(&create_info, &allocation_callbacks, &instance));
}

fn debugCallback(
    flags: c.VkDebugReportFlagsEXT,
    objectType: c.VkDebugReportObjectTypeEXT,
    object: u64,
    location: usize,
    messageCode: i32,
    pLayerPrefix: [*c]const u8,
    pMessage: [*c]const u8,
    pUserData: ?*anyopaque,
) callconv(.C) c.VkBool32 {
    _ = flags;
    _ = objectType;
    _ = object;
    _ = location;
    _ = messageCode;
    _ = pLayerPrefix;
    _ = pUserData;

    log_scoped.debug("{s}", .{pMessage});
    return c.VK_FALSE;
}

fn createDebugCallback() !void {
    if (!std.debug.runtime_safety)
        return;

    log_scoped.info("Creating debug callback...", .{});

    const create_info = c.VkDebugReportCallbackCreateInfoEXT{
        .sType = c.VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
        .pNext = null,
        .flags = c.VK_DEBUG_REPORT_WARNING_BIT_EXT | c.VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT | c.VK_DEBUG_REPORT_ERROR_BIT_EXT,
        .pfnCallback = debugCallback,
        .pUserData = null,
    };

    try checkResult(c.vkCreateDebugReportCallbackEXT(instance, &create_info, &allocation_callbacks, &debug_callback));
}

fn selectPhysicalDevice() !void {
    // NOTE Simplified physical device selection
    // Select first physical device that is a dedictated GPU

    log_scoped.info("Selecting physical device...", .{});

    var physical_device_count: u32 = 0;
    try checkResult(c.vkEnumeratePhysicalDevices(instance, &physical_device_count, null));
    if (physical_device_count == 0) {
        log_scoped.err("Failed to find any physical devices", .{});
        return error.NoAvailableVulkanDevices;
    }

    const physical_devices = try allocator.alloc(c.VkPhysicalDevice, physical_device_count);
    defer allocator.free(physical_devices);
    try checkResult(c.vkEnumeratePhysicalDevices(instance, &physical_device_count, physical_devices.ptr));

    const PhysicalDeviceCandidate = struct {
        device: c.VkPhysicalDevice,
        properties: c.VkPhysicalDeviceProperties,
        features: c.VkPhysicalDeviceFeatures,
    };

    const physical_device_candidates = try allocator.alloc(PhysicalDeviceCandidate, physical_device_count);
    defer allocator.free(physical_device_candidates);

    for (physical_devices) |available_device, i| {
        physical_device_candidates[i].device = available_device;
        c.vkGetPhysicalDeviceProperties(available_device, &physical_device_candidates[i].properties);
        c.vkGetPhysicalDeviceFeatures(available_device, &physical_device_candidates[i].features);
        log_scoped.info("Available GPU: {s}", .{std.mem.sliceTo(&physical_device_candidates[i].properties.deviceName, 0)});
    }

    const DevicePrioritization = struct {
        fn sort(_: void, a: PhysicalDeviceCandidate, b: PhysicalDeviceCandidate) bool {
            return a.properties.deviceType > b.properties.deviceType; // Prefer discrete GPU over integrated GPU
        }
    };

    std.sort.sort(PhysicalDeviceCandidate, physical_device_candidates, {}, DevicePrioritization.sort);

    physical_device = physical_device_candidates[0].device;
    physical_device_properties = physical_device_candidates[0].properties;
    physical_device_features = physical_device_candidates[0].features;

    log_scoped.info("Selected GPU: {s} (Driver version: {}.{}.{}, Vulkan support: {}.{}.{})", .{
        std.mem.sliceTo(&physical_device_properties.deviceName, 0),
        c.VK_VERSION_MAJOR(physical_device_properties.driverVersion),
        c.VK_VERSION_MINOR(physical_device_properties.driverVersion),
        c.VK_VERSION_PATCH(physical_device_properties.driverVersion),
        c.VK_VERSION_MAJOR(physical_device_properties.apiVersion),
        c.VK_VERSION_MINOR(physical_device_properties.apiVersion),
        c.VK_VERSION_PATCH(physical_device_properties.apiVersion),
    });
}

fn createWindowSurface(window: glfw.Window) !void {
    log_scoped.info("Creating window surface...", .{});

    try checkResult(c.glfwCreateWindowSurface(instance, window.handle, &allocation_callbacks, &surface));
    try checkResult(c.vkGetPhysicalDeviceSurfaceCapabilitiesKHR(physical_device, surface, &surface_capabilities));
}

fn selectQueueFamilies() !void {
    // NOTE Simplified queue family selection
    // Select first queue that supports both graphics and presentation

    log_scoped.info("Selecting queue families...", .{});

    var queue_family_count: u32 = 0;
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, null);

    const queue_families = try allocator.alloc(c.VkQueueFamilyProperties, queue_family_count);
    defer allocator.free(queue_families);
    c.vkGetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_family_count, queue_families.ptr);

    var found_suitable_queue = false;
    for (queue_families) |queue_family, i| {
        var graphics_support = queue_family.queueFlags & c.VK_QUEUE_GRAPHICS_BIT != 0;
        var present_support: c.VkBool32 = c.VK_FALSE;

        try checkResult(c.vkGetPhysicalDeviceSurfaceSupportKHR(physical_device, @intCast(u32, i), surface, &present_support));

        if (queue_family.queueCount > 0 and graphics_support == true and present_support == c.VK_TRUE) {
            queue_graphics_index = @intCast(u32, i);
            found_suitable_queue = true;
            break;
        }
    }

    if (!found_suitable_queue) {
        log_scoped.err("Failed to find suitable queue family", .{});
        return error.NoSuitableVulkanQueueFamily;
    }
}

fn createLogicalDevice() !void {
    log_scoped.info("Creating logical device...", .{});

    const queue_priorities = [1]f32{1.0};
    const queue_create_info = c.VkDeviceQueueCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueFamilyIndex = queue_graphics_index,
        .queueCount = 1,
        .pQueuePriorities = &queue_priorities,
    };

    const device_features = std.mem.zeroes(c.VkPhysicalDeviceFeatures);
    const device_create_info = c.VkDeviceCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .queueCreateInfoCount = 1,
        .pQueueCreateInfos = &queue_create_info,
        .enabledLayerCount = if (std.debug.runtime_safety) @intCast(u32, validation_layers.len) else 0,
        .ppEnabledLayerNames = if (std.debug.runtime_safety) validation_layers else null,
        .enabledExtensionCount = @intCast(u32, device_extensions.len),
        .ppEnabledExtensionNames = device_extensions,
        .pEnabledFeatures = &device_features,
    };

    try checkResult(c.vkCreateDevice(physical_device, &device_create_info, &allocation_callbacks, &device));
    c.vkGetDeviceQueue(device, queue_graphics_index, 0, &queue_graphics);
}

fn createSwapchain(window: glfw.Window) !void {
    // NOTE Simplified surface format and present mode selection
    // Hardcoded swapchain preferences with most common support across most platforms

    log_scoped.info("Creating swapchain...", .{});

    swapchain_extent = c.VkExtent2D{
        .width = @intCast(u32, window.getWidth()),
        .height = @intCast(u32, window.getHeight()),
    };

    swapchain_image_format = c.VK_FORMAT_B8G8R8A8_UNORM;
    swapchain_color_space = c.VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;

    const swapchain_create_info = c.VkSwapchainCreateInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR,
        .pNext = null,
        .flags = 0,
        .surface = surface,
        .minImageCount = 2,
        .imageFormat = swapchain_image_format,
        .imageColorSpace = swapchain_color_space,
        .imageExtent = swapchain_extent,
        .imageArrayLayers = 1,
        .imageUsage = c.VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT,
        .imageSharingMode = c.VK_SHARING_MODE_EXCLUSIVE,
        .queueFamilyIndexCount = 0,
        .pQueueFamilyIndices = null,
        .preTransform = surface_capabilities.currentTransform,
        .compositeAlpha = c.VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR,
        .presentMode = c.VK_PRESENT_MODE_FIFO_KHR,
        .clipped = c.VK_TRUE,
        .oldSwapchain = null,
    };

    try checkResult(c.vkCreateSwapchainKHR(device, &swapchain_create_info, &allocation_callbacks, &swapchain));

    var image_count: u32 = 0;
    try checkResult(c.vkGetSwapchainImagesKHR(device, swapchain, &image_count, null));

    swapchain_images = try allocator.alloc(c.VkImage, image_count);
    try checkResult(c.vkGetSwapchainImagesKHR(device, swapchain, &image_count, swapchain_images.?.ptr));

    swapchain_image_views = try allocator.alloc(c.VkImageView, image_count);
    for (swapchain_image_views.?) |*image| {
        image.* = null;
    }

    for (swapchain_images.?) |image, i| {
        const image_view_create_info = c.VkImageViewCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .image = image,
            .viewType = c.VK_IMAGE_VIEW_TYPE_2D,
            .format = swapchain_image_format,
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

        try checkResult(c.vkCreateImageView(device, &image_view_create_info, &allocation_callbacks, &swapchain_image_views.?[i]));
    }

    max_inflight_frames = image_count;
}

fn createCommandPool() !void {
    log_scoped.info("Creating command pool...", .{});

    const command_pool_create_info = c.VkCommandPoolCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .pNext = null,
        .flags = c.VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT,
        .queueFamilyIndex = queue_graphics_index,
    };

    try checkResult(c.vkCreateCommandPool(device, &command_pool_create_info, &allocation_callbacks, &command_pool));
}

fn createCommandBuffers() !void {
    log_scoped.info("Creating command buffers...", .{});

    command_buffers = try allocator.alloc(c.VkCommandBuffer, max_inflight_frames);

    const command_buffer_allocate_info = c.VkCommandBufferAllocateInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .pNext = null,
        .commandPool = command_pool,
        .level = c.VK_COMMAND_BUFFER_LEVEL_PRIMARY,
        .commandBufferCount = @intCast(u32, command_buffers.?.len),
    };

    try checkResult(c.vkAllocateCommandBuffers(device, &command_buffer_allocate_info, command_buffers.?.ptr));
}

fn createRenderSynchronization() !void {
    log_scoped.info("Creating render synchronization...", .{});

    image_available_semaphores = try allocator.alloc(c.VkSemaphore, max_inflight_frames);
    render_finished_semaphores = try allocator.alloc(c.VkSemaphore, max_inflight_frames);
    frame_inflight_fences = try allocator.alloc(c.VkFence, max_inflight_frames);

    for (util.range(max_inflight_frames)) |_, i| {
        image_available_semaphores.?[i] = null;
        render_finished_semaphores.?[i] = null;
        frame_inflight_fences.?[i] = null;
    }

    for (util.range(max_inflight_frames)) |_, i| {
        const semaphore_create_info = c.VkSemaphoreCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
        };

        try checkResult(c.vkCreateSemaphore(device, &semaphore_create_info, &allocation_callbacks, &image_available_semaphores.?[i]));
        try checkResult(c.vkCreateSemaphore(device, &semaphore_create_info, &allocation_callbacks, &render_finished_semaphores.?[i]));

        const fence_create_info = c.VkFenceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FENCE_CREATE_INFO,
            .pNext = null,
            .flags = c.VK_FENCE_CREATE_SIGNALED_BIT,
        };

        try checkResult(c.vkCreateFence(device, &fence_create_info, &allocation_callbacks, &frame_inflight_fences.?[i]));
    }
}

fn createRenderPass() !void {
    log_scoped.info("Creating render pass...", .{});

    const color_attachment_desc = c.VkAttachmentDescription{
        .flags = 0,
        .format = swapchain_image_format,
        .samples = c.VK_SAMPLE_COUNT_1_BIT,
        .loadOp = c.VK_ATTACHMENT_LOAD_OP_CLEAR,
        .storeOp = c.VK_ATTACHMENT_STORE_OP_STORE,
        .stencilLoadOp = c.VK_ATTACHMENT_LOAD_OP_DONT_CARE,
        .stencilStoreOp = c.VK_ATTACHMENT_STORE_OP_DONT_CARE,
        .initialLayout = c.VK_IMAGE_LAYOUT_UNDEFINED,
        .finalLayout = c.VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
    };

    const color_attachment_ref = c.VkAttachmentReference{
        .attachment = 0,
        .layout = c.VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
    };

    const subpass_desc = c.VkSubpassDescription{
        .flags = 0,
        .pipelineBindPoint = c.VK_PIPELINE_BIND_POINT_GRAPHICS,
        .inputAttachmentCount = 0,
        .pInputAttachments = null,
        .colorAttachmentCount = 1,
        .pColorAttachments = &color_attachment_ref,
        .pResolveAttachments = null,
        .pDepthStencilAttachment = null,
        .preserveAttachmentCount = 0,
        .pPreserveAttachments = null,
    };

    const subpass_dependency = c.VkSubpassDependency{
        .srcSubpass = c.VK_SUBPASS_EXTERNAL,
        .dstSubpass = 0,
        .srcStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .dstStageMask = c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
        .srcAccessMask = 0,
        .dstAccessMask = c.VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT,
        .dependencyFlags = 0,
    };

    const render_pass_create_info = c.VkRenderPassCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .attachmentCount = 1,
        .pAttachments = &color_attachment_desc,
        .subpassCount = 1,
        .pSubpasses = &subpass_desc,
        .dependencyCount = 1,
        .pDependencies = &subpass_dependency,
    };

    try checkResult(c.vkCreateRenderPass(device, &render_pass_create_info, &allocation_callbacks, &render_pass));
}

fn createFramebuffers() !void {
    log_scoped.info("Creating framebuffers...", .{});

    framebuffers = try allocator.alloc(c.VkFramebuffer, swapchain_image_views.?.len);
    for (framebuffers.?) |*framebuffer| {
        framebuffer.* = null;
    }

    for (swapchain_image_views.?) |image_view, i| {
        const attachments = [_]c.VkImageView{
            image_view,
        };

        const framebuffer_create_info = c.VkFramebufferCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .renderPass = render_pass,
            .attachmentCount = attachments.len,
            .pAttachments = &attachments[0],
            .width = swapchain_extent.width,
            .height = swapchain_extent.height,
            .layers = 1,
        };

        try checkResult(c.vkCreateFramebuffer(device, &framebuffer_create_info, &allocation_callbacks, &framebuffers.?[i]));
    }
}

fn createShaderModule(path: []const u8) !c.VkShaderModule {
    log_scoped.info("Creating shader module from \"{s}\" file...", .{path});

    const code = try std.fs.cwd().readFileAllocOptions(allocator, path, util.megabytes(1), null, @alignOf(u32), null);
    defer allocator.free(code);

    const shader_module_create_info = c.VkShaderModuleCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .codeSize = code.len,
        .pCode = std.mem.bytesAsSlice(u32, code).ptr,
    };

    var shader_module: c.VkShaderModule = null;
    try checkResult(c.vkCreateShaderModule(device, &shader_module_create_info, &allocation_callbacks, &shader_module));
    return shader_module;
}

fn createGraphicsPipeline() !void {
    // TODO Should be moved to specialized renderer

    log_scoped.info("Creating graphics pipeline...", .{});

    const pipeline_layout_create_info = c.VkPipelineLayoutCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .setLayoutCount = 0,
        .pSetLayouts = null,
        .pushConstantRangeCount = 0,
        .pPushConstantRanges = null,
    };

    try checkResult(c.vkCreatePipelineLayout(device, &pipeline_layout_create_info, &allocation_callbacks, &pipeline_layout));

    const vertex_shader_module = try createShaderModule("data/shaders/simple.vert.spv");
    defer c.vkDestroyShaderModule(device, vertex_shader_module, &allocation_callbacks);

    const fragment_shader_module = try createShaderModule("data/shaders/simple.frag.spv");
    defer c.vkDestroyShaderModule(device, fragment_shader_module, &allocation_callbacks);

    const vertex_shader_stage_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = c.VK_SHADER_STAGE_VERTEX_BIT,
        .module = vertex_shader_module,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const fragment_shader_stage_info = c.VkPipelineShaderStageCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stage = c.VK_SHADER_STAGE_FRAGMENT_BIT,
        .module = fragment_shader_module,
        .pName = "main",
        .pSpecializationInfo = null,
    };

    const shader_stages = &[_]c.VkPipelineShaderStageCreateInfo{
        vertex_shader_stage_info,
        fragment_shader_stage_info,
    };

    const dynamic_states = &[_]c.VkDynamicState{
        c.VK_DYNAMIC_STATE_VIEWPORT,
        c.VK_DYNAMIC_STATE_SCISSOR,
    };

    const dynamic_state_create_info = c.VkPipelineDynamicStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .dynamicStateCount = dynamic_states.len,
        .pDynamicStates = dynamic_states,
    };

    const vertex_input_state_create_info = c.VkPipelineVertexInputStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .vertexBindingDescriptionCount = 0,
        .pVertexBindingDescriptions = null,
        .vertexAttributeDescriptionCount = 0,
        .pVertexAttributeDescriptions = null,
    };

    const input_assembly_state_create_info = c.VkPipelineInputAssemblyStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .topology = c.VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST,
        .primitiveRestartEnable = c.VK_FALSE,
    };

    const viewport_state_create_info = c.VkPipelineViewportStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .viewportCount = 1,
        .pViewports = null,
        .scissorCount = 1,
        .pScissors = null,
    };

    const rasterization_state_create_info = c.VkPipelineRasterizationStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .depthClampEnable = c.VK_FALSE,
        .rasterizerDiscardEnable = c.VK_FALSE,
        .polygonMode = c.VK_POLYGON_MODE_FILL,
        .cullMode = c.VK_CULL_MODE_BACK_BIT,
        .frontFace = c.VK_FRONT_FACE_CLOCKWISE,
        .depthBiasEnable = c.VK_FALSE,
        .depthBiasConstantFactor = 0.0,
        .depthBiasClamp = 0.0,
        .depthBiasSlopeFactor = 0.0,
        .lineWidth = 1.0,
    };

    const multisample_state_create_info = c.VkPipelineMultisampleStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .rasterizationSamples = c.VK_SAMPLE_COUNT_1_BIT,
        .sampleShadingEnable = c.VK_FALSE,
        .minSampleShading = 1.0,
        .pSampleMask = null,
        .alphaToCoverageEnable = c.VK_FALSE,
        .alphaToOneEnable = c.VK_FALSE,
    };

    const color_blend_attachment_state = c.VkPipelineColorBlendAttachmentState{
        .blendEnable = c.VK_FALSE,
        .srcColorBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstColorBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .colorBlendOp = c.VK_BLEND_OP_ADD,
        .srcAlphaBlendFactor = c.VK_BLEND_FACTOR_ONE,
        .dstAlphaBlendFactor = c.VK_BLEND_FACTOR_ZERO,
        .alphaBlendOp = c.VK_BLEND_OP_ADD,
        .colorWriteMask = c.VK_COLOR_COMPONENT_R_BIT | c.VK_COLOR_COMPONENT_G_BIT | c.VK_COLOR_COMPONENT_B_BIT | c.VK_COLOR_COMPONENT_A_BIT,
    };

    const color_blend_state_create_info = c.VkPipelineColorBlendStateCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .logicOpEnable = c.VK_FALSE,
        .logicOp = c.VK_LOGIC_OP_COPY,
        .attachmentCount = 1,
        .pAttachments = &color_blend_attachment_state,
        .blendConstants = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    };

    const graphics_pipeline_create_info = c.VkGraphicsPipelineCreateInfo{
        .sType = c.VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO,
        .pNext = null,
        .flags = 0,
        .stageCount = shader_stages.len,
        .pStages = shader_stages,
        .pVertexInputState = &vertex_input_state_create_info,
        .pInputAssemblyState = &input_assembly_state_create_info,
        .pTessellationState = null,
        .pViewportState = &viewport_state_create_info,
        .pRasterizationState = &rasterization_state_create_info,
        .pMultisampleState = &multisample_state_create_info,
        .pDepthStencilState = null,
        .pColorBlendState = &color_blend_state_create_info,
        .pDynamicState = &dynamic_state_create_info,
        .layout = pipeline_layout,
        .renderPass = render_pass,
        .subpass = 0,
        .basePipelineHandle = null,
        .basePipelineIndex = 0,
    };

    try checkResult(c.vkCreateGraphicsPipelines(device, null, 1, &graphics_pipeline_create_info, &allocation_callbacks, &pipeline_graphics));
}

fn recordCommandBuffer(command_buffer: c.VkCommandBuffer, image_index: u32) !void {
    var command_buffer_begin_info = c.VkCommandBufferBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
        .pNext = null,
        .flags = 0,
        .pInheritanceInfo = null,
    };

    try checkResult(c.vkBeginCommandBuffer(command_buffer, &command_buffer_begin_info));

    var render_pass_begin_info = c.VkRenderPassBeginInfo{
        .sType = c.VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
        .pNext = null,
        .renderPass = render_pass,
        .framebuffer = framebuffers.?[image_index],
        .renderArea = c.VkRect2D{
            .offset = c.VkOffset2D{
                .x = 0,
                .y = 0,
            },
            .extent = swapchain_extent,
        },
        .clearValueCount = 1,
        .pClearValues = &c.VkClearValue{
            .color = c.VkClearColorValue{
                .float32 = [_]f32{ 0.0, 0.0, 0.0, 1.0 },
            },
        },
    };

    c.vkCmdBeginRenderPass(command_buffer, &render_pass_begin_info, c.VK_SUBPASS_CONTENTS_INLINE);
    c.vkCmdBindPipeline(command_buffer, c.VK_PIPELINE_BIND_POINT_GRAPHICS, pipeline_graphics);

    const viewport = c.VkViewport{
        .x = 0.0,
        .y = 0.0,
        .width = @intToFloat(f32, swapchain_extent.width),
        .height = @intToFloat(f32, swapchain_extent.height),
        .minDepth = 0.0,
        .maxDepth = 1.0,
    };

    c.vkCmdSetViewport(command_buffer, 0, 1, &viewport);

    const scissors = c.VkRect2D{
        .offset = c.VkOffset2D{
            .x = 0,
            .y = 0,
        },
        .extent = swapchain_extent,
    };

    c.vkCmdSetScissor(command_buffer, 0, 1, &scissors);

    c.vkCmdDraw(command_buffer, 3, 1, 0, 0);
    c.vkCmdEndRenderPass(command_buffer);

    try checkResult(c.vkEndCommandBuffer(command_buffer));
}

pub fn render() !void {
    try checkResult(c.vkWaitForFences(device, 1, &frame_inflight_fences.?[frame_current], c.VK_TRUE, std.math.maxInt(u64)));
    try checkResult(c.vkResetFences(device, 1, &frame_inflight_fences.?[frame_current]));

    var image_current: u32 = 0;
    try checkResult(c.vkAcquireNextImageKHR(device, swapchain, std.math.maxInt(u64), image_available_semaphores.?[frame_current], null, &image_current));

    try checkResult(c.vkResetCommandBuffer(command_buffers.?[frame_current], 0));
    try recordCommandBuffer(command_buffers.?[frame_current], image_current);

    const submit_wait_semaphores = [_]c.VkSemaphore{
        image_available_semaphores.?[frame_current],
    };

    const submit_wait_stages = [_]c.VkPipelineStageFlags{
        c.VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT,
    };

    std.debug.assert(submit_wait_semaphores.len == submit_wait_stages.len);

    const submit_command_buffers = [_]c.VkCommandBuffer{
        command_buffers.?[frame_current],
    };

    const submit_signal_semaphores = [_]c.VkSemaphore{
        render_finished_semaphores.?[frame_current],
    };

    const submit_info = c.VkSubmitInfo{
        .sType = c.VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .pNext = null,
        .waitSemaphoreCount = submit_wait_semaphores.len,
        .pWaitSemaphores = &submit_wait_semaphores[0],
        .pWaitDstStageMask = &submit_wait_stages[0],
        .commandBufferCount = submit_command_buffers.len,
        .pCommandBuffers = &submit_command_buffers[0],
        .signalSemaphoreCount = submit_signal_semaphores.len,
        .pSignalSemaphores = &submit_signal_semaphores[0],
    };

    try checkResult(c.vkQueueSubmit(queue_graphics, 1, &submit_info, frame_inflight_fences.?[frame_current]));

    const present_info = c.VkPresentInfoKHR{
        .sType = c.VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
        .pNext = null,
        .waitSemaphoreCount = submit_signal_semaphores.len,
        .pWaitSemaphores = &submit_signal_semaphores[0],
        .swapchainCount = 1,
        .pSwapchains = &swapchain,
        .pImageIndices = &image_current,
        .pResults = null,
    };

    try checkResult(c.vkQueuePresentKHR(queue_graphics, &present_info));
    frame_current = (frame_current + 1) % max_inflight_frames;
}
