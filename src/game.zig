const std = @import("std");

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

    pub const InitError = error{MoreMinesThanCells} || std.mem.Allocator.Error;

    pub fn init(a: std.mem.Allocator, rng: std.Random, width: usize, height: usize, mines: usize) InitError!Grid {
        const len = width * height;
        if (mines >= len) {
            return error.MoreMinesThanCells;
        }

        var mineCells = try std.bit_set.Dynamic.initEmpty(a, len);
        errdefer mineCells.deinit(a);
        var visibleCells = try std.bit_set.Dynamic.initEmpty(a, len);
        errdefer visibleCells.deinit(a);
        var markedCells = try std.bit_set.Dynamic.initEmpty(a, len);
        errdefer markedCells.deinit(a);

        var cellQueue = try std.Deque(usize).initCapacity(a, len);
        errdefer cellQueue.deinit(a);

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
        const surroundingMineCounts = try a.alloc(u4, len);
        @memset(surroundingMineCounts, 0);
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

    fn coordsToGridIndex(self: *const Grid, x: usize, y: usize) error{OutOfBounds}!usize {
        if (x < self.width and y < self.height) {
            return y * self.width + x;
        }

        return error.OutOfBounds;
    }

    pub fn cellView(self: *const Grid, x: usize, y: usize) error{OutOfBounds}!CellView {
        const i = try self.coordsToGridIndex(x, y);
        if (!self.visibleCells.isSet(i)) {
            return .{ .hidden = .{ .marked = self.markedCells.isSet(i) } };
        }

        if (self.mineCells.isSet(i)) {
            return .mine;
        }

        return .{ .clear = .{ .surroundingMines = self.surroundingMineCounts[i] } };
    }

    pub fn revealCell(self: *Grid, x: usize, y: usize) error{OutOfBounds}!GameState {
        const i = try self.coordsToGridIndex(x, y);

        if (self.visibleCells.isSet(i) or self.markedCells.isSet(i)) {
            return .ongoing;
        }
        self.visibleCells.set(i);

        if (self.mineCells.isSet(i)) {
            return .lost;
        }

        // Recursive cell reveal
        self.cellQueue.pushBackAssumeCapacity(i);
        while (self.cellQueue.popFront()) |cellIndex| {
            var surroundingCells = SurroundingCellIndexIterator.init(self.width, self.gridLength(), cellIndex);
            while (surroundingCells.next()) |surroundingCellIndex| {
                if (self.visibleCells.isSet(surroundingCellIndex) or self.mineCells.isSet(surroundingCellIndex)) {
                    continue;
                }

                self.visibleCells.set(surroundingCellIndex);
                if (self.surroundingMineCounts[surroundingCellIndex] == 0) {
                    self.cellQueue.pushBackAssumeCapacity(surroundingCellIndex);
                }
            }
        }

        // If we uncovered everything besides the mines themselves, we won!
        const totalMines: usize = self.mineCells.count();
        const totalHiddenCells: usize = self.visibleCells.bit_length - self.visibleCells.count();
        if (totalHiddenCells == totalMines) {
            return .won;
        }

        return .ongoing;
    }

    pub fn markCell(self: *Grid, x: usize, y: usize) error{OutOfBounds}!void {
        const i = try self.coordsToGridIndex(x, y);
        self.markedCells.toggle(i);
    }
};

pub const GameState = enum { won, lost, ongoing };

pub const CellView = union(enum) {
    hidden: struct { marked: bool },
    mine,
    clear: struct { surroundingMines: usize },
};

const surrounding_offsets: [8]struct { HorizontalOffset, VerticalOffset } = .{
    .{ .left, .up },
    .{ .none, .up },
    .{ .right, .up },
    .{ .left, .none },
    .{ .right, .none },
    .{ .left, .down },
    .{ .none, .down },
    .{ .right, .down },
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
            const horizontalOffset, const verticalOffset = surrounding_offsets[self.currentOffsetIndex];
            self.currentOffsetIndex += 1;

            var surroundingCellIndex = self.cellIndex;
            switch (horizontalOffset) {
                .left => {
                    const hasLeft = self.cellIndex % self.gridWidth != 0;
                    if (hasLeft) {
                        surroundingCellIndex -= 1;
                    } else {
                        continue;
                    }
                },
                .right => {
                    const hasRight = self.cellIndex % self.gridWidth != self.gridWidth - 1;
                    if (hasRight) {
                        surroundingCellIndex += 1;
                    } else {
                        continue;
                    }
                },
                .none => {},
            }

            switch (verticalOffset) {
                .up => {
                    const hasUp = self.cellIndex >= self.gridWidth;
                    if (hasUp) {
                        surroundingCellIndex -= self.gridWidth;
                    } else {
                        continue;
                    }
                },
                .down => {
                    const hasDown = self.cellIndex < self.gridLength - self.gridWidth;
                    if (hasDown) {
                        surroundingCellIndex += self.gridWidth;
                    } else {
                        continue;
                    }
                },
                .none => {},
            }

            return surroundingCellIndex;
        }

        return null;
    }
};

const HorizontalOffset = enum {
    left,
    none,
    right,
};

const VerticalOffset = enum {
    up,
    none,
    down,
};

test "surrounding cell index iterator at 0" {
    var iter = SurroundingCellIndexIterator.init(10, 100, 0);
    try std.testing.expectEqual(1, iter.next());
    try std.testing.expectEqual(10, iter.next());
    try std.testing.expectEqual(11, iter.next());
    try std.testing.expectEqual(null, iter.next());
}

test "surrounding cell index iterator at 1" {
    var iter = SurroundingCellIndexIterator.init(10, 100, 1);
    try std.testing.expectEqual(0, iter.next());
    try std.testing.expectEqual(2, iter.next());
    try std.testing.expectEqual(10, iter.next());
    try std.testing.expectEqual(11, iter.next());
    try std.testing.expectEqual(12, iter.next());
    try std.testing.expectEqual(null, iter.next());
}

test "surrounding cell index iterator at 9" {
    var iter = SurroundingCellIndexIterator.init(10, 100, 9);
    try std.testing.expectEqual(8, iter.next());
    try std.testing.expectEqual(18, iter.next());
    try std.testing.expectEqual(19, iter.next());
    try std.testing.expectEqual(null, iter.next());
}

test "surrounding cell index iterator at 90" {
    var iter = SurroundingCellIndexIterator.init(10, 100, 90);
    try std.testing.expectEqual(80, iter.next());
    try std.testing.expectEqual(81, iter.next());
    try std.testing.expectEqual(91, iter.next());
    try std.testing.expectEqual(null, iter.next());
}

test "surrounding cell index iterator at 99" {
    var iter = SurroundingCellIndexIterator.init(10, 100, 99);
    try std.testing.expectEqual(88, iter.next());
    try std.testing.expectEqual(89, iter.next());
    try std.testing.expectEqual(98, iter.next());
    try std.testing.expectEqual(null, iter.next());
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
    try std.testing.expectEqual(null, iter.next());
}

test "grid cleanup" {
    const a = std.testing.allocator;
    var rng = std.Random.DefaultPrng.init(0);
    var grid = try Grid.init(a, rng.random(), 20, 10, 12);
    defer grid.deinit(a); // Try commenting this out and see if zig detects the memory leak!
}

test "grid cleanup after failed allocation during init" {
    const helper = struct {
        fn initAndDeinitGrid(a: std.mem.Allocator) !void {
            var rng = std.Random.DefaultPrng.init(0);
            var grid = try Grid.init(a, rng.random(), 20, 10, 12);
            grid.deinit(a);
        }
    };

    try std.testing.checkAllAllocationFailures(std.testing.allocator, helper.initAndDeinitGrid, .{});
}
