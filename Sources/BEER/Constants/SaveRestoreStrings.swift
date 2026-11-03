import Foundation

/// User-facing text for browsing and restoring save backups, and for the
/// prompt that settles a restore with Steam Cloud.
enum SaveRestoreStrings {
    static let menuItem = "Manage or Restore Backups…"
    static let sheetTitle = "Manage or Restore Backups"
    static let sheetCaption = "BEER copies your saves here before every sync, and before clearing or restoring them. The newest few are kept per game."
    static let emptyList = "No backups yet. One is made the first time this game syncs."
    static let restoreButton = "Restore…"
    static let revealButton = "Show in Finder"
    static let doneButton = "Done"
    static let busy = "Unavailable while the game is running or a sync is in progress."

    static func trigger(_ label: String) -> String {
        switch label {
        case "before-sync": return "Before a sync"
        case "before-pull": return "Before a pull"
        case CloudSaveBackupLimits.neverPrunedLabel: return "Before clearing saves"
        case CloudSaveBackupLimits.beforeRestoreLabel: return "Before a restore"
        case CloudSaveBackupLimits.steamCloudCopyLabel: return "Steam Cloud's copy"
        default: return label
        }
    }

    static func fileSummary(count: Int, bytes: Int64) -> String {
        "\(count) file\(count == 1 ? "" : "s") · \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    // MARK: Confirming a restore

    static func confirmTitle(_ date: Date) -> String {
        "Restore the backup from \(date.formatted(date: .abbreviated, time: .shortened))?"
    }

    static let confirmButton = "Back Up Current Saves & Restore"

    static func confirmMessage(_ plan: SaveRestorePlan) -> String {
        let folders = plan.folders.map { CloudSyncEngine.snapshotTail(of: $0.target) }.joined(separator: ", ")
        var lines = ["• Puts back \(plan.filesRestored) file\(plan.filesRestored == 1 ? "" : "s") in \(folders)."]
        if let changed = plan.currentLastChanged {
            lines.append("• Replaces your current saves, last changed \(changed.formatted(date: .abbreviated, time: .shortened)).")
        }
        if plan.filesRemoved > 0 {
            lines.append("• Removes \(plan.filesRemoved) file\(plan.filesRemoved == 1 ? "" : "s") that aren't in this backup.")
        }
        lines.append("• Your current saves are backed up first, so this can be undone from this list.")
        lines.append("• Steam Cloud isn't changed. Your next sync, or launching the game, asks whether to keep these saves or Steam Cloud's.")
        return lines.joined(separator: "\n")
    }

    static func restored(_ date: Date) -> String {
        "Restored the backup from \(date.formatted(date: .abbreviated, time: .shortened)). Your next sync will ask which saves to keep."
    }

    static func pendingCaption(_ pending: PendingSaveRestore) -> String {
        "You restored the backup from \(pending.snapshotDate.formatted(date: .abbreviated, time: .shortened)). Your next sync, or launching the game, asks whether to keep it or Steam Cloud's saves."
    }

    // MARK: Settling with Steam Cloud

    static let conflictTitle = "Your Restored Saves Differ from Steam Cloud"
    static let conflictIntro = "You restored a backup on this Mac. Steam Cloud still has different saves. Choose which to keep. Nothing has changed yet."
    static let localSide = "Restored saves on this Mac"
    static let cloudSide = "Steam Cloud"

    static func localDetail(_ c: SaveRestoreConflict) -> [String] {
        ["From the backup of \(c.pending.snapshotDate.formatted(date: .abbreviated, time: .shortened))",
         "\(c.localFileCount) file\(c.localFileCount == 1 ? "" : "s")",
         c.localLastChanged.map { "Last changed \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No files"]
    }

    static func cloudDetail(_ c: SaveRestoreConflict) -> [String] {
        ["\(c.cloudFileCount) file\(c.cloudFileCount == 1 ? "" : "s"), \(c.differingCloudFiles.count) different from yours",
         c.cloudLastUploaded.map { "Last uploaded \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "No files"]
    }

    static let keepRestoredButton = "Keep Restored Saves"
    static func keepRestoredConsequence(_ c: SaveRestoreConflict) -> String {
        "Uploads your restored saves to Steam, replacing \(c.differingCloudFiles.count) of Steam Cloud's files on every device. BEER downloads Steam's copies into a backup first, and uploads nothing if that fails."
    }

    static let useCloudButton = "Use Steam Cloud Saves"
    static let useCloudConsequence = "Downloads Steam Cloud's saves over the restored ones on this Mac. The restored saves are backed up first, and the backup you restored from stays in the list."

    static let cancelButton = "Decide Later"
    static let cancelSyncConsequence = "Nothing syncs until you choose."
    static let cancelLaunchConsequence = "The game doesn't start, and nothing syncs until you choose."

    static func keptRestored(_ r: CloudSyncReport) -> String {
        r.failures.isEmpty
            ? "Kept your restored saves: \(r.uploaded) uploaded. Steam's old copies are in Manage or Restore Backups."
            : "\(r.uploaded) restored saves uploaded, \(r.failures.count) failed. Steam's copies are in Manage or Restore Backups; sync again to retry."
    }

    static let postPlayBlocked = "Your saves weren't uploaded: a restored backup is waiting for you to choose between it and Steam Cloud. Sync from the Steam Cloud row to choose."
}
