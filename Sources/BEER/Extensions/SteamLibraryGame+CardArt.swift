import Foundation

extension SteamLibraryGame {
    /// The portrait cover a cover card fills itself with: one the player
    /// picked, or Steam's. Nil for a non-Steam game without one, whose single
    /// picked image is shown whole instead of cropped.
    var portraitCover: URL? {
        if let custom = customArt?.url(for: .cover) { return custom }
        return effectiveIsNonSteam ? nil : libraryCapsuleImage
    }

    /// The small square icon for a list row: Steam's community icon, or a
    /// non-Steam game's picked image.
    var listIcon: URL? {
        effectiveIsNonSteam ? headerImage : iconURL.flatMap(URL.init(string:))
    }
}
