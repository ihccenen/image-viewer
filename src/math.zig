const std = @import("std");

pub const Vec3 = @Vector(3, f32);
pub const Vec4 = @Vector(4, f32);

pub fn sincos(angle: f32) struct { f32, f32 } {
    return .{ @sin(angle), @cos(angle) };
}

pub const Mat4 = struct {
    data: [4]Vec4,

    pub fn diagonal(value: f32) Mat4 {
        return .{
            .data = .{
                .{ value, 0.0, 0.0, 0.0 },
                .{ 0.0, value, 0.0, 0.0 },
                .{ 0.0, 0.0, value, 0.0 },
                .{ 0.0, 0.0, 0.0, value },
            },
        };
    }

    pub fn scale(v: Vec3) Mat4 {
        return .{
            .data = .{
                .{ v[0], 0.0, 0.0, 0.0 },
                .{ 0.0, v[1], 0.0, 0.0 },
                .{ 0.0, 0.0, v[2], 0.0 },
                .{ 0.0, 0.0, 0.0, 1.0 },
            },
        };
    }

    pub fn translate(v: Vec3) Mat4 {
        return .{
            .data = .{
                .{ 1, 0, 0, 0 },
                .{ 0, 1, 0, 0 },
                .{ 0, 0, 1, 0 },
                .{ v[0], v[1], v[2], 1 },
            },
        };
    }

    pub fn orthographic(left: f32, right: f32, bottom: f32, top: f32, near: f32, far: f32) Mat4 {
        const r = 1 / (near - far);
        return .{
            .data = .{
                .{ 2.0 / (right - left), 0.0, 0.0, 0.0 },
                .{ 0.0, 2.0 / (top - bottom), 0.0, 0.0 },
                .{ 0.0, 0.0, r, 0.0 },
                .{ -(right + left) / (right - left), -(top + bottom) / (top - bottom), r * near, 1.0 },
            },
        };
    }
};
