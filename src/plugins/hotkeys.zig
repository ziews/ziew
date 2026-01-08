//! Global Hotkeys Plugin
//!
//! Register global keyboard shortcuts that work even when app is unfocused.
//!
//! Linux: Uses X11 XGrabKey
//! macOS: Uses Carbon RegisterEventHotKey (TODO)
//! Windows: Uses RegisterHotKey (TODO)

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const HotkeyError = error{
    AlreadyRegistered,
    RegistrationFailed,
    InvalidKey,
    NotSupported,
    NotImplemented,
};

pub const Modifier = enum(u32) {
    none = 0,
    shift = 1,
    ctrl = 2,
    alt = 4,
    super = 8, // Windows key / Command key

    pub fn combine(mods: []const Modifier) u32 {
        var result: u32 = 0;
        for (mods) |m| {
            result |= @intFromEnum(m);
        }
        return result;
    }
};

pub const Key = enum {
    a,
    b,
    c,
    d,
    e,
    f,
    g,
    h,
    i,
    j,
    k,
    l,
    m,
    n,
    o,
    p,
    q,
    r,
    s,
    t,
    u,
    v,
    w,
    x,
    y,
    z,
    @"0",
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    space,
    enter,
    escape,
    tab,
    backspace,
    delete,
    insert,
    home,
    end,
    page_up,
    page_down,
    up,
    down,
    left,
    right,
};

const HotkeyCallback = *const fn () void;

const RegisteredHotkey = struct {
    modifiers: u32,
    key: Key,
    callback: HotkeyCallback,
};

// Linux X11 implementation
const linux = struct {
    const c = @cImport({
        @cInclude("X11/Xlib.h");
        @cInclude("X11/keysym.h");
    });

    var display: ?*c.Display = null;
    var root_window: c.Window = 0;
    var hotkeys: std.ArrayList(RegisteredHotkey) = undefined;
    var allocator: Allocator = undefined;
    var running: bool = false;
    var event_thread: ?std.Thread = null;

    pub fn init(alloc: Allocator) !void {
        allocator = alloc;
        hotkeys = std.ArrayList(RegisteredHotkey).init(allocator);

        display = c.XOpenDisplay(null);
        if (display == null) {
            return HotkeyError.NotSupported;
        }

        root_window = c.DefaultRootWindow(display);
    }

    pub fn deinit() void {
        running = false;
        if (event_thread) |t| {
            t.join();
        }

        // Ungrab all keys
        for (hotkeys.items) |hk| {
            ungrabKey(hk.modifiers, hk.key);
        }
        hotkeys.deinit();

        if (display) |d| {
            c.XCloseDisplay(d);
            display = null;
        }
    }

    pub fn register(modifiers: u32, key: Key, callback: HotkeyCallback) !void {
        // Check if already registered
        for (hotkeys.items) |hk| {
            if (hk.modifiers == modifiers and hk.key == key) {
                return HotkeyError.AlreadyRegistered;
            }
        }

        const x_mods = toX11Modifiers(modifiers);
        const x_key = toX11Key(key) orelse return HotkeyError.InvalidKey;

        if (display == null) return HotkeyError.NotSupported;

        // Grab the key (with various modifier combinations for caps/num lock)
        const mod_combos = [_]c_uint{
            x_mods,
            x_mods | c.Mod2Mask, // NumLock
            x_mods | c.LockMask, // CapsLock
            x_mods | c.Mod2Mask | c.LockMask,
        };

        const keycode = c.XKeysymToKeycode(display, x_key);

        for (mod_combos) |mods| {
            _ = c.XGrabKey(
                display,
                keycode,
                mods,
                root_window,
                c.True,
                c.GrabModeAsync,
                c.GrabModeAsync,
            );
        }

        try hotkeys.append(.{
            .modifiers = modifiers,
            .key = key,
            .callback = callback,
        });

        // Start event loop if not running
        if (!running) {
            running = true;
            event_thread = try std.Thread.spawn(.{}, eventLoop, .{});
        }
    }

    pub fn unregister(modifiers: u32, key: Key) void {
        var i: usize = 0;
        while (i < hotkeys.items.len) {
            const hk = hotkeys.items[i];
            if (hk.modifiers == modifiers and hk.key == key) {
                ungrabKey(modifiers, key);
                _ = hotkeys.orderedRemove(i);
            } else {
                i += 1;
            }
        }
    }

    fn ungrabKey(modifiers: u32, key: Key) void {
        if (display == null) return;

        const x_mods = toX11Modifiers(modifiers);
        const x_key = toX11Key(key) orelse return;
        const keycode = c.XKeysymToKeycode(display, x_key);

        const mod_combos = [_]c_uint{
            x_mods,
            x_mods | c.Mod2Mask,
            x_mods | c.LockMask,
            x_mods | c.Mod2Mask | c.LockMask,
        };

        for (mod_combos) |mods| {
            _ = c.XUngrabKey(display, keycode, mods, root_window);
        }
    }

    fn eventLoop() void {
        if (display == null) return;

        var event: c.XEvent = undefined;
        while (running) {
            // Check for pending events with timeout
            if (c.XPending(display) > 0) {
                _ = c.XNextEvent(display, &event);

                if (event.type == c.KeyPress) {
                    const key_event = event.xkey;
                    const keysym = c.XLookupKeysym(&event.xkey, 0);

                    // Find matching hotkey
                    for (hotkeys.items) |hk| {
                        const x_key = toX11Key(hk.key) orelse continue;
                        const x_mods = toX11Modifiers(hk.modifiers);

                        // Mask out caps/num lock
                        const clean_state = key_event.state & ~@as(c_uint, c.Mod2Mask | c.LockMask);

                        if (keysym == x_key and clean_state == x_mods) {
                            hk.callback();
                            break;
                        }
                    }
                }
            } else {
                std.time.sleep(10 * std.time.ns_per_ms);
            }
        }
    }

    fn toX11Modifiers(mods: u32) c_uint {
        var result: c_uint = 0;
        if (mods & @intFromEnum(Modifier.shift) != 0) result |= c.ShiftMask;
        if (mods & @intFromEnum(Modifier.ctrl) != 0) result |= c.ControlMask;
        if (mods & @intFromEnum(Modifier.alt) != 0) result |= c.Mod1Mask;
        if (mods & @intFromEnum(Modifier.super) != 0) result |= c.Mod4Mask;
        return result;
    }

    fn toX11Key(key: Key) ?c.KeySym {
        return switch (key) {
            .a => c.XK_a,
            .b => c.XK_b,
            .c => c.XK_c,
            .d => c.XK_d,
            .e => c.XK_e,
            .f => c.XK_f,
            .g => c.XK_g,
            .h => c.XK_h,
            .i => c.XK_i,
            .j => c.XK_j,
            .k => c.XK_k,
            .l => c.XK_l,
            .m => c.XK_m,
            .n => c.XK_n,
            .o => c.XK_o,
            .p => c.XK_p,
            .q => c.XK_q,
            .r => c.XK_r,
            .s => c.XK_s,
            .t => c.XK_t,
            .u => c.XK_u,
            .v => c.XK_v,
            .w => c.XK_w,
            .x => c.XK_x,
            .y => c.XK_y,
            .z => c.XK_z,
            .@"0" => c.XK_0,
            .@"1" => c.XK_1,
            .@"2" => c.XK_2,
            .@"3" => c.XK_3,
            .@"4" => c.XK_4,
            .@"5" => c.XK_5,
            .@"6" => c.XK_6,
            .@"7" => c.XK_7,
            .@"8" => c.XK_8,
            .@"9" => c.XK_9,
            .f1 => c.XK_F1,
            .f2 => c.XK_F2,
            .f3 => c.XK_F3,
            .f4 => c.XK_F4,
            .f5 => c.XK_F5,
            .f6 => c.XK_F6,
            .f7 => c.XK_F7,
            .f8 => c.XK_F8,
            .f9 => c.XK_F9,
            .f10 => c.XK_F10,
            .f11 => c.XK_F11,
            .f12 => c.XK_F12,
            .space => c.XK_space,
            .enter => c.XK_Return,
            .escape => c.XK_Escape,
            .tab => c.XK_Tab,
            .backspace => c.XK_BackSpace,
            .delete => c.XK_Delete,
            .insert => c.XK_Insert,
            .home => c.XK_Home,
            .end => c.XK_End,
            .page_up => c.XK_Page_Up,
            .page_down => c.XK_Page_Down,
            .up => c.XK_Up,
            .down => c.XK_Down,
            .left => c.XK_Left,
            .right => c.XK_Right,
        };
    }
};

// Public API

pub fn init(allocator: Allocator) !void {
    switch (builtin.os.tag) {
        .linux => try linux.init(allocator),
        .macos => return HotkeyError.NotImplemented,
        .windows => return HotkeyError.NotImplemented,
        else => return HotkeyError.NotSupported,
    }
}

pub fn deinit() void {
    switch (builtin.os.tag) {
        .linux => linux.deinit(),
        else => {},
    }
}

/// Register a global hotkey
pub fn register(modifiers: u32, key: Key, callback: HotkeyCallback) !void {
    switch (builtin.os.tag) {
        .linux => try linux.register(modifiers, key, callback),
        else => return HotkeyError.NotImplemented,
    }
}

/// Unregister a global hotkey
pub fn unregister(modifiers: u32, key: Key) void {
    switch (builtin.os.tag) {
        .linux => linux.unregister(modifiers, key),
        else => {},
    }
}

/// Parse a hotkey string like "Ctrl+Shift+A"
pub fn parseHotkey(str: []const u8) !struct { modifiers: u32, key: Key } {
    var modifiers: u32 = 0;
    var key: ?Key = null;

    var iter = std.mem.splitSequence(u8, str, "+");
    while (iter.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " ");
        const lower = blk: {
            var buf: [32]u8 = undefined;
            const len = @min(trimmed.len, buf.len);
            for (0..len) |i| {
                buf[i] = std.ascii.toLower(trimmed[i]);
            }
            break :blk buf[0..len];
        };

        if (std.mem.eql(u8, lower, "ctrl") or std.mem.eql(u8, lower, "control") or std.mem.eql(u8, lower, "commandorcontrol")) {
            modifiers |= @intFromEnum(Modifier.ctrl);
        } else if (std.mem.eql(u8, lower, "shift")) {
            modifiers |= @intFromEnum(Modifier.shift);
        } else if (std.mem.eql(u8, lower, "alt") or std.mem.eql(u8, lower, "option")) {
            modifiers |= @intFromEnum(Modifier.alt);
        } else if (std.mem.eql(u8, lower, "super") or std.mem.eql(u8, lower, "meta") or std.mem.eql(u8, lower, "command") or std.mem.eql(u8, lower, "win")) {
            modifiers |= @intFromEnum(Modifier.super);
        } else if (lower.len == 1 and lower[0] >= 'a' and lower[0] <= 'z') {
            key = @enumFromInt(lower[0] - 'a');
        } else if (std.mem.eql(u8, lower, "space")) {
            key = .space;
        } else if (std.mem.eql(u8, lower, "enter") or std.mem.eql(u8, lower, "return")) {
            key = .enter;
        } else if (std.mem.eql(u8, lower, "escape") or std.mem.eql(u8, lower, "esc")) {
            key = .escape;
        }
        // Add more key mappings as needed
    }

    if (key) |k| {
        return .{ .modifiers = modifiers, .key = k };
    }
    return HotkeyError.InvalidKey;
}
