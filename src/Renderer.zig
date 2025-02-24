pub const Renderer = @This();

const gl = @import("gl.zig");
const Shader = @import("Shader.zig");
const Image = @import("Image.zig");
const Mat4 = @import("math.zig").Mat4;

shader: Shader,

vao: gl.GLuint,
vbo: gl.GLuint,
ebo: gl.GLuint,

viewport_width: usize = 0,
viewport_height: usize = 0,

texture: gl.GLuint,
texture_width: usize = 0,
texture_height: usize = 0,

scale: f32 = 1.0,
fit_screen_scale: f32 = 1.0,

translateX: f32 = 0.0,
translateY: f32 = 0.0,

pub fn init() !Renderer {
    const vertices = [_]f32{
        1.0, 1.0, 0.0, 1.0, 1.0, // top right
        1.0, -1.0, 0.0, 1.0, 0.0, // bottom right
        -1.0, -1.0, 0.0, 0.0, 0.0, // bottom left
        -1.0, 1.0, 0.0, 0.0, 1.0, // top left
    };

    const indices = [_]i32{
        0, 1, 3,
        1, 2, 3,
    };

    var vao: gl.GLuint = 0;
    gl.glGenVertexArrays(1, &vao);
    gl.glBindVertexArray(vao);

    var vbo: gl.GLuint = 0;
    gl.glGenBuffers(1, &vbo);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.GL_STATIC_DRAW);

    var ebo: gl.GLuint = 0;
    gl.glGenBuffers(1, &ebo);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, gl.GL_STATIC_DRAW);

    // position attribute
    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(0));
    gl.glEnableVertexAttribArray(0);
    // texture coord attribute
    gl.glVertexAttribPointer(1, 2, gl.GL_FLOAT, gl.GL_FALSE, 5 * @sizeOf(f32), @ptrFromInt(3 * @sizeOf(f32)));
    gl.glEnableVertexAttribArray(1);

    var texture: gl.GLuint = 0;
    gl.glGenTextures(1, &texture);
    gl.glBindTexture(gl.GL_TEXTURE_2D, texture);

    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_S, gl.GL_REPEAT);
    gl.glTexParameteri(gl.GL_TEXTURE_2D, gl.GL_TEXTURE_WRAP_T, gl.GL_REPEAT);

    return .{
        .shader = try Shader.init(),
        .vao = vao,
        .vbo = vbo,
        .ebo = ebo,
        .texture = texture,
    };
}

pub fn deinit(self: *Renderer) void {
    self.shader.deinit();
    gl.glDeleteVertexArrays(1, &self.vao);
    gl.glDeleteBuffers(1, &self.vbo);
    gl.glDeleteBuffers(1, &self.ebo);
}

pub fn setTexture(self: *Renderer, image: Image) void {
    self.texture_width = image.width;
    self.texture_height = image.height;
    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA, @intCast(image.width), @intCast(image.height), 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, @ptrCast(image.data.ptr));
}

pub fn viewport(self: *Renderer, width: usize, height: usize) void {
    if (self.texture_width > self.texture_height) {
        self.fit_screen_scale = @as(f32, @floatFromInt(height)) / @as(f32, @floatFromInt(self.texture_height));
    } else {
        self.fit_screen_scale = @as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(self.texture_width));
    }

    if (self.texture_width > width or self.texture_height > height) {
        self.scale = self.fit_screen_scale;
    }

    self.viewport_width = width;
    self.viewport_height = height;
    gl.glViewport(0, 0, @intCast(width), @intCast(height));
}

pub fn toggleFitScreen(self: *Renderer) void {
    if (self.scale != self.fit_screen_scale) {
        self.scale = self.fit_screen_scale;
    } else {
        self.scale = 1.0;
    }
}

pub const Zoom = enum {
    in,
    out,
    fit_screen,
    reset,
};

pub fn zoom(self: *Renderer, action: Zoom) void {
    self.scale = switch (action) {
        .in => @max(self.scale * @sqrt(2.0), 1.0 / 1024.0),
        .out => @min(self.scale / @sqrt(2.0), 1024.0),
        .fit_screen => if (self.scale != self.fit_screen_scale) self.fit_screen_scale else 1.0,
        .reset => 1.0,
    };
}

pub const Direction = enum {
    up,
    right,
    down,
    left,
};

pub fn move(self: *Renderer, direction: Direction) void {
    switch (direction) {
        .up => self.translateY -= 0.1,
        .right => self.translateX -= 0.1,
        .down => self.translateY += 0.1,
        .left => self.translateX += 0.1,
    }
}

pub fn render(self: Renderer) void {
    gl.glClearColor(0.0, 0.0, 0.0, 1.0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    gl.glBindTexture(gl.GL_TEXTURE_2D, self.texture);

    self.shader.use();

    self.shader.setMat4("scale", Mat4.scale(.{
        self.scale * (@as(f32, @floatFromInt(self.texture_width)) / @as(f32, @floatFromInt(self.viewport_width))),
        self.scale * (@as(f32, @floatFromInt(self.texture_height)) / @as(f32, @floatFromInt(self.viewport_height))),
        0.0,
    }));

    self.shader.setMat4("translate", Mat4.translate(.{ self.translateX, self.translateY, 0.0 }));

    gl.glBindVertexArray(self.vao);
    gl.glDrawElements(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, @ptrFromInt(0));
}
