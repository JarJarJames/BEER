import Foundation

/// The value each Appearance setting starts at, and goes back to on Reset to
/// Defaults: the look BEER had before the settings existed.
enum AppearanceDefaults {
    static let cardStyle = LibraryCardStyle.wide
    static let cardWidth = LibraryGridLayout.defaultCardWidth
    static let cardLabel = LibraryCardLabel.appID
    static let sortOrder = LibrarySortOrder.installedFirst

    static let layout = GamePageLayout.overlay
    static let bannerHeight = GameBannerLayout.defaultHeightRatio
    static let titleScale = GameBannerLayout.defaultTitleScale
    static let showsBackdrop = false

    static let shownStats = GamePageStat.encode(GamePageStat.defaultShown)

    static let playtimeFormat = PlaytimeFormat.decimalHours
    static let lastPlayedFormat = LastPlayedFormat.date
}
