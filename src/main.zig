const std = @import("std");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");
const Image = @import("Image.zig");
const Event = @import("Event.zig").Event;
const Mat4 = @import("math.zig").Mat4;

pub fn main() !void {
    var image = try Image.init(std.mem.span(std.os.argv[1]));
    defer image.deinit();

    var window = Window{};
    try window.init(image.width, image.height);
    defer window.deinit();

    var renderer = try Renderer.init();
    defer renderer.deinit();

    renderer.setTexture(image);

    var event: Event = undefined;

    while (!window.shouldClose()) {
        const size = std.posix.read(window.pipe_fds[0], std.mem.asBytes(&event)) catch |e| switch (e) {
            error.WouldBlock => 0,
            else => unreachable,
        };

        if (size > 0) {
            switch (event) {
                .keyboard => |keysym| {
                    var buf: [128]u8 = undefined;
                    window.keyboard.getName(keysym, &buf);

                    std.debug.print("key: {s}\n", .{@as([*:0]const u8, @ptrCast(&buf))});
                },
            }
        }

        renderer.render(
            Mat4.scale(.{
                @as(f32, @floatFromInt(image.width)) / 2.0,
                @as(f32, @floatFromInt(image.height)) / 2.0,
                0.0,
            }),
            Mat4.translate(.{
                @as(f32, @floatFromInt(window.width)) / 2.0,
                @as(f32, @floatFromInt(window.height)) / 2.0,
                0.0,
            }),
            Mat4.orthographic(
                0.0,
                @floatFromInt(window.width),
                0.0,
                @floatFromInt(window.height),
                -1.0,
                1.0,
            ),
        );
        try window.swapBuffers();
    }
}
