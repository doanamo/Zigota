const std = @import("std");
const builtin = @import("builtin");
const root = @import("root");
const c = @import("../cimport/c.zig");
const memory = @import("../common/memory.zig");
const utility = @import("../common/utility.zig");
const log = std.log.scoped(.GLFW);

pub const Window = struct {
    pub const Config = struct {
        width: u32,
        height: u32,
        resizable: bool,
    };

    handle: ?*c.GLFWwindow = null,
    width: u32 = undefined,
    height: u32 = undefined,
    resized: bool = false,
    minimized: bool = false,

    title_buffer: []u8 = &[_]u8{},
    title_initial: [:0]const u8 = undefined,

    key_callback: struct {
        userdata: ?*anyopaque = null,
        function: ?*const fn (userdata: ?*anyopaque, key: c_int, scan_code: c_int, action: c_int, mods: c_int) void = null,
    } = .{},

    pub fn init(self: *Window, title: [:0]const u8) !void {
        errdefer self.deinit();

        self.createTitleBuffer(title) catch |err| {
            log.err("Failed to create title buffer: {}", .{err});
            return error.FailedToCreateTitleBuffer;
        };

        self.createWindow() catch |err| {
            log.err("Failed to create window: {}", .{err});
            return error.FailedToCreateWindow;
        };
    }

    pub fn deinit(self: *Window) void {
        self.destroyWindow();
        self.destroyTitleBuffer();
        self.* = .{};
    }

    fn createTitleBuffer(self: *Window, title: [:0]const u8) !void {
        self.title_buffer = try memory.default_allocator.alloc(u8, 256);
        self.title_initial = title;
    }

    fn destroyTitleBuffer(self: *Window) void {
        memory.default_allocator.free(self.title_buffer);
    }

    fn createWindow(self: *Window) !void {
        log.info("Creating window...", .{});
        const config = root.config.window;

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        c.glfwWindowHint(c.GLFW_RESIZABLE, if (config.resizable) c.GLFW_TRUE else c.GLFW_FALSE);
        c.glfwWindowHint(c.GLFW_VISIBLE, c.GLFW_FALSE);

        self.handle = c.glfwCreateWindow(@intCast(config.width), @intCast(config.height), "", null, null);
        if (self.handle == null) {
            return error.FailedToCreateWindow;
        }

        try self.updateTitle(0.0, 0.0);

        c.glfwSetWindowUserPointer(self.handle, self);
        _ = c.glfwSetFramebufferSizeCallback(self.handle, framebufferSizeCallback);
        _ = c.glfwSetKeyCallback(self.handle, keyCallback);

        var width: c_int = undefined;
        var height: c_int = undefined;
        c.glfwGetFramebufferSize(self.handle, &width, &height);

        self.width = @intCast(width);
        self.height = @intCast(height);
        log.info("Created {}x{} window", .{ width, height });
    }

    fn destroyWindow(self: *Window) void {
        if (self.handle != null) {
            c.glfwDestroyWindow(self.handle);
        }
    }

    pub fn show(self: *Window) void {
        std.debug.assert(self.handle != null);
        c.glfwShowWindow(self.handle);
    }

    pub fn hide(self: *Window) void {
        std.debug.assert(self.handle != null);
        c.glfwHideWindow(self.handle);
    }

    pub fn close(self: *Window) void {
        std.debug.assert(self.handle != null);
        c.glfwSetWindowShouldClose(self.handle, c.GLFW_TRUE);
    }

    pub fn setTitle(self: *Window, title: [:0]const u8) void {
        std.debug.assert(self.handle != null);
        c.glfwSetWindowTitle(self.handle, title.ptr);
    }

    pub fn shouldClose(self: *const Window) bool {
        std.debug.assert(self.handle != null);
        return c.glfwWindowShouldClose(self.handle) == c.GLFW_TRUE;
    }

    pub fn updateTitle(self: *Window, fps_count: f32, frame_time: f32) !void {
        var physical_memory: usize = undefined;
        var committed_memory: usize = undefined;
        c.mi_process_info(null, null, null, &physical_memory, null, &committed_memory, null, null);

        const format = "{s} - {s} - FPS: {d:.0} ({d:.2}ms) - RAM: {d:.2}MB (Committed: {d:.2}MB)";
        self.setTitle(try std.fmt.bufPrintZ(self.title_buffer, format, .{
            self.title_initial,
            @tagName(builtin.mode),
            fps_count,
            frame_time * std.time.ms_per_s,
            utility.toMegabytes(physical_memory),
            utility.toMegabytes(committed_memory),
        }));
    }

    pub fn handleResize(self: *Window) bool {
        const resized = self.resized;
        self.resized = false;
        return resized;
    }

    fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
        var self = @as(?*Window, @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)))) orelse unreachable;

        self.width = @intCast(width);
        self.height = @intCast(height);

        if (width > 0 and height > 0) {
            self.resized = !self.minimized;
            self.minimized = false;
        } else {
            self.minimized = true;
        }
    }

    fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scan_code: c_int, action: c_int, mods: c_int) callconv(.C) void {
        var self = @as(?*Window, @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)))) orelse unreachable;

        if (self.key_callback.function != null) {
            self.key_callback.function.?(self.key_callback.userdata, key, scan_code, action, mods);
        }
    }
};
