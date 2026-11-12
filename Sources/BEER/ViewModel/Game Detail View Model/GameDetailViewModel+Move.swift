import Foundation

extension GameDetailViewModel {
    /// Why the game can't move right now; nil when it can.
    func moveBlockedReason(_ bottle: Bottle) -> String? {
        if mover.isMoving(bottle.id) { return GameMoveStrings.blockedMoving }
        if let name = bottles.installLocation(of: bottle).missingDriveName {
            return GameMoveStrings.blockedDriveMissing(name)
        }
        if bottles.activeBottleIDs.contains(bottle.id) { return GameMoveStrings.blockedRunning }
        if download?.isInProgress == true { return GameMoveStrings.blockedDownloading }
        if cloudSync.isSyncing { return GameMoveStrings.blockedSyncing }
        if isPatching { return GameMoveStrings.blockedPatching }
        return nil
    }

    func showMoveSheet(for bottle: Bottle) {
        guard moveBlockedReason(bottle) == nil, let source = bottles.installLocation(of: bottle).url else { return }
        moveSourceBytes = nil
        moveOptions = moveTargetOptions(for: bottle)
        moveTarget = InstallTargets.initialSelection(moveOptions, rememberedDriveUUID: nil)
        isShowingMoveSheet = true
        Task { [self] in
            // Walks the whole game folder.
            let bytes = await Task.detached { DiskSpaceCheck.allocatedSize(of: source) }.value
            if isShowingMoveSheet { moveSourceBytes = bytes }
        }
    }

    func moveTargetOptions(for bottle: Bottle) -> [InstallTargetOption] {
        InstallTargets.options(
            drives: drives.drives, macFreeBytes: InstallTargets.macFreeBytes(),
            alreadyHere: { $0.holds(bottle.gameDrive) }
        )
    }

    /// The move won't fit at the chosen place. Same margin as an install: the
    /// bottle and save backups keep growing after.
    var moveShortfall: DiskSpaceShortfall? {
        guard let bytes = moveSourceBytes,
              let option = moveOptions.first(where: { $0.id == moveTarget?.id }),
              let free = option.availableBytes else { return nil }
        return DiskSpaceCheck.shortfall(installBytes: bytes, availableBytes: free, volumeName: option.target.name)
    }

    func confirmMove(_ bottle: Bottle) {
        guard let target = moveTarget, moveSourceBytes != nil, moveShortfall == nil else { return }
        isShowingMoveSheet = false
        moveMessage = nil
        let appID = game.appID
        let cloudSync = cloudSync
        Task { [self] in
            do {
                let outcome = try await mover.move(
                    bottle, gameName: game.name, to: target, bottles: bottles,
                    backUpSaves: { try cloudSync.backUpSaves(inside: $0, appID: appID) }
                )
                switch outcome {
                case .moved:
                    moveIsError = false
                    moveMessage = GameMoveStrings.moved(to: target.name) + " " + GameMoveStrings.registryNote
                case .movedKeptOldCopy(let reason):
                    moveIsError = true
                    moveMessage = GameMoveStrings.movedKeptOld(to: target.name, reason: reason)
                }
            } catch {
                moveIsError = true
                moveMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            // The emulator row probes the install folder, which just changed.
            patchProbeTick &+= 1
        }
    }

    func cancelMove(_ bottle: Bottle) {
        mover.cancel(bottleID: bottle.id)
    }

    /// Whether `bottle`'s game is moving, saying so in the Steam Cloud row:
    /// nothing may write into its folder until the move is done.
    func refuseWhileMoving(_ bottle: Bottle) -> Bool {
        guard mover.isMoving(bottle.id) else { return false }
        cloudSyncIsError = true
        cloudSyncMessage = GameMoveStrings.waitForMove
        return true
    }
}
