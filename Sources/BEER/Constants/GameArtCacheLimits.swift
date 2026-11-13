import Foundation

/// How much library art BEER keeps, on disk and in memory. Memory is kept
/// small on purpose: BEER runs beside the game it launched, and every
/// megabyte it holds is one the game can't use.
enum GameArtCacheLimits {
    /// The downloaded art folder. A cover is 30–100 KB, so this holds a
    /// thousand-game library in any one card style with room to spare.
    static let diskBytes = 100 * 1024 * 1024
    /// A full disk cache is trimmed to this share of `diskBytes`, so it isn't
    /// trimmed again on the very next download.
    static let diskTrimTarget = 0.9
    /// Decoded art kept for cards that just scrolled away, in screens' worth
    /// of pixels. One of them is the cards on screen, which hold the same
    /// images.
    static let memoryScreens = 3
    /// Used when no screen can be measured (tests, a headless Mac).
    static let fallbackScreenPixels = 2880 * 1800
    /// Cards past the last one shown whose art is downloaded ahead.
    static let prefetchAhead = 12
    /// Downloads ahead at once. More are dropped, not queued: by the time a
    /// queue drained the player would have scrolled past those cards.
    static let prefetchConcurrency = 4
    /// Decode sizes are rounded up to this many pixels, so resizing the
    /// window doesn't decode the art again for every point it moves.
    static let pixelStep: CGFloat = 64
    /// The blurred copy behind art shown whole. Small, because blurred it
    /// looks the same as a big one.
    static let backdropPixels: CGFloat = 48
    /// The blur's box size on that copy, in pixels. Odd, as vImage needs.
    static let backdropBlurKernel: UInt32 = 9
}
