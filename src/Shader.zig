pub const Shader = @This();

const std = @import("std");
const gl = @import("gl.zig");
const Mat4 = @import("math.zig").Mat4;

const vertex =
    \\ #version 330 core
    \\ layout (location = 0) in vec3 vPos;
    \\ layout (location = 1) in vec2 vTexCoord;
    \\
    \\ out vec2 TexCoord;
    \\ uniform mat4 scale;
    \\ uniform mat4 translate;
    \\
    \\ void main()
    \\ {
    \\     gl_Position = translate * scale * vec4(vPos, 1.0);
    \\     TexCoord = vTexCoord;
    \\ }
;

const fragment =
    \\ #version 330 core
    \\ in vec2 TexCoord;
    \\ out vec4 FragColor;
    \\
    \\ uniform sampler2DArray textures;
    \\
    \\ void main()
    \\ {
    \\    float layerWidth = 1.0 / 2.0;
    \\    float layerHeight = 1.0 / 2.0;
    \\
    \\    int layerX = int(TexCoord.x / layerWidth);
    \\    int layerY = int(TexCoord.y / layerHeight);
    \\    int layer = layerY * 2 + layerX;
    \\
    \\    float adjustedX = (TexCoord.x - float(layerX) * layerWidth) / layerWidth;
    \\    float adjustedY = (TexCoord.y - float(layerY) * layerHeight) / layerHeight;
    \\
    \\    FragColor = texture(textures, vec3(adjustedX, adjustedY, layer));
    \\ }
;

fn createShader(src: [:0]const u8, _type: gl.GLenum) !gl.GLuint {
    const shader: gl.GLuint = gl.glCreateShader(_type);
    gl.glShaderSource(shader, 1, @ptrCast(&src), null);
    gl.glCompileShader(shader);

    var success: gl.GLint = 0;
    gl.glGetShaderiv(shader, gl.GL_COMPILE_STATUS, &success);

    if (success == gl.GL_FALSE) {
        var info: [512]u8 = [_:0]u8{0} ** 512;
        gl.glGetShaderInfoLog(shader, info.len, null, &info);

        return error.ShaderFailedToCompile;
    }

    return shader;
}

id: gl.GLuint = 0,

pub fn init() !Shader {
    const vertex_shader = try createShader(vertex, gl.GL_VERTEX_SHADER);
    const fragment_shader = try createShader(fragment, gl.GL_FRAGMENT_SHADER);
    const id = gl.glCreateProgram();

    gl.glAttachShader(id, vertex_shader);
    gl.glAttachShader(id, fragment_shader);
    gl.glLinkProgram(id);

    var success: gl.GLint = 0;
    gl.glGetProgramiv(id, gl.GL_LINK_STATUS, &success);

    if (success == gl.GL_FALSE) {
        var info: [512]u8 = [_:0]u8{0} ** 512;
        gl.glGetProgramInfoLog(id, info.len, null, &info);

        std.debug.print("program linking error: {s}", .{info});

        return error.ProgramLinkingError;
    }

    gl.glDeleteShader(vertex_shader);
    gl.glDeleteShader(fragment_shader);

    return .{ .id = id };
}

pub fn deinit(self: Shader) void {
    gl.glDeleteProgram(self.id);
}

pub fn use(self: Shader) void {
    gl.glUseProgram(self.id);
}

pub fn setInt(self: Shader, name: [:0]const u8, val: usize) void {
    gl.glUniform1i(gl.glGetUniformLocation(self.id, name), @intCast(val));
}

pub fn setMat4(self: Shader, name: [:0]const u8, mat: Mat4) void {
    gl.glUniformMatrix4fv(gl.glGetUniformLocation(self.id, name), 1, gl.GL_FALSE, @ptrCast(&mat.data));
}
