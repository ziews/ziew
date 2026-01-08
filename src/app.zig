//! Ziew App - High-level API for building webview applications

const std = @import("std");
const webview = @import("webview.zig");
const bridge = @import("bridge.zig");

pub const App = struct {
    window: webview.Window,
    allocator: std.mem.Allocator,

    pub const Config = struct {
        title: [:0]const u8 = "Ziew App",
        width: u32 = 800,
        height: u32 = 600,
        debug: bool = false,
    };

    /// Initialize a new Ziew application
    pub fn init(allocator: std.mem.Allocator, config: Config) !App {
        const window = try webview.Window.create(.{
            .title = config.title,
            .width = config.width,
            .height = config.height,
            .debug = config.debug,
        });

        var app = App{
            .window = window,
            .allocator = allocator,
        };

        // Inject the ziew.js bridge
        try app.window.init(bridge.ziew_js);

        return app;
    }

    /// Clean up resources
    pub fn deinit(self: *App) void {
        self.window.destroy() catch {};
    }

    /// Load HTML directly
    pub fn loadHtml(self: *App, html: [:0]const u8) void {
        self.window.setHtml(html) catch {};
    }

    /// Navigate to a URL
    pub fn navigate(self: *App, url: [:0]const u8) void {
        self.window.navigate(url) catch {};
    }

    /// Execute JavaScript
    pub fn eval(self: *App, js: [:0]const u8) void {
        self.window.eval(js) catch {};
    }

    /// Run the application (blocking)
    pub fn run(self: *App) void {
        self.window.run() catch {};
    }

    /// Stop the application
    pub fn terminate(self: *App) void {
        self.window.terminate() catch {};
    }

    /// Set window title
    pub fn setTitle(self: *App, title: [:0]const u8) void {
        self.window.setTitle(title) catch {};
    }

    /// Set window size
    pub fn setSize(self: *App, width: u32, height: u32) void {
        self.window.setSize(width, height) catch {};
    }

    /// Bind a native function to JavaScript
    pub fn bind(self: *App, name: [:0]const u8, callback: webview.Window.BindCallback, arg: ?*anyopaque) !void {
        try self.window.bind(name, callback, arg);
    }
};
