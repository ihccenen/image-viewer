const std = @import("std");
const Allocator = std.mem.Allocator;
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");
const Image = @import("Image.zig");
const Event = @import("event.zig").Event;

const App = @This();

pub fn loadImage(image: *Image, path: [:0]u8, pipe_fd: std.posix.fd_t, index: usize) void {
    image.* = Image.init(path) catch return;
    const event = Event{ .image_loaded = @intCast(index) };
    _ = std.posix.write(pipe_fd, std.mem.asBytes(&event)) catch return;
}

window: *Window,
renderer: *Renderer = undefined,
paths: [][:0]u8,
index: usize,
image: Image = undefined,
loading_image: bool,
event: Event = undefined,
allocator: Allocator,

pub fn init(allocator: Allocator, paths: [][:0]u8) !App {
    var window = try allocator.create(Window);
    const basename = std.fs.path.basename(paths[0]);
    const filename = try std.fmt.allocPrintZ(allocator, "{d} of {d} - {s}", .{ 1, paths.len, basename });
    defer allocator.free(filename);
    try window.init(1, 1, filename);

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
        .{
            .fd = self.window.wl_display_fd,
            .events = std.os.linux.POLL.IN,
            .revents = 0,
        },
        .{
            .fd = self.window.pipe_fds[0],
            .events = std.os.linux.POLL.IN,
            .revents = 0,
        },
    };

    if (!self.window.wl_display.prepareRead()) {
        return;
    }

    _ = self.window.wl_display.flush();

    _ = std.posix.poll(&pfds, -1) catch {
        self.window.wl_display.cancelRead();
        return;
    };

    if (pfds[0].revents != 0 & std.os.linux.POLL.IN) {
        _ = self.window.wl_display.readEvents();
    } else {
        _ = self.window.wl_display.cancelRead();
    }
}

fn nextImage(self: *App, step: isize) !void {
    const next_index = @as(isize, @intCast(self.index)) + step;

    if (!self.loading_image and next_index >= 0 and @as(usize, @intCast(next_index)) < self.paths.len) {
        self.loading_image = true;
        var thread = try std.Thread.spawn(.{}, loadImage, .{ &self.image, self.paths[@intCast(next_index)], self.window.pipe_fds[1], @as(usize, @intCast(next_index)) });
        thread.detach();
    }
}

fn keyboardHandler(self: *App, keysym: u32) !void {
    var buf: [128:0]u8 = undefined;
    self.window.keyboard.getName(keysym, &buf);

    if (std.mem.orderZ(u8, &buf, "plus") == .eq) {
        self.renderer.zoom(.in);
    } else if (std.mem.orderZ(u8, &buf, "minus") == .eq) {
        self.renderer.zoom(.out);
    } else if (std.mem.orderZ(u8, &buf, "s") == .eq) {
        self.renderer.setFit(.width);
    } else if (std.mem.orderZ(u8, &buf, "w") == .eq) {
        self.renderer.setFit(.both);
    } else if (std.mem.orderZ(u8, &buf, "o") == .eq) {
        self.renderer.zoom(.none);
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
    } else if (std.mem.orderZ(u8, &buf, "q") == .eq) {
        self.window.running = false;
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
    _ = self.window.wl_display.dispatchPending();

    var event: Event = undefined;

    while (true) {
        _ = std.posix.read(self.window.pipe_fds[0], std.mem.asBytes(&event)) catch |e| switch (e) {
            error.WouldBlock => break,
            else => unreachable,
        };

        switch (event) {
            .keyboard => |keysym| try self.keyboardHandler(keysym),
            .pointer => |e| switch (e) {
                .button => |button| try self.pointerPressedHandler(button),
                .axis => |axis| self.renderer.move(.vertical, if (axis < 0) -0.1 else 0.1),
            },
            .resize => |dim| {
                const width, const height = dim;
                self.renderer.setViewport(width, height);
            },
            .image_loaded => |new_index| {
                self.loading_image = false;
                self.index = new_index;
                self.renderer.setTexture(self.image);
                self.image.deinit();

                const basename = std.fs.path.basename(self.paths[self.index]);
                const filename = try std.fmt.allocPrintZ(self.allocator, "{d} of {d} - {s}", .{ self.index + 1, self.paths.len, basename });
                defer self.allocator.free(filename);

                self.window.setTitle(filename);
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
