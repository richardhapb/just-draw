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
    gray = 0x161616,
};

const Mode = enum {
    normal,
    square,
    line,
};

const Point = struct {
    x: i32,
    y: i32,
};

const JustDraw = struct {
    allocator: std.mem.Allocator,
    win_width: u32 = @intCast(WIDTH),
    win_height: u32 = @intCast(HEIGHT),
    color: Color,
    drawing: bool = false,
    deleting: bool = false,
    last_pos: ?Point = null,
    size: usize = 5, // diameter
    background_color: Color = .gray,
    mode: Mode = .normal,
    shape_init: ?Point = null,
    dirty: bool = true,
    prev_pos: ?Point = null,

    buffer: []u32 = undefined,
    overlay_buffer: []u32 = undefined,
    display: []u32 = undefined,

    fn init(allocator: std.mem.Allocator) !JustDraw {
        return .{
            .color = .white,
            .display = try allocator.alloc(u32, WIDTH * HEIGHT),
            .buffer = try allocator.alloc(u32, WIDTH * HEIGHT),
            .overlay_buffer = try allocator.alloc(u32, WIDTH * HEIGHT),
            .allocator = allocator,
        };
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

        // If deleting, override the color
        const color = if (self.deleting) self.background_color else self.color;
        const buffer = if (self.mode == .normal) self.buffer else self.overlay_buffer;
        while (x <= end) : (x += 1) {
            buffer[@intCast(y * WIDTH + x)] = @intFromEnum(color);
        }
        self.dirty = true;
    }

    // Draw a filled rectangle
    fn draw_rect(self: *JustDraw, x: i32, y: i32, w: i32, h: i32) void {
        if (w < 0 or h < 0) return;

        var py = y;
        var px = x;

        while (px < x + w) : (px += 1) {
            self.set_point(px, py);
            self.set_point(px, py + h);
        }
        while (py < y + h) : (py += 1) {
            self.set_point(px - w, py);
            self.set_point(px, py);
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
        for (self.buffer) |*pixel| {
            pixel.* = @intFromEnum(self.background_color);
        }
        self.dirty = true;
    }

    fn to_canvas(jd: *JustDraw, x: i32, y: i32) Point {
        // Compute best-fit viewport manually
        const win_w: i32 = @intCast(jd.win_width);
        const win_h: i32 = @intCast(jd.win_height);
        const scale_x = @as(f32, @floatFromInt(win_w)) / WIDTH;
        const scale_y = @as(f32, @floatFromInt(win_h)) / HEIGHT;
        const scale = @min(scale_x, scale_y);

        const vp_w = @as(i32, @intFromFloat(@as(f32, WIDTH) * scale));
        const vp_h = @as(i32, @intFromFloat(@as(f32, HEIGHT) * scale));
        const offset_x = @divTrunc(win_w - vp_w, 2);
        const offset_y = @divTrunc(win_h - vp_h, 2);

        return .{
            .x = @intFromFloat((@as(f32, @floatFromInt(x - offset_x)) / scale)),
            .y = @intFromFloat((@as(f32, @floatFromInt(y - offset_y)) / scale)),
        };
    }

    fn update_display(self: *JustDraw) void {
        @memcpy(self.display, self.buffer);
    }

    fn update_overlay(self: *JustDraw) void {
        @memcpy(self.overlay_buffer, self.buffer);
    }

    fn commit_overlay(self: *JustDraw) void {
        @memcpy(self.buffer, self.overlay_buffer);
        self.dirty = true;
    }
};

pub fn main() !void {
    const window = c.mfb_open_ex("JUST DRAW", WIDTH, HEIGHT, c.WF_RESIZABLE);
    if (window == null) return;
    defer c.mfb_close(window);

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpalloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpalloc);
    const allocator = arena.allocator();
    defer _ = arena.deinit();

    const jd = try allocator.create(JustDraw);
    defer allocator.destroy(jd);
    jd.* = try JustDraw.init(allocator);

    c.mfb_set_user_data(window, jd);

    jd.redraw_canvas();
    c.mfb_set_keyboard_callback(window, keyboard_callback);
    c.mfb_set_mouse_move_callback(window, mouse_move_callback);
    c.mfb_set_mouse_button_callback(window, mouse_button_callback);
    c.mfb_set_resize_callback(window, resize_callback);

    // Initial render
    _ = c.mfb_update(window, jd.display.ptr);

    // Event-driven main loop
    while (true) {
        // Block until event arrives - 0% CPU when idle
        if (c.mfb_wait_events(window) != c.STATE_OK) break;

        // Check if cursor moved
        const cursor_moved = if (jd.last_pos) |pos| blk: {
            if (jd.prev_pos) |prev| {
                break :blk pos.x != prev.x or pos.y != prev.y;
            }
            break :blk true;
        } else false;

        const needs_update = jd.dirty or cursor_moved;

        // Only redraw if something changed
        if (needs_update) {
            if (jd.last_pos) |pos| {
                jd.update_display();
                draw_cursor(jd.display, pos.x, pos.y, jd.size, @intFromEnum(jd.color));
                jd.prev_pos = pos;

                if (jd.shape_init) |init| {
                    jd.update_overlay();
                    switch (jd.mode) {
                        .square => {
                            const init_x = if (init.x < pos.x) init.x else pos.x;
                            const init_y = if (init.y < pos.y) init.y else pos.y;

                            const width: i32 = @intCast(@abs(pos.x - init.x));
                            const height: i32 = @intCast(@abs(pos.y - init.y));

                            jd.draw_rect(init_x, init_y, width, height);
                        },
                        .line => jd.draw_line(init.x, init.y, pos.x, pos.y),
                        else => {},
                    }
                    jd.dirty = false;
                    if (c.mfb_update(window, jd.overlay_buffer[0..].ptr) != c.STATE_OK) break;
                    continue;
                }
            }
            jd.dirty = false;
            if (c.mfb_update(window, jd.display.ptr) != c.STATE_OK) break;
        }
    }
}

fn draw_cursor(buffer: []u32, cx: i32, cy: i32, size: usize, color: u32) void {
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

fn put_pixel(buffer: []u32, x: i32, y: i32, color: u32) void {
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
        else => return,
    }

    // Reload the cursor
    jd.dirty = true;
}

fn mouse_move_callback(window: ?*c.mfb_window, x: i32, y: i32) callconv(.c) void {
    const pointer = c.mfb_get_user_data(window) orelse return;
    var jd: *JustDraw = @ptrCast(@alignCast(pointer));

    const pos = jd.to_canvas(x, y);

    if (!jd.drawing and !jd.deleting) {
        // Just update the position to handle it on next click
        jd.last_pos = pos;
        return;
    }

    if (jd.last_pos) |last_pos| {
        jd.draw_line(last_pos.x, last_pos.y, pos.x, pos.y);
    }

    jd.last_pos = pos;

    jd.set_point(pos.x, pos.y);
}

fn mouse_button_callback(window: ?*c.mfb_window, button: c.mfb_mouse_button, mod: c.mfb_key_mod, is_pressed: bool) callconv(.c) void {
    const pointer = c.mfb_get_user_data(window) orelse return;
    var jd: *JustDraw = @ptrCast(@alignCast(pointer));

    switch (button) {
        c.MOUSE_LEFT => {
            switch (mod) {
                // With shift draw a square
                c.KB_MOD_SUPER => {
                    if (is_pressed) {
                        jd.mode = .square;
                        jd.shape_init = jd.last_pos;
                    } else {
                        jd.commit_overlay();
                        jd.mode = .normal;
                        jd.shape_init = null;
                    }
                },
                c.KB_MOD_SHIFT => {
                    if (is_pressed) {
                        jd.mode = .line;
                        jd.shape_init = jd.last_pos;
                    } else {
                        jd.commit_overlay();
                        jd.mode = .normal;
                        jd.shape_init = null;
                    }
                },
                else => {},
            }

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

fn resize_callback(window: ?*c.mfb_window, width: i32, height: i32) callconv(.c) void {
    const pointer = c.mfb_get_user_data(window) orelse return;
    const jd: *JustDraw = @ptrCast(@alignCast(pointer));
    jd.win_width = @intCast(width);
    jd.win_height = @intCast(height);
}
