const std = @import("std");
const c = @import("../c/c.zig");
const math = @import("../math.zig");
const memory = @import("../memory.zig");
const utility = @import("../utility.zig");
const log = std.log.scoped(.Renderer);

pub const Camera = struct {
    fov: f32 = 70.0,
    aspect_ratio: f32 = 1.0,
    near_plane: f32 = 0.01,
    far_plane: f32 = 1000.0,

    position: math.Vec3 = .{ 0.0, 0.0, 0.0 },
    forward: math.Vec3 = math.default_forward,
    up: math.Vec3 = math.default_up,

    projection: math.Mat4 = undefined,
    view: math.Mat4 = undefined,

    recalculate_projection: bool = true,
    recalculate_view: bool = true,

    pub fn getProjection(self: *Camera) math.Mat4 {
        if (self.recalculate_projection) {
            self.projection = math.perspectiveFov(
                math.radians(self.fov),
                self.aspect_ratio,
                self.near_plane,
                self.far_plane,
            );
            self.recalculate_projection = false;
        }
        return self.projection;
    }

    pub fn getView(self: *Camera) math.Mat4 {
        if (self.recalculate_view) {
            self.view = math.lookTo(self.position, self.forward, self.up);
            self.recalculate_view = false;
        }
        return self.view;
    }
};
