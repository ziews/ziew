//! Chatbot Example - Local AI chatbot with text-to-speech
//!
//! Demonstrates a chat interface with:
//! - Streaming text generation via ziew.ai.stream()
//! - Text-to-speech via ziew.ai.speak() (piper)
//!
//! Build with: zig build -Dai=true -Dpiper=true chatbot
//!
//! Models are auto-detected from:
//! - LLM: ~/.ziew/models/*.gguf
//! - Piper voices: ~/.ziew/voices/*.onnx

const std = @import("std");
const ziew = @import("ziew");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create the app window
    var app = try ziew.App.init(allocator, .{
        .title = "Ziew Voice Chatbot",
        .width = 650,
        .height = 550,
        .debug = true,
    });
    defer app.deinit();

    // Initialize AI bridge (LLM)
    var ai_bridge = try ziew.ai_bridge.AiBridge.initAuto(allocator, app.window);
    defer ai_bridge.deinit();
    try ai_bridge.bind();

    // Initialize Piper bridge (TTS)
    var piper_opt: ?ziew.piper_bridge.PiperBridge = ziew.piper_bridge.PiperBridge.initAuto(allocator, app.window) catch |err| blk: {
        std.debug.print("[chatbot] Piper init failed: {}\n", .{err});
        break :blk null;
    };
    defer if (piper_opt) |*pb| pb.deinit();
    if (piper_opt) |*pb| {
        pb.bind() catch {};
    }

    // Load the HTML file
    // When running from project root: zig build chatbot && ./zig-out/bin/chatbot
    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch ".";
    const html_path = std.fmt.allocPrintZ(allocator, "file://{s}/examples/chatbot/index.html", .{cwd}) catch {
        std.debug.print("[chatbot] Failed to build HTML path\n", .{});
        return;
    };
    defer allocator.free(html_path);

    std.debug.print("[chatbot] Loading: {s}\n", .{html_path});
    app.navigate(html_path);

    // Run the app
    app.run();
}
