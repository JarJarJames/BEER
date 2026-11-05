import Foundation

/// The order the library lists games in.
enum LibrarySortOrder: String, CaseIterable, Identifiable {
    /// Installed games first, then A to Z: the original order.
    case installedFirst
    case name
    case recentlyPlayed
    case mostPlayed

    var id: String { rawValue }

    var label: String {
        switch self {
        case .installedFirst: "Installed First"
        case .name: "Name"
        case .recentlyPlayed: "Recently Played"
        case .mostPlayed: "Most Played"
        }
    }
}
