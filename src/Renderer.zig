pub const Renderer = @This();

const gl = @import("gl.zig");
const Shader = @import("Shader.zig");

shader: Shader = undefined,
vao: gl.GLuint = 0,
vbo: gl.GLuint = 0,
ebo: gl.GLuint = 0,

pub fn init() !Renderer {
    const vertices = [_]f32{
        1.0, 1.0, 0.0, // top right
        1.0, -1.0, 0.0, // bottom right
        -1.0, -1.0, 0.0, // bottom left
        -1.0, 1.0, 0.0, // top left
    };

    const indices = [_]i32{
        0, 1, 3,
        1, 2, 3,
    };

    var vao: gl.GLuint = 0;
    var vbo: gl.GLuint = 0;
    var ebo: gl.GLuint = 0;

    gl.glGenVertexArrays(1, &vao);
    gl.glBindVertexArray(vao);

    gl.glGenBuffers(1, &vbo);
    gl.glBindBuffer(gl.GL_ARRAY_BUFFER, vbo);
    gl.glBufferData(gl.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), &vertices, gl.GL_STATIC_DRAW);

    gl.glGenBuffers(1, &ebo);
    gl.glBindBuffer(gl.GL_ELEMENT_ARRAY_BUFFER, ebo);
    gl.glBufferData(gl.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(indices)), &indices, gl.GL_STATIC_DRAW);

    gl.glVertexAttribPointer(0, 3, gl.GL_FLOAT, gl.GL_FALSE, 3 * @sizeOf(f32), @ptrFromInt(0));
    gl.glEnableVertexAttribArray(0);

    return .{
        .shader = try Shader.init(),
        .vao = vao,
        .vbo = vbo,
        .ebo = ebo,
    };
}

pub fn deinit(self: *Renderer) void {
    self.shader.deinit();
    gl.glDeleteVertexArrays(1, &self.vao);
    gl.glDeleteBuffers(1, &self.vbo);
    gl.glDeleteBuffers(1, &self.ebo);
}

pub fn render(self: Renderer) void {
    gl.glClearColor(0.0, 0.0, 0.0, 1.0);
    gl.glClear(gl.GL_COLOR_BUFFER_BIT);

    self.shader.use();

    gl.glBindVertexArray(self.vao);
    gl.glDrawElements(gl.GL_TRIANGLES, 6, gl.GL_UNSIGNED_INT, @ptrFromInt(0));
}
