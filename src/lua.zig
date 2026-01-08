//! LuaJIT bindings for Ziew
//!
//! Provides Lua scripting capabilities for backend logic.
//! Scripts can access ziew APIs and be called from JavaScript.

const std = @import("std");

const c = @cImport({
    @cInclude("luajit-2.1/lua.h");
    @cInclude("luajit-2.1/lualib.h");
    @cInclude("luajit-2.1/lauxlib.h");
});

pub const LuaState = *c.lua_State;

pub const LuaError = error{
    InitFailed,
    LoadFailed,
    CallFailed,
    TypeError,
};

/// Lua runtime for executing scripts
pub const Lua = struct {
    state: LuaState,
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize a new Lua state
    pub fn init(allocator: std.mem.Allocator) !Self {
        const state = c.luaL_newstate() orelse return LuaError.InitFailed;
        c.luaL_openlibs(state);

        return Self{
            .state = state,
            .allocator = allocator,
        };
    }

    /// Clean up Lua state
    pub fn deinit(self: *Self) void {
        c.lua_close(self.state);
    }

    /// Load and execute a Lua file
    pub fn loadFile(self: *Self, path: []const u8) !void {
        const path_z = try self.allocator.dupeZ(u8, path);
        defer self.allocator.free(path_z);

        if (c.luaL_loadfile(self.state, path_z.ptr) != 0) {
            self.logError();
            return LuaError.LoadFailed;
        }

        if (c.lua_pcall(self.state, 0, c.LUA_MULTRET, 0) != 0) {
            self.logError();
            return LuaError.CallFailed;
        }
    }

    /// Load and execute a Lua string
    pub fn loadString(self: *Self, code: []const u8) !void {
        const code_z = try self.allocator.dupeZ(u8, code);
        defer self.allocator.free(code_z);

        if (c.luaL_loadstring(self.state, code_z.ptr) != 0) {
            self.logError();
            return LuaError.LoadFailed;
        }

        if (c.lua_pcall(self.state, 0, c.LUA_MULTRET, 0) != 0) {
            self.logError();
            return LuaError.CallFailed;
        }
    }

    /// Call a global Lua function by name with a single string argument
    pub fn call(self: *Self, func_name: []const u8, args: anytype) !?[]const u8 {
        const func_name_z = try self.allocator.dupeZ(u8, func_name);
        defer self.allocator.free(func_name_z);

        // Get the function
        c.lua_getglobal(self.state, func_name_z.ptr);

        if (c.lua_type(self.state, -1) != c.LUA_TFUNCTION) {
            c.lua_pop(self.state, 1);
            return LuaError.TypeError;
        }

        // Push arguments
        const ArgsType = @TypeOf(args);
        const args_type_info = @typeInfo(ArgsType);
        comptime var num_args: c_int = 0;

        if (args_type_info == .Struct) {
            const fields = args_type_info.Struct.fields;
            inline for (fields) |field| {
                const arg = @field(args, field.name);
                self.pushValue(arg);
                num_args += 1;
            }
        }

        // Call function
        if (c.lua_pcall(self.state, num_args, 1, 0) != 0) {
            self.logError();
            return LuaError.CallFailed;
        }

        // Get result
        const result = self.popString();
        return result;
    }

    /// Call a Lua function with JSON arguments (for JS bridge)
    pub fn callJson(self: *Self, func_name: []const u8, json_args: []const u8) ![]const u8 {
        const func_name_z = try self.allocator.dupeZ(u8, func_name);
        defer self.allocator.free(func_name_z);

        // Get the function
        c.lua_getglobal(self.state, func_name_z.ptr);

        if (c.lua_type(self.state, -1) != c.LUA_TFUNCTION) {
            c.lua_pop(self.state, 1);
            return LuaError.TypeError;
        }

        // Push JSON string as single argument
        const json_z = try self.allocator.dupeZ(u8, json_args);
        defer self.allocator.free(json_z);
        c.lua_pushstring(self.state, json_z.ptr);

        // Call function (1 arg, 1 result)
        if (c.lua_pcall(self.state, 1, 1, 0) != 0) {
            self.logError();
            return LuaError.CallFailed;
        }

        // Get result as string (expecting JSON)
        if (self.popString()) |result| {
            return result;
        }
        return "null";
    }

    /// Push a Zig value onto the Lua stack
    fn pushValue(self: *Self, value: anytype) void {
        const T = @TypeOf(value);
        const type_info = @typeInfo(T);

        switch (type_info) {
            .Int, .ComptimeInt => c.lua_pushinteger(self.state, @intCast(value)),
            .Float, .ComptimeFloat => c.lua_pushnumber(self.state, @floatCast(value)),
            .Bool => c.lua_pushboolean(self.state, if (value) 1 else 0),
            .Pointer => |ptr| {
                if (ptr.size == .Slice and ptr.child == u8) {
                    // String slice []const u8
                    c.lua_pushlstring(self.state, value.ptr, value.len);
                } else if (ptr.size == .One) {
                    // Pointer to array (string literal)
                    const child_info = @typeInfo(ptr.child);
                    if (child_info == .Array and child_info.Array.child == u8) {
                        c.lua_pushlstring(self.state, value, child_info.Array.len);
                    } else {
                        c.lua_pushnil(self.state);
                    }
                } else {
                    c.lua_pushnil(self.state);
                }
            },
            else => c.lua_pushnil(self.state),
        }
    }

    /// Pop a string from the Lua stack
    fn popString(self: *Self) ?[]const u8 {
        if (c.lua_type(self.state, -1) != c.LUA_TSTRING) {
            c.lua_pop(self.state, 1);
            return null;
        }

        var len: usize = 0;
        const ptr = c.lua_tolstring(self.state, -1, &len);
        if (ptr == null) {
            c.lua_pop(self.state, 1);
            return null;
        }

        // Copy the string since Lua owns the original
        const result = self.allocator.dupe(u8, ptr[0..len]) catch {
            c.lua_pop(self.state, 1);
            return null;
        };

        c.lua_pop(self.state, 1);
        return result;
    }

    /// Log error from Lua stack
    fn logError(self: *Self) void {
        if (c.lua_type(self.state, -1) == c.LUA_TSTRING) {
            var len: usize = 0;
            const err = c.lua_tolstring(self.state, -1, &len);
            if (err != null) {
                std.debug.print("[lua] Error: {s}\n", .{err[0..len]});
            }
        }
        c.lua_pop(self.state, 1);
    }

    /// Register a native function callable from Lua
    pub fn register(self: *Self, name: []const u8, func: c.lua_CFunction) !void {
        const name_z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(name_z);

        c.lua_pushcfunction(self.state, func);
        c.lua_setglobal(self.state, name_z.ptr);
    }

    /// Set a global string value
    pub fn setGlobal(self: *Self, name: []const u8, value: []const u8) !void {
        const name_z = try self.allocator.dupeZ(u8, name);
        defer self.allocator.free(name_z);

        const value_z = try self.allocator.dupeZ(u8, value);
        defer self.allocator.free(value_z);

        c.lua_pushstring(self.state, value_z.ptr);
        c.lua_setglobal(self.state, name_z.ptr);
    }
};

// Tests
test "lua init and deinit" {
    var lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();
}

test "lua execute string" {
    var lua = try Lua.init(std.testing.allocator);
    defer lua.deinit();

    try lua.loadString("x = 1 + 1");
}
