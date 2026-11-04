import Foundation

/// Sizes for the game page's banner and the art behind the page.
enum GameBannerLayout {
    /// The banner slider sets the banner's height as a fraction of its width.
    /// The banner never gets shorter than the title and buttons on it, so the
    /// low end is just tall enough for them.
    static let heightRatioRange: ClosedRange<Double> = 0.1...0.6
    /// Steam's `library_hero.jpg` is 1920×620, the original shape.
    static let defaultHeightRatio: Double = 620.0 / 1920.0

    /// The title slider scales the logo (or the name) from its original size.
    /// It never gets wider than the page; a banner too short for it grows.
    static let titleScaleRange: ClosedRange<Double> = 0.4...2.5
    static let defaultTitleScale: Double = 1
    /// The logo's box at the original size.
    static let logoMaxWidth: CGFloat = 420
    static let logoMaxHeight: CGFloat = 150
    /// The name's font size at the original size, when there's no logo art.
    static let titleFontSize: CGFloat = 36
    /// The game page's margin. The Steam-style header runs edge to edge, so
    /// its title and bar use this to line up with the settings below.
    static let pageInset: CGFloat = 28
    /// Where the Steam-style art starts fading into the page, as a fraction
    /// of the header's height; it's gone by the bottom of the stat bar.
    static let fadeStart: CGFloat = 0.6
    /// The Steam-style strip Play and the stats sit on: dark enough to read
    /// over bright art, light enough that the art shows through.
    static let statBarVerticalPadding: CGFloat = 16
    static let statBarOpacity: Double = 0.3
    static let statSpacing: CGFloat = 28
    static let statTitleTracking: CGFloat = 1
    static let backdropBlur: CGFloat = 40
    static let backdropOpacity: Double = 0.35
    /// Scaled up so the blur's soft edges fall outside the window.
    static let backdropScale: CGFloat = 1.2
}
