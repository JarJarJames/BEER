import Foundation

/// User-facing text for the Steam client loader row in Advanced Settings.
enum SteamClientLoaderStrings {
    static let title = "Steam client loader"
    static let modeCaption = "Starts the game through the Steam emulator's loader, which stands in for a running Steam. Automatic uses it for games wrapped in Steam's DRM, very old games built on Steam.dll, and games with no steam_api.dll. Choose Always if a game quits right away or asks for Steam."

    static let overlayTitle = "Overlay DLL"
    static let overlayToggle = "Load the overlay DLL into the game"
    static let overlayCaption = "For the few games that check their own memory for Steam's overlay. Leave off unless a game needs it."

    static let staysOpenTitle = "Keep loader open"
    static let staysOpenToggle = "Keep the loader running while you play"
    static let staysOpenCaption = "For launchers that restart themselves and then can't find Steam. The loader shows a dialog; click OK in it once you've finished playing."
}
