const std = @import("std");
const Io = std.Io;

const game = @import("game.zig");
pub const Grid = game.Grid;
pub const GameState = game.GameState;

pub fn printGrid(grid: *const Grid, writer: *Io.Writer) Io.Writer.Error!void {
    // Horizontal axis coordinates
    try writer.writeAll("   ");
    for (0..grid.width) |x| {
        try writer.print("{d:>2} ", .{x});
    }
    try writer.writeAll("\n\n");

    // Vertical axis coordinates + each row's cells
    for (0..grid.height) |y| {
        try writer.print("{d:<2} ", .{y});
        for (0..grid.width) |x| {
            const i = y * grid.width + x;
            const visible = grid.visibleCells.isSet(i);
            const mine = grid.mineCells.isSet(i);
            const marked = grid.markedCells.isSet(i);

            if (visible) {
                if (mine) {
                    try writer.writeAll(" * ");
                } else {
                    const mineCount = grid.surroundingMineCounts[i];
                    if (mineCount == 0) {
                        try writer.writeAll("   ");
                    } else {
                        try writer.print(" {d} ", .{mineCount});
                    }
                }
            } else {
                if (marked) {
                    try writer.writeAll("[x]");
                } else {
                    try writer.writeAll("[ ]");
                }
            }
        }

        try writer.writeAll("\n");
    }
}

test {
    _ = game;
}
