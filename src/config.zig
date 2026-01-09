//! Ziew Configuration
//!
//! Handles reading and writing ziew.zon project configuration files.
//!
//! Example ziew.zon:
//! .{
//!     .name = "myapp",
//!     .version = "0.1.0",
//!     .plugins = .{ "sqlite", "notify" },
//! }

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Config = struct {
    allocator: Allocator,
    name: []const u8,
    version: []const u8,
    plugins: []const []const u8,
    name_allocated: bool = false,
    version_allocated: bool = false,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        return Self{
            .allocator = allocator,
            .name = "app",
            .version = "0.1.0",
            .plugins = &.{},
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.name_allocated) {
            self.allocator.free(self.name);
        }
        if (self.version_allocated) {
            self.allocator.free(self.version);
        }
        if (self.plugins.len > 0) {
            for (self.plugins) |plugin_name| {
                self.allocator.free(plugin_name);
            }
            self.allocator.free(self.plugins);
        }
    }

    /// Load config from ziew.zon in current directory
    pub fn load(allocator: Allocator) !Self {
        const content = std.fs.cwd().readFileAlloc(allocator, "ziew.zon", 1024 * 64) catch |err| {
            if (err == error.FileNotFound) {
                return Self.init(allocator);
            }
            return err;
        };
        defer allocator.free(content);

        return Self.parse(allocator, content);
    }

    /// Parse config from ZON string
    pub fn parse(allocator: Allocator, zon_content: []const u8) !Self {
        var config = Self.init(allocator);

        // Parse .name = "..."
        if (findZonStringValue(zon_content, ".name")) |name| {
            config.name = try allocator.dupe(u8, name);
            config.name_allocated = true;
        }

        // Parse .version = "..."
        if (findZonStringValue(zon_content, ".version")) |version| {
            config.version = try allocator.dupe(u8, version);
            config.version_allocated = true;
        }

        // Parse .plugins = .{ ... }
        config.plugins = try parseZonPluginsArray(allocator, zon_content);

        return config;
    }

    /// Save config to ziew.zon
    pub fn save(self: *const Self) !void {
        var file = try std.fs.cwd().createFile("ziew.zon", .{});
        defer file.close();

        const writer = file.writer();

        try writer.writeAll(".{\n");
        try writer.print("    .name = \"{s}\",\n", .{self.name});
        try writer.print("    .version = \"{s}\",\n", .{self.version});
        try writer.writeAll("    .plugins = .{");

        if (self.plugins.len > 0) {
            try writer.writeAll(" ");
            for (self.plugins, 0..) |plugin_name, i| {
                if (i > 0) try writer.writeAll(", ");
                try writer.print("\"{s}\"", .{plugin_name});
            }
            try writer.writeAll(" ");
        }

        try writer.writeAll("},\n}\n");
    }

    /// Check if a plugin is enabled
    pub fn hasPlugin(self: *const Self, name: []const u8) bool {
        for (self.plugins) |plugin_name| {
            if (std.mem.eql(u8, plugin_name, name)) return true;
        }
        return false;
    }

    /// Add a plugin to the config
    pub fn addPlugin(self: *Self, name: []const u8) !void {
        // Check if already present
        if (self.hasPlugin(name)) return;

        // Create new array with one more element
        const new_plugins = try self.allocator.alloc([]const u8, self.plugins.len + 1);
        @memcpy(new_plugins[0..self.plugins.len], self.plugins);
        new_plugins[self.plugins.len] = try self.allocator.dupe(u8, name);

        // Free old array (but not the strings - they're still referenced)
        if (self.plugins.len > 0) {
            self.allocator.free(self.plugins);
        }

        self.plugins = new_plugins;
    }

    /// Remove a plugin from the config
    pub fn removePlugin(self: *Self, name: []const u8) !void {
        if (!self.hasPlugin(name)) return;

        if (self.plugins.len == 1) {
            self.allocator.free(self.plugins[0]);
            self.allocator.free(self.plugins);
            self.plugins = &.{};
            return;
        }

        const new_plugins = try self.allocator.alloc([]const u8, self.plugins.len - 1);
        var j: usize = 0;
        for (self.plugins) |plugin_name| {
            if (std.mem.eql(u8, plugin_name, name)) {
                self.allocator.free(plugin_name);
            } else {
                new_plugins[j] = plugin_name;
                j += 1;
            }
        }

        self.allocator.free(self.plugins);
        self.plugins = new_plugins;
    }

    /// Get zig build arguments for enabled plugins
    pub fn getPluginBuildArgs(self: *const Self, allocator: Allocator) ![]const []const u8 {
        if (self.plugins.len == 0) return &.{};

        const args = try allocator.alloc([]const u8, self.plugins.len);
        for (self.plugins, 0..) |plugin_name, i| {
            args[i] = try std.fmt.allocPrint(allocator, "-D{s}=true", .{plugin_name});
        }
        return args;
    }
};

/// Find a string value in ZON like: .key = "value"
fn findZonStringValue(zon: []const u8, key: []const u8) ?[]const u8 {
    // Search for the key pattern
    var pos: usize = 0;
    while (pos < zon.len) {
        const key_pos = std.mem.indexOfPos(u8, zon, pos, key) orelse return null;
        pos = key_pos + key.len;

        // Skip whitespace and =
        while (pos < zon.len and (zon[pos] == ' ' or zon[pos] == '\t' or zon[pos] == '\n' or zon[pos] == '=')) {
            pos += 1;
        }

        // Expect opening quote
        if (pos >= zon.len or zon[pos] != '"') continue;
        pos += 1;

        // Find closing quote
        const value_start = pos;
        while (pos < zon.len and zon[pos] != '"') {
            pos += 1;
        }

        return zon[value_start..pos];
    }
    return null;
}

/// Parse plugins array from ZON: .plugins = .{ "a", "b" }
fn parseZonPluginsArray(allocator: Allocator, zon: []const u8) ![]const []const u8 {
    // Find .plugins = .{
    const plugins_key = std.mem.indexOf(u8, zon, ".plugins") orelse return &.{};
    var pos = plugins_key + 8; // len of ".plugins"

    // Skip to opening .{
    while (pos + 1 < zon.len) {
        if (zon[pos] == '.' and zon[pos + 1] == '{') {
            pos += 2;
            break;
        }
        pos += 1;
    }
    if (pos >= zon.len) return &.{};

    // Find closing }
    const start_pos = pos;
    var brace_depth: usize = 1;
    while (pos < zon.len and brace_depth > 0) {
        if (zon[pos] == '{') brace_depth += 1;
        if (zon[pos] == '}') brace_depth -= 1;
        pos += 1;
    }
    const array_content = zon[start_pos .. pos - 1];

    // Count strings in array
    var count: usize = 0;
    var in_string = false;
    for (array_content) |c| {
        if (c == '"' and !in_string) {
            in_string = true;
        } else if (c == '"' and in_string) {
            in_string = false;
            count += 1;
        }
    }

    if (count == 0) return &.{};

    // Parse strings
    const plugins = try allocator.alloc([]const u8, count);
    var plugin_idx: usize = 0;
    pos = 0;

    while (pos < array_content.len and plugin_idx < count) {
        // Find opening quote
        while (pos < array_content.len and array_content[pos] != '"') {
            pos += 1;
        }
        if (pos >= array_content.len) break;
        pos += 1; // Skip opening quote

        const start = pos;
        // Find closing quote
        while (pos < array_content.len and array_content[pos] != '"') {
            pos += 1;
        }

        plugins[plugin_idx] = try allocator.dupe(u8, array_content[start..pos]);
        plugin_idx += 1;
        pos += 1; // Skip closing quote
    }

    return plugins;
}

/// Available plugins with their descriptions and dependencies
pub const PluginInfo = struct {
    name: []const u8,
    description: []const u8,
    deps: []const u8,
    category: Category,

    pub const Category = enum {
        core,
        input,
        ai,
        platform,
    };
};

pub const available_plugins = [_]PluginInfo{
    // Core
    .{ .name = "sqlite", .description = "SQLite database", .deps = "libsqlite3-dev", .category = .core },
    .{ .name = "notify", .description = "System notifications", .deps = "libnotify-dev", .category = .core },
    .{ .name = "keychain", .description = "Secure credential storage", .deps = "libsecret-1-dev", .category = .core },
    .{ .name = "lua", .description = "LuaJIT scripting", .deps = "libluajit-5.1-dev", .category = .core },
    // Input
    .{ .name = "hotkeys", .description = "Global keyboard shortcuts", .deps = "libx11-dev", .category = .input },
    .{ .name = "gamepad", .description = "Game controller input", .deps = "none", .category = .input },
    .{ .name = "serial", .description = "Serial port communication", .deps = "none", .category = .input },
    // AI
    .{ .name = "ai", .description = "Local LLM (llama.cpp)", .deps = "llama.cpp", .category = .ai },
    .{ .name = "piper", .description = "Text-to-speech", .deps = "piper CLI", .category = .ai },
    // Platform
    .{ .name = "steamworks", .description = "Steam integration", .deps = "Steamworks SDK", .category = .platform },
};

pub fn getPluginInfo(name: []const u8) ?PluginInfo {
    for (available_plugins) |info| {
        if (std.mem.eql(u8, info.name, name)) return info;
    }
    return null;
}

pub fn isValidPlugin(name: []const u8) bool {
    return getPluginInfo(name) != null;
}
