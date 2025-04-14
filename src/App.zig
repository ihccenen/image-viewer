const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Window = @import("Window.zig");
const Event = Window.Event;
const Renderer = @import("Renderer.zig");
const Image = @import("Image.zig");

fn loadNextImage(app: *App, next_image_index: usize) void {
    const event = Event{
        .image = .{
            .index = next_image_index,
            .image = Image.init(app.paths[next_image_index]) catch unreachable,
        },
    };
    _ = std.posix.write(app.window.pipe_fds[1], std.mem.asBytes(&event)) catch unreachable;
}

window: *Window,
renderer: *Renderer,
paths: [][:0]u8,
index: usize,
loading_image: bool,
allocator: Allocator,

pub fn init(allocator: Allocator, paths: [][:0]u8) !App {
    var window = try allocator.create(Window);
    const basename = std.fs.path.basename(paths[0]);
    const filename = try std.fmt.allocPrintZ(allocator, "{d} of {d} - {s}", .{ 1, paths.len, basename });
    defer allocator.free(filename);
    try window.init(1280, 720, filename);

    var renderer = try allocator.create(Renderer);
    renderer.* = try Renderer.init();

    var image = try Image.init(paths[0]);
    renderer.setTexture(image);
    image.deinit();

    return .{
        .window = window,
        .renderer = renderer,
        .paths = paths,
        .index = 0,
        .loading_image = false,
        .allocator = allocator,
    };
}

pub fn deinit(self: *App) void {
    self.window.deinit();
    self.renderer.deinit();
    self.allocator.destroy(self.window);
    self.allocator.destroy(self.renderer);
}

fn waitEvent(self: *App) void {
    var pfds = [_]std.posix.pollfd{
        .{ .fd = self.window.wl_display_fd, .events = std.os.linux.POLL.IN, .revents = undefined },
        .{ .fd = self.window.pipe_fds[0], .events = std.os.linux.POLL.IN, .revents = undefined },
    };

    while (!self.window.wl_display.prepareRead()) {
        if (self.window.wl_display.dispatchPending() != .SUCCESS) {
            return;
        }
    }

    if (self.window.wl_display.flush() != .SUCCESS) {
        return;
    }

    _ = std.posix.poll(&pfds, -1) catch {
        self.window.wl_display.cancelRead();
        return;
    };

    if (pfds[0].revents != 0 & std.os.linux.POLL.IN) {
        if (self.window.wl_display.readEvents() != .SUCCESS) {
            return;
        }
    } else {
        self.window.wl_display.cancelRead();
    }

    _ = self.window.wl_display.dispatchPending();
}

fn nextImage(self: *App, step: isize) !void {
    const next_index = @min(
        self.paths.len - 1,
        if (step < 0)
            self.index -| @as(usize, @abs(step))
        else
            self.index +| @as(usize, @intCast(step)),
    );

    if (!self.loading_image) {
        self.loading_image = true;
        var thread = try std.Thread.spawn(.{}, loadNextImage, .{ self, next_index });
        thread.detach();
    }
}

fn keyboardHandler(self: *App, keysym: u32) !void {
    var buf: [128:0]u8 = undefined;
    self.window.keyboard.getName(keysym, &buf);

    if (std.mem.orderZ(u8, &buf, "q") == .eq) {
        self.window.running = false;
        return;
    }

    if (self.loading_image) return;

    if (std.mem.orderZ(u8, &buf, "plus") == .eq) {
        self.renderer.setZoom(.in);
    } else if (std.mem.orderZ(u8, &buf, "minus") == .eq) {
        self.renderer.setZoom(.out);
    } else if (std.mem.orderZ(u8, &buf, "s") == .eq) {
        self.renderer.setFit(.width);
    } else if (std.mem.orderZ(u8, &buf, "w") == .eq) {
        self.renderer.setFit(.both);
    } else if (std.mem.orderZ(u8, &buf, "o") == .eq) {
        self.renderer.setFit(.none);
    } else if (std.mem.orderZ(u8, &buf, "k") == .eq) {
        self.renderer.move(.vertical, -0.1);
    } else if (std.mem.orderZ(u8, &buf, "l") == .eq) {
        self.renderer.move(.horizontal, -0.1);
    } else if (std.mem.orderZ(u8, &buf, "j") == .eq) {
        self.renderer.move(.vertical, 0.1);
    } else if (std.mem.orderZ(u8, &buf, "h") == .eq) {
        self.renderer.move(.horizontal, 0.1);
    } else if (std.mem.orderZ(u8, &buf, "m") == .eq) {
        self.renderer.move(.center, 0.0);
    } else if (std.mem.orderZ(u8, &buf, "n") == .eq) {
        try self.nextImage(1);
    } else if (std.mem.orderZ(u8, &buf, "p") == .eq) {
        try self.nextImage(-1);
    }
}

fn pointerPressedHandler(self: *App, button: u32) !void {
    switch (button) {
        275 => try self.nextImage(-1),
        276 => try self.nextImage(1),
        else => {},
    }
}

fn readEvents(self: *App) !void {
    var event: Event = undefined;

    while (true) {
        const n = std.posix.read(self.window.pipe_fds[0], std.mem.asBytes(&event)) catch |e| switch (e) {
            error.WouldBlock => break,
            else => unreachable,
        };

        if (n == 0) break;

        switch (event) {
            .keyboard => |keysym| try self.keyboardHandler(keysym),
            .pointer => |e| if (!self.loading_image) {
                switch (e) {
                    .button => |button| try self.pointerPressedHandler(button),
                    .axis => |axis| self.renderer.move(.vertical, if (axis < 0) -0.1 else 0.1),
                    .motion => |motion| {
                        const x = 1 / (self.renderer.scale.factor * self.renderer.texture.width / 2);
                        const y = 1 / (self.renderer.scale.factor * self.renderer.texture.height / 2);

                        self.renderer.move(.horizontal, @as(f32, @floatFromInt(motion.x)) * x);
                        self.renderer.move(.vertical, @as(f32, @floatFromInt(motion.y)) * -y);
                    },
                }
            },
            .resize => |dim| {
                const width, const height = dim;
                self.renderer.setViewport(width, height);
            },
            .image => |image| {
                defer image.image.deinit();
                self.index = image.index;
                self.renderer.setTexture(image.image);
                self.renderer.applyFitAndTranslate();

                const basename = std.fs.path.basename(self.paths[self.index]);
                const filename = try std.fmt.allocPrintZ(self.allocator, "{d} of {d} - {s}", .{ self.index + 1, self.paths.len, basename });
                defer self.allocator.free(filename);

                self.window.setTitle(filename);

                self.loading_image = false;
            },
        }
    }
}

pub fn run(self: *App) !void {
    while (!self.window.shouldClose()) {
        if (self.renderer.need_redraw) {
            self.renderer.render();
            try self.window.swapBuffers();
        }

        self.waitEvent();
        try self.readEvents();
    }
}
