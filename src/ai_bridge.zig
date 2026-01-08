//! AI Bridge - Connects AI module to webview
//!
//! Provides native bindings for ziew.ai.complete(), ziew.ai.stream(), etc.
//! Models are auto-detected from ~/.ziew/models/

const std = @import("std");
const webview = @import("webview.zig");
const ai = @import("ai.zig");

/// Context for AI bridge callbacks
pub const AiBridge = struct {
    allocator: std.mem.Allocator,
    ai_instance: ?*ai.Ai,
    window: webview.Window,
    auto_load_attempted: bool,

    const Self = @This();

    /// Initialize AI bridge with a specific model
    pub fn init(allocator: std.mem.Allocator, window: webview.Window, model_path: []const u8) !Self {
        const ai_instance = try allocator.create(ai.Ai);
        ai_instance.* = try ai.Ai.init(allocator, model_path);

        var bridge = Self{
            .allocator = allocator,
            .ai_instance = ai_instance,
            .window = window,
            .auto_load_attempted = true,
        };

        // Bind the native functions
        try bridge.bindFunctions();

        return bridge;
    }

    /// Initialize AI bridge with auto-detection from ~/.ziew/models/
    pub fn initAuto(allocator: std.mem.Allocator, window: webview.Window) !Self {
        // Ensure models directory exists
        ai.ensureModelsDir(allocator) catch {};

        var bridge = Self{
            .allocator = allocator,
            .ai_instance = null,
            .window = window,
            .auto_load_attempted = false,
        };

        // Try to auto-load default model
        if (ai.findDefaultModel(allocator) catch null) |model_path| {
            defer allocator.free(model_path);
            std.debug.print("[ai] Auto-loading model: {s}\n", .{model_path});

            const ai_instance = allocator.create(ai.Ai) catch null;
            if (ai_instance) |instance| {
                instance.* = ai.Ai.init(allocator, model_path) catch {
                    allocator.destroy(instance);
                    std.debug.print("[ai] Failed to load model\n", .{});
                    bridge.auto_load_attempted = true;
                    try bridge.bindFunctions();
                    return bridge;
                };
                bridge.ai_instance = instance;
                std.debug.print("[ai] Model loaded successfully\n", .{});
            }
        } else {
            std.debug.print("[ai] No models found in ~/.ziew/models/\n", .{});
        }

        bridge.auto_load_attempted = true;
        try bridge.bindFunctions();
        return bridge;
    }

    /// Initialize AI bridge without loading any model (fully lazy)
    pub fn initLazy(allocator: std.mem.Allocator, window: webview.Window) !Self {
        var bridge = Self{
            .allocator = allocator,
            .ai_instance = null,
            .window = window,
            .auto_load_attempted = false,
        };

        try bridge.bindFunctions();
        return bridge;
    }

    /// Bind all native functions to the webview
    fn bindFunctions(self: *Self) !void {
        try self.window.bind("__ziew_ai_complete", completeCallback, @ptrCast(self));
        try self.window.bind("__ziew_ai_stream", streamCallback, @ptrCast(self));
        try self.window.bind("__ziew_ai_load", loadCallback, @ptrCast(self));
        try self.window.bind("__ziew_ai_models", modelsCallback, @ptrCast(self));
    }

    /// Load a model by name or path
    pub fn loadModel(self: *Self, model_name: []const u8) !void {
        // Get full path (handles both names and paths)
        const model_path = try ai.getModelPath(self.allocator, model_name);
        defer self.allocator.free(model_path);

        // Unload existing model
        if (self.ai_instance) |instance| {
            instance.deinit();
            self.allocator.destroy(instance);
            self.ai_instance = null;
        }

        // Load new model
        const ai_instance = try self.allocator.create(ai.Ai);
        ai_instance.* = try ai.Ai.init(self.allocator, model_path);
        self.ai_instance = ai_instance;
    }

    /// Try to auto-load a model if none is loaded
    fn tryAutoLoad(self: *Self) bool {
        if (self.ai_instance != null) return true;
        if (self.auto_load_attempted) return false;

        self.auto_load_attempted = true;

        if (ai.findDefaultModel(self.allocator) catch null) |model_path| {
            defer self.allocator.free(model_path);
            std.debug.print("[ai] Auto-loading model: {s}\n", .{model_path});

            const ai_instance = self.allocator.create(ai.Ai) catch return false;
            ai_instance.* = ai.Ai.init(self.allocator, model_path) catch {
                self.allocator.destroy(ai_instance);
                return false;
            };
            self.ai_instance = ai_instance;
            return true;
        }
        return false;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        if (self.ai_instance) |instance| {
            instance.deinit();
            self.allocator.destroy(instance);
        }
    }

    /// Callback for ziew.ai.load()
    fn loadCallback(seq: [*c]const u8, req: [*c]const u8, arg: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(arg));
        self.handleLoad(seq, req) catch |err| {
            self.returnError(seq, err);
        };
    }

    fn handleLoad(self: *Self, seq: [*c]const u8, req: [*c]const u8) !void {
        _ = seq;
        const req_slice = std.mem.span(req);

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, req_slice, .{}) catch {
            return;
        };
        defer parsed.deinit();

        const root = parsed.value.object;
        const id = root.get("id") orelse return;
        const id_str = switch (id) {
            .string => |s| s,
            else => return,
        };

        // Get model name (optional - if not provided, auto-load)
        const model_name = if (root.get("model")) |m| switch (m) {
            .string => |s| s,
            else => null,
        } else null;

        if (model_name) |name| {
            self.loadModel(name) catch |err| {
                const msg = switch (err) {
                    error.ModelLoadFailed => "Failed to load model",
                    error.FileNotFound => "Model not found",
                    else => "Load error",
                };
                return self.rejectWithId(id_str, msg);
            };
            self.resolveWithId(id_str, "true");
        } else {
            // Auto-load
            if (self.tryAutoLoad()) {
                self.resolveWithId(id_str, "true");
            } else {
                self.rejectWithId(id_str, "No models found in ~/.ziew/models/");
            }
        }
    }

    /// Callback for ziew.ai.models()
    fn modelsCallback(seq: [*c]const u8, req: [*c]const u8, arg: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(arg));
        self.handleModels(seq, req) catch |err| {
            self.returnError(seq, err);
        };
    }

    fn handleModels(self: *Self, seq: [*c]const u8, req: [*c]const u8) !void {
        _ = seq;
        const req_slice = std.mem.span(req);

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, req_slice, .{}) catch {
            return;
        };
        defer parsed.deinit();

        const root = parsed.value.object;
        const id = root.get("id") orelse return;
        const id_str = switch (id) {
            .string => |s| s,
            else => return,
        };

        // List models
        const models = ai.listModels(self.allocator) catch {
            return self.rejectWithId(id_str, "Failed to list models");
        };
        defer {
            for (models) |m| self.allocator.free(m);
            self.allocator.free(models);
        }

        // Build JSON array
        var json = std.ArrayList(u8).init(self.allocator);
        defer json.deinit();

        try json.appendSlice("[");
        for (models, 0..) |model, i| {
            if (i > 0) try json.appendSlice(",");
            try json.appendSlice("\\\"");
            try json.appendSlice(model);
            try json.appendSlice("\\\"");
        }
        try json.appendSlice("]");

        self.resolveJsonWithId(id_str, json.items);
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

        // Try auto-load if no model is loaded
        _ = self.tryAutoLoad();

        // Check if AI is loaded
        const ai_instance = self.ai_instance orelse {
            return self.rejectWithId(id_str, "No model found. Place a .gguf file in ~/.ziew/models/");
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

        // Try auto-load if no model is loaded
        _ = self.tryAutoLoad();

        // Check if AI is loaded
        const ai_instance = self.ai_instance orelse {
            self.streamError(id_str, "No model found. Place a .gguf file in ~/.ziew/models/");
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

    /// Helper: resolve a promise with JSON result (no extra escaping)
    fn resolveJsonWithId(self: *Self, id: []const u8, json_result: []const u8) void {
        const js = std.fmt.allocPrintZ(
            self.allocator,
            "ziew._resolve(\"{s}\", {s})",
            .{ id, json_result },
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
