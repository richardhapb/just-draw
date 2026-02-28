const c = @import("c");

const WIDTH = 800;
const HEIGHT = 600;

// Pixel buffer - this is where you draw!
// Format: 0xAARRGGBB (or just 0x00RRGGBB)
var buffer: [WIDTH * HEIGHT]u32 = undefined;

pub fn main() void {
    // Create window
    const window = c.mfb_open("draw", WIDTH, HEIGHT);
    if (window == null) return;
    defer c.mfb_close(window);

    // Clear to dark gray
    for (&buffer) |*pixel| {
        pixel.* = 0x1E1E1E;
    }

    // Draw a red rectangle
    drawRect(100, 100, 200, 150, 0xFF0000);

    // Draw a green rectangle
    drawRect(350, 200, 150, 200, 0x00FF00);

    // Draw a blue rectangle
    drawRect(550, 100, 180, 180, 0x0000FF);

    // Draw a diagonal line
    drawLine(50, 50, 750, 550, 0xFFFF00);

    // Main loop
    while (c.mfb_wait_sync(window)) {
        const state = c.mfb_update(window, &buffer);
        if (state != c.STATE_OK) break;
    }
}

// Set a single pixel (with bounds checking)
fn setPixel(x: i32, y: i32, color: u32) void {
    if (x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT) return;
    buffer[@intCast(y * WIDTH + x)] = color;
}

// Draw a filled rectangle
fn drawRect(x: i32, y: i32, w: i32, h: i32, color: u32) void {
    var py = y;
    while (py < y + h) : (py += 1) {
        var px = x;
        while (px < x + w) : (px += 1) {
            setPixel(px, py, color);
        }
    }
}

// Draw a line using Bresenham's algorithm
fn drawLine(x0: i32, y0: i32, x1: i32, y1: i32, color: u32) void {
    var x = x0;
    var y = y0;

    const dx: i32 = @intCast(@abs(x1 - x0));
    const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
    const sx: i32 = if (x0 < x1) 1 else -1;
    const sy: i32 = if (y0 < y1) 1 else -1;
    var err = dx + dy;

    while (true) {
        setPixel(x, y, color);
        if (x == x1 and y == y1) break;
        const e2 = 2 * err;
        if (e2 >= dy) {
            err += dy;
            x += sx;
        }
        if (e2 <= dx) {
            err += dx;
            y += sy;
        }
    }
}
