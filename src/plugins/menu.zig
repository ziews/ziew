//! Native Menu Plugin
//!
//! Native application and context menus.
//!
//! Linux: Uses GTK3 menus
//! macOS: Uses NSMenu (TODO)
//! Windows: Uses Win32 menus (TODO)

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const MenuError = error{
    CreateFailed,
    NotSupported,
    NotImplemented,
};

pub const MenuItemType = enum {
    normal,
    separator,
    checkbox,
    submenu,
};

pub const MenuItemConfig = struct {
    label: []const u8 = "",
    item_type: MenuItemType = .normal,
    enabled: bool = true,
    checked: bool = false,
    accelerator: ?[]const u8 = null,
    callback: ?*const fn () void = null,
    submenu: ?[]const MenuItemConfig = null,
};

// Linux GTK implementation
const linux = struct {
    const c = @cImport({
        @cInclude("gtk/gtk.h");
    });

    pub const Menu = struct {
        gtk_menu: *c.GtkMenu,
        allocator: Allocator,

        pub fn init(allocator: Allocator) !Menu {
            const menu = c.gtk_menu_new();
            if (menu == null) return MenuError.CreateFailed;

            return Menu{
                .gtk_menu = @ptrCast(menu),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Menu) void {
            c.gtk_widget_destroy(@ptrCast(self.gtk_menu));
        }

        pub fn addItem(self: *Menu, config: MenuItemConfig) !void {
            const item = try createMenuItem(self.allocator, config);
            c.gtk_menu_shell_append(@ptrCast(self.gtk_menu), item);
        }

        pub fn addSeparator(self: *Menu) void {
            const sep = c.gtk_separator_menu_item_new();
            c.gtk_menu_shell_append(@ptrCast(self.gtk_menu), sep);
        }

        pub fn popup(self: *Menu, x: i32, y: i32) void {
            c.gtk_widget_show_all(@ptrCast(self.gtk_menu));
            c.gtk_menu_popup_at_pointer(self.gtk_menu, null);
            _ = x;
            _ = y;
        }

        pub fn popupAtWidget(self: *Menu, widget: *anyopaque) void {
            c.gtk_widget_show_all(@ptrCast(self.gtk_menu));
            c.gtk_menu_popup_at_widget(
                self.gtk_menu,
                @ptrCast(widget),
                c.GDK_GRAVITY_SOUTH_WEST,
                c.GDK_GRAVITY_NORTH_WEST,
                null,
            );
        }
    };

    pub const MenuBar = struct {
        gtk_menubar: *c.GtkMenuBar,
        allocator: Allocator,

        pub fn init(allocator: Allocator) !MenuBar {
            const menubar = c.gtk_menu_bar_new();
            if (menubar == null) return MenuError.CreateFailed;

            return MenuBar{
                .gtk_menubar = @ptrCast(menubar),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *MenuBar) void {
            c.gtk_widget_destroy(@ptrCast(self.gtk_menubar));
        }

        pub fn addMenu(self: *MenuBar, label: []const u8, items: []const MenuItemConfig) !void {
            const label_z = try self.allocator.dupeZ(u8, label);
            defer self.allocator.free(label_z);

            const menu_item = c.gtk_menu_item_new_with_label(label_z);
            const submenu = c.gtk_menu_new();

            for (items) |item_config| {
                const item = try createMenuItem(self.allocator, item_config);
                c.gtk_menu_shell_append(@ptrCast(submenu), item);
            }

            c.gtk_menu_item_set_submenu(@ptrCast(menu_item), submenu);
            c.gtk_menu_shell_append(@ptrCast(self.gtk_menubar), menu_item);
        }

        pub fn widget(self: *MenuBar) *anyopaque {
            return @ptrCast(self.gtk_menubar);
        }
    };

    fn createMenuItem(allocator: Allocator, config: MenuItemConfig) !*c.GtkWidget {
        var item: *c.GtkWidget = undefined;

        switch (config.item_type) {
            .separator => {
                item = c.gtk_separator_menu_item_new().?;
            },
            .checkbox => {
                const label_z = try allocator.dupeZ(u8, config.label);
                defer allocator.free(label_z);
                item = c.gtk_check_menu_item_new_with_label(label_z).?;
                c.gtk_check_menu_item_set_active(@ptrCast(item), if (config.checked) 1 else 0);
            },
            .normal, .submenu => {
                const label_z = try allocator.dupeZ(u8, config.label);
                defer allocator.free(label_z);
                item = c.gtk_menu_item_new_with_label(label_z).?;
            },
        }

        c.gtk_widget_set_sensitive(item, if (config.enabled) 1 else 0);

        if (config.callback) |cb| {
            const CallbackData = struct {
                callback: *const fn () void,
            };
            const data = allocator.create(CallbackData) catch return item;
            data.callback = cb;

            _ = c.g_signal_connect_data(
                @ptrCast(item),
                "activate",
                @ptrCast(&menuActivate),
                data,
                null,
                0,
            );
        }

        if (config.submenu) |submenu_items| {
            const submenu = c.gtk_menu_new();
            for (submenu_items) |sub_config| {
                const sub_item = try createMenuItem(allocator, sub_config);
                c.gtk_menu_shell_append(@ptrCast(submenu), sub_item);
            }
            c.gtk_menu_item_set_submenu(@ptrCast(item), submenu);
        }

        return item;
    }

    fn menuActivate(_: *c.GtkMenuItem, user_data: ?*anyopaque) callconv(.C) void {
        if (user_data) |data| {
            const cb_data: *struct { callback: *const fn () void } = @ptrCast(@alignCast(data));
            cb_data.callback();
        }
    }
};

// Public API

pub const Menu = switch (builtin.os.tag) {
    .linux => linux.Menu,
    else => struct {
        allocator: Allocator,
        pub fn init(_: Allocator) !@This() {
            return MenuError.NotImplemented;
        }
        pub fn deinit(_: *@This()) void {}
        pub fn addItem(_: *@This(), _: MenuItemConfig) !void {}
        pub fn addSeparator(_: *@This()) void {}
        pub fn popup(_: *@This(), _: i32, _: i32) void {}
    },
};

pub const MenuBar = switch (builtin.os.tag) {
    .linux => linux.MenuBar,
    else => struct {
        allocator: Allocator,
        pub fn init(_: Allocator) !@This() {
            return MenuError.NotImplemented;
        }
        pub fn deinit(_: *@This()) void {}
        pub fn addMenu(_: *@This(), _: []const u8, _: []const MenuItemConfig) !void {}
        pub fn widget(_: *@This()) *anyopaque {
            return undefined;
        }
    },
};

/// Create a context menu
pub fn createContextMenu(allocator: Allocator) !Menu {
    return Menu.init(allocator);
}

/// Create a menu bar
pub fn createMenuBar(allocator: Allocator) !MenuBar {
    return MenuBar.init(allocator);
}
