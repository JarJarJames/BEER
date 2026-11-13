import CoreGraphics

/// Where a card's art is: on its way, ready to draw, or not coming (no art,
/// or the download failed), when the card shows its placeholder for good.
enum GameArtPhase {
    case loading
    case loaded(CGImage)
    case failed

    init(_ image: CGImage?) {
        self = image.map(GameArtPhase.loaded) ?? .failed
    }

    var image: CGImage? {
        if case .loaded(let image) = self { return image }
        return nil
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }
}
