//! Ziew Plugin System
//!
//! Optional plugins that extend Ziew with native capabilities.
//! Enable plugins at build time with -D flags:
//!   zig build -Dnotify -Dsqlite -Dtray
//!
//! Each plugin provides:
//! - Zig API for direct use
//! - JS bridge functions for webview binding

const std = @import("std");
const builtin = @import("builtin");

// Conditionally import plugins based on build options (via C macros)
pub const notify = @import("notify.zig");
pub const single_instance = @import("single_instance.zig");
pub const sqlite = @import("sqlite.zig");
pub const keychain = @import("keychain.zig");
pub const tray = @import("tray.zig");
pub const hotkeys = @import("hotkeys.zig");
pub const menu = @import("menu.zig");
pub const gamepad = @import("gamepad.zig");
pub const serial = @import("serial.zig");

/// Platform detection
pub const Platform = enum {
    linux,
    macos,
    windows,
    unknown,
};

pub const platform: Platform = switch (builtin.os.tag) {
    .linux => .linux,
    .macos => .macos,
    .windows => .windows,
    else => .unknown,
};

/// Plugin initialization context
pub const PluginContext = struct {
    allocator: std.mem.Allocator,
    app_name: []const u8,
    app_id: []const u8,

    pub fn init(allocator: std.mem.Allocator, app_name: []const u8, app_id: []const u8) PluginContext {
        return .{
            .allocator = allocator,
            .app_name = app_name,
            .app_id = app_id,
        };
    }
};

/// Initialize all enabled plugins
pub fn initAll(ctx: PluginContext) !void {
    _ = ctx;
    // Plugins initialize on first use
}

/// Deinitialize all plugins
pub fn deinitAll() void {
    notify.deinit();
    single_instance.release();
    keychain.deinit();
    hotkeys.deinit();
    tray.destroy();
    gamepad.deinit();
}
