const std = @import("std");
const root = @import("root");
const builtins = @import("builtins");
const c = @import("../cimport/c.zig");
const memory = @import("memory.zig");
const utility = @import("utility.zig");
const log = std.log.scoped(.Vulkan);
const check = utility.vulkanCheckResult;

pub const Instance = struct {
    pub const api_version = c.VK_API_VERSION_1_3;

    handle: c.VkInstance = null,
    debug_callback: c.VkDebugReportCallbackEXT = null,

    pub fn init(self: *Instance) !void {
        errdefer self.deinit();

        self.createInstance() catch |err| {
            log.err("Failed to create instance: {}", .{err});
            return error.FailedToCreateInstance;
        };

        self.createDebugCallback() catch |err| {
            log.err("Failed to create debug callback: {}", .{err});
            return error.FailedToCreateDebugCallback;
        };
    }

    pub fn deinit(self: *Instance) void {
        self.destroyDebugCallback();
        self.destroyInstance();
        self.* = .{};
    }

    fn createInstance(self: *Instance) !void {
        log.info("Creating instance...", .{});

        try check(c.volkInitialize());

        const project_version = c.VK_MAKE_VERSION(
            root.project_version.major,
            root.project_version.minor,
            root.project_version.patch,
        );

        const application_info = c.VkApplicationInfo{
            .sType = c.VK_STRUCTURE_TYPE_APPLICATION_INFO,
            .pNext = null,
            .pApplicationName = root.project_name,
            .applicationVersion = project_version,
            .pEngineName = root.project_name,
            .engineVersion = project_version,
            .apiVersion = api_version,
        };

        const validation_layers = getValidationLayers();
        const extensions = try getExtensions();
        defer memory.default_allocator.free(extensions);

        const create_info = c.VkInstanceCreateInfo{
            .sType = c.VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
            .pNext = null,
            .flags = 0,
            .pApplicationInfo = &application_info,
            .enabledLayerCount = if (std.debug.runtime_safety) @intCast(validation_layers.len) else 0,
            .ppEnabledLayerNames = if (std.debug.runtime_safety) &validation_layers else null,
            .enabledExtensionCount = @intCast(extensions.len),
            .ppEnabledExtensionNames = extensions.ptr,
        };

        try check(c.vkCreateInstance.?(&create_info, memory.vulkan_allocator, &self.handle));
        c.volkLoadInstanceOnly(self.handle);

        var instance_version: u32 = 0;
        try check(c.vkEnumerateInstanceVersion.?(&instance_version));
        log.info("Instance version {}.{}.{}", .{
            c.VK_VERSION_MAJOR(instance_version),
            c.VK_VERSION_MINOR(instance_version),
            c.VK_VERSION_PATCH(instance_version),
        });
    }

    fn destroyInstance(self: *Instance) void {
        if (self.handle != null) {
            c.vkDestroyInstance.?(self.handle, memory.vulkan_allocator);
        }
    }

    fn createDebugCallback(self: *Instance) !void {
        if (!std.debug.runtime_safety)
            return;

        log.info("Creating debug callback...", .{});

        const create_info = c.VkDebugReportCallbackCreateInfoEXT{
            .sType = c.VK_STRUCTURE_TYPE_DEBUG_REPORT_CALLBACK_CREATE_INFO_EXT,
            .pNext = null,
            .flags = c.VK_DEBUG_REPORT_WARNING_BIT_EXT | c.VK_DEBUG_REPORT_PERFORMANCE_WARNING_BIT_EXT | c.VK_DEBUG_REPORT_ERROR_BIT_EXT,
            .pfnCallback = debugCallback,
            .pUserData = null,
        };

        try check(c.vkCreateDebugReportCallbackEXT.?(self.handle, &create_info, memory.vulkan_allocator, &self.debug_callback));
    }

    fn destroyDebugCallback(self: *Instance) void {
        if (!std.debug.runtime_safety)
            return;

        if (self.debug_callback != null) {
            c.vkDestroyDebugReportCallbackEXT.?(self.handle, self.debug_callback, memory.vulkan_allocator);
        }
    }

    pub fn getValidationLayers() [1][*c]const u8 {
        return [_][*c]const u8{
            "VK_LAYER_KHRONOS_validation",
        };
    }

    pub fn getExtensions() ![][*c]const u8 {
        var extensions = std.ArrayList([*c]const u8).init(memory.default_allocator);
        defer extensions.deinit();

        var glfw_extension_count: u32 = 0;
        var glfw_extensions = c.glfwGetRequiredInstanceExtensions(&glfw_extension_count);
        try extensions.appendSlice(glfw_extensions[0..glfw_extension_count]);

        if (comptime std.debug.runtime_safety) {
            try extensions.append(c.VK_EXT_DEBUG_REPORT_EXTENSION_NAME);
        }

        return extensions.toOwnedSlice();
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

        log.debug("{s}", .{pMessage});
        @breakpoint();
        return c.VK_FALSE;
    }
};
