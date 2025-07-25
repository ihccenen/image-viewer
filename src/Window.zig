pub const Window = @This();

const std = @import("std");
const mem = std.mem;

const wayland = @import("wayland");
const wl = wayland.client.wl;
const xdg = wayland.client.xdg;

const c = @cImport({
    @cInclude("time.h");
    @cInclude("signal.h");

    @cDefine("WL_EGL_PLATFORM", "1");
    @cInclude("EGL/egl.h");
    @cInclude("EGL/eglext.h");
    @cUndef("WL_EGL_PLATFORM");
});

const TextureRenderer = @import("TextureRenderer.zig");
const Keyboard = @import("Keyboard.zig");
const Image = @import("Image.zig");

pub const Event = union(enum) {
    keyboard: u32,
    pointer: union(enum) {
        button: u32,
        axis: i24,
        motion: struct { x: i24, y: i24 },
    },
    resize: struct { c_int, c_int },
    image: struct {
        index: i32,
        image: Image,
    },
};

fn dispatchEvent(self: Window, event: *Event) void {
    _ = std.posix.write(self.pipe_fds[1], std.mem.asBytes(event)) catch return;
}

fn onTimer(sigval: c.union_sigval) callconv(.C) void {
    const window = @as(*Window, @ptrCast(@alignCast(sigval.sival_ptr)));
    var e: Event = .{ .keyboard = window.repeat_key };
    window.dispatchEvent(&e);
}

fn setTimer(self: Window, repeats: bool, pressed: bool) void {
    if (!pressed) {
        const its = c.itimerspec{
            .it_value = c.timespec{
                .tv_sec = 0,
                .tv_nsec = 0,
            },
            .it_interval = c.timespec{
                .tv_sec = 0,
                .tv_nsec = 0,
            },
        };

        if (c.timer_settime(self.timer_id, 0, &its, null) == -1) {
            unreachable;
        }

        return;
    }

    var e: Event = .{ .keyboard = self.repeat_key };
    self.dispatchEvent(&e);

    if (repeats) {
        const its = c.itimerspec{
            .it_value = c.timespec{
                .tv_sec = 0,
                .tv_nsec = self.repeat_delay * 1000 * 1000,
            },
            .it_interval = c.timespec{
                .tv_sec = 0,
                .tv_nsec = self.repeat_interval * 1000 * 1000,
            },
        };

        if (c.timer_settime(self.timer_id, 0, &its, null) == -1) {
            unreachable;
        }
    }
}

fn pointerListener(_: *wl.Pointer, event: wl.Pointer.Event, window: *Window) void {
    switch (event) {
        .enter => |enter| {
            window.pointer.current_x = enter.surface_x.toInt();
            window.pointer.current_y = enter.surface_y.toInt();
            window.pointer.last_x = enter.surface_x.toInt();
            window.pointer.last_y = enter.surface_y.toInt();
            window.wl_pointer.setCursor(
                enter.serial,
                window.wl_cursor_surface,
                @intCast(window.wl_cursor_image.hotspot_x),
                @intCast(window.wl_cursor_image.hotspot_y),
            );
        },
        .leave => {},
        .motion => |motion| {
            window.pointer.current_x = motion.surface_x.toInt();
            window.pointer.current_y = motion.surface_y.toInt();
        },
        .button => |b| {
            switch (b.button) {
                272 => window.pointer.right_button_pressed = b.state == .pressed,
                274, 275, 276 => {
                    if (b.state == .pressed) {
                        var e: Event = .{
                            .pointer = .{
                                .button = b.button,
                            },
                        };
                        window.dispatchEvent(&e);
                    }
                },
                else => {},
            }
        },
        .axis => |axis| {
            switch (axis.axis) {
                .vertical_scroll => {
                    var e: Event = .{
                        .pointer = .{
                            .axis = axis.value.toInt(),
                        },
                    };
                    window.dispatchEvent(&e);
                },
                .horizontal_scroll => {},
                _ => {},
            }
        },
        .frame => {
            const dx = window.pointer.current_x - window.pointer.last_x;
            const dy = window.pointer.current_y - window.pointer.last_y;

            window.pointer.last_x = window.pointer.current_x;
            window.pointer.last_y = window.pointer.current_y;

            if ((dx != 0 or dy != 0) and window.pointer.right_button_pressed) {
                var e: Event = .{
                    .pointer = .{
                        .motion = .{
                            .x = dx,
                            .y = dy,
                        },
                    },
                };
                window.dispatchEvent(&e);
            }
        },
        .axis_source => {},
        .axis_stop => {},
        .axis_discrete => {},
        .axis_value120 => {},
        .axis_relative_direction => {},
    }
}

fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, window: *Window) void {
    switch (event) {
        .keymap => |keymap| {
            defer std.posix.close(keymap.fd);

            if (keymap.format == .xkb_v1) {
                const map_shm = std.posix.mmap(null, keymap.size, std.posix.PROT.READ, .{ .TYPE = .SHARED }, keymap.fd, 0) catch return;
                defer std.posix.munmap(map_shm);
                window.keyboard.setKeymap(@ptrCast(map_shm));
            }
        },
        .enter => {},
        .leave => {},
        .key => |key| {
            const keysym = window.keyboard.getOneSym(key.key);

            window.keyboard.updateKey(key.key, key.state == .pressed);
            window.repeat_key = keysym;
            window.setTimer(window.keyboard.keyRepeats(key.key), key.state == .pressed);
        },
        .modifiers => |modifiers| {
            window.keyboard.updateMods(modifiers.mods_depressed, modifiers.mods_latched, modifiers.mods_locked);
        },
        .repeat_info => |repeat| {
            window.repeat_delay = repeat.delay;
            window.repeat_interval = @divTrunc(1000, repeat.rate);
        },
    }
}

fn seatListener(_: *wl.Seat, event: wl.Seat.Event, window: *Window) void {
    switch (event) {
        .capabilities => |e| {
            if (e.capabilities.keyboard) {
                window.keyboard = Keyboard{};
                window.keyboard.initContext();

                window.wl_keyboard = wl.Seat.getKeyboard(window.wl_seat) catch return;
                window.wl_keyboard.setListener(*Window, keyboardListener, window);
            }

            if (e.capabilities.pointer) {
                window.wl_pointer = wl.Seat.getPointer(window.wl_seat) catch return;
                window.wl_pointer.setListener(*Window, pointerListener, window);
            }
        },
        .name => {},
    }
}

fn wmBaseListener(_: *xdg.WmBase, event: xdg.WmBase.Event, window: *Window) void {
    switch (event) {
        .ping => |ping| {
            window.xdg_wm_base.pong(ping.serial);
        },
    }
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, window: *Window) void {
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                window.wl_compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Shm.interface.name) == .eq) {
                window.wl_shm = registry.bind(global.name, wl.Shm, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                window.wl_seat = registry.bind(global.name, wl.Seat, 9) catch return;
                window.wl_seat.setListener(*Window, seatListener, window);
            } else if (mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                window.xdg_wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
                window.xdg_wm_base.setListener(*Window, wmBaseListener, window);
            }
        },
        .global_remove => {},
    }
}

fn xdgSurfaceListener(xdg_surface: *xdg.Surface, event: xdg.Surface.Event, window: *Window) void {
    switch (event) {
        .configure => |configure| {
            xdg_surface.ackConfigure(configure.serial);
            window.xdg_configured = true;
        },
    }
}

fn xdgToplevelListener(_: *xdg.Toplevel, event: xdg.Toplevel.Event, window: *Window) void {
    switch (event) {
        .configure => |configure| {
            if (configure.width != 0 and configure.height != 0) {
                window.width = configure.width;
                window.height = configure.height;

                wl.EglWindow.resize(window.egl_window, window.width, window.height, 0, 0);
                var e: Event = .{ .resize = .{ window.width, window.height } };
                window.dispatchEvent(&e);
            }
        },
        .configure_bounds => {},
        .wm_capabilities => {},
        .close => window.running = false,
    }
}

fn setNonBlock(fd: std.posix.fd_t) void {
    var flags = std.posix.fcntl(fd, std.posix.F.GETFL, 0) catch unreachable;
    flags |= std.posix.SOCK.NONBLOCK;
    _ = std.posix.fcntl(fd, std.posix.F.SETFL, flags) catch unreachable;
}

wl_display: *wl.Display,
wl_registry: *wl.Registry,
wl_shm: *wl.Shm,
wl_compositor: *wl.Compositor,
wl_surface: *wl.Surface,
wl_seat: *wl.Seat,
wl_keyboard: *wl.Keyboard,
wl_pointer: *wl.Pointer,

wl_cursor_surface: *wl.Surface,
wl_cursor_image: *wl.CursorImage,

xdg_wm_base: *xdg.WmBase,
xdg_surface: *xdg.Surface,
xdg_toplevel: *xdg.Toplevel,
xdg_configured: bool,

egl_display: c.EGLDisplay,
egl_context: c.EGLContext,
egl_surface: c.EGLSurface,
egl_window: *wl.EglWindow,

width: c_int,
height: c_int,

pointer: struct {
    right_button_pressed: bool,
    current_x: i24,
    current_y: i24,
    last_x: i24,
    last_y: i24,
},

keyboard: Keyboard,
repeat_key: u32,
repeat_delay: i32,
repeat_interval: i32,

wl_display_fd: std.posix.fd_t,
pipe_fds: [2]std.posix.fd_t,
timer_id: c.timer_t,

running: bool,

renderer: TextureRenderer,

pub const default: Window = .{
    .wl_display = undefined,
    .wl_registry = undefined,
    .wl_shm = undefined,
    .wl_compositor = undefined,
    .wl_surface = undefined,
    .wl_seat = undefined,
    .wl_keyboard = undefined,
    .wl_pointer = undefined,
    .wl_cursor_surface = undefined,
    .wl_cursor_image = undefined,
    .xdg_wm_base = undefined,
    .xdg_surface = undefined,
    .xdg_toplevel = undefined,
    .xdg_configured = undefined,
    .egl_display = undefined,
    .egl_context = undefined,
    .egl_surface = undefined,
    .egl_window = undefined,
    .width = 0,
    .height = 0,
    .pointer = undefined,
    .keyboard = undefined,
    .repeat_key = undefined,
    .repeat_delay = undefined,
    .repeat_interval = undefined,
    .wl_display_fd = undefined,
    .pipe_fds = undefined,
    .timer_id = undefined,
    .running = undefined,
    .renderer = undefined,
};

pub fn init(self: *Window, width: c_int, height: c_int, image: Image, title: [:0]const u8) !void {
    self.wl_display = try wl.Display.connect(null);
    self.wl_display_fd = self.wl_display.getFd();
    self.pipe_fds = try std.posix.pipe();

    setNonBlock(self.pipe_fds[0]);
    setNonBlock(self.pipe_fds[1]);

    var sigevent = c.sigevent{
        .sigev_notify = c.SIGEV_THREAD,
        .sigev_value = .{
            .sival_ptr = self,
        },
        ._sigev_un = .{
            ._sigev_thread = .{
                ._function = onTimer,
            },
        },
    };

    if (c.timer_create(c.CLOCK_MONOTONIC, @ptrCast(&sigevent), &self.timer_id) == -1) {
        return error.TimerCreate;
    }

    self.wl_registry = try self.wl_display.getRegistry();
    self.wl_registry.setListener(*Window, registryListener, self);

    if (self.wl_display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    self.wl_surface = try self.wl_compositor.createSurface();
    self.xdg_surface = try self.xdg_wm_base.getXdgSurface(self.wl_surface);
    self.xdg_toplevel = try self.xdg_surface.getToplevel();

    self.xdg_surface.setListener(*Window, xdgSurfaceListener, self);
    self.xdg_toplevel.setTitle(title);
    self.xdg_toplevel.setListener(*Window, xdgToplevelListener, self);

    const wl_cursor_theme = try wl.CursorTheme.load(null, 24, self.wl_shm);

    const wl_cursor = wl_cursor_theme.getCursor("left_ptr").?;
    self.wl_cursor_image = wl_cursor.images[0];

    const wl_buffer = try self.wl_cursor_image.getBuffer();
    defer wl_buffer.destroy();

    self.wl_cursor_surface = try self.wl_compositor.createSurface();
    self.wl_cursor_surface.attach(wl_buffer, 0, 0);
    self.wl_cursor_surface.commit();

    self.egl_display = c.eglGetPlatformDisplay(c.EGL_PLATFORM_WAYLAND_KHR, self.wl_display, null);

    var egl_major: c.EGLint = 0;
    var egl_minor: c.EGLint = 0;

    if (c.eglInitialize(self.egl_display, &egl_major, &egl_minor) == c.EGL_FALSE) switch (c.eglGetError()) {
        c.EGL_BAD_DISPLAY => return error.EglBadDisplay,
        else => return error.EglFailedToInitialize,
    };

    const egl_attributes = [6:c.EGL_NONE]c.EGLint{
        c.EGL_RED_SIZE,   8,
        c.EGL_GREEN_SIZE, 8,
        c.EGL_BLUE_SIZE,  8,
    };

    const egl_config = config: {
        var config: c.EGLConfig = null;
        var num_configs: c.EGLint = undefined;
        const result = c.eglChooseConfig(self.egl_display, &egl_attributes, &config, 1, &num_configs);

        if (result != c.EGL_TRUE) {
            switch (c.eglGetError()) {
                c.EGL_BAD_ATTRIBUTE => return error.InvalidEglConfigAttribute,
                else => return error.EglConfigError,
            }
        }

        break :config config;
    };

    if (c.eglBindAPI(c.EGL_OPENGL_API) != c.EGL_TRUE) {
        switch (c.eglGetError()) {
            c.EGL_BAD_PARAMETER => return error.OpenGlUnsupported,
            else => return error.InvalidApi,
        }
    }

    self.egl_context = c.eglCreateContext(self.egl_display, egl_config, c.EGL_NO_CONTEXT, null) orelse switch (c.eglGetError()) {
        c.EGL_BAD_ATTRIBUTE => return error.InvalidContextAttribute,
        c.EGL_BAD_CONFIG => return error.CreateContextWithBadConfig,
        c.EGL_BAD_MATCH => return error.UnsupportedConfig,
        else => return error.FailedToCreateContext,
    };

    self.egl_window = try wl.EglWindow.create(self.wl_surface, width, height);

    self.egl_surface = c.eglCreatePlatformWindowSurface(self.egl_display, egl_config, @ptrCast(self.egl_window), null) orelse switch (c.eglGetError()) {
        c.EGL_BAD_MATCH => return error.MismatchedConfig,
        c.EGL_BAD_CONFIG => return error.InvalidConfig,
        c.EGL_BAD_NATIVE_WINDOW => return error.InvalidWindow,
        else => return error.FailedToCreateEglSurface,
    };

    const result = c.eglMakeCurrent(self.egl_display, self.egl_surface, self.egl_surface, self.egl_context);

    if (result == c.EGL_FALSE) {
        switch (c.eglGetError()) {
            c.EGL_BAD_ACCESS => return error.EglThreadError,
            c.EGL_BAD_MATCH => return error.MismatchedContextOrSurfaces,
            c.EGL_BAD_NATIVE_WINDOW => return error.EglWindowInvalid,
            c.EGL_BAD_CONTEXT => return error.InvalidEglContext,
            c.EGL_BAD_ALLOC => return error.OutOfMemory,
            else => return error.FailedToMakeCurrent,
        }
    }

    self.wl_surface.commit();
    if (self.wl_display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    self.renderer = try TextureRenderer.init(@floatFromInt(width), @floatFromInt(height));
    self.renderer.setTexture(image);

    self.running = true;
}

pub fn deinit(self: Window) void {
    self.renderer.deinit();

    std.posix.close(self.pipe_fds[0]);
    std.posix.close(self.pipe_fds[1]);

    _ = c.timer_delete(self.timer_id);

    self.xdg_surface.destroy();
    self.xdg_toplevel.destroy();

    self.keyboard.deinit();

    self.wl_keyboard.release();
    self.wl_pointer.release();
    self.wl_seat.destroy();
    self.wl_surface.destroy();
    self.wl_cursor_surface.destroy();
    self.wl_registry.destroy();
    self.wl_display.disconnect();

    _ = c.eglDestroySurface(self.egl_display, self.egl_surface);
    _ = c.eglDestroyContext(self.egl_display, self.egl_context);
    _ = c.eglTerminate(self.egl_display);
    self.egl_window.destroy();
}

pub fn setTitle(self: Window, title: [:0]const u8) void {
    self.xdg_toplevel.setTitle(title);
}

fn swapBuffers(self: Window) !void {
    if (self.xdg_configured) {
        if (c.eglSwapBuffers(self.egl_display, self.egl_surface) != c.EGL_TRUE) {
            switch (c.eglGetError()) {
                c.EGL_BAD_DISPLAY => return error.InvalidDisplay,
                c.EGL_BAD_SURFACE => return error.PresentInvalidSurface,
                c.EGL_CONTEXT_LOST => return error.EGLContextLost,
                else => return error.FailedToSwapBuffers,
            }
        }
    }
}

pub fn draw(self: *Window) !void {
    if (self.renderer.need_redraw) {
        self.renderer.render();
        try self.swapBuffers();
    }
}

pub fn shouldClose(self: Window) bool {
    return !self.running;
}
