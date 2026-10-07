import Foundation

struct SteamAccount: Codable, Equatable {
    var username: String           // Steam account/persona name once signed in
    var steamID64: String?
    var avatarURL: String?
    var isLoggedIn: Bool

    static let signedOut = SteamAccount(username: "", steamID64: nil, avatarURL: nil, isLoggedIn: false)
}
