import Foundation

/// Copies a game folder file by file, so a move can show progress, stop when
/// cancelled, and be checked against the original before the original is
/// deleted. Symlinks stay symlinks, and permissions (the executable bit) and
/// modification times are kept: cloud sync compares saves by the latter.
enum FolderCopier {
    struct Entry: Equatable {
        enum Kind: Equatable {
            case directory
            case file
            case symlink(String)
        }

        let relativePath: String
        let kind: Kind
        let size: Int64
    }

    /// Everything under `root`, sorted by path. Throws rather than skipping
    /// anything it can't read: a skipped folder would be missing from both
    /// sides of the check, and then deleted with the original.
    ///
    /// A `root` that is itself a symlink is followed: listing the link would
    /// find nothing, and an empty copy would pass the check.
    static func inventory(of root: URL) throws -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
        let root = root.resolvingSymlinksInPath()
        let base = root.standardizedFileURL.path
        let failure = Box<Error?>(nil)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [],
            errorHandler: { _, error in failure.value = error; return false }
        ) else { throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: root.path]) }

        var entries: [Entry] = []
        for case let url as URL in enumerator {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            let relative = String(path.dropFirst(base.count + 1))
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true {
                let target = try FileManager.default.destinationOfSymbolicLink(atPath: url.path)
                entries.append(Entry(relativePath: relative, kind: .symlink(target), size: 0))
            } else if values.isDirectory == true {
                entries.append(Entry(relativePath: relative, kind: .directory, size: 0))
            } else {
                entries.append(Entry(relativePath: relative, kind: .file, size: Int64(values.fileSize ?? 0)))
            }
        }
        if let error = failure.value { throw error }
        return entries.sorted { $0.relativePath < $1.relativePath }
    }

    /// Copy the items in `entries` from `source` into `destination`, which
    /// must not exist yet. `progress` gets the bytes copied by each chunk.
    static func copy(
        _ entries: [Entry], from source: URL, to destination: URL,
        progress: (Int64) -> Void, isCancelled: () -> Bool
    ) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: false)
        for entry in entries {
            if isCancelled() { throw GameFolderError.cancelled }
            let from = source.appendingPathComponent(entry.relativePath)
            let to = destination.appendingPathComponent(entry.relativePath)
            switch entry.kind {
            case .directory:
                try fm.createDirectory(at: to, withIntermediateDirectories: true)
            case .symlink(let target):
                try fm.createSymbolicLink(atPath: to.path, withDestinationPath: target)
            case .file:
                try copyFile(from: from, to: to, progress: progress, isCancelled: isCancelled)
            }
        }
    }

    /// Ask the drive to write out what it's holding in its own cache, so a
    /// copy is really on it before the original is deleted. One call covers
    /// everything copied to that drive. Best-effort: some drives refuse.
    static func flush(_ url: URL) {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { return }
        defer { close(fd) }
        if fcntl(fd, F_FULLFSYNC) == -1 { fsync(fd) }
    }

    private static func copyFile(from: URL, to: URL, progress: (Int64) -> Void, isCancelled: () -> Bool) throws {
        let fm = FileManager.default
        guard fm.createFile(atPath: to.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: to.path])
        }
        let input = try FileHandle(forReadingFrom: from)
        defer { try? input.close() }   // Nothing left to lose once reading is done.
        let output = try FileHandle(forWritingTo: to)
        do {
            while let chunk = try input.read(upToCount: GameFolderLimits.copyChunkBytes), !chunk.isEmpty {
                if isCancelled() { throw GameFolderError.cancelled }
                try output.write(contentsOf: chunk)
                progress(Int64(chunk.count))
            }
            // On the drive itself, not just in memory, before the original
            // can be deleted: a drive pulled right after a "finished" copy
            // would otherwise lose what was still cached.
            try output.synchronize()
            try output.close()
        } catch {
            try? output.close()   // Already failing; the copy is discarded.
            throw error
        }
        let attributes = try fm.attributesOfItem(atPath: from.path)
        var kept: [FileAttributeKey: Any] = [:]
        kept[.posixPermissions] = attributes[.posixPermissions]
        kept[.modificationDate] = attributes[.modificationDate]
        try fm.setAttributes(kept, ofItemAtPath: to.path)
    }

    /// Throws `copyMismatch` naming the first thing in `copy` that differs
    /// from `original`. Every item must match in kind, name and size, and
    /// files small enough to be saves are compared byte for byte.
    static func verify(_ copy: URL, against original: URL, isCancelled: () -> Bool = { false }) throws {
        let expected = try inventory(of: original)
        let actual = try inventory(of: copy)
        for (index, entry) in expected.enumerated() {
            guard index < actual.count, actual[index] == entry else {
                throw GameFolderError.copyMismatch(entry.relativePath)
            }
        }
        if actual.count > expected.count {
            throw GameFolderError.copyMismatch(actual[expected.count].relativePath)
        }
        for entry in expected where entry.kind == .file && entry.size <= GameFolderLimits.byteCompareLimitBytes {
            if isCancelled() { throw GameFolderError.cancelled }
            let same = try sameBytes(original.appendingPathComponent(entry.relativePath),
                                     copy.appendingPathComponent(entry.relativePath))
            if !same { throw GameFolderError.copyMismatch(entry.relativePath) }
        }
    }

    private static func sameBytes(_ a: URL, _ b: URL) throws -> Bool {
        let left = try FileHandle(forReadingFrom: a)
        defer { try? left.close() }   // Read-only handles.
        let right = try FileHandle(forReadingFrom: b)
        defer { try? right.close() }
        while true {
            let l = try left.read(upToCount: GameFolderLimits.copyChunkBytes) ?? Data()
            let r = try right.read(upToCount: GameFolderLimits.copyChunkBytes) ?? Data()
            if l != r { return false }
            if l.isEmpty { return true }
        }
    }
}
