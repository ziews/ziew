const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Optional features
    const enable_lua = b.option(bool, "lua", "Enable LuaJIT support (requires libluajit-5.1-dev)") orelse false;

    // Get the webview dependency
    const webview_dep = b.dependency("webview", .{});

    // Build the webview C++ library
    const webview_lib = b.addStaticLibrary(.{
        .name = "webview",
        .target = target,
        .optimize = optimize,
    });

    // Add webview source file
    webview_lib.addCSourceFile(.{
        .file = webview_dep.path("core/src/webview.cc"),
        .flags = &.{ "-std=c++14", "-DWEBVIEW_STATIC" },
    });

    // Add include paths
    webview_lib.addIncludePath(webview_dep.path("core/include"));
    webview_lib.addIncludePath(webview_dep.path("core/include/webview"));

    // Link C++ standard library
    webview_lib.linkLibCpp();

    // Platform-specific configuration
    const os = target.result.os.tag;
    if (os == .linux) {
        webview_lib.linkSystemLibrary("gtk+-3.0");
        webview_lib.linkSystemLibrary("webkit2gtk-4.1");
    } else if (os == .macos) {
        webview_lib.linkFramework("Cocoa");
        webview_lib.linkFramework("WebKit");
    } else if (os == .windows) {
        webview_lib.addIncludePath(b.path("vendor/WebView2/include"));
        webview_lib.linkSystemLibrary("ole32");
        webview_lib.linkSystemLibrary("shlwapi");
        webview_lib.linkSystemLibrary("version");
        webview_lib.linkSystemLibrary("advapi32");
        webview_lib.linkSystemLibrary("shell32");
        webview_lib.linkSystemLibrary("user32");
    }

    b.installArtifact(webview_lib);

    // Main ziew library
    const lib = b.addStaticLibrary(.{
        .name = "ziew",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add webview include path for @cImport
    lib.addIncludePath(webview_dep.path("core/include"));
    lib.linkLibrary(webview_lib);

    // LuaJIT support (optional)
    if (enable_lua) {
        if (os == .linux) {
            lib.linkSystemLibrary("luajit-5.1");
        }
        // Define HAS_LUA so code can conditionally compile
        lib.root_module.addCMacro("HAS_LUA", "1");
    }

    b.installArtifact(lib);

    // Ziew CLI
    const cli_exe = b.addExecutable(.{
        .name = "ziew",
        .root_source_file = b.path("src/cli.zig"),
        .target = target,
        .optimize = optimize,
    });
    cli_exe.root_module.addImport("ziew", &lib.root_module);
    b.installArtifact(cli_exe);

    // Hello example
    const hello_exe = b.addExecutable(.{
        .name = "hello",
        .root_source_file = b.path("examples/hello/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    hello_exe.root_module.addImport("ziew", &lib.root_module);
    hello_exe.addIncludePath(webview_dep.path("core/include"));
    hello_exe.linkLibrary(webview_lib);
    b.installArtifact(hello_exe);

    // Run CLI
    const run_cli = b.addRunArtifact(cli_exe);
    run_cli.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cli.addArgs(args);
    }
    const cli_step = b.step("cli", "Run the ziew CLI");
    cli_step.dependOn(&run_cli.step);

    // Run hello example
    const run_cmd = b.addRunArtifact(hello_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the hello example");
    run_step.dependOn(&run_cmd.step);

    // Lua example (only when lua is enabled)
    if (enable_lua) {
        const lua_exe = b.addExecutable(.{
            .name = "lua-example",
            .root_source_file = b.path("examples/lua/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        lua_exe.root_module.addImport("ziew", &lib.root_module);
        lua_exe.addIncludePath(webview_dep.path("core/include"));
        lua_exe.linkLibrary(webview_lib);
        lua_exe.linkSystemLibrary("luajit-5.1");
        b.installArtifact(lua_exe);

        const run_lua = b.addRunArtifact(lua_exe);
        run_lua.step.dependOn(b.getInstallStep());
        const lua_step = b.step("lua", "Run the Lua example");
        lua_step.dependOn(&run_lua.step);
    }

    // Tests
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_tests.addIncludePath(webview_dep.path("core/include"));
    lib_tests.linkLibrary(webview_lib);
    const run_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
