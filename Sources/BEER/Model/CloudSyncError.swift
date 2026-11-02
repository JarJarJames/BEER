import Foundation

enum CloudSyncError: LocalizedError {
    case userHomeNotFound(URL)
    case notSignedIn
    case cannotInferRemotePath
    case backupFailed(String)
    /// A restored backup differs from Steam Cloud; the player has to choose.
    case restoreConflict(SaveRestoreConflict)
    /// An older snapshot whose save folder can't be found in the bottle.
    case restoreTargetUnknown(String)
    /// Saving Steam's copies failed, so the restored saves weren't uploaded.
    case steamCopyFailed(String)

    var errorDescription: String? {
        switch self {
        case .userHomeNotFound(let url):
            return "Couldn't find a Wine user home inside \(url.path). The bottle may not be initialized."
        case .notSignedIn:
            return "Connect Steam Cloud first."
        case .cannotInferRemotePath:
            return "No existing cloud files to learn the save path from. Sync once from your PC's Steam first, then push will work."
        case .backupFailed(let reason):
            return "Couldn't back up your local saves, so nothing was synced or restored and your saves are untouched. \(reason)"
        case .restoreConflict:
            return "Your restored saves differ from Steam Cloud. Choose which to keep before syncing."
        case .restoreTargetUnknown(let folder):
            return "This backup doesn't say where “\(folder)” came from, and BEER couldn't find exactly one matching folder in the bottle. Open the backup in Finder to copy the files back yourself."
        case .steamCopyFailed(let reason):
            return "Couldn't save a copy of Steam's saves first, so nothing was uploaded and Steam Cloud is unchanged. \(reason)"
        }
    }
}
