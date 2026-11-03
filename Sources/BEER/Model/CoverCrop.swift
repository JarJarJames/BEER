import CoreGraphics

/// The square of a game's cover that its shortcut icon shows. Stored relative
/// to the image, so it holds whatever size Steam serves the cover at.
struct CoverCrop: Codable, Hashable {
    /// Centre of the square, as fractions of the image's width and height.
    var centerX: Double
    var centerY: Double
    /// The square's side as a fraction of the image's shorter side: 1 is the
    /// largest square that fits, smaller is zoomed in.
    var scale: Double

    static let centered = CoverCrop(centerX: 0.5, centerY: 0.5, scale: 1)
    static let minimumScale = 0.4

    /// The square in pixels, moved and sized as needed to stay inside the image.
    func rect(in size: CGSize) -> CGRect {
        let side = min(size.width, size.height) * min(max(scale, Self.minimumScale), 1)
        let x = min(max(centerX * size.width - side / 2, 0), size.width - side)
        let y = min(max(centerY * size.height - side / 2, 0), size.height - side)
        return CGRect(x: x, y: y, width: side, height: side)
    }

    /// The same square, with its centre and scale pulled back inside the image.
    func clamped(to size: CGSize) -> CoverCrop {
        let r = rect(in: size)
        return CoverCrop(
            centerX: r.midX / size.width,
            centerY: r.midY / size.height,
            scale: r.width / min(size.width, size.height)
        )
    }
}
