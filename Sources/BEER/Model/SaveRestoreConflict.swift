import Foundation

/// Restored saves that differ from Steam's copies. A sync stops on this until
/// the player picks a side, the way Steam's own Cloud Sync Conflict does.
struct SaveRestoreConflict: Equatable {
    let pending: PendingSaveRestore
    /// Save files in the restored folders now.
    let localFileCount: Int
    let localLastChanged: Date?
    /// Steam's files for the restored folders.
    let cloudFileCount: Int
    let cloudLastUploaded: Date?
    /// Steam files whose contents differ from the restored copy, or that the
    /// restored saves don't have at all.
    let differingCloudFiles: [CloudRemoteFile]
}
