const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main ziew library
    const lib = b.addStaticLibrary(.{
        .name = "ziew",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Link system libraries and add include paths
    linkSystemLibraries(lib, target);
    b.installArtifact(lib);

    // Hello example
    const hello_exe = b.addExecutable(.{
        .name = "hello",
        .root_source_file = b.path("examples/hello/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    hello_exe.root_module.addImport("ziew", &lib.root_module);
    linkSystemLibraries(hello_exe, target);
    b.installArtifact(hello_exe);

    // Run step
    const run_cmd = b.addRunArtifact(hello_exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the hello example");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const lib_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    linkSystemLibraries(lib_tests, target);
    const run_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}

fn linkSystemLibraries(step: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    step.linkLibC();

    // Linux: GTK3, WebKit2GTK
    if (target.result.os.tag == .linux) {
        // Add GTK3 include paths and libraries
        step.linkSystemLibrary("gtk+-3.0");

        // Add WebKit2GTK include paths and libraries
        step.linkSystemLibrary("webkit2gtk-4.1");
    }
    // macOS: Cocoa, WebKit frameworks
    else if (target.result.os.tag == .macos) {
        step.linkFramework("Cocoa");
        step.linkFramework("WebKit");
    }
    // Windows: Various system libs for WebView2
    else if (target.result.os.tag == .windows) {
        step.linkSystemLibrary("ole32");
        step.linkSystemLibrary("shell32");
        step.linkSystemLibrary("shlwapi");
        step.linkSystemLibrary("user32");
        step.linkSystemLibrary("gdi32");
        step.linkSystemLibrary("advapi32");
    }
}
