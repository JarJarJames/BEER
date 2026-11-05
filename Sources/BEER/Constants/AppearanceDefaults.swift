import Foundation

/// The value each Appearance setting starts at, and goes back to on Reset to
/// Defaults: cover cards and a Steam-style game page with the art behind it.
enum AppearanceDefaults {
    static let cardStyle = LibraryCardStyle.cover
    static let cardWidth: Double = 320
    static let cardLabel = LibraryCardLabel.artOnly
    static let sortOrder = LibrarySortOrder.installedFirst

    static let layout = GamePageLayout.steam
    static let bannerHeight: Double = 0.31
    static let titleScale: Double = 1.75
    static let showsBackdrop = true

    static let shownStats = GamePageStat.encode([.lastPlayed, .playtime])

    static let playtimeFormat = PlaytimeFormat.hoursAndMinutes
    static let lastPlayedFormat = LastPlayedFormat.relative
}
