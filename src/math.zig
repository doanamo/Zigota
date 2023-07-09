const std = @import("std");

pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);
pub const Mat4 = [4]Vec4;

pub fn radians(deg: f32) f32 {
    return std.math.degreesToRadians(f32, deg);
}

pub fn degrees(rad: f32) f32 {
    return std.math.radiansToDegrees(f32, rad);
}

pub fn splat3(value: f32) Vec3 {
    return @splat(3, value);
}

pub fn splat4(value: f32) Vec4 {
    return @splat(4, value);
}

pub fn identity() Mat4 {
    return .{
        Vec4{ 1.0, 0.0, 0.0, 0.0 },
        Vec4{ 0.0, 1.0, 0.0, 0.0 },
        Vec4{ 0.0, 0.0, 1.0, 0.0 },
        Vec4{ 0.0, 0.0, 0.0, 1.0 },
    };
}

pub fn translation(offset: Vec3) Mat4 {
    return .{
        Vec4{ 1.0, 0.0, 0.0, 0.0 },
        Vec4{ 0.0, 1.0, 0.0, 0.0 },
        Vec4{ 0.0, 0.0, 1.0, 0.0 },
        Vec4{ offset[0], offset[1], offset[2], 1.0 },
    };
}

pub fn rotation(angles: Vec3) Mat4 {
    const s = Vec3{ @sin(angles[0]), @sin(angles[1]), @sin(angles[2]) };
    const c = Vec3{ @cos(angles[0]), @cos(angles[1]), @cos(angles[2]) };
    const t = Vec3{ c[2] * s[0], c[0] * c[2], s[1] * s[2] };

    return .{
        Vec4{ c[1] * c[2], t[0] * s[1] + c[0] * s[2], -t[1] * s[1] + s[0] * s[2], 0.0 },
        Vec4{ -c[1] * s[2], t[1] - s[0] * t[2], t[0] + c[0] * t[2], 0.0 },
        Vec4{ s[1], -c[1] * s[0], c[0] * c[1], 0.0 },
        Vec4{ 0.0, 0.0, 0.0, 1.0 },
    };
}

pub fn perspectiveFov(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
    // Left handed perspective projection matrix with depth in [0.0, 1.0] range
    const tanHalfFovy = @tan(fovy * 0.5);

    const w = 1 / (aspect * tanHalfFovy);
    const h = 1 / tanHalfFovy;
    const r = far - near;

    return .{
        Vec4{ w, 0.0, 0.0, 0.0 },
        Vec4{ 0.0, h, 0.0, 0.0 },
        Vec4{ 0.0, 0.0, far / r, 1.0 },
        Vec4{ 0.0, 0.0, -(near * far) / r, 0.0 },
    };
}
