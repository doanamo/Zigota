const c = @import("../c.zig");

pub const max_attributes: u32 = 8;

pub const VertexAttributeFlags = packed struct(u32) {
    position: bool = false,
    normal: bool = false,
    color: bool = false,
    uv: bool = false,

    padding: u28 = undefined,

    pub fn isValid(self: VertexAttributeFlags) bool {
        if (self.getAttributeCount() > max_attributes) {
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
        }
    }

    pub fn getAttributeCount(self: VertexAttributeFlags) u32 {
        var count: u32 = 0;
        if (self.position) count += 1;
        if (self.normal) count += 1;
        if (self.color) count += 1;
        if (self.uv) count += 1;
        return count;
    }

    pub fn getTotalSize(self: VertexAttributeFlags) u32 {
        var size: u32 = 0;
        if (self.position) size += getVertexAttributeSize(.Position);
        if (self.normal) size += getVertexAttributeSize(.Normal);
        if (self.color) size += getVertexAttributeSize(.Color);
        if (self.uv) size += getVertexAttributeSize(.UV);
        return size;
    }
};

pub const VertexAttributeType = enum {
    Position,
    Normal,
    Color,
    UV,
};

pub fn getVertexAttributeSize(attribute: VertexAttributeType) u32 {
    switch (attribute) {
        .UV => return @sizeOf([2]f32),
        .Position, .Normal => return @sizeOf([3]f32),
        .Color => return @sizeOf([4]u8),
    }
}

pub fn getVertexAttributeFormat(attribute: VertexAttributeType) c.VkFormat {
    switch (attribute) {
        .UV => return c.VK_FORMAT_R32G32_SFLOAT,
        .Position, .Normal => return c.VK_FORMAT_R32G32B32_SFLOAT,
        .Color => return c.VK_FORMAT_R8G8B8A8_UNORM,
    }
}
