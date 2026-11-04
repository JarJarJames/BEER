import Foundation

/// UserDefaults keys for the Appearance settings. Read with `@AppStorage`; a
/// missing or unknown value falls back to the original look.
enum AppearancePreferences {
    static let cardStyleKey = "library.cardStyle"
    /// A wide card's width in points, from the size slider.
    static let cardWidthKey = "library.cardWidth"
    /// What shows under each card (`LibraryCardLabel`).
    static let cardLabelKey = "library.cardLabel"
    static let sortOrderKey = "library.sortOrder"
    /// The banner's height as a fraction of its width, from the slider.
    static let bannerHeightKey = "gamePage.bannerHeight"
    /// How much bigger or smaller than the original the title is, from the slider.
    static let titleScaleKey = "gamePage.titleScale"
    static let showsBackdropKey = "gamePage.showsBackdrop"
    static let layoutKey = "gamePage.layout"
    /// The `GamePageStat`s shown, comma-separated (`GamePageStat.encode`).
    static let shownStatsKey = "gamePage.shownStats"
    static let playtimeFormatKey = "playStats.playtimeFormat"
    static let lastPlayedFormatKey = "playStats.lastPlayedFormat"
    /// The Settings window's open tab, so a button can open it on Runtimes.
    static let settingsTabKey = "settings.tab"
}
