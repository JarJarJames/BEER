import Accelerate
import CoreGraphics
import ImageIO

/// Decodes library art only as big as its card shows it.
///
/// Art the card shows smaller than the file is read straight to that size as
/// a thumbnail, so the full image is never decoded. Art shown at the file's
/// own size or bigger (Steam's covers on a Retina screen, mostly) is decoded
/// whole by ImageIO instead: ImageIO keeps those pixels in memory macOS can
/// reclaim, which doesn't count against BEER, where a thumbnail's pixels do.
/// Measured on 36 drawn covers: +3 MB that way, +21 MB as thumbnails.
enum GameArtDecoder {
    static func image(at file: URL, for request: GameArtRequest) -> CGImage? {
        CGImageSourceCreateWithURL(file as CFURL, sourceOptions).flatMap { image(from: $0, for: request) }
    }

    static func image(from data: Data, for request: GameArtRequest) -> CGImage? {
        CGImageSourceCreateWithData(data as CFData, sourceOptions).flatMap { image(from: $0, for: request) }
    }

    /// Nothing is decoded when the source opens; each path below decides.
    private static var sourceOptions: CFDictionary { [kCGImageSourceShouldCache: false] as CFDictionary }

    private static func image(from source: CGImageSource, for request: GameArtRequest) -> CGImage? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0 else { return nil }
        if request.fit == .backdrop {
            return thumbnail(from: source, longestSide: GameArtCacheLimits.backdropPixels).flatMap(blurred)
        }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let longest = longestSide(width: width, height: height, turned: orientation >= 5, for: request)
        // Whole, unless it needs turning: only a thumbnail applies the turn.
        if longest >= max(width, height), orientation == 1 {
            let options: [CFString: Any] = [
                kCGImageSourceShouldCache: true,
                // Decode now, off the main thread, not when the card first draws.
                kCGImageSourceShouldCacheImmediately: true,
            ]
            return CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary)
        }
        return thumbnail(from: source, longestSide: longest)
    }

    private static func thumbnail(from source: CGImageSource, longestSide: CGFloat) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: longestSide,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// The decoded image's longest side: just enough to cover (fill) or sit
    /// inside (fit) the card's frame, and never bigger than the file.
    /// Orientations 5–8 are turned a quarter, swapping width and height.
    private static func longestSide(width: Double, height: Double, turned: Bool, for request: GameArtRequest) -> CGFloat {
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
