import Foundation

extension GameDetailViewModel {
    /// A drive was plugged in, pulled out or renamed. The page itself redraws
    /// on its own; the install and move sheets list places once when they
    /// open, so they're listed again here, keeping the player's choice while
    /// it's still there.
    func drivesChanged() {
        if isShowingInstallSheet {
            let chosen = installTarget
            prepareInstallTargets()
            if let kept = Self.stillThere(chosen, in: installOptions) { installTarget = kept }
            installSpaceReport = nil
            Task { await assessInstallTarget() }
        }

        if isShowingMoveSheet, let bottle = installedBottle {
            // The game's own drive went away: there's nothing to move from.
            guard moveBlockedReason(bottle) == nil else {
                isShowingMoveSheet = false
                return
            }
            let chosen = moveTarget
            moveOptions = moveTargetOptions(for: bottle)
            moveTarget = Self.stillThere(chosen, in: moveOptions)
                ?? InstallTargets.initialSelection(moveOptions, rememberedDriveUUID: nil)
        }
    }

    /// `target` as it reads now (a drive's mount point and free space may
    /// have changed), or nil when it's gone or can't be picked any more.
    private static func stillThere(_ target: InstallTarget?, in options: [InstallTargetOption]) -> InstallTarget? {
        guard let target else { return nil }
        return options.first { $0.id == target.id && $0.isEnabled }?.target
    }
}
