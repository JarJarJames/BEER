import Foundation

/// User-facing text for the Display rows.
enum DisplayModeStrings {
    static let resolutionTitle = "Resolution"
    static let highResolutionCaption = "Exposes Retina resolutions to the game (up to twice the width and height) and treats it as DPI-aware. Sharper, but substantially more demanding; some games may not handle high-DPI mode correctly."
    static let standardCaption = "Uses macOS point dimensions for better performance and compatibility. On Retina displays this limits games to half the high-resolution width and height."

    static let captureTitle = "Capture Display"
    static let captureToggle = "Capture display in fullscreen"
    static let captureCaption = "Turn on if the hidden cursor reappears at the screen edges. Blocks the Dock and menu bar while the game is fullscreen and frontmost."
}
