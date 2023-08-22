const std = @import("std");
const c = @import("../c/c.zig");
const memory = @import("../common/memory.zig");
const utility = @import("../common/utility.zig");
const math = @import("../common/math.zig");
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
        const camera = &self.renderer.camera;
        var rotation = math.Vec3{ 0.0, 0.0, 0.0 };
        var movement = math.Vec3{ 0.0, 0.0, 0.0 };

        if (self.input.keyboard.isPressed(c.GLFW_KEY_UP)) {
            rotation[0] += time_delta * 100.0;
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_DOWN)) {
            rotation[0] -= time_delta * 100.0;
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_RIGHT)) {
            rotation[2] += time_delta * 100.0;
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_LEFT)) {
            rotation[2] -= time_delta * 100.0;
        }

        if (!math.isNearZero(rotation, 0.001)) {
            camera.rotation += rotation;
            camera.recalculate_forward = true;
            camera.recalculate_view = true;
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_W)) {
            movement += math.default_forward;
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_S)) {
            movement -= math.default_forward;
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_D)) {
            movement += math.default_right;
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_A)) {
            movement -= math.default_right;
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_SPACE)) {
            movement += math.default_up;
        }

        if (self.input.keyboard.isPressed(c.GLFW_KEY_C)) {
            movement -= math.default_up;
        }

        if (math.length(movement) > 0.001) {
            movement = math.normalize(movement);
            camera.position += camera.getRight() * math.splat(math.Vec3, time_delta * movement[0]);
            camera.position += camera.getForward() * math.splat(math.Vec3, time_delta * movement[1]);
            camera.position += camera.getUp() * math.splat(math.Vec3, time_delta * movement[2]);
            camera.recalculate_view = true;
        }
    }
};
