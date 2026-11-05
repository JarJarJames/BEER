import Foundation

/// Sizes for the library's cards and the grid they sit in.
enum LibraryGridLayout {
    static let gridPadding: CGFloat = 22
    static let gridSpacing: CGFloat = 18
    static let listSpacing: CGFloat = 6
    static let cornerRadius: CGFloat = 8
    static let captionPadding: CGFloat = 10
    static let badgeInset: CGFloat = 8
    static let hoverScale: CGFloat = 1.02
    static let listRowSpacing: CGFloat = 12
    static let listRowHorizontalPadding: CGFloat = 12
    static let listRowVerticalPadding: CGFloat = 8
    static let listIconCornerRadius: CGFloat = 4

    /// Steam's `header.jpg` is 460×215.
    static let wideArtAspectRatio: CGFloat = 460.0 / 215.0
    /// Steam's `library_600x900.jpg`.
    static let coverArtAspectRatio: CGFloat = 600.0 / 900.0
    /// How much the blurred copy behind art shown whole is blurred.
    static let fittedArtBlur: CGFloat = 18

    /// The size slider sets a wide card's width. The top end is past any
    /// screen on purpose: the grid caps cards to the space it has, so the
    /// far right of the slider is one card filling the view.
    static let cardWidthRange: ClosedRange<Double> = 160...1600
    /// The original card width.
    static let defaultCardWidth: Double = 220
    /// Cover cards are narrower than wide ones at the same slider position.
    static let coverWidthScale: Double = 0.68
    /// How far past the chosen width a card stretches to fill a row.
    static let rowStretch: Double = 1.27
    /// A list row's icon, relative to the chosen width.
    static let listIconScale: Double = 0.15
    static let listIconMinimum: CGFloat = 24

    /// The width range a grid card can stretch across: the chosen width, but
    /// never wider than `available`, the grid's width inside its padding, so
    /// even the biggest card stays on screen. Zero before it's measured.
    static func cardWidth(style: LibraryCardStyle, chosen: Double, available: CGFloat) -> ClosedRange<CGFloat> {
        let base = CGFloat(style == .cover ? chosen * coverWidthScale : chosen)
        let stretched = base * CGFloat(rowStretch)
        guard available > 0 else { return base...stretched }
        let lower = min(base, available)
        return lower...max(lower, min(stretched, available))
    }

    /// A list row's icon, which sets the row's height.
    static func listIconSize(chosen: Double) -> CGFloat {
        max(listIconMinimum, CGFloat(chosen * listIconScale))
    }
}
