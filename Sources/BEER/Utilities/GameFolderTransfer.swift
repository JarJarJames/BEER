import Foundation

/// Brings an existing game folder into a bottle's `drive_c/Games`.
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
    /// A move is a rename on the same volume and a copy-then-delete across
    /// volumes; if that fails partway the source is left in place.
    static func transfer(from source: URL, to destination: URL, mode: Mode) throws {
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

        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch mode {
        case .move: try fm.moveItem(at: source, to: destination)
        case .copy: try fm.copyItem(at: source, to: destination)
        }
    }

    /// Where `file` lands after its containing `sourceRoot` is transferred to `destinationRoot`.
    static func relocated(_ file: URL, from sourceRoot: URL, to destinationRoot: URL) -> URL {
        let root = sourceRoot.standardizedFileURL.path
        let path = file.standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return file }
        return destinationRoot.appendingPathComponent(String(path.dropFirst(root.count + 1)))
    }
}
