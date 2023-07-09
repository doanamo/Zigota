const c = @import("../c.zig");
const math = @import("../math.zig");

pub const VertexTransformUniform = struct {
    model: math.Mat,
    view: math.Mat,
    projection: math.Mat,
};
