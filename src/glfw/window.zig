const std = @import("std");
const builtin = @import("builtin");
const root = @import("root");
const c = @import("../c.zig");
const memory = @import("../memory.zig");
const utility = @import("../utility.zig");
const log = std.log.scoped(.GLFW);

pub const Window = struct {
    pub const Config = struct {
        width: u32,
        height: u32,
        resizable: bool,
    };

    // Heap allocated memory for window callbacks
    pub const Heap = struct {
        width: u32 = undefined,
        height: u32 = undefined,
        resized: bool = false,
        minimized: bool = false,
    };

    heap: ?*Heap = null,
    title_buffer: []u8 = &[_]u8{},
    title_initial: [:0]const u8 = undefined,
    handle: ?*c.GLFWwindow = null,

    pub fn init(title: [:0]const u8) !Window {
        var self = Window{};
        errdefer self.deinit();

        self.heap = try memory.default_allocator.create(Heap);
        self.heap.?.* = .{};

        self.createTitleBuffer(title) catch {
            log.err("Failed to create title buffer", .{});
            return error.FailedToCreateTitleBuffer;
        };

        self.createWindow() catch {
            log.err("Failed to create window", .{});
            return error.FailedToCreateWindow;
        };

        return self;
    }

    pub fn deinit(self: *Window) void {
        self.destroyWindow();
        self.destroyTitleBuffer();

        if (self.heap) |heap| {
            memory.default_allocator.destroy(heap);
        }
        self.* = undefined;
    }

    fn createTitleBuffer(self: *Window, title: [:0]const u8) !void {
        self.title_buffer = try memory.default_allocator.alloc(u8, 256);
        self.title_initial = title;
    }

    fn destroyTitleBuffer(self: *Window) void {
        memory.default_allocator.free(self.title_buffer);
    }

    fn createWindow(self: *Window) !void {
        const config = root.config.window;

        c.glfwWindowHint(c.GLFW_CLIENT_API, c.GLFW_NO_API);
        c.glfwWindowHint(c.GLFW_RESIZABLE, if (config.resizable) c.GLFW_TRUE else c.GLFW_FALSE);
        c.glfwWindowHint(c.GLFW_VISIBLE, c.GLFW_FALSE);

        self.handle = c.glfwCreateWindow(@intCast(config.width), @intCast(config.height), "", null, null);
        if (self.handle == null) {
            return error.FailedToCreateWindow;
        }

        try self.updateTitle(0.0, 0.0);

        c.glfwSetWindowUserPointer(self.handle, self.heap);
        _ = c.glfwSetFramebufferSizeCallback(self.handle, framebufferSizeCallback);

        var width: c_int = undefined;
        var height: c_int = undefined;
        c.glfwGetFramebufferSize(self.handle, &width, &height);

        self.heap.?.width = @intCast(width);
        self.heap.?.height = @intCast(height);
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

    pub fn getWidth(self: *const Window) u32 {
        return self.heap.?.width;
    }

    pub fn getHeight(self: *const Window) u32 {
        return self.heap.?.height;
    }

    pub fn isMinimized(self: *const Window) bool {
        return self.heap.?.minimized;
    }

    pub fn handleResize(self: *Window) bool {
        const resized = self.heap.?.resized;
        self.heap.?.resized = false;
        return resized;
    }

    fn framebufferSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) callconv(.C) void {
        var heap = @as(?*Heap, @ptrCast(@alignCast(c.glfwGetWindowUserPointer(window)))) orelse unreachable;

        if (width > 0 and height > 0) {
            heap.width = @intCast(width);
            heap.height = @intCast(height);
            heap.resized = !heap.minimized;
            heap.minimized = false;
        } else {
            heap.minimized = true;
        }
    }
};
