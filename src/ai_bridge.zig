//! AI Bridge - Connects AI module to webview
//!
//! Provides native bindings for ziew.ai.complete() and ziew.ai.stream()

const std = @import("std");
const webview = @import("webview.zig");
const ai = @import("ai.zig");

/// Context for AI bridge callbacks
pub const AiBridge = struct {
    allocator: std.mem.Allocator,
    ai_instance: ?*ai.Ai,
    window: webview.Window,

    const Self = @This();

    /// Initialize AI bridge with a loaded model
    pub fn init(allocator: std.mem.Allocator, window: webview.Window, model_path: []const u8) !Self {
        const ai_instance = try allocator.create(ai.Ai);
        ai_instance.* = try ai.Ai.init(allocator, model_path);

        const bridge = Self{
            .allocator = allocator,
            .ai_instance = ai_instance,
            .window = window,
        };

        // Bind the native functions
        try window.bind("__ziew_ai_complete", completeCallback, @ptrCast(&bridge));
        try window.bind("__ziew_ai_stream", streamCallback, @ptrCast(&bridge));

        return bridge;
    }

    /// Initialize AI bridge without a model (for lazy loading)
    pub fn initLazy(allocator: std.mem.Allocator, window: webview.Window) !Self {
        const bridge = Self{
            .allocator = allocator,
            .ai_instance = null,
            .window = window,
        };

        // Bind the native functions
        try window.bind("__ziew_ai_complete", completeCallback, @ptrCast(&bridge));
        try window.bind("__ziew_ai_stream", streamCallback, @ptrCast(&bridge));

        return bridge;
    }

    /// Load a model (for lazy initialization)
    pub fn loadModel(self: *Self, model_path: []const u8) !void {
        if (self.ai_instance) |instance| {
            instance.deinit();
            self.allocator.destroy(instance);
        }

        const ai_instance = try self.allocator.create(ai.Ai);
        ai_instance.* = try ai.Ai.init(self.allocator, model_path);
        self.ai_instance = ai_instance;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        if (self.ai_instance) |instance| {
            instance.deinit();
            self.allocator.destroy(instance);
        }
    }

    /// Callback for ziew.ai.complete()
    fn completeCallback(seq: [*c]const u8, req: [*c]const u8, arg: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(arg));
        self.handleComplete(seq, req) catch |err| {
            self.returnError(seq, err);
        };
    }

    fn handleComplete(self: *Self, seq: [*c]const u8, req: [*c]const u8) !void {
        const req_slice = std.mem.span(req);

        // Parse JSON request
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, req_slice, .{}) catch {
            return self.returnJsonError(seq, "Invalid JSON request");
        };
        defer parsed.deinit();

        const root = parsed.value.object;

        // Get request ID
        const id = root.get("id") orelse return self.returnJsonError(seq, "Missing id");
        const id_str = switch (id) {
            .string => |s| s,
            else => return self.returnJsonError(seq, "Invalid id"),
        };

        // Get prompt
        const prompt_val = root.get("prompt") orelse {
            return self.rejectWithId(id_str, "Missing prompt");
        };
        const prompt = switch (prompt_val) {
            .string => |s| s,
            else => return self.rejectWithId(id_str, "Invalid prompt"),
        };

        // Get options
        const max_tokens: u32 = if (root.get("maxTokens")) |v| switch (v) {
            .integer => |i| @intCast(i),
            else => 256,
        } else 256;

        // Check if AI is loaded
        const ai_instance = self.ai_instance orelse {
            return self.rejectWithId(id_str, "No model loaded - call ziew.ai.load() first");
        };

        // Generate completion
        const result = ai_instance.complete(prompt, max_tokens) catch |err| {
            const msg = switch (err) {
                error.TokenizeFailed => "Tokenization failed",
                error.DecodeFailed => "Decode failed",
                error.OutOfMemory => "Out of memory",
                else => "Generation failed",
            };
            return self.rejectWithId(id_str, msg);
        };
        defer self.allocator.free(result);

        // Return result
        self.resolveWithId(id_str, result);
    }

    /// Callback for ziew.ai.stream()
    fn streamCallback(seq: [*c]const u8, req: [*c]const u8, arg: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(arg));
        self.handleStream(seq, req) catch |err| {
            self.returnError(seq, err);
        };
    }

    fn handleStream(self: *Self, seq: [*c]const u8, req: [*c]const u8) !void {
        _ = seq;
        const req_slice = std.mem.span(req);

        // Parse JSON request
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, req_slice, .{}) catch {
            return; // Can't return error for stream
        };
        defer parsed.deinit();

        const root = parsed.value.object;

        // Get request ID
        const id = root.get("id") orelse return;
        const id_str = switch (id) {
            .string => |s| s,
            else => return,
        };

        // Get prompt
        const prompt_val = root.get("prompt") orelse {
            self.streamError(id_str, "Missing prompt");
            return;
        };
        const prompt = switch (prompt_val) {
            .string => |s| s,
            else => {
                self.streamError(id_str, "Invalid prompt");
                return;
            },
        };

        // Get options
        const max_tokens: u32 = if (root.get("maxTokens")) |v| switch (v) {
            .integer => |i| @intCast(i),
            else => 256,
        } else 256;

        // Check if AI is loaded
        const ai_instance = self.ai_instance orelse {
            self.streamError(id_str, "No model loaded");
            return;
        };

        // Create streaming context - need to copy id since parsed will be freed
        const id_copy = self.allocator.dupe(u8, id_str) catch {
            self.streamError(id_str, "Out of memory");
            return;
        };
        defer self.allocator.free(id_copy);

        const StreamCtx = struct {
            bridge: *Self,
            id: []const u8,
        };
        var stream_ctx = StreamCtx{ .bridge = self, .id = id_copy };

        // Stream tokens
        ai_instance.stream(prompt, max_tokens, streamTokenCallback, @ptrCast(&stream_ctx)) catch {
            self.streamError(id_copy, "Stream failed");
            return;
        };

        // End stream
        self.streamEnd(id_copy);
    }

    /// Callback for streaming tokens
    fn streamTokenCallback(token: []const u8, ctx: ?*anyopaque) void {
        const StreamCtx = struct {
            bridge: *Self,
            id: []const u8,
        };
        const stream_ctx: *StreamCtx = @ptrCast(@alignCast(ctx));
        stream_ctx.bridge.streamPush(stream_ctx.id, token);
    }

    /// Helper: resolve a promise with result
    fn resolveWithId(self: *Self, id: []const u8, result: []const u8) void {
        // Escape the result for JavaScript string
        var escaped = std.ArrayList(u8).init(self.allocator);
        defer escaped.deinit();

        for (result) |ch| {
            switch (ch) {
                '\\' => escaped.appendSlice("\\\\") catch return,
                '"' => escaped.appendSlice("\\\"") catch return,
                '\n' => escaped.appendSlice("\\n") catch return,
                '\r' => escaped.appendSlice("\\r") catch return,
                '\t' => escaped.appendSlice("\\t") catch return,
                else => escaped.append(ch) catch return,
            }
        }

        const js = std.fmt.allocPrintZ(
            self.allocator,
            "ziew._resolve(\"{s}\", \"{s}\")",
            .{ id, escaped.items },
        ) catch return;
        defer self.allocator.free(js);

        self.window.eval(js) catch {};
    }

    /// Helper: reject a promise with error
    fn rejectWithId(self: *Self, id: []const u8, err_msg: []const u8) void {
        const js = std.fmt.allocPrintZ(
            self.allocator,
            "ziew._reject(\"{s}\", \"{s}\")",
            .{ id, err_msg },
        ) catch return;
        defer self.allocator.free(js);

        self.window.eval(js) catch {};
    }

    /// Helper: push token to stream
    fn streamPush(self: *Self, id: []const u8, token: []const u8) void {
        // Escape the token for JavaScript string
        var escaped = std.ArrayList(u8).init(self.allocator);
        defer escaped.deinit();

        for (token) |ch| {
            switch (ch) {
                '\\' => escaped.appendSlice("\\\\") catch return,
                '"' => escaped.appendSlice("\\\"") catch return,
                '\n' => escaped.appendSlice("\\n") catch return,
                '\r' => escaped.appendSlice("\\r") catch return,
                '\t' => escaped.appendSlice("\\t") catch return,
                else => escaped.append(ch) catch return,
            }
        }

        const js = std.fmt.allocPrintZ(
            self.allocator,
            "ziew._streamPush(\"{s}\", \"{s}\")",
            .{ id, escaped.items },
        ) catch return;
        defer self.allocator.free(js);

        self.window.eval(js) catch {};
    }

    /// Helper: end a stream
    fn streamEnd(self: *Self, id: []const u8) void {
        const js = std.fmt.allocPrintZ(
            self.allocator,
            "ziew._streamEnd(\"{s}\")",
            .{id},
        ) catch return;
        defer self.allocator.free(js);

        self.window.eval(js) catch {};
    }

    /// Helper: send stream error
    fn streamError(self: *Self, id: []const u8, err_msg: []const u8) void {
        // Set error on stream object
        const js = std.fmt.allocPrintZ(
            self.allocator,
            "(() => {{ const s = window.ziew._streams?.get(\"{s}\"); if (s) {{ s.error = \"{s}\"; s.done = true; if (s.resolver) s.resolver(); }} }})()",
            .{ id, err_msg },
        ) catch return;
        defer self.allocator.free(js);

        self.window.eval(js) catch {};
    }

    /// Helper: return generic error
    fn returnError(self: *Self, seq: [*c]const u8, err: anyerror) void {
        const seq_slice = std.mem.span(seq);
        const msg = std.fmt.allocPrintZ(self.allocator, "\"Error: {any}\"", .{err}) catch return;
        defer self.allocator.free(msg);

        const seq_z = self.allocator.dupeZ(u8, seq_slice) catch return;
        defer self.allocator.free(seq_z);

        self.window.returnResult(seq_z, 1, msg) catch {};
    }

    /// Helper: return JSON error
    fn returnJsonError(self: *Self, seq: [*c]const u8, msg: []const u8) void {
        const seq_slice = std.mem.span(seq);
        const err_json = std.fmt.allocPrintZ(self.allocator, "\"{s}\"", .{msg}) catch return;
        defer self.allocator.free(err_json);

        const seq_z = self.allocator.dupeZ(u8, seq_slice) catch return;
        defer self.allocator.free(seq_z);

        self.window.returnResult(seq_z, 1, err_json) catch {};
    }
};
