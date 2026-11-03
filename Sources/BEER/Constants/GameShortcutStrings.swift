import Foundation

/// User-facing text for game shortcuts and their icon.
enum GameShortcutStrings {
    static let createDesktop = "Create Desktop Shortcut"
    static let createApplication = "Create Application Shortcut"
    static let editIcon = "Shortcut Icon…"
    static let installDesktop = "Create desktop shortcut"
    static let installApplication = "Create application shortcut"
    static let noArtwork = "This game has no artwork to make an icon from."
    static let artworkUnreadable = "The game's artwork couldn't be read."

    static func nameTaken(_ name: String) -> String {
        "Something named “\(name)” is already there, so BEER left it alone."
    }

    static func created(_ kind: GameShortcutKind) -> String {
        switch kind {
        case .desktop: "Desktop shortcut created."
        case .application: "Application shortcut created in Applications."
        }
    }

    static func failed(_ message: String) -> String { "Couldn't create the shortcut: \(message)" }

    // Icon sheet
    static let sheetTitle = "Shortcut Icon"
    static let coverOption = "Cover"
    static let steamIconOption = "Steam icon"
    static let checkingSteamIcon = "Checking for Steam's icon…"
    static let noSteamIcon = "Steam has no icon for this game at 256×256 or larger."
    static let cropHint = "Drag the square to choose what the icon shows."
    static let zoom = "Zoom"
    static let preview = "Preview"
    static let reset = "Reset"
    static let save = "Save"
    static let cancel = "Cancel"
}
