const std = @import("std");
const Io = std.Io;

const game = @import("game.zig");
pub const Grid = game.Grid;
pub const GameState = game.GameState;

pub const pretty = @import("views/pretty.zig");
pub const cli = @import("views/cli.zig");

test {
    _ = game;
    _ = cli;
    _ = pretty;
}
