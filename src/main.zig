const std = @import("std");
const Io = std.Io;

const minesweeper = @import("minesweeper");
const Grid = minesweeper.Grid;

pub fn main(init: std.process.Init) !void {
    const gpa: std.mem.Allocator = init.gpa;
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_file_writer: Io.File.Writer = .init(.stdout(), io, &stdout_buffer);
    const stdout_writer = &stdout_file_writer.interface;

    var seed: u64 = undefined;
    io.random(std.mem.asBytes(&seed));
    var rng = std.Random.DefaultPrng.init(seed);

    var grid = try Grid.init(gpa, rng.random(), 10, 10, 20);
    defer grid.deinit(gpa);

    // First render
    try grid.display(stdout_writer);
    try stdout_writer.flush();

    // Process player input
    var stdin_buffer: [1024]u8 = undefined;
    var stdin_file_reader: Io.File.Reader = .init(.stdin(), io, &stdin_buffer);
    const stdin_reader = &stdin_file_reader.interface;

    var gameState = minesweeper.GameState.ongoing;
    while (gameState == minesweeper.GameState.ongoing) {
        const raw = try stdin_reader.takeDelimiter('\n') orelse break;
        const line = std.mem.trim(u8, raw, " \r\t");
        var parts = std.mem.tokenizeScalar(u8, line, ' ');
        const command = parts.next() orelse continue;
        const xStr = parts.next() orelse continue;
        const yStr = parts.next() orelse continue;

        const x = std.fmt.parseInt(usize, xStr, 10) catch |err| {
            try stdout_writer.print("Invalid number for the x coordinate: `{s}` ({t})", .{ xStr, err });
            try stdout_writer.flush();
            continue;
        };
        const y = std.fmt.parseInt(usize, yStr, 10) catch |err| {
            try stdout_writer.print("Invalid number for the x coordinate: `{s}` ({t})", .{ xStr, err });
            try stdout_writer.flush();
            continue;
        };

        if (std.mem.eql(u8, command, "m")) {
            grid.markCell(x, y) catch |err| switch (err) {
                error.OutOfBounds => {
                    try stdout_writer.print("The coordinates {d}, {d} are out of bounds", .{ x, y });
                    try stdout_writer.flush();
                    continue;
                },
            };
        } else if (std.mem.eql(u8, command, "s")) {
            gameState = grid.revealCell(x, y) catch |err| switch (err) {
                error.OutOfBounds => {
                    try stdout_writer.print("The coordinates {d}, {d} are out of bounds", .{ x, y });
                    try stdout_writer.flush();
                    continue;
                },
                error.OutOfMemory => {
                    try stdout_writer.print("Internal error: ran out of memory while revealing hidden cells", .{});
                    try stdout_writer.flush();
                    return;
                },
            };
        }

        // Updated render
        try grid.display(stdout_writer);
        try stdout_writer.flush();
    }
}
