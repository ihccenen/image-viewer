const std = @import("std");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");
const Image = @import("Image.zig");
const Event = @import("event.zig").Event;
const Mat4 = @import("math.zig").Mat4;

pub fn main() !void {
    var image = try Image.init(std.mem.span(std.os.argv[1]));
    defer image.deinit();

    var window = Window{};
    try window.init(image.width, image.height);
    defer window.deinit();

    var renderer = try Renderer.init();
    defer renderer.deinit();

    renderer.setTexture(&image);

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

                    if (std.mem.orderZ(u8, @as([*:0]const u8, @ptrCast(&buf)), "plus") == .eq) {
                        renderer.scale = @max(renderer.scale * @sqrt(2.0), 1.0 / 1024.0);
                    } else if (std.mem.orderZ(u8, @as([*:0]const u8, @ptrCast(&buf)), "minus") == .eq) {
                        renderer.scale = @min(renderer.scale / @sqrt(2.0), 1024.0);
                    } else if (std.mem.orderZ(u8, @as([*:0]const u8, @ptrCast(&buf)), "l") == .eq) {
                        renderer.translateX += 0.1;
                    } else if (std.mem.orderZ(u8, @as([*:0]const u8, @ptrCast(&buf)), "h") == .eq) {
                        renderer.translateX -= 0.1;
                    } else if (std.mem.orderZ(u8, @as([*:0]const u8, @ptrCast(&buf)), "j") == .eq) {
                        renderer.translateY -= 0.1;
                    } else if (std.mem.orderZ(u8, @as([*:0]const u8, @ptrCast(&buf)), "k") == .eq) {
                        renderer.translateY += 0.1;
                    } else if (std.mem.orderZ(u8, @as([*:0]const u8, @ptrCast(&buf)), "q") == .eq) {
                        window.running = false;
                    }
                },
                .resize => |dim| {
                    const width, const height = dim;
                    renderer.viewport(width, height);
                },
            }
        }

        renderer.render();
        try window.swapBuffers();
    }
}
