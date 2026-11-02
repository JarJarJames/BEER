import Foundation

/// A restore the player hasn't settled with Steam Cloud yet. Written by a
/// restore, removed once they pick which saves to keep (or the restored saves
/// turn out to match Steam's).
struct PendingSaveRestore: Codable, Equatable {
    /// The snapshot folder the saves came from.
    let snapshotName: String
    let snapshotDate: Date
    let restoredAt: Date
    /// The save folders the restore replaced, as absolute paths.
    let folders: [String]

    var folderURLs: [URL] { folders.map { URL(fileURLWithPath: $0, isDirectory: true) } }
}
