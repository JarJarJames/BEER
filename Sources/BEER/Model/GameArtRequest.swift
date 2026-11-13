import CoreGraphics
import Foundation

/// One piece of library art at the size a card shows it.
struct GameArtRequest: Hashable, Sendable {
    /// How the art sits in its frame, which sets how big it's decoded.
    enum Fit: Hashable, Sendable {
        /// Covers the frame, cropped at the edges.
        case fill
        /// Shown whole inside the frame.
        case fit
        /// A small blurred copy, stretched behind art shown whole.
        case backdrop
    }

    let url: URL
    /// The frame in pixels (points × the screen's scale), rounded up to
    /// `GameArtCacheLimits.pixelStep`.
    let pixelSize: CGSize
    let fit: Fit

    /// Nil until the frame has a size.
    init?(url: URL?, points: CGSize, scale: CGFloat, fit: Fit) {
        guard let url, points.width > 0, points.height > 0, scale > 0 else { return nil }
        let step = GameArtCacheLimits.pixelStep
        func rounded(_ value: CGFloat) -> CGFloat { (value * scale / step).rounded(.up) * step }
        self.url = url
        self.pixelSize = fit == .backdrop ? .zero : CGSize(width: rounded(points.width), height: rounded(points.height))
        self.fit = fit
    }
}
