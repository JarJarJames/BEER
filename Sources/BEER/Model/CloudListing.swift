import Foundation

/// What the helper's `enumerate` reports for a game: its files in the cloud,
/// and the folders it saves into.
struct CloudListing: Equatable {
    let files: [CloudRemoteFile]
    /// Empty when Steam has no rules for the game, or the helper predates them.
    let saveRules: [CloudSaveRule]

    init(files: [CloudRemoteFile], saveRules: [CloudSaveRule] = []) {
        self.files = files
        self.saveRules = saveRules
    }

    init(json: [String: Any]) throws {
        guard let files = json["files"] as? [[String: Any]] else {
            throw CloudSyncClientError.badOutput("no files array")
        }
        self.init(
            files: files.compactMap(CloudRemoteFile.init(json:)),
            saveRules: (json["savefiles"] as? [[String: Any]] ?? []).compactMap(CloudSaveRule.init(json:))
        )
    }
}
