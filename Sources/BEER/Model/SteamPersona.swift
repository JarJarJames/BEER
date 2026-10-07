import Foundation
import SwiftUI

/// Steam's own view of the signed-in account, pushed by the live session.
struct SteamPersona: Equatable {
    var name: String
    var state: SteamPersonaState
    var avatarHash: String?
    /// The app Steam currently believes this account is playing, if any.
    var currentAppID: Int?

    /// Steam serves a zeroed hash for accounts with no custom avatar.
    var avatarURL: URL? {
        guard let hash = avatarHash, !hash.isEmpty,
              hash.contains(where: { $0 != "0" }) else { return nil }
        return URL(string: "https://avatars.steamstatic.com/\(hash)_full.jpg")
    }
}
