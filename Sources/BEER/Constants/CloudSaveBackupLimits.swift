import Foundation

/// How many cloud-save snapshots BEER keeps. Every sync used to add a full copy
/// of a game's save folders and nothing removed them; two Kingdom Come games
/// grew past 400 GB that way.
enum CloudSaveBackupLimits {
    /// Overrides `defaultSnapshotsPerGame` when set to a positive number:
    /// `defaults write <bundle id> cloudSaveBackupsPerGame -int 5`.
    static let snapshotsPerGameKey = "cloudSaveBackupsPerGame"

    static let defaultSnapshotsPerGame = 3

    static var snapshotsPerGame: Int {
        let configured = UserDefaults.standard.integer(forKey: snapshotsPerGameKey)
        return configured > 0 ? configured : defaultSnapshotsPerGame
    }

    /// One game's backups above this get a warning in the log.
    static let warnAboveBytes: Int64 = 20 * 1024 * 1024 * 1024

    /// Snapshots with this label are taken right before BEER deletes the local
    /// saves, so they may be the only copy left. Retention never removes them.
    static let neverPrunedLabel = "before-clear"

    /// Written into each snapshot so the next sync can tell nothing changed.
    static let fingerprintFileName = ".beer-fingerprint"

    /// Written into each snapshot: which save folder each copied folder came
    /// from, so a restore knows where to put it back. Older snapshots lack it.
    static let sourcesFileName = ".beer-sources.json"

    /// Taken right before a restore replaces the local saves.
    static let beforeRestoreLabel = "before-restore"

    /// Steam's copies of restored saves, downloaded before the restored saves
    /// are uploaded over them.
    static let steamCloudCopyLabel = "steam-cloud-copy"

    /// Present in a game's backup folder from a restore until the player picks
    /// which saves to keep. Every sync stops on it, and the snapshot it names
    /// is not pruned meanwhile.
    static let pendingRestoreFileName = "pending-restore.json"

    /// How far below the Wine user folder (or the game's folder) a restore
    /// looks for the save folder of a backup that didn't record it.
    static let restoreSearchDepth = 8

    /// Set once the launch cleanup has applied retention to old backups.
    static let launchCleanupDoneKey = "cloudSaveBackupRetentionApplied"
}
