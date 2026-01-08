//! Gamepad Plugin
//!
//! Game controller input support.
//!
//! Linux: Uses evdev (linux/input.h)
//! macOS: Uses Game Controller framework (TODO)
//! Windows: Uses XInput (TODO)

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;
const Allocator = std.mem.Allocator;

pub const GamepadError = error{
    OpenFailed,
    ReadFailed,
    NotSupported,
    NotImplemented,
    NoGamepads,
};

pub const Button = enum {
    a, // Cross on PlayStation
    b, // Circle
    x, // Square
    y, // Triangle
    lb, // L1
    rb, // R1
    lt, // L2 (as button)
    rt, // R2 (as button)
    start,
    select, // Back/Share
    home, // Guide/PS
    l3, // Left stick click
    r3, // Right stick click
    dpad_up,
    dpad_down,
    dpad_left,
    dpad_right,
};

pub const Axis = enum {
    left_x,
    left_y,
    right_x,
    right_y,
    left_trigger,
    right_trigger,
};

pub const GamepadState = struct {
    connected: bool = false,
    name: [128]u8 = [_]u8{0} ** 128,
    buttons: u32 = 0, // Bitmask of pressed buttons
    axes: [6]f32 = [_]f32{0} ** 6, // Axis values -1.0 to 1.0

    pub fn isPressed(self: *const GamepadState, button: Button) bool {
        return (self.buttons & (@as(u32, 1) << @intFromEnum(button))) != 0;
    }

    pub fn getAxis(self: *const GamepadState, axis: Axis) f32 {
        return self.axes[@intFromEnum(axis)];
    }
};

// Linux evdev implementation
const linux = struct {
    const c = @cImport({
        @cInclude("linux/input.h");
        @cInclude("linux/input-event-codes.h");
        @cInclude("dirent.h");
        @cInclude("fcntl.h");
        @cInclude("unistd.h");
        @cInclude("sys/ioctl.h");
    });

    const MAX_GAMEPADS = 4;

    var fds: [MAX_GAMEPADS]?posix.fd_t = [_]?posix.fd_t{null} ** MAX_GAMEPADS;
    var states: [MAX_GAMEPADS]GamepadState = [_]GamepadState{.{}} ** MAX_GAMEPADS;
    var running: bool = false;
    var poll_thread: ?std.Thread = null;

    pub fn init() !void {
        try scanDevices();
    }

    pub fn deinit() void {
        running = false;
        if (poll_thread) |t| {
            t.join();
        }

        for (&fds) |*fd| {
            if (fd.*) |f| {
                posix.close(f);
                fd.* = null;
            }
        }
    }

    fn scanDevices() !void {
        // Look for gamepad devices in /dev/input/
        var gamepad_idx: usize = 0;

        var i: usize = 0;
        while (i < 32 and gamepad_idx < MAX_GAMEPADS) : (i += 1) {
            var path_buf: [64]u8 = undefined;
            const path = std.fmt.bufPrintZ(&path_buf, "/dev/input/event{d}", .{i}) catch continue;

            const fd = posix.open(path, .{ .ACCMODE = .RDONLY, .NONBLOCK = true }, 0) catch continue;

            // Check if it's a gamepad (has BTN_GAMEPAD or BTN_SOUTH)
            var bits: [(@as(usize, c.KEY_MAX) + 7) / 8]u8 = undefined;
            const ioctl_result = std.os.linux.ioctl(fd, c.EVIOCGBIT(c.EV_KEY, bits.len), @intFromPtr(&bits));
            if (ioctl_result < 0) {
                posix.close(fd);
                continue;
            }

            // Check for gamepad buttons
            const has_gamepad = testBit(&bits, c.BTN_GAMEPAD) or testBit(&bits, c.BTN_SOUTH);
            if (!has_gamepad) {
                posix.close(fd);
                continue;
            }

            // Get device name
            var name_buf: [128]u8 = undefined;
            const name_result = std.os.linux.ioctl(fd, c.EVIOCGNAME(name_buf.len), @intFromPtr(&name_buf));
            if (name_result >= 0) {
                @memcpy(&states[gamepad_idx].name, &name_buf);
            }

            fds[gamepad_idx] = fd;
            states[gamepad_idx].connected = true;
            gamepad_idx += 1;
        }

        if (gamepad_idx == 0) {
            return GamepadError.NoGamepads;
        }

        // Start polling thread
        running = true;
        poll_thread = try std.Thread.spawn(.{}, pollLoop, .{});
    }

    fn testBit(bits: []const u8, bit: usize) bool {
        return (bits[bit / 8] & (@as(u8, 1) << @as(u3, @intCast(bit % 8)))) != 0;
    }

    fn pollLoop() void {
        var event: c.input_event = undefined;

        while (running) {
            for (fds, 0..) |maybe_fd, idx| {
                const fd = maybe_fd orelse continue;

                const bytes_read = posix.read(fd, std.mem.asBytes(&event)) catch |err| {
                    if (err == error.WouldBlock) continue;
                    // Device disconnected
                    states[idx].connected = false;
                    continue;
                };

                if (bytes_read != @sizeOf(c.input_event)) continue;

                switch (event.type) {
                    c.EV_KEY => handleButton(&states[idx], event.code, event.value),
                    c.EV_ABS => handleAxis(&states[idx], event.code, event.value),
                    else => {},
                }
            }

            std.time.sleep(1 * std.time.ns_per_ms);
        }
    }

    fn handleButton(state: *GamepadState, code: u16, value: i32) void {
        const button: ?Button = switch (code) {
            c.BTN_SOUTH, c.BTN_A => .a,
            c.BTN_EAST, c.BTN_B => .b,
            c.BTN_NORTH, c.BTN_X => .x,
            c.BTN_WEST, c.BTN_Y => .y,
            c.BTN_TL => .lb,
            c.BTN_TR => .rb,
            c.BTN_TL2 => .lt,
            c.BTN_TR2 => .rt,
            c.BTN_START => .start,
            c.BTN_SELECT => .select,
            c.BTN_MODE => .home,
            c.BTN_THUMBL => .l3,
            c.BTN_THUMBR => .r3,
            c.BTN_DPAD_UP => .dpad_up,
            c.BTN_DPAD_DOWN => .dpad_down,
            c.BTN_DPAD_LEFT => .dpad_left,
            c.BTN_DPAD_RIGHT => .dpad_right,
            else => null,
        };

        if (button) |b| {
            const mask = @as(u32, 1) << @intFromEnum(b);
            if (value != 0) {
                state.buttons |= mask;
            } else {
                state.buttons &= ~mask;
            }
        }
    }

    fn handleAxis(state: *GamepadState, code: u16, value: i32) void {
        // Normalize to -1.0 to 1.0
        const normalized: f32 = @as(f32, @floatFromInt(value)) / 32767.0;

        switch (code) {
            c.ABS_X => state.axes[@intFromEnum(Axis.left_x)] = normalized,
            c.ABS_Y => state.axes[@intFromEnum(Axis.left_y)] = normalized,
            c.ABS_RX => state.axes[@intFromEnum(Axis.right_x)] = normalized,
            c.ABS_RY => state.axes[@intFromEnum(Axis.right_y)] = normalized,
            c.ABS_Z => state.axes[@intFromEnum(Axis.left_trigger)] = @as(f32, @floatFromInt(value)) / 255.0,
            c.ABS_RZ => state.axes[@intFromEnum(Axis.right_trigger)] = @as(f32, @floatFromInt(value)) / 255.0,
            // D-pad as axis (some controllers)
            c.ABS_HAT0X => {
                state.buttons &= ~(@as(u32, 1) << @intFromEnum(Button.dpad_left));
                state.buttons &= ~(@as(u32, 1) << @intFromEnum(Button.dpad_right));
                if (value < 0) state.buttons |= @as(u32, 1) << @intFromEnum(Button.dpad_left);
                if (value > 0) state.buttons |= @as(u32, 1) << @intFromEnum(Button.dpad_right);
            },
            c.ABS_HAT0Y => {
                state.buttons &= ~(@as(u32, 1) << @intFromEnum(Button.dpad_up));
                state.buttons &= ~(@as(u32, 1) << @intFromEnum(Button.dpad_down));
                if (value < 0) state.buttons |= @as(u32, 1) << @intFromEnum(Button.dpad_up);
                if (value > 0) state.buttons |= @as(u32, 1) << @intFromEnum(Button.dpad_down);
            },
            else => {},
        }
    }

    pub fn getState(index: usize) GamepadState {
        if (index >= MAX_GAMEPADS) return .{};
        return states[index];
    }

    pub fn isConnected(index: usize) bool {
        if (index >= MAX_GAMEPADS) return false;
        return states[index].connected;
    }

    pub fn getConnectedCount() usize {
        var count: usize = 0;
        for (states) |state| {
            if (state.connected) count += 1;
        }
        return count;
    }
};

// Public API

pub fn init() !void {
    switch (builtin.os.tag) {
        .linux => try linux.init(),
        .macos => return GamepadError.NotImplemented,
        .windows => return GamepadError.NotImplemented,
        else => return GamepadError.NotSupported,
    }
}

pub fn deinit() void {
    switch (builtin.os.tag) {
        .linux => linux.deinit(),
        else => {},
    }
}

/// Get the state of a gamepad
pub fn getState(index: usize) GamepadState {
    switch (builtin.os.tag) {
        .linux => return linux.getState(index),
        else => return .{},
    }
}

/// Check if a gamepad is connected
pub fn isConnected(index: usize) bool {
    switch (builtin.os.tag) {
        .linux => return linux.isConnected(index),
        else => return false,
    }
}

/// Get number of connected gamepads
pub fn getConnectedCount() usize {
    switch (builtin.os.tag) {
        .linux => return linux.getConnectedCount(),
        else => return 0,
    }
}
