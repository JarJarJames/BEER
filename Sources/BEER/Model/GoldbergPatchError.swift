import AchievementUI
import Foundation

enum GoldbergPatchError: LocalizedError {
    case stubsMissing
    case unreadableInstallDir(String)
    case noSteamApiFound

    var errorDescription: String? {
        switch self {
        case .stubsMissing:
            return "The Steam emulator binaries weren't found. Reapply it from this game's settings."
        case .unreadableInstallDir(let path):
            return "Could not read the game's install directory at \(path)."
        case .noSteamApiFound:
            return "No steam_api.dll / steam_api64.dll was found in the install. Either the game doesn't use Steamworks, or the depot download is incomplete."
        }
    }
}
