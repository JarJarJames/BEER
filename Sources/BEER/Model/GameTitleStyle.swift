import Foundation

/// What the game page's banner shows as the title.
enum GameTitleStyle: String, CaseIterable, Identifiable {
    /// Steam's logo art, or the name when the game has none.
    case logo
    /// The game's name as text.
    case name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .logo: "Logo"
        case .name: "Name"
        }
    }
}
