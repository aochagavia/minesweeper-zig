const std = @import("std");
const game = @import("../game.zig");
const rl = @import("raylib");

const ScreenParams = struct {
    width: usize,
    height: usize,

    fn toVector2(self: ScreenParams) rl.Vector2 {
        const screenWidth: f32 = @floatFromInt(self.width);
        const screenHeight: f32 = @floatFromInt(self.height);
        return .{
            .x = screenWidth,
            .y = screenHeight,
        };
    }
};

const GridParams = struct {
    width: usize,
    height: usize,
};

const ScreenToGridMapping = struct {
    cellSize: rl.Vector2,

    fn init(screen: ScreenParams, grid: GridParams) ScreenToGridMapping {
        const cellWidth = @as(f32, @floatFromInt(screen.width)) / @as(f32, @floatFromInt(grid.width));
        const cellHeight = @as(f32, @floatFromInt(screen.height)) / @as(f32, @floatFromInt(grid.height));
        return .{ .cellSize = .{ .x = cellWidth, .y = cellHeight } };
    }

    fn mapCoords(self: *const ScreenToGridMapping, pos: rl.Vector2) struct { usize, usize } {
        const gridX: usize = @floor(pos.x / self.cellSize.x);
        const gridY: usize = @floor(pos.y / self.cellSize.y);
        return .{ gridX, gridY };
    }
};

pub fn run(io: std.Io, allocator: std.mem.Allocator) !void {
    var seed: u64 = undefined;
    io.random(std.mem.asBytes(&seed));
    var rng: std.Random.DefaultPrng = .init(seed);

    const screenParams: ScreenParams = .{
        .width = 600,
        .height = 600,
    };

    const gridParams: GridParams = .{
        .width = 10,
        .height = 10,
    };

    const screenToGrid = ScreenToGridMapping.init(screenParams, gridParams);

    var grid = try game.Grid.init(allocator, rng.random(), gridParams.width, gridParams.height, 10);
    defer grid.deinit(allocator);
    var gameState: game.GameState = .ongoing;

    rl.initWindow(screenParams.width, screenParams.height, "Mine sweeper");
    rl.setTargetFPS(60);
    const font = try rl.getFontDefault();
    while (!rl.windowShouldClose()) {
        // Draw
        rl.beginDrawing();
        rl.clearBackground(rl.Color.blue);
        try drawGrid(font, &grid, screenToGrid.cellSize);
        drawGameState(screenParams, gameState, font);
        rl.endDrawing();

        // Handle input
        if (gameState != .ongoing) {
            if (rl.isKeyPressed(.enter)) {
                // Initialize the new grid before freeing the old one, so we can swap it
                // atomically (and hence prevent a double free if initialization fails).
                const newGrid = try game.Grid.init(allocator, rng.random(), gridParams.width, gridParams.height, 10);
                grid.deinit(allocator);
                grid = newGrid;
                gameState = .ongoing;
            }

            continue;
        }

        if (rl.isMouseButtonPressed(.left)) {
            const pos = rl.getMousePosition();
            const gridX, const gridY = screenToGrid.mapCoords(pos);
            gameState = grid.revealCell(gridX, gridY) catch {
                std.debug.print("impossible", .{});
                continue;
            };
        } else if (rl.isMouseButtonPressed(.right)) {
            const pos = rl.getMousePosition();
            const gridX, const gridY = screenToGrid.mapCoords(pos);
            grid.markCell(gridX, gridY) catch {
                std.debug.print("impossible", .{});
                continue;
            };
        }
    }
}

const intToStr = [_][:0]const u8{
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
};

fn drawGrid(font: rl.Font, grid: *const game.Grid, cellSize: rl.Vector2) !void {
    const cellBorder = 2;
    const paddedCellSize = cellSize.subtractValue(cellBorder * 2);

    const fontSize = @min(paddedCellSize.x, paddedCellSize.y) * 0.6;
    const fontSpacing = fontSize * 0.1;

    for (0..grid.height) |y| {
        for (0..grid.width) |x| {
            const cellPos: rl.Vector2 = .{ .x = @as(f32, @floatFromInt(x)) * cellSize.x, .y = @as(f32, @floatFromInt(y)) * cellSize.y };

            const view = try grid.cellView(x, y);
            switch (view) {
                .hidden => |c| {
                    if (c.marked) {
                        rl.drawRectangleV(cellPos.addValue(cellBorder), paddedCellSize, rl.Color.orange);
                    } else {
                        rl.drawRectangleV(cellPos.addValue(cellBorder), paddedCellSize, rl.Color.light_gray);
                    }
                },
                .mine => {
                    rl.drawRectangleV(cellPos.addValue(cellBorder), paddedCellSize, rl.Color.red);
                },
                .clear => |c| {
                    if (c.surroundingMines > 0) {
                        // Draw surrounding mines
                        const s = intToStr[c.surroundingMines];
                        const textSize = rl.measureTextEx(font, s, fontSize, fontSpacing);
                        const textPos = cellPos.add(centerBox(cellSize, textSize));
                        rl.drawRectangleV(cellPos.addValue(cellBorder), paddedCellSize, rl.Color.light_gray);
                        rl.drawTextEx(font, s, textPos, fontSize, fontSpacing, rl.Color.black);
                    }
                },
            }
        }
    }
}

fn drawGameState(screen: ScreenParams, state: game.GameState, font: rl.Font) void {
    const fontSize = 50;
    const fontSpacing = 10;

    const s: [:0]const u8 = switch (state) {
        .won => "You won!",
        .lost => "You lost!",
        .ongoing => return,
    };

    const hint = "Press Enter to restart";
    const hintFontSize = 20;
    const hintFontSpacing = 2;
    const lineGap = 10;

    const textSize = rl.measureTextEx(font, s, fontSize, fontSpacing);
    const hintSize = rl.measureTextEx(font, hint, hintFontSize, hintFontSpacing);
    const contentSize: rl.Vector2 = .{
        .x = @max(textSize.x, hintSize.x),
        .y = textSize.y + lineGap + hintSize.y,
    };
    const boxSize = contentSize.scale(1.2);

    // Overlay
    rl.drawRectangle(0, 0, @as(i32, @intCast(screen.width)), @as(i32, @intCast(screen.height)), rl.Color.black.fade(0.5));

    // The actual text, boxed for better readability
    const boxPos = centerBox(screen.toVector2(), boxSize);
    rl.drawRectangle(@as(i32, @floor(boxPos.x)), @as(i32, @floor(boxPos.y)), @as(i32, @ceil(boxSize.x)), @as(i32, @ceil(boxSize.y)), rl.Color.light_gray);

    // Both lines are horizontally centered within the content area, the hint below the main text
    const contentPos = centerBox(screen.toVector2(), contentSize);
    const textPos = contentPos.add(.{ .x = (contentSize.x - textSize.x) / 2, .y = 0 });
    const hintPos = contentPos.add(.{ .x = (contentSize.x - hintSize.x) / 2, .y = textSize.y + lineGap });
    rl.drawTextEx(font, s, textPos, fontSize, fontSpacing, rl.Color.black);
    rl.drawTextEx(font, hint, hintPos, hintFontSize, hintFontSpacing, rl.Color.dark_gray);
}

fn centerBox(containerSize: rl.Vector2, boxSize: rl.Vector2) rl.Vector2 {
    var computedPosition = rl.Vector2.zero();
    if (boxSize.x < containerSize.x) {
        computedPosition.x = containerSize.x / 2 - boxSize.x / 2;
    }

    if (boxSize.y < containerSize.y) {
        computedPosition.y = containerSize.y / 2 - boxSize.y / 2;
    }

    return computedPosition;
}
