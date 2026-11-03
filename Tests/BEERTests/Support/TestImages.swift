import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Images built in memory for icon tests, so no artwork is checked in.
enum TestImages {
    static func png(width: Int, height: Int) -> Data {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        // Coloured by size, so images of different sizes never come out identical.
        context.setFillColor(CGColor(red: CGFloat(width % 256) / 255, green: CGFloat(height % 256) / 255, blue: 0.5, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// A Windows `.ico` holding a square PNG at each of `sides`, laid out as
    /// Steam's are: a 6-byte header, a 16-byte entry per image, then the images.
    static func ico(sides: [Int]) -> Data {
        let images = sides.map { png(width: $0, height: $0) }
        var data = Data()
        func le16(_ v: Int) { data.append(contentsOf: [UInt8(v & 0xff), UInt8(v >> 8 & 0xff)]) }
        func le32(_ v: Int) { le16(v & 0xffff); le16(v >> 16 & 0xffff) }
        le16(0); le16(1); le16(sides.count)
        var offset = 6 + 16 * sides.count
        for (side, image) in zip(sides, images) {
            // A side of 256 or more is written as 0.
            data.append(contentsOf: [UInt8(side >= 256 ? 0 : side), UInt8(side >= 256 ? 0 : side), 0, 0])
            le16(1); le16(32); le32(image.count); le32(offset)
            offset += image.count
        }
        images.forEach { data.append($0) }
        return data
    }
}
