const std = @import("std");
const Image = @import("Image.zig");

pub const Event = union(enum) {
    keyboard: u32,
    resize: struct { usize, usize },
    image_loaded: usize,
};
