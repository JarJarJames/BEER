import Foundation

/// User-facing text about a game that has an update on Steam.
enum GameUpdateStrings {
    static let cardBadge = "UPDATE"
    static let updateButton = "Update"
    static let updateHelp = "Download what changed since this copy was installed."
    static let checkButton = "Check for Updates"
    static let checkHelp = "BEER can't tell whether this copy is up to date: it was installed without a record of its version. This compares every file with Steam and downloads only what differs, then keeps track from then on. Files you changed that are part of the game go back to Steam's version; anything you added is left alone."
    static let updateFirst = "Update First"
    static let playAnyway = "Play Anyway"
    static let cancel = "Cancel"

    static func beforePlayTitle(_ game: String) -> String { "\(game) has an update" }

    static let beforePlayMessage = "Steam has a newer version than the one installed. Saves made by the newer version on another computer may not load in this one, and they're synced down before the game starts. Update first to stay on the same version."
}
