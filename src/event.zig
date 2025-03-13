const std = @import("std");
const Image = @import("Image.zig");

pub const Event = union(enum) {
    keyboard: u32,
    pointer: union(enum) {
        button: u32,
        scroll: i24,
    },
    resize: struct { usize, usize },
    image_loaded: usize,
};
