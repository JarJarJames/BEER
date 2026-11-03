import Foundation

/// User-facing text about which drive a game is on.
enum InstallDriveStrings {
    static let thisMac = "This Mac"
    static let unknownFormat = "Unknown format"
    static let caseSensitive = "This drive is case-sensitive, which breaks Windows games. Use a drive formatted as APFS (not case-sensitive)."
    static let locationTitle = "Location"
    static let revealFiles = "Reveal Game Files"
    static let freeUnknown = "Free space unknown"
    static let putOn = "Put it on"

    static func unsupportedFormat(_ format: String) -> String {
        "\(format) drives can't run Windows games. Reformat it as APFS in Disk Utility to use it."
    }

    static func free(_ bytes: Int64) -> String { "\(bytes.fileSizeString) free" }

    static func driveNotConnected(_ name: String) -> String {
        "“\(name)” isn't connected. Connect it and try again."
    }

    // MARK: Game page and library

    static func connectToPlay(_ name: String) -> String { "Connect “\(name)” to play" }

    static func driveMissingDetail(_ name: String) -> String {
        "This game's files are on “\(name)”. Connect the drive to play, sync saves or change settings."
    }

    static let filesMissing = "This game's files are missing."
    static let cardBadge = "DRIVE NOT CONNECTED"

    static func syncNeedsDrive(_ name: String) -> String {
        "Connect “\(name)” to sync saves. This game's files are on it, and some games keep saves there."
    }

    // MARK: Downloads

    static func downloadPaused(_ name: String) -> String {
        "Download paused: “\(name)” was disconnected. Connect it, then click Resume."
    }

    static func resumeDriveMissing(_ name: String) -> String {
        "This game's download is on “\(name)”. Connect it to resume."
    }

    static let resumeHere = "Downloads into the game's current folder. To put it somewhere else, use Move on the game page, or uninstall first."

    // MARK: Uninstall

    static func removeWhileMissingTitle(_ game: String) -> String { "Remove \(game) from BEER?" }

    static func removeWhileMissingMessage(_ drive: String) -> String {
        "“\(drive)” isn't connected, so the game's files stay on it. Connect it later and BEER offers to add the game back."
    }

    static let removeButton = "Remove"
    static let cancelButton = "Cancel"
}
