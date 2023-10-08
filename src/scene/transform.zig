const std = @import("std");
const math = @import("../common/math.zig");

pub const Transform = struct {
    position: math.Vec3 = .{ 0.0, 0.0, 0.0 },
    rotation: math.Vec3 = .{ 0.0, 0.0, 0.0 },
    scale: math.Vec3 = .{ 1.0, 1.0, 1.0 },

    transform: math.Mat4 = math.identity(),
    dirty: bool = true,

    pub fn getTransform(self: *Transform) *const math.Mat4 {
        if (self.dirty) {
            self.transform = math.scale(self.scale);
            self.transform = math.mul(self.transform, math.rotate(self.rotation));
            self.transform = math.mul(self.transform, math.translate(self.position));
            self.dirty = false;
        }
        return &self.transform;
    }
};
