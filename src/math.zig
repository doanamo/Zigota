const std = @import("std");

pub const Vec1 = @Vector(1, f32);
pub const Vec2 = @Vector(2, f32);
pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);
pub const Mat4 = [4]Vec4;

pub const Vec2Component = enum { x, y };
pub const Vec3Component = enum { x, y, z };
pub const Vec4Component = enum { x, y, z, w };

pub const default_right = Vec3{ 1.0, 0.0, 0.0 };
pub const default_forward = Vec3{ 0.0, 1.0, 0.0 };
pub const default_up = Vec3{ 0.0, 0.0, 1.0 };

pub inline fn radians(deg: f32) f32 {
    return std.math.degreesToRadians(f32, deg);
}

pub inline fn degrees(rad: f32) f32 {
    return std.math.radiansToDegrees(f32, rad);
}

pub inline fn wrapRadians(deg: f32) f32 {
    const max = 2.0 * std.math.pi;
    const mod = @mod(deg, max);
    return if (mod >= 0.0) mod else mod + max;
}

pub inline fn wrapDegrees(deg: f32) f32 {
    const max = degrees(2.0 * std.math.pi);
    const mod = @mod(deg, max);
    return if (mod >= 0.0) mod else mod + max;
}

pub inline fn splat(comptime T: type, value: f32) T {
    switch (T) {
        Vec2, Vec3, Vec4 => return @as(T, @splat(value)),
        else => @compileError("Expected vector, found '" ++ @typeName(T) ++ "'"),
    }
}

pub inline fn dot(a: anytype, b: @TypeOf(a)) f32 {
    switch (@TypeOf(a)) {
        Vec2, Vec3, Vec4 => return @reduce(.Add, a * b),
        else => @compileError("Expected vector, found '" ++ @typeName(@TypeOf(a)) ++ "'"),
    }
}

pub inline fn cross(a: Vec3, b: Vec3) Vec3 {
    const a1 = @shuffle(f32, a, undefined, [3]i32{ 1, 2, 0 });
    const b1 = @shuffle(f32, b, undefined, [3]i32{ 2, 0, 1 });
    const a2 = @shuffle(f32, a, undefined, [3]i32{ 2, 0, 1 });
    const b2 = @shuffle(f32, b, undefined, [3]i32{ 1, 2, 0 });
    return a1 * b1 - a2 * b2;
}

pub inline fn length(v: anytype) f32 {
    switch (@TypeOf(v)) {
        Vec2, Vec3, Vec4 => return @sqrt(dot(v, v)),
        else => @compileError("Expected vector, found '" ++ @typeName(@TypeOf(v)) ++ "'"),
    }
}

pub inline fn normalize(v: anytype) @TypeOf(v) {
    return v / splat(@TypeOf(v), length(v));
}

pub inline fn isNearEqual(a: anytype, b: anytype, epsilon: f32) bool {
    const delta = a - b;
    const epsilons = @as(@TypeOf(delta), @splat(epsilon));
    const result = @max(delta, -delta) <= epsilons;
    return @reduce(.And, result);
}

pub inline fn isNearZero(v: anytype, epsilon: f32) bool {
    const zeroes = @as(@TypeOf(v), @splat(0.0));
    return isNearEqual(v, zeroes, epsilon);
}

pub fn identity() Mat4 {
    return .{
        Vec4{ 1.0, 0.0, 0.0, 0.0 },
        Vec4{ 0.0, 1.0, 0.0, 0.0 },
        Vec4{ 0.0, 0.0, 1.0, 0.0 },
        Vec4{ 0.0, 0.0, 0.0, 1.0 },
    };
}

pub fn mul(a: Mat4, b: Mat4) Mat4 {
    var result: Mat4 = undefined;
    comptime var row: u32 = 0;
    inline while (row < 4) : (row += 1) {
        const vx = @shuffle(f32, a[row], undefined, [4]i32{ 0, 0, 0, 0 });
        const vy = @shuffle(f32, a[row], undefined, [4]i32{ 1, 1, 1, 1 });
        const vz = @shuffle(f32, a[row], undefined, [4]i32{ 2, 2, 2, 2 });
        const vw = @shuffle(f32, a[row], undefined, [4]i32{ 3, 3, 3, 3 });
        result[row] = @mulAdd(Vec4, vx, b[0], vz * b[2]) + @mulAdd(Vec4, vy, b[1], vw * b[3]);
    }
    return result;
}

pub fn transpose(m: Mat4) Mat4 {
    const v1 = @shuffle(f32, m[0], m[1], [4]i32{ 0, 1, ~@as(i32, 0), ~@as(i32, 1) });
    const v3 = @shuffle(f32, m[0], m[1], [4]i32{ 2, 3, ~@as(i32, 2), ~@as(i32, 3) });
    const v2 = @shuffle(f32, m[2], m[3], [4]i32{ 0, 1, ~@as(i32, 0), ~@as(i32, 1) });
    const v4 = @shuffle(f32, m[2], m[3], [4]i32{ 2, 3, ~@as(i32, 2), ~@as(i32, 3) });
    return .{
        @shuffle(f32, v1, v2, [4]i32{ 0, 2, ~@as(i32, 0), ~@as(i32, 2) }),
        @shuffle(f32, v1, v2, [4]i32{ 1, 3, ~@as(i32, 1), ~@as(i32, 3) }),
        @shuffle(f32, v3, v4, [4]i32{ 0, 2, ~@as(i32, 0), ~@as(i32, 2) }),
        @shuffle(f32, v3, v4, [4]i32{ 1, 3, ~@as(i32, 1), ~@as(i32, 3) }),
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

pub fn scaling(scale: Vec3) Mat4 {
    return .{
        Vec4{ scale[0], 0.0, 0.0, 0.0 },
        Vec4{ 0.0, scale[1], 0.0, 0.0 },
        Vec4{ 0.0, 0.0, scale[2], 0.0 },
        Vec4{ 0.0, 0.0, 0.0, 1.0 },
    };
}

pub fn lookTo(position: Vec3, direction: Vec3, up: Vec3) Mat4 {
    const f = direction;
    const s = normalize(cross(f, up));
    const u = cross(s, f);
    const t = Vec3{
        dot(s, position),
        dot(u, position),
        dot(f, position),
    } * splat(Vec3, -1.0);

    return .{
        Vec4{ s[0], u[0], -f[0], 0.0 },
        Vec4{ s[1], u[1], -f[1], 0.0 },
        Vec4{ s[2], u[2], -f[2], 0.0 },
        Vec4{ t[0], t[1], -t[2], 1.0 },
    };
}

pub fn lookAt(position: Vec3, target: Vec3, up: Vec3) Mat4 {
    return lookTo(position, normalize(target - position), up);
}

pub fn perspectiveFov(fovy: f32, aspect: f32, near: f32, far: f32) Mat4 {
    const tanHalfFovy = @tan(fovy * 0.5);
    const w = 1.0 / (aspect * tanHalfFovy);
    const h = -1.0 / tanHalfFovy;

    return .{
        Vec4{ w, 0.0, 0.0, 0.0 },
        Vec4{ 0.0, h, 0.0, 0.0 },
        Vec4{ 0.0, 0.0, far / (near - far), -1.0 },
        Vec4{ 0.0, 0.0, -(far * near) / (far - near), 0.0 },
    };
}
