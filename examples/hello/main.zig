//! Hello World - Minimal Ziew application

const std = @import("std");
const ziew = @import("ziew");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var app = try ziew.App.init(allocator, .{
        .title = "Hello Ziew!",
        .width = 600,
        .height = 400,
        .debug = true,
    });
    defer app.deinit();

    // Load inline HTML
    app.loadHtml(
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <meta charset="utf-8">
        \\  <title>Hello Ziew</title>
        \\  <style>
        \\    * { margin: 0; padding: 0; box-sizing: border-box; }
        \\    body {
        \\      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
        \\      display: flex;
        \\      flex-direction: column;
        \\      align-items: center;
        \\      justify-content: center;
        \\      min-height: 100vh;
        \\      background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
        \\      color: #eee;
        \\    }
        \\    h1 {
        \\      font-size: 3rem;
        \\      margin-bottom: 1rem;
        \\      background: linear-gradient(90deg, #00d4ff, #7b2ff7);
        \\      -webkit-background-clip: text;
        \\      -webkit-text-fill-color: transparent;
        \\    }
        \\    p { color: #888; font-size: 1.2rem; }
        \\    .info {
        \\      margin-top: 2rem;
        \\      padding: 1rem 2rem;
        \\      background: rgba(255,255,255,0.05);
        \\      border-radius: 8px;
        \\      font-family: monospace;
        \\    }
        \\  </style>
        \\</head>
        \\<body>
        \\  <h1>Hello, Ziew!</h1>
        \\  <p>Lightweight desktop apps with native webviews</p>
        \\  <div class="info">
        \\    <p>Platform: <span id="platform">loading...</span></p>
        \\    <p>Version: <span id="version">loading...</span></p>
        \\  </div>
        \\  <script>
        \\    document.getElementById('platform').textContent = ziew.platform;
        \\    document.getElementById('version').textContent = ziew.version;
        \\  </script>
        \\</body>
        \\</html>
    );

    // Run the event loop
    app.run();
}
