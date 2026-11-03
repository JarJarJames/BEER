import Foundation

/// Moves installed games between this Mac and drives, and finishes moves a
/// crash or a pulled drive interrupted. The file work is `GameMove`; this adds
/// progress for the game page, Cancel, and the bottle update.
@MainActor
final class GameMover: ObservableObject {
    /// Moves under way, by bottle.
    @Published private(set) var progress: [UUID: GameMoveProgress] = [:]

    var journal = GameMoveJournal(url: AppPaths.gameMovesURL)
    var volumes: VolumeCatalog = .system
    private var cancelFlags: [UUID: CancelFlag] = [:]
    /// Games whose interrupted move is being finished. Their journal entry
    /// is still in use, so a new move for them waits.
    @Published private(set) var recovering: Set<UUID> = []
    private var isFinishingMoves = false

    func isMoving(_ bottleID: UUID) -> Bool { progress[bottleID] != nil || recovering.contains(bottleID) }

    func cancel(bottleID: UUID) {
        cancelFlags[bottleID]?.cancel()
    }

    /// Where `bottle`'s game lands when moved to `target`. A folder already
    /// there (another game's, or a leftover of this one) gets a numbered name
    /// rather than being merged into.
    func destination(for bottle: Bottle, gameName: String, to target: InstallTarget) -> URL {
        switch target {
        case .thisMac:
            let preferred = AppPaths.gameInstallDirectory(for: bottle, gameName: gameName)
            return GameFolders.freeFolder(for: gameName,
                                          in: preferred.deletingLastPathComponent())
        case .drive(let volume):
            return GameFolders.freeFolder(for: gameName,
                                          in: AppPaths.driveGamesDirectory(onDriveAt: volume.root))
        }
    }

    /// Move `bottle`'s game to `target`. `backUpSaves` runs on the old copy
    /// before it's deleted.
    func move(
        _ bottle: Bottle, gameName: String, to target: InstallTarget,
        bottles: BottleStore, backUpSaves: (URL) throws -> Void
    ) async throws -> GameMoveOutcome {
        guard !isMoving(bottle.id) else { throw GameFolderError.cancelled }
        let location = bottles.installLocation(of: bottle)
        guard let source = location.url else {
            throw GameFolderError.driveNotConnected(location.missingDriveName ?? bottle.name)
        }
        if let volume = target.volume {
            guard volumes.drive(withUUID: volume.uuid ?? "") != nil else {
                throw GameFolderError.driveNotConnected(volume.name)
            }
            if let reason = volume.unsupportedReason { throw GameFolderError.unsupportedDrive(reason) }
        }
        let destination = destination(for: bottle, gameName: gameName, to: target)
        let record = GameMoveRecord(
            bottleID: bottle.id, source: source.path, sourceDrive: bottle.gameDrive,
            destination: destination.path, destinationDrive: target.volume?.link, stage: .copying
        )

        let flag = CancelFlag()
        cancelFlags[bottle.id] = flag
        progress[bottle.id] = GameMoveProgress(phase: .copying, copiedBytes: 0, totalBytes: 0)
        defer {
            progress[bottle.id] = nil
            cancelFlags[bottle.id] = nil
        }

        let bottleID = bottle.id
        return try await mover(for: bottles).run(
            record, cancel: flag,
            progress: { [weak self] update in
                Task { @MainActor in
                    // A late tick from a move that has since ended.
                    guard let self, self.cancelFlags[bottleID] === flag else { return }
                    self.progress[bottleID] = update
                }
            },
            switchBottle: {
                try bottles.relocateGame(bottleID: bottleID, from: source, to: destination, drive: record.destinationDrive)
            },
            backUpSaves: backUpSaves
        )
    }

    /// Undo or finish every move the journal says was cut short. Moves whose
    /// drive isn't connected wait until it is.
    func finishInterruptedMoves(bottles: BottleStore, backUpSaves: (Bottle, URL) throws -> Void) async {
        // Drive events come in bursts; one pass at a time.
        guard !isFinishingMoves else { return }
        isFinishingMoves = true
        defer { isFinishingMoves = false }
        for record in journal.records() where !isMoving(record.bottleID) {
            // Re-read: an entry can change while an earlier one is handled.
            guard journal.record(for: record.bottleID) == record else { continue }
            recovering.insert(record.bottleID)
            defer { recovering.remove(record.bottleID) }
            let bottle = bottles.bottles.first { $0.id == record.bottleID }
            let mover = mover(for: bottles)
            let finished = await mover.recover(
                mover.rebased(record),
                bottleDirectory: bottle?.gameInstallDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) },
                backUpSaves: { folder in if let bottle { try backUpSaves(bottle, folder) } }
            )
            if finished {
                Log.install.info("Finished an interrupted game move.")
            }
        }
    }

    private func mover(for bottles: BottleStore) -> GameMove {
        let bottleGames = bottles.bottles.map {
            AppPaths.gameInstallDirectory(for: $0, gameName: "_").deletingLastPathComponent()
        }
        let driveGames = volumes.mountedDrives().map { AppPaths.driveGamesDirectory(onDriveAt: $0.root) }
        var move = GameMove(journal: journal, gameFolderParents: bottleGames + driveGames)
        move.volumes = volumes
        return move
    }
}
