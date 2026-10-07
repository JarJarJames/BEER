import Foundation

struct CloudRemoteFile: Equatable {
    /// Steam's own cloud key for the file, e.g. "%WinSavedGames%/kingdomcome/…".
    let filename: String
    let size: Int
    let timestamp: Date
    let sha: String
}
