import Foundation

enum AppPaths {
    /// Application Support root for all on-disk state (bottles, runtimes,
    /// downloads, the CloudSync helper, save backups).
    ///
    /// Resolved once. The app was formerly named "GameNativeMac"; on first
    /// access we migrate that directory to "BEER" with a single atomic rename
    /// (same volume), so existing installs keep their bottles and saves. If the
    /// rename fails we keep using the legacy directory rather than orphan data.
    static let applicationSupport: URL = {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let new = base.appendingPathComponent("BEER", isDirectory: true)
        let legacy = base.appendingPathComponent("GameNativeMac", isDirectory: true)
        if fm.fileExists(atPath: legacy.path), !fm.fileExists(atPath: new.path) {
            do {
                try fm.moveItem(at: legacy, to: new)
            } catch {
                NSLog("BEER: storage migration failed, using legacy directory: \(error.localizedDescription)")
                return legacy
            }
        }
        return new
    }()

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
        prefixURL(for: bottle).appendingPathComponent("beer.log")
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

    /// Legacy plaintext Steam Cloud auth file from older builds. The refresh
    /// token now lives in the Keychain (see `Keychain` / `SteamAuthStore`);
    /// this path only exists so `load()` can migrate and delete it.
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

    // Graphics translators (DXVK / DXMT) downloaded once at app level, then
    // their DLLs are copied into each bottle that selects them.
    static var translatorsDirectory: URL {
        applicationSupport.appendingPathComponent("Translators", isDirectory: true)
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
