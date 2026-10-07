import Foundation

enum DepotDownloaderError: LocalizedError {
    case binaryMissing
    case spawnFailed(String)
    case authenticationFailed(String)
    case sessionExpired
    case downloadFailed(Int32, String)
    case launchExeNotFound
    case installDirMissing(String)
    case appNotOwned(String)

    var errorDescription: String? {
        switch self {
        case .binaryMissing:
            return "DepotDownloader is not installed. Open the app's onboarding step to install it."
        case .spawnFailed(let detail):
            return "Could not start DepotDownloader: \(detail)"
        case .authenticationFailed(let detail):
            return "Steam sign-in failed: \(detail)"
        case .sessionExpired:
            return "Steam session expired."
        case .downloadFailed(let code, let tail):
            return "DepotDownloader exited with code \(code). Last output:\n\(tail)"
        case .launchExeNotFound:
            return "Download completed but we couldn't find a Windows .exe in the install directory."
        case .installDirMissing(let path):
            return "The game's install folder is missing at \(path). Reinstall the game before adding DLC."
        case .appNotOwned(let name):
            return "\(name) isn't available on this Steam account. If you bought it recently, sign out and back in so Steam re-sends your licences."
        }
    }
}
