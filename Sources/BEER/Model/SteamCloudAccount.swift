import Foundation

struct SteamCloudAccount: Codable, Equatable {
    var accountName: String
    var steamID64: String
    var refreshToken: String
    var connectedAt: Date
}
