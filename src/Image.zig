pub const Image = @This();

const stbi = @cImport({
    @cInclude("stb_image.h");
});

data: []u8,
width: usize,
height: usize,

pub fn init(path: [:0]const u8) !Image {
    var width: c_int = undefined;
    var height: c_int = undefined;
    stbi.stbi_set_flip_vertically_on_load(1);
    const data = stbi.stbi_load(path, &width, &height, null, 4);

    if (data == null) {
        return error.NoImageData;
    }

    errdefer stbi.stbi_image_free(data);

    if (width < 0) {
        return error.InvalidImageWidth;
    }

    return .{
        .data = data[0..@intCast(width * height * 4)],
        .width = @intCast(width),
        .height = @intCast(height),
    };
}

pub fn deinit(self: Image) void {
    stbi.stbi_image_free(@ptrCast(self.data.ptr));
}
