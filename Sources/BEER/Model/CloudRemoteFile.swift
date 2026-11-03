import Foundation

struct CloudRemoteFile: Equatable {
    /// Steam's own cloud key for the file, e.g. "%WinSavedGames%/kingdomcome/…".
    let filename: String
    let size: Int
    let timestamp: Date
    let sha: String
}

extension CloudRemoteFile {
    init?(json: [String: Any]) {
        guard let filename = json["filename"] as? String else { return nil }
        self.init(
            filename: filename,
            size: (json["size"] as? NSNumber)?.intValue ?? 0,
            timestamp: Date(timeIntervalSince1970: (json["timestamp"] as? NSNumber)?.doubleValue ?? 0),
            sha: json["sha"] as? String ?? ""
        )
    }
}
