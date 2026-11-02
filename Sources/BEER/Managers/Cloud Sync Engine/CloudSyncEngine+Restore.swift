import Foundation

// Putting a snapshot's saves back, and settling them with Steam Cloud after.
//
// A restore is local only: it backs up the current saves, swaps the
// snapshot's copies in, and leaves a pending-restore note. Restored files keep
// the dates they had, so a normal sync would see Steam's copies as newer and
// quietly pull them over the restore. The note stops that: every sync checks
// it first and, when the restored saves differ from Steam's, stops and asks
// the player which to keep, the way Steam's own Cloud Sync Conflict does.

extension CloudSyncEngine {
    /// This game's snapshots, newest first, for the backups list.
    func saveBackups(appID: Int) -> [CloudSaveSnapshot] {
        CloudSaveBackupRetention.snapshotInfo(in: backupsDirectory(appID))
    }

    func pendingRestore(appID: Int) -> PendingSaveRestore? {
        CloudSaveBackupRetention.pendingRestore(in: backupsDirectory(appID))
    }

    // MARK: - Planning

    /// Work out where each folder in `snapshot` goes back to, and what the
    /// restore would replace. Touches nothing. Walks the bottle when an older
    /// snapshot doesn't record its folders, so run it off the main actor.
    nonisolated static func restorePlan(for snapshot: CloudSaveSnapshot, userHome: URL, installDir: URL?) throws -> SaveRestorePlan {
        let roots = [userHome] + (installDir.map { [$0] } ?? [])
        var folders: [SaveRestorePlan.Folder] = []
        for (tail, recorded) in storedFolders(in: snapshot.url) {
            let stored = snapshot.url.appendingPathComponent(tail, isDirectory: true)
            // A recorded folder outside this bottle (a bottle that moved, say)
            // is no better than none.
            let target = recorded.flatMap { path in
                let url = URL(fileURLWithPath: path, isDirectory: true)
                return roots.contains { isInside(url, $0) } ? url : nil
            } ?? findFolder(tail: tail, under: roots)
            guard let target else { throw CloudSyncError.restoreTargetUnknown(tail) }
            if !folders.contains(where: { $0.target == target }) {
                folders.append(.init(stored: stored, target: target))
            }
        }

        var restored = 0
        var removed = 0
        for folder in folders {
            let incoming = CloudSaveBackupRetention.relativeFilePaths(under: folder.stored)
            restored += incoming.count
            removed += CloudSaveBackupRetention.relativeFilePaths(under: folder.target).subtracting(incoming).count
        }
        return SaveRestorePlan(
            snapshot: snapshot, folders: folders, filesRestored: restored, filesRemoved: removed,
            currentLastChanged: CloudSaveBackupRetention.fileSummary(of: folders.map(\.target)).lastChanged
        )
    }

    /// The save folders copied into a snapshot, by their path inside it, with
    /// the folder each came from when the snapshot recorded it.
    nonisolated static func storedFolders(in snapshot: URL) -> [(tail: String, recorded: String?)] {
        let manifest = snapshot.appendingPathComponent(CloudSaveBackupLimits.sourcesFileName)
        if let data = try? Data(contentsOf: manifest),
           let sources = try? JSONDecoder().decode([String: String].self, from: data) {
            return sources.keys.sorted().map { ($0, sources[$0]) }
        }
        // Older snapshots: every folder three levels down is a copied save
        // folder (see `snapshotTail`).
        let fm = FileManager.default
        func subfolders(_ url: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        }
        var tails: [String] = []
        for a in subfolders(snapshot) {
            for b in subfolders(a) {
                for c in subfolders(b) {
                    tails.append([a, b, c].map(\.lastPathComponent).joined(separator: "/"))
                }
            }
        }
        return tails.sorted().map { ($0, nil) }
    }

    /// The one folder under `roots` whose path ends in `tail`. A folder that
    /// was cleared is gone, so failing that, the one folder ending in the
    /// tail's parent, with the last part added back. Nil unless exactly one
    /// matches: guessing wrong would put saves in the wrong place.
    nonisolated static func findFolder(tail: String, under roots: [URL]) -> URL? {
        let wanted = tail.split(separator: "/").map(String.init)
        guard !wanted.isEmpty else { return nil }
        var exact: [URL] = []
        var parents: [URL] = []
        for (walk, reportAs) in searchRoots(roots) {
            guard let walker = FileManager.default.enumerator(
                at: walk, includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in walker {
                // Save folders sit a few levels down; Documents can go on forever.
                if walker.level >= CloudSaveBackupLimits.restoreSearchDepth { walker.skipDescendants() }
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                      let below = relativePath(of: url, in: walk) else { continue }
                let found = reportAs.appendingPathComponent(below, isDirectory: true)
                let parts = found.pathComponents
                if parts.suffix(wanted.count).elementsEqual(wanted) { exact.append(found) }
                if wanted.count > 1, parts.suffix(wanted.count - 1).elementsEqual(wanted.dropLast()) {
                    parents.append(found.appendingPathComponent(wanted.last!, isDirectory: true))
                }
            }
        }
        if exact.count == 1 { return exact[0] }
        if exact.isEmpty, parents.count == 1 { return parents[0] }
        return nil
    }

    /// Where to look for save folders: each root, plus the folders its links
    /// point to. A bottle's Documents is a link to the Mac's own, which a walk
    /// doesn't follow. What's found there is reported under the link, the
    /// path the bottle (and Steam's cloud names) use.
    nonisolated static func searchRoots(_ roots: [URL]) -> [(walk: URL, reportAs: URL)] {
        var result = roots.map { ($0, $0) }
        for root in roots {
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]
            )) ?? []
            for link in entries where (try? link.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true {
                let target = link.resolvingSymlinksInPath()
                guard (try? target.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
                result.append((target, root.appendingPathComponent(link.lastPathComponent, isDirectory: true)))
            }
        }
        return result
    }

    /// `url`'s path below `folder`, or nil when it isn't inside it. Tried as
    /// written, then with links resolved: a bottle's Documents is a link to
    /// the Mac's own, so a save there has two paths. Resolving alone isn't
    /// enough, since Foundation only rewrites the parts of a path that exist,
    /// and a file not written yet resolves differently from its folder.
    nonisolated static func relativePath(of url: URL, in folder: URL) -> String? {
        let candidates = [(url.pathComponents, folder.pathComponents),
                          (url.resolvingSymlinksInPath().pathComponents, folder.resolvingSymlinksInPath().pathComponents)]
        for (path, base) in candidates where path.starts(with: base) {
            return path.dropFirst(base.count).joined(separator: "/")
        }
        return nil
    }

    nonisolated static func isInside(_ url: URL, _ folder: URL) -> Bool {
        relativePath(of: url, in: folder) != nil
    }

    // MARK: - Restoring

    /// Put `plan`'s saves back. The current saves are backed up first; Steam
    /// Cloud isn't touched until the next sync, which asks which saves to keep.
    func restore(_ plan: SaveRestorePlan, appID: Int) throws {
        isSyncing = true
        defer { isSyncing = false }
        let fm = FileManager.default
        let previous = pendingRestore(appID: appID)

        // Written before the backup below, whose pruning would otherwise be
        // free to delete the very snapshot being restored.
        try writePendingRestore(PendingSaveRestore(
            snapshotName: plan.snapshot.url.lastPathComponent, snapshotDate: plan.snapshot.date,
            restoredAt: Date(), folders: plan.folders.map(\.target.path)
        ), appID: appID)

        var swapped = false
        var incoming: [URL] = []
        do {
            phase = "Backing up current saves…"
            _ = try backUpBeforeWriting(appID: appID, dirs: Set(plan.folders.map(\.target)),
                                        label: CloudSaveBackupLimits.beforeRestoreLabel)

            phase = "Restoring saves…"
            // Copy everything next to its destination first, so a full disk
            // fails before any save folder has been swapped.
            for folder in plan.folders {
                let parent = folder.target.deletingLastPathComponent()
                try fm.createDirectory(at: parent, withIntermediateDirectories: true)
                let copy = parent.appendingPathComponent(".beer-restore-\(UUID().uuidString)", isDirectory: true)
                try fm.copyItem(at: folder.stored, to: copy)
                incoming.append(copy)
            }
            for (folder, copy) in zip(plan.folders, incoming) {
                try swap(copy, into: folder.target)
                swapped = true
            }
        } catch {
            for copy in incoming { try? fm.removeItemIfPresent(at: copy) }
            // Nothing changed, so nothing is pending beyond what was before.
            if !swapped {
                if let previous { try? writePendingRestore(previous, appID: appID) } else { clearPendingRestore(appID: appID) }
            }
            phase = ""
            throw error
        }
        phase = "Backup restored. Your next sync will ask which saves to keep."
    }

    /// Replace `target` with `copy`. The old folder is moved aside, not
    /// deleted, until the new one is in place.
    private func swap(_ copy: URL, into target: URL) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: target.path) else {
            try fm.moveItem(at: copy, to: target)
            return
        }
        let aside = target.deletingLastPathComponent()
            .appendingPathComponent(".beer-replaced-\(UUID().uuidString)", isDirectory: true)
        try fm.moveItem(at: target, to: aside)
        do {
            try fm.moveItem(at: copy, to: target)
        } catch {
            try? fm.moveItem(at: aside, to: target)
            throw error
        }
        // The backup taken before the restore holds these.
        attempt("remove the replaced save folder", log: Log.cloudSync) { try fm.removeItem(at: aside) }
    }

    func writePendingRestore(_ pending: PendingSaveRestore, appID: Int) throws {
        let dir = backupsDirectory(appID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try JSONEncoder().encode(pending).write(
            to: dir.appendingPathComponent(CloudSaveBackupLimits.pendingRestoreFileName), options: .atomic
        )
    }

    func clearPendingRestore(appID: Int) {
        attempt("clear the pending restore", log: Log.cloudSync) {
            try FileManager.default.removeItemIfPresent(
                at: backupsDirectory(appID).appendingPathComponent(CloudSaveBackupLimits.pendingRestoreFileName)
            )
        }
    }

    // MARK: - Settling with Steam Cloud

    /// The conflict a sync must stop on, or nil when no restore is pending or
    /// the restored saves already match Steam's. In that last case the note
    /// is removed: there's nothing left to choose.
    func restoreConflict(appID: Int, remote: [CloudRemoteFile], userHome: URL, installDir: URL?) -> SaveRestoreConflict? {
        guard let pending = pendingRestore(appID: appID) else { return nil }
        let folders = pending.folderURLs
        let cloud = remote.compactMap { rf -> (file: CloudRemoteFile, local: URL)? in
            guard let local = mapToLocal(rf.filename, userHome: userHome, installDir: installDir),
                  folders.contains(where: { Self.isInside(local, $0) }) else { return nil }
            return (rf, local)
        }
        let differing = cloud.filter { !localFileMatchesRemote($0.local, remote: $0.file) }.map(\.file)
        guard !differing.isEmpty else {
            clearPendingRestore(appID: appID)
            return nil
        }
        let local = CloudSaveBackupRetention.fileSummary(of: folders)
        return SaveRestoreConflict(
            pending: pending, localFileCount: local.count, localLastChanged: local.lastChanged,
            cloudFileCount: cloud.count, cloudLastUploaded: cloud.map(\.file.timestamp).max(),
            differingCloudFiles: differing
        )
    }

    /// The player chose Steam's saves. The sync they were running then pulls
    /// Steam's copies as usual, after backing up the restored ones.
    func useSteamSavesOverRestore(appID: Int) {
        clearPendingRestore(appID: appID)
    }

    /// The player chose the restored saves. Steam's differing copies are
    /// downloaded into their own snapshot first, then the restored saves are
    /// uploaded over them. Nothing is uploaded unless every copy downloaded.
    func keepRestoredSaves(bottle: Bottle, appID: Int, auth: SteamAuthStore) async throws -> CloudSyncReport {
        guard let account = auth.account else { throw CloudSyncError.notSignedIn }
        isSyncing = true
        defer { isSyncing = false }
        let userHome = try resolveWineUserHome(for: bottle)
        let installDir = bottle.gameInstallDirectory.map { URL(fileURLWithPath: $0) }
        var report = CloudSyncReport()

        phase = "Listing cloud files…"
        let listing = try await client.enumerate(appID: appID, account: account.accountName, refreshToken: account.refreshToken)
        guard let conflict = restoreConflict(appID: appID, remote: listing.files, userHome: userHome, installDir: installDir) else {
            phase = "Restored saves already match Steam Cloud."
            return report
        }
        let folders = conflict.pending.folderURLs

        phase = "Saving a copy of Steam's saves…"
        let copy = try await saveSteamCopies(of: conflict.differingCloudFiles, folders: folders, appID: appID,
                                             userHome: userHome, installDir: installDir, account: account)
        report.backupPath = copy
        report.downloaded = conflict.differingCloudFiles.count

        let cloudDirs = Set(listing.files.compactMap {
            mapToLocal($0.filename, userHome: userHome, installDir: installDir)?.deletingLastPathComponent()
        })
        let rules = resolveSaveRules(listing.saveRules, userHome: userHome, installDir: installDir, steamID64: account.steamID64)
        let plan = planUploads(remote: listing.files, cloudDirs: cloudDirs, ruleMatches: rules.flatMap(matches(of:)),
                               userHome: userHome, installDir: installDir, forcing: folders)
        // Only the restored saves: the sync the player was running handles
        // everything else once this is settled.
        let uploads = plan.uploads.filter { job in folders.contains { Self.isInside(job.local, $0) } }

        phase = "Uploading restored saves…"
        let batch = try await client.batch(
            appID: appID, downloads: [], uploads: uploads,
            account: account.accountName, refreshToken: account.refreshToken,
            onProgress: { [weak self] done, total in
                Task { @MainActor in self?.phase = "Uploading \(done)/\(total)…" }
            }
        )
        for op in batch.ops {
            if let err = op.error { report.failures.append((op.filename, err)) } else { report.uploaded += 1 }
        }
        // Anything that didn't upload still differs, so the next sync asks
        // again rather than pulling Steam's copy over it.
        if report.failures.isEmpty { clearPendingRestore(appID: appID) }
        writeFailureLog(appID: appID, report: report, helperNotes: batch.notes)
        lastSyncAt = Date()
        lastReport = report
        phase = "Kept the restored saves: \(report.uploaded) uploaded" + (report.failures.isEmpty ? "." : ", \(report.failures.count) failed.")
        return report
    }

    /// Download Steam's copies of `files` into a new snapshot laid out like
    /// any other, so it shows in the backups list and can be restored.
    private func saveSteamCopies(of files: [CloudRemoteFile], folders: [URL], appID: Int,
                                 userHome: URL, installDir: URL?, account: SteamCloudAccount) async throws -> URL {
        let fm = FileManager.default
        let stamp = Self.timestampFormatter.string(from: Date())
        let root = backupsDirectory(appID).appendingPathComponent("\(stamp)-\(CloudSaveBackupLimits.steamCloudCopyLabel)", isDirectory: true)
        var sources: [String: String] = [:]
        var downloads: [CloudSyncClient.DownloadJob] = []
        for rf in files {
            guard let local = mapToLocal(rf.filename, userHome: userHome, installDir: installDir),
                  let folder = folders.first(where: { Self.isInside(local, $0) }) else { continue }
            let tail = Self.snapshotTail(of: folder)
            guard let relative = Self.relativePath(of: local, in: folder) else { continue }
            downloads.append(.init(filename: rf.filename, out: root.appendingPathComponent(tail).appendingPathComponent(relative)))
            sources[tail] = folder.path
        }

        do {
            try fm.createDirectory(at: root, withIntermediateDirectories: true)
            let batch = try await client.batch(
                appID: appID, downloads: downloads, uploads: [],
                account: account.accountName, refreshToken: account.refreshToken,
                onProgress: { [weak self] done, total in
                    Task { @MainActor in self?.phase = "Saving Steam's copies \(done)/\(total)…" }
                }
            )
            let failed = batch.ops.filter { $0.error != nil }
            if let first = failed.first {
                throw CloudSyncError.steamCopyFailed("\(failed.count) file\(failed.count == 1 ? "" : "s") didn't download: \(first.filename): \(first.error ?? "")")
            }
            if batch.ops.count < downloads.count {
                throw CloudSyncError.steamCopyFailed("Steam answered for \(batch.ops.count) of \(downloads.count) files.")
            }
            try writeSources(sources, into: root)
        } catch {
            try? fm.removeItemIfPresent(at: root)
            let reason = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            writeAbortedSyncLog(appID: appID, stage: "saving Steam's copies before keeping restored saves", reason: reason)
            if error is CloudSyncError || error is CloudSyncClientError { throw error }
            throw CloudSyncError.steamCopyFailed(reason)
        }
        pruneBackups(appID: appID, keeping: root)
        return root
    }
}
