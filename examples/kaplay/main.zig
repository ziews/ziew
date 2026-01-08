//! Kaplay Example - 2D game with Kaplay.js
//!
//! Demonstrates using Ziew as a game runtime with Kaplay.
//! Build with: zig build kaplay

const std = @import("std");
const ziew = @import("ziew");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create the game window
    var app = try ziew.App.init(allocator, .{
        .title = "Ziew + Kaplay",
        .width = 640,
        .height = 480,
        .debug = false, // No devtools for games
    });
    defer app.deinit();

    // Load the game HTML
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch ".";
    const html_path = std.fmt.allocPrintZ(allocator, "file://{s}/examples/kaplay/index.html", .{cwd}) catch {
        std.debug.print("[kaplay] Failed to build HTML path\n", .{});
        return;
    };
    defer allocator.free(html_path);

    std.debug.print("[kaplay] Loading game: {s}\n", .{html_path});
    app.navigate(html_path);

    // Run the game
    app.run();
}
