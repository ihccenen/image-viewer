pub const Renderer = @This();

const gl = @import("gl.zig");
const Shader = @import("Shader.zig");
const Image = @import("Image.zig");
const Mat4 = @import("math.zig").Mat4;

pub const Fit = enum {
    width,
    both,
    none,
};

shader: Shader,

vao: gl.GLuint,
vbo: gl.GLuint,
ebo: gl.GLuint,

viewport: struct {
    width: f32,
    height: f32,
},

texture: struct {
    id: gl.GLuint,
    width: f32,
    height: f32,
},

scale: struct {
    factor: f32,
    width: f32,
    height: f32,
},

fit: struct {
    state: Fit,
    width: f32,
    both: f32,
},

translate: struct {
    max_x: f32,
    x: f32,
    max_y: f32,
    y: f32,
},

need_redraw: bool = false,

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
    gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, texture);

    gl.glTexParameteri(gl.GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_MIN_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_MAG_FILTER, gl.GL_LINEAR);
    gl.glTexParameteri(gl.GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_WRAP_S, gl.GL_CLAMP_TO_EDGE);
    gl.glTexParameteri(gl.GL_TEXTURE_2D_ARRAY, gl.GL_TEXTURE_WRAP_T, gl.GL_CLAMP_TO_EDGE);

    const shader = try Shader.init();
    shader.setInt("textures", 0);

    return .{
        .shader = shader,
        .vao = vao,
        .vbo = vbo,
        .ebo = ebo,
        .viewport = .{ .width = 0, .height = 0 },
        .texture = .{ .id = texture, .width = 0, .height = 0 },
        .scale = .{ .factor = 1, .width = 1, .height = 1 },
        .fit = .{ .state = .both, .width = 1, .both = 1 },
        .translate = .{ .max_x = 0, .x = 0, .max_y = 0, .y = 0 },
        .need_redraw = false,
    };
}

pub fn deinit(self: *Renderer) void {
    self.shader.deinit();
    gl.glDeleteVertexArrays(1, &self.vao);
    gl.glDeleteBuffers(1, &self.vbo);
    gl.glDeleteBuffers(1, &self.ebo);
}

pub fn resetScaleAndTranslate(self: *Renderer) void {
    self.scale.factor = 1.0;
    self.fit.state = .none;

    self.translate.max_x = @max((self.texture.width - self.viewport.width) / self.texture.width, 0);
    self.translate.max_y = @max((self.texture.height - self.viewport.height) / self.texture.height, 0);

    self.translate.x = self.translate.max_x;
    self.translate.y = -self.translate.max_y;
}

pub fn setFit(self: *Renderer, state: Fit) void {
    self.fit.state = state;
    self.translate.x = 0.0;

    switch (state) {
        .width => {
            self.translate.x = 0.0;
            self.scale.factor = self.fit.width;
            self.translate.max_y = @max((self.scale.factor * self.texture.height - self.viewport.height) / (self.scale.factor * self.texture.height), 0);
            self.translate.y = self.translate.max_y;
        },
        .both => {
            self.translate.y = 0.0;
            self.scale.factor = self.fit.both;
        },
        .none => self.resetScaleAndTranslate(),
    }

    self.scale.width = self.scale.factor * (self.texture.width / self.viewport.width);
    self.scale.height = self.scale.factor * (self.texture.height / self.viewport.height);

    self.need_redraw = true;
}

pub fn setTexture(self: *Renderer, image: Image) void {
    self.texture.width = @floatFromInt(image.width);
    self.texture.height = @floatFromInt(image.height);

    self.fit.width = self.viewport.width / self.texture.width;
    self.fit.both = @min(self.fit.width, self.viewport.height / self.texture.height);

    const width = image.width / 2;
    const height = image.height / 2;
    const layer_count = 4;

    gl.glPixelStorei(gl.GL_UNPACK_ROW_LENGTH, @intCast(image.width));
    gl.glPixelStorei(gl.GL_UNPACK_IMAGE_HEIGHT, @intCast(image.height));
    gl.glPixelStorei(gl.GL_UNPACK_ALIGNMENT, 1);

    gl.glTexImage3D(gl.GL_TEXTURE_2D_ARRAY, 0, gl.GL_RGBA8, @intCast(width), @intCast(height), layer_count, 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, null);

    for (0..2) |x| {
        for (0..2) |y| {
            gl.glTexSubImage3D(
                gl.GL_TEXTURE_2D_ARRAY,
                0,
                0,
                0,
                @intCast(x * 2 + y),
                @intCast(width),
                @intCast(height),
                1,
                gl.GL_RGBA,
                gl.GL_UNSIGNED_BYTE,
                @ptrCast(image.data.ptr + (x * height * @as(usize, @intCast(image.width)) + y * width) * 4),
            );
        }
    }

    self.setFit(self.fit.state);
}

pub fn setViewport(self: *Renderer, width: c_int, height: c_int) void {
    self.viewport.width = @floatFromInt(width);
    self.viewport.height = @floatFromInt(height);

    self.fit.width = self.viewport.width / self.texture.width;
    self.fit.both = @min(self.fit.width, self.viewport.height / self.texture.height);

    self.translate.max_x = @max((self.texture.width - self.viewport.width) / self.texture.width, 0);
    self.translate.max_y = @max((self.texture.height - self.viewport.height) / self.texture.height, 0);

    gl.glViewport(0, 0, @intFromFloat(self.viewport.width), @intFromFloat(self.viewport.height));

    self.setFit(self.fit.state);
}

pub const Zoom = enum {
    in,
    out,
    none,
};

pub fn zoom(self: *Renderer, action: Zoom) void {
    self.fit.state = .both;

    switch (action) {
        .in => self.scale.factor = @max(self.scale.factor * @sqrt(2.0), 1.0 / 1024.0),
        .out => self.scale.factor = @min(self.scale.factor / @sqrt(2.0), 1024.0),
        .none => self.resetScaleAndTranslate(),
    }

    self.scale.width = self.scale.factor * (self.texture.width / self.viewport.width);
    self.scale.height = self.scale.factor * (self.texture.height / self.viewport.height);

    self.translate.max_x = @max((self.scale.factor * self.texture.width - self.viewport.width) / (self.scale.factor * self.texture.width), 0);
    self.translate.max_y = @max((self.scale.factor * self.texture.height - self.viewport.height) / (self.scale.factor * self.texture.height), 0);

    self.translate.x = @min(@max(self.translate.x, -self.translate.max_x), self.translate.max_x);
    self.translate.y = @min(@max(self.translate.y, -self.translate.max_y), self.translate.max_y);

    self.need_redraw = true;
}

pub const Direction = enum {
    horizontal,
    vertical,
    center,
};

pub fn move(self: *Renderer, direction: Direction, step: f32) void {
    switch (direction) {
        .vertical => {
            if (self.scale.factor * self.texture.height > self.viewport.height) {
                self.translate.y = @min(@max(self.translate.y + step, -self.translate.max_y), self.translate.max_y);
            }
        },
        .horizontal => {
            if (self.scale.factor * self.texture.width > self.viewport.width) {
                self.translate.x = @min(@max(self.translate.x + step, -self.translate.max_x), self.translate.max_x);
            }
        },
        .center => {
            self.translate.y = 0.0;
            self.translate.x = 0.0;
        },
    }

    self.need_redraw = true;
}

pub fn render(self: *Renderer) void {
    gl.glClearColor(0.0, 0.0, 0.0, 1.0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    gl.glBindTexture(gl.GL_TEXTURE_2D_ARRAY, self.texture.id);
    self.shader.use();
    self.shader.setMat4("scale", Mat4.scale(.{ self.scale.width, self.scale.height, 0.0 }));
    self.shader.setMat4("translate", Mat4.translate(.{ self.translate.x, self.translate.y, 0.0 }));
    gl.glBindVertexArray(self.vao);
    gl.glDrawElements(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, @ptrFromInt(0));

    self.need_redraw = false;
}
