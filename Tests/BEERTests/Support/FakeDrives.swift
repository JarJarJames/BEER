import Foundation
@testable import BEER

/// Fake drives for tests: each is a temporary folder standing in for a mounted
/// drive, so a test can plug one in, pull it out, rename it, or make it exFAT
/// without touching a real disk. Hand `catalog` to whatever looks drives up.
final class FakeDrives: @unchecked Sendable {
    private let lock = NSLock()
    private var mounted: [InstallVolume] = []

    var drives: [InstallVolume] {
        get { lock.withLock { mounted } }
        set { lock.withLock { mounted = newValue } }
    }

    /// A path reports the ID of the fake drive whose folder holds it, like a
    /// real path reports its volume's.
    var catalog: VolumeCatalog {
        VolumeCatalog(
            mountedDrives: { [self] in drives },
            volumeUUID: { [self] url in
                let path = url.standardizedFileURL.path
                guard FileManager.default.fileExists(atPath: path) else { return nil }
                return drives.first { path == $0.root.path || path.hasPrefix($0.root.path + "/") }?.uuid
            }
        )
    }

    /// Plug in a drive whose files live in `root`.
    @discardableResult
    func plugIn(
        _ name: String, at root: URL, uuid: String = UUID().uuidString, format: String = "APFS",
        symlinks: Bool = true, caseSensitive: Bool = false, readOnly: Bool = false,
        local: Bool = true, diskImage: Bool = false, freeBytes: Int64 = 500_000_000_000
    ) throws -> InstallVolume {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let volume = InstallVolume(
            root: root.standardizedFileURL, name: name, uuid: uuid, availableBytes: freeBytes, format: format,
            supportsSymbolicLinks: symlinks, isCaseSensitive: caseSensitive, isReadOnly: readOnly,
            isLocal: local, isDiskImage: diskImage
        )
        drives = drives.filter { $0.uuid != uuid } + [volume]
        return volume
    }

    /// Pull a drive out. Its folder stays on disk, standing in for whatever
    /// else might be at that path afterwards.
    func unplug(_ volume: InstallVolume) {
        drives = drives.filter { $0.uuid != volume.uuid }
    }

    static func bottle(named name: String = "Game") -> Bottle {
        Bottle.make(
            name: name,
            runtime: RuntimeCandidate(kind: .gameNativeWine, executablePath: "/tmp/wine", displayName: "Test Wine"),
            graphicsBackend: .automatic
        )
    }
}
