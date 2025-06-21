const App = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;
const Window = @import("Window.zig");
const Event = Window.Event;
const Renderer = @import("Renderer.zig");
const Image = @import("Image.zig");
const Config = @import("Config.zig");

window: Window,
renderer: Renderer,
config: Config,
path_list: *std.ArrayListUnmanaged([:0]const u8),
index: i32,
loading_image: bool,
inotify_fd: i32,
wds: std.AutoHashMapUnmanaged(i32, [:0]const u8),

pub fn init(allocator: Allocator, path_list: *std.ArrayListUnmanaged([:0]const u8)) !*App {
    const app = try allocator.create(App);
    var image: Image = undefined;

    while (true) {
        image = Image.init(path_list.items[0]) catch |err| {
            _ = path_list.orderedRemove(0);

            if (path_list.items.len == 0) {
                return err;
            } else {
                continue;
            }
        };

        break;
    }
    defer image.deinit();

    const fd = try std.posix.inotify_init1(std.os.linux.IN.NONBLOCK);
    var wds: std.AutoHashMapUnmanaged(i32, [:0]const u8) = .empty;

    for (path_list.items) |path| {
        const wd = try std.posix.inotify_add_watch(fd, path, std.os.linux.IN.DELETE_SELF | std.os.linux.IN.MOVE_SELF);

        try wds.put(allocator, wd, path[0..]);
    }

    app.* = .{
        .window = .default,
        .renderer = undefined,
        .config = try Config.init(allocator),
        .path_list = path_list,
        .index = 0,
        .loading_image = false,
        .inotify_fd = fd,
        .wds = wds,
    };

    var buf = [_]u8{0} ** std.posix.NAME_MAX;
    const title = try std.fmt.bufPrintZ(&buf, "{d} of {d} - {s}", .{ 1, path_list.items.len, std.fs.path.basename(path_list.items[0]) });

    try app.window.init(1280, 720, title);

    app.renderer = try Renderer.init(1280, 720);
    app.renderer.setTexture(image);

    return app;
}

pub fn deinit(self: *App, allocator: Allocator) void {
    self.window.deinit();
    self.renderer.deinit();
    self.config.deinit(allocator);

    var iter = self.wds.keyIterator();

    while (iter.next()) |wd| {
        std.posix.inotify_rm_watch(self.inotify_fd, wd.*);
    }

    self.wds.deinit(allocator);

    std.posix.close(self.inotify_fd);
    allocator.destroy(self);
}

fn loadImage(app: *App, new_index: i32, previous: bool) !void {
    var i = new_index;
    var image: Image = undefined;

    while (true) {
        image = Image.init(app.path_list.items[@intCast(i)]) catch {
            _ = app.path_list.orderedRemove(@intCast(i));

            if (app.path_list.items.len == 0)
                return;

            i = if (previous)
                @min(i - 1, 0)
            else
                @min(i, @as(i32, @intCast(app.path_list.items.len)) - 1);

            continue;
        };

        break;
    }

    const event = Event{
        .image = .{
            .index = i,
            .image = image,
        },
    };

    _ = std.posix.write(app.window.pipe_fds[1], std.mem.asBytes(&event)) catch unreachable;
}

fn navigate(self: *App, step: i32) !void {
    const new_index = self.index + step;

    if (new_index >= 0 and new_index < self.path_list.items.len and new_index != self.index and !self.loading_image) {
        self.loading_image = true;
        var thread = try std.Thread.spawn(.{}, loadImage, .{ self, new_index, step < 0 });
        thread.detach();
    }
}

fn removePathByWd(self: *App, wd: i32, step: i32) void {
    if (self.wds.fetchRemove(wd)) |kv| {
        const path = kv.value;
        const index = self.getPathIndex(path) orelse unreachable;
        _ = self.path_list.orderedRemove(index);

        if (index < self.index or (index == self.index and self.index == 0))
            self.index += step;
    }
}

fn deleteCurrentImage(self: *App) !void {
    if (!self.loading_image) {
        const deleted = self.path_list.items[@intCast(self.index)];
        var iter = self.wds.iterator();

        while (iter.next()) |entry| {
            const path = entry.value_ptr.*;

            if (std.mem.orderZ(u8, path, deleted) == .eq) {
                const wd = entry.key_ptr.*;
                std.posix.inotify_rm_watch(self.inotify_fd, wd);
                self.removePathByWd(wd, 0);
                try std.fs.deleteFileAbsolute(deleted);

                if (self.path_list.items.len == 0) {
                    self.window.running = false;
                    return;
                }

                self.loading_image = true;
                var thread = try std.Thread.spawn(.{}, loadImage, .{ self, if (self.index >= self.path_list.items.len) @as(i32, @intCast(self.path_list.items.len)) - 1 else self.index, false });
                thread.detach();

                return;
            }
        }
    }
}

fn keyboardHandler(self: *App, keysym: u32) !void {
    var buf: [128:0]u8 = undefined;
    self.window.keyboard.getName(keysym, &buf);

    const cmd = self.config.cmdFromKey(&buf) orelse return;

    if (cmd == .quit) {
        self.window.running = false;
        return;
    }

    if (self.loading_image)
        return;

    switch (cmd) {
        .left => self.renderer.move(.horizontal, 0.1),
        .down => self.renderer.move(.vertical, 0.1),
        .right => self.renderer.move(.horizontal, -0.1),
        .up => self.renderer.move(.vertical, -0.1),
        .@"zoom-in" => self.renderer.setZoom(.in),
        .@"zoom-out" => self.renderer.setZoom(.out),
        .@"fit-both" => self.renderer.setFit(.both),
        .@"fit-width" => self.renderer.setFit(.width),
        .@"fit-none" => self.renderer.setFit(.none),
        .rotate_clockwise => self.renderer.rotateTexture(90),
        .rotate_counterclockwise => self.renderer.rotateTexture(-90),
        .next => try self.navigate(1),
        .previous => try self.navigate(-1),
        .delete => try self.deleteCurrentImage(),
        else => {},
    }
}

fn pointerPressedHandler(self: *App, button: u32) !void {
    switch (button) {
        274 => self.window.running = false,
        275 => try self.navigate(-1),
        276 => try self.navigate(1),
        else => {},
    }
}

fn getPathIndex(self: App, path: [:0]const u8) ?usize {
    for (self.path_list.items, 0..) |item, i| {
        if (std.mem.orderZ(u8, path, item) == .eq) return i;
    }

    return null;
}

fn readWindowEvents(self: *App) !void {
    while (true) {
        var event: Event = undefined;

        while (std.posix.read(self.window.pipe_fds[0], std.mem.asBytes(&event))) |n| {
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

                    var buf = [_]u8{0} ** std.posix.NAME_MAX;
                    const title = try std.fmt.bufPrintZ(&buf, "{d} of {d} - {s}", .{ self.index + 1, self.path_list.items.len, std.fs.path.basename(self.path_list.items[@intCast(self.index)]) });

                    self.window.setTitle(title);

                    self.loading_image = false;
                },
            }
        } else |err| switch (err) {
            error.WouldBlock => break,
            else => return err,
        }
    }
}

fn readInotifyEvents(self: *App) !void {
    while (true) {
        var buf: [4096]u8 align(@alignOf(std.os.linux.inotify_event)) = undefined;

        while (std.posix.read(self.inotify_fd, &buf)) |n| {
            if (n == 0) break;

            const inotify_event = @as(*std.os.linux.inotify_event, @ptrCast(&buf));

            if (inotify_event.mask & std.os.linux.IN.DELETE_SELF != 0) {
                self.removePathByWd(inotify_event.wd, -1);
            } else if (inotify_event.mask & std.os.linux.IN.MOVE_SELF != 0) {
                std.posix.inotify_rm_watch(self.inotify_fd, inotify_event.wd);
                self.removePathByWd(inotify_event.wd, -1);
            }
        } else |err| switch (err) {
            error.WouldBlock => break,
            else => return,
        }
    }
}

fn waitEvent(self: *App) !void {
    var pfds = [_]std.posix.pollfd{
        .{ .fd = self.window.wl_display_fd, .events = std.os.linux.POLL.IN, .revents = undefined },
        .{ .fd = self.window.pipe_fds[0], .events = std.os.linux.POLL.IN, .revents = undefined },
        .{ .fd = self.inotify_fd, .events = std.os.linux.POLL.IN, .revents = undefined },
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

    if (pfds[1].revents != 0 & std.os.linux.POLL.IN) {
        try self.readWindowEvents();
    }

    if (pfds[2].revents != 0 & std.os.linux.POLL.IN) {
        try self.readInotifyEvents();
    }
}

pub fn run(self: *App) !void {
    while (!self.window.shouldClose()) {
        if (self.renderer.need_redraw) {
            self.renderer.render();
            try self.window.swapBuffers();
        }

        try self.waitEvent();
    }
}
