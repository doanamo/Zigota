const std = @import("std");
const root = @import("root");
const builtin = @import("builtin");
const c = @import("cimport/c.zig");
const memory = @import("common/memory.zig");
const log = std.log.scoped(.Application);

const Window = @import("glfw/window.zig").Window;
const Input = @import("glfw/input.zig").Input;
const Scene = @import("scene/scene.zig").Scene;
const Renderer = @import("renderer/renderer.zig").Renderer;
const Game = @import("game/game.zig").Game;

pub const Application = struct {
    window: Window = .{},
    input: Input = .{},
    scene: Scene = .{},
    renderer: Renderer = .{},
    game: Game = .{},

    fps_count: u32 = 0,
    fps_time: f32 = 0.0,

    pub fn init(self: *Application) !void {
        log.info("Initializing application...", .{});
        errdefer self.deinit();

        const title = std.fmt.comptimePrint("{s} {}", .{
            root.project_name,
            root.project_version,
        });

        self.window.init(title) catch |err| {
            log.err("Failed to initialize window: {}", .{err});
            return error.FailedToInitializeWindow;
        };

        self.input.init(&self.window) catch |err| {
            log.err("Failed to initialize input: {}", .{err});
            return error.FailedToInitializeInput;
        };

        self.scene.init() catch |err| {
            log.err("Failed to initialize scene: {}", .{err});
            return error.FailedToInitializeScene;
        };

        self.renderer.init(&self.window) catch |err| {
            log.err("Failed to initialize renderer: {}", .{err});
            return error.FailedToInitializeRenderer;
        };

        self.game.init(&self.input, &self.renderer) catch |err| {
            log.err("Failed to initialize game: {}", .{err});
            return error.FailedToInitializeGame;
        };
    }

    pub fn deinit(self: *Application) void {
        log.info("Deinitializing application...", .{});

        self.game.deinit();
        self.renderer.deinit();
        self.scene.deinit();
        self.input.deinit();
        self.window.deinit();
        self.* = .{};
    }

    pub fn update(self: *Application, time_delta: f32) !void {
        self.fps_time += time_delta;
        if (self.fps_time >= 1.0) {
            const fps_count_avg = @as(f32, @floatFromInt(self.fps_count)) / self.fps_time;
            const frame_time_avg = self.fps_time / @as(f32, @floatFromInt(self.fps_count));
            try self.window.updateTitle(fps_count_avg, frame_time_avg);

            self.fps_count = 0;
            self.fps_time = 0.0;
        }

        if (self.window.handleResize()) {
            log.info("Window resized to {}x{}", .{ self.window.width, self.window.height });
            try self.renderer.handleResize();
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_ESCAPE)) {
            self.window.close();
        }

        self.game.update(time_delta);
        self.renderer.update(time_delta);
    }

    pub fn render(self: *Application) !void {
        if (!self.window.minimized) {
            self.renderer.render() catch |err| {
                switch (err) {
                    error.SkipFrameRender => return,
                    else => return err,
                }
            };
        } else {
            std.time.sleep(100 * std.time.ns_per_ms);
        }

        self.fps_count += 1;
    }
};
