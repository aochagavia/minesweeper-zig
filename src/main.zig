const std = @import("std");
const Io = std.Io;

const minesweeper = @import("minesweeper");

pub fn main(init: std.process.Init) !void {
    var args = init.minimal.args.iterate();
    _ = args.skip();

    if (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "pretty")) {
            try minesweeper.pretty.run(init.io, init.gpa);
        } else {
            std.debug.print("Unknown argument: {s}\n", .{arg});
            return;
        }
    } else {
        try minesweeper.cli.run(init);
    }
}
