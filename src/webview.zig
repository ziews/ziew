//! Webview bindings - Cross-platform via webview/webview library
//!
//! Supports:
//! - Linux: GTK3 + WebKit2GTK
//! - macOS: Cocoa + WebKit
//! - Windows: Edge WebView2
//!
//! Uses the webview C library: https://github.com/webview/webview

const std = @import("std");
const builtin = @import("builtin");

// Import the webview C header
const c = @cImport({
    @cInclude("webview/webview.h");
});

// Platform-specific imports for dev tools and window management
const platform = if (builtin.os.tag == .linux) @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("webkit2/webkit2.h");
}) else if (builtin.os.tag == .windows) @cImport({
    // WebView2 headers would go here
}) else struct {}; // macOS uses Objective-C

/// Webview size hints for setSize
pub const SizeHint = enum(c_int) {
    none = c.WEBVIEW_HINT_NONE,
    min = c.WEBVIEW_HINT_MIN,
    max = c.WEBVIEW_HINT_MAX,
    fixed = c.WEBVIEW_HINT_FIXED,
};

/// Webview errors
pub const Error = error{
    MissingDependency,
    Canceled,
    InvalidState,
    InvalidArgument,
    Unspecified,
    Duplicate,
    NotFound,
    CreateFailed,
};

fn handleError(err: c.webview_error_t) Error!void {
    return switch (err) {
        c.WEBVIEW_ERROR_OK => {},
        c.WEBVIEW_ERROR_MISSING_DEPENDENCY => error.MissingDependency,
        c.WEBVIEW_ERROR_CANCELED => error.Canceled,
        c.WEBVIEW_ERROR_INVALID_STATE => error.InvalidState,
        c.WEBVIEW_ERROR_INVALID_ARGUMENT => error.InvalidArgument,
        c.WEBVIEW_ERROR_DUPLICATE => error.Duplicate,
        c.WEBVIEW_ERROR_NOT_FOUND => error.NotFound,
        else => error.Unspecified,
    };
}

pub const Window = struct {
    handle: c.webview_t,

    pub const Config = struct {
        debug: bool = false,
        title: [:0]const u8 = "Ziew App",
        width: u32 = 800,
        height: u32 = 600,
    };

    /// Callback type for bound functions
    pub const BindCallback = *const fn ([*c]const u8, [*c]const u8, ?*anyopaque) callconv(.C) void;

    /// Create a new webview window
    pub fn create(config: Config) !Window {
        const handle = c.webview_create(@intFromBool(config.debug), null);
        if (handle == null) {
            return error.CreateFailed;
        }

        const window = Window{ .handle = handle };

        // Set initial title and size
        // Note: webview 0.12.0 has a bug where GTK set_size always returns error
        // even though the operation succeeds. We ignore errors here since the
        // operations actually work.
        _ = c.webview_set_title(window.handle, config.title.ptr);
        _ = c.webview_set_size(
            window.handle,
            @intCast(config.width),
            @intCast(config.height),
            @intFromEnum(SizeHint.none),
        );

        // Enable loading local files (fix CORS for file:// URLs)
        if (builtin.os.tag == .linux) {
            const browser_handle = window.getBrowserHandle();
            if (browser_handle) |ptr| {
                const webkit_view: *platform.WebKitWebView = @ptrCast(@alignCast(ptr));
                const settings = platform.webkit_web_view_get_settings(webkit_view);
                if (settings != null) {
                    platform.webkit_settings_set_allow_file_access_from_file_urls(settings, 1);
                    platform.webkit_settings_set_allow_universal_access_from_file_urls(settings, 1);
                }
            }
        }

        return window;
    }

    /// Run the main event loop (blocking)
    pub fn run(self: Window) !void {
        try handleError(c.webview_run(self.handle));
    }

    /// Stop the event loop
    pub fn terminate(self: Window) !void {
        try handleError(c.webview_terminate(self.handle));
    }

    /// Destroy the window and free resources
    pub fn destroy(self: Window) !void {
        try handleError(c.webview_destroy(self.handle));
    }

    /// Set window title
    pub fn setTitle(self: Window, title: [:0]const u8) !void {
        try handleError(c.webview_set_title(self.handle, title.ptr));
    }

    /// Set window size
    pub fn setSize(self: Window, width: u32, height: u32) !void {
        try handleError(c.webview_set_size(
            self.handle,
            @intCast(width),
            @intCast(height),
            @intFromEnum(SizeHint.none),
        ));
    }

    /// Set window size with hint
    pub fn setSizeWithHint(self: Window, width: u32, height: u32, hint: SizeHint) !void {
        try handleError(c.webview_set_size(
            self.handle,
            @intCast(width),
            @intCast(height),
            @intFromEnum(hint),
        ));
    }

    /// Navigate to a URL
    pub fn navigate(self: Window, url: [:0]const u8) !void {
        try handleError(c.webview_navigate(self.handle, url.ptr));
    }

    /// Set HTML content directly
    pub fn setHtml(self: Window, html: [:0]const u8) !void {
        try handleError(c.webview_set_html(self.handle, html.ptr));
    }

    /// Execute JavaScript in the webview
    pub fn eval(self: Window, js: [:0]const u8) !void {
        try handleError(c.webview_eval(self.handle, js.ptr));
    }

    /// Inject JavaScript to run on every page load
    pub fn init(self: Window, js: [:0]const u8) !void {
        try handleError(c.webview_init(self.handle, js.ptr));
    }

    /// Bind a native function to JavaScript
    /// The function will be available as window.<name>() in JS
    pub fn bind(self: Window, name: [:0]const u8, callback: BindCallback, arg: ?*anyopaque) !void {
        try handleError(c.webview_bind(self.handle, name.ptr, callback, arg));
    }

    /// Unbind a previously bound function
    pub fn unbind(self: Window, name: [:0]const u8) !void {
        try handleError(c.webview_unbind(self.handle, name.ptr));
    }

    /// Return a result to JavaScript from a bound function
    /// status: 0 for success, non-zero for error
    /// result: JSON-encoded result string
    pub fn returnResult(self: Window, seq: [:0]const u8, status: c_int, result: [:0]const u8) !void {
        try handleError(c.webview_return(self.handle, seq.ptr, status, result.ptr));
    }

    /// Get the native window handle
    /// Returns platform-specific handle (GtkWidget*, NSWindow*, HWND)
    pub fn getNativeHandle(self: Window) ?*anyopaque {
        return c.webview_get_window(self.handle);
    }

    /// Get the browser controller handle
    /// Returns WebKitWebView* (GTK), WKWebView* (Cocoa), ICoreWebView2Controller* (Win32)
    pub fn getBrowserHandle(self: Window) ?*anyopaque {
        return c.webview_get_native_handle(self.handle, c.WEBVIEW_NATIVE_HANDLE_KIND_BROWSER_CONTROLLER);
    }

    /// Open developer tools in a separate window (debug mode must be enabled)
    pub fn showDevTools(self: Window) void {
        if (builtin.os.tag == .linux) {
            // Get WebKitWebView handle
            const webview_ptr = self.getBrowserHandle();
            if (webview_ptr) |ptr| {
                const webkit_view: *platform.WebKitWebView = @ptrCast(@alignCast(ptr));
                const inspector = platform.webkit_web_view_get_inspector(webkit_view);
                if (inspector != null) {
                    platform.webkit_web_inspector_show(inspector);
                }
            }
        } else if (builtin.os.tag == .windows) {
            // TODO: WebView2 OpenDevToolsWindow()
            // Requires ICoreWebView2 interface
        } else if (builtin.os.tag == .macos) {
            // TODO: WKWebView inspector (requires Objective-C)
        }
    }

    /// Set window icon from file path
    pub fn setIcon(self: Window, path: [:0]const u8) void {
        if (builtin.os.tag == .linux) {
            const window_ptr = self.getNativeHandle();
            if (window_ptr) |ptr| {
                const gtk_window: *platform.GtkWindow = @ptrCast(@alignCast(ptr));
                _ = platform.gtk_window_set_icon_from_file(gtk_window, path.ptr, null);
            }
        } else if (builtin.os.tag == .windows) {
            // TODO: Set HICON on window
        } else if (builtin.os.tag == .macos) {
            // TODO: NSApplication setApplicationIconImage (requires Objective-C)
        }
    }
};

/// Webview version info
pub const VersionInfo = struct {
    major: u32,
    minor: u32,
    patch: u32,
};

/// Get the webview library version
pub fn version() VersionInfo {
    const ver = c.webview_version();
    return .{
        .major = ver.*.version.major,
        .minor = ver.*.version.minor,
        .patch = ver.*.version.patch,
    };
}
