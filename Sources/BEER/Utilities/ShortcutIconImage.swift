import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns Steam's icon or a game's cover into a shortcut's icon. Pure image
/// work on data already in hand, so tests can feed it files.
enum ShortcutIconImage {
    /// The largest image in an `.ico`, or nil when it has none at least
    /// `minimumSide` wide. An `.ico` holds the same icon at several sizes.
    static func steamIcon(from data: Data, minimumSide: Int = ShortcutIconLimits.minimumSteamIconSide) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let largest = (0..<CGImageSourceGetCount(source))
            .compactMap { CGImageSourceCreateImageAtIndex(source, $0, nil) }
            .max { $0.width < $1.width }
        guard let largest, largest.width >= minimumSide, largest.height >= minimumSide else { return nil }
        return largest
    }

    /// The first image in `data` (a cover JPEG or PNG).
    static func image(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// The square of `image` that `crop` picks. CoverCrop measures from the
    /// top, as CGImage cropping does.
    static func crop(_ image: CGImage, to crop: CoverCrop) -> CGImage? {
        image.cropping(to: crop.rect(in: CGSize(width: image.width, height: image.height)).integral)
    }

    /// A Mac `.icns` holding `image` at every size macOS asks for.
    static func icns(from image: CGImage) -> Data? {
        let data = NSMutableData()
        let sides = ShortcutIconLimits.icnsSides
        guard let destination = CGImageDestinationCreateWithData(data, UTType.icns.identifier as CFString, sides.count, nil) else {
            return nil
        }
        for side in sides {
            guard let scaled = scaled(image, to: side) else { return nil }
            CGImageDestinationAddImage(destination, scaled, nil)
        }
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func scaled(_ image: CGImage, to side: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        return context.makeImage()
    }
}
