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
    /// True for a game the user added from a folder on disk rather than one
    /// Steam owns. Its `appID` is a negative placeholder that only identifies
    /// it inside BEER, so nothing may send it to Steam. Optional for the same
    /// decoding reason as `playtimeMinutes`.
    var isNonSteam: Bool?
    /// Cover art the user picked for a non-Steam game, a copy kept under
    /// `AppPaths.customArtDirectory`.
    var customImagePath: String?
    /// Steam's Windows icon for the game, once BEER has asked for it.
    var clientIconURL: String?
    /// What the game's shortcuts show. Nil until the player picks.
    var shortcutIcon: ShortcutIconChoice?

    var effectiveIsNonSteam: Bool { isNonSteam ?? false }

    private var customImageURL: URL? {
        customImagePath.map { URL(fileURLWithPath: $0) }
    }

    var headerImage: URL? {
        if effectiveIsNonSteam { return customImageURL }
        return URL(string: headerImageURL ?? "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/header.jpg")
    }

    /// Steam's wide, high-resolution Library backdrop. Unlike `header.jpg`,
    /// this contains artwork without a baked-in oversized game logo.
    var libraryHeroImage: URL? {
        if effectiveIsNonSteam { return customImageURL }
        return URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/library_hero.jpg")
    }

    /// Steam's portrait Library cover. Its art is centered, so it survives
    /// being cropped to a square where the wide header would lose its logo.
    var libraryCapsuleImage: URL? {
        if effectiveIsNonSteam { return customImageURL }
        return URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/library_600x900.jpg")
    }

    /// The cover at full size (600×900), for cutting a sharp square icon from.
    /// `library_600x900.jpg` is only 300×450 despite its name.
    var shortcutCoverImage: URL? {
        if effectiveIsNonSteam { return customImageURL }
        return URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/library_600x900_2x.jpg")
    }

    /// Transparent title treatment Steam layers over its Library hero art.
    var libraryLogoImage: URL? {
        if effectiveIsNonSteam { return nil }
        return URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/logo.png")
    }
}
