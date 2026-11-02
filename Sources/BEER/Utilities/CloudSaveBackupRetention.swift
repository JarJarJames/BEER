import Foundation

/// Deciding which cloud-save snapshots to keep. A snapshot is a folder named
/// `<yyyy-MM-dd_HH-mm-ss>-<label>` inside a game's backup folder; anything
/// else there (`last-sync.log`, folders the user made) is never touched.
enum CloudSaveBackupRetention {
    /// The snapshot folders in `appDirectory`, newest first.
    static func snapshots(in appDirectory: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: appDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: []
        )) ?? []
        return entries
            .filter { isSnapshotName($0.lastPathComponent) && isDirectory($0) }
            // The timestamp prefix sorts the same as the time it records.
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    static func isSnapshotName(_ name: String) -> Bool {
        // `CloudSyncEngine.timestampFormatter`'s yyyy-MM-dd_HH-mm-ss, a dash, a label.
        name.range(of: #"^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}-."#, options: .regularExpression) != nil
    }

    /// The snapshots retention would remove: every empty one, and every one
    /// past the newest `keep` (not counting `before-clear` snapshots, which
    /// are always kept). `protecting`, a snapshot in `appDirectory`, is never
    /// included and counts toward `keep`.
    static func snapshotsToPrune(in appDirectory: URL, keep: Int, protecting: URL? = nil) -> [URL] {
        var kept = 0
        var prune: [URL] = []
        for snapshot in snapshots(in: appDirectory) {
            if snapshot.lastPathComponent == protecting?.lastPathComponent { kept += 1; continue }
            if isEmpty(snapshot) { prune.append(snapshot); continue }
            if snapshot.lastPathComponent.hasSuffix("-\(CloudSaveBackupLimits.neverPrunedLabel)") { continue }
            if kept < keep { kept += 1 } else { prune.append(snapshot) }
        }
        return prune
    }

    /// Remove what `snapshotsToPrune` lists. Returns the bytes freed.
    @discardableResult
    static func prune(appDirectory: URL, keep: Int, protecting: URL? = nil) -> Int64 {
        remove(snapshotsToPrune(in: appDirectory, keep: keep, protecting: protecting))
    }

    /// What retention would remove across every game under `root` (the
    /// CloudSaveBackups folder), and how much space that frees.
    static func cleanupPlan(root: URL, keep: Int) -> (snapshots: [URL], bytes: Int64) {
        let appDirs = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        let snapshots = appDirs.filter(isDirectory).flatMap { snapshotsToPrune(in: $0, keep: keep) }
        return (snapshots, snapshots.reduce(0) { $0 + byteCount(of: $1) })
    }

    /// Delete `snapshots`, logging and skipping any that can't be removed.
    /// Returns the bytes freed.
    @discardableResult
    static func remove(_ snapshots: [URL]) -> Int64 {
        var freed: Int64 = 0
        for snapshot in snapshots {
            let size = byteCount(of: snapshot)
            if attempt("remove old save backup", log: Log.cloudSync, {
                try FileManager.default.removeItem(at: snapshot)
            }) != nil {
                freed += size
            }
        }
        return freed
    }

    /// A signature of every file under `dirs`: path, size and modification
    /// time. Nil when there are no files.
    static func fingerprint(of dirs: Set<URL>) -> String? {
        var parts: [String] = []
        for dir in dirs {
            forEachFile(under: dir, keys: [.contentModificationDateKey, .fileSizeKey]) { url, values in
                let mtime = values.contentModificationDate?.timeIntervalSince1970 ?? 0
                parts.append("\(url.path):\(mtime):\(values.fileSize ?? 0)")
            }
        }
        return parts.isEmpty ? nil : parts.sorted().joined(separator: "|")
    }

    static func byteCount(of dir: URL) -> Int64 {
        var total: Int64 = 0
        forEachFile(under: dir, keys: [.totalFileAllocatedSizeKey, .fileSizeKey]) { _, values in
            total += Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
        }
        return total
    }

    private static func isEmpty(_ dir: URL) -> Bool {
        var found = false
        forEachFile(under: dir, keys: []) { _, _ in found = true }
        return !found
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private static func forEachFile(
        under dir: URL, keys: [URLResourceKey], _ body: (URL, URLResourceValues) -> Void
    ) {
        let allKeys = Set(keys + [.isRegularFileKey])
        guard let walker = FileManager.default.enumerator(
            at: dir, includingPropertiesForKeys: Array(allKeys),
            options: [.skipsHiddenFiles]
        ) else { return }
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: allKeys), values.isRegularFile == true else { continue }
            body(url, values)
        }
    }
}
