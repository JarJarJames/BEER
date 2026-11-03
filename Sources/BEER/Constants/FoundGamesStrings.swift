import Foundation

/// User-facing text for games found on a drive that aren't in BEER.
enum FoundGamesStrings {
    static let review = "Review…"
    static let dismiss = "Not Now"
    static let sheetTitle = "Games Found"
    static let addButton = "Add Games"
    static let cancelButton = "Cancel"
    static let adding = "Setting up the games…"
    static let steam = "Steam"
    static let nonSteam = "Non-Steam"
    static let notOwned = "Not in your Steam library, so it can't be added."
    static let alreadyInstalled = "Already installed in BEER."
    static let noExecutable = "No game .exe found in the folder."
    static let verifyNote = "Each game gets a new bottle and uses its files where they are. To check a Steam game's files, use Reinstall / Validate on its page."

    static func banner(count: Int, drive: String) -> String {
        "Found \(count) game\(count == 1 ? "" : "s") on “\(drive)” that \(count == 1 ? "isn't" : "aren't") in BEER."
    }

    static func message(drive: String) -> String {
        "These folders on “\(drive)” hold games from an earlier install. Pick the ones to add back."
    }

    static func addFailed(_ name: String, _ reason: String) -> String {
        "Couldn't add \(name): \(reason)"
    }
}
