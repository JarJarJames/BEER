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

@MainActor
final class CloudSyncEngine: ObservableObject {

    @Published private(set) var isSyncing: Bool = false

    @Published private(set) var phase: String = ""

    @Published private(set) var lastSyncAt: Date? = nil

    @Published private(set) var lastReport: CloudSyncReport? = nil

    @Published var lastError: String? = nil

    let client = CloudSyncClient()

    /// Save directories learned from the last successful sync, per appID. Kept
    /// so `localSaveFingerprint` can tell whether a play session wrote anything
    /// without spending a Steam logon to find out.
    var knownSaveDirs: [Int: Set<URL>] = [:]

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

    func run(bottle: Bottle, appID: Int, auth: SteamAuthStore, doPull: Bool, doPush: Bool) async throws -> CloudSyncReport {
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

    func summary(_ r: CloudSyncReport, doPull: Bool, doPush: Bool) -> String {
        var parts: [String] = []
        if doPull { parts.append("\(r.downloaded) pulled") }
        if doPush { parts.append("\(r.uploaded) pushed") }
        parts.append("\(r.skipped) up-to-date")
        if !r.failures.isEmpty { parts.append("\(r.failures.count) failed") }
        return parts.joined(separator: ", ") + "."
    }
}
