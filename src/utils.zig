//! Cross-platform utilities for Ziew
//!
//! Provides platform-independent functions for common operations
//! that differ between Windows and POSIX systems.

const std = @import("std");
const builtin = @import("builtin");

/// Get the user's home directory in a cross-platform way.
/// On Windows: uses USERPROFILE environment variable
/// On POSIX: uses HOME environment variable
pub fn getHomeDir(allocator: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag == .windows) {
        // Windows: use USERPROFILE
        const result = std.process.getEnvVarOwned(allocator, "USERPROFILE") catch {
            return error.NoHomeDir;
        };
        return result;
    } else {
        // POSIX: use HOME
        const result = std.process.getEnvVarOwned(allocator, "HOME") catch {
            return error.NoHomeDir;
        };
        return result;
    }
}

/// Get the ziew config directory (~/.ziew on POSIX, %USERPROFILE%\.ziew on Windows)
pub fn getZiewDir(allocator: std.mem.Allocator) ![]const u8 {
    const home = try getHomeDir(allocator);
    defer allocator.free(home);

    if (builtin.os.tag == .windows) {
        return std.fmt.allocPrint(allocator, "{s}\\.ziew", .{home});
    } else {
        return std.fmt.allocPrint(allocator, "{s}/.ziew", .{home});
    }
}

/// Get the runtime directory for temporary files
/// On Linux: XDG_RUNTIME_DIR or /tmp
/// On macOS: /tmp
/// On Windows: %TEMP% or %USERPROFILE%\AppData\Local\Temp
pub fn getRuntimeDir(allocator: std.mem.Allocator) ![]const u8 {
    if (builtin.os.tag == .windows) {
        // Try TEMP, then TMP, then fall back to home\AppData\Local\Temp
        if (std.process.getEnvVarOwned(allocator, "TEMP")) |temp| {
            return temp;
        } else |_| {
            if (std.process.getEnvVarOwned(allocator, "TMP")) |tmp| {
                return tmp;
            } else |_| {
                const home = try getHomeDir(allocator);
                defer allocator.free(home);
                return std.fmt.allocPrint(allocator, "{s}\\AppData\\Local\\Temp", .{home});
            }
        }
    } else if (builtin.os.tag == .linux) {
        // Linux: prefer XDG_RUNTIME_DIR, fall back to /tmp
        if (std.process.getEnvVarOwned(allocator, "XDG_RUNTIME_DIR")) |dir| {
            return dir;
        } else |_| {
            return allocator.dupe(u8, "/tmp");
        }
    } else {
        // macOS and others: use /tmp
        return allocator.dupe(u8, "/tmp");
    }
}

/// Join path components with the appropriate separator for the current OS
pub fn joinPath(allocator: std.mem.Allocator, base: []const u8, component: []const u8) ![]const u8 {
    const sep = if (builtin.os.tag == .windows) "\\" else "/";
    return std.fmt.allocPrint(allocator, "{s}{s}{s}", .{ base, sep, component });
}
