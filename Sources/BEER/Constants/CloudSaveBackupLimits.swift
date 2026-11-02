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

    /// Set once the launch cleanup has applied retention to old backups.
    static let launchCleanupDoneKey = "cloudSaveBackupRetentionApplied"
}
