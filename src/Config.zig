pub const Config = @This();

const std = @import("std");
const Allocator = std.mem.Allocator;

const Keyboard = @import("Keyboard.zig");

left: [:0]const u8,
down: [:0]const u8,
up: [:0]const u8,
right: [:0]const u8,
@"zoom-in": [:0]const u8,
@"zoom-out": [:0]const u8,
@"fit-both": [:0]const u8,
@"fit-width": [:0]const u8,
reset: [:0]const u8,
quit: [:0]const u8,
next: [:0]const u8,
previous: [:0]const u8,

const default: Config = .{
    .left = "h",
    .down = "j",
    .up = "k",
    .right = "l",
    .@"zoom-in" = "plus",
    .@"zoom-out" = "minus",
    .@"fit-both" = "w",
    .@"fit-width" = "s",
    .reset = "o",
    .quit = "q",
    .next = "n",
    .previous = "p",
};

fn parseLine(allocator: Allocator, config: *Config, line: []u8, line_number: usize) !void {
    var it = std.mem.splitScalar(u8, line, '=');
    const command = std.mem.trim(u8, it.first(), " ");

    inline for (@typeInfo(Config).@"struct".fields) |field| {
        if (std.mem.order(u8, command, field.name) == .eq) {
            const key = try allocator.dupeZ(u8, std.mem.trim(u8, it.next() orelse "", " ="));

            if (Keyboard.isKeyValid(key)) {
                @field(config, field.name) = key;
            } else {
                std.log.warn("invalid key in line {d} \"{s}\"\n", .{ line_number, key });
                allocator.free(key);
            }
            return;
        }
    }

    std.log.warn("invalid command in line {d} \"{s}\"\n", .{ line_number, command });
}

pub fn init(allocator: Allocator) !*Config {
    const config = try allocator.create(Config);
    config.* = .default;

    const basename = std.fs.path.basename(std.mem.span(std.os.argv[0]));

    const config_path = if (std.posix.getenv("XDG_CONFIG_HOME")) |dir|
        try std.fs.path.join(allocator, &.{ dir, basename, "config" })
    else
        try std.fs.path.join(allocator, &.{ std.posix.getenv("HOME").?, ".config", basename, "config" });

    defer allocator.free(config_path);
    const config_file = std.fs.cwd().openFile(config_path, .{}) catch return config;
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
        if (line.items.len > 0)
            try parseLine(allocator, config, line.items[0..line.items.len], line_number);
    } else |err| switch (err) {
        error.EndOfStream => {
            if (line.items.len > 0) {
                line_number += 1;
                try parseLine(allocator, config, line.items[0..line.items.len], line_number);
            }
        },
        else => return err,
    }

    return config;
}
