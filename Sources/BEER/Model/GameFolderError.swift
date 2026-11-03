import Foundation

/// Why BEER wouldn't put a game folder somewhere, or take one away.
enum GameFolderError: LocalizedError, Equatable {
    case driveNotConnected(String)
    case unsupportedDrive(String)
    case copyMismatch(String)
    case cancelled
    case notAGameFolder(String)

    var errorDescription: String? {
        switch self {
        case .driveNotConnected(let name): return InstallDriveStrings.driveNotConnected(name)
        case .unsupportedDrive(let reason): return reason
        case .copyMismatch(let file): return GameMoveStrings.copyMismatch(file)
        case .cancelled: return GameMoveStrings.cancelled
        case .notAGameFolder(let path): return GameMoveStrings.notAGameFolder(path)
        }
    }
}
