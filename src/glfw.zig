const c = @import("c.zig");
const std = @import("std");

var allocator: std.mem.Allocator = undefined;
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

    pub fn init(config: *const WindowConfig) !Window {
        var self = Window{};
        errdefer self.deinit();

        try self.createWindow(config);
        log.info("Created {}x{} window", .{
            self.getWidth(), self.getHeight(),
        });

        return self;
    }

    pub fn deinit(self: *Window) void {
        if (self.handle != null) {
            c.glfwDestroyWindow(self.handle);
        }
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
            log.err("Failed to create window", .{});
            return error.FailedToCreateGLFWWindow;
        }
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

    pub fn getWidth(self: *const Window) c_int {
        var width: c_int = undefined;
        c.glfwGetFramebufferSize(self.handle, &width, null);
        return width;
    }

    pub fn getHeight(self: *const Window) c_int {
        var height: c_int = undefined;
        c.glfwGetFramebufferSize(self.handle, null, &height);
        return height;
    }
};
