import Foundation

/// A shortcut BEER made, kept so uninstalling can remove it again.
struct GameShortcutRecord: Codable, Equatable {
    let appID: Int
    let kind: GameShortcutKind
    /// Where BEER put it. A shortcut no longer here was moved or renamed by
    /// the player, and is left alone.
    let path: String
}
