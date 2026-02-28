const std = @import("std");
const c = @import("c");

const WIDTH = 800;
const HEIGHT = 600;

const Color = enum(u32) {
    white = 0x00FFFFFF,
    blue = 0x000000FF,
    red = 0x00FF0000,
    green = 0x0000FF00,
    yellow = 0x00FFFF00,
};

const Point = struct {
    x: i32,
    y: i32,
};

const JustDraw = struct {
    color: Color,
    buffer: [WIDTH * HEIGHT]u32 = undefined,
    drawing: bool = false,
    last_pos: ?Point = null,

    fn init() JustDraw {
        return .{ .color = .white };
    }

    // Set a single pixel (with bounds checking)
    fn setPixel(self: *JustDraw, x: i32, y: i32) void {
        if (x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT) return;
        self.buffer[@intCast(y * WIDTH + x)] = @intFromEnum(self.color);
    }

    // Draw a filled rectangle
    fn drawRect(self: *JustDraw, x: i32, y: i32, w: i32, h: i32) void {
        var py = y;
        while (py < y + h) : (py += 1) {
            var px = x;
            while (px < x + w) : (px += 1) {
                self.setPixel(px, py);
            }
        }
    }

    // Draw a line using Bresenham's algorithm
    fn drawLine(self: *JustDraw, x0: i32, y0: i32, x1: i32, y1: i32) void {
        var x = x0;
        var y = y0;

        const dx: i32 = @intCast(@abs(x1 - x0));
        const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx + dy;

        while (true) {
            self.setPixel(x, y);
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
};

pub fn main() void {
    // Create window
    const window = c.mfb_open("draw", WIDTH, HEIGHT);
    if (window == null) return;
    defer c.mfb_close(window);

    var jd = JustDraw.init();

    c.mfb_set_user_data(window, &jd);

    // Clear to dark gray
    for (&jd.buffer) |*pixel| {
        pixel.* = 0x1E1E1E;
    }
    c.mfb_set_keyboard_callback(window, keyboard_callback);
    c.mfb_set_mouse_move_callback(window, mouse_move_callback);
    c.mfb_set_mouse_button_callback(window, mouse_button_callback);

    // Main loop
    while (c.mfb_wait_sync(window)) {
        const state = c.mfb_update(window, &jd.buffer);

        if (state != c.STATE_OK) break;
    }
}

fn keyboard_callback(window: ?*c.mfb_window, key: c.mfb_key, _: c.mfb_key_mod, is_pressed: bool) callconv(.c) void {
    if (!is_pressed) return;

    const pointer = c.mfb_get_user_data(window) orelse return;
    var jd: *JustDraw = @ptrCast(@alignCast(pointer));

    switch (key) {
        '1' => jd.color = .red,
        '2' => jd.color = .green,
        '3' => jd.color = .blue,
        '4' => jd.color = .yellow,
        '0' => jd.color = .white,
        else => {},
    }
}

fn mouse_move_callback(window: ?*c.mfb_window, x: i32, y: i32) callconv(.c) void {
    const pointer = c.mfb_get_user_data(window) orelse return;
    var jd: *JustDraw = @ptrCast(@alignCast(pointer));

    if (!jd.drawing) return;

    jd.last_pos = .{ .x = x, .y = y };
    jd.setPixel(x, y);
}

fn mouse_button_callback(window: ?*c.mfb_window, button: c.mfb_mouse_button, _: c.mfb_key_mod, is_pressed: bool) callconv(.c) void {
    const pointer = c.mfb_get_user_data(window) orelse return;
    var jd: *JustDraw = @ptrCast(@alignCast(pointer));

    switch (button) {
        c.MOUSE_LEFT => jd.drawing = is_pressed,
        else => {},
    }
}
