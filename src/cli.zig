//! Ziew CLI - Command-line interface for project management
//!
//! Commands:
//! - ziew init <name> [--style=<style>]
//! - ziew dev
//! - ziew build [--release]
//! - ziew ship [--target=<target>]
//! - ziew plugin add <name>
//! - ziew plugin list
//! - ziew plugin remove <name>
//! - ziew docs [--format=json|md]

const std = @import("std");
const plugin = @import("plugin.zig");
const builtin = @import("builtin");

pub const Command = enum {
    init,
    dev,
    build,
    ship,
    plugin_add,
    plugin_list,
    plugin_remove,
    docs,
    help,
    version,
};

pub const CliError = error{
    MissingArgument,
    UnknownCommand,
    InvalidOption,
    PluginNotFound,
    NetworkError,
    FileSystemError,
};

pub const Cli = struct {
    allocator: std.mem.Allocator,
    args: []const [:0]u8,
    plugin_manager: plugin.PluginManager,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const args = try std.process.argsAlloc(allocator);
        return Self{
            .allocator = allocator,
            .args = args,
            .plugin_manager = try plugin.PluginManager.init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        std.process.argsFree(self.allocator, self.args);
        self.plugin_manager.deinit();
    }

    pub fn run(self: *Self) !void {
        if (self.args.len < 2) {
            try self.printHelp();
            return;
        }

        const cmd_str = self.args[1];

        if (std.mem.eql(u8, cmd_str, "init")) {
            try self.cmdInit();
        } else if (std.mem.eql(u8, cmd_str, "dev")) {
            try self.cmdDev();
        } else if (std.mem.eql(u8, cmd_str, "build")) {
            try self.cmdBuild();
        } else if (std.mem.eql(u8, cmd_str, "ship")) {
            try self.cmdShip();
        } else if (std.mem.eql(u8, cmd_str, "plugin")) {
            try self.cmdPlugin();
        } else if (std.mem.eql(u8, cmd_str, "docs")) {
            try self.cmdDocs();
        } else if (std.mem.eql(u8, cmd_str, "help") or std.mem.eql(u8, cmd_str, "--help") or std.mem.eql(u8, cmd_str, "-h")) {
            try self.printHelp();
        } else if (std.mem.eql(u8, cmd_str, "version") or std.mem.eql(u8, cmd_str, "--version") or std.mem.eql(u8, cmd_str, "-v")) {
            try self.printVersion();
        } else {
            try self.printError("Unknown command: {s}", .{cmd_str});
            try self.printHelp();
        }
    }

    fn cmdInit(self: *Self) !void {
        if (self.args.len < 3) {
            try self.printError("Usage: ziew init <project-name> [--template=<template>] [--style=<style>]", .{});
            try self.print("\nTemplates: kaplay, phaser, three", .{});
            return;
        }

        const name = self.args[2];
        var style: ?[]const u8 = null;
        var template: ?[]const u8 = null;

        // Parse options
        for (self.args[3..]) |arg| {
            if (std.mem.startsWith(u8, arg, "--style=")) {
                style = arg["--style=".len..];
            } else if (std.mem.startsWith(u8, arg, "--template=")) {
                template = arg["--template=".len..];
            }
        }

        if (template) |t| {
            try self.print("Creating {s} project: {s}", .{ t, name });
        } else {
            try self.print("Creating project: {s}", .{name});
        }
        try self.initProject(name, style, template);
    }

    fn cmdDev(self: *Self) !void {
        try self.print("Starting development server...", .{});
        // TODO: Implement dev server with hot reload
        try self.printError("dev command not yet implemented", .{});
    }

    fn cmdBuild(self: *Self) !void {
        var release = false;
        for (self.args[2..]) |arg| {
            if (std.mem.eql(u8, arg, "--release")) {
                release = true;
            }
        }

        try self.print("Building project{s}...", .{if (release) " (release)" else ""});
        // TODO: Implement build command
        try self.printError("build command not yet implemented", .{});
    }

    fn cmdShip(self: *Self) !void {
        // Parse options
        var targets_specified = false;
        var build_windows = false;
        var build_macos_x64 = false;
        var build_macos_arm = false;
        var build_linux = false;

        for (self.args[2..]) |arg| {
            if (std.mem.startsWith(u8, arg, "--target=")) {
                targets_specified = true;
                const target = arg["--target=".len..];
                if (std.mem.eql(u8, target, "windows")) {
                    build_windows = true;
                } else if (std.mem.eql(u8, target, "macos") or std.mem.eql(u8, target, "macos-x64")) {
                    build_macos_x64 = true;
                } else if (std.mem.eql(u8, target, "macos-arm64")) {
                    build_macos_arm = true;
                } else if (std.mem.eql(u8, target, "linux")) {
                    build_linux = true;
                } else if (std.mem.eql(u8, target, "all")) {
                    build_windows = true;
                    build_macos_x64 = true;
                    build_macos_arm = true;
                    build_linux = true;
                } else {
                    try self.printError("Unknown target: {s}", .{target});
                    try self.print("Valid targets: windows, macos, macos-x64, macos-arm64, linux, all", .{});
                    return;
                }
            }
        }

        // Default: build for all platforms
        if (!targets_specified) {
            build_windows = true;
            build_macos_x64 = true;
            build_macos_arm = true;
            build_linux = true;
        }

        // Check if build.zig exists
        std.fs.cwd().access("build.zig", .{}) catch {
            try self.printError("No build.zig found in current directory", .{});
            try self.print("Run this command from a ziew project directory", .{});
            return;
        };

        // Get project name from build.zig.zon if it exists
        const project_name = self.getProjectName() catch "app";

        try self.print("Building {s} for distribution...\n", .{project_name});

        // Create dist directory
        std.fs.cwd().makeDir("dist") catch |err| {
            if (err != error.PathAlreadyExists) {
                try self.printError("Failed to create dist directory: {any}", .{err});
                return;
            }
        };

        const Target = struct {
            name: []const u8,
            zig_target: []const u8,
            extension: []const u8,
        };

        var targets = std.ArrayList(Target).init(self.allocator);
        defer targets.deinit();

        if (build_windows) {
            try targets.append(.{ .name = "windows-x64", .zig_target = "x86_64-windows", .extension = ".exe" });
        }
        if (build_macos_x64) {
            try targets.append(.{ .name = "macos-x64", .zig_target = "x86_64-macos", .extension = "" });
        }
        if (build_macos_arm) {
            try targets.append(.{ .name = "macos-arm64", .zig_target = "aarch64-macos", .extension = "" });
        }
        if (build_linux) {
            try targets.append(.{ .name = "linux-x64", .zig_target = "x86_64-linux", .extension = "" });
        }

        var results = std.ArrayList(struct { name: []const u8, size: u64, success: bool }).init(self.allocator);
        defer results.deinit();

        for (targets.items) |target| {
            try self.print("Building for {s}...", .{target.name});

            // Run zig build with target
            const result = std.process.Child.run(.{
                .allocator = self.allocator,
                .argv = &.{
                    "zig",
                    "build",
                    std.fmt.allocPrint(self.allocator, "-Dtarget={s}", .{target.zig_target}) catch continue,
                    "-Doptimize=ReleaseSmall",
                },
                .cwd = null,
            }) catch |err| {
                try self.print("  Failed to run zig build: {any}", .{err});
                try results.append(.{ .name = target.name, .size = 0, .success = false });
                continue;
            };
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);

            if (result.term.Exited != 0) {
                try self.print("  Build failed for {s}", .{target.name});
                if (result.stderr.len > 0) {
                    try self.print("  {s}", .{result.stderr});
                }
                try results.append(.{ .name = target.name, .size = 0, .success = false });
                continue;
            }

            // Find and copy the built binary
            const src_path = std.fmt.allocPrint(self.allocator, "zig-out/bin/{s}{s}", .{ project_name, target.extension }) catch continue;
            defer self.allocator.free(src_path);

            const dst_name = std.fmt.allocPrint(self.allocator, "{s}-{s}{s}", .{ project_name, target.name, target.extension }) catch continue;
            defer self.allocator.free(dst_name);

            const dst_path = std.fmt.allocPrint(self.allocator, "dist/{s}", .{dst_name}) catch continue;
            defer self.allocator.free(dst_path);

            // Copy file to dist
            std.fs.cwd().copyFile(src_path, std.fs.cwd(), dst_path, .{}) catch |err| {
                try self.print("  Failed to copy binary: {any}", .{err});
                try results.append(.{ .name = target.name, .size = 0, .success = false });
                continue;
            };

            // Get file size
            const stat = std.fs.cwd().statFile(dst_path) catch |err| {
                try self.print("  Failed to stat binary: {any}", .{err});
                try results.append(.{ .name = target.name, .size = 0, .success = false });
                continue;
            };

            try results.append(.{ .name = target.name, .size = stat.size, .success = true });
        }

        // Print summary
        try self.print("\n----------------------------------------", .{});
        try self.print("Build Results:", .{});
        try self.print("----------------------------------------", .{});

        var total_size: u64 = 0;
        var success_count: usize = 0;

        for (results.items) |r| {
            if (r.success) {
                const size_str = formatSize(self.allocator, r.size) catch "?";
                defer if (!std.mem.eql(u8, size_str, "?")) self.allocator.free(size_str);
                try self.print("  {s}-{s}: {s}", .{ project_name, r.name, size_str });
                total_size += r.size;
                success_count += 1;
            } else {
                try self.print("  {s}-{s}: FAILED", .{ project_name, r.name });
            }
        }

        if (success_count > 0) {
            const total_str = formatSize(self.allocator, total_size) catch "?";
            defer if (!std.mem.eql(u8, total_str, "?")) self.allocator.free(total_str);
            try self.print("----------------------------------------", .{});
            try self.print("Total: {s} ({d} platforms)", .{ total_str, success_count });
            try self.print("\nBinaries in: ./dist/", .{});
        }
    }

    fn getProjectName(self: *Self) ![]const u8 {
        // Try to read from build.zig.zon
        const zon_content = std.fs.cwd().readFileAlloc(self.allocator, "build.zig.zon", 1024 * 64) catch {
            return error.NoProjectName;
        };
        defer self.allocator.free(zon_content);

        // Simple parse: look for .name = "..."
        if (std.mem.indexOf(u8, zon_content, ".name = \"")) |start| {
            const name_start = start + ".name = \"".len;
            if (std.mem.indexOfPos(u8, zon_content, name_start, "\"")) |end| {
                return self.allocator.dupe(u8, zon_content[name_start..end]);
            }
        }

        return error.NoProjectName;
    }

    fn formatSize(allocator: std.mem.Allocator, bytes: u64) ![]const u8 {
        if (bytes >= 1024 * 1024) {
            const mb = @as(f64, @floatFromInt(bytes)) / (1024 * 1024);
            return std.fmt.allocPrint(allocator, "{d:.1} MB", .{mb});
        } else if (bytes >= 1024) {
            const kb = @as(f64, @floatFromInt(bytes)) / 1024;
            return std.fmt.allocPrint(allocator, "{d:.0} KB", .{kb});
        } else {
            return std.fmt.allocPrint(allocator, "{d} B", .{bytes});
        }
    }

    fn cmdPlugin(self: *Self) !void {
        if (self.args.len < 3) {
            try self.printError("Usage: ziew plugin <add|list|remove> [name]", .{});
            return;
        }

        const subcmd = self.args[2];

        if (std.mem.eql(u8, subcmd, "add")) {
            if (self.args.len < 4) {
                try self.printError("Usage: ziew plugin add <name>", .{});
                return;
            }
            try self.pluginAdd(self.args[3]);
        } else if (std.mem.eql(u8, subcmd, "list")) {
            try self.pluginList();
        } else if (std.mem.eql(u8, subcmd, "remove")) {
            if (self.args.len < 4) {
                try self.printError("Usage: ziew plugin remove <name>", .{});
                return;
            }
            try self.pluginRemove(self.args[3]);
        } else {
            try self.printError("Unknown plugin subcommand: {s}", .{subcmd});
        }
    }

    fn cmdDocs(self: *Self) !void {
        var format: []const u8 = "md";
        for (self.args[2..]) |arg| {
            if (std.mem.startsWith(u8, arg, "--format=")) {
                format = arg["--format=".len..];
            }
        }

        try self.print("Generating documentation ({s})...", .{format});
        // TODO: Implement docs generation
        try self.printError("docs command not yet implemented", .{});
    }

    fn pluginAdd(self: *Self, spec: []const u8) !void {
        try self.plugin_manager.ensurePluginsDir();

        // Parse the plugin specifier
        const source = plugin.PluginSource.parse(spec);
        const display_name = try source.getDisplayName(self.allocator);
        defer self.allocator.free(display_name);

        const plugin_json_url = try source.getPluginJsonUrl(self.allocator);
        defer self.allocator.free(plugin_json_url);

        const plugin_name = switch (source.kind) {
            .official, .third_party => source.name,
            .direct_url => extractNameFromUrl(source.url.?),
        };

        const plugin_dir = try self.plugin_manager.getPluginPath(plugin_name);
        defer self.allocator.free(plugin_dir);

        try self.print("Installing {s} from {s}...", .{ plugin_name, display_name });

        std.fs.makeDirAbsolute(plugin_dir) catch |err| {
            if (err != error.PathAlreadyExists) return err;
        };

        try self.print("\n  Fetch plugin.json:", .{});
        try self.print("    curl -o {s}/plugin.json \"{s}\"", .{ plugin_dir, plugin_json_url });
        try self.print("\n  Then install files listed in plugin.json", .{});

        try self.print("\n✓ Plugin directory created: {s}", .{plugin_dir});
    }

    fn extractNameFromUrl(url: []const u8) []const u8 {
        // Extract the last path segment, removing trailing slashes
        var end = url.len;
        while (end > 0 and url[end - 1] == '/') end -= 1;

        var start = end;
        while (start > 0 and url[start - 1] != '/') start -= 1;

        const segment = url[start..end];
        // Remove common suffixes like .git
        if (std.mem.endsWith(u8, segment, ".git")) {
            return segment[0 .. segment.len - 4];
        }
        return segment;
    }

    fn pluginList(self: *Self) !void {
        try self.print("Installed plugins:", .{});

        const installed = try self.plugin_manager.listInstalled();
        defer {
            for (installed) |name| {
                self.allocator.free(name);
            }
            self.allocator.free(installed);
        }

        if (installed.len == 0) {
            try self.print("  (none)", .{});
        } else {
            for (installed) |name| {
                try self.print("  - {s}", .{name});
            }
        }

        try self.print("\nOfficial plugins (ziews/plugins):", .{});
        try self.print("  - lua: LuaJIT scripting for backend logic", .{});
        try self.print("  - sqlite: SQLite database bindings", .{});
        try self.print("  - llama: Local LLM inference via llama.cpp", .{});
        try self.print("  - whisper: Speech-to-text via whisper.cpp", .{});

        try self.print("\nStyle presets (use with --style flag):", .{});
        for (plugin.style_presets) |preset| {
            try self.print("  - {s}: {s}", .{ preset.name, preset.description });
        }
    }

    fn pluginRemove(self: *Self, name: []const u8) !void {
        const plugin_dir = try self.plugin_manager.getPluginPath(name);
        defer self.allocator.free(plugin_dir);

        if (!self.plugin_manager.isInstalled(name)) {
            try self.printError("Plugin '{s}' is not installed", .{name});
            return;
        }

        // Remove the plugin directory
        try std.fs.deleteTreeAbsolute(plugin_dir);
        try self.print("✓ Plugin {s} removed", .{name});
    }

    fn initProject(self: *Self, name: []const u8, style: ?[]const u8, template: ?[]const u8) !void {
        // Create project directory
        try std.fs.cwd().makeDir(name);

        const cwd = try std.fs.cwd().realpathAlloc(self.allocator, ".");
        defer self.allocator.free(cwd);

        const project_dir = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ cwd, name });
        defer self.allocator.free(project_dir);

        // Convert name to lowercase for build artifacts
        var name_lower_buf: [256]u8 = undefined;
        const name_lower = blk: {
            var i: usize = 0;
            for (name) |c| {
                if (i >= name_lower_buf.len) break;
                name_lower_buf[i] = if (c >= 'A' and c <= 'Z') c + 32 else if (c == ' ') '_' else c;
                i += 1;
            }
            break :blk name_lower_buf[0..i];
        };

        if (template) |t| {
            // Use game template
            try self.initFromTemplate(project_dir, name, name_lower, t);
        } else {
            // Default project (no template)
            try self.initDefaultProject(project_dir, name, name_lower, style);
        }

        try self.print("\n✓ Project '{s}' created!", .{name});
        try self.print("\nNext steps:", .{});
        try self.print("  cd {s}", .{name});
        try self.print("  zig build run", .{});
    }

    fn initDefaultProject(self: *Self, project_dir: []const u8, name: []const u8, name_lower: []const u8, style: ?[]const u8) !void {
        // Create index.html
        const html_path = try std.fmt.allocPrint(self.allocator, "{s}/index.html", .{project_dir});
        defer self.allocator.free(html_path);

        var html_file = try std.fs.createFileAbsolute(html_path, .{});
        defer html_file.close();

        const style_link = if (style) |s|
            try std.fmt.allocPrint(self.allocator, "  <link rel=\"stylesheet\" href=\"{s}.css\">\n", .{s})
        else
            "";
        defer if (style != null) self.allocator.free(style_link);

        try html_file.writer().print(
            \\<!DOCTYPE html>
            \\<html lang="en">
            \\<head>
            \\  <meta charset="UTF-8">
            \\  <meta name="viewport" content="width=device-width, initial-scale=1.0">
            \\  <title>{s}</title>
            \\{s}</head>
            \\<body>
            \\  <h1>Welcome to {s}</h1>
            \\  <p>Built with <a href="https://ziew.sh">Ziew</a></p>
            \\
            \\  <script>
            \\    // Ziew APIs available via window.ziew
            \\    console.log('Platform:', ziew.platform);
            \\    console.log('Version:', ziew.version);
            \\  </script>
            \\</body>
            \\</html>
        , .{ name, style_link, name });

        // Create main.zig
        try self.writeTemplateFile(project_dir, "main.zig", tpl_default_main, name, name_lower);

        // Create build files
        try self.writeTemplateFile(project_dir, "build.zig", tpl_build_zig, name, name_lower);
        try self.writeTemplateFile(project_dir, "build.zig.zon", tpl_build_zon, name, name_lower);
    }

    fn initFromTemplate(self: *Self, project_dir: []const u8, name: []const u8, name_lower: []const u8, template: []const u8) !void {
        // Get template files based on template name
        const files: []const struct { name: []const u8, content: []const u8 } = if (std.mem.eql(u8, template, "kaplay"))
            &.{
                .{ .name = "index.html", .content = tpl_kaplay_html },
                .{ .name = "game.js", .content = tpl_kaplay_js },
                .{ .name = "main.zig", .content = tpl_kaplay_main },
            }
        else if (std.mem.eql(u8, template, "phaser"))
            &.{
                .{ .name = "index.html", .content = tpl_phaser_html },
                .{ .name = "game.js", .content = tpl_phaser_js },
                .{ .name = "main.zig", .content = tpl_phaser_main },
            }
        else if (std.mem.eql(u8, template, "three"))
            &.{
                .{ .name = "index.html", .content = tpl_three_html },
                .{ .name = "game.js", .content = tpl_three_js },
                .{ .name = "main.zig", .content = tpl_three_main },
            }
        else {
            try self.printError("Unknown template: {s}", .{template});
            try self.print("Available templates: kaplay, phaser, three", .{});
            return error.UnknownTemplate;
        };

        // Write template files
        for (files) |file| {
            try self.writeTemplateFile(project_dir, file.name, file.content, name, name_lower);
        }

        // Write build files
        try self.writeTemplateFile(project_dir, "build.zig", tpl_build_zig, name, name_lower);
        try self.writeTemplateFile(project_dir, "build.zig.zon", tpl_build_zon_game, name, name_lower);
    }

    fn writeTemplateFile(self: *Self, project_dir: []const u8, filename: []const u8, template: []const u8, name: []const u8, name_lower: []const u8) !void {
        const file_path = try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ project_dir, filename });
        defer self.allocator.free(file_path);

        var file = try std.fs.createFileAbsolute(file_path, .{});
        defer file.close();

        // Replace placeholders
        var content = try self.allocator.alloc(u8, template.len + name.len * 10);
        defer self.allocator.free(content);

        var write_idx: usize = 0;
        var read_idx: usize = 0;

        while (read_idx < template.len) {
            if (read_idx + 16 <= template.len and std.mem.eql(u8, template[read_idx .. read_idx + 16], "{{PROJECT_NAME}}")) {
                @memcpy(content[write_idx .. write_idx + name.len], name);
                write_idx += name.len;
                read_idx += 16;
            } else if (read_idx + 22 <= template.len and std.mem.eql(u8, template[read_idx .. read_idx + 22], "{{PROJECT_NAME_LOWER}}")) {
                @memcpy(content[write_idx .. write_idx + name_lower.len], name_lower);
                write_idx += name_lower.len;
                read_idx += 22;
            } else {
                content[write_idx] = template[read_idx];
                write_idx += 1;
                read_idx += 1;
            }
        }

        try file.writeAll(content[0..write_idx]);
    }

    // ============================================
    // EMBEDDED TEMPLATES
    // ============================================

    const tpl_default_main =
        \\const std = @import("std");
        \\const ziew = @import("ziew");
        \\
        \\pub fn main() !void {
        \\    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        \\    defer _ = gpa.deinit();
        \\    const allocator = gpa.allocator();
        \\
        \\    var app = try ziew.App.init(allocator, .{
        \\        .title = "{{PROJECT_NAME}}",
        \\        .width = 800,
        \\        .height = 600,
        \\        .debug = true,
        \\    });
        \\    defer app.deinit();
        \\
        \\    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
        \\    const cwd = std.fs.cwd().realpath(".", &cwd_buf) catch ".";
        \\    const html_path = std.fmt.allocPrintZ(allocator, "file://{s}/index.html", .{cwd}) catch return;
        \\    defer allocator.free(html_path);
        \\
        \\    app.navigate(html_path);
        \\    app.run();
        \\}
    ;

    const tpl_build_zig =
        \\const std = @import("std");
        \\
        \\pub fn build(b: *std.Build) void {
        \\    const target = b.standardTargetOptions(.{});
        \\    const optimize = b.standardOptimizeOption(.{});
        \\    const os = target.result.os.tag;
        \\
        \\    // Get ziew dependency (includes webview)
        \\    const ziew_dep = b.dependency("ziew", .{
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\
        \\    // Get webview from ziew's dependencies
        \\    const webview_dep = ziew_dep.builder.dependency("webview", .{});
        \\
        \\    // Build webview C++ library
        \\    const webview_lib = b.addStaticLibrary(.{
        \\        .name = "webview",
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\    webview_lib.addCSourceFile(.{
        \\        .file = webview_dep.path("core/src/webview.cc"),
        \\        .flags = &.{ "-std=c++14", "-DWEBVIEW_STATIC" },
        \\    });
        \\    webview_lib.addIncludePath(webview_dep.path("core/include"));
        \\    webview_lib.linkLibCpp();
        \\
        \\    // Link platform libraries
        \\    if (os == .linux) {
        \\        webview_lib.linkSystemLibrary("gtk+-3.0");
        \\        webview_lib.linkSystemLibrary("webkit2gtk-4.1");
        \\    } else if (os == .macos) {
        \\        webview_lib.linkFramework("Cocoa");
        \\        webview_lib.linkFramework("WebKit");
        \\    } else if (os == .windows) {
        \\        webview_lib.linkSystemLibrary("ole32");
        \\        webview_lib.linkSystemLibrary("shlwapi");
        \\        webview_lib.linkSystemLibrary("version");
        \\        webview_lib.linkSystemLibrary("advapi32");
        \\        webview_lib.linkSystemLibrary("shell32");
        \\        webview_lib.linkSystemLibrary("user32");
        \\    }
        \\
        \\    // Build executable
        \\    const exe = b.addExecutable(.{
        \\        .name = "{{PROJECT_NAME_LOWER}}",
        \\        .root_source_file = b.path("main.zig"),
        \\        .target = target,
        \\        .optimize = optimize,
        \\    });
        \\
        \\    exe.root_module.addImport("ziew", ziew_dep.module("ziew"));
        \\    exe.addIncludePath(webview_dep.path("core/include"));
        \\    exe.linkLibrary(webview_lib);
        \\
        \\    b.installArtifact(exe);
        \\
        \\    const run_cmd = b.addRunArtifact(exe);
        \\    run_cmd.step.dependOn(b.getInstallStep());
        \\    if (b.args) |args| {
        \\        run_cmd.addArgs(args);
        \\    }
        \\
        \\    const run_step = b.step("run", "Run the app");
        \\    run_step.dependOn(&run_cmd.step);
        \\}
    ;

    const tpl_build_zon =
        \\.{
        \\    .name = "{{PROJECT_NAME_LOWER}}",
        \\    .version = "0.1.0",
        \\    .dependencies = .{
        \\        .ziew = .{
        \\            .url = "https://github.com/ziews/ziew/archive/refs/heads/main.tar.gz",
        \\            // .hash = "...",
        \\        },
        \\    },
        \\    .paths = .{ "build.zig", "build.zig.zon", "main.zig", "index.html" },
        \\}
    ;

    const tpl_build_zon_game =
        \\.{
        \\    .name = "{{PROJECT_NAME_LOWER}}",
        \\    .version = "0.1.0",
        \\    .dependencies = .{
        \\        .ziew = .{
        \\            .url = "https://github.com/ziews/ziew/archive/refs/heads/main.tar.gz",
        \\            .hash = "1220d05ba59d18f58632664aafc28e4474ae06e173fc925266a663ae3827375777fc",
        \\        },
        \\    },
        \\    .paths = .{ "build.zig", "build.zig.zon", "main.zig", "index.html", "game.js" },
        \\}
    ;

    // Kaplay templates
    const tpl_kaplay_html = @embedFile("templates/kaplay/index.html");
    const tpl_kaplay_js = @embedFile("templates/kaplay/game.js");
    const tpl_kaplay_main = @embedFile("templates/kaplay/main.zig");

    // Phaser templates
    const tpl_phaser_html = @embedFile("templates/phaser/index.html");
    const tpl_phaser_js = @embedFile("templates/phaser/game.js");
    const tpl_phaser_main = @embedFile("templates/phaser/main.zig");

    // Three.js templates
    const tpl_three_html = @embedFile("templates/three/index.html");
    const tpl_three_js = @embedFile("templates/three/game.js");
    const tpl_three_main = @embedFile("templates/three/main.zig");

    fn print(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        _ = self;
        const stdout = std.io.getStdOut().writer();
        try stdout.print(fmt ++ "\n", args);
    }

    fn printError(self: *Self, comptime fmt: []const u8, args: anytype) !void {
        _ = self;
        const stderr = std.io.getStdErr().writer();
        try stderr.print("error: " ++ fmt ++ "\n", args);
    }

    fn printHelp(self: *Self) !void {
        try self.print(
            \\ziew - Desktop apps in kilobytes, not megabytes
            \\
            \\Usage: ziew <command> [options]
            \\
            \\Commands:
            \\  init <name> [--style=<style>]  Create a new project
            \\  dev                            Start development server
            \\  build [--release]              Build the project
            \\  ship [--target=<target>]       Build for all platforms
            \\  plugin <add|list|remove>       Manage plugins
            \\  docs [--format=json|md]        Generate API documentation
            \\  help                           Show this help
            \\  version                        Show version
            \\
            \\Plugin sources:
            \\  pico                 Official plugin (ziews/plugins)
            \\  someuser/theme       Third-party (github.com/someuser/theme)
            \\  https://...          Direct URL
            \\
            \\Examples:
            \\  ziew init myapp
            \\  ziew init myapp --style=pico
            \\  ziew plugin add pico
            \\  ziew plugin add cooldev/dark-mode
            \\  ziew plugin list
            \\
            \\More info: https://ziew.sh
        , .{});
    }

    fn printVersion(self: *Self) !void {
        const version_str = @import("main.zig").version;
        try self.print("ziew {s}", .{version_str});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var cli = try Cli.init(allocator);
    defer cli.deinit();

    try cli.run();
}
