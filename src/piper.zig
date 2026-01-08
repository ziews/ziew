//! Piper TTS - Text-to-speech via Piper CLI
//!
//! Uses the prebuilt Piper binary for local TTS synthesis
//! Voices are stored in ~/.ziew/voices/

const std = @import("std");
const utils = @import("utils.zig");

pub const PiperError = error{
    PiperNotFound,
    VoiceNotFound,
    SynthesisFailed,
    OutOfMemory,
};

/// Piper text-to-speech instance
pub const Piper = struct {
    allocator: std.mem.Allocator,
    piper_path: []const u8,
    voice_path: ?[]const u8,

    const Self = @This();

    /// Initialize Piper with auto-detection
    pub fn init(allocator: std.mem.Allocator) !Self {
        const piper_path = try getPiperPath(allocator);

        // Check if piper exists
        std.fs.accessAbsolute(piper_path, .{}) catch {
            allocator.free(piper_path);
            return PiperError.PiperNotFound;
        };

        // Try to find a default voice
        const voice_path = findDefaultVoice(allocator) catch null;

        return Self{
            .allocator = allocator,
            .piper_path = piper_path,
            .voice_path = voice_path,
        };
    }

    /// Synthesize text to WAV audio bytes
    pub fn speak(self: *Self, text: []const u8) ![]const u8 {
        const voice = self.voice_path orelse return PiperError.VoiceNotFound;

        // Create temp output file
        var tmp_path_buf: [256]u8 = undefined;
        const tmp_path = std.fmt.bufPrint(&tmp_path_buf, "/tmp/piper_{d}.wav", .{std.time.milliTimestamp()}) catch {
            return PiperError.OutOfMemory;
        };

        // Build command
        var child = std.process.Child.init(&[_][]const u8{
            self.piper_path,
            "--model",
            voice,
            "--output_file",
            tmp_path,
        }, self.allocator);

        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Ignore;
        child.stderr_behavior = .Ignore;

        child.spawn() catch {
            return PiperError.SynthesisFailed;
        };

        // Write text to stdin
        if (child.stdin) |stdin| {
            stdin.writeAll(text) catch {};
            stdin.close();
            child.stdin = null;
        }

        // Wait for completion
        const result = child.wait() catch {
            return PiperError.SynthesisFailed;
        };

        if (result.Exited != 0) {
            return PiperError.SynthesisFailed;
        }

        // Read output file
        const file = std.fs.openFileAbsolute(tmp_path, .{}) catch {
            return PiperError.SynthesisFailed;
        };
        defer file.close();

        const wav_data = file.readToEndAlloc(self.allocator, 10 * 1024 * 1024) catch {
            return PiperError.OutOfMemory;
        };

        // Clean up temp file
        std.fs.deleteFileAbsolute(tmp_path) catch {};

        return wav_data;
    }

    /// List available voices
    pub fn listVoices(self: *Self) ![][]const u8 {
        const voices_dir = try getVoicesDir(self.allocator);
        defer self.allocator.free(voices_dir);

        var voices = std.ArrayList([]const u8).init(self.allocator);
        errdefer {
            for (voices.items) |v| self.allocator.free(v);
            voices.deinit();
        }

        var dir = std.fs.openDirAbsolute(voices_dir, .{ .iterate = true }) catch {
            return voices.toOwnedSlice() catch return PiperError.OutOfMemory;
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".onnx") and
                !std.mem.endsWith(u8, entry.name, ".onnx.json"))
            {
                // Extract voice name (remove .onnx extension)
                const name_len = entry.name.len - 5;
                const voice_name = try self.allocator.dupe(u8, entry.name[0..name_len]);
                try voices.append(voice_name);
            }
        }

        return voices.toOwnedSlice() catch return PiperError.OutOfMemory;
    }

    /// Set the voice to use
    pub fn setVoice(self: *Self, voice_name: []const u8) !void {
        const voices_dir = try getVoicesDir(self.allocator);
        defer self.allocator.free(voices_dir);

        const voice_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}.onnx", .{ voices_dir, voice_name });

        // Check if voice exists
        std.fs.accessAbsolute(voice_path, .{}) catch {
            self.allocator.free(voice_path);
            return PiperError.VoiceNotFound;
        };

        if (self.voice_path) |old| {
            self.allocator.free(old);
        }
        self.voice_path = voice_path;
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.allocator.free(self.piper_path);
        if (self.voice_path) |v| {
            self.allocator.free(v);
        }
    }
};

/// Get the Piper binary path
pub fn getPiperPath(allocator: std.mem.Allocator) ![]const u8 {
    const ziew_dir = try utils.getZiewDir(allocator);
    defer allocator.free(ziew_dir);
    const bin_dir = try utils.joinPath(allocator, ziew_dir, "bin");
    defer allocator.free(bin_dir);
    const piper_dir = try utils.joinPath(allocator, bin_dir, "piper");
    defer allocator.free(piper_dir);
    return utils.joinPath(allocator, piper_dir, "piper");
}

/// Get the voices directory path
pub fn getVoicesDir(allocator: std.mem.Allocator) ![]const u8 {
    const ziew_dir = try utils.getZiewDir(allocator);
    defer allocator.free(ziew_dir);
    return utils.joinPath(allocator, ziew_dir, "voices");
}

/// Find a default voice
pub fn findDefaultVoice(allocator: std.mem.Allocator) !?[]const u8 {
    const voices_dir = try getVoicesDir(allocator);
    defer allocator.free(voices_dir);

    var dir = std.fs.openDirAbsolute(voices_dir, .{ .iterate = true }) catch {
        return null;
    };
    defer dir.close();

    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".onnx") and
            !std.mem.endsWith(u8, entry.name, ".onnx.json"))
        {
            return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ voices_dir, entry.name });
        }
    }

    return null;
}
