//! {{PROJECT_NAME}} - Built with Ziew + Three.js
//!
//! Run with: zig build run

const std = @import("std");
const ziew = @import("ziew");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try ziew.App.init(allocator, .{
        .title = "{{PROJECT_NAME}}",
        .width = 1024,
        .height = 768,
        .debug = false,
    });
    defer app.deinit();

    // Load the game
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch ".";
    const html_path = std.fmt.allocPrintZ(allocator, "file://{s}/index.html", .{cwd}) catch return;
    defer allocator.free(html_path);

    app.navigate(html_path);
    app.run();
}
