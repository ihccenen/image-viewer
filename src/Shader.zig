pub const Shader = @This();

const std = @import("std");
const gl = @import("gl.zig");

const vertex =
    \\ #version 330 core
    \\ layout (location = 0) in vec3 vPos;
    \\ 
    \\ void main()
    \\ {
    \\     gl_Position = vec4(vPos, 1.0);
    \\ }
;

const fragment =
    \\ #version 330 core
    \\ out vec4 FragColor;
    \\ 
    \\ void main()
    \\ {
    \\     FragColor = vec4(0.0, 0.0, 0.0, 1.0);
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
