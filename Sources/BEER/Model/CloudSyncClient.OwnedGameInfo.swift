import Foundation

extension CloudSyncClient {
    struct OwnedGameInfo {
        let appID: Int
        let name: String
        let iconURL: String?
        let lastPlayed: Date?
        /// Total minutes Steam has recorded for this app, across every device.
        /// BEER contributes to this itself — see `SteamPresenceStore`.
        let playtimeMinutes: Int?
    }
}
