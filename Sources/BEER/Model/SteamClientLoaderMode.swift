import Foundation

/// Whether a Steam game starts through gbe_fork's steamclient loader (see
/// `ColdClientApplicator`) instead of straight from its exe.
enum SteamClientLoaderMode: String, Codable, CaseIterable, Identifiable {
    /// Only when the game needs it: Steam's DRM wrapper, the old `Steam.dll`
    /// library, or no `steam_api.dll` to patch.
    case automatic
    case always
    case off

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Automatic"
        case .always: "Always"
        case .off: "Off"
        }
    }
}
