# Contributing to Ziew

Thanks for your interest in contributing! The main way to contribute is by **creating plugins**.

## Creating a Plugin

Plugins extend Ziew with native capabilities. Each plugin has:

1. **Zig implementation** - Native code in `src/plugins/<name>.zig`
2. **JS bridge** - Exposes API to JavaScript
3. **Registration** - Added to `src/config.zig`

### Plugin Structure

```
src/plugins/
└── myplugin.zig    # Your plugin implementation
```

### Example Plugin

```zig
//! MyPlugin - Description of what it does
//!
//! Linux: How it works on Linux
//! macOS: How it works on macOS (or TODO)
//! Windows: How it works on Windows (or TODO)

const std = @import("std");

pub const MyPlugin = struct {
    // Plugin state

    pub fn init() !MyPlugin {
        // Initialize
    }

    pub fn deinit(self: *MyPlugin) void {
        // Cleanup
    }

    // Your API methods
    pub fn doSomething(self: *MyPlugin, arg: []const u8) ![]const u8 {
        // Implementation
    }
};
```

### Registering Your Plugin

Add to `src/config.zig`:

```zig
pub const available_plugins = [_]PluginInfo{
    // ... existing plugins
    .{ .name = "myplugin", .description = "What it does", .deps = "system-deps", .category = .core },
};
```

Add build option to `build.zig` and wire up the linking.

### JS Bridge

Add your plugin to `src/bridge.zig` to expose it to JavaScript:

```javascript
// Users will call it like:
const result = await ziew.myplugin.doSomething('arg');
```

## Submitting

1. Fork the repo
2. Create your plugin
3. Test on at least one platform (Linux is easiest)
4. Submit a PR with:
   - Plugin implementation
   - Brief description of what it does
   - What platforms are implemented (OK to start with just Linux)

## Guidelines

- **Start simple** - Get one platform working first
- **Document TODOs** - Mark unimplemented platforms clearly
- **No external deps if possible** - Use system libraries
- **Match existing style** - Look at other plugins for patterns

## Questions?

Open an issue on GitHub.
