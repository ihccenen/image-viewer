const std = @import("std");

pub const Event = union(enum) {
    keyboard: u32,
    resize: struct { usize, usize },
};
