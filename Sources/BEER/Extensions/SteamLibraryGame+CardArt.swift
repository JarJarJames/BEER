import Foundation

extension SteamLibraryGame {
    /// The portrait cover a cover card fills itself with. Nil for a non-Steam
    /// game, whose one picked image is shown whole instead of cropped.
    var portraitCover: URL? {
        effectiveIsNonSteam ? nil : libraryCapsuleImage
    }

    /// The small square icon for a list row: Steam's community icon, or a
    /// non-Steam game's picked image.
    var listIcon: URL? {
        effectiveIsNonSteam ? headerImage : iconURL.flatMap(URL.init(string:))
    }
}
