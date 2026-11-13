import Accelerate
import CoreGraphics
import ImageIO

/// Decodes library art only as big as its card shows it. ImageIO reads the
/// compressed file straight to that size, so the full image is never
/// decoded: a 600×900 cover is about 2 MB decoded, a card-sized one a
/// fraction of that.
enum GameArtDecoder {
    static func image(at file: URL, for request: GameArtRequest) -> CGImage? {
        CGImageSourceCreateWithURL(file as CFURL, sourceOptions).flatMap { image(from: $0, for: request) }
    }

    static func image(from data: Data, for request: GameArtRequest) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, sourceOptions).flatMap { image(from: $0, for: request) }
    }

    /// The source itself never keeps a decoded copy; only the thumbnail is made.
    private static var sourceOptions: CFDictionary { [kCGImageSourceShouldCache: false] as CFDictionary }

    private static func image(from source: CGImageSource, for request: GameArtRequest) -> CGImage? {
        guard let longestSide = longestSide(of: source, for: request) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            // Decode now, off the main thread, not when the card first draws.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return request.fit == .backdrop ? blurred(image) : image
    }

    /// The decoded image's longest side: just enough to cover (fill) or sit
    /// inside (fit) the card's frame, and never bigger than the file.
    private static func longestSide(of source: CGImageSource, for request: GameArtRequest) -> CGFloat? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        if request.fit == .backdrop { return GameArtCacheLimits.backdropPixels }
        // Orientations 5–8 are turned a quarter, swapping width and height.
        let turned = ((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1) >= 5
        let (w, h) = turned ? (height, width) : (width, height)
        let scaleX = request.pixelSize.width / w
        let scaleY = request.pixelSize.height / h
        let scale = min(request.fit == .fill ? max(scaleX, scaleY) : min(scaleX, scaleY), 1)
        return max(1, (max(w, h) * scale).rounded(.up))
    }

    /// A box blur, twice, on the small copy: close to a Gaussian, and cheap
    /// at this size. Stretched behind the art, it reads as a soft backdrop.
    private static func blurred(_ image: CGImage) -> CGImage? {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let format = vImage_CGImageFormat(
                  bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: colorSpace,
                  bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
              var source = try? vImage_Buffer(cgImage: image, format: format) else { return nil }
        defer { source.free() }
        guard var scratch = try? vImage_Buffer(width: Int(source.width), height: Int(source.height),
                                               bitsPerPixel: format.bitsPerPixel) else { return nil }
        defer { scratch.free() }
        let kernel = GameArtCacheLimits.backdropBlurKernel
        let flags = vImage_Flags(kvImageEdgeExtend)
        guard vImageTentConvolve_ARGB8888(&source, &scratch, nil, 0, 0, kernel, kernel, nil, flags) == kvImageNoError,
              vImageTentConvolve_ARGB8888(&scratch, &source, nil, 0, 0, kernel, kernel, nil, flags) == kvImageNoError
        else { return nil }
        return try? source.createCGImage(format: format)
    }
}
