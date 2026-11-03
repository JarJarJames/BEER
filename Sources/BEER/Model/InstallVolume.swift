import Foundation

/// A mounted drive other than the Mac's startup disk, with what BEER needs to
/// decide whether a Windows game can live on it.
struct InstallVolume: Equatable, Hashable, Identifiable, Sendable {
    /// Where it's mounted, e.g. `/Volumes/Games`. Changes when the drive is renamed.
    let root: URL
    let name: String
    /// Stays the same across renames and remounts, so it's what a game records.
    let uuid: String?
    let availableBytes: Int64?
    /// Finder's name for the format, e.g. "APFS" or "ExFAT".
    let format: String
    let supportsSymbolicLinks: Bool
    let isCaseSensitive: Bool
    let isReadOnly: Bool
    let isLocal: Bool
    let isDiskImage: Bool

    var id: String { uuid ?? root.path }

    /// Network shares, read-only drives and mounted disk images (installers,
    /// simulator runtimes) are never offered.
    var isListed: Bool { isLocal && !isReadOnly && !isDiskImage && uuid != nil }

    /// Why a listed drive can't hold a game; nil when it can.
    ///
    /// Wine and DepotDownloader rely on symlinks, Unix permissions and the
    /// executable bit, which exFAT and FAT32 don't have. A case-sensitive drive
    /// breaks games that open `Data.pak` as `data.pak`, as Windows allows.
    var unsupportedReason: String? {
        if !supportsSymbolicLinks { return InstallDriveStrings.unsupportedFormat(format) }
        if isCaseSensitive { return InstallDriveStrings.caseSensitive }
        return nil
    }

    /// The same drive under `name`. Right after a rename the drive still
    /// reports its old name for a moment; the notification has the new one.
    func named(_ name: String) -> InstallVolume {
        InstallVolume(root: root, name: name, uuid: uuid, availableBytes: availableBytes, format: format,
                      supportsSymbolicLinks: supportsSymbolicLinks, isCaseSensitive: isCaseSensitive,
                      isReadOnly: isReadOnly, isLocal: isLocal, isDiskImage: isDiskImage)
    }

    var link: GameDrive? {
        uuid.map { GameDrive(uuid: $0, name: name, mountPath: root.path) }
    }
}
