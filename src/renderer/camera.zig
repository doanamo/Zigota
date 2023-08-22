const std = @import("std");
const c = @import("../c/c.zig");
const math = @import("../common/math.zig");
const log = std.log.scoped(.Renderer);

pub const Camera = struct {
    fov: f32 = 70.0,
    aspect_ratio: f32 = 1.0,
    near_plane: f32 = 0.01,
    far_plane: f32 = 1000.0,

    position: math.Vec3 = .{ 0.0, 0.0, 0.0 },
    rotation: math.Vec3 = .{ 0.0, 0.0, 0.0 },

    forward: math.Vec3 = undefined,
    projection: math.Mat4 = undefined,
    view: math.Mat4 = undefined,

    recalculate_forward: bool = true,
    recalculate_projection: bool = true,
    recalculate_view: bool = true,

    pub fn getForward(self: *Camera) math.Vec3 {
        if (self.recalculate_forward) {
            self.rotation = .{
                math.wrapDegrees(self.rotation[0]),
                math.wrapDegrees(self.rotation[1]),
                math.wrapDegrees(self.rotation[2]),
            };
            self.forward = math.normalize(math.Vec3{
                @sin(math.radians(self.rotation[2])) * @cos(math.radians(self.rotation[0])),
                @cos(math.radians(self.rotation[2])) * @cos(math.radians(self.rotation[0])),
                @sin(math.radians(self.rotation[0])),
            });
            self.recalculate_forward = false;
        }
        return self.forward;
    }

    pub fn getRight(self: *Camera) math.Vec3 {
        return math.normalize(math.cross(self.getForward(), self.getUp()));
    }

    pub fn getUp(_: *Camera) math.Vec3 {
        return math.default_up;
    }

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
            self.view = math.lookTo(self.position, self.getForward(), self.getUp());
            self.recalculate_view = false;
        }
        return self.view;
    }
};
