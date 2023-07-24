const std = @import("std");
const root = @import("root");
const builtin = @import("builtin");
const memory = @import("memory.zig");
const log = std.log.scoped(.Application);

const Window = @import("glfw/window.zig").Window;
const Renderer = @import("renderer.zig").Renderer;

pub const Application = struct {
    pub const Heap = struct {
        window: Window = .{},
        renderer: Renderer = .{},
    };

    heap: ?*Heap = null,
    fps_count: u32 = 0,
    fps_time: f32 = 0.0,

    pub fn init() !Application {
        log.info("Initializing...", .{});

        var self = Application{};
        errdefer self.deinit();

        self.heap = try memory.default_allocator.create(Heap);
        var heap = self.heap.?;
        heap.* = .{};

        const title = std.fmt.comptimePrint("{s} {}", .{
            root.project_name,
            root.project_version,
        });

        heap.window = Window.init(title) catch |err| {
            log.err("Failed to initialize window: {}", .{err});
            return error.FailedToInitializeWindow;
        };

        heap.renderer = Renderer.init(&heap.window) catch |err| {
            log.err("Failed to initialize renderer: {}", .{err});
            return error.FailedToInitializeRenderer;
        };

        return self;
    }

    pub fn deinit(self: *Application) void {
        log.info("Deinitializing...", .{});

        if (self.heap) |heap| {
            heap.renderer.deinit();
            heap.window.deinit();

            memory.default_allocator.destroy(heap);
        }
        self.* = undefined;
    }

    pub fn update(self: *Application, time_delta: f32) !void {
        var window = &self.heap.?.window;
        var renderer = &self.heap.?.renderer;

        self.fps_time += time_delta;
        if (self.fps_time >= 1.0) {
            const fps_count_avg = @as(f32, @floatFromInt(self.fps_count)) / self.fps_time;
            const frame_time_avg = self.fps_time / @as(f32, @floatFromInt(self.fps_count));
            try window.updateTitle(fps_count_avg, frame_time_avg);

            self.fps_count = 0;
            self.fps_time = 0.0;
        }

        if (window.handleResize()) {
            log.info("Window resized to {}x{}", .{ window.getWidth(), window.getHeight() });
            try renderer.recreateSwapchain();
        }

        try renderer.update(time_delta);
    }

    pub fn render(self: *Application) !void {
        var window = &self.heap.?.window;
        var renderer = &self.heap.?.renderer;

        if (!window.isMinimized()) {
            try renderer.render();
        } else {
            std.time.sleep(100 * std.time.ns_per_ms);
        }

        self.fps_count += 1;
    }
};
