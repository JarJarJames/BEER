import Foundation

/// How the top of a game's page is arranged.
enum GamePageLayout: String, CaseIterable, Identifiable {
    /// The title, stats and buttons sit on the art: the original look.
    case overlay
    /// The art shows only the title; Play and the stats sit in a bar under
    /// it, like Steam's game pages.
    case steam

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overlay: "Overlay"
        case .steam: "Steam-style"
        }
    }
}
