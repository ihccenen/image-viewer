const std = @import("std");
const Allocator = std.mem.Allocator;
const App = @import("App.zig");

const supported_formats = [_][:0]const u8{ ".jpeg", ".jpg", ".png", ".psd" };

fn lessThan(_: void, lhs: [:0]const u8, rhs: [:0]const u8) bool {
    return std.mem.orderZ(u8, lhs, rhs) == .lt;
}

fn isSupported(path: [:0]const u8) bool {
    for (supported_formats) |extension| {
        if (std.ascii.endsWithIgnoreCase(path, extension)) return true;
    }

    return false;
}

fn appendImagesPaths(allocator: Allocator, path_list: *std.ArrayListUnmanaged([:0]const u8), path: [:0]const u8) !void {
    if (isSupported(path)) {
        try path_list.append(allocator, path);
        return;
    }

    var walker = try (std.fs.cwd().openDir(path, .{ .iterate = true }) catch return).walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        switch (entry.kind) {
            .file => if (isSupported(entry.basename))
                try path_list.append(
                    allocator,
                    try std.fs.path.joinZ(allocator, &.{ path, entry.path }),
                ),

            else => {},
        }
    }
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var path_list: std.ArrayListUnmanaged([:0]const u8) = .empty;
    defer path_list.deinit(allocator);

    for (std.os.argv[1..]) |path| {
        try appendImagesPaths(allocator, &path_list, std.mem.span(path));
    }

    if (path_list.items.len < 1) {
        std.debug.print("usage: {s} [image path]\n", .{std.fs.path.basename(std.mem.span(std.os.argv[0]))});
        return;
    }

    std.mem.sort([:0]const u8, path_list.items, {}, lessThan);

    var app = try App.init(allocator, path_list.items);
    defer app.deinit(allocator);
    try app.run();
}
