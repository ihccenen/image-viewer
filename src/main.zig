const std = @import("std");
const Allocator = std.mem.Allocator;
const App = @import("App.zig");

const supported_formats = [_][:0]const u8{ ".jpeg", ".jpg", ".png", ".psd" };

fn lessThan(_: void, lhs: [:0]u8, rhs: [:0]u8) bool {
    return std.mem.orderZ(u8, lhs, rhs) == .lt;
}

fn isSupported(path: [:0]u8) bool {
    const ext = std.fs.path.extension(path);

    for (supported_formats) |extension| {
        if (std.mem.eql(u8, ext, extension)) return true;
    }

    return false;
}

fn appendImagePaths(allocator: Allocator, paths: *std.ArrayList([:0]u8), current_path: [:0]u8) !void {
    var iter = (std.fs.cwd().openDir(current_path, .{ .iterate = true }) catch {
        if (isSupported(current_path)) try paths.append(current_path);

        return;
    }).iterate();

    while (try iter.next()) |entry| {
        const path = try std.fs.path.joinZ(allocator, &[_][]const u8{ current_path, entry.name });
        switch (entry.kind) {
            .file => _ = if (isSupported(path)) try paths.append(path),
            .directory => try appendImagePaths(allocator, paths, path),
            else => {},
        }
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var paths = std.ArrayList([:0]u8).init(allocator);
    defer paths.deinit();

    for (std.os.argv[1..]) |arg| {
        try appendImagePaths(allocator, &paths, std.mem.span(arg));
    }

    if (paths.items.len < 1) {
        std.debug.print("usage: {s} [image path]\n", .{std.fs.path.basename(std.mem.span(std.os.argv[0]))});
        return;
    }

    std.mem.sort([:0]u8, paths.items, {}, lessThan);

    var app = try App.init(allocator, paths.items);
    defer app.deinit();
    try app.run();
}
