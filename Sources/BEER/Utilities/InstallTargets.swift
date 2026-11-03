import Foundation

/// The rows of the install, move and add lists: this Mac, then each drive.
enum InstallTargets {
    /// `alreadyHere` marks where the game is now, when moving it.
    static func options(
        drives: [InstallVolume], macFreeBytes: Int64?,
        alreadyHere: (InstallTarget) -> Bool = { _ in false }
    ) -> [InstallTargetOption] {
        let listed = drives.filter(\.isListed)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let targets = [InstallTarget.thisMac] + listed.map(InstallTarget.drive)
        return targets.map { target in
            InstallTargetOption(
                target: target,
                availableBytes: target.volume.map(\.availableBytes) ?? macFreeBytes,
                disabledReason: alreadyHere(target) ? GameMoveStrings.alreadyHere : target.volume?.unsupportedReason
            )
        }
    }

    /// The row selected when the list opens: the drive used last time, if it's
    /// connected and usable, else the first row that can be picked.
    static func initialSelection(_ options: [InstallTargetOption], rememberedDriveUUID: String?) -> InstallTarget? {
        let enabled = options.filter(\.isEnabled)
        if let rememberedDriveUUID,
           let remembered = enabled.first(where: { $0.target.volume?.uuid == rememberedDriveUUID }) {
            return remembered.target
        }
        return enabled.first?.target
    }

    /// Free space on this Mac where bottles live.
    static func macFreeBytes() -> Int64? {
        DiskSpaceCheck.freeSpace(at: AppPaths.bottlesDirectory)?.availableBytes
    }
}
