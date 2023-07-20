const c = @import("../c.zig");

pub const VertexAttribute = enum {
    Float2,
    Float3,
    Float4,
};

pub fn getVertexAttributeSize(attribute: VertexAttribute) u32 {
    switch (attribute) {
        .Float2 => return @sizeOf([2]f32),
        .Float3 => return @sizeOf([3]f32),
        .Float4 => return @sizeOf([4]f32),
    }
}

pub fn getVertexAttributeFormat(attribute: VertexAttribute) c.VkFormat {
    switch (attribute) {
        .Float2 => return c.VK_FORMAT_R32G32_SFLOAT,
        .Float3 => return c.VK_FORMAT_R32G32B32_SFLOAT,
        .Float4 => return c.VK_FORMAT_R32G32B32A32_SFLOAT,
    }
}
