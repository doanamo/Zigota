const std = @import("std");
const c = @import("../c.zig");
const utility = @import("utility.zig");
const log = utility.log_scoped;

pub const Window = struct {
    pub const Config = struct {
        title: [:0]const u8,
        width: i32 = 1024,
        height: i32 = 576,
        resizable: bool = false,
        visible: bool = false,
    };

    handle: ?*c.GLFWwindow = null,
    allocator: std.mem.Allocator = undefined,
    width: u32 = undefined,
    height: u32 = undefined,
    resized: bool = false,
    minimized: bool = false,

    pub fn init(self: *Window, config: *const Config, allocator: std.mem.Allocator) !void {
        self.allocator = allocator;
        errdefer self.deinit();

        self.createWindow(config) catch {
            log.err("Failed to create window", .{});
            return error.FailedToCreateWindow;
        };
    }

    pub fn deinit(self: *Window) void {
        if (self.handle != null) {
            c.glfwDestroyWindow(self.handle);
        }

        self.* = undefined;
    }

    fn createWindow(self: *Window, config: *const Config) !void {
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

        c.glfwSetWindowUserPointer(self.handle, self);
        _ = c.glfwSetFramebufferSizeCallback(self.handle, framebufferSizeCallback);

        var width: c_int = undefined;
        var height: c_int = undefined;
        c.glfwGetFramebufferSize(self.handle, &width, &height);

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
