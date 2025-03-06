const std = @import("std");
const Allocator = std.mem.Allocator;
const Window = @import("Window.zig");
const Renderer = @import("Renderer.zig");
const App = @import("App.zig");

const supported_formats = [_][:0]const u8{ ".jpeg", ".jpg", ".png", ".psd" };

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

    var app = try App.init(allocator, paths.items);
    defer app.deinit();
    try app.run();
}
