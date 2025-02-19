const std = @import("std");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");
const Image = @import("Image.zig");
const Event = @import("Event.zig").Event;

pub fn main() !void {
    var window = Window{};
    try window.init(100, 100);
    defer window.deinit();

    var renderer = try Renderer.init();
    defer renderer.deinit();

    var image = try Image.init(std.mem.span(std.os.argv[1]));
    defer image.deinit();

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

        renderer.render();
        try window.swapBuffers();
    }
}
