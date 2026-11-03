import Foundation

/// Where a game can be put: inside its bottle on this Mac, or on a drive.
enum InstallTarget: Hashable, Identifiable, Sendable {
    case thisMac
    case drive(InstallVolume)

    var id: String {
        switch self {
        case .thisMac: return "this-mac"
        case .drive(let volume): return volume.id
        }
    }

    var volume: InstallVolume? {
        if case .drive(let volume) = self { return volume }
        return nil
    }

    var name: String { volume?.name ?? InstallDriveStrings.thisMac }

    /// Whether a game whose files are on `drive` (nil: this Mac) is already here.
    func holds(_ drive: GameDrive?) -> Bool {
        switch self {
        case .thisMac: return drive == nil
        case .drive(let volume): return drive != nil && drive?.uuid == volume.uuid
        }
    }
}
