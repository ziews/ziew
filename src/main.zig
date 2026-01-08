//! Ziew - Lightweight desktop apps with native webviews and local AI
//!
//! Build tiny, fast desktop applications using web technologies
//! with first-class support for local AI inference.

const std = @import("std");

pub const App = @import("app.zig").App;
pub const webview = @import("webview.zig");
pub const bridge = @import("bridge.zig");
pub const plugin = @import("plugin.zig");

/// Ziew version
pub const version = "0.2.0";

/// Get the current platform name
pub fn platform() []const u8 {
    return switch (@import("builtin").os.tag) {
        .linux => "linux",
        .macos => "macos",
        .windows => "windows",
        else => "unknown",
    };
}

test "basic app creation" {
    // This test won't actually create a window in CI, just verify compilation
    _ = App;
    _ = webview.Window;
}
