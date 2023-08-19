const std = @import("std");
const c = @import("../c/c.zig");
const memory = @import("../memory.zig");
const utility = @import("../utility.zig");
const math = @import("../math.zig");
const log = std.log.scoped(.Game);

const Input = @import("../glfw/input.zig").Input;
const Renderer = @import("../renderer/renderer.zig").Renderer;

pub const Game = struct {
    input: *Input = undefined,
    renderer: *Renderer = undefined,

    pub fn init(self: *Game, input: *Input, renderer: *Renderer) !void {
        log.info("Initializing game...", .{});
        errdefer self.deinit();

        self.input = input;
        self.renderer = renderer;
    }

    pub fn deinit(self: *Game) void {
        log.info("Deinitializing game...", .{});
        self.* = .{};
    }

    pub fn update(self: *Game, time_delta: f32) void {
        var movement_direction = math.Vec3{ 0.0, 0.0, 0.0 };

        if (self.input.keyboard.isPressed(c.GLFW_KEY_W)) {
            movement_direction += math.default_forward;
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_S)) {
            movement_direction -= math.default_forward;
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_D)) {
            movement_direction += math.default_right;
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_A)) {
            movement_direction -= math.default_right;
        }

        if (math.length(movement_direction) > 0.1) {
            const camera = &self.renderer.camera;
            camera.position += math.normalize(movement_direction) * math.splat(math.Vec3, time_delta);
            camera.recalculate_view = true;
        }
    }
};
