const std = @import("std");

pub fn run(_: std.Io, _: std.mem.Allocator) !void {
    std.debug.print("Hello\n", .{});
}
