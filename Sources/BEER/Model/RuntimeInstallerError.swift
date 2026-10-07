import Foundation

enum RuntimeInstallerError: LocalizedError {
    case releaseFetchFailed
    case assetNotFound
    case downloadFailed
    case digestMismatch
    case extractionFailed(String)
    case runtimeNotFound

    var errorDescription: String? {
        switch self {
        case .releaseFetchFailed:
            "Could not fetch the latest GPTK release from GitHub."
        case .assetNotFound:
            "The latest GPTK release does not include a downloadable .tar.xz asset."
        case .downloadFailed:
            "The GPTK runtime download failed."
        case .digestMismatch:
            "The downloaded GPTK archive did not match GitHub's SHA-256 digest."
        case .extractionFailed(let output):
            output.isEmpty ? "Could not extract the GPTK archive." : "Could not extract the GPTK archive: \(output)"
        case .runtimeNotFound:
            "The archive extracted, but no usable wine, wine64, or gameportingtoolkit executable was found."
        }
    }
}
