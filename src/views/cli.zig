const std = @import("std");
const Io = std.Io;

const game = @import("../game.zig");
const Grid = game.Grid;

pub fn run(init: std.process.Init) !void {
    const gpa = init.gpa;
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var seed: u64 = undefined;
    io.random(std.mem.asBytes(&seed));
    var rng: std.Random.DefaultPrng = .init(seed);

    var grid = try Grid.init(gpa, rng.random(), 10, 10, 20);
    defer grid.deinit(gpa);

    // First render
    try printGrid(&grid, stdout_writer);
    try stdout_writer.flush();

    // Process player input
    var stdin_buffer: [1024]u8 = undefined;
    var stdin_file_reader: Io.File.Reader = .init(.stdin(), io, &stdin_buffer);
    const stdin_reader = &stdin_file_reader.interface;

    var gameState: game.GameState = .ongoing;
    while (gameState == .ongoing) {
        const raw = try stdin_reader.takeDelimiter('\n') orelse break;
        const line = std.mem.trim(u8, raw, " \r\t");
        var parts = std.mem.tokenizeScalar(u8, line, ' ');
        const command = parts.next() orelse continue;
        const xStr = parts.next() orelse continue;
        const yStr = parts.next() orelse continue;

        const x = std.fmt.parseInt(usize, xStr, 10) catch |err| {
            try stdout_writer.print("Invalid number for the x coordinate: `{s}` ({t})\n", .{ xStr, err });
            try stdout_writer.flush();
            continue;
        };
        const y = std.fmt.parseInt(usize, yStr, 10) catch |err| {
            try stdout_writer.print("Invalid number for the y coordinate: `{s}` ({t})\n", .{ yStr, err });
            try stdout_writer.flush();
            continue;
        };

        if (std.mem.eql(u8, command, "m")) {
            grid.markCell(x, y) catch |err| switch (err) {
                error.OutOfBounds => {
                    try stdout_writer.print("The coordinates {d}, {d} are out of bounds\n", .{ x, y });
                    try stdout_writer.flush();
                    continue;
                },
            };
        } else if (std.mem.eql(u8, command, "s")) {
            gameState = grid.revealCell(x, y) catch |err| switch (err) {
                error.OutOfBounds => {
                    try stdout_writer.print("The coordinates {d}, {d} are out of bounds\n", .{ x, y });
                    try stdout_writer.flush();
                    continue;
                },
            };
        }

        // Updated render
        try printGrid(&grid, stdout_writer);
        try stdout_writer.flush();
    }
}

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
