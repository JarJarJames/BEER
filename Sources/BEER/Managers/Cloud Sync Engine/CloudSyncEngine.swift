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
//     exact key Steam uses. A brand-new local save takes its name from sibling
//     cloud files, or from the game's save rules when its folder has none.

@MainActor
final class CloudSyncEngine: ObservableObject {

    @Published private(set) var isSyncing: Bool = false

    @Published private(set) var phase: String = ""

    @Published private(set) var lastSyncAt: Date? = nil

    @Published private(set) var lastReport: CloudSyncReport? = nil

    @Published var lastError: String? = nil

    let client = CloudSyncClient()

    /// Where backups and `last-sync.log` go for an app. Tests point this at a
    /// temporary folder.
    var backupsDirectory: (Int) -> URL = AppPaths.cloudSaveBackupsDirectory(forAppID:)

    /// How many snapshots per game survive pruning (`before-clear` ones are
    /// always kept on top of these).
    var snapshotsToKeep = CloudSaveBackupLimits.snapshotsPerGame

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
    /// delete: everything is copied to a timestamped backup first. Returns
    /// that backup, or nil when there were no local saves to copy.
    @discardableResult
    func backupAndClearLocalSaves(bottle: Bottle, appID: Int, auth: SteamAuthStore) async throws -> URL? {
        guard let account = auth.account else { throw CloudSyncError.notSignedIn }
        isSyncing = true
        defer { isSyncing = false }

        phase = "Listing cloud files…"
        // Only folders with cloud files are cleared. Saves the cloud has never
        // seen would survive only in the backup.
        let remote = try await client.enumerate(appID: appID, account: account.accountName, refreshToken: account.refreshToken).files
        let userHome = try resolveWineUserHome(for: bottle)
        let installDir = bottle.gameInstallDirectory.map { URL(fileURLWithPath: $0) }

        // Tracked local files = the local mapping of every cloud file that
        // currently exists locally.
        let trackedDirs = Set(remote.compactMap { rf -> URL? in
            mapToLocal(rf.filename, userHome: userHome, installDir: installDir)?.deletingLastPathComponent()
        })

        phase = "Backing up local saves…"
        let backup = try backUpBeforeWriting(appID: appID, dirs: trackedDirs, label: "before-clear")

        phase = "Clearing local saves…"
        // The backup above already holds a copy, so a failure here is safe to
        // report. Swallowing it would claim the saves were cleared when they
        // weren't.
        for dir in trackedDirs {
            try FileManager.default.removeItemIfPresent(at: dir)
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
        let listing: CloudListing
        do {
            listing = try await client.enumerate(appID: appID, account: acct, refreshToken: token)
        } catch {
            // Nothing was written to last-sync.log yet — without this, a sync
            // that fails this early leaves the log (and anyone reading it to
            // check "did the last push actually go through") pointing at
            // whatever the previous SUCCESSFUL sync said, which reads as if
            // nothing had gone wrong.
            writeAbortedSyncLog(appID: appID, stage: "listing cloud files",
                                 reason: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            throw error
        }
        let remote = listing.files
        let saveRules = resolveSaveRules(listing.saveRules, userHome: userHome, installDir: installDir,
                                         steamID64: account.steamID64)

        // Snapshot every locally-present tracked file BEFORE touching anything.
        let cloudDirs = Set(remote.compactMap {
            mapToLocal($0.filename, userHome: userHome, installDir: installDir)?.deletingLastPathComponent()
        })
        let trackedDirs = outermostFolders(cloudDirs.union(saveFoldersToTrack(saveRules)))
        if !trackedDirs.isEmpty {
            knownSaveDirs[appID] = trackedDirs
            phase = "Backing up local saves…"
            report.backupPath = try backUpBeforeWriting(appID: appID, dirs: trackedDirs, label: doPush ? "before-sync" : "before-pull")
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
        var notes: [String] = []
        if doPush {
            if listing.saveRules.isEmpty {
                notes.append("Steam listed no save folders for this game, so only folders already in the cloud were checked for new saves.")
            }
            let plan = planUploads(remote: remote, cloudDirs: cloudDirs,
                                   ruleMatches: saveRules.flatMap(matches(of:)),
                                   userHome: userHome, installDir: installDir)
            uploads = plan.uploads
            report.skipped += plan.skipped
            report.failures += plan.failures
        }

        // ---- Execute the whole batch in one Steam session ----
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
            notes += batch.notes
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
        writeFailureLog(appID: appID, report: report, helperNotes: notes)
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
