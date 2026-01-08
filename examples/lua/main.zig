const std = @import("std");
const ziew = @import("ziew");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize Lua
    var lua = try ziew.lua.Lua.init(allocator);
    defer lua.deinit();

    // Load the backend script
    lua.loadFile("examples/lua/backend.lua") catch |err| {
        std.debug.print("Failed to load backend.lua: {}\n", .{err});
        return;
    };

    std.debug.print("Lua backend loaded!\n", .{});

    // Test calling a Lua function
    if (try lua.call("greet", .{"World"})) |result| {
        std.debug.print("Lua returned: {s}\n", .{result});
        allocator.free(result);
    }

    // Test math function
    if (try lua.call("add", .{ 10, 20 })) |result| {
        std.debug.print("10 + 20 = {s}\n", .{result});
        allocator.free(result);
    }

    std.debug.print("\nLua integration working!\n", .{});
}
