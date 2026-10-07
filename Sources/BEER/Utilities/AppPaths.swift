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
    /// PID of a play-session helper that is currently announcing a game to
    /// Steam, so a BEER that died without unwinding can clean it up next launch.
    static var playSessionStateURL: URL {
        applicationSupport.appendingPathComponent("play-session.json")
    }

    /// The Steam online status the user picked, applied on every connect.
    static var presenceStateURL: URL {
        applicationSupport.appendingPathComponent("presence-state.json")
    }

    /// Everything the current/last play-session helper printed. First stop
    /// when Steam play time or in-game presence doesn't show up.
    static var playSessionLogURL: URL {
        applicationSupport.appendingPathComponent("play-session.log")
    }

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

    /// DepotDownloader's raw output for the most recent run of an app, kept so a
    /// failed install can be diagnosed after the in-memory Downloads row is gone.
    static func depotDownloaderLogURL(forAppID appID: Int) -> URL {
        applicationSupport
            .appendingPathComponent("DepotDownloaderLogs", isDirectory: true)
            .appendingPathComponent("\(appID).log", isDirectory: false)
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
    /// Artifacts for the opt-in controller fix, installed by
    /// `Tools/ControllerFix/build.sh` (the `dpad_helper` binary and the
    /// `hid.dll` shim). Mirrors how the CloudSync helper is installed.
    static var controllerFixDirectory: URL {
        applicationSupport.appendingPathComponent("ControllerFix", isDirectory: true)
    }

    static var controllerFixHelperURL: URL {
        controllerFixDirectory.appendingPathComponent("dpad_helper")
    }

    static var controllerFixShimURL: URL {
        controllerFixDirectory.appendingPathComponent("hid.dll")
    }

    static var goldbergDirectory: URL {
        applicationSupport.appendingPathComponent("Goldberg", isDirectory: true)
    }

    static func ensureBaseDirectories() throws {
        try FileManager.default.createDirectory(at: bottlesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runtimesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
    }
}
