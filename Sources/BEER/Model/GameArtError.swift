import Foundation

/// Why library art didn't download.
enum GameArtError: LocalizedError {
    /// Steam has no such art for this game (many older games have no
    /// portrait cover). Not asked for again until BEER restarts.
    case missing
    case status(Int)

    var errorDescription: String? {
        switch self {
        case .missing: "Steam has no art at that address."
        case .status(let code): "Steam answered \(code) for the art."
        }
    }
}
