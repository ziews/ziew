//! Webview bindings - platform-specific implementations
//!
//! Currently implemented:
//! - Linux: GTK3 + WebKit2GTK-4.1
//!
//! Coming soon:
//! - macOS: Cocoa + WebKit
//! - Windows: Edge WebView2

const std = @import("std");
const c = @cImport({
    @cInclude("gtk/gtk.h");
    @cInclude("webkit2/webkit2.h");
});

pub const Window = struct {
    gtk_window: *c.GtkWidget,
    webview: *c.WebKitWebView,

    pub const Config = struct {
        debug: bool = false,
        title: [:0]const u8 = "Ziew App",
        width: u32 = 800,
        height: u32 = 600,
    };

    /// Create a new webview window
    pub fn create(config: Config) !Window {
        // Initialize GTK
        if (c.gtk_init_check(null, null) == 0) {
            return error.GtkInitFailed;
        }

        // Create window
        const gtk_window = c.gtk_window_new(c.GTK_WINDOW_TOPLEVEL) orelse {
            return error.WindowCreateFailed;
        };
        c.gtk_window_set_title(@ptrCast(gtk_window), config.title.ptr);
        c.gtk_window_set_default_size(@ptrCast(gtk_window), @intCast(config.width), @intCast(config.height));

        // Create WebView
        const webview = c.webkit_web_view_new() orelse {
            return error.WebViewCreateFailed;
        };

        // Add webview to window
        c.gtk_container_add(@ptrCast(gtk_window), webview);

        // Connect destroy signal to quit
        _ = c.g_signal_connect_data(
            gtk_window,
            "destroy",
            @ptrCast(&c.gtk_main_quit),
            null,
            null,
            0,
        );

        // Show all widgets
        c.gtk_widget_show_all(gtk_window);

        // Enable developer tools if debug mode
        if (config.debug) {
            const settings = c.webkit_web_view_get_settings(@ptrCast(webview));
            c.webkit_settings_set_enable_developer_extras(settings, 1);
        }

        return Window{
            .gtk_window = gtk_window,
            .webview = @ptrCast(webview),
        };
    }

    /// Run the main event loop (blocking)
    pub fn run(_: Window) void {
        c.gtk_main();
    }

    /// Stop the event loop
    pub fn terminate(_: Window) void {
        c.gtk_main_quit();
    }

    /// Destroy the window
    pub fn destroy(self: Window) void {
        c.gtk_widget_destroy(self.gtk_window);
    }

    /// Set window title
    pub fn setTitle(self: Window, title: [:0]const u8) void {
        c.gtk_window_set_title(@ptrCast(self.gtk_window), title.ptr);
    }

    /// Set window size
    pub fn setSize(self: Window, width: u32, height: u32) void {
        c.gtk_window_resize(@ptrCast(self.gtk_window), @intCast(width), @intCast(height));
    }

    /// Navigate to a URL
    pub fn navigate(self: Window, url: [:0]const u8) void {
        c.webkit_web_view_load_uri(self.webview, url.ptr);
    }

    /// Set HTML content directly
    pub fn setHtml(self: Window, html: [:0]const u8) void {
        c.webkit_web_view_load_html(self.webview, html.ptr, null);
    }

    /// Execute JavaScript
    pub fn eval(self: Window, js: [:0]const u8) void {
        c.webkit_web_view_run_javascript(self.webview, js.ptr, null, null, null);
    }

    /// Inject JS to run on every page load
    pub fn init(self: Window, js: [:0]const u8) void {
        const content_manager = c.webkit_web_view_get_user_content_manager(self.webview);
        const script = c.webkit_user_script_new(
            js.ptr,
            c.WEBKIT_USER_CONTENT_INJECT_TOP_FRAME,
            c.WEBKIT_USER_SCRIPT_INJECT_AT_DOCUMENT_START,
            null,
            null,
        );
        c.webkit_user_content_manager_add_script(content_manager, script);
        c.webkit_user_script_unref(script);
    }
};
