import Foundation
import SwiftUI

/// Steam's persona states. `offline` is only ever reported by Steam; BEER
/// never sets it (see `choices`).
enum SteamPersonaState: String, Codable, CaseIterable, Identifiable {
    case online = "Online"
    case away = "Away"
    case invisible = "Invisible"
    case offline = "Offline"

    /// What the status menu offers. Not Offline: persona state belongs to the
    /// account, and Offline signs every device out of Friends & Chat — so
    /// picking it in BEER signed the user's Steam client on their PC and Mac
    /// out each time BEER opened.
    static let choices: [SteamPersonaState] = [.online, .away, .invisible]

    /// The state BEER may send to Steam. A saved Offline from older builds
    /// becomes Invisible, which hides the user without signing anyone out.
    var assertable: SteamPersonaState { self == .offline ? .invisible : self }

    var id: String { rawValue }
    var label: String { rawValue }

    /// The explanatory line Steam shows under the non-obvious options.
    var caption: String? {
        switch self {
        case .invisible: return "Appear offline, but you can still chat"
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
