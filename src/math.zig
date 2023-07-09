const std = @import("std");

pub const Vec = @Vector(4, f32);
pub const Mat = [4]Vec;

pub fn identity() Mat {
    return Mat{
        Vec{ 1.0, 0.0, 0.0, 0.0 },
        Vec{ 0.0, 1.0, 0.0, 0.0 },
        Vec{ 0.0, 0.0, 1.0, 0.0 },
        Vec{ 0.0, 0.0, 0.0, 1.0 },
    };
}
