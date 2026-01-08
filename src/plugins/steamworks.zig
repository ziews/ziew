//! Steamworks Plugin
//!
//! Steam integration for achievements, leaderboards, overlay, and more.
//!
//! Requires Steamworks SDK: https://partner.steamgames.com/
//! Place SDK in ~/.ziew/sdk/steamworks/ or set STEAMWORKS_SDK env var
//!
//! All platforms: Link against steam_api (steam_api64 on Windows x64)

const std = @import("std");
const builtin = @import("builtin");

const c = @cImport({
    @cInclude("steam/steam_api.h");
});

pub const SteamError = error{
    NotInitialized,
    InitFailed,
    NotLoggedIn,
    InvalidParam,
    RequestFailed,
    NotImplemented,
};

var initialized: bool = false;

/// Initialize Steamworks with your App ID
/// In development, create a steam_appid.txt file with your App ID
pub fn init() SteamError!void {
    if (initialized) return;

    if (c.SteamAPI_Init() == 0) {
        return SteamError.InitFailed;
    }
    initialized = true;
}

/// Shutdown Steamworks - call before app exit
pub fn deinit() void {
    if (initialized) {
        c.SteamAPI_Shutdown();
        initialized = false;
    }
}

/// Must be called regularly (e.g., every frame or tick) to process callbacks
pub fn runCallbacks() void {
    if (initialized) {
        c.SteamAPI_RunCallbacks();
    }
}

/// Check if Steam is running and user is logged in
pub fn isRunning() bool {
    return initialized and c.SteamAPI_IsSteamRunning() != 0;
}

// ============================================================================
// User Info
// ============================================================================

pub const User = struct {
    /// Get the current user's Steam ID as u64
    pub fn getSteamId() ?u64 {
        if (!initialized) return null;
        const user = c.SteamUser();
        if (user == null) return null;
        return c.SteamAPI_ISteamUser_GetSteamID(user);
    }

    /// Get the current user's display name
    pub fn getPersonaName() ?[]const u8 {
        if (!initialized) return null;
        const friends = c.SteamFriends();
        if (friends == null) return null;
        const name = c.SteamAPI_ISteamFriends_GetPersonaName(friends);
        if (name == null) return null;
        return std.mem.span(name);
    }

    /// Check if the user is logged into Steam
    pub fn isLoggedIn() bool {
        if (!initialized) return false;
        const user = c.SteamUser();
        if (user == null) return false;
        return c.SteamAPI_ISteamUser_BLoggedOn(user) != 0;
    }
};

// ============================================================================
// Achievements
// ============================================================================

pub const Achievements = struct {
    /// Unlock an achievement by API name
    pub fn unlock(name: []const u8) SteamError!void {
        if (!initialized) return SteamError.NotInitialized;

        const stats = c.SteamUserStats();
        if (stats == null) return SteamError.NotInitialized;

        const name_z = std.heap.c_allocator.dupeZ(u8, name) catch return SteamError.RequestFailed;
        defer std.heap.c_allocator.free(name_z);

        if (c.SteamAPI_ISteamUserStats_SetAchievement(stats, name_z) == 0) {
            return SteamError.RequestFailed;
        }

        // Store stats to Steam servers
        _ = c.SteamAPI_ISteamUserStats_StoreStats(stats);
    }

    /// Check if an achievement is unlocked
    pub fn isUnlocked(name: []const u8) SteamError!bool {
        if (!initialized) return SteamError.NotInitialized;

        const stats = c.SteamUserStats();
        if (stats == null) return SteamError.NotInitialized;

        const name_z = std.heap.c_allocator.dupeZ(u8, name) catch return SteamError.RequestFailed;
        defer std.heap.c_allocator.free(name_z);

        var achieved: c.bool = 0;
        if (c.SteamAPI_ISteamUserStats_GetAchievement(stats, name_z, &achieved) == 0) {
            return SteamError.RequestFailed;
        }

        return achieved != 0;
    }

    /// Clear an achievement (for testing)
    pub fn clear(name: []const u8) SteamError!void {
        if (!initialized) return SteamError.NotInitialized;

        const stats = c.SteamUserStats();
        if (stats == null) return SteamError.NotInitialized;

        const name_z = std.heap.c_allocator.dupeZ(u8, name) catch return SteamError.RequestFailed;
        defer std.heap.c_allocator.free(name_z);

        if (c.SteamAPI_ISteamUserStats_ClearAchievement(stats, name_z) == 0) {
            return SteamError.RequestFailed;
        }

        _ = c.SteamAPI_ISteamUserStats_StoreStats(stats);
    }

    /// Request achievement data from Steam (call once at startup)
    pub fn requestStats() SteamError!void {
        if (!initialized) return SteamError.NotInitialized;

        const stats = c.SteamUserStats();
        if (stats == null) return SteamError.NotInitialized;

        if (c.SteamAPI_ISteamUserStats_RequestCurrentStats(stats) == 0) {
            return SteamError.RequestFailed;
        }
    }
};

// ============================================================================
// Stats (for leaderboards and tracking)
// ============================================================================

pub const Stats = struct {
    /// Set an integer stat
    pub fn setInt(name: []const u8, value: i32) SteamError!void {
        if (!initialized) return SteamError.NotInitialized;

        const stats = c.SteamUserStats();
        if (stats == null) return SteamError.NotInitialized;

        const name_z = std.heap.c_allocator.dupeZ(u8, name) catch return SteamError.RequestFailed;
        defer std.heap.c_allocator.free(name_z);

        if (c.SteamAPI_ISteamUserStats_SetStatInt32(stats, name_z, value) == 0) {
            return SteamError.RequestFailed;
        }
    }

    /// Set a float stat
    pub fn setFloat(name: []const u8, value: f32) SteamError!void {
        if (!initialized) return SteamError.NotInitialized;

        const stats = c.SteamUserStats();
        if (stats == null) return SteamError.NotInitialized;

        const name_z = std.heap.c_allocator.dupeZ(u8, name) catch return SteamError.RequestFailed;
        defer std.heap.c_allocator.free(name_z);

        if (c.SteamAPI_ISteamUserStats_SetStatFloat(stats, name_z, value) == 0) {
            return SteamError.RequestFailed;
        }
    }

    /// Get an integer stat
    pub fn getInt(name: []const u8) SteamError!i32 {
        if (!initialized) return SteamError.NotInitialized;

        const stats = c.SteamUserStats();
        if (stats == null) return SteamError.NotInitialized;

        const name_z = std.heap.c_allocator.dupeZ(u8, name) catch return SteamError.RequestFailed;
        defer std.heap.c_allocator.free(name_z);

        var value: i32 = 0;
        if (c.SteamAPI_ISteamUserStats_GetStatInt32(stats, name_z, &value) == 0) {
            return SteamError.RequestFailed;
        }

        return value;
    }

    /// Store all stats to Steam servers
    pub fn store() SteamError!void {
        if (!initialized) return SteamError.NotInitialized;

        const stats = c.SteamUserStats();
        if (stats == null) return SteamError.NotInitialized;

        if (c.SteamAPI_ISteamUserStats_StoreStats(stats) == 0) {
            return SteamError.RequestFailed;
        }
    }
};

// ============================================================================
// Overlay
// ============================================================================

pub const Overlay = struct {
    /// Check if Steam overlay is enabled
    pub fn isEnabled() bool {
        if (!initialized) return false;
        const utils = c.SteamUtils();
        if (utils == null) return false;
        return c.SteamAPI_ISteamUtils_IsOverlayEnabled(utils) != 0;
    }

    /// Open Steam overlay to a specific dialog
    /// Valid dialogs: "friends", "community", "players", "settings",
    ///                "officialgamegroup", "stats", "achievements"
    pub fn activate(dialog: []const u8) SteamError!void {
        if (!initialized) return SteamError.NotInitialized;

        const friends = c.SteamFriends();
        if (friends == null) return SteamError.NotInitialized;

        const dialog_z = std.heap.c_allocator.dupeZ(u8, dialog) catch return SteamError.RequestFailed;
        defer std.heap.c_allocator.free(dialog_z);

        c.SteamAPI_ISteamFriends_ActivateGameOverlay(friends, dialog_z);
    }

    /// Open Steam overlay to a URL
    pub fn openUrl(url: []const u8) SteamError!void {
        if (!initialized) return SteamError.NotInitialized;

        const friends = c.SteamFriends();
        if (friends == null) return SteamError.NotInitialized;

        const url_z = std.heap.c_allocator.dupeZ(u8, url) catch return SteamError.RequestFailed;
        defer std.heap.c_allocator.free(url_z);

        c.SteamAPI_ISteamFriends_ActivateGameOverlayToWebPage(friends, url_z, c.k_EActivateGameOverlayToWebPageMode_Default);
    }

    /// Open Steam store page for current app
    pub fn openStore() SteamError!void {
        if (!initialized) return SteamError.NotInitialized;

        const friends = c.SteamFriends();
        if (friends == null) return SteamError.NotInitialized;

        const utils = c.SteamUtils();
        if (utils == null) return SteamError.NotInitialized;

        const app_id = c.SteamAPI_ISteamUtils_GetAppID(utils);
        c.SteamAPI_ISteamFriends_ActivateGameOverlayToStore(friends, app_id, c.k_EOverlayToStoreFlag_None);
    }
};

// ============================================================================
// Cloud Saves
// ============================================================================

pub const Cloud = struct {
    /// Check if cloud saves are enabled for this app
    pub fn isEnabled() bool {
        if (!initialized) return false;
        const remote = c.SteamRemoteStorage();
        if (remote == null) return false;
        return c.SteamAPI_ISteamRemoteStorage_IsCloudEnabledForApp(remote) != 0;
    }

    /// Write data to Steam Cloud
    pub fn write(filename: []const u8, data: []const u8) SteamError!void {
        if (!initialized) return SteamError.NotInitialized;

        const remote = c.SteamRemoteStorage();
        if (remote == null) return SteamError.NotInitialized;

        const filename_z = std.heap.c_allocator.dupeZ(u8, filename) catch return SteamError.RequestFailed;
        defer std.heap.c_allocator.free(filename_z);

        if (c.SteamAPI_ISteamRemoteStorage_FileWrite(remote, filename_z, data.ptr, @intCast(data.len)) == 0) {
            return SteamError.RequestFailed;
        }
    }

    /// Read data from Steam Cloud
    pub fn read(allocator: std.mem.Allocator, filename: []const u8) SteamError![]u8 {
        if (!initialized) return SteamError.NotInitialized;

        const remote = c.SteamRemoteStorage();
        if (remote == null) return SteamError.NotInitialized;

        const filename_z = std.heap.c_allocator.dupeZ(u8, filename) catch return SteamError.RequestFailed;
        defer std.heap.c_allocator.free(filename_z);

        const size = c.SteamAPI_ISteamRemoteStorage_GetFileSize(remote, filename_z);
        if (size <= 0) return SteamError.RequestFailed;

        const buffer = allocator.alloc(u8, @intCast(size)) catch return SteamError.RequestFailed;
        errdefer allocator.free(buffer);

        const read_size = c.SteamAPI_ISteamRemoteStorage_FileRead(remote, filename_z, buffer.ptr, size);
        if (read_size != size) {
            allocator.free(buffer);
            return SteamError.RequestFailed;
        }

        return buffer;
    }

    /// Check if a file exists in Steam Cloud
    pub fn exists(filename: []const u8) SteamError!bool {
        if (!initialized) return SteamError.NotInitialized;

        const remote = c.SteamRemoteStorage();
        if (remote == null) return SteamError.NotInitialized;

        const filename_z = std.heap.c_allocator.dupeZ(u8, filename) catch return SteamError.RequestFailed;
        defer std.heap.c_allocator.free(filename_z);

        return c.SteamAPI_ISteamRemoteStorage_FileExists(remote, filename_z) != 0;
    }

    /// Delete a file from Steam Cloud
    pub fn delete(filename: []const u8) SteamError!void {
        if (!initialized) return SteamError.NotInitialized;

        const remote = c.SteamRemoteStorage();
        if (remote == null) return SteamError.NotInitialized;

        const filename_z = std.heap.c_allocator.dupeZ(u8, filename) catch return SteamError.RequestFailed;
        defer std.heap.c_allocator.free(filename_z);

        if (c.SteamAPI_ISteamRemoteStorage_FileDelete(remote, filename_z) == 0) {
            return SteamError.RequestFailed;
        }
    }
};

// ============================================================================
// App Info
// ============================================================================

pub const App = struct {
    /// Get the current App ID
    pub fn getId() ?u32 {
        if (!initialized) return null;
        const utils = c.SteamUtils();
        if (utils == null) return null;
        return c.SteamAPI_ISteamUtils_GetAppID(utils);
    }

    /// Get current game language (e.g., "english", "german")
    pub fn getLanguage() ?[]const u8 {
        if (!initialized) return null;
        const apps = c.SteamApps();
        if (apps == null) return null;
        const lang = c.SteamAPI_ISteamApps_GetCurrentGameLanguage(apps);
        if (lang == null) return null;
        return std.mem.span(lang);
    }

    /// Check if app is owned (DRM check)
    pub fn isSubscribed() bool {
        if (!initialized) return false;
        const apps = c.SteamApps();
        if (apps == null) return false;
        return c.SteamAPI_ISteamApps_BIsSubscribed(apps) != 0;
    }

    /// Check if running in VR mode
    pub fn isVRMode() bool {
        if (!initialized) return false;
        const utils = c.SteamUtils();
        if (utils == null) return false;
        return c.SteamAPI_ISteamUtils_IsSteamRunningInVR(utils) != 0;
    }
};
