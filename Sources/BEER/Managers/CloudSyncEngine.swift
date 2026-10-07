import Foundation

// Bidirectional Steam Cloud sync for a bottle, via the CloudSync helper.
//
// Safety is the whole point here: the user has long-played saves they cannot
// afford to lose. So:
//   • Before any pull OR push that could change local files, we snapshot every
//     tracked save file to a timestamped backup OUTSIDE the bottle
//     (~/…/BEER/CloudSaveBackups/<appid>/<timestamp>/). A wiped bottle
//     never takes the backups with it.
//   • Sync is conflict-aware: pull only overwrites a local file when the cloud
//     copy is strictly newer; push only uploads when the local copy is strictly
//     newer (or the file is new to the cloud). We never clobber the newer side.
//   • A file is keyed by Steam's own cloud filename, so push echoes back the
//     exact key Steam uses, and learns the path convention for brand-new local
//     saves from sibling cloud files.

struct CloudSyncReport {
    var downloaded: Int = 0
    var uploaded: Int = 0
    var skipped: Int = 0
    var failures: [(filename: String, reason: String)] = []
    var backupPath: URL? = nil
}

enum CloudSyncError: LocalizedError {
    case userHomeNotFound(URL)
    case notSignedIn
    case cannotInferRemotePath

    var errorDescription: String? {
        switch self {
        case .userHomeNotFound(let url):
            return "Couldn't find a Wine user home inside \(url.path). The bottle may not be initialized."
        case .notSignedIn:
            return "Connect Steam Cloud first."
        case .cannotInferRemotePath:
            return "No existing cloud files to learn the save path from. Sync once from your PC's Steam first, then push will work."
        }
    }
}

/// Maps a Steam cloud "root" token to a relative path under the Wine user home
/// (drive_c/users/<user>/). Steam uses a small, stable set of roots. We accept
/// the token with or without the surrounding %…% the client protocol uses.
private let steamRootRouting: [String: String] = [
    "WINSAVEDGAMES": "Saved Games",
    "WINAPPDATAROAMING": "AppData/Roaming",
    "WINAPPDATALOCAL": "AppData/Local",
    "WINAPPDATALOCALLOW": "AppData/LocalLow",
    "WINDOCUMENTS": "Documents",
    "WINMYDOCUMENTS": "Documents",
    "WINMYPICTURES": "Pictures",
    "WINMYMUSIC": "Music",
    "WINMYVIDEO": "Videos",
    "GAMEINSTALL": ""  // resolved specially against the install dir
]

@MainActor
final class CloudSyncEngine: ObservableObject {
    @Published private(set) var isSyncing: Bool = false
    @Published private(set) var phase: String = ""
    @Published private(set) var lastSyncAt: Date? = nil
    @Published private(set) var lastReport: CloudSyncReport? = nil
    @Published var lastError: String? = nil

    private let client = CloudSyncClient()

    /// Save directories learned from the last successful sync, per appID. Kept
    /// so `localSaveFingerprint` can tell whether a play session wrote anything
    /// without spending a Steam logon to find out.
    private var knownSaveDirs: [Int: Set<URL>] = [:]

    // MARK: - Public operations

    /// Pull newer cloud saves down. Backs up local saves first.
    func pull(bottle: Bottle, appID: Int, auth: SteamAuthStore) async throws -> CloudSyncReport {
        try await run(bottle: bottle, appID: appID, auth: auth, doPull: true, doPush: false)
    }

    /// Push newer local saves up. Backs up local saves first.
    func push(bottle: Bottle, appID: Int, auth: SteamAuthStore) async throws -> CloudSyncReport {
        try await run(bottle: bottle, appID: appID, auth: auth, doPull: false, doPush: true)
    }

    /// Full two-way sync (pull then push). Used automatically around game launch.
    func sync(bottle: Bottle, appID: Int, auth: SteamAuthStore) async throws -> CloudSyncReport {
        try await run(bottle: bottle, appID: appID, auth: auth, doPull: true, doPush: true)
    }

    /// Back up, then remove, the local saves for this game — the "start clean
    /// from cloud" / "don't let me mess up my saves" escape hatch. Never a true
    /// delete: everything is copied to a timestamped backup first.
    @discardableResult
    func backupAndClearLocalSaves(bottle: Bottle, appID: Int, auth: SteamAuthStore) async throws -> URL {
        guard let account = auth.account else { throw CloudSyncError.notSignedIn }
        isSyncing = true
        defer { isSyncing = false }

        phase = "Listing cloud files…"
        let remote = try await client.enumerate(appID: appID, account: account.accountName, refreshToken: account.refreshToken)
        let userHome = try resolveWineUserHome(for: bottle)
        let installDir = bottle.gameInstallDirectory.map { URL(fileURLWithPath: $0) }

        // Tracked local files = the local mapping of every cloud file that
        // currently exists locally.
        let trackedDirs = Set(remote.compactMap { rf -> URL? in
            mapToLocal(rf.filename, userHome: userHome, installDir: installDir)?.deletingLastPathComponent()
        })

        phase = "Backing up local saves…"
        let backup = try snapshotBackup(appID: appID, dirs: trackedDirs, label: "before-clear")

        phase = "Clearing local saves…"
        for dir in trackedDirs where FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.removeItem(at: dir)
        }
        phase = "Local saves cleared. Backup saved."
        lastSyncAt = Date()
        return backup
    }

    // MARK: - Core sync

    private func run(bottle: Bottle, appID: Int, auth: SteamAuthStore, doPull: Bool, doPush: Bool) async throws -> CloudSyncReport {
        guard let account = auth.account else { throw CloudSyncError.notSignedIn }
        isSyncing = true
        defer { isSyncing = false }

        let acct = account.accountName
        let token = account.refreshToken
        let userHome = try resolveWineUserHome(for: bottle)
        let installDir = bottle.gameInstallDirectory.map { URL(fileURLWithPath: $0) }
        var report = CloudSyncReport()

        phase = "Listing cloud files…"
        let remote: [CloudRemoteFile]
        do {
            remote = try await client.enumerate(appID: appID, account: acct, refreshToken: token)
        } catch {
            // Nothing was written to last-sync.log yet — without this, a sync
            // that fails this early leaves the log (and anyone reading it to
            // check "did the last push actually go through") pointing at
            // whatever the previous SUCCESSFUL sync said, which reads as if
            // nothing had gone wrong.
            writeAbortedSyncLog(appID: appID,
                                 reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            throw error
        }

        // Snapshot every locally-present tracked file BEFORE touching anything.
        let trackedDirs = Set(remote.compactMap {
            mapToLocal($0.filename, userHome: userHome, installDir: installDir)?.deletingLastPathComponent()
        })
        if !trackedDirs.isEmpty {
            knownSaveDirs[appID] = trackedDirs
            phase = "Backing up local saves…"
            report.backupPath = try? snapshotBackup(appID: appID, dirs: trackedDirs, label: doPush ? "before-sync" : "before-pull")
        }

        // Build the work lists in Swift (cheap, local), then hand the whole set
        // to the helper for ONE logged-on session — no per-file logons.
        var downloads: [CloudSyncClient.DownloadJob] = []
        var uploads: [CloudSyncClient.UploadJob] = []

        // ---- PULL: cloud → local, only when cloud is strictly newer ----
        if doPull {
            for rf in remote {
                guard let target = mapToLocal(rf.filename, userHome: userHome, installDir: installDir) else {
                    report.failures.append((rf.filename, "unknown cloud root")); continue
                }
                // Local is strictly newer: the player's progress wins, and a
                // full sync pushes it below. Never clobber it with the cloud.
                if let mtime = fileMTime(target), mtime > rf.timestamp.addingTimeInterval(2) {
                    report.skipped += 1; continue
                }
                // Otherwise the clock can't decide anything: every file we pull
                // is stamped with the cloud's timestamp, so "same time" is the
                // normal state, and Wine touches saves on shutdown besides.
                // Contents decide. This is also what heals a file that landed
                // corrupt — matching the clock used to make it unpullable
                // forever, which is how zip-wrapped cloud saves survived a fix
                // to the downloader.
                if localFileMatchesRemote(target, remote: rf) {
                    report.skipped += 1; continue
                }
                downloads.append(.init(filename: rf.filename, out: target))
            }
        }

        // ---- PUSH: local → cloud, only when local is strictly newer / new ----
        if doPush {
            let remoteByLocalPath = Dictionary(
                remote.compactMap { rf -> (String, CloudRemoteFile)? in
                    guard let local = mapToLocal(rf.filename, userHome: userHome, installDir: installDir) else { return nil }
                    return (local.path, rf)
                },
                uniquingKeysWith: { a, _ in a }
            )
            // Learn the remote directory convention from existing cloud files:
            // local-dir → remote-dir-prefix (filename minus its last component).
            var remoteDirByLocalDir: [String: String] = [:]
            for rf in remote {
                guard let local = mapToLocal(rf.filename, userHome: userHome, installDir: installDir) else { continue }
                remoteDirByLocalDir[local.deletingLastPathComponent().path] = remoteDir(of: rf.filename)
            }

            for dir in trackedDirs {
                guard let entries = try? FileManager.default.contentsOfDirectory(
                    at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
                ) else { continue }
                for fileURL in entries {
                    guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                    guard let localMTime = fileMTime(fileURL) else { continue }

                    let remoteName: String
                    if let existing = remoteByLocalPath[fileURL.path] {
                        if localMTime <= existing.timestamp.addingTimeInterval(2) { report.skipped += 1; continue }
                        if localFileMatchesRemote(fileURL, remote: existing) {
                            report.skipped += 1; continue
                        }
                        remoteName = existing.filename
                    } else if let prefix = remoteDirByLocalDir[dir.path] {
                        remoteName = prefix.isEmpty ? fileURL.lastPathComponent : "\(prefix)/\(fileURL.lastPathComponent)"
                    } else {
                        report.failures.append((fileURL.lastPathComponent, "couldn't infer cloud path"))
                        continue
                    }
                    uploads.append(.init(filename: remoteName, local: fileURL, mtime: localMTime))
                }
            }
        }

        // ---- Execute the whole batch in one Steam session ----
        var helperNotes: [String] = []
        if !downloads.isEmpty || !uploads.isEmpty {
            let total = downloads.count + uploads.count
            phase = "Syncing \(total) file\(total == 1 ? "" : "s")…"
            let batch = try await client.batch(
                appID: appID, downloads: downloads, uploads: uploads,
                account: acct, refreshToken: token,
                onProgress: { [weak self] done, total in
                    Task { @MainActor in self?.phase = "Syncing \(done)/\(total)…" }
                }
            )
            helperNotes = batch.notes
            for op in batch.ops {
                if let err = op.error {
                    report.failures.append((op.filename, err))
                } else if op.op == "download" {
                    report.downloaded += 1
                } else {
                    report.uploaded += 1
                }
            }
        }

        lastSyncAt = Date()
        lastReport = report
        writeFailureLog(appID: appID, report: report, helperNotes: helperNotes)
        phase = summary(report, doPull: doPull, doPush: doPush)
        return report
    }

    /// Persist the per-file failure reasons so they can be inspected (the UI
    /// only shows a count). Lives next to the backups for this app.
    private func writeFailureLog(appID: Int, report: CloudSyncReport, helperNotes: [String] = []) {
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
    private func writeAbortedSyncLog(appID: Int, reason: String) {
        let dir = AppPaths.cloudSaveBackupsDirectory(forAppID: appID)
        let url = dir.appendingPathComponent("last-sync.log")
        var text = "Sync \(Date())\n"
        text += "helper binary: \(CloudSyncClient.locateBinary()?.path ?? "not found")\n"
        text += "FAILED before listing cloud files completed: \(reason)\n"
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Backups

    /// Copy every regular file under `dirs` into a fresh timestamped backup
    /// folder, preserving the path tail after the user home so a restore is
    /// obvious. Returns the backup root.
    private func snapshotBackup(appID: Int, dirs: Set<URL>, label: String) throws -> URL {
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

    private static let timestampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f
    }()

    // MARK: - Path mapping

    /// A cheap signature of every tracked save file's size and modification
    /// time. Nil when we have not yet learned where this game's saves live.
    ///
    /// Comparing this across a play session answers "did the game write
    /// anything?" locally. That matters because the alternative — always
    /// pushing — spends a Steam logon per launch, and a game that crash-loops
    /// turns that into a burst of logons that Steam starts refusing outright,
    /// taking the library refresh and the presence session down with it.
    func localSaveFingerprint(appID: Int) -> String? {
        guard let dirs = knownSaveDirs[appID], !dirs.isEmpty else { return nil }
        let fm = FileManager.default
        var parts: [String] = []
        for dir in dirs.sorted(by: { $0.path < $1.path }) {
            guard let walker = fm.enumerator(
                at: dir,
                includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let mtime = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
                let size = values?.fileSize ?? 0
                parts.append("\(url.path):\(mtime):\(size)")
            }
        }
        return parts.isEmpty ? nil : parts.sorted().joined(separator: "|")
    }

    private func resolveWineUserHome(for bottle: Bottle) throws -> URL {
        let usersDir = AppPaths.prefixURL(for: bottle)
            .appendingPathComponent("drive_c", isDirectory: true)
            .appendingPathComponent("users", isDirectory: true)
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: usersDir.path)) ?? []
        // Prefer "crossover" — our pinned Wine username (see BottleStore). A
        // bottle may also have a stale login-named folder from before we pinned
        // it; the game now always uses crossover, so sync must target it too.
        let candidate = entries.first(where: { $0 == "crossover" })
            ?? entries.filter { !$0.hasPrefix(".") }.first(where: { $0 != "Public" })
            ?? entries.first
        guard let user = candidate else { throw CloudSyncError.userHomeNotFound(usersDir) }
        return usersDir.appendingPathComponent(user, isDirectory: true)
    }

    /// Split a Steam cloud filename into (root token, remainder). The protocol
    /// uses "%Token%/rest"; some forms drop the %…%. Returns nil remainder-safe.
    private func splitRoot(_ filename: String) -> (root: String, rest: String) {
        var name = filename.replacingOccurrences(of: "\\", with: "/")
        if name.hasPrefix("/") { name.removeFirst() }
        if name.hasPrefix("%"), let close = name.dropFirst().firstIndex(of: "%") {
            let token = String(name[name.index(after: name.startIndex)..<close])
            var rest = String(name[name.index(after: close)...])
            if rest.hasPrefix("/") { rest.removeFirst() }
            return (token, rest)
        }
        // No %…%: first path component is the root token.
        let parts = name.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
        return (String(parts.first ?? ""), parts.count > 1 ? String(parts[1]) : "")
    }

    /// Map a Steam cloud filename to the local file URL inside the bottle.
    private func mapToLocal(_ filename: String, userHome: URL, installDir: URL?) -> URL? {
        let (token, rest) = splitRoot(filename)
        let key = token.uppercased()

        let base: URL
        if key == "GAMEINSTALL" {
            guard let installDir else { return nil }
            base = installDir
        } else if let rel = steamRootRouting[key] {
            base = rel.isEmpty ? userHome : appendingComponents(rel, to: userHome, isDir: true)
        } else {
            // Unknown root — treat the token itself as a folder under the home.
            base = appendingComponents(token, to: userHome, isDir: true)
        }
        return rest.isEmpty ? base : appendingComponents(rest, to: base, isDir: false)
    }

    /// The remote filename minus its last "/"-component (its directory prefix).
    private func remoteDir(of filename: String) -> String {
        let normalized = filename.replacingOccurrences(of: "\\", with: "/")
        guard let slash = normalized.lastIndex(of: "/") else { return normalized }
        return String(normalized[..<slash])
    }

    private func appendingComponents(_ path: String, to base: URL, isDir: Bool) -> URL {
        var url = base
        let comps = path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
        for (i, c) in comps.enumerated() {
            url = url.appendingPathComponent(c, isDirectory: isDir ? true : i < comps.count - 1)
        }
        return url
    }

    private func fileMTime(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    private func localFileMatchesRemote(_ url: URL, remote: CloudRemoteFile) -> Bool {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size == remote.size
        else { return false }
        return SHA1Digest.fileMatches(url, remoteDigest: remote.sha)
    }

    private func summary(_ r: CloudSyncReport, doPull: Bool, doPush: Bool) -> String {
        var parts: [String] = []
        if doPull { parts.append("\(r.downloaded) pulled") }
        if doPush { parts.append("\(r.uploaded) pushed") }
        parts.append("\(r.skipped) up-to-date")
        if !r.failures.isEmpty { parts.append("\(r.failures.count) failed") }
        return parts.joined(separator: ", ") + "."
    }
}
