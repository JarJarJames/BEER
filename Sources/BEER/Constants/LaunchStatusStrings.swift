import Foundation

/// User-facing text for what Play is doing, from the click to the game's window.
enum LaunchStatusStrings {
    static let settingUpWine = "Setting up Wine…"
    static let syncingSaves = "Syncing saves…"
    static let startingGame = "Starting game…"
    static let playing = "Playing"

    static let cardSettingUpWine = "SETTING UP WINE…"
    static let cardSyncingSaves = "SYNCING SAVES…"
    static let cardStartingGame = "STARTING GAME…"
    static let cardPlaying = "PLAYING"
    static let cardFailed = "COULDN'T START"

    static let slowHint = "Wine can be slow the first time a game starts. The bottle's log shows what it's doing."
    static let showLog = "Show Log"
    static let showLogHelp = "Show this game's Wine log (beer.log) in Finder."

    static let wineSetupFailed = "Couldn't set up Wine for this game. The bottle's log has the details."
    static let noExecutable = "This game has no program set to launch. Reinstall it to find one."
    static let gameDidNotStart = "The game couldn't be started. The bottle's log has the details."

    static func clientLoaderFailed(_ detail: String) -> String { "Couldn't launch: \(detail)" }

    static func graphicsSetupFailed(_ translator: String, detail: String) -> String {
        "Couldn't set up \(translator): \(detail)"
    }

    static func closedBeforeWindow(exitCode: Int32) -> String {
        "The game closed before its window opened (exit code \(exitCode)). The bottle's log has the details."
    }
}
