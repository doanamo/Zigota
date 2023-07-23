const c = @import("../c.zig");

pub const max_attributes: u32 = 8;

pub const VertexAttributeFlags = packed struct(u32) {
    position: bool = false,
    normal: bool = false,
    color: bool = false,
    uv: bool = false,

    padding: u28 = undefined,

    pub fn isValid(self: VertexAttributeFlags) bool {
        var enabled_count: u32 = 0;
        if (self.position) enabled_count += 1;
        if (self.normal) enabled_count += 1;
        if (self.color) enabled_count += 1;
        if (self.uv) enabled_count += 1;

        if (enabled_count > max_attributes) {
            return false;
        }

        return self.position or self.normal or self.color or self.uv;
    }

    pub fn hasAttribute(self: VertexAttributeFlags, attribute: VertexAttributeType) bool {
        switch (attribute) {
            .Position => return self.position,
            .Normal => return self.normal,
            .Color => return self.color,
            .UV => return self.uv,
            else => return false,
        }
    }

    pub fn getCombinedSize(self: VertexAttributeFlags) u32 {
        var size: u32 = 0;
        if (self.position) size += getVertexAttributeSize(.Position);
        if (self.normal) size += getVertexAttributeSize(.Normal);
        if (self.color) size += getVertexAttributeSize(.Color);
        if (self.uv) size += getVertexAttributeSize(.UV);
        return size;
    }
};

pub const VertexAttributeType = enum {
    Float2,
    Float3,
    Float4,

    Position,
    Normal,
    Color,
    UV,
};

pub fn getVertexAttributeSize(attribute: VertexAttributeType) u32 {
    switch (attribute) {
        .Float2, .UV => return @sizeOf([2]f32),
        .Float3, .Position, .Normal => return @sizeOf([3]f32),
        .Float4, .Color => return @sizeOf([4]f32),
    }
}

pub fn getVertexAttributeFormat(attribute: VertexAttributeType) c.VkFormat {
    switch (attribute) {
        .Float2, .UV => return c.VK_FORMAT_R32G32_SFLOAT,
        .Float3, .Position, .Normal => return c.VK_FORMAT_R32G32B32_SFLOAT,
        .Float4, .Color => return c.VK_FORMAT_R32G32B32A32_SFLOAT,
    }
}
