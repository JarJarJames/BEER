import Foundation

/// The Rich Presence card for a running game, shaped as Discord's `SET_ACTIVITY`
/// expects it (encode with `.convertToSnakeCase`). Steam games show their store
/// art with the BEER logo as a badge; a non-Steam game has no art online that
/// Discord can reach, so it shows the logo alone.
struct DiscordActivity: Encodable, Equatable {
    struct Timestamps: Encodable, Equatable {
        /// Unix seconds. Discord counts the elapsed timer up from here.
        let start: Int
    }

    struct Assets: Encodable, Equatable {
        let largeImage: String
        let largeText: String
        let smallImage: String?
        let smallText: String?
    }

    struct Button: Encodable, Equatable {
        let label: String
        let url: String
    }

    /// 0 is "Playing".
    let type = 0
    /// Overrides the app's registered name as the card's title.
    let name: String
    let details: String
    let timestamps: Timestamps
    let assets: Assets
    let buttons = [Button(label: DiscordPresenceConfig.buttonLabel, url: DiscordPresenceConfig.buttonURL)]

    init(game: SteamLibraryGame, startedAt: Date) {
        name = game.name + DiscordPresenceConfig.titleSuffix
        details = DiscordPresenceConfig.details
        timestamps = Timestamps(start: Int(startedAt.timeIntervalSince1970))

        if let art = game.libraryCapsuleImage, art.scheme == "https" {
            assets = Assets(
                largeImage: art.absoluteString,
                largeText: game.name,
                smallImage: DiscordPresenceConfig.logoAssetKey,
                smallText: DiscordPresenceConfig.logoHoverText
            )
        } else {
            assets = Assets(
                largeImage: DiscordPresenceConfig.logoAssetKey,
                largeText: game.name,
                smallImage: nil,
                smallText: nil
            )
        }
    }
}
