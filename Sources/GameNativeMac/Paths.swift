import Foundation

enum AppPaths {
    static var applicationSupport: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("GameNativeMac", isDirectory: true)
    }

    static var bottlesDirectory: URL {
        applicationSupport.appendingPathComponent("Bottles", isDirectory: true)
    }

    static var runtimesDirectory: URL {
        applicationSupport.appendingPathComponent("Runtimes", isDirectory: true)
    }

    static var downloadsDirectory: URL {
        applicationSupport.appendingPathComponent("Downloads", isDirectory: true)
    }

    static var metadataURL: URL {
        applicationSupport.appendingPathComponent("bottles.json")
    }

    static func prefixURL(for bottle: Bottle) -> URL {
        bottlesDirectory.appendingPathComponent(bottle.folderName, isDirectory: true)
    }

    static func logsURL(for bottle: Bottle) -> URL {
        prefixURL(for: bottle).appendingPathComponent("gamenative.log")
    }

    static func steamDirectoryURL(for bottle: Bottle) -> URL {
        prefixURL(for: bottle)
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("Program Files (x86)", isDirectory: true)
            .appendingPathComponent("Steam", isDirectory: true)
    }

    static func steamLogsDirectoryURL(for bottle: Bottle) -> URL {
        steamDirectoryURL(for: bottle).appendingPathComponent("logs", isDirectory: true)
    }

    static func steamLogURL(for bottle: Bottle, name: String) -> URL {
        steamLogsDirectoryURL(for: bottle).appendingPathComponent(name, isDirectory: false)
    }

    // (legacy — old SteamCMD-via-Wine path; superseded by DepotDownloader)
    static var steamCMDDirectory: URL {
        applicationSupport.appendingPathComponent("SteamCMD", isDirectory: true)
    }

    static var steamCMDExecutableURL: URL {
        steamCMDDirectory.appendingPathComponent("steamcmd.exe", isDirectory: false)
    }

    // App-level DepotDownloader install. Native macOS Apple Silicon binary,
    // no Wine, no .NET runtime. One install shared across all game bottles —
    // its account.config caches the refresh token so we only sign in once.
    static var depotDownloaderDirectory: URL {
        applicationSupport.appendingPathComponent("DepotDownloader", isDirectory: true)
    }

    static var depotDownloaderExecutableURL: URL {
        depotDownloaderDirectory.appendingPathComponent("DepotDownloader", isDirectory: false)
    }

    static var steamLibraryStateURL: URL {
        applicationSupport.appendingPathComponent("steam-library.json")
    }

    /// Persisted Steam Cloud auth (refresh token + cached access token).
    /// TODO(security): move into the Keychain — refresh tokens grant access
    /// to the user's Steam account. For v1 we keep them in Application
    /// Support like the rest of our state.
    static var steamCloudAuthStateURL: URL {
        applicationSupport.appendingPathComponent("steam-cloud-auth.json")
    }

    // CloudSync helper — native SteamKit2-based binary that does real
    // bidirectional Steam Cloud (enumerate/download/upload). Located at runtime
    // from several candidate paths (see CloudSyncClient.locateBinary()).
    static var cloudSyncDirectory: URL {
        applicationSupport.appendingPathComponent("CloudSync", isDirectory: true)
    }

    static var cloudSyncExecutableURL: URL {
        cloudSyncDirectory.appendingPathComponent("CloudSync", isDirectory: false)
    }

    /// Timestamped, out-of-bottle backups of a game's save folders. We snapshot
    /// here before EVERY cloud pull/push and before any "clear local saves", so
    /// a long-played save can always be recovered — even if a bottle is wiped.
    static func cloudSaveBackupsDirectory(forAppID appID: Int) -> URL {
        applicationSupport
            .appendingPathComponent("CloudSaveBackups", isDirectory: true)
            .appendingPathComponent(String(appID), isDirectory: true)
    }

    // App-level GBE_Fork ("Goldberg") Steamworks emulator install. The Windows
    // release contains the steam_api*.dll stubs we drop into game directories
    // so games launch without a running Steam process.
    static var goldbergDirectory: URL {
        applicationSupport.appendingPathComponent("Goldberg", isDirectory: true)
    }

    static func ensureBaseDirectories() throws {
        try FileManager.default.createDirectory(at: bottlesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
    }
}
