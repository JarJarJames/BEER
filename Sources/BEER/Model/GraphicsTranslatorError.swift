import Foundation

enum GraphicsTranslatorError: LocalizedError {
    case releaseFetchFailed(String)
    case assetNotFound(String)
    case downloadFailed
    case extractionFailed(String)
    case dllsNotFound(String)

    var errorDescription: String? {
        switch self {
        case .releaseFetchFailed(let r): "Couldn't fetch the latest \(r) release from GitHub."
        case .assetNotFound(let r): "The latest \(r) release has no installable archive."
        case .downloadFailed: "The translator download failed."
        case .extractionFailed(let o): "Could not extract the translator: \(o)"
        case .dllsNotFound(let n): "Extracted \(n) but found no x86_64-windows DLLs to install."
        }
    }
}
