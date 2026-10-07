import Foundation

struct SteamLibraryGame: Identifiable, Codable, Hashable {
    var id: Int { appID }
    var appID: Int
    var name: String
    var headerImageURL: String?
    var iconURL: String?
    var sizeOnDiskBytes: Int64?
    var lastPlayed: Date?
    /// Total minutes Steam has recorded for this app across every device the
    /// account plays on — including this one, because BEER announces the game
    /// to Steam while it runs (see `CloudSyncClient.PlaySession`).
    ///
    /// Optional rather than a defaulted `Int` on purpose: Swift's synthesized
    /// `Decodable` ignores default values and throws `keyNotFound` for a missing
    /// key, and `SteamLibraryStore.load()` decodes with `try?` — a throw there
    /// would silently discard the saved account and sign the user out.
    var playtimeMinutes: Int?
    var installedBottleID: UUID?

    /// Steam-style play time, e.g. "43.4 hours". Nil when the account has never
    /// played the game.
    var playtimeDisplay: String? {
        guard let minutes = playtimeMinutes, minutes > 0 else { return nil }
        if minutes < 60 { return "\(minutes) minute\(minutes == 1 ? "" : "s")" }
        return String(format: "%.1f hours", Double(minutes) / 60)
    }

    var headerImage: URL? {
        URL(string: headerImageURL ?? "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/header.jpg")
    }

    /// Steam's wide, high-resolution Library backdrop. Unlike `header.jpg`,
    /// this contains artwork without a baked-in oversized game logo.
    var libraryHeroImage: URL? {
        URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/library_hero.jpg")
    }

    /// Transparent title treatment Steam layers over its Library hero art.
    var libraryLogoImage: URL? {
        URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/logo.png")
    }
}
