//! Ziew - Lightweight desktop apps with native webviews and local AI
//!
//! Build tiny, fast desktop applications using web technologies
//! with first-class support for local AI inference.

const std = @import("std");

pub const App = @import("app.zig").App;
pub const webview = @import("webview.zig");
pub const bridge = @import("bridge.zig");
pub const plugin = @import("plugin.zig");

// Lua module - optional, build with -Dlua=true
pub const lua = @import("lua.zig");
pub const lua_bridge = @import("lua_bridge.zig");

// AI module - optional, build with -Dai=true
pub const ai = @import("ai.zig");
pub const ai_bridge = @import("ai_bridge.zig");

// Piper module - optional, build with -Dpiper=true
pub const piper = @import("piper.zig");
pub const piper_bridge = @import("piper_bridge.zig");

/// Ziew version
pub const version = "0.3.0";

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
