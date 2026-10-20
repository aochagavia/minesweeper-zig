const std = @import("std");
const Io = std.Io;

pub const Grid = struct {
    width: usize,
    height: usize,
    mineCells: std.bit_set.Dynamic,
    visibleCells: std.bit_set.Dynamic,
    markedCells: std.bit_set.Dynamic,

    // Cached surrounding mine counts per cell
    surroundingMineCounts: []u4,

    // Used when traversing the grid
    //
    // The queue can hold at most `width * height` cells, which should be enough for anybody and
    // keeps memory usage bounded
    cellQueue: std.Deque(usize),

    pub fn init(a: std.mem.Allocator, rng: std.Random, width: usize, height: usize, mines: usize) !Grid {
        const len = width * height;
        if (mines >= len) {
            return error.MoreMinesThanCells;
        }

        var mineCells = try std.bit_set.Dynamic.initEmpty(a, len);
        const visibleCells = try std.bit_set.Dynamic.initEmpty(a, len);
        const markedCells = try std.bit_set.Dynamic.initEmpty(a, len);

        const surroundingMineCounts = try a.alloc(u4, len);
        const cellQueue = try std.Deque(usize).initCapacity(a, len);

        // Place mines
        var placedMines: usize = 0;
        while (placedMines < mines) {
            const i = rng.uintLessThan(usize, len);
            if (!mineCells.isSet(i)) {
                mineCells.set(i);
                placedMines += 1;
            }
        }

        // Calculate mines surrounding each cell
        for (0..len) |i| {
            if (mineCells.isSet(i)) {
                continue;
            }

            var surroundingMines: u4 = 0;
            var surroundingCellIter = SurroundingCellIndexIterator.init(width, len, i);
            while (surroundingCellIter.next()) |surroundingCellIndex| {
                if (mineCells.isSet(surroundingCellIndex)) {
                    surroundingMines += 1;
                }
            }
            surroundingMineCounts[i] = surroundingMines;
        }

        return .{ .width = width, .height = height, .mineCells = mineCells, .visibleCells = visibleCells, .markedCells = markedCells, .cellQueue = cellQueue, .surroundingMineCounts = surroundingMineCounts };
    }

    pub fn deinit(self: *Grid, a: std.mem.Allocator) void {
        self.mineCells.deinit(a);
        self.visibleCells.deinit(a);
        self.markedCells.deinit(a);
        self.cellQueue.deinit(a);
        a.free(self.surroundingMineCounts);
    }

    fn gridLength(self: *const Grid) usize {
        return self.width * self.height;
    }

    pub fn revealCell(self: *Grid, x: usize, y: usize) error{ OutOfBounds, OutOfMemory }!GameState {
        const i = y * self.width + x;
        if (i >= self.gridLength()) {
            return error.OutOfBounds;
        }

        if (self.visibleCells.isSet(i)) {
            return GameState.ongoing;
        }
        self.visibleCells.set(i);

        if (self.mineCells.isSet(i)) {
            return GameState.lost;
        }

        // Recursive cell reveal
        self.cellQueue.len = 0;
        try self.cellQueue.pushBackBounded(i);
        while (self.cellQueue.popFront()) |cellIndex| {
            var surroundingCells = SurroundingCellIndexIterator.init(self.width, self.gridLength(), cellIndex);
            while (surroundingCells.next()) |surroundingCellIndex| {
                if (self.visibleCells.isSet(surroundingCellIndex) or self.mineCells.isSet(surroundingCellIndex)) {
                    continue;
                }

                    self.visibleCells.set(surroundingCellIndex);
                    if (self.surroundingMineCounts[surroundingCellIndex] == 0) {
                        try self.cellQueue.pushBackBounded(surroundingCellIndex);
                }
            }
        }

        // If we uncovered everything besides the mines themselves, we won!
        const totalMines: usize = self.mineCells.count();
        const totalHiddenCells: usize = self.visibleCells.bit_length - self.visibleCells.count();
        if (totalHiddenCells == totalMines) {
            return GameState.won;
        }

        return GameState.ongoing;
    }

    pub fn markCell(self: *Grid, x: usize, y: usize) error{OutOfBounds}!void {
        const i = y * self.width + x;
        if (i >= self.gridLength()) {
            return error.OutOfBounds;
        }

        self.markedCells.toggle(i);
    }

    pub fn display(self: *Grid, writer: *Io.Writer) !void {
        // Horizontal axis coordinates
        try writer.print("   ", .{});
        for (0..self.width) |x| {
            if (x < 10) {
                try writer.print(" ", .{});
            }
            try writer.print("{d} ", .{x});
        }
        try writer.print("\n\n", .{});

        // Vertical axis coordinates + each row's cells
        for (0..self.height) |y| {
            try writer.print("{d} ", .{y});
            if (y < 10) {
                try writer.print(" ", .{});
            }

            for (0..self.width) |x| {
                const i = y * self.width + x;
                const visible = self.visibleCells.isSet(i);
                const mine = self.mineCells.isSet(i);
                const marked = self.markedCells.isSet(i);

                if (visible) {
                    if (mine) {
                        try writer.print(" * ", .{});
                    } else {
                        const mineCount = self.surroundingMineCounts[i];
                        if (mineCount == 0) {
                            try writer.print("   ", .{});
                        } else {
                            try writer.print(" {d} ", .{mineCount});
                        }
                    }
                } else {
                    if (marked) {
                        try writer.print("[x]", .{});
                    } else {
                        try writer.print("[ ]", .{});
                    }
                }
            }

            try writer.print("\n", .{});
        }
    }
};

pub const GameState = enum { won, lost, ongoing };

const SurroundingOffsets: [8]struct { HorizontalOffset, VerticalOffset } = .{
    .{ HorizontalOffset.Left, VerticalOffset.Up },
    .{ HorizontalOffset.None, VerticalOffset.Up },
    .{ HorizontalOffset.Right, VerticalOffset.Up },
    .{ HorizontalOffset.Left, VerticalOffset.None },
    .{ HorizontalOffset.Right, VerticalOffset.None },
    .{ HorizontalOffset.Left, VerticalOffset.Down },
    .{ HorizontalOffset.None, VerticalOffset.Down },
    .{ HorizontalOffset.Right, VerticalOffset.Down },
};

const SurroundingCellIndexIterator = struct {
    gridWidth: usize,
    gridLength: usize,
    cellIndex: usize,
    currentOffsetIndex: usize,

    pub fn init(gridWidth: usize, gridLength: usize, cellIndex: usize) SurroundingCellIndexIterator {
        return .{ .gridWidth = gridWidth, .gridLength = gridLength, .cellIndex = cellIndex, .currentOffsetIndex = 0 };
    }

    pub fn next(self: *SurroundingCellIndexIterator) ?usize {
        while (self.currentOffsetIndex < 8) {
            const horizontalOffset, const verticalOffset = SurroundingOffsets[self.currentOffsetIndex];
            self.currentOffsetIndex += 1;

            var surroundingCellIndex = self.cellIndex;
            switch (horizontalOffset) {
                .Left => {
                    const hasLeft = self.cellIndex % self.gridWidth != 0;
                    if (hasLeft) {
                        surroundingCellIndex -= 1;
                    } else {
                        continue;
                    }
                },
                .Right => {
                    const hasRight = self.cellIndex % self.gridWidth != self.gridWidth - 1;
                    if (hasRight) {
                        surroundingCellIndex += 1;
                    } else {
                        continue;
                    }
                },
                .None => {},
            }

            switch (verticalOffset) {
                .Up => {
                    const hasUp = self.cellIndex >= self.gridWidth;
                    if (hasUp) {
                        surroundingCellIndex -= self.gridWidth;
                    } else {
                        continue;
                    }
                },
                .Down => {
                    const hasDown = self.cellIndex < self.gridLength - self.gridWidth;
                    if (hasDown) {
                        surroundingCellIndex += self.gridWidth;
                    } else {
                        continue;
                    }
                },
                .None => {},
            }

            return surroundingCellIndex;
        }

        return null;
    }
};

const HorizontalOffset = enum {
    Left,
    None,
    Right,
};

const VerticalOffset = enum {
    Up,
    None,
    Down,
};

test "surrounding cell index iterator at 0" {
    var iter = SurroundingCellIndexIterator.init(10, 100, 0);
    try std.testing.expectEqual(1, iter.next());
    try std.testing.expectEqual(10, iter.next());
    try std.testing.expectEqual(11, iter.next());
}

test "surrounding cell index iterator at 1" {
    var iter = SurroundingCellIndexIterator.init(10, 100, 1);
    try std.testing.expectEqual(0, iter.next());
    try std.testing.expectEqual(2, iter.next());
    try std.testing.expectEqual(10, iter.next());
    try std.testing.expectEqual(11, iter.next());
    try std.testing.expectEqual(12, iter.next());
}

test "surrounding cell index iterator at 9" {
    var iter = SurroundingCellIndexIterator.init(10, 100, 9);
    try std.testing.expectEqual(8, iter.next());
    try std.testing.expectEqual(18, iter.next());
    try std.testing.expectEqual(19, iter.next());
}

test "surrounding cell index iterator at 90" {
    var iter = SurroundingCellIndexIterator.init(10, 100, 90);
    try std.testing.expectEqual(80, iter.next());
    try std.testing.expectEqual(81, iter.next());
    try std.testing.expectEqual(91, iter.next());
}

test "surrounding cell index iterator at 99" {
    var iter = SurroundingCellIndexIterator.init(10, 100, 99);
    try std.testing.expectEqual(88, iter.next());
    try std.testing.expectEqual(89, iter.next());
    try std.testing.expectEqual(98, iter.next());
}

test "surrounding cell index iterator at 55" {
    var iter = SurroundingCellIndexIterator.init(10, 100, 55);
    try std.testing.expectEqual(44, iter.next());
    try std.testing.expectEqual(45, iter.next());
    try std.testing.expectEqual(46, iter.next());
    try std.testing.expectEqual(54, iter.next());
    try std.testing.expectEqual(56, iter.next());
    try std.testing.expectEqual(64, iter.next());
    try std.testing.expectEqual(65, iter.next());
    try std.testing.expectEqual(66, iter.next());
}

test "grid cleanup" {
    const a = std.testing.allocator;
    var rng = std.Random.DefaultPrng.init(0);
    var grid = try Grid.init(a, rng.random(), 20, 10, 12);
    defer grid.deinit(a); // Try commenting this out and see if zig detects the memory leak!
}
