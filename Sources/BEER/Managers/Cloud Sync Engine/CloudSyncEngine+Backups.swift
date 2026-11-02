import Foundation

extension CloudSyncEngine {
    /// Persist the per-file failure reasons so they can be inspected (the UI
    /// only shows a count). Lives next to the backups for this app.
    func writeFailureLog(appID: Int, report: CloudSyncReport, helperNotes: [String] = []) {
        let dir = backupsDirectory(appID)
        let url = dir.appendingPathComponent("last-sync.log")
        var text = "Sync \(Date())\n"
        // Which helper actually ran. A stale binary shadowing the installed one
        // is invisible otherwise, and it looks exactly like a helper bug.
        text += "helper binary: \(CloudSyncClient.locateBinary()?.path ?? "not found")\n"
        text += "downloaded=\(report.downloaded) uploaded=\(report.uploaded) skipped=\(report.skipped) failed=\(report.failures.count)\n\n"
        if report.failures.isEmpty {
            text += "(no failures)\n"
        } else {
            for f in report.failures {
                text += "FAIL\t\(f.filename)\t\(f.reason)\n"
            }
        }
        if !helperNotes.isEmpty {
            text += "\nhelper:\n"
            for note in helperNotes { text += "  \(note)\n" }
        }
        attempt("write last-sync.log", log: Log.cloudSync) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Record a sync that stopped before it got far enough to build a real
    /// report: listing cloud files failed, or the backup did.
    func writeAbortedSyncLog(appID: Int, stage: String, reason: String) {
        let dir = backupsDirectory(appID)
        let url = dir.appendingPathComponent("last-sync.log")
        var text = "Sync \(Date())\n"
        text += "helper binary: \(CloudSyncClient.locateBinary()?.path ?? "not found")\n"
        text += "FAILED while \(stage), before any file was written: \(reason)\n"
        attempt("write last-sync.log", log: Log.cloudSync) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Snapshot `dirs` before anything is written. A sync that can't make this
    /// copy must not run: it is the only way back from a bad overwrite. The
    /// failure is logged and rethrown as `CloudSyncError.backupFailed`.
    func backUpBeforeWriting(appID: Int, dirs: Set<URL>, label: String) throws -> URL? {
        do {
            return try snapshotBackup(appID: appID, dirs: dirs, label: label)
        } catch {
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            Log.cloudSync.error("Backup before writing saves for app \(appID, privacy: .public) failed; sync stopped: \(reason)")
            writeAbortedSyncLog(appID: appID, stage: "backing up local saves", reason: reason)
            throw CloudSyncError.backupFailed(reason)
        }
    }

    /// Copy every file under `dirs` into a fresh timestamped backup folder,
    /// preserving the path tail after the user home so a restore is obvious.
    /// Returns the snapshot holding the current saves: the newest existing one
    /// when nothing changed since it was taken, otherwise a new one. Nil when
    /// there are no saves to copy.
    func snapshotBackup(appID: Int, dirs: Set<URL>, label: String) throws -> URL? {
        let fm = FileManager.default
        let appDir = backupsDirectory(appID)
        // Even with nothing to copy, an unwritable backup folder means a full
        // or broken disk, and the sync must stop.
        try fm.createDirectory(at: appDir, withIntermediateDirectories: true)

        let presentDirs = dirs.filter { fm.fileExists(atPath: $0.path) }
        guard let files = CloudSaveBackupRetention.fingerprint(of: presentDirs) else { return nil }
        let fingerprint = SHA256Digest.hexDigest(Data(files.utf8))
        // A before-clear snapshot always gets its own copy: retention never
        // removes it, and the saves it holds are about to be deleted.
        if label != CloudSaveBackupLimits.neverPrunedLabel,
           let newest = CloudSaveBackupRetention.snapshots(in: appDir).first,
           storedFingerprint(of: newest) == fingerprint {
            return newest
        }

        let stamp = Self.timestampFormatter.string(from: Date())
        let root = appDir.appendingPathComponent("\(stamp)-\(label)", isDirectory: true)
        do {
            var sources: [String: String] = [:]
            for dir in presentDirs {
                // Mirror the directory under the backup root using its last
                // three path components (enough to disambiguate save folders).
                let tail = Self.snapshotTail(of: dir)
                let dest = root.appendingPathComponent(tail, isDirectory: true)
                try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                try fm.copyItem(at: dir, to: dest)
                sources[tail] = dir.path
            }
            try writeSources(sources, into: root)
            // Written last, so only a complete copy can stand in for a later one.
            try fingerprint.write(to: root.appendingPathComponent(CloudSaveBackupLimits.fingerprintFileName),
                                  atomically: true, encoding: .utf8)
        } catch {
            try? fm.removeItem(at: root)
            throw error
        }
        pruneBackups(appID: appID, keeping: root)
        return root
    }

    /// Where a save folder goes inside a snapshot.
    nonisolated static func snapshotTail(of dir: URL) -> String {
        dir.pathComponents.suffix(3).joined(separator: "/")
    }

    /// Record which save folder each copied folder came from, so a restore
    /// can put it back.
    func writeSources(_ sources: [String: String], into snapshot: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(sources).write(to: snapshot.appendingPathComponent(CloudSaveBackupLimits.sourcesFileName),
                                          options: .atomic)
    }

    private func storedFingerprint(of snapshot: URL) -> String? {
        try? String(contentsOf: snapshot.appendingPathComponent(CloudSaveBackupLimits.fingerprintFileName), encoding: .utf8)
    }

    /// Apply retention after a new snapshot.
    func pruneBackups(appID: Int, keeping snapshot: URL) {
        let appDir = backupsDirectory(appID)
        let freed = CloudSaveBackupRetention.prune(appDirectory: appDir, keep: snapshotsToKeep, protecting: snapshot)
        if freed > 0 {
            Log.cloudSync.info("Pruned \(freed, privacy: .public) bytes of old save backups for app \(appID, privacy: .public)")
        }
        let total = CloudSaveBackupRetention.byteCount(of: appDir)
        if total > CloudSaveBackupLimits.warnAboveBytes {
            Log.cloudSync.warning("Save backups for app \(appID, privacy: .public) use \(total, privacy: .public) bytes, over the \(CloudSaveBackupLimits.warnAboveBytes, privacy: .public)-byte warning threshold")
        }
    }

    static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()
}
