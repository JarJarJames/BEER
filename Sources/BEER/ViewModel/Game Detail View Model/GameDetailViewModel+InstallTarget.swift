import Foundation

extension GameDetailViewModel {
    /// Fill the install sheet's list. A game that already has a bottle (a
    /// download that stopped, or a reinstall) stays where its files are.
    func prepareInstallTargets() {
        installNote = nil
        if let existing = bottles.findBottle(forAppID: game.appID) {
            let fixed = fixedTarget(for: existing)
            installOptions = fixed.map { [fixedOption(for: $0)] } ?? []
            installTarget = fixed
            installNote = existing.gameDrive.flatMap { drive in
                fixed == nil ? InstallDriveStrings.resumeDriveMissing(drive.name) : nil
            } ?? InstallDriveStrings.resumeHere
        } else {
            installOptions = InstallTargets.options(drives: drives.drives, macFreeBytes: InstallTargets.macFreeBytes())
            installTarget = InstallTargets.initialSelection(
                installOptions, rememberedDriveUUID: UserDefaults.standard.string(forKey: InstallPreferences.lastDriveKey)
            )
        }
    }

    func selectInstallTarget(_ target: InstallTarget?) {
        guard let target, target.id != installTarget?.id else { return }
        installTarget = target
        installSpaceReport = nil
        Task { await assessInstallTarget() }
    }

    /// Where `bottle`'s files are: this Mac, or its drive while connected.
    /// Nil when that drive isn't.
    func fixedTarget(for bottle: Bottle) -> InstallTarget? {
        guard let drive = bottle.gameDrive else { return .thisMac }
        return drives.current.drive(withUUID: drive.uuid).map(InstallTarget.drive)
    }

    private func fixedOption(for target: InstallTarget) -> InstallTargetOption {
        InstallTargetOption(
            target: target,
            availableBytes: target.volume.map(\.availableBytes) ?? InstallTargets.macFreeBytes(),
            disabledReason: nil
        )
    }

    /// Where the free-space check looks for an install to `target`, and the
    /// folder an earlier download left (only the rest still needs room).
    func installDestination(for target: InstallTarget) -> (destination: URL, partial: URL?) {
        if let existing = bottles.findBottle(forAppID: game.appID) {
            let folder = existing.downloadDirectory(gameName: game.name)
            return (folder, folder)
        }
        switch target {
        case .thisMac:
            return (AppPaths.bottlesDirectory, nil)
        case .drive(let volume):
            return (AppPaths.driveGamesDirectory(onDriveAt: volume.root), nil)
        }
    }

    /// Re-check free space for the chosen place, with the size Steam gave.
    func assessInstallTarget() async {
        guard let size = installSize, let target = installTarget else { return }
        let (destination, partial) = installDestination(for: target)
        let report = await installSpaceCheck.assess(size, destination: destination, partialDownload: partial)
        // The sheet closed, or another place was picked, while this ran.
        guard isShowingInstallSheet, installTarget?.id == target.id else { return }
        installSpaceReport = report
    }
}
