const std = @import("std");
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");
const Image = @import("Image.zig");
const Event = @import("event.zig").Event;
const Mat4 = @import("math.zig").Mat4;

const supported_formats = [_][:0]const u8{ ".jpeg", ".jpg", ".png", ".psd" };

pub fn loadImage(image: *Image, paths: [][:0]u8, pipe_fd: std.posix.fd_t, index: usize, step: isize) void {
    const next_index = @as(isize, @intCast(index)) + step;

    if (next_index >= paths.len or next_index < 0) return;

    image.* = Image.init(paths[@intCast(next_index)]) catch return;

    const event = Event{ .image_loaded = @intCast(next_index) };
    _ = std.posix.write(pipe_fd, std.mem.asBytes(&event)) catch return;
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var paths = std.ArrayList([:0]u8).init(allocator);
    defer paths.deinit();

    for (std.os.argv[1..]) |arg| {
        const path = std.mem.span(arg);
        const ext = std.fs.path.extension(path);

        for (supported_formats) |extension| {
            if (std.mem.eql(u8, ext, extension)) {
                try paths.append(path);
                break;
            }
        }
    }

    if (paths.items.len < 1) {
        std.debug.print("usage: {s} [image path]\n", .{std.fs.path.basename(std.mem.span(std.os.argv[0]))});
        return;
    }

    var index: usize = 0;

    var window = Window{};
    try window.init(100, 100);
    defer window.deinit();

    var renderer = try Renderer.init();
    defer renderer.deinit();

    var image = try Image.init(paths.items[index]);
    renderer.setTexture(image);
    image.deinit();

    var loading_image: bool = false;
    var event: Event = undefined;

    while (!window.shouldClose()) {
        const size = std.posix.read(window.pipe_fds[0], std.mem.asBytes(&event)) catch |e| switch (e) {
            error.WouldBlock => 0,
            else => unreachable,
        };

        if (size > 0) {
            switch (event) {
                .keyboard => |keysym| {
                    var buf: [128:0]u8 = undefined;
                    window.keyboard.getName(keysym, &buf);

                    if (std.mem.orderZ(u8, &buf, "plus") == .eq) {
                        renderer.zoom(.in);
                    } else if (std.mem.orderZ(u8, &buf, "minus") == .eq) {
                        renderer.zoom(.out);
                    } else if (std.mem.orderZ(u8, &buf, "s") == .eq) {
                        renderer.zoom(.fit_width);
                    } else if (std.mem.orderZ(u8, &buf, "w") == .eq) {
                        renderer.zoom(.fit_both);
                    } else if (std.mem.orderZ(u8, &buf, "o") == .eq) {
                        renderer.zoom(.reset);
                    } else if (std.mem.orderZ(u8, &buf, "k") == .eq) {
                        renderer.move(.up);
                    } else if (std.mem.orderZ(u8, &buf, "l") == .eq) {
                        renderer.move(.right);
                    } else if (std.mem.orderZ(u8, &buf, "j") == .eq) {
                        renderer.move(.down);
                    } else if (std.mem.orderZ(u8, &buf, "h") == .eq) {
                        renderer.move(.left);
                    } else if (std.mem.orderZ(u8, &buf, "m") == .eq) {
                        renderer.move(.center);
                    } else if (std.mem.orderZ(u8, &buf, "q") == .eq) {
                        window.running = false;
                    } else if (std.mem.orderZ(u8, &buf, "n") == .eq) {
                        if (!loading_image) {
                            loading_image = true;
                            var thread = try std.Thread.spawn(.{}, loadImage, .{ &image, paths.items, window.pipe_fds[1], index, 1 });
                            thread.detach();
                        }
                    } else if (std.mem.orderZ(u8, &buf, "p") == .eq) {
                        if (!loading_image) {
                            loading_image = true;
                            var thread = try std.Thread.spawn(.{}, loadImage, .{ &image, paths.items, window.pipe_fds[1], index, -1 });
                            thread.detach();
                        }
                    }
                },
                .resize => |dim| {
                    const width, const height = dim;
                    renderer.viewport(width, height);
                },
                .image_loaded => |new_index| {
                    loading_image = false;
                    index = new_index;
                    renderer.setTexture(image);
                    image.deinit();
                },
            }
        }

        renderer.render();
        try window.swapBuffers();
    }
}
