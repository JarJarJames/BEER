import CoreImage
import CoreImage.CIFilterBuiltins

enum QRCodeGenerator {
    /// A QR code for `string`, upscaled so it isn't a tiny pixelated mess when
    /// the image view scales it.
    static func image(from string: String) -> CGImage? {
        guard let data = string.data(using: .utf8) else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.setValue(data, forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        return CIContext().createCGImage(scaled, from: scaled.extent)
    }
}
