//! System Notifications Plugin
//!
//! Sends native desktop notifications.
//!
//! Linux: Uses libnotify
//! macOS: Uses NSUserNotificationCenter (TODO)
//! Windows: Uses Shell_NotifyIcon (TODO)

const std = @import("std");
const builtin = @import("builtin");

pub const Notification = struct {
    title: []const u8,
    body: []const u8,
    icon: ?[]const u8 = null,
    timeout: i32 = -1, // -1 = default, 0 = never expire
};

// Linux implementation using libnotify
const linux = struct {
    const c = @cImport({
        @cInclude("libnotify/notify.h");
    });

    var initialized: bool = false;

    pub fn init(app_name: [*:0]const u8) bool {
        if (initialized) return true;
        initialized = c.notify_init(app_name) != 0;
        return initialized;
    }

    pub fn deinit() void {
        if (initialized) {
            c.notify_uninit();
            initialized = false;
        }
    }

    pub fn send(notif: Notification) !void {
        if (!initialized) return error.NotInitialized;

        const title_z = try std.heap.c_allocator.dupeZ(u8, notif.title);
        defer std.heap.c_allocator.free(title_z);

        const body_z = try std.heap.c_allocator.dupeZ(u8, notif.body);
        defer std.heap.c_allocator.free(body_z);

        const icon_z: ?[*:0]const u8 = if (notif.icon) |icon| blk: {
            const z = try std.heap.c_allocator.dupeZ(u8, icon);
            break :blk z;
        } else null;
        defer if (icon_z) |z| std.heap.c_allocator.free(std.mem.span(z));

        const n = c.notify_notification_new(title_z, body_z, icon_z);
        if (n == null) return error.FailedToCreateNotification;
        defer c.g_object_unref(n);

        if (notif.timeout >= 0) {
            c.notify_notification_set_timeout(n, notif.timeout);
        }

        var err: ?*c.GError = null;
        if (c.notify_notification_show(n, &err) == 0) {
            if (err) |e| {
                std.debug.print("[notify] Error: {s}\n", .{e.*.message});
                c.g_error_free(e);
            }
            return error.FailedToShowNotification;
        }
    }
};

// Public API - dispatches to platform implementation
pub fn init(app_name: []const u8) !void {
    const app_name_z = try std.heap.c_allocator.dupeZ(u8, app_name);
    defer std.heap.c_allocator.free(app_name_z);

    switch (builtin.os.tag) {
        .linux => {
            if (!linux.init(app_name_z)) {
                return error.FailedToInitialize;
            }
        },
        .macos => {
            // TODO: macOS implementation
            return error.NotImplemented;
        },
        .windows => {
            // TODO: Windows implementation
            return error.NotImplemented;
        },
        else => return error.UnsupportedPlatform,
    }
}

pub fn deinit() void {
    switch (builtin.os.tag) {
        .linux => linux.deinit(),
        else => {},
    }
}

pub fn send(notif: Notification) !void {
    switch (builtin.os.tag) {
        .linux => try linux.send(notif),
        else => return error.UnsupportedPlatform,
    }
}

/// Convenience function for simple notifications
pub fn sendSimple(title: []const u8, body: []const u8) !void {
    try send(.{ .title = title, .body = body });
}

// JS Bridge functions
pub fn bridgeSend(seq: [*:0]const u8, req: [*:0]const u8, _: ?*anyopaque) callconv(.C) void {
    _ = seq;
    // Parse JSON request and send notification
    // Format: {"title": "...", "body": "...", "icon": "..."}
    const req_str = std.mem.span(req);
    _ = req_str;

    // TODO: JSON parsing and response
    // For now, just demonstrate the API works
}
