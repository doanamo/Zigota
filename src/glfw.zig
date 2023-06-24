const c = @import("c.zig");
const std = @import("std");

//var allocator_callbacks: c.GLFWallocator = undefined; // TODO Waiting for GLFW 3.4.0
const log = std.log.scoped(.GLFW);

fn allocateCallback(size: usize, user: ?*anyopaque) callconv(.C) ?*anyopaque {
    _ = user;
    return c.mi_malloc(size);
}

fn reallocateCallback(block: ?*anyopaque, size: usize, user: ?*anyopaque) callconv(.C) ?*anyopaque {
    _ = user;
    return c.mi_realloc(block, size);
}

fn freeCallback(block: ?*anyopaque, user: ?*anyopaque) callconv(.C) void {
    _ = user;
    c.mi_free(block);
}

fn errorCallback(error_code: c_int, description: [*c]const u8) callconv(.C) void {
    log.err("{s} (Code: {})", .{ description, error_code });
}

fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
    var self = @ptrCast(*Window, @alignCast(@alignOf(Window), c.glfwGetWindowUserPointer(window)));

    if (width > 0 and height > 0) {
        self.width = @intCast(u32, width);
        self.height = @intCast(u32, height);
        self.resized = !self.minimized;
        self.minimized = false;
    } else {
        self.minimized = true;
    }
}

pub fn init() !void {
    log.info("Initializing...", .{});

    // TODO Waiting for GLFW 3.4.0
    // allocator_callbacks = .{
    //     .allocate = &allocateCallback,
    //     .reallocate = &reallocateCallback,
    //     .free = &freeCallback,
    //     .user = null,
    // };
    // c.glfwInitAllocator(&allocator_callbacks);

    if (c.glfwInit() == c.GLFW_FALSE) {
        log.err("Failed to initialize library", .{});
        return error.FailedToInitializeGLFWLibrary;
    }

    _ = c.glfwSetErrorCallback(errorCallback);

    var glfwVersionMajor: c_int = undefined;
    var glfwVersionMinor: c_int = undefined;
    var glfwVersionPatch: c_int = undefined;
    c.glfwGetVersion(&glfwVersionMajor, &glfwVersionMinor, &glfwVersionPatch);
    log.info("Initialized version {}.{}.{}", .{
        glfwVersionMajor, glfwVersionMinor, glfwVersionPatch,
    });
}

pub fn deinit() void {
    log.info("Deinitializing...", .{});
    c.glfwTerminate();
}

pub fn pollEvents() void {
    c.glfwPollEvents();
}

pub const WindowConfig = struct {
    title: [:0]const u8,
    width: i32 = 1024,
    height: i32 = 576,
    resizable: bool = false,
    visible: bool = false,
};

pub const Window = struct {
    handle: ?*c.GLFWwindow = null,
    width: u32 = undefined,
    height: u32 = undefined,
    resized: bool = false,
    minimized: bool = false,

    pub fn init(config: *const WindowConfig, allocator: std.mem.Allocator) !*Window {
        var self = try allocator.create(Window);
        errdefer self.deinit(allocator);

        self.createWindow(config) catch {
            log.err("Failed to create window", .{});
            return error.FailedToCreateWindow;
        };

        return self;
    }

    pub fn deinit(self: *Window, allocator: std.mem.Allocator) void {
        if (self.handle != null) {
            c.glfwDestroyWindow(self.handle);
        }

        allocator.destroy(self);
        self.* = undefined;
    }

    fn createWindow(self: *Window, config: *const WindowConfig) !void {
        log.info("Creating window...", .{});

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        c.glfwWindowHint(c.GLFW_RESIZABLE, if (config.resizable) c.GLFW_TRUE else c.GLFW_FALSE);
        c.glfwWindowHint(c.GLFW_VISIBLE, if (config.visible) c.GLFW_TRUE else c.GLFW_FALSE);

        self.handle = c.glfwCreateWindow(
            config.width,
            config.height,
            config.title.ptr,
            null,
            null,
        );

        if (self.handle == null) {
            return error.FailedToCreateWindow;
        }

        var width: c_int = undefined;
        var height: c_int = undefined;
        c.glfwGetFramebufferSize(self.handle, &width, &height);

        c.glfwSetWindowUserPointer(self.handle, self);
        _ = c.glfwSetFramebufferSizeCallback(self.handle, framebufferSizeCallback);

        self.width = @intCast(u32, width);
        self.height = @intCast(u32, height);
        log.info("Created {}x{} window", .{ self.width, self.height });
    }

    pub fn show(self: *Window) void {
        c.glfwShowWindow(self.handle);
    }

    pub fn hide(self: *Window) void {
        c.glfwHideWindow(self.handle);
    }

    pub fn setTitle(self: *Window, title: [:0]const u8) void {
        c.glfwSetWindowTitle(self.handle, title.ptr);
    }

    pub fn shouldClose(self: *const Window) bool {
        return c.glfwWindowShouldClose(self.handle) == c.GLFW_TRUE;
    }
};
