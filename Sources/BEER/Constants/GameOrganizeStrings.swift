import Foundation

/// User-facing text for favorites, hiding and custom artwork.
enum GameOrganizeStrings {
    static let addFavorite = "Add to Favorites"
    static let removeFavorite = "Remove from Favorites"
    static let hide = "Hide Game"
    static let unhide = "Unhide Game"
    static let customizeArtwork = "Customize Artwork…"
    static let more = "More"
    static let favoriteHelp = "Favorite"

    static let artworkTitle = "Customize Artwork"
    static let artworkMessage = "Pick your own images for this game. They're copied into BEER, so moving or deleting the originals won't affect them."
    static let chooseImage = "Choose…"
    static let useSteams = "Use Steam's"
    static let removeImage = "Remove"
    static let done = "Done"
    static func copyFailed(_ reason: String) -> String { "Couldn't use that image: \(reason)" }
}
