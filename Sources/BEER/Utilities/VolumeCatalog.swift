import DiskArbitration
import Foundation

/// The drives mounted right now, and which drive a path is on. Both lookups
/// are swappable so tests can fake an exFAT drive, an unplugged drive or two
/// drives with the same name, the way `InstallSpaceCheck.freeSpace` fakes a
/// full disk.
struct VolumeCatalog: Sendable {
    /// Every mounted drive other than the Mac's startup disk, listed or not.
    var mountedDrives: @Sendable () -> [InstallVolume]
    /// The ID of the volume holding `url`; nil when `url` doesn't exist.
    var volumeUUID: @Sendable (URL) -> String?
    /// The drive mounted at `root`, read directly. For the address a mount or
    /// rename notification carries, which the mounted list can lag behind.
    var drive: @Sendable (_ root: URL) -> InstallVolume? = { _ in nil }

    static let system = VolumeCatalog(
        mountedDrives: SystemVolumes.mountedDrives,
        volumeUUID: SystemVolumes.volumeUUID(of:),
        drive: SystemVolumes.drive(at:)
    )

    func drive(withUUID uuid: String) -> InstallVolume? {
        mountedDrives().first { $0.uuid == uuid }
    }
}

private enum SystemVolumes {
    static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeUUIDStringKey, .volumeAvailableCapacityForImportantUsageKey,
        .volumeAvailableCapacityKey, .volumeLocalizedFormatDescriptionKey,
        .volumeSupportsSymbolicLinksKey, .volumeSupportsCaseSensitiveNamesKey,
        .volumeIsReadOnlyKey, .volumeIsLocalKey
    ]

    @Sendable static func mountedDrives() -> [InstallVolume] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]
        ) ?? []
        return urls.compactMap(drive(at:))
    }

    @Sendable static func drive(at root: URL) -> InstallVolume? {
        // Only /Volumes: the startup disk is "/" and its system volumes live
        // under /System/Volumes; simulator runtimes mount elsewhere too.
        guard root.standardizedFileURL.pathComponents.count == 3, root.path.hasPrefix("/Volumes/") else { return nil }
        // Resource values for a volume that just unmounted fail; it's gone.
        guard let values = try? root.resourceValues(forKeys: Set(keys)) else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init)
        return InstallVolume(
            root: root,
            name: values.volumeName ?? root.lastPathComponent,
            uuid: values.volumeUUIDString,
            availableBytes: available,
            format: values.volumeLocalizedFormatDescription ?? InstallDriveStrings.unknownFormat,
            supportsSymbolicLinks: values.volumeSupportsSymbolicLinks ?? false,
            isCaseSensitive: values.volumeSupportsCaseSensitiveNames ?? false,
            isReadOnly: values.volumeIsReadOnly ?? true,
            isLocal: values.volumeIsLocal ?? false,
            isDiskImage: isDiskImage(root)
        )
    }

    @Sendable static func volumeUUID(of url: URL) -> String? {
        // A path that doesn't exist has no volume; that's the answer, not an error.
        (try? url.resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
    }

    /// A mounted .dmg or simulator runtime reports itself as a disk image to
    /// Disk Arbitration; nothing in `URLResourceKey` says so.
    static func isDiskImage(_ root: URL) -> Bool {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, root as CFURL),
              let description = DADiskCopyDescription(disk) as? [CFString: Any] else { return false }
        let model = (description[kDADiskDescriptionDeviceModelKey] as? String)?
            .trimmingCharacters(in: .whitespaces)
        let transport = description[kDADiskDescriptionDeviceProtocolKey] as? String
        return model == "Disk Image" || transport == "Virtual Interface"
    }
}
