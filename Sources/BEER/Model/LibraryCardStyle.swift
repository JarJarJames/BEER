import Foundation

/// How the library shows each game. The Library and Installed tabs share it.
enum LibraryCardStyle: String, CaseIterable, Identifiable {
    /// Steam's wide header art, the original look.
    case wide
    /// Steam's portrait cover, several to a row.
    case cover
    /// One row per game: icon, name and caption.
    case list

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wide: "Wide"
        case .cover: "Cover"
        case .list: "List"
        }
    }

    var systemImage: String {
        switch self {
        case .wide: "rectangle.grid.2x2"
        case .cover: "square.grid.3x3"
        case .list: "list.bullet"
        }
    }
}
