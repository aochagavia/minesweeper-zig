const std = @import("std");
const game = @import("../game.zig");
const rl = @import("raylib");

// Minimal equivalent to raylib's `Vector2`, but stores `usize`
const Vector2Usize = struct {
    x: usize,
    y: usize,

    fn init(x: usize, y: usize) Vector2Usize {
        return .{ .x = x, .y = y };
    }

    fn toVector2(self: Vector2Usize) rl.Vector2 {
        return .init(@floatFromInt(self.x), @floatFromInt(self.y));
    }
};

const ScreenToGridMapping = struct {
    cellSize: rl.Vector2,

    fn init(screenSize: Vector2Usize, gridSize: Vector2Usize) ScreenToGridMapping {
        return .{ .cellSize = screenSize.toVector2().divide(gridSize.toVector2()) };
    }

    fn mapCoords(self: *const ScreenToGridMapping, pos: rl.Vector2) Vector2Usize {
        const gridX: usize = @floor(pos.x / self.cellSize.x);
        const gridY: usize = @floor(pos.y / self.cellSize.y);
        return .init(gridX, gridY);
    }
};

pub fn run(io: std.Io, allocator: std.mem.Allocator) !void {
    var seed: u64 = undefined;
    io.random(std.mem.asBytes(&seed));
    var rng: std.Random.DefaultPrng = .init(seed);

    const screenSizePx: Vector2Usize = comptime .init(600, 600);
    const gridSize: Vector2Usize = .init(10, 10);
    const screenToGrid = ScreenToGridMapping.init(screenSizePx, gridSize);

    var grid = try game.Grid.init(allocator, rng.random(), gridSize.x, gridSize.y, 10);
    defer grid.deinit(allocator);
    var gameState: game.GameState = .ongoing;

    rl.initWindow(screenSizePx.x, screenSizePx.y, "Mine sweeper");
    rl.setTargetFPS(60);
    const font = try rl.getFontDefault();
    while (!rl.windowShouldClose()) {
        // Draw
        rl.beginDrawing();
        rl.clearBackground(rl.Color.blue);
        try drawGrid(font, &grid, screenToGrid.cellSize);
        drawGameState(screenSizePx, gameState, font);
        rl.endDrawing();

        // Handle input
        if (gameState != .ongoing) {
            if (rl.isKeyPressed(.enter)) {
                // Initialize the new grid before freeing the old one, so we can swap it
                // atomically (and hence prevent a double free if initialization fails).
                const newGrid = try game.Grid.init(allocator, rng.random(), gridSize.x, gridSize.y, 10);
                grid.deinit(allocator);
                grid = newGrid;
                gameState = .ongoing;
            }

            continue;
        }

        if (rl.isMouseButtonPressed(.left)) {
            const screenPos = rl.getMousePosition();
            const gridPos = screenToGrid.mapCoords(screenPos);
            gameState = grid.revealCell(gridPos.x, gridPos.y) catch {
                std.debug.print("impossible", .{});
                continue;
            };
        } else if (rl.isMouseButtonPressed(.right)) {
            const screenPos = rl.getMousePosition();
            const gridPos = screenToGrid.mapCoords(screenPos);
            grid.markCell(gridPos.x, gridPos.y) catch {
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
            const cellPos = cellSize.multiply(.init(@floatFromInt(x), @floatFromInt(y)));

            const view = try grid.cellView(x, y);
            const color: rl.Color = switch (view) {
                .hidden => |c| if (c.marked) .orange else .light_gray,
                .mine => .red,
                // No surrounding mines = display the background color (i.e., we don't draw anything on top)
                .clear => |c| if (c.surroundingMines > 0) .light_gray else continue,
            };
            rl.drawRectangleV(cellPos.addValue(cellBorder), paddedCellSize, color);

            if (view == .clear) {
                const s = intToStr[view.clear.surroundingMines];
                const textSize = rl.measureTextEx(font, s, fontSize, fontSpacing);
                const textPos = cellPos.add(centerBox(cellSize, textSize));
                rl.drawTextEx(font, s, textPos, fontSize, fontSpacing, .black);
            }
        }
    }
}

fn drawGameState(screenSize: Vector2Usize, state: game.GameState, font: rl.Font) void {
    const fontSize = 50;
    const fontSpacing = 10;

    const msg: [:0]const u8 = switch (state) {
        .won => "You won!",
        .lost => "You lost!",
        .ongoing => return,
    };

    const hint = "Press Enter to restart";
    const hintFontSize = 20;
    const hintFontSpacing = 2;
    const lineGap = 10;

    const textSize = rl.measureTextEx(font, msg, fontSize, fontSpacing);
    const hintSize = rl.measureTextEx(font, hint, hintFontSize, hintFontSpacing);
    const contentSize: rl.Vector2 = .init(@max(textSize.x, hintSize.x), textSize.y + lineGap + hintSize.y);
    const boxSize = contentSize.scale(1.2);

    // Overlay
    rl.drawRectangleV(.init(0, 0), screenSize.toVector2(), rl.Color.black.fade(0.5));

    // The actual text, boxed for better readability
    const boxPos = centerBox(screenSize.toVector2(), boxSize);
    rl.drawRectangleV(boxPos, boxSize, rl.Color.light_gray);

    // Both lines are horizontally centered within the content area, the hint below the main text
    const contentPos = centerBox(screenSize.toVector2(), contentSize);
    const textPos = contentPos.add(.init((contentSize.x - textSize.x) / 2, 0));
    const hintPos = contentPos.add(.init((contentSize.x - hintSize.x) / 2, textSize.y + lineGap));
    rl.drawTextEx(font, msg, textPos, fontSize, fontSpacing, .black);
    rl.drawTextEx(font, hint, hintPos, hintFontSize, hintFontSpacing, .dark_gray);
}

// Returns the position that centers `boxSize` within `containerSize`
//
// When the box doesn't fit (horizontally and/or vertically), the offending axes get clamped to 0
fn centerBox(containerSize: rl.Vector2, boxSize: rl.Vector2) rl.Vector2 {
    return containerSize.subtract(boxSize).scale(0.5).max(.zero());
}
