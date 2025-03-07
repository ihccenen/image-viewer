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

const Keyboard = @import("Keyboard.zig");
const Event = @import("event.zig").Event;

fn keyboardListener(_: *wl.Keyboard, event: wl.Keyboard.Event, window: *Window) void {
    switch (event) {
        .keymap => |keymap| {
            defer std.posix.close(keymap.fd);
            const map_shm = std.posix.mmap(null, keymap.size, std.posix.PROT.READ, .{ .TYPE = .SHARED }, keymap.fd, 0) catch return;
            defer std.posix.munmap(map_shm);
            window.keyboard.setKeymap(@ptrCast(map_shm));
        },
        .enter => {},
        .leave => {},
        .key => |key| {
            window.dispatchKey(key.key, key.state == .pressed);
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
        },
        .name => {},
    }
}

fn wmBaseListener(_: *xdg.WmBase, event: xdg.WmBase.Event, window: *Window) void {
    switch (event) {
        .ping => |ping| {
            window.wm_base.pong(ping.serial);
        },
    }
}

fn registryListener(registry: *wl.Registry, event: wl.Registry.Event, window: *Window) void {
    switch (event) {
        .global => |global| {
            if (mem.orderZ(u8, global.interface, wl.Compositor.interface.name) == .eq) {
                window.wl_compositor = registry.bind(global.name, wl.Compositor, 1) catch return;
            } else if (mem.orderZ(u8, global.interface, wl.Seat.interface.name) == .eq) {
                window.wl_seat = registry.bind(global.name, wl.Seat, 9) catch return;
                window.wl_seat.setListener(*Window, seatListener, window);
            } else if (mem.orderZ(u8, global.interface, xdg.WmBase.interface.name) == .eq) {
                window.wm_base = registry.bind(global.name, xdg.WmBase, 1) catch return;
                window.wm_base.setListener(*Window, wmBaseListener, window);
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
            if (window.width != configure.width and window.height != configure.height) {
                window.width = @intCast(configure.width);
                window.height = @intCast(configure.height);
                wl.EglWindow.resize(window.egl_window, @intCast(window.width), @intCast(window.height), 0, 0);
                const e = Event{ .resize = .{ window.width, window.height } };
                _ = std.posix.write(window.pipe_fds[1], std.mem.asBytes(&e)) catch return;
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

fn onTimer(sigval: c.union_sigval) callconv(.C) void {
    const window = @as(*Window, @ptrCast(@alignCast(sigval.sival_ptr)));

    window.writeKeypress(window.repeat_keycode);
}

wl_display: *wl.Display = undefined,
wl_registry: *wl.Registry = undefined,
wl_compositor: *wl.Compositor = undefined,
wl_surface: *wl.Surface = undefined,
wl_seat: *wl.Seat = undefined,
wl_keyboard: *wl.Keyboard = undefined,

wm_base: *xdg.WmBase = undefined,
xdg_surface: *xdg.Surface = undefined,
xdg_toplevel: *xdg.Toplevel = undefined,
xdg_configured: bool = false,

egl_display: c.EGLDisplay = undefined,
egl_context: c.EGLContext = undefined,
egl_surface: c.EGLSurface = undefined,
egl_window: *wl.EglWindow = undefined,

width: usize = 0,
height: usize = 0,

keyboard: Keyboard = undefined,
repeat_keycode: u32 = undefined,
repeat_delay: i32 = 400,
repeat_interval: i32 = 80,

wl_display_fd: std.posix.fd_t = undefined,
pipe_fds: [2]std.posix.fd_t = undefined,
timer_id: c.timer_t = undefined,

running: bool = false,

pub fn init(self: *Window, width: usize, height: usize, title: [:0]u8) !void {
    self.wl_display = try wl.Display.connect(null);
    self.wl_registry = try self.wl_display.getRegistry();

    self.wl_display_fd = self.wl_display.getFd();

    self.wl_registry.setListener(*Window, registryListener, self);
    if (self.wl_display.roundtrip() != .SUCCESS) return error.RoundtripFailed;

    self.wl_surface = try self.wl_compositor.createSurface();
    self.xdg_surface = try self.wm_base.getXdgSurface(self.wl_surface);
    self.xdg_toplevel = try self.xdg_surface.getToplevel();

    self.xdg_surface.setListener(*Window, xdgSurfaceListener, self);
    self.xdg_toplevel.setTitle(title);
    self.xdg_toplevel.setListener(*Window, xdgToplevelListener, self);

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

    self.egl_window = try wl.EglWindow.create(self.wl_surface, @intCast(width), @intCast(height));

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

    self.running = true;
    self.pipe_fds = try std.posix.pipe();

    setNonBlock(self.pipe_fds[0]);
    setNonBlock(self.pipe_fds[0]);

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
}

pub fn deinit(self: *Window) void {
    std.posix.close(self.pipe_fds[0]);
    std.posix.close(self.pipe_fds[1]);

    _ = c.timer_delete(self.timer_id);

    self.xdg_surface.destroy();
    self.xdg_toplevel.destroy();

    self.keyboard.deinit();

    self.wl_keyboard.release();
    self.wl_seat.destroy();
    self.wl_surface.destroy();
    self.wl_registry.destroy();
    self.wl_display.disconnect();

    _ = c.eglTerminate(self.egl_display);
    _ = c.eglDestroyContext(self.egl_display, self.egl_context);
    self.egl_window.destroy();
}

pub fn setTitle(self: Window, title: [:0]u8) void {
    self.xdg_toplevel.setTitle(title);
}

pub fn swapBuffers(self: *Window) !void {
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

pub fn shouldClose(self: *Window) bool {
    return !self.running;
}

pub fn writeKeypress(self: Window, keycode: u32) void {
    const keysym = self.keyboard.getOneSym(keycode);
    const event = Event{ .keyboard = keysym };

    _ = std.posix.write(self.pipe_fds[1], std.mem.asBytes(&event)) catch return;
}

pub fn dispatchKey(self: *Window, keycode: u32, pressed: bool) void {
    self.keyboard.updateKey(keycode, pressed);

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

    self.writeKeypress(keycode);

    if (self.keyboard.keyRepeats(keycode)) {
        self.repeat_keycode = keycode;
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
