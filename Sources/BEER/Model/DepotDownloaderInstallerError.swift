import Foundation

enum DepotDownloaderInstallerError: LocalizedError {
    case releaseFetchFailed
    case assetNotFound
    case downloadFailed
    case extractionFailed(String)
    case executableMissing

    var errorDescription: String? {
        switch self {
        case .releaseFetchFailed: return "Could not look up the latest DepotDownloader release on GitHub."
        case .assetNotFound: return "The latest DepotDownloader release does not include a macOS arm64 zip."
        case .downloadFailed: return "Downloading DepotDownloader failed."
        case .extractionFailed(let detail):
            return detail.isEmpty ? "Could not extract DepotDownloader." : "Could not extract DepotDownloader:\n\(detail)"
        case .executableMissing: return "Extraction finished but the DepotDownloader binary was not present in the archive."
        }
    }
}
