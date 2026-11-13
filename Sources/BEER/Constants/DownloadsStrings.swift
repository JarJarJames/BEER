import Foundation

/// User-facing text for the Downloads button and list.
enum DownloadsStrings {
    static let title = "Downloads"
    static let pause = "Pause"
    static let resume = "Resume"
    static let pausing = "Pausing…"
    static let paused = "Paused"
    static let resumeHelp = "Opens the game's page and carries on from what's already downloaded."

    // MARK: Library card badge

    static func cardDownloading(_ fraction: Double) -> String { "DOWNLOADING \(fraction.percentString)" }
    static func cardPaused(_ fraction: Double) -> String { "PAUSED \(fraction.percentString)" }
    static let cardNotInstalled = "NOT INSTALLED"
}
