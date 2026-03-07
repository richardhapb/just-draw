const std = @import("std");
const c = @import("c");
const hidder = @import("hidder");

const WIDTH = 1000;
const HEIGHT = 800;
const MAX_POINT_SIZE = 50;
const MIN_POINT_SIZE = 2; // Cannot be smaller than 2, otherwise it will crash
const MAX_PRESSURE: u16 = 8191;

const Color = enum(u32) {
    white = 0x00FFFFFF,
    blue = 0x000000FF,
    red = 0x00FF0000,
    green = 0x0000FF00,
    yellow = 0x00FFFF00,
    black = 0x00000000,
};

const PenEvent = enum {
    tip,
    button1,
    button2,
    pressure,
    x,
    y,
};

// HID Usage Pages
const UsagePage = enum(u16) {
    generic_desktop = 0x01,
    digitizer = 0x0D,
};

// HID Usages for Generic Desktop page
const GenericDesktopUsage = enum(u16) {
    x = 0x30,
    y = 0x31,
};

// HID Usages for Digitizer page
const DigitizerUsage = enum(u16) {
    tip_pressure = 0x30,
    tip_switch = 0x42,
    barrel_switch = 0x44,
    eraser = 0x45,
    secondary_barrel = 0x5A,

    fn fromInt(usage: u32) !DigitizerUsage {
        for (@as([5]u32, .{ 0x30, 0x42, 0x44, 0x45, 0x5A })) |num| {
            if (usage == num) {
                return @as(DigitizerUsage, @enumFromInt(usage));
            }
        }

        return error.InvalidEnum;
    }
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
    base_size: usize = 2, // base diameter set by keyboard
    size: usize = 2, // actual diameter (base + pressure)
    background_color: Color = .black,
    mode: Mode = .normal,
    shape_init: ?Point = null,
    dirty: bool = true,
    prev_pos: ?Point = null,

    is_pen_connected: bool = false,
    eraser_mode: bool = false,
    last_button1_frame: u64 = 0, // For double-tap detection (frame counter)
    button1_held: bool = false,
    button2_held: bool = false,
    feedback_frames: u32 = 0, // Frames remaining to show feedback
    feedback_text: enum { none, eraser_on, eraser_off } = .none,

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

    fn setPoint(self: *JustDraw, cx: i32, cy: i32) void {
        const r: i32 = @intCast(self.size / 2);
        var x: i32 = 0;
        var y: i32 = r;
        var d: i32 = 3 - 2 * r;

        while (x <= y) : (x += 1) {
            self.hLine(cx - x, cx + x, cy + y);
            self.hLine(cx - x, cx + x, cy - y);
            self.hLine(cx - y, cx + y, cy + x);
            self.hLine(cx - y, cx + y, cy - x);

            if (d < 0) {
                d += 4 * x + 6;
            } else {
                d += 4 * (x - y) + 10;
                y -= 1;
            }
        }
    }

    fn hLine(self: *JustDraw, x0: i32, x1: i32, y: i32) void {
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
    fn drawRect(self: *JustDraw, x: i32, y: i32, w: i32, h: i32) void {
        if (w < 0 or h < 0) return;

        var py = y;
        var px = x;

        while (px < x + w) : (px += 1) {
            self.setPoint(px, py);
            self.setPoint(px, py + h);
        }
        while (py < y + h) : (py += 1) {
            self.setPoint(px - w, py);
            self.setPoint(px, py);
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
            self.setPoint(x, y);
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

    fn redrawCanvas(self: *JustDraw) void {
        // Clear to background color
        for (self.buffer) |*pixel| {
            pixel.* = @intFromEnum(self.background_color);
        }
        self.dirty = true;
    }

    fn toCanvas(jd: *JustDraw, x: i32, y: i32) Point {
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

    fn updateDisplay(self: *JustDraw) void {
        @memcpy(self.display, self.buffer);
    }

    fn updateOverlay(self: *JustDraw) void {
        @memcpy(self.overlay_buffer, self.buffer);
    }

    fn commitOverlay(self: *JustDraw) void {
        @memcpy(self.buffer, self.overlay_buffer);
        self.dirty = true;
    }

    fn mapPressure(self: *JustDraw, pressure: i32) void {
        const ratio: f32 = @as(f32, @floatFromInt(pressure)) / MAX_PRESSURE;
        const max_growth: f32 = 8.0;
        // Set size based on base_size + pressure contribution (not +=)
        self.size = self.base_size + @as(usize, @intFromFloat(max_growth * ratio));
    }

    fn drawFeedback(self: *JustDraw) void {
        if (self.feedback_frames == 0) return;
        self.feedback_frames -= 1;

        const indicator_x: i32 = 30;
        const indicator_y: i32 = 30;
        const radius: i32 = 15;

        const color: u32 = switch (self.feedback_text) {
            .eraser_on => @intFromEnum(Color.red),
            .eraser_off => @intFromEnum(Color.white),
            .none => return,
        };

        // Draw indicator circle on display buffer
        var x: i32 = 0;
        var y: i32 = radius;
        var d: i32 = 3 - 2 * radius;

        while (x <= y) : (x += 1) {
            if (self.feedback_text == .eraser_on) {
                // Filled circle for eraser ON
                drawHLineOnBuffer(self.display, indicator_x - x, indicator_x + x, indicator_y + y, color);
                drawHLineOnBuffer(self.display, indicator_x - x, indicator_x + x, indicator_y - y, color);
                drawHLineOnBuffer(self.display, indicator_x - y, indicator_x + y, indicator_y + x, color);
                drawHLineOnBuffer(self.display, indicator_x - y, indicator_x + y, indicator_y - x, color);
            } else {
                // Hollow circle for eraser OFF
                putPixel(self.display, indicator_x + x, indicator_y + y, color);
                putPixel(self.display, indicator_x - x, indicator_y + y, color);
                putPixel(self.display, indicator_x + x, indicator_y - y, color);
                putPixel(self.display, indicator_x - x, indicator_y - y, color);
                putPixel(self.display, indicator_x + y, indicator_y + x, color);
                putPixel(self.display, indicator_x - y, indicator_y + x, color);
                putPixel(self.display, indicator_x + y, indicator_y - x, color);
                putPixel(self.display, indicator_x - y, indicator_y - x, color);
            }

            if (d < 0) {
                d += 4 * x + 6;
            } else {
                d += 4 * (x - y) + 10;
                y -= 1;
            }
        }
    }
};

fn drawHLineOnBuffer(buffer: []u32, x0: i32, x1: i32, y: i32, color: u32) void {
    if (y < 0 or y >= HEIGHT) return;
    const start = @max(x0, 0);
    const end = @min(x1, WIDTH - 1);
    var x = start;
    while (x <= end) : (x += 1) {
        buffer[@intCast(y * WIDTH + x)] = color;
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const gpalloc = gpa.allocator();

    var arena = std.heap.ArenaAllocator.init(gpalloc);
    const allocator = arena.allocator();
    defer _ = arena.deinit();

    const jd = try allocator.create(JustDraw);
    defer allocator.destroy(jd);
    jd.* = try JustDraw.init(allocator);

    try hidder.initHidApi();
    const devices_list = try hidder.discoverDevices(allocator);

    var watcher: ?hidder.ReportsWatcher = null;
    var queue = hidder.EventQueue(hidder.FieldEvent).init(allocator);
    defer queue.deinit();
    var events_map = std.AutoHashMap(*const hidder.FieldDescriptor, PenEvent).init(allocator);
    defer events_map.deinit();

    // Tablet coordinate ranges (will be set from HID descriptors)
    var tablet_x_max: i32 = 1;
    var tablet_y_max: i32 = 1;

    if (hidder.getXPPenDevice(devices_list) catch null) |xppen| {
        // Copy device to heap so it outlives this block
        const device_ptr = try allocator.create(hidder.DeviceInfo);
        device_ptr.* = xppen;

        const report = try hidder.getDescriptors(allocator, device_ptr);

        // Debug: print all field descriptors
        std.debug.print("=== Field Descriptors ({}) ===\n", .{report.field_descriptors.len});
        for (report.field_descriptors, 0..) |desc, idx| {
            std.debug.print("[{d:2}] page=0x{X:0>2} usage=0x{X:0>2} bits={} range={}..{}\n", .{
                idx,
                desc.usage_page,
                desc.usage,
                desc.bit_size,
                desc.logical_min,
                desc.logical_max,
            });
        }
        std.debug.print("==============================\n", .{});

        // Find field descriptors by usage page and usage
        var subs_list: std.ArrayListUnmanaged(*const hidder.FieldDescriptor) = .empty;

        for (report.field_descriptors, 0..) |*desc, i| {
            const ptr = &report.field_descriptors[i];

            if (desc.usage_page == @intFromEnum(UsagePage.digitizer)) {
                switch (DigitizerUsage.fromInt(desc.usage) catch continue) {
                    DigitizerUsage.tip_switch => {
                        std.debug.print("Found: Tip Switch at index {}\n", .{i});
                        try subs_list.append(allocator, ptr);
                        try events_map.put(ptr, .tip);
                    },
                    DigitizerUsage.barrel_switch => {
                        std.debug.print("Found: Barrel Switch at index {}\n", .{i});
                        try subs_list.append(allocator, ptr);
                        try events_map.put(ptr, .button1);
                    },
                    DigitizerUsage.secondary_barrel, DigitizerUsage.eraser => {
                        std.debug.print("Found: Button 2 (eraser/secondary) at index {}\n", .{i});
                        try subs_list.append(allocator, ptr);
                        try events_map.put(ptr, .button2);
                    },
                    DigitizerUsage.tip_pressure => {
                        std.debug.print("Found: Pressure at index {}\n", .{i});
                        try subs_list.append(allocator, ptr);
                        try events_map.put(ptr, .pressure);
                    },
                }
            } else if (desc.usage_page == @intFromEnum(UsagePage.generic_desktop)) {
                if (desc.usage == @intFromEnum(GenericDesktopUsage.x)) {
                    std.debug.print("Found: X at index {} (max={})\n", .{ i, desc.logical_max });
                    try subs_list.append(allocator, ptr);
                    try events_map.put(ptr, .x);
                    tablet_x_max = desc.logical_max;
                } else if (desc.usage == @intFromEnum(GenericDesktopUsage.y)) {
                    std.debug.print("Found: Y at index {} (max={})\n", .{ i, desc.logical_max });
                    try subs_list.append(allocator, ptr);
                    try events_map.put(ptr, .y);
                    tablet_y_max = desc.logical_max;
                }
            }
        }

        const subs = try subs_list.toOwnedSlice(allocator);

        if (subs.len > 0) {
            watcher = hidder.ReportsWatcher.init(allocator, device_ptr, report, subs, &queue);
            try watcher.?.start();
            jd.is_pen_connected = true;
            std.log.info("XPPen connected: tablet range {}x{}", .{ tablet_x_max, tablet_y_max });
        }
    }

    defer if (watcher) |*w| {
        w.stop();
        w.deinit();
    };

    const window = c.mfb_open_ex("JUST DRAW", WIDTH, HEIGHT, c.WF_RESIZABLE);
    if (window == null) return;
    defer c.mfb_close(window);

    c.mfb_show_cursor(window, false);

    c.mfb_set_user_data(window, jd);

    jd.redrawCanvas();
    c.mfb_set_keyboard_callback(window, keyboardCallback);
    c.mfb_set_mouse_move_callback(window, mouseMoveCallback);
    c.mfb_set_mouse_button_callback(window, mouseButtonCallback);
    c.mfb_set_resize_callback(window, resizeCallback);
    c.mfb_set_active_callback(window, activeCallback);

    // Initial render
    _ = c.mfb_update(window, jd.display.ptr);

    // Main loop - use polling when pen is connected, blocking otherwise
    var frame_counter: u64 = 0;
    while (true) {
        frame_counter +%= 1;
        // When pen is connected, we need to poll for HID events
        // Otherwise block until window event arrives (0% CPU when idle)
        const state = if (jd.is_pen_connected)
            c.mfb_update_events(window)
        else
            c.mfb_wait_events(window);

        if (state != c.STATE_OK) break;

        // Check if cursor moved
        const cursor_moved = if (jd.last_pos) |pos| blk: {
            if (jd.prev_pos) |prev| {
                break :blk pos.x != prev.x or pos.y != prev.y;
            }
            break :blk true;
        } else false;

        // Track pen coordinates for this frame
        var pen_x: ?i32 = null;
        var pen_y: ?i32 = null;

        // TODO: Detect when pen is disconnected
        if (jd.is_pen_connected) {
            while (watcher.?.queue.pop()) |event| {
                const event_type = events_map.get(event.descriptor) orelse continue;
                switch (event_type) {
                    .tip => {
                        const pressed = event.new_value == 1;
                        jd.drawing = pressed;

                        if (jd.mode != .normal) {
                            if (!pressed) {
                                // Commit shapes
                                jd.commitOverlay();
                                jd.shape_init = null;
                            } else if (jd.shape_init == null) {
                                // Begin shape
                                jd.shape_init = jd.last_pos;
                            }
                        }

                        // Apply eraser mode when drawing
                        if (jd.drawing and jd.eraser_mode) {
                            jd.deleting = true;
                        } else if (!jd.drawing) {
                            jd.deleting = false;
                        }
                    },
                    .button1 => {
                        const pressed = event.new_value == 1;
                        jd.button1_held = pressed;

                        if (pressed) {
                            const double_tap_threshold: u64 = 300; // ~300ms at 1ms per frame
                            if (frame_counter - jd.last_button1_frame < double_tap_threshold) {
                                // Double tap -> toggle eraser mode
                                jd.eraser_mode = !jd.eraser_mode;
                                jd.feedback_text = if (jd.eraser_mode) .eraser_on else .eraser_off;
                                jd.feedback_frames = 120; // Show for ~120ms
                            }
                            jd.last_button1_frame = frame_counter;
                        }
                    },
                    .button2 => {
                        jd.button2_held = event.new_value == 1;
                    },
                    .pressure => jd.mapPressure(event.new_value),
                    .x => pen_x = event.new_value,
                    .y => pen_y = event.new_value,
                }
                jd.dirty = true;
            }

            // Continuous size adjustment while holding buttons (every 50 frames ~50ms)
            if (frame_counter % 50 == 0) {
                if (jd.button1_held) {
                    jd.base_size = @min(MAX_POINT_SIZE, jd.base_size + 1);
                    jd.size = jd.base_size;
                    jd.dirty = true;
                }
                if (jd.button2_held) {
                    jd.base_size = @max(MIN_POINT_SIZE, jd.base_size -| 1);
                    jd.size = jd.base_size;
                    jd.dirty = true;
                }
            }

            // Update pen position if we got coordinates
            if (pen_x != null or pen_y != null) {
                // Convert tablet coordinates to canvas coordinates
                const x = if (pen_x) |px| @divTrunc(px * WIDTH, tablet_x_max) else if (jd.last_pos) |p| p.x else 0;
                const y = if (pen_y) |py| @divTrunc(py * HEIGHT, tablet_y_max) else if (jd.last_pos) |p| p.y else 0;

                const pos = Point{ .x = x, .y = y };

                if (jd.drawing or jd.deleting) {
                    if (jd.last_pos) |last_pos| {
                        jd.drawLine(last_pos.x, last_pos.y, pos.x, pos.y);
                    }
                    jd.setPoint(pos.x, pos.y);
                }
                jd.last_pos = pos;
            }
        }

        const needs_update = jd.dirty or cursor_moved;

        // Only redraw if something changed (or feedback is active)
        const needs_feedback = jd.feedback_frames > 0;
        if (needs_update or needs_feedback) {
            if (jd.last_pos) |pos| {
                jd.updateDisplay();
                jd.drawFeedback();
                drawCursor(jd.display, pos.x, pos.y, jd.size, @intFromEnum(jd.color));
                jd.prev_pos = pos;

                if (jd.shape_init) |init| {
                    jd.updateOverlay();
                    switch (jd.mode) {
                        .square => {
                            const init_x = if (init.x < pos.x) init.x else pos.x;
                            const init_y = if (init.y < pos.y) init.y else pos.y;

                            const width: i32 = @intCast(@abs(pos.x - init.x));
                            const height: i32 = @intCast(@abs(pos.y - init.y));

                            jd.drawRect(init_x, init_y, width, height);
                        },
                        .line => jd.drawLine(init.x, init.y, pos.x, pos.y),
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

        // Small sleep when polling to avoid 100% CPU
        if (jd.is_pen_connected) {
            const ts = c.struct_timespec{ .tv_sec = 0, .tv_nsec = 1_000_000 }; // 1ms
            _ = c.nanosleep(&ts, null);
        }
    }
}

fn drawCursor(buffer: []u32, cx: i32, cy: i32, size: usize, color: u32) void {
    const r: i32 = @intCast(size / 2);
    var x: i32 = 0;
    var y: i32 = r;
    var d: i32 = 3 - 2 * r;

    while (x <= y) : (x += 1) {
        putPixel(buffer, cx + x, cy + y, color);
        putPixel(buffer, cx - x, cy + y, color);
        putPixel(buffer, cx + x, cy - y, color);
        putPixel(buffer, cx - x, cy - y, color);
        putPixel(buffer, cx + y, cy + x, color);
        putPixel(buffer, cx - y, cy + x, color);
        putPixel(buffer, cx + y, cy - x, color);
        putPixel(buffer, cx - y, cy - x, color);

        if (d < 0) {
            d += 4 * x + 6;
        } else {
            d += 4 * (x - y) + 10;
            y -= 1;
        }
    }
}

fn putPixel(buffer: []u32, x: i32, y: i32, color: u32) void {
    if (x < 0 or y < 0 or x >= WIDTH or y >= HEIGHT) return;
    buffer[@intCast(y * WIDTH + x)] = color;
}

fn keyboardCallback(window: ?*c.mfb_window, key: c.mfb_key, mod: c.mfb_key_mod, is_pressed: bool) callconv(.c) void {
    const pointer = c.mfb_get_user_data(window) orelse return;
    var jd: *JustDraw = @ptrCast(@alignCast(pointer));

    switch (mod) {
        c.KB_MOD_SHIFT => jd.mode = .line,
        c.KB_MOD_SUPER => jd.mode = .square,
        else => jd.mode = .normal,
    }

    if (!is_pressed) return;

    // These requires handle is_pressed release
    switch (key) {
        '1' => jd.color = .red,
        '2' => jd.color = .green,
        '3' => jd.color = .blue,
        '4' => jd.color = .yellow,
        '0' => jd.color = .white,
        '=' => { // Same position as `+`
            jd.base_size = @min(MAX_POINT_SIZE, jd.base_size + 2);
            jd.size = jd.base_size;
        },
        '-' => {
            jd.base_size = @max(MIN_POINT_SIZE, jd.base_size - 2);
            jd.size = jd.base_size;
        },
        c.KB_KEY_BACKSPACE => jd.redrawCanvas(),
        else => return,
    }

    // Reload the cursor
    jd.dirty = true;
}

fn mouseMoveCallback(window: ?*c.mfb_window, x: i32, y: i32) callconv(.c) void {
    const pointer = c.mfb_get_user_data(window) orelse return;
    var jd: *JustDraw = @ptrCast(@alignCast(pointer));

    const pos = jd.toCanvas(x, y);

    if (!jd.drawing and !jd.deleting) {
        // Just update the position to handle it on next click
        jd.last_pos = pos;
        return;
    }

    if (jd.last_pos) |last_pos| {
        jd.drawLine(last_pos.x, last_pos.y, pos.x, pos.y);
    }

    jd.last_pos = pos;

    jd.setPoint(pos.x, pos.y);
}

fn mouseButtonCallback(window: ?*c.mfb_window, button: c.mfb_mouse_button, _: c.mfb_key_mod, is_pressed: bool) callconv(.c) void {
    const pointer = c.mfb_get_user_data(window) orelse return;
    var jd: *JustDraw = @ptrCast(@alignCast(pointer));

    switch (button) {
        c.MOUSE_LEFT => {
            jd.drawing = is_pressed;
            if (is_pressed) {
                if (jd.mode != .normal) {
                    jd.shape_init = jd.last_pos;
                } else if (jd.last_pos) |last_pos| {
                    // First pixel, this handles the `click` alone event without movement
                    jd.setPoint(last_pos.x, last_pos.y);
                }
                jd.last_pos = null; // Restart state to avoid join lines when click again
            } else {
                if (jd.mode != .normal) {
                    jd.commitOverlay();
                    jd.shape_init = null;
                }
            }
        },
        c.MOUSE_RIGHT => {
            jd.deleting = is_pressed;

            if (is_pressed) {
                if (jd.last_pos) |last_pos| {
                    // First pixel, this handles the `click` alone event without movement
                    jd.setPoint(last_pos.x, last_pos.y);
                }
            } else jd.last_pos = null; // Restart state to avoid join lines when click again
        },
        else => {},
    }
}

fn resizeCallback(window: ?*c.mfb_window, width: i32, height: i32) callconv(.c) void {
    const pointer = c.mfb_get_user_data(window) orelse return;
    const jd: *JustDraw = @ptrCast(@alignCast(pointer));
    jd.win_width = @intCast(width);
    jd.win_height = @intCast(height);
}

fn activeCallback(window: ?*c.mfb_window, is_active: bool) callconv(.c) void {
    const pointer = c.mfb_get_user_data(window) orelse return;
    const jd: *JustDraw = @ptrCast(@alignCast(pointer));

    // update when it is focused
    jd.dirty = is_active;
}
