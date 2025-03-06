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
    width: f32 = 0,
    height: f32 = 0,
} = .{},

texture: struct {
    id: gl.GLuint = 0,
    width: f32 = 0,
    height: f32 = 0,
} = .{},

scale: struct {
    factor: f32 = 1,
    width: f32 = 1,
    height: f32 = 1,
} = .{},

fit: struct {
    state: Fit = .both,
    width: f32 = 1,
    both: f32 = 1,
} = .{},

translate: struct {
    x: f32 = 0,
    y: f32 = 0,
} = .{},

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
        .texture = .{ .id = texture },
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

    if (self.texture.width > self.viewport.width) {
        self.translate.x = -1.0 + (self.texture.width / self.viewport.width);
    } else {
        self.translate.x = 0.0;
    }

    if (self.texture.height > self.viewport.height) {
        self.translate.y = 1.0 - (self.texture.height / self.viewport.height);
    } else {
        self.translate.y = 0.0;
    }

    self.need_redraw = true;
}

pub fn setFit(self: *Renderer, state: Fit) void {
    self.fit.state = state;

    switch (state) {
        .width => {
            self.translate.y = 1.0 - (self.fit.width * self.texture.height / self.viewport.height);
            self.translate.x = 0.0;
            self.scale.factor = self.fit.width;
        },
        .both => {
            self.translate.y = 0.0;
            self.translate.x = 0.0;
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
    self.setFit(self.fit.state);

    gl.glTexImage2D(gl.GL_TEXTURE_2D, 0, gl.GL_RGBA, @intCast(image.width), @intCast(image.height), 0, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, @ptrCast(image.data.ptr));

    self.need_redraw = true;
}

pub fn setViewport(self: *Renderer, width: usize, height: usize) void {
    self.viewport.width = @floatFromInt(width);
    self.viewport.height = @floatFromInt(height);

    self.fit.width = self.viewport.width / self.texture.width;
    self.fit.both = @min(self.fit.width, self.viewport.height / self.texture.height);
    self.setFit(self.fit.state);

    gl.glViewport(0, 0, @intFromFloat(self.viewport.width), @intFromFloat(self.viewport.height));

    self.need_redraw = true;
}

pub const Zoom = enum {
    in,
    out,
    none,
};

pub fn zoom(self: *Renderer, action: Zoom) void {
    self.fit.state = .none;

    switch (action) {
        .in => self.scale.factor = @max(self.scale.factor * @sqrt(2.0), 1.0 / 1024.0),
        .out => self.scale.factor = @min(self.scale.factor / @sqrt(2.0), 1024.0),
        .none => self.resetScaleAndTranslate(),
    }

    self.scale.width = self.scale.factor * (self.texture.width / self.viewport.width);
    self.scale.height = self.scale.factor * (self.texture.height / self.viewport.height);

    self.need_redraw = true;
}

pub const Direction = enum {
    up,
    right,
    down,
    left,
    center,
};

pub fn move(self: *Renderer, direction: Direction) void {
    switch (direction) {
        .up => self.translate.y += 0.1,
        .right => self.translate.x += 0.1,
        .down => self.translate.y -= 0.1,
        .left => self.translate.x -= 0.1,
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

    gl.glBindTexture(gl.GL_TEXTURE_2D, self.texture.id);

    self.shader.use();

    self.shader.setMat4("scale", Mat4.scale(.{ self.scale.width, self.scale.height, 0.0 }));

    self.shader.setMat4("translate", Mat4.translate(.{ self.translate.x, self.translate.y, 0.0 }));

    gl.glBindVertexArray(self.vao);
    gl.glDrawElements(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, @ptrFromInt(0));

    self.need_redraw = false;
}
