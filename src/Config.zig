pub const Config = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Keyboard = @import("Keyboard.zig");

const Command = enum {
    left,
    down,
    up,
    right,
    @"zoom-in",
    @"zoom-out",
    @"fit-both",
    @"fit-width",
    @"fit-none",
    next,
    previous,
    quit,
};

const Keybindings = std.StringHashMapUnmanaged(Command);

fn setDefaults(allocator: Allocator, keybindings: *Keybindings) !void {
    const defaults = [_]struct { [:0]const u8, Command }{
        .{ "h", .left },
        .{ "j", .down },
        .{ "k", .up },
        .{ "l", .right },
        .{ "plus", .@"zoom-in" },
        .{ "minus", .@"zoom-out" },
        .{ "a", .@"fit-both" },
        .{ "s", .@"fit-width" },
        .{ "d", .@"fit-none" },
        .{ "n", .next },
        .{ "p", .previous },
        .{ "q", .quit },
    };

    for (defaults) |default| {
        const cmd_key, const cmd = default;

        key: {
            var iter = keybindings.valueIterator();

            while (iter.next()) |entry| {
                if (entry.* == cmd)
                    break :key;
            }

            if (!keybindings.contains(cmd_key))
                try keybindings.put(allocator, try allocator.dupeZ(u8, cmd_key), cmd);
        }
    }
}

fn parseCommand(allocator: Allocator, keybindings: *Keybindings, line: []u8, line_number: usize) !?struct { Command, [][:0]const u8 } {
    if (line.len < 1) return null;

    var it = std.mem.splitScalar(u8, line, '=');

    const command = std.mem.trim(u8, it.first(), " ");
    const cmd = std.meta.stringToEnum(Command, command) orelse {
        std.log.warn("line {d}: unknown command \"{s}\"", .{ line_number, command });
        return null;
    };

    var keys = std.mem.splitScalar(u8, it.next() orelse "", ',');
    var list: std.ArrayListUnmanaged([:0]const u8) = .empty;
    errdefer list.deinit(allocator);

    while (keys.next()) |next| {
        const key = try allocator.dupeZ(u8, std.mem.trim(u8, next, " "));

        if (Keyboard.isKeyValid(key)) {
            if (!keybindings.contains(key)) {
                try list.append(allocator, key);
            } else {
                std.log.warn("line {d}: key \"{s}\" already in use", .{ line_number, key });
                allocator.free(key);
            }
        } else {
            std.log.warn("line {d}: unknown key \"{s}\"", .{ line_number, key });
            allocator.free(key);
        }
    }

    if (list.items.len < 1)
        return null;

    return .{ cmd, try list.toOwnedSlice(allocator) };
}

fn setKeybindings(allocator: Allocator, keybindings: *Keybindings, line: []u8, line_number: usize) !void {
    if (try parseCommand(allocator, keybindings, line, line_number)) |result| {
        const cmd, const list = result;
        defer allocator.free(list);
        for (list) |key| {
            try keybindings.put(allocator, key, cmd);
        }
    }
}

keybindings: Keybindings,

pub fn init(allocator: Allocator) !Config {
    const basename = std.fs.path.basename(std.mem.span(std.os.argv[0]));
    const config_path = if (std.posix.getenv("XDG_CONFIG_HOME")) |dir|
        try std.fs.path.join(allocator, &.{ dir, basename, "config" })
    else
        try std.fs.path.join(allocator, &.{ std.posix.getenv("HOME").?, ".config", basename, "config" });

    defer allocator.free(config_path);

    var keybindings: Keybindings = .empty;

    const config_file = std.fs.cwd().openFile(config_path, .{}) catch {
        try setDefaults(allocator, &keybindings);
        return .{ .keybindings = keybindings };
    };
    defer config_file.close();

    var buf_reader = std.io.bufferedReader(config_file.reader());
    const reader = buf_reader.reader();
    var line: std.ArrayListUnmanaged(u8) = .empty;
    defer line.deinit(allocator);
    const writer = line.writer(allocator);
    var line_number: usize = 0;

    while (reader.streamUntilDelimiter(writer, '\n', null)) {
        defer line.clearRetainingCapacity();
        line_number += 1;
        try setKeybindings(allocator, &keybindings, line.items[0..line.items.len], line_number);
    } else |err| switch (err) {
        error.EndOfStream => {
            line_number += 1;
            try setKeybindings(allocator, &keybindings, line.items[0..line.items.len], line_number);
        },
        else => return err,
    }

    try setDefaults(allocator, &keybindings);

    return .{ .keybindings = keybindings };
}

pub fn deinit(self: *Config, allocator: Allocator) void {
    defer self.keybindings.deinit(allocator);
    var iter = self.keybindings.iterator();

    while (iter.next()) |entry| {
        allocator.free(entry.key_ptr.*);
    }
}

pub fn cmdFromKey(self: Config, key: [:0]const u8) ?Command {
    return self.keybindings.get(std.mem.span(key.ptr));
}
