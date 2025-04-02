const std = @import("std");
const Image = @import("Image.zig");

pub const Event = union(enum) {
    keyboard: u32,
    pointer: union(enum) {
        button: u32,
        axis: i24,
        motion: struct { x: i32, y: i32 },
    },
    resize: struct { c_int, c_int },
    image: struct {
        index: usize,
        image: Image,
    },
};
