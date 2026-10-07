import Foundation

extension CloudSyncEngine {
    /// Persist the per-file failure reasons so they can be inspected (the UI
    /// only shows a count). Lives next to the backups for this app.
    func writeFailureLog(appID: Int, report: CloudSyncReport, helperNotes: [String] = []) {
        let dir = AppPaths.cloudSaveBackupsDirectory(forAppID: appID)
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
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Record a sync that failed before it got far enough to build a real
    /// report (i.e. listing cloud files itself failed) — see the call site.
    func writeAbortedSyncLog(appID: Int, reason: String) {
        let dir = AppPaths.cloudSaveBackupsDirectory(forAppID: appID)
        let url = dir.appendingPathComponent("last-sync.log")
        var text = "Sync \(Date())\n"
        text += "helper binary: \(CloudSyncClient.locateBinary()?.path ?? "not found")\n"
        text += "FAILED before listing cloud files completed: \(reason)\n"
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Copy every regular file under `dirs` into a fresh timestamped backup
    /// folder, preserving the path tail after the user home so a restore is
    /// obvious. Returns the backup root.
    func snapshotBackup(appID: Int, dirs: Set<URL>, label: String) throws -> URL {
        let fm = FileManager.default
        let stamp = Self.timestampFormatter.string(from: Date())
        let root = AppPaths.cloudSaveBackupsDirectory(forAppID: appID)
            .appendingPathComponent("\(stamp)-\(label)", isDirectory: true)
        var copiedAnything = false
        for dir in dirs where fm.fileExists(atPath: dir.path) {
            // Mirror the directory under the backup root using its last two
            // path components (enough to disambiguate save folders).
            let tail = dir.pathComponents.suffix(3).joined(separator: "/")
            let dest = root.appendingPathComponent(tail, isDirectory: true)
            try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
            try fm.copyItem(at: dir, to: dest)
            copiedAnything = true
        }
        if !copiedAnything {
            try? fm.createDirectory(at: root, withIntermediateDirectories: true)
        }
        return root
    }

    static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()
}
