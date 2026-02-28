const std = @import("std");
const c = @import("c");

const WIDTH = 1000;
const HEIGHT = 800;
const MAX_POINT_SIZE = 50;
const MIN_POINT_SIZE = 2; // Cannot be smaller than 2, otherwise it will crash

const Color = enum(u32) {
    white = 0x00FFFFFF,
    blue = 0x000000FF,
    red = 0x00FF0000,
    green = 0x0000FF00,
    yellow = 0x00FFFF00,
    gray = 0x1E1E1E,
};

const Point = struct {
    x: i32,
    y: i32,
};

const JustDraw = struct {
    color: Color,
    buffer: [WIDTH * HEIGHT]u32 = undefined,
    drawing: bool = false,
    deleting: bool = false,
    last_pos: ?Point = null,
    size: usize = 5, // diameter
    background_color: Color = .gray,

    fn init() JustDraw {
        return .{ .color = .white };
    }

    fn set_point(self: *JustDraw, cx: i32, cy: i32) void {
        const r: i32 = @intCast(self.size / 2);
        var x: i32 = 0;
        var y: i32 = r;
        var d: i32 = 3 - 2 * r;

        while (x <= y) : (x += 1) {
            self.hline(cx - x, cx + x, cy + y);
            self.hline(cx - x, cx + x, cy - y);
            self.hline(cx - y, cx + y, cy + x);
            self.hline(cx - y, cx + y, cy - x);

            if (d < 0) {
                d += 4 * x + 6;
            } else {
                d += 4 * (x - y) + 10;
                y -= 1;
            }
        }
    }

    fn hline(self: *JustDraw, x0: i32, x1: i32, y: i32) void {
        if (y < 0 or y >= HEIGHT) return;
        const start = @max(x0, 0);
        const end = @min(x1, WIDTH - 1);
        var x = start;

        // If deleting override the color
        const color = if (self.deleting) self.background_color else self.color;
        while (x <= end) : (x += 1) {
            self.buffer[@intCast(y * WIDTH + x)] = @intFromEnum(color);
        }
    }

    // Draw a filled rectangle
    fn draw_rect(self: *JustDraw, x: i32, y: i32, w: i32, h: i32) void {
        var py = y;
        while (py < y + h) : (py += 1) {
            var px = x;
            while (px < x + w) : (px += 1) {
                self.set_point(px, py);
            }
        }
    }

    // Draw a line using Bresenham's algorithm
    fn draw_line(self: *JustDraw, x0: i32, y0: i32, x1: i32, y1: i32) void {
        var x = x0;
        var y = y0;

        const dx: i32 = @intCast(@abs(x1 - x0));
        const dy: i32 = -@as(i32, @intCast(@abs(y1 - y0)));
        const sx: i32 = if (x0 < x1) 1 else -1;
        const sy: i32 = if (y0 < y1) 1 else -1;
        var err = dx + dy;

        while (true) {
            self.set_point(x, y);
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

    fn redraw_canvas(self: *JustDraw) void {
        // Clear to background color
        for (&self.buffer) |*pixel| {
            pixel.* = @intFromEnum(self.background_color);
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

    jd.redraw_canvas();
    c.mfb_set_keyboard_callback(window, keyboard_callback);
    c.mfb_set_mouse_move_callback(window, mouse_move_callback);
    c.mfb_set_mouse_button_callback(window, mouse_button_callback);

    // Main loop
    while (c.mfb_wait_sync(window)) {
        // Copy buffer to display buffer
        var display: [WIDTH * HEIGHT]u32 = jd.buffer;

        // Draw cursor on display buffer only
        if (jd.last_pos) |pos| {
            draw_cursor(&display, pos.x, pos.y, jd.size, @intFromEnum(jd.color));
        }

        const state = c.mfb_update(window, &display);

        if (state != c.STATE_OK) break;
    }
}

fn draw_cursor(buffer: *[WIDTH * HEIGHT]u32, cx: i32, cy: i32, size: usize, color: u32) void {
    const r: i32 = @intCast(size / 2);
    var x: i32 = 0;
    var y: i32 = r;
    var d: i32 = 3 - 2 * r;

    while (x <= y) : (x += 1) {
        put_pixel(buffer, cx + x, cy + y, color);
        put_pixel(buffer, cx - x, cy + y, color);
        put_pixel(buffer, cx + x, cy - y, color);
        put_pixel(buffer, cx - x, cy - y, color);
        put_pixel(buffer, cx + y, cy + x, color);
        put_pixel(buffer, cx - y, cy + x, color);
        put_pixel(buffer, cx + y, cy - x, color);
        put_pixel(buffer, cx - y, cy - x, color);

        if (d < 0) {
            d += 4 * x + 6;
        } else {
            d += 4 * (x - y) + 10;
            y -= 1;
        }
    }
}

fn put_pixel(buffer: *[WIDTH * HEIGHT]u32, x: i32, y: i32, color: u32) void {
    if (x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT) return;
    buffer[@intCast(y * WIDTH + x)] = color;
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
        '=' => jd.size = @min(MAX_POINT_SIZE, jd.size + 2), // Same position as `+`
        '-' => jd.size = @max(MIN_POINT_SIZE, jd.size - 2),
        c.KB_KEY_BACKSPACE => jd.redraw_canvas(),
        else => std.debug.print("{}", .{key}),
    }
}

fn mouse_move_callback(window: ?*c.mfb_window, x: i32, y: i32) callconv(.c) void {
    const pointer = c.mfb_get_user_data(window) orelse return;
    var jd: *JustDraw = @ptrCast(@alignCast(pointer));

    if (!jd.drawing and !jd.deleting) {
        // Just update the position to handle it on next click
        jd.last_pos = .{ .x = x, .y = y };
        return;
    }

    if (jd.last_pos) |last_pos| {
        jd.draw_line(last_pos.x, last_pos.y, x, y);
    }

    jd.last_pos = .{ .x = x, .y = y };

    jd.set_point(x, y);
}

fn mouse_button_callback(window: ?*c.mfb_window, button: c.mfb_mouse_button, _: c.mfb_key_mod, is_pressed: bool) callconv(.c) void {
    const pointer = c.mfb_get_user_data(window) orelse return;
    var jd: *JustDraw = @ptrCast(@alignCast(pointer));

    switch (button) {
        c.MOUSE_LEFT => {
            jd.drawing = is_pressed;
            if (is_pressed) {
                if (jd.last_pos) |last_pos| {
                    // First pixel, this handles the `click` alone event without movement
                    jd.set_point(last_pos.x, last_pos.y);
                }
            } else jd.last_pos = null; // Restart state to avoid join lines when click again
        },
        c.MOUSE_RIGHT => {
            jd.deleting = is_pressed;

            if (is_pressed) {
                if (jd.last_pos) |last_pos| {
                    // First pixel, this handles the `click` alone event without movement
                    jd.set_point(last_pos.x, last_pos.y);
                }
            } else jd.last_pos = null; // Restart state to avoid join lines when click again
        },
        else => {},
    }
}
