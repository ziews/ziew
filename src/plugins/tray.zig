//! System Tray Plugin
//!
//! System tray icon with menu support.
//!
//! Linux: Uses libappindicator3 or GtkStatusIcon
//! macOS: Uses NSStatusItem (TODO)
//! Windows: Uses Shell_NotifyIcon (TODO)

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const TrayError = error{
    InitFailed,
    NotSupported,
    NotImplemented,
    InvalidIcon,
};

pub const MenuItem = struct {
    label: []const u8,
    enabled: bool = true,
    separator: bool = false,
    callback: ?*const fn () void = null,
    submenu: ?[]const MenuItem = null,
};

// Linux implementation using AppIndicator or GtkStatusIcon
const linux = struct {
    const c = @cImport({
        @cInclude("gtk/gtk.h");
        // Try AppIndicator first, fall back to GtkStatusIcon
        // @cInclude("libappindicator/app-indicator.h");
    });

    var status_icon: ?*c.GtkStatusIcon = null;
    var menu: ?*c.GtkMenu = null;
    var click_callback: ?*const fn () void = null;

    pub fn create(icon_path: []const u8, tooltip: []const u8) !void {
        if (status_icon != null) return;

        const icon_z = std.heap.c_allocator.dupeZ(u8, icon_path) catch return TrayError.InitFailed;
        defer std.heap.c_allocator.free(icon_z);

        const tooltip_z = std.heap.c_allocator.dupeZ(u8, tooltip) catch return TrayError.InitFailed;
        defer std.heap.c_allocator.free(tooltip_z);

        status_icon = c.gtk_status_icon_new_from_file(icon_z);
        if (status_icon == null) {
            // Try creating from icon name instead
            status_icon = c.gtk_status_icon_new_from_icon_name(icon_z);
        }

        if (status_icon) |icon| {
            c.gtk_status_icon_set_tooltip_text(icon, tooltip_z);
            c.gtk_status_icon_set_visible(icon, 1);

            // Connect click signal
            _ = c.g_signal_connect_data(
                @ptrCast(icon),
                "activate",
                @ptrCast(&onActivate),
                null,
                null,
                0,
            );

            // Connect right-click for menu
            _ = c.g_signal_connect_data(
                @ptrCast(icon),
                "popup-menu",
                @ptrCast(&onPopupMenu),
                null,
                null,
                0,
            );
        } else {
            return TrayError.InitFailed;
        }
    }

    fn onActivate(_: ?*c.GtkStatusIcon, _: ?*anyopaque) callconv(.C) void {
        if (click_callback) |cb| {
            cb();
        }
    }

    fn onPopupMenu(_: ?*c.GtkStatusIcon, button: c.guint, activate_time: c.guint32, _: ?*anyopaque) callconv(.C) void {
        if (menu) |m| {
            c.gtk_menu_popup(
                m,
                null,
                null,
                null,
                null,
                button,
                activate_time,
            );
        }
    }

    pub fn setMenu(items: []const MenuItem) !void {
        // Clean up old menu
        if (menu) |m| {
            c.gtk_widget_destroy(@ptrCast(m));
        }

        menu = @ptrCast(c.gtk_menu_new());
        if (menu == null) return TrayError.InitFailed;

        for (items) |item| {
            try addMenuItem(menu.?, item);
        }

        c.gtk_widget_show_all(@ptrCast(menu.?));
    }

    fn addMenuItem(parent_menu: *c.GtkMenu, item: MenuItem) !void {
        if (item.separator) {
            const sep = c.gtk_separator_menu_item_new();
            c.gtk_menu_shell_append(@ptrCast(parent_menu), sep);
            return;
        }

        const label_z = std.heap.c_allocator.dupeZ(u8, item.label) catch return;
        defer std.heap.c_allocator.free(label_z);

        const menu_item = c.gtk_menu_item_new_with_label(label_z);
        c.gtk_widget_set_sensitive(menu_item, if (item.enabled) 1 else 0);

        if (item.callback) |cb| {
            // Store callback and connect signal
            const CallbackData = struct {
                callback: *const fn () void,
            };
            const data = std.heap.c_allocator.create(CallbackData) catch return;
            data.callback = cb;

            _ = c.g_signal_connect_data(
                @ptrCast(menu_item),
                "activate",
                @ptrCast(&menuItemActivate),
                data,
                null,
                0,
            );
        }

        if (item.submenu) |sub| {
            const submenu: *c.GtkMenu = @ptrCast(c.gtk_menu_new());
            for (sub) |subitem| {
                try addMenuItem(submenu, subitem);
            }
            c.gtk_menu_item_set_submenu(@ptrCast(menu_item), @ptrCast(submenu));
        }

        c.gtk_menu_shell_append(@ptrCast(parent_menu), menu_item);
    }

    fn menuItemActivate(_: *c.GtkMenuItem, user_data: ?*anyopaque) callconv(.C) void {
        if (user_data) |data| {
            const cb_data: *struct { callback: *const fn () void } = @ptrCast(@alignCast(data));
            cb_data.callback();
        }
    }

    pub fn setIcon(icon_path: []const u8) !void {
        if (status_icon == null) return TrayError.InitFailed;

        const icon_z = std.heap.c_allocator.dupeZ(u8, icon_path) catch return TrayError.InitFailed;
        defer std.heap.c_allocator.free(icon_z);

        c.gtk_status_icon_set_from_file(status_icon.?, icon_z);
    }

    pub fn setTooltip(tooltip: []const u8) !void {
        if (status_icon == null) return TrayError.InitFailed;

        const tooltip_z = std.heap.c_allocator.dupeZ(u8, tooltip) catch return TrayError.InitFailed;
        defer std.heap.c_allocator.free(tooltip_z);

        c.gtk_status_icon_set_tooltip_text(status_icon.?, tooltip_z);
    }

    pub fn setVisible(visible: bool) void {
        if (status_icon) |icon| {
            c.gtk_status_icon_set_visible(icon, if (visible) 1 else 0);
        }
    }

    pub fn onClick(callback: *const fn () void) void {
        click_callback = callback;
    }

    pub fn destroy() void {
        if (menu) |m| {
            c.gtk_widget_destroy(@ptrCast(m));
            menu = null;
        }
        if (status_icon) |icon| {
            c.g_object_unref(icon);
            status_icon = null;
        }
        click_callback = null;
    }
};

// Public API

/// Create a system tray icon
pub fn create(icon_path: []const u8, tooltip: []const u8) !void {
    switch (builtin.os.tag) {
        .linux => try linux.create(icon_path, tooltip),
        .macos => return TrayError.NotImplemented,
        .windows => return TrayError.NotImplemented,
        else => return TrayError.NotSupported,
    }
}

/// Set the tray menu
pub fn setMenu(items: []const MenuItem) !void {
    switch (builtin.os.tag) {
        .linux => try linux.setMenu(items),
        else => return TrayError.NotImplemented,
    }
}

/// Update the tray icon
pub fn setIcon(icon_path: []const u8) !void {
    switch (builtin.os.tag) {
        .linux => try linux.setIcon(icon_path),
        else => return TrayError.NotImplemented,
    }
}

/// Update the tooltip
pub fn setTooltip(tooltip: []const u8) !void {
    switch (builtin.os.tag) {
        .linux => try linux.setTooltip(tooltip),
        else => return TrayError.NotImplemented,
    }
}

/// Show or hide the tray icon
pub fn setVisible(visible: bool) void {
    switch (builtin.os.tag) {
        .linux => linux.setVisible(visible),
        else => {},
    }
}

/// Set click callback
pub fn onClick(callback: *const fn () void) void {
    switch (builtin.os.tag) {
        .linux => linux.onClick(callback),
        else => {},
    }
}

/// Remove the tray icon
pub fn destroy() void {
    switch (builtin.os.tag) {
        .linux => linux.destroy(),
        else => {},
    }
}
