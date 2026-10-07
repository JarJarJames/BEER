import Foundation
import SwiftUI

/// The four states Steam's own status menu offers.
enum SteamPersonaState: String, Codable, CaseIterable, Identifiable {
    case online = "Online"
    case away = "Away"
    case invisible = "Invisible"
    case offline = "Offline"

    var id: String { rawValue }
    var label: String { rawValue }

    /// The explanatory line Steam shows under the non-obvious options.
    var caption: String? {
        switch self {
        case .invisible: return "Appear offline, but you can still chat"
        case .offline: return "Sign out of Friends & Chat"
        default: return nil
        }
    }

    var tint: Color {
        switch self {
        case .online: return .green
        case .away: return .yellow
        case .invisible, .offline: return .secondary
        }
    }
}
