const std = @import("std");
const root = @import("root");
const builtin = @import("builtin");
const log = std.log.scoped(.Application);

const Window = @import("glfw/window.zig").Window;
const Renderer = @import("renderer.zig").Renderer;

pub const Application = struct {
    allocator: std.mem.Allocator = undefined,

    window: Window = .{},
    renderer: Renderer = .{},

    fps_count: u32 = 0,
    fps_time: f32 = 0.0,

    pub fn init(self: *Application, allocator: std.mem.Allocator) !void {
        log.info("Initializing...", .{});
        self.allocator = allocator;
        errdefer self.deinit();

        const title = std.fmt.comptimePrint("{s} {}.{}.{}", .{
            root.project_name,
            root.project_version.major,
            root.project_version.minor,
            root.project_version.patch,
        });

        self.window.init(title, allocator) catch {
            log.err("Failed to initialize window", .{});
            return error.FailedToInitializeWindow;
        };

        self.renderer.init(&self.window, allocator) catch {
            log.err("Failed to initialize renderer", .{});
            return error.FailedToInitializeRenderer;
        };
    }

    pub fn deinit(self: *Application) void {
        log.info("Deinitializing...", .{});

        self.renderer.deinit();
        self.window.deinit();

        self.* = undefined;
    }

    pub fn update(self: *Application, time_delta: f32) !void {
        self.fps_time += time_delta;
        if (self.fps_time >= 1.0) {
            const fps_count_avg = @intToFloat(f32, self.fps_count) / self.fps_time;
            const frame_time_avg = self.fps_time / @intToFloat(f32, self.fps_count);
            try self.window.updateTitle(fps_count_avg, frame_time_avg);

            self.fps_count = 0;
            self.fps_time = 0.0;
        }

        if (self.window.resized) {
            log.info("Window resized to {}x{}", .{ self.window.width, self.window.height });
            try self.renderer.recreateSwapchain();
            self.window.resized = false;
        }
    }

    pub fn render(self: *Application) !void {
        if (!self.window.minimized) {
            try self.renderer.render();
        } else {
            std.time.sleep(100 * std.time.ns_per_ms);
        }

        self.fps_count += 1;
    }
};
