import Foundation

enum GoldbergInstallerError: LocalizedError {
    case releaseFetchFailed
    case assetNotFound
    case downloadFailed
    case extractionFailed(String)
    case binariesNotFound

    var errorDescription: String? {
        switch self {
        case .releaseFetchFailed: return "Could not look up the latest GBE_Fork release on GitHub."
        case .assetNotFound: return "No emu-win-release.7z asset on the latest GBE_Fork release."
        case .downloadFailed: return "Downloading the Steam emulator archive failed."
        case .extractionFailed(let detail):
            return detail.isEmpty ? "Could not extract the GBE_Fork archive." : "Could not extract GBE_Fork:\n\(detail)"
        case .binariesNotFound:
            return "Extraction finished but no steam_api64.dll / steam_api.dll was found in the archive."
        }
    }
}
