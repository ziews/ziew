.{
    .name = "{{PROJECT_NAME_LOWER}}",
    .version = "0.1.0",
    .dependencies = .{
        .ziew = .{
            .url = "https://github.com/ziews/ziew/archive/refs/heads/main.tar.gz",
            // Run: zig fetch <url> to get the hash
            // .hash = "...",
        },
    },
    .paths = .{ "build.zig", "build.zig.zon", "main.zig", "index.html", "game.js" },
}
