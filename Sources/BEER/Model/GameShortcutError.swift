import Foundation

enum GameShortcutError: LocalizedError, Equatable {
    case nameTaken(String)
    case noArtwork
    case artworkUnreadable

    var errorDescription: String? {
        switch self {
        case .nameTaken(let name): GameShortcutStrings.nameTaken(name)
        case .noArtwork: GameShortcutStrings.noArtwork
        case .artworkUnreadable: GameShortcutStrings.artworkUnreadable
        }
    }
}
