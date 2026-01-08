//! Lua Bridge - Connects Lua module to webview
//!
//! Provides native bindings for ziew.lua.call()

const std = @import("std");
const webview = @import("webview.zig");
const lua = @import("lua.zig");

/// Context for Lua bridge callbacks
pub const LuaBridge = struct {
    allocator: std.mem.Allocator,
    lua_instance: ?*lua.Lua,
    window: webview.Window,

    const Self = @This();

    /// Initialize Lua bridge with a script file
    pub fn init(allocator: std.mem.Allocator, window: webview.Window, script_path: ?[]const u8) !Self {
        const lua_instance = try allocator.create(lua.Lua);
        lua_instance.* = try lua.Lua.init(allocator);

        // Load script if provided
        if (script_path) |path| {
            try lua_instance.loadFile(path);
        }

        var bridge = Self{
            .allocator = allocator,
            .lua_instance = lua_instance,
            .window = window,
        };

        // Bind the native function
        try window.bind("__ziew_lua_call", callCallback, @ptrCast(&bridge));

        return bridge;
    }

    /// Initialize Lua bridge without a script (for lazy loading)
    pub fn initLazy(allocator: std.mem.Allocator, window: webview.Window) !Self {
        const lua_instance = try allocator.create(lua.Lua);
        lua_instance.* = try lua.Lua.init(allocator);

        var bridge = Self{
            .allocator = allocator,
            .lua_instance = lua_instance,
            .window = window,
        };

        // Bind the native function
        try window.bind("__ziew_lua_call", callCallback, @ptrCast(&bridge));

        return bridge;
    }

    /// Load a Lua script file
    pub fn loadScript(self: *Self, path: []const u8) !void {
        if (self.lua_instance) |instance| {
            try instance.loadFile(path);
        }
    }

    /// Load Lua code from string
    pub fn loadString(self: *Self, code: []const u8) !void {
        if (self.lua_instance) |instance| {
            try instance.loadString(code);
        }
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        if (self.lua_instance) |instance| {
            instance.deinit();
            self.allocator.destroy(instance);
        }
    }

    /// Callback for ziew.lua.call()
    fn callCallback(seq: [*c]const u8, req: [*c]const u8, arg: ?*anyopaque) callconv(.C) void {
        const self: *Self = @ptrCast(@alignCast(arg));
        self.handleCall(seq, req) catch |err| {
            self.returnError(seq, err);
        };
    }

    fn handleCall(self: *Self, seq: [*c]const u8, req: [*c]const u8) !void {
        _ = seq;
        const req_slice = std.mem.span(req);

        // Parse JSON request: { id, func, args }
        const parsed = std.json.parseFromSlice(std.json.Value, self.allocator, req_slice, .{}) catch {
            return; // Can't return error without ID
        };
        defer parsed.deinit();

        const root = parsed.value.object;

        // Get request ID
        const id = root.get("id") orelse return;
        const id_str = switch (id) {
            .string => |s| s,
            else => return,
        };

        // Get function name
        const func_val = root.get("func") orelse {
            return self.rejectWithId(id_str, "Missing function name");
        };
        const func_name = switch (func_val) {
            .string => |s| s,
            else => return self.rejectWithId(id_str, "Invalid function name"),
        };

        // Get args array
        const args_val = root.get("args");

        // Check if Lua is available
        const lua_instance = self.lua_instance orelse {
            return self.rejectWithId(id_str, "Lua not initialized");
        };

        // Build args string for Lua (JSON encoded)
        var args_json = std.ArrayList(u8).init(self.allocator);
        defer args_json.deinit();

        if (args_val) |args| {
            switch (args) {
                .array => |arr| {
                    // Convert args to JSON string for Lua
                    std.json.stringify(arr.items, .{}, args_json.writer()) catch {
                        return self.rejectWithId(id_str, "Failed to encode args");
                    };
                },
                else => {},
            }
        }

        // Call Lua function with JSON args
        const result = lua_instance.callJson(func_name, args_json.items) catch |err| {
            const msg = switch (err) {
                error.TypeError => "Function not found",
                error.CallFailed => "Lua call failed",
                error.LoadFailed => "Failed to load function",
                else => "Lua error",
            };
            return self.rejectWithId(id_str, msg);
        };
        defer self.allocator.free(result);

        // Return result
        self.resolveWithId(id_str, result);
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
