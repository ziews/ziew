//! AI Example - Local LLM inference with Ziew
//!
//! Demonstrates text generation using llama.cpp.
//! Build with: zig build -Dai=true ai
//!
//! Models are auto-detected from ~/.ziew/models/
//! Or pass a specific model path: ai-example /path/to/model.gguf

const std = @import("std");
const ziew = @import("ziew");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get model path from args or auto-detect
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const model_path: []const u8 = if (args.len > 1)
        args[1]
    else blk: {
        // Try to find a model in ~/.ziew/models/
        std.debug.print("[ai] Looking for models in ~/.ziew/models/\n", .{});

        // Ensure directory exists
        ziew.ai.ensureModelsDir(allocator) catch {};

        // Find default model
        if (try ziew.ai.findDefaultModel(allocator)) |path| {
            std.debug.print("[ai] Found model: {s}\n", .{path});
            break :blk path;
        } else {
            std.debug.print("[ai] No models found in ~/.ziew/models/\n", .{});
            std.debug.print("[ai] Download a .gguf model from HuggingFace:\n", .{});
            std.debug.print("[ai]   https://huggingface.co/models?search=gguf\n", .{});
            std.debug.print("[ai] Or specify a path: ai-example /path/to/model.gguf\n", .{});
            return;
        }
    };
    defer if (args.len <= 1) allocator.free(model_path);

    std.debug.print("[ai] Loading model: {s}\n", .{model_path});

    // Initialize AI
    var ai = ziew.ai.Ai.init(allocator, model_path) catch |err| {
        std.debug.print("[ai] Failed to load model: {any}\n", .{err});
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
