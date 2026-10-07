import Foundation

enum CloudSyncError: LocalizedError {
    case userHomeNotFound(URL)
    case notSignedIn
    case cannotInferRemotePath

    var errorDescription: String? {
        switch self {
        case .userHomeNotFound(let url):
            return "Couldn't find a Wine user home inside \(url.path). The bottle may not be initialized."
        case .notSignedIn:
            return "Connect Steam Cloud first."
        case .cannotInferRemotePath:
            return "No existing cloud files to learn the save path from. Sync once from your PC's Steam first, then push will work."
        }
    }
}
