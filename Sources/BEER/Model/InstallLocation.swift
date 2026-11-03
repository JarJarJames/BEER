import Foundation

/// Where an installed game's files are right now.
enum InstallLocation: Equatable {
    case available(URL)
    /// The files are on a drive that isn't connected. Nothing may be written
    /// to the stored path: with the drive gone it no longer leads to the game.
    case driveMissing(driveName: String)
    /// The drive is there (or the game is on this Mac) but the folder isn't.
    case missing

    var url: URL? {
        if case .available(let url) = self { return url }
        return nil
    }

    var missingDriveName: String? {
        if case .driveMissing(let name) = self { return name }
        return nil
    }
}
