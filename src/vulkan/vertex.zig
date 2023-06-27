const c = @import("../c.zig");

pub const ColorVertex = struct {
    position: [3]f32,
    color: [4]f32,

    pub const binding_description = c.VkVertexInputBindingDescription{
        .binding = 0,
        .stride = @sizeOf(@This()),
        .inputRate = c.VK_VERTEX_INPUT_RATE_VERTEX,
    };

    pub const attribute_descriptions = [2]c.VkVertexInputAttributeDescription{
        c.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 0,
            .format = c.VK_FORMAT_R32G32B32_SFLOAT,
            .offset = @offsetOf(@This(), "position"),
        },
        c.VkVertexInputAttributeDescription{
            .binding = 0,
            .location = 1,
            .format = c.VK_FORMAT_R32G32B32A32_SFLOAT,
            .offset = @offsetOf(@This(), "color"),
        },
    };
};
