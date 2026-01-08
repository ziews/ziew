//! AI Example - Local LLM inference with Ziew
//!
//! Demonstrates text generation using llama.cpp.
//! Build with: zig build -Dai=true ai
//!
//! Requires a GGUF model file. Download one from:
//! https://huggingface.co/models?search=gguf

const std = @import("std");
const ziew = @import("ziew");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get model path from args or use default
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const model_path = if (args.len > 1) args[1] else blk: {
        const default = try ziew.ai.getDefaultModelPath(allocator);
        std.debug.print("[ai] No model specified, checking default: {s}\n", .{default});
        break :blk default;
    };

    std.debug.print("[ai] Loading model: {s}\n", .{model_path});

    // Initialize AI
    var ai = ziew.ai.Ai.init(allocator, model_path) catch |err| {
        std.debug.print("[ai] Failed to load model: {any}\n", .{err});
        std.debug.print("[ai] Usage: ai-example <path-to-model.gguf>\n", .{});
        return;
    };
    defer ai.deinit();

    std.debug.print("[ai] Model loaded successfully!\n", .{});

    // Example: complete a prompt
    const prompt = "Once upon a time";
    std.debug.print("[ai] Prompt: {s}\n", .{prompt});
    std.debug.print("[ai] Generating...\n\n", .{});

    // Streaming output
    ai.stream(prompt, 100, printToken, null) catch |err| {
        std.debug.print("\n[ai] Generation error: {any}\n", .{err});
        return;
    };

    std.debug.print("\n\n[ai] Done!\n", .{});
}

fn printToken(token: []const u8, _: ?*anyopaque) void {
    std.io.getStdOut().writer().writeAll(token) catch {};
}
