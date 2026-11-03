import Foundation

/// Sizes for game shortcut icons.
enum ShortcutIconLimits {
    /// Steam's icon is offered only with an image at least this wide; smaller
    /// ones look blurry in the Dock.
    static let minimumSteamIconSide = 256
    /// The sizes written into a shortcut's `.icns`.
    static let icnsSides = [16, 32, 128, 256, 512]
}
