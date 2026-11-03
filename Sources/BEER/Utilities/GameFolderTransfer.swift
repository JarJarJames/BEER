import Foundation

/// Brings an existing game folder into a bottle's `drive_c/Games`, or into a
/// drive's `BEER/Games`.
enum GameFolderTransfer {
    enum Mode: String, CaseIterable, Identifiable {
        case move, copy
        var id: String { rawValue }
    }

    enum TransferError: LocalizedError {
        case sourceMissing(String)
        case destinationExists(String)
        case destinationInsideSource

        var errorDescription: String? {
            switch self {
            case .sourceMissing(let path): return "The game folder no longer exists at \(path)."
            case .destinationExists(let path): return "Something already exists at \(path)."
            case .destinationInsideSource: return "The destination can't be inside the game folder."
            }
        }
    }

    /// Never overwrites: a destination that already exists is an error, so a
    /// transfer can't clobber files (saves included) that are already there.
    /// On one volume a move is a rename and a copy is a clone. Across volumes
    /// the copy is checked against the original before a move deletes it; if
    /// anything fails the source is left in place and the partial copy goes.
    /// `sameVolume` is decided from the volumes' IDs unless a test says.
    static func transfer(from source: URL, to destination: URL, mode: Mode, sameVolume: Bool? = nil) throws {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw TransferError.sourceMissing(source.path)
        }
        guard !fm.fileExists(atPath: destination.path) else {
            throw TransferError.destinationExists(destination.path)
        }
        let sourcePath = source.standardizedFileURL.resolvingSymlinksInPath().path
        let destinationPath = destination.standardizedFileURL.resolvingSymlinksInPath().path
        guard !destinationPath.hasPrefix(sourcePath + "/") else {
            throw TransferError.destinationInsideSource
        }

        try GameFolders.requireDrive(for: destination)
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if sameVolume ?? isSameVolume(source, destination.deletingLastPathComponent()) {
            switch mode {
            case .move: try fm.moveItem(at: source, to: destination)
            case .copy: try fm.copyItem(at: source, to: destination)
            }
            return
        }

        do {
            let entries = try FolderCopier.inventory(of: source)
            try FolderCopier.copy(entries, from: source, to: destination, progress: { _ in }, isCancelled: { false })
            try FolderCopier.verify(destination, against: source)
        } catch {
            attempt("Remove a partial game copy", log: Log.install) { try fm.removeItemIfPresent(at: destination) }
            throw error
        }
        FolderCopier.flush(destination)
        guard mode == .move else { return }
        // The checked copy is the game now. If the original won't go
        // entirely, the copy still stands: throwing here would make the
        // caller discard it, leaving only a half-deleted original.
        attempt("Remove a moved game's original folder", log: Log.install) {
            try fm.removeItem(at: source)
        }
    }

    /// Room a transfer needs at its destination. A move within one volume is a
    /// rename and needs none; anything else needs a full copy's worth.
    static func spaceNeeded(folderBytes: Int64, mode: Mode, sameVolume: Bool) -> Int64 {
        mode == .move && sameVolume ? 0 : folderBytes
    }

    static func isSameVolume(_ a: URL, _ b: URL) -> Bool {
        let uuid = VolumeCatalog.system.volumeUUID
        return uuid(a) != nil && uuid(a) == uuid(b)
    }

    /// Where `file` lands after its containing `sourceRoot` is transferred to `destinationRoot`.
    static func relocated(_ file: URL, from sourceRoot: URL, to destinationRoot: URL) -> URL {
        let root = sourceRoot.standardizedFileURL.path
        let path = file.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return file }
        return destinationRoot.appendingPathComponent(String(path.dropFirst(root.count + 1)))
    }
}
