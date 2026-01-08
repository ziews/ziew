//! Lua Web Example - Lua scripting with webview UI
//!
//! Demonstrates calling Lua functions from JavaScript.
//! Build with: zig build -Dlua=true lua-web

const std = @import("std");
const ziew = @import("ziew");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create the app window
    var app = try ziew.App.init(allocator, .{
        .title = "Ziew Lua Demo",
        .width = 500,
        .height = 400,
        .debug = true,
    });
    defer app.deinit();

    // Initialize Lua bridge
    var lua_bridge = try ziew.lua_bridge.LuaBridge.initLazy(allocator, app.window);
    defer lua_bridge.deinit();

    // Load backend script from file
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch ".";

    const lua_path = std.fmt.allocPrint(allocator, "{s}/examples/lua-web/backend.lua", .{cwd}) catch {
        std.debug.print("[lua-web] Failed to build Lua path\n", .{});
        return;
    };
    defer allocator.free(lua_path);

    lua_bridge.loadFile(lua_path) catch |err| {
        std.debug.print("[lua-web] Failed to load Lua: {any}\n", .{err});
    };

    std.debug.print("[lua-web] Lua loaded! Opening window...\n", .{});

    // Load the HTML file
    const html_path = std.fmt.allocPrintZ(allocator, "file://{s}/examples/lua-web/index.html", .{cwd}) catch {
        std.debug.print("[lua-web] Failed to build HTML path\n", .{});
        return;
    };
    defer allocator.free(html_path);

    std.debug.print("[lua-web] Loading: {s}\n", .{html_path});
    app.navigate(html_path);

    // Run the app
    app.run();
}
