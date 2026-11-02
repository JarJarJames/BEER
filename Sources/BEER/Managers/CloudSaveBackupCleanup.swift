import AppKit

/// One pass at launch that applies snapshot retention to the backups made
/// before BEER pruned them. It can delete hundreds of GB, so it asks first and
/// only remembers it ran once the user agreed (or there was nothing to free).
@MainActor
enum CloudSaveBackupCleanup {
    static func offerIfNeeded(root: URL = AppPaths.cloudSaveBackupsRoot, defaults: UserDefaults = .standard) async {
        guard !defaults.bool(forKey: CloudSaveBackupLimits.launchCleanupDoneKey) else { return }
        let keep = CloudSaveBackupLimits.snapshotsPerGame
        let plan = await Task.detached { CloudSaveBackupRetention.cleanupPlan(root: root, keep: keep) }.value
        guard !plan.snapshots.isEmpty else {
            defaults.set(true, forKey: CloudSaveBackupLimits.launchCleanupDoneKey)
            return
        }

        let size = ByteCountFormatter.string(fromByteCount: plan.bytes, countStyle: .file)
        let alert = NSAlert()
        alert.messageText = "Free \(size) of old save backups?"
        alert.informativeText = """
            BEER used to copy a game's saves before every cloud sync and never removed the copies. \
            It now keeps the newest \(keep) per game, plus every backup made before clearing local saves.

            This deletes \(plan.snapshots.count) older or empty backups from CloudSaveBackups. \
            Your current saves and installed games are not touched.
            """
        alert.addButton(withTitle: "Delete Old Backups")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let freed = await Task.detached { CloudSaveBackupRetention.remove(plan.snapshots) }.value
        Log.cloudSync.info("Launch cleanup removed \(plan.snapshots.count, privacy: .public) old save backups, freeing \(freed, privacy: .public) bytes")
        defaults.set(true, forKey: CloudSaveBackupLimits.launchCleanupDoneKey)
    }
}
