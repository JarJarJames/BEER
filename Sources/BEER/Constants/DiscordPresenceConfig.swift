import Foundation

/// The Discord application BEER announces games through. Rich Presence needs a
/// registered app (discord.com/developers/applications); its ID is public, so
/// it lives in source. Its uploaded art is referenced by the keys below.
enum DiscordPresenceConfig {
    /// Empty disables Discord presence entirely.
    static let applicationID = "1565916884409389188"

    /// Appended to the game's name for the card's title: "Portal 2 with BEER".
    static let titleSuffix = " with BEER"
    /// The line under the title. Repeats "BEER" because a long game name
    /// pushes the suffix off the end of the title.
    static let details = "Playing with BEER on Mac"
    /// Key of the BEER logo uploaded under the app's Rich Presence art assets.
    static let logoAssetKey = "beer"
    static let logoHoverText = "BEER"
    /// Shown to people viewing the card, never to the player themself.
    static let buttonLabel = "Get BEER"
    static let buttonURL = "https://github.com/JarJarJames/BEER"

    /// Discord listens on the first free of `discord-ipc-0` … `discord-ipc-9`.
    static let socketNames = (0...9).map { "discord-ipc-\($0)" }
}
