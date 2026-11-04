import Foundation

/// The pieces of a game's art the player can replace.
enum GameArtSlot: String, CaseIterable, Identifiable, Codable {
    /// The portrait art on Cover cards.
    case cover
    /// The wide art across the top of the game page.
    case banner
    /// The title art on the banner.
    case logo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cover: "Cover"
        case .banner: "Banner"
        case .logo: "Logo"
        }
    }

    var hint: String {
        switch self {
        case .cover: "Portrait, like 600 × 900. Used on Cover cards."
        case .banner: "Wide, like 1920 × 620. Used on the game page."
        case .logo: "A PNG with a transparent background works best."
        }
    }
}
