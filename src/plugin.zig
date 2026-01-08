//! Plugin System - Extensible architecture for styles, native bindings, and tools
//!
//! Plugin types:
//! - style: CSS frameworks (pico, water, simple)
//! - native: Native bindings (lua, sqlite)
//! - ai: AI model integrations (llama, whisper)
//! - tool: CLI extensions
//!
//! Plugin sources:
//! - "pico"              → official: github.com/ziews/plugins/pico
//! - "someuser/plugin"   → third-party: github.com/someuser/plugin
//! - "https://..."       → direct URL

const std = @import("std");
const fs = std.fs;
const json = std.json;
const utils = @import("utils.zig");

/// Official plugins repo base URL
pub const OFFICIAL_REPO = "https://raw.githubusercontent.com/ziews/plugins/main";

/// GitHub base URL for third-party plugins
pub const GITHUB_BASE = "https://raw.githubusercontent.com";

/// Plugin metadata from plugin.json
pub const PluginMeta = struct {
    name: []const u8,
    version: []const u8,
    plugin_type: PluginType,
    description: []const u8 = "",
    files: []const []const u8 = &.{},
    /// HTML to inject (e.g., <link rel="stylesheet" ...>)
    inject_html: ?[]const u8 = null,
    /// JS to inject on page load
    inject_js: ?[]const u8 = null,
};

pub const PluginType = enum {
    style,
    native,
    ai,
    tool,

    pub fn fromString(s: []const u8) ?PluginType {
        if (std.mem.eql(u8, s, "style")) return .style;
        if (std.mem.eql(u8, s, "native")) return .native;
        if (std.mem.eql(u8, s, "ai")) return .ai;
        if (std.mem.eql(u8, s, "tool")) return .tool;
        return null;
    }
};

/// Built-in plugin registry with download URLs
pub const BuiltinPlugin = struct {
    name: []const u8,
    url: []const u8,
    plugin_type: PluginType,
    description: []const u8,
};

/// Plugin source type - determines where to fetch from
pub const PluginSource = struct {
    kind: Kind,
    name: []const u8,
    owner: ?[]const u8 = null, // GitHub user/org for third-party
    url: ?[]const u8 = null, // Direct URL

    pub const Kind = enum {
        official, // Short name like "lua" → ziews/plugins
        third_party, // "user/repo" format → github.com/user/repo
        direct_url, // Full URL
    };

    /// Parse a plugin specifier into a source
    /// Examples:
    ///   "lua"            → official (ziews/plugins/lua)
    ///   "someuser/theme" → third_party (github.com/someuser/theme)
    ///   "https://..."    → direct_url
    pub fn parse(spec: []const u8) PluginSource {
        // Check for direct URL
        if (std.mem.startsWith(u8, spec, "https://") or std.mem.startsWith(u8, spec, "http://")) {
            return .{
                .kind = .direct_url,
                .name = spec,
                .url = spec,
            };
        }

        // Check for user/repo format
        if (std.mem.indexOf(u8, spec, "/")) |slash_pos| {
            return .{
                .kind = .third_party,
                .name = spec[slash_pos + 1 ..],
                .owner = spec[0..slash_pos],
            };
        }

        // All short names are official plugins (styles are handled separately)
        return .{
            .kind = .official,
            .name = spec,
        };
    }

    /// Get the URL to fetch plugin.json from
    pub fn getPluginJsonUrl(self: PluginSource, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self.kind) {
            .official => std.fmt.allocPrint(allocator, "{s}/{s}/plugin.json", .{ OFFICIAL_REPO, self.name }),
            .third_party => std.fmt.allocPrint(allocator, "{s}/{s}/{s}/main/plugin.json", .{ GITHUB_BASE, self.owner.?, self.name }),
            .direct_url => if (std.mem.endsWith(u8, self.url.?, "plugin.json"))
                allocator.dupe(u8, self.url.?)
            else
                std.fmt.allocPrint(allocator, "{s}/plugin.json", .{self.url.?}),
        };
    }

    /// Get display name for the plugin source
    pub fn getDisplayName(self: PluginSource, allocator: std.mem.Allocator) ![]const u8 {
        return switch (self.kind) {
            .official => std.fmt.allocPrint(allocator, "ziews/plugins/{s}", .{self.name}),
            .third_party => std.fmt.allocPrint(allocator, "{s}/{s}", .{ self.owner.?, self.name }),
            .direct_url => allocator.dupe(u8, self.url.?),
        };
    }
};

/// Built-in style presets (CSS frameworks) - not plugins, just CLI convenience
pub const StylePreset = struct {
    name: []const u8,
    url: []const u8,
    description: []const u8,
};

pub const style_presets = [_]StylePreset{
    .{ .name = "pico", .url = "https://unpkg.com/@picocss/pico@latest/css/pico.min.css", .description = "Minimal CSS framework for semantic HTML" },
    .{ .name = "water", .url = "https://unpkg.com/water.css@2/out/water.min.css", .description = "A drop-in collection of CSS styles" },
    .{ .name = "simple", .url = "https://unpkg.com/simpledotcss/simple.min.css", .description = "A classless CSS framework" },
    .{ .name = "mvp", .url = "https://unpkg.com/mvp.css", .description = "Minimalist stylesheet for HTML elements" },
    .{ .name = "tailwind", .url = "https://cdn.tailwindcss.com", .description = "Tailwind CSS (Play CDN - no build required)" },
};

/// Get a style preset by name
pub fn getStylePreset(name: []const u8) ?StylePreset {
    for (style_presets) |preset| {
        if (std.mem.eql(u8, preset.name, name)) {
            return preset;
        }
    }
    return null;
}

/// Real plugins that extend ziew functionality
pub const builtin_plugins = [_]BuiltinPlugin{};

/// Plugin manager for loading and managing plugins
pub const PluginManager = struct {
    allocator: std.mem.Allocator,
    plugins_dir: []const u8,
    loaded_plugins: std.StringHashMap(PluginMeta),

    const Self = @This();

    /// Initialize plugin manager with default plugins directory
    pub fn init(allocator: std.mem.Allocator) !Self {
        // Default to ~/.ziew/plugins/
        const ziew_dir = try utils.getZiewDir(allocator);
        defer allocator.free(ziew_dir);
        const plugins_dir = try utils.joinPath(allocator, ziew_dir, "plugins");

        return Self{
            .allocator = allocator,
            .plugins_dir = plugins_dir,
            .loaded_plugins = std.StringHashMap(PluginMeta).init(allocator),
        };
    }

    /// Initialize with custom plugins directory
    pub fn initWithDir(allocator: std.mem.Allocator, dir: []const u8) Self {
        return Self{
            .allocator = allocator,
            .plugins_dir = dir,
            .loaded_plugins = std.StringHashMap(PluginMeta).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.loaded_plugins.deinit();
        self.allocator.free(self.plugins_dir);
    }

    /// Ensure plugins directory exists (creates parent dirs too)
    pub fn ensurePluginsDir(self: *Self) !void {
        // First ensure ~/.ziew/ exists
        const ziew_dir = try utils.getZiewDir(self.allocator);
        defer self.allocator.free(ziew_dir);

        fs.makeDirAbsolute(ziew_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        // Then ensure plugins dir exists
        fs.makeDirAbsolute(self.plugins_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };
    }

    /// List installed plugins
    pub fn listInstalled(self: *Self) ![]const []const u8 {
        var plugins = std.ArrayList([]const u8).init(self.allocator);

        var dir = fs.openDirAbsolute(self.plugins_dir, .{ .iterate = true }) catch {
            return plugins.toOwnedSlice();
        };
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            if (entry.kind == .directory) {
                const name = try self.allocator.dupe(u8, entry.name);
                try plugins.append(name);
            }
        }

        return plugins.toOwnedSlice();
    }

    /// Check if a plugin is a built-in
    pub fn getBuiltin(name: []const u8) ?BuiltinPlugin {
        for (builtin_plugins) |plugin| {
            if (std.mem.eql(u8, plugin.name, name)) {
                return plugin;
            }
        }
        return null;
    }

    /// Get path to a plugin
    pub fn getPluginPath(self: *Self, name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ self.plugins_dir, name });
    }

    /// Check if a plugin is installed
    pub fn isInstalled(self: *Self, name: []const u8) bool {
        const path = self.getPluginPath(name) catch return false;
        defer self.allocator.free(path);

        var dir = fs.openDirAbsolute(path, .{}) catch return false;
        dir.close();
        return true;
    }
};

/// Generate HTML injection for a style plugin
pub fn generateStyleInject(css_filename: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    return std.fmt.allocPrint(allocator, "<link rel=\"stylesheet\" href=\"./{s}\">", .{css_filename});
}

test "plugin type parsing" {
    const t = std.testing;
    try t.expectEqual(PluginType.style, PluginType.fromString("style").?);
    try t.expectEqual(PluginType.native, PluginType.fromString("native").?);
    try t.expect(PluginType.fromString("invalid") == null);
}

test "style preset lookup" {
    const pico = getStylePreset("pico");
    const t = std.testing;
    try t.expect(pico != null);
    try t.expectEqualStrings("pico", pico.?.name);

    const tailwind = getStylePreset("tailwind");
    try t.expect(tailwind != null);

    const unknown = getStylePreset("unknown");
    try t.expect(unknown == null);
}

test "plugin source parsing - official" {
    const t = std.testing;
    // All short names are now official plugins
    const lua = PluginSource.parse("lua");
    try t.expectEqual(PluginSource.Kind.official, lua.kind);
    try t.expectEqualStrings("lua", lua.name);

    const pico = PluginSource.parse("pico");
    try t.expectEqual(PluginSource.Kind.official, pico.kind);
    try t.expectEqualStrings("pico", pico.name);
}

test "plugin source parsing - third party" {
    const t = std.testing;
    const source = PluginSource.parse("someuser/cool-theme");
    try t.expectEqual(PluginSource.Kind.third_party, source.kind);
    try t.expectEqualStrings("cool-theme", source.name);
    try t.expectEqualStrings("someuser", source.owner.?);
}

test "plugin source parsing - direct url" {
    const t = std.testing;
    const source = PluginSource.parse("https://example.com/my-plugin");
    try t.expectEqual(PluginSource.Kind.direct_url, source.kind);
    try t.expectEqualStrings("https://example.com/my-plugin", source.url.?);
}
