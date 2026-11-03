import Foundation

/// The file side of moving a game: copy, check, switch, back up, delete. The
/// bottle update and the save backup are passed in, so this runs (and is
/// tested) without the app's stores.
///
/// The game always has one complete copy it runs from. It is never pointed at
/// a half-copied folder, and its old copy is deleted only after the new one
/// matched it and the bottle was saved pointing at it. The journal records
/// each step, so a move cut short is undone or finished by `recover`.
///
/// Runs on the main actor beside the stores it updates; copying, checking and
/// deleting folders run off it.
@MainActor
struct GameMove {
    var journal: GameMoveJournal
    /// The folders an old copy may be deleted from: the bottle's
    /// `drive_c/Games` and each connected drive's `BEER/Games`.
    var gameFolderParents: [URL]
    /// Whether two folders are on the same volume, where a move is one rename.
    /// Tests turn it off to exercise the copy on a single disk.
    var isSameVolume: @Sendable (URL, URL) -> Bool = GameFolderTransfer.isSameVolume
    /// The mounted drives, to check a folder is on the drive the move recorded.
    var volumes: VolumeCatalog = .system

    func run(
        _ record: GameMoveRecord,
        cancel: CancelFlag,
        progress: @escaping @Sendable (GameMoveProgress) -> Void,
        switchBottle: () async throws -> Void,
        backUpSaves: (URL) throws -> Void
    ) async throws -> GameMoveOutcome {
        let fm = FileManager.default
        let source = record.sourceURL, destination = record.destinationURL, staging = record.stagingURL
        try GameFolders.requireDrive(for: source)
        try GameFolders.requireDrive(for: destination)
        guard fm.directoryExists(at: source) else { throw GameFolderTransfer.TransferError.sourceMissing(source.path) }
        guard !fm.fileExists(atPath: destination.path), !fm.fileExists(atPath: staging.path) else {
            throw GameFolderTransfer.TransferError.destinationExists(destination.path)
        }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        if isSameVolume(source, destination.deletingLastPathComponent()) {
            // One rename: nothing copied, nothing to check, no old copy left.
            try fm.moveItem(at: source, to: destination)
            do {
                try await switchBottle()
            } catch {
                attempt("Put a game back after a failed move", log: Log.install) {
                    try fm.moveItem(at: destination, to: source)
                }
                throw error
            }
            return .moved
        }

        var journaled = record
        journaled.stage = .copying
        journal.save(journaled)
        do {
            try await Task.detached {
                let entries = try FolderCopier.inventory(of: source)
                let total = entries.reduce(Int64(0)) { $0 + $1.size }
                let copied = Box<Int64>(0)
                progress(GameMoveProgress(phase: .copying, copiedBytes: 0, totalBytes: total))
                try FolderCopier.copy(entries, from: source, to: staging, progress: { bytes in
                    copied.value += bytes
                    progress(GameMoveProgress(phase: .copying, copiedBytes: copied.value, totalBytes: total))
                }, isCancelled: { cancel.isCancelled })
                progress(GameMoveProgress(phase: .checking, copiedBytes: total, totalBytes: total))
                try FolderCopier.verify(staging, against: source, isCancelled: { cancel.isCancelled })
            }.value
            progress(GameMoveProgress(phase: .finishing, copiedBytes: 0, totalBytes: 0))
            try fm.moveItem(at: staging, to: destination)
            // On the disk, rename included, before the old copy can go.
            FolderCopier.flush(destination)
            FolderCopier.flush(destination.deletingLastPathComponent())
        } catch {
            await discard([staging], bottleID: record.bottleID)
            throw error
        }

        do {
            try await switchBottle()
        } catch {
            await discard([destination], bottleID: record.bottleID)
            throw error
        }
        journaled.stage = .switched
        journal.save(journaled)

        // A drive pulled since the rename: keep the old copy, and the journal
        // entry so `recover` deletes it once the new copy is back.
        guard isPresent(destination, on: record.destinationDrive) else {
            return .movedKeptOldCopy(reason: GameMoveStrings.newCopyUnreachable)
        }
        let outcome = await deleteOldCopy(record, backUpSaves: backUpSaves)
        journal.remove(bottleID: record.bottleID)
        return outcome
    }

    /// Undo or finish a move a crash or a pulled drive interrupted. `record`'s
    /// paths should already follow renamed drives (see `rebased`), and
    /// `bottleDirectory` is where the bottle points now (nil: the game was
    /// removed). Returns false when a drive it needs isn't connected, so it's
    /// tried again when one is.
    func recover(_ record: GameMoveRecord, bottleDirectory: URL?, backUpSaves: (URL) throws -> Void) async -> Bool {
        let pointsAtDestination = bottleDirectory.map(GameFolders.canonicalPath) == GameFolders.canonicalPath(record.destinationURL)
        if record.stage == .switched || pointsAtDestination {
            // The game runs from its new place; only the old copy is left.
            // Deleted only once the new copy is there, on its own drive.
            guard isPresent(record.destinationURL, on: record.destinationDrive),
                  isConnected(record.sourceURL, on: record.sourceDrive) else { return false }
            if FileManager.default.fileExists(atPath: record.sourceURL.path),
               case .movedKeptOldCopy(let reason) = await deleteOldCopy(record, backUpSaves: backUpSaves) {
                Log.install.error("Kept a moved game's old copy: \(reason)")
            }
        } else {
            // The game still runs from where it was, or was removed meanwhile;
            // the unfinished copy goes. A finished copy goes too when the
            // bottle still points at the original, and stays (for the
            // found-games list) when there's no bottle to say which is current.
            guard isConnected(record.destinationURL, on: record.destinationDrive) else { return false }
            var leftovers = [record.stagingURL]
            if bottleDirectory != nil,
               GameFolders.isDirectChild(record.destinationURL, ofAny: gameFolderParents),
               GameFolders.canonicalPath(record.destinationURL) != GameFolders.canonicalPath(record.sourceURL) {
                leftovers.append(record.destinationURL)
            }
            let onRecordedDrive = leftovers.filter { isOnRecordedDrive($0, record.destinationDrive) }
            guard await removeAll(onRecordedDrive) else { return false }
        }
        journal.remove(bottleID: record.bottleID)
        return true
    }

    /// `record` with its paths moved to where its drives are mounted now, so a
    /// drive renamed (or mounted as "<name> 1") since is still recognized.
    func rebased(_ record: GameMoveRecord) -> GameMoveRecord {
        var record = record
        func follow(_ path: String, _ drive: GameDrive?) -> String {
            guard let drive, let mounted = volumes.drive(withUUID: drive.uuid) else { return path }
            return drive.rebase(path, onto: mounted.root) ?? path
        }
        record.source = follow(record.source, record.sourceDrive)
        record.destination = follow(record.destination, record.destinationDrive)
        return record
    }

    private func deleteOldCopy(_ record: GameMoveRecord, backUpSaves: (URL) throws -> Void) async -> GameMoveOutcome {
        let source = record.sourceURL
        do {
            try backUpSaves(source)
        } catch {
            return .movedKeptOldCopy(reason: GameMoveStrings.savesNotBackedUp(error.localizedDescription))
        }
        guard GameFolders.isDirectChild(source, ofAny: gameFolderParents) else {
            return .movedKeptOldCopy(reason: GameMoveStrings.notAGameFolder(source.path))
        }
        do {
            try await Self.remove(source)
        } catch {
            return .movedKeptOldCopy(reason: GameMoveStrings.oldCopyNotDeleted(error.localizedDescription))
        }
        return .moved
    }

    /// Clean up after a failed copy. If its drive went away the leftovers
    /// can't be removed now, so the journal keeps the move for `recover`.
    private func discard(_ urls: [URL], bottleID: UUID) async {
        if await removeAll(urls) { journal.remove(bottleID: bottleID) }
    }

    private func removeAll(_ urls: [URL]) async -> Bool {
        var removed = true
        for url in urls {
            guard isReachable(url) else { removed = false; continue }
            do {
                try await Self.remove(url)
            } catch {
                Log.install.error("Couldn't remove a partial game copy: \(error.localizedDescription)")
                removed = false
            }
        }
        return removed
    }

    /// A game folder can hold tens of thousands of files; deleting them
    /// mustn't stall the window.
    private static func remove(_ url: URL) async throws {
        try await Task.detached { try FileManager.default.removeItemIfPresent(at: url) }.value
    }

    private func isReachable(_ url: URL) -> Bool {
        GameFolders.driveRoot(of: url).map(GameFolders.isMounted) ?? true
    }

    /// Whether the drive `url` was recorded on is plugged in. Nil `drive`:
    /// this Mac, or whatever is mounted at the path.
    private func isConnected(_ url: URL, on drive: GameDrive?) -> Bool {
        guard let drive else { return isReachable(url) }
        return GameFolders.isConnected(drive, volumes: volumes)
    }

    /// `url` exists and, when a drive was recorded, is on that drive and not
    /// another one mounted under the same name.
    private func isPresent(_ url: URL, on drive: GameDrive?) -> Bool {
        FileManager.default.directoryExists(at: url) && isOnRecordedDrive(url, drive)
    }

    /// Paths that don't exist pass: there's nothing there to delete wrongly.
    private func isOnRecordedDrive(_ url: URL, _ drive: GameDrive?) -> Bool {
        guard let drive, FileManager.default.fileExists(atPath: url.path) else { return true }
        return volumes.volumeUUID(url) == drive.uuid
    }
}
