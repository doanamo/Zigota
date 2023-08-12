const c = @import("../c/c.zig");
const math = @import("../math.zig");

pub const VertexTransformUniform = struct {
    model: math.Mat4,
    view: math.Mat4,
    projection: math.Mat4,
};
