import Foundation

/// An install that won't fit: how much it needs and what the volume has.
struct DiskSpaceShortfall: Equatable {
    let neededBytes: Int64
    let availableBytes: Int64
    let volumeName: String

    var missingBytes: Int64 { neededBytes - availableBytes }
}

/// Refuses installs the disk can't hold, before anything is downloaded.
enum DiskSpaceCheck {
    /// Nil when it fits. `alreadyOnDisk` is what an earlier, unfinished
    /// download left in the install folder; only the rest still needs room.
    static func shortfall(
        installBytes: Int64,
        alreadyOnDisk: Int64 = 0,
        availableBytes: Int64,
        volumeName: String,
        margin: Int64 = DiskSpaceLimits.safetyMarginBytes
    ) -> DiskSpaceShortfall? {
        let needed = max(0, installBytes - alreadyOnDisk) + margin
        guard needed > availableBytes else { return nil }
        return DiskSpaceShortfall(neededBytes: needed, availableBytes: availableBytes, volumeName: volumeName)
    }

    /// Free space as Finder reports it, on the volume holding `url` (or its
    /// nearest existing parent, since the destination may not exist yet).
    static func freeSpace(at url: URL) -> VolumeSpace? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path) {
            let parent = probe.deletingLastPathComponent()
            guard parent != probe else { return nil }
            probe = parent
        }
        guard let values = try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeNameKey]),
              let bytes = values.volumeAvailableCapacityForImportantUsage else { return nil }
        return VolumeSpace(availableBytes: bytes, name: values.volumeName ?? "this disk")
    }

    /// Bytes the files under `directory` occupy. Zero when it doesn't exist.
    static func allocatedSize(of directory: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in files {
            guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            total += Int64(values.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
