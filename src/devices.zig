const std = @import("std");
const c = @import("c");

const XP_PEN_VENDOR_ID: u16 = 0x28bd;
const XP_PEN_PRODUCT_ID: u16 = 0x0913;
const STYLUS_INTERFACE: u8 = 1;

pub const DeviceInfo = struct { vendor_id: u16, product_id: u16, path: [:0]const u8, manufacturer: ?[:0]const u8, product: ?[:0]const u8, interface: i32 };

fn isNullCPtr(ptr: anytype) bool {
    return @intFromPtr(ptr) == 0;
}

fn wcharLen(ptr: [*c]const c.wchar_t) usize {
    var len: usize = 0;
    while (ptr[len] != 0) : (len += 1) {}
    return len;
}

fn wcharToUtf8AllocZ(allocator: std.mem.Allocator, wide: [*c]const c.wchar_t) !?[:0]u8 {
    if (isNullCPtr(wide)) return null;

    const ptr = wide;
    const len = wcharLen(ptr);

    return switch (@sizeOf(c.wchar_t)) {
        2 => {
            const wide16 = @as([*]const u16, @ptrCast(ptr))[0..len];
            return try std.unicode.utf16LeToUtf8AllocZ(allocator, wide16);
        },
        4 => {
            var utf8 = try std.ArrayList(u8).initCapacity(allocator, len * 4 + 1);
            errdefer utf8.deinit(allocator);

            const wide32 = @as([*]const c.wchar_t, @ptrCast(ptr))[0..len];
            for (wide32) |code_unit| {
                const raw: u32 = @bitCast(code_unit);
                const codepoint: u21 = if (raw <= 0x10FFFF) blk: {
                    const cp: u21 = @intCast(raw);
                    break :blk if (std.unicode.utf8ValidCodepoint(cp)) cp else std.unicode.replacement_character;
                } else std.unicode.replacement_character;

                var buf: [4]u8 = undefined;
                const n = try std.unicode.utf8Encode(codepoint, &buf);
                try utf8.appendSlice(allocator, buf[0..n]);
            }

            return try utf8.toOwnedSliceSentinel(allocator, 0);
        },
        else => return error.UnsupportedWcharWidth,
    };
}

pub fn initHidApi() !void {
    if (c.hid_init() == 0) return;
    return error.HidApiInitFailed;
}

pub fn discoverDevices(allocator: std.mem.Allocator) ![]DeviceInfo {
    const devices = c.hid_enumerate(0, 0) orelse return error.HidEnumerateFailed;
    defer c.hid_free_enumeration(devices);

    var list = try std.ArrayList(DeviceInfo).initCapacity(allocator, 100);
    errdefer list.deinit(allocator);

    var device: ?*c.struct_hid_device_info = devices;
    while (device) |dev| : (device = dev.next) {
        if (isNullCPtr(dev.path)) return error.HidDevicePathMissing;

        try list.append(allocator, .{
            .vendor_id = dev.vendor_id,
            .product_id = dev.product_id,
            .path = try allocator.dupeZ(u8, std.mem.span(dev.path)),
            .manufacturer = try wcharToUtf8AllocZ(allocator, dev.manufacturer_string),
            .product = try wcharToUtf8AllocZ(allocator, dev.product_string),
            .interface = dev.interface_number,
        });
    }

    std.log.info("found {} HID device{s}", .{
        list.items.len,
        if (list.items.len == 1) "" else "s",
    });

    return try list.toOwnedSlice(allocator);
}

pub fn getXPPenDevice(devices: []DeviceInfo) !?DeviceInfo {
    for (devices) |device| {
        if (device.vendor_id == XP_PEN_VENDOR_ID and
            device.product_id == XP_PEN_PRODUCT_ID and
            device.interface == STYLUS_INTERFACE)
        {
            return device;
        }
    }
    return null;
}

const InterruptEndpoint = struct {
    interface: u8,
    setting: u8,
    address: u8,
    packet_size: usize,
};

pub fn collectInterruptEndpoints(allocator: std.mem.Allocator, device: *const DeviceInfo) ![]InterruptEndpoint {
    var buf: [64]u8 = undefined;

    std.debug.print("opening path: {s}\n", .{device.path});
    const handle = c.hid_open_path(device.path) orelse return error.HidOpenFailed;
    defer _ = c.hid_close(handle);

    const n = c.hid_read(handle, &buf, buf.len);

    if (n < 0) return error.HidReadFailed;

    std.debug.print("Read {} interrupts, {any}\n", .{ n, buf[0..@intCast(n)] });

    var interrupts = try std.ArrayList(InterruptEndpoint).initCapacity(allocator, @intCast(n));
    defer interrupts.deinit(allocator);

    for (buf) |interrupt| {
        std.debug.print("Capturing int: {any}", .{interrupt});
    }

    return try interrupts.toOwnedSlice(allocator);
}
