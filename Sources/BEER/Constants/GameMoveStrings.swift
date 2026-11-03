import Foundation

/// User-facing text for moving an installed game between this Mac and drives.
enum GameMoveStrings {
    static let moveButton = "Move…"
    static let sheetTitle = "Move Game"
    static let moveTo = "MOVE TO:"
    static let confirmButton = "Move"
    static let cancelButton = "Cancel"
    static let cancelMove = "Cancel Move"
    static let measuring = "Measuring…"
    static let cancelled = "The move was cancelled. The game is still where it was."
    static let checking = "Checking the copy…"
    static let finishing = "Finishing…"
    static let currentLocation = "Current location"
    static let registryNote = "A few games remember their install folder. If this one won't start after the move, use Reinstall / Validate."

    static func copying(_ copied: Int64, of total: Int64) -> String {
        "Moving… \(copied.fileSizeString) of \(total.fileSizeString)"
    }

    static func copyMismatch(_ file: String) -> String {
        "The copy of “\(file)” didn't match the original, so the move was stopped. The game is still where it was."
    }

    static func notAGameFolder(_ path: String) -> String {
        "BEER only deletes game folders it made, and \(path) isn't one. Nothing was deleted."
    }

    static func moved(to target: String) -> String { "Moved to \(target)." }

    static func movedKeptOld(to target: String, reason: String) -> String {
        "Moved to \(target), but the old copy was kept. \(reason)"
    }

    static func savesNotBackedUp(_ reason: String) -> String {
        "Its saves couldn't be backed up first (\(reason)). Delete the old folder yourself once you've checked the game."
    }

    static let newCopyUnreachable = "The drive it moved to was disconnected, so the old copy stays until it's back."

    static func oldCopyNotDeleted(_ reason: String) -> String {
        "It couldn't be deleted (\(reason)). Delete the old folder yourself."
    }

    static func size(_ bytes: Int64) -> String { bytes.fileSizeString }

    // MARK: Why Move is turned off

    static let blockedRunning = "Quit the game to move it."
    static let blockedDownloading = "Wait for the download to finish to move it."
    static let blockedSyncing = "Wait for the save sync to finish to move it."
    static let blockedMoving = "This game is already moving."
    static let blockedPatching = "Wait for the Steam emulator to finish to move it."

    static func blockedDriveMissing(_ name: String) -> String { "Connect “\(name)” to move this game." }

    static let alreadyHere = "Already here"
    static let waitForMove = "Wait for the move to finish."
}
