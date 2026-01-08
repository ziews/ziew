//! Piper Bridge - Connects Piper TTS to webview
//!
//! Provides native bindings for ziew.ai.speak() and ziew.ai.voices()

const std = @import("std");
const webview = @import("webview.zig");
const piper = @import("piper.zig");

/// Context for Piper bridge callbacks
pub const PiperBridge = struct {
    allocator: std.mem.Allocator,
    piper_instance: ?*piper.Piper,
    window: webview.Window,

    const Self = @This();

    /// Initialize Piper bridge with auto-detection
    pub fn initAuto(allocator: std.mem.Allocator, window: webview.Window) !Self {
        var bridge = Self{
            .allocator = allocator,
            .piper_instance = null,
            .window = window,
        };

        // Try to init piper
        const instance = allocator.create(piper.Piper) catch null;
        if (instance) |inst| {
            inst.* = piper.Piper.init(allocator) catch {
                allocator.destroy(inst);
                std.debug.print("[piper] Piper not found or failed to init\n", .{});
                return bridge;
            };
            bridge.piper_instance = inst;
            std.debug.print("[piper] Piper initialized\n", .{});
            if (inst.voice_path) |voice| {
                std.debug.print("[piper] Default voice: {s}\n", .{voice});
            }
        }

        return bridge;
    }

    /// Bind all native functions to the webview
    pub fn bind(self: *Self) !void {
        try self.window.bind("__ziew_ai_speak", speakCallback, @ptrCast(self));
        try self.window.bind("__ziew_ai_voices", voicesCallback, @ptrCast(self));
        try self.window.bind("__ziew_ai_set_voice", setVoiceCallback, @ptrCast(self));
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        if (self.piper_instance) |instance| {
            instance.deinit();
            self.allocator.destroy(instance);
        }
    }

    /// Callback for ziew.ai.speak()
    fn speakCallback(seq: [*c]const u8, req: [*c]const u8, arg: ?*anyopaque) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(arg));
        self.handleSpeak(seq, req) catch |err| {
            self.returnError(seq, err);
        };
    }

    fn handleSpeak(self: *Self, seq: [*c]const u8, req: [*c]const u8) !void {
        _ = seq;
        const req_slice = std.mem.span(req);

        // Parse JSON request
        const outer = std.json.parseFromSlice(std.json.Value, self.allocator, req_slice, .{}) catch {
            return;
        };
        defer outer.deinit();

        const args_array = outer.value.array;
        if (args_array.items.len == 0) return;

        const json_str = switch (args_array.items[0]) {
            .string => |s| s,
            else => return,
        };

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{}) catch {
            return;
        };
        defer parsed.deinit();

        const root = parsed.value.object;

        // Get request ID
        const id = root.get("id") orelse return;
        const id_str = switch (id) {
            .string => |s| s,
            else => return,
        };

        // Get text to speak
        const text_val = root.get("text") orelse {
            self.rejectWithId(id_str, "Missing text");
            return;
        };
        const text = switch (text_val) {
            .string => |s| s,
            else => {
                self.rejectWithId(id_str, "Invalid text");
                return;
            },
        };

        // Check if piper is loaded
        const instance = self.piper_instance orelse {
            self.rejectWithId(id_str, "Piper not available");
            return;
        };

        // Synthesize speech
        const wav_data = instance.speak(text) catch |err| {
            const msg = switch (err) {
                error.VoiceNotFound => "No voice selected",
                error.SynthesisFailed => "Speech synthesis failed",
                error.OutOfMemory => "Out of memory",
                else => "TTS error",
            };
            self.rejectWithId(id_str, msg);
            return;
        };
        defer self.allocator.free(wav_data);

        // Encode as base64
        const encoder = std.base64.standard.Encoder;
        const encoded_len = encoder.calcSize(wav_data.len);
        const encoded = self.allocator.alloc(u8, encoded_len) catch {
            self.rejectWithId(id_str, "Out of memory");
            return;
        };
        defer self.allocator.free(encoded);

        _ = encoder.encode(encoded, wav_data);

        // Return as data URL
        const data_url = std.fmt.allocPrint(
            self.allocator,
            "data:audio/wav;base64,{s}",
            .{encoded},
        ) catch {
            self.rejectWithId(id_str, "Out of memory");
            return;
        };
        defer self.allocator.free(data_url);

        self.resolveWithId(id_str, data_url);
    }

    /// Callback for ziew.ai.voices()
    fn voicesCallback(seq: [*c]const u8, req: [*c]const u8, arg: ?*anyopaque) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(arg));
        self.handleVoices(seq, req) catch |err| {
            self.returnError(seq, err);
        };
    }

    fn handleVoices(self: *Self, seq: [*c]const u8, req: [*c]const u8) !void {
        _ = seq;
        const req_slice = std.mem.span(req);

        // Parse JSON request
        const outer = std.json.parseFromSlice(std.json.Value, self.allocator, req_slice, .{}) catch {
            return;
        };
        defer outer.deinit();

        const args_array = outer.value.array;
        if (args_array.items.len == 0) return;

        const json_str = switch (args_array.items[0]) {
            .string => |s| s,
            else => return,
        };

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{}) catch {
            return;
        };
        defer parsed.deinit();

        const root = parsed.value.object;
        const id = root.get("id") orelse return;
        const id_str = switch (id) {
            .string => |s| s,
            else => return,
        };

        const instance = self.piper_instance orelse {
            self.resolveJsonWithId(id_str, "[]");
            return;
        };

        // List voices
        const voices = instance.listVoices() catch {
            self.resolveJsonWithId(id_str, "[]");
            return;
        };
        defer {
            for (voices) |v| self.allocator.free(v);
            self.allocator.free(voices);
        }

        // Build JSON array
        var json = std.ArrayList(u8).init(self.allocator);
        defer json.deinit();

        try json.appendSlice("[");
        for (voices, 0..) |voice, i| {
            if (i > 0) try json.appendSlice(",");
            try json.appendSlice("\"");
            try json.appendSlice(voice);
            try json.appendSlice("\"");
        }
        try json.appendSlice("]");

        self.resolveJsonWithId(id_str, json.items);
    }

    /// Callback for ziew.ai.setVoice()
    fn setVoiceCallback(seq: [*c]const u8, req: [*c]const u8, arg: ?*anyopaque) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(arg));
        self.handleSetVoice(seq, req) catch |err| {
            self.returnError(seq, err);
        };
    }

    fn handleSetVoice(self: *Self, seq: [*c]const u8, req: [*c]const u8) !void {
        _ = seq;
        const req_slice = std.mem.span(req);

        const outer = std.json.parseFromSlice(std.json.Value, self.allocator, req_slice, .{}) catch {
            return;
        };
        defer outer.deinit();

        const args_array = outer.value.array;
        if (args_array.items.len == 0) return;

        const json_str = switch (args_array.items[0]) {
            .string => |s| s,
            else => return,
        };

        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, json_str, .{}) catch {
            return;
        };
        defer parsed.deinit();

        const root = parsed.value.object;
        const id = root.get("id") orelse return;
        const id_str = switch (id) {
            .string => |s| s,
            else => return,
        };

        const voice_val = root.get("voice") orelse {
            self.rejectWithId(id_str, "Missing voice name");
            return;
        };
        const voice_name = switch (voice_val) {
            .string => |s| s,
            else => {
                self.rejectWithId(id_str, "Invalid voice name");
                return;
            },
        };

        const instance = self.piper_instance orelse {
            self.rejectWithId(id_str, "Piper not available");
            return;
        };

        instance.setVoice(voice_name) catch |err| {
            const msg = switch (err) {
                error.VoiceNotFound => "Voice not found",
                else => "Failed to set voice",
            };
            self.rejectWithId(id_str, msg);
            return;
        };

        self.resolveWithId(id_str, "true");
    }

    /// Helper: resolve a promise with result
    fn resolveWithId(self: *Self, id: []const u8, result: []const u8) void {
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

    /// Helper: resolve with JSON (no string escaping)
    fn resolveJsonWithId(self: *Self, id: []const u8, json_result: []const u8) void {
        const js = std.fmt.allocPrintZ(
            self.allocator,
            "ziew._resolve(\"{s}\", {s})",
            .{ id, json_result },
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

    /// Helper: return generic error
    fn returnError(self: *Self, seq: [*c]const u8, err: anyerror) void {
        const seq_slice = std.mem.span(seq);
        const msg = std.fmt.allocPrintZ(self.allocator, "\"Error: {any}\"", .{err}) catch return;
        defer self.allocator.free(msg);

        const seq_z = self.allocator.dupeZ(u8, seq_slice) catch return;
        defer self.allocator.free(seq_z);

        self.window.returnResult(seq_z, 1, msg) catch {};
    }
};
