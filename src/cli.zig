//! Ziew CLI - Command-line interface for project management
//!
//! Commands:
//! - ziew init <name> [--style=<style>] [--template=<template>]
//! - ziew dev
//! - ziew build [--release]
//! - ziew ship [--target=<target>]
//! - ziew plugin add <plugins...>
//! - ziew plugin remove <plugins...>
//! - ziew plugin list
//! - ziew help
//! - ziew version

const std = @import("std");
const config = @import("config.zig");
const builtin = @import("builtin");

pub const Cli = struct {
    allocator: std.mem.Allocator,
    args: []const [:0]u8,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator) !Self {
        const args = try std.process.argsAlloc(allocator);
        return Self{
            .allocator = allocator,
            .args = args,
        };
    }

    pub fn deinit(self: *Self) void {
        std.process.argsFree(self.allocator, self.args);
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
            try self.print("Styles: pico, water, simple, mvp, tailwind", .{});
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
        // Check for ziew.zon
        var cfg = config.Config.load(self.allocator) catch |err| {
            try self.printError("Failed to load ziew.zon: {any}", .{err});
            try self.print("Run this command from a ziew project directory", .{});
            return;
        };
        defer cfg.deinit();

        try self.print("Starting development server for {s}...", .{cfg.name});
        try self.print("Plugins: {s}", .{if (cfg.plugins.len > 0) "enabled" else "none"});

        // Build with plugins and run
        try self.runZigBuild(&cfg, false, true);
    }

    fn cmdBuild(self: *Self) !void {
        var release = false;
        for (self.args[2..]) |arg| {
            if (std.mem.eql(u8, arg, "--release")) {
                release = true;
            }
        }

        // Load config
        var cfg = config.Config.load(self.allocator) catch |err| {
            try self.printError("Failed to load ziew.zon: {any}", .{err});
            try self.print("Run this command from a ziew project directory", .{});
            return;
        };
        defer cfg.deinit();

        try self.print("Building {s}{s}...", .{ cfg.name, if (release) " (release)" else "" });
        if (cfg.plugins.len > 0) {
            try self.print("Plugins: ", .{});
            for (cfg.plugins, 0..) |plugin_name, i| {
                if (i > 0) {
                    const stdout = std.io.getStdOut().writer();
                    try stdout.writeAll(", ");
                }
                const stdout = std.io.getStdOut().writer();
                try stdout.print("{s}", .{plugin_name});
            }
            const stdout = std.io.getStdOut().writer();
            try stdout.writeAll("\n");
        }

        try self.runZigBuild(&cfg, release, false);
    }

    fn runZigBuild(self: *Self, cfg: *config.Config, release: bool, run_after: bool) !void {
        // Build argument list
        var args = std.ArrayList([]const u8).init(self.allocator);
        defer args.deinit();

        try args.append("zig");
        try args.append("build");

        // Add plugin flags
        for (cfg.plugins) |plugin_name| {
            const flag = try std.fmt.allocPrint(self.allocator, "-D{s}=true", .{plugin_name});
            try args.append(flag);
        }

        // Add optimize flag for release builds
        if (release) {
            try args.append("-Doptimize=ReleaseSmall");
        }

        // Add run if requested
        if (run_after) {
            try args.append("run");
        }

        // Run zig build
        var child = std.process.Child.init(args.items, self.allocator);
        child.stderr_behavior = .Inherit;
        child.stdout_behavior = .Inherit;

        _ = try child.spawnAndWait();
    }

    fn cmdShip(self: *Self) !void {
        // Load config
        var cfg = config.Config.load(self.allocator) catch |err| {
            try self.printError("Failed to load ziew.zon: {any}", .{err});
            try self.print("Run this command from a ziew project directory", .{});
            return;
        };
        defer cfg.deinit();

        // Parse target options
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

        try self.print("Building {s} for distribution...", .{cfg.name});
        if (cfg.plugins.len > 0) {
            try self.print("Plugins: ", .{});
            for (cfg.plugins, 0..) |plugin_name, i| {
                if (i > 0) {
                    const stdout = std.io.getStdOut().writer();
                    try stdout.writeAll(", ");
                }
                const stdout = std.io.getStdOut().writer();
                try stdout.print("{s}", .{plugin_name});
            }
            const stdout = std.io.getStdOut().writer();
            try stdout.writeAll("\n");
        }

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
            try self.print("\nBuilding for {s}...", .{target.name});

            // Build argument list
            var args = std.ArrayList([]const u8).init(self.allocator);
            defer args.deinit();

            try args.append("zig");
            try args.append("build");

            // Add target
            const target_flag = try std.fmt.allocPrint(self.allocator, "-Dtarget={s}", .{target.zig_target});
            try args.append(target_flag);

            // Add plugin flags
            for (cfg.plugins) |plugin_name| {
                const flag = try std.fmt.allocPrint(self.allocator, "-D{s}=true", .{plugin_name});
                try args.append(flag);
            }

            // Always optimize for ship
            try args.append("-Doptimize=ReleaseSmall");

            // Run zig build
            const result = std.process.Child.run(.{
                .allocator = self.allocator,
                .argv = args.items,
                .cwd = null,
            }) catch |err| {
                try self.print("  Failed: {any}", .{err});
                try results.append(.{ .name = target.name, .size = 0, .success = false });
                continue;
            };
            defer self.allocator.free(result.stdout);
            defer self.allocator.free(result.stderr);

            if (result.term.Exited != 0) {
                try self.print("  Build failed", .{});
                if (result.stderr.len > 0) {
                    try self.print("  {s}", .{result.stderr});
                }
                try results.append(.{ .name = target.name, .size = 0, .success = false });
                continue;
            }

            // Copy binary to dist
            const src_path = try std.fmt.allocPrint(self.allocator, "zig-out/bin/{s}{s}", .{ cfg.name, target.extension });
            defer self.allocator.free(src_path);

            const dst_name = try std.fmt.allocPrint(self.allocator, "{s}-{s}{s}", .{ cfg.name, target.name, target.extension });
            defer self.allocator.free(dst_name);

            const dst_path = try std.fmt.allocPrint(self.allocator, "dist/{s}", .{dst_name});
            defer self.allocator.free(dst_path);

            std.fs.cwd().copyFile(src_path, std.fs.cwd(), dst_path, .{}) catch |err| {
                try self.print("  Failed to copy binary: {any}", .{err});
                try results.append(.{ .name = target.name, .size = 0, .success = false });
                continue;
            };

            const stat = std.fs.cwd().statFile(dst_path) catch |err| {
                try self.print("  Failed to stat binary: {any}", .{err});
                try results.append(.{ .name = target.name, .size = 0, .success = false });
                continue;
            };

            try self.print("  OK: {s}", .{formatSize(self.allocator, stat.size) catch "?"});
            try results.append(.{ .name = target.name, .size = stat.size, .success = true });
        }

        // Print summary
        try self.print("\n========================================", .{});
        try self.print("Build Results:", .{});
        try self.print("========================================", .{});

        var total_size: u64 = 0;
        var success_count: usize = 0;

        for (results.items) |r| {
            if (r.success) {
                const size_str = formatSize(self.allocator, r.size) catch "?";
                try self.print("  {s}-{s}: {s}", .{ cfg.name, r.name, size_str });
                total_size += r.size;
                success_count += 1;
            } else {
                try self.print("  {s}-{s}: FAILED", .{ cfg.name, r.name });
            }
        }

        if (success_count > 0) {
            const total_str = formatSize(self.allocator, total_size) catch "?";
            try self.print("========================================", .{});
            try self.print("Total: {s} ({d} platforms)", .{ total_str, success_count });
            try self.print("\nBinaries in: ./dist/", .{});
        }
    }

    fn cmdPlugin(self: *Self) !void {
        if (self.args.len < 3) {
            try self.printError("Usage: ziew plugin <add|remove|list> [plugins...]", .{});
            return;
        }

        const subcmd = self.args[2];

        if (std.mem.eql(u8, subcmd, "add")) {
            try self.pluginAdd();
        } else if (std.mem.eql(u8, subcmd, "list")) {
            try self.pluginList();
        } else if (std.mem.eql(u8, subcmd, "remove")) {
            try self.pluginRemove();
        } else {
            try self.printError("Unknown plugin subcommand: {s}", .{subcmd});
            try self.print("Usage: ziew plugin <add|remove|list> [plugins...]", .{});
        }
    }

    fn pluginAdd(self: *Self) !void {
        if (self.args.len < 4) {
            try self.printError("Usage: ziew plugin add <plugin1> [plugin2] ...", .{});
            try self.print("\nAvailable plugins:", .{});
            for (config.available_plugins) |info| {
                try self.print("  {s}: {s}", .{ info.name, info.description });
            }
            return;
        }

        // Load existing config
        var cfg = config.Config.load(self.allocator) catch {
            try self.printError("No ziew.zon found. Run 'ziew init' first.", .{});
            return;
        };
        defer cfg.deinit();

        // Add each plugin
        var added: usize = 0;
        for (self.args[3..]) |plugin_name| {
            if (!config.isValidPlugin(plugin_name)) {
                try self.printError("Unknown plugin: {s}", .{plugin_name});
                continue;
            }

            if (cfg.hasPlugin(plugin_name)) {
                try self.print("Plugin '{s}' already enabled", .{plugin_name});
                continue;
            }

            try cfg.addPlugin(plugin_name);
            const info = config.getPluginInfo(plugin_name).?;
            try self.print("Added: {s} ({s})", .{ plugin_name, info.description });
            if (!std.mem.eql(u8, info.deps, "none")) {
                try self.print("  Requires: {s}", .{info.deps});
            }
            added += 1;
        }

        if (added > 0) {
            try cfg.save();
            try self.print("\nUpdated ziew.zon", .{});
        }
    }

    fn pluginRemove(self: *Self) !void {
        if (self.args.len < 4) {
            try self.printError("Usage: ziew plugin remove <plugin1> [plugin2] ...", .{});
            return;
        }

        // Load existing config
        var cfg = config.Config.load(self.allocator) catch {
            try self.printError("No ziew.zon found.", .{});
            return;
        };
        defer cfg.deinit();

        // Remove each plugin
        var removed: usize = 0;
        for (self.args[3..]) |plugin_name| {
            if (!cfg.hasPlugin(plugin_name)) {
                try self.print("Plugin '{s}' not enabled", .{plugin_name});
                continue;
            }

            try cfg.removePlugin(plugin_name);
            try self.print("Removed: {s}", .{plugin_name});
            removed += 1;
        }

        if (removed > 0) {
            try cfg.save();
            try self.print("\nUpdated ziew.zon", .{});
        }
    }

    fn pluginList(self: *Self) !void {
        // Try to load project config
        var cfg = config.Config.load(self.allocator) catch {
            // No project config, just list available plugins
            try self.print("Available plugins:\n", .{});
            try self.printPluginsByCategory();
            return;
        };
        defer cfg.deinit();

        // Show enabled plugins
        try self.print("Enabled plugins in {s}:", .{cfg.name});
        if (cfg.plugins.len == 0) {
            try self.print("  (none)\n", .{});
        } else {
            for (cfg.plugins) |plugin_name| {
                if (config.getPluginInfo(plugin_name)) |info| {
                    try self.print("  {s}: {s}", .{ plugin_name, info.description });
                } else {
                    try self.print("  {s}", .{plugin_name});
                }
            }
            try self.print("", .{});
        }

        // Show available plugins
        try self.print("Available plugins:", .{});
        try self.printPluginsByCategory();
    }

    fn printPluginsByCategory(self: *Self) !void {
        try self.print("\n  Core:", .{});
        for (config.available_plugins) |info| {
            if (info.category == .core) {
                try self.print("    {s}: {s}", .{ info.name, info.description });
            }
        }

        try self.print("\n  Input:", .{});
        for (config.available_plugins) |info| {
            if (info.category == .input) {
                try self.print("    {s}: {s}", .{ info.name, info.description });
            }
        }

        try self.print("\n  AI:", .{});
        for (config.available_plugins) |info| {
            if (info.category == .ai) {
                try self.print("    {s}: {s}", .{ info.name, info.description });
            }
        }
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

        // Create ziew.zon
        try self.createZiewZon(project_dir, name);

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
        try self.print("  ziew build", .{});
        try self.print("  ziew dev", .{});
        try self.print("\nAdd plugins:", .{});
        try self.print("  ziew plugin add sqlite notify", .{});
    }

    fn createZiewZon(self: *Self, project_dir: []const u8, name: []const u8) !void {
        const zon_path = try std.fmt.allocPrint(self.allocator, "{s}/ziew.zon", .{project_dir});
        defer self.allocator.free(zon_path);

        var file = try std.fs.createFileAbsolute(zon_path, .{});
        defer file.close();

        try file.writer().print(
            \\.{{
            \\    .name = "{s}",
            \\    .version = "0.1.0",
            \\    .plugins = .{{}},
            \\}}
            \\
        , .{name});
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
        \\    // Plugin options (configured via ziew.zon, passed by ziew build)
        \\    const enable_sqlite = b.option(bool, "sqlite", "Enable SQLite plugin") orelse false;
        \\    const enable_notify = b.option(bool, "notify", "Enable notifications plugin") orelse false;
        \\    const enable_keychain = b.option(bool, "keychain", "Enable keychain plugin") orelse false;
        \\    const enable_hotkeys = b.option(bool, "hotkeys", "Enable global hotkeys plugin") orelse false;
        \\    const enable_gamepad = b.option(bool, "gamepad", "Enable gamepad plugin") orelse false;
        \\    const enable_serial = b.option(bool, "serial", "Enable serial port plugin") orelse false;
        \\    const enable_lua = b.option(bool, "lua", "Enable Lua scripting") orelse false;
        \\    const enable_ai = b.option(bool, "ai", "Enable AI (llama.cpp)") orelse false;
        \\    const enable_whisper = b.option(bool, "whisper", "Enable Whisper STT") orelse false;
        \\    const enable_piper = b.option(bool, "piper", "Enable Piper TTS") orelse false;
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
        \\    // Link plugin dependencies
        \\    if (enable_sqlite) {
        \\        exe.linkSystemLibrary("sqlite3");
        \\        exe.root_module.addCMacro("HAS_SQLITE", "1");
        \\    }
        \\    if (enable_notify and os == .linux) {
        \\        exe.linkSystemLibrary("libnotify");
        \\        exe.root_module.addCMacro("HAS_NOTIFY", "1");
        \\    }
        \\    if (enable_keychain and os == .linux) {
        \\        exe.linkSystemLibrary("libsecret-1");
        \\        exe.root_module.addCMacro("HAS_KEYCHAIN", "1");
        \\    }
        \\    if (enable_hotkeys and os == .linux) {
        \\        exe.linkSystemLibrary("x11");
        \\        exe.root_module.addCMacro("HAS_HOTKEYS", "1");
        \\    }
        \\    if (enable_gamepad) exe.root_module.addCMacro("HAS_GAMEPAD", "1");
        \\    if (enable_serial) exe.root_module.addCMacro("HAS_SERIAL", "1");
        \\    if (enable_lua) {
        \\        if (os == .linux) exe.linkSystemLibrary("luajit-5.1");
        \\        exe.root_module.addCMacro("HAS_LUA", "1");
        \\    }
        \\    if (enable_ai) {
        \\        exe.linkSystemLibrary("llama");
        \\        exe.linkLibC();
        \\        exe.root_module.addCMacro("HAS_AI", "1");
        \\    }
        \\    if (enable_whisper) exe.root_module.addCMacro("HAS_WHISPER", "1");
        \\    if (enable_piper) exe.root_module.addCMacro("HAS_PIPER", "1");
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
        \\            // Run: zig build 2>&1 | grep "hash" to get the hash
        \\        },
        \\    },
        \\    .paths = .{ "build.zig", "build.zig.zon", "main.zig", "index.html", "ziew.zon" },
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
        \\    .paths = .{ "build.zig", "build.zig.zon", "main.zig", "index.html", "game.js", "ziew.zon" },
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
            \\  init <name> [options]       Create a new project
            \\    --style=<style>           Include CSS framework (pico, water, simple, mvp, tailwind)
            \\    --template=<template>     Use game template (kaplay, phaser, three)
            \\
            \\  build [--release]           Build the project
            \\  dev                         Build and run in development mode
            \\  ship [--target=<target>]    Build for distribution
            \\
            \\  plugin add <plugins...>     Enable plugins
            \\  plugin remove <plugins...>  Disable plugins
            \\  plugin list                 List available plugins
            \\
            \\  help                        Show this help
            \\  version                     Show version
            \\
            \\Examples:
            \\  ziew init myapp
            \\  ziew init myapp --style=pico
            \\  ziew init mygame --template=phaser
            \\  ziew plugin add sqlite notify
            \\  ziew build --release
            \\  ziew ship --target=windows
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
