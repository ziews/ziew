//! Keychain Plugin
//!
//! Secure credential storage using OS keychain.
//!
//! Linux: Uses libsecret (Secret Service API)
//! macOS: Uses Security framework Keychain Services (TODO)
//! Windows: Uses Windows Credential Manager (TODO)

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

pub const KeychainError = error{
    NotFound,
    AccessDenied,
    InvalidData,
    ServiceUnavailable,
    Unknown,
    NotImplemented,
};

// Linux implementation using libsecret
const linux = struct {
    const c = @cImport({
        @cInclude("libsecret/secret.h");
    });

    // Secret schema for storing credentials
    var schema: ?*c.SecretSchema = null;

    pub fn init() void {
        if (schema != null) return;

        // Create schema for storing credentials
        schema = c.secret_schema_new(
            "dev.ziew.credentials",
            c.SECRET_SCHEMA_NONE,
            "service",
            c.SECRET_SCHEMA_ATTRIBUTE_STRING,
            "account",
            c.SECRET_SCHEMA_ATTRIBUTE_STRING,
            @as(?*anyopaque, null),
        );
    }

    pub fn deinit() void {
        if (schema) |s| {
            c.secret_schema_unref(s);
            schema = null;
        }
    }

    pub fn store(service: []const u8, account: []const u8, secret: []const u8) !void {
        if (schema == null) init();

        const service_z = std.heap.c_allocator.dupeZ(u8, service) catch return KeychainError.Unknown;
        defer std.heap.c_allocator.free(service_z);

        const account_z = std.heap.c_allocator.dupeZ(u8, account) catch return KeychainError.Unknown;
        defer std.heap.c_allocator.free(account_z);

        const secret_z = std.heap.c_allocator.dupeZ(u8, secret) catch return KeychainError.Unknown;
        defer std.heap.c_allocator.free(secret_z);

        const label = std.heap.c_allocator.dupeZ(u8, service) catch return KeychainError.Unknown;
        defer std.heap.c_allocator.free(label);

        var err: ?*c.GError = null;
        const result = c.secret_password_store_sync(
            schema,
            c.SECRET_COLLECTION_DEFAULT,
            label,
            secret_z,
            null, // cancellable
            &err,
            "service",
            service_z,
            "account",
            account_z,
            @as(?*anyopaque, null),
        );

        if (err) |e| {
            std.debug.print("[keychain] Store error: {s}\n", .{e.*.message});
            c.g_error_free(e);
            return KeychainError.Unknown;
        }

        if (result == 0) {
            return KeychainError.Unknown;
        }
    }

    pub fn lookup(allocator: Allocator, service: []const u8, account: []const u8) !?[]const u8 {
        if (schema == null) init();

        const service_z = try allocator.dupeZ(u8, service);
        defer allocator.free(service_z);

        const account_z = try allocator.dupeZ(u8, account);
        defer allocator.free(account_z);

        var err: ?*c.GError = null;
        const password = c.secret_password_lookup_sync(
            schema,
            null, // cancellable
            &err,
            "service",
            service_z,
            "account",
            account_z,
            @as(?*anyopaque, null),
        );

        if (err) |e| {
            std.debug.print("[keychain] Lookup error: {s}\n", .{e.*.message});
            c.g_error_free(e);
            return KeychainError.Unknown;
        }

        if (password) |pwd| {
            defer c.secret_password_free(pwd);
            return try allocator.dupe(u8, std.mem.span(pwd));
        }

        return null;
    }

    pub fn delete(service: []const u8, account: []const u8) !void {
        if (schema == null) init();

        const service_z = std.heap.c_allocator.dupeZ(u8, service) catch return KeychainError.Unknown;
        defer std.heap.c_allocator.free(service_z);

        const account_z = std.heap.c_allocator.dupeZ(u8, account) catch return KeychainError.Unknown;
        defer std.heap.c_allocator.free(account_z);

        var err: ?*c.GError = null;
        const result = c.secret_password_clear_sync(
            schema,
            null, // cancellable
            &err,
            "service",
            service_z,
            "account",
            account_z,
            @as(?*anyopaque, null),
        );

        if (err) |e| {
            std.debug.print("[keychain] Delete error: {s}\n", .{e.*.message});
            c.g_error_free(e);
            return KeychainError.Unknown;
        }

        if (result == 0) {
            return KeychainError.NotFound;
        }
    }
};

// Public API

pub fn init() void {
    switch (builtin.os.tag) {
        .linux => linux.init(),
        else => {},
    }
}

pub fn deinit() void {
    switch (builtin.os.tag) {
        .linux => linux.deinit(),
        else => {},
    }
}

/// Store a secret in the keychain
pub fn set(service: []const u8, account: []const u8, secret: []const u8) !void {
    switch (builtin.os.tag) {
        .linux => try linux.store(service, account, secret),
        .macos => return KeychainError.NotImplemented,
        .windows => return KeychainError.NotImplemented,
        else => return KeychainError.NotImplemented,
    }
}

/// Retrieve a secret from the keychain
pub fn get(allocator: Allocator, service: []const u8, account: []const u8) !?[]const u8 {
    switch (builtin.os.tag) {
        .linux => return linux.lookup(allocator, service, account),
        .macos => return KeychainError.NotImplemented,
        .windows => return KeychainError.NotImplemented,
        else => return KeychainError.NotImplemented,
    }
}

/// Delete a secret from the keychain
pub fn delete(service: []const u8, account: []const u8) !void {
    switch (builtin.os.tag) {
        .linux => try linux.delete(service, account),
        .macos => return KeychainError.NotImplemented,
        .windows => return KeychainError.NotImplemented,
        else => return KeychainError.NotImplemented,
    }
}
