//! Single Instance Plugin
//!
//! Ensures only one instance of the app runs at a time.
//! Can also receive messages from subsequent launch attempts.
//!
//! Linux/macOS: Uses Unix domain socket
//! Windows: Uses named mutex + named pipe (TODO)

const std = @import("std");
const builtin = @import("builtin");
const posix = std.posix;

pub const SingleInstance = struct {
    allocator: std.mem.Allocator,
    app_id: []const u8,
    socket_path: []const u8,
    socket_fd: ?posix.socket_t = null,
    is_primary: bool = false,
    on_second_instance: ?*const fn (args: []const u8) void = null,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, app_id: []const u8) !Self {
        // Create socket path in /tmp or XDG_RUNTIME_DIR
        const runtime_dir = std.posix.getenv("XDG_RUNTIME_DIR") orelse "/tmp";
        const socket_path = try std.fmt.allocPrint(allocator, "{s}/ziew-{s}.sock", .{ runtime_dir, app_id });

        return Self{
            .allocator = allocator,
            .app_id = try allocator.dupe(u8, app_id),
            .socket_path = socket_path,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.socket_fd) |fd| {
            posix.close(fd);
        }
        if (self.is_primary) {
            std.fs.deleteFileAbsolute(self.socket_path) catch {};
        }
        self.allocator.free(self.socket_path);
        self.allocator.free(self.app_id);
    }

    /// Try to acquire the single instance lock.
    /// Returns true if this is the primary instance.
    /// Returns false if another instance is already running.
    pub fn acquire(self: *Self) !bool {
        switch (builtin.os.tag) {
            .linux, .macos => return self.acquireUnix(),
            .windows => return error.NotImplemented,
            else => return error.UnsupportedPlatform,
        }
    }

    fn acquireUnix(self: *Self) !bool {
        // Try to connect to existing socket (another instance running)
        const connect_result = self.tryConnect();
        if (connect_result) |fd| {
            // Another instance is running - send our args and exit
            posix.close(fd);
            self.is_primary = false;
            return false;
        }

        // No other instance - create the socket
        // First remove any stale socket file
        std.fs.deleteFileAbsolute(self.socket_path) catch {};

        // Create and bind socket
        const sock = try posix.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0);
        errdefer posix.close(sock);

        var addr: posix.sockaddr.un = .{ .family = posix.AF.UNIX, .path = undefined };
        @memset(&addr.path, 0);

        const path_bytes = self.socket_path;
        if (path_bytes.len >= addr.path.len) {
            return error.PathTooLong;
        }
        @memcpy(addr.path[0..path_bytes.len], path_bytes);

        try posix.bind(sock, @ptrCast(&addr), @sizeOf(posix.sockaddr.un));
        try posix.listen(sock, 5);

        self.socket_fd = sock;
        self.is_primary = true;
        return true;
    }

    fn tryConnect(self: *Self) ?posix.socket_t {
        const sock = posix.socket(posix.AF.UNIX, posix.SOCK.STREAM, 0) catch return null;
        errdefer posix.close(sock);

        var addr: posix.sockaddr.un = .{ .family = posix.AF.UNIX, .path = undefined };
        @memset(&addr.path, 0);

        const path_bytes = self.socket_path;
        if (path_bytes.len >= addr.path.len) {
            return null;
        }
        @memcpy(addr.path[0..path_bytes.len], path_bytes);

        posix.connect(sock, @ptrCast(&addr), @sizeOf(posix.sockaddr.un)) catch return null;
        return sock;
    }

    /// Send a message to the primary instance
    pub fn sendToPrimary(self: *Self, message: []const u8) !void {
        const sock = self.tryConnect() orelse return error.NoPrimaryInstance;
        defer posix.close(sock);

        _ = try posix.write(sock, message);
    }

    /// Check for messages from other instances (non-blocking)
    pub fn pollMessages(self: *Self) !?[]const u8 {
        if (!self.is_primary) return null;
        const sock = self.socket_fd orelse return null;

        // Set non-blocking
        var pollfd = [_]posix.pollfd{.{
            .fd = sock,
            .events = posix.POLL.IN,
            .revents = 0,
        }};

        const ready = try posix.poll(&pollfd, 0);
        if (ready == 0) return null;

        // Accept connection
        const client = posix.accept(sock, null, null) catch return null;
        defer posix.close(client);

        // Read message
        var buf: [4096]u8 = undefined;
        const n = posix.read(client, &buf) catch return null;
        if (n == 0) return null;

        return try self.allocator.dupe(u8, buf[0..n]);
    }
};

// Convenience functions
var global_instance: ?SingleInstance = null;

pub fn acquire(allocator: std.mem.Allocator, app_id: []const u8) !bool {
    if (global_instance != null) return error.AlreadyInitialized;
    global_instance = try SingleInstance.init(allocator, app_id);
    return global_instance.?.acquire();
}

pub fn release() void {
    if (global_instance) |*inst| {
        inst.deinit();
        global_instance = null;
    }
}

pub fn sendToPrimary(message: []const u8) !void {
    if (global_instance) |*inst| {
        try inst.sendToPrimary(message);
    } else {
        return error.NotInitialized;
    }
}

pub fn pollMessages() !?[]const u8 {
    if (global_instance) |*inst| {
        return inst.pollMessages();
    }
    return null;
}
