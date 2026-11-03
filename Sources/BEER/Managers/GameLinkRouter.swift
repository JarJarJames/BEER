import Foundation

/// Carries a `beer://game/<appID>` link from a shortcut to the window: the
/// main shell opens that game's page, and the page starts the game if it's
/// installed. A game that isn't installed just shows its page with Install.
@MainActor
final class GameLinkRouter: ObservableObject {
    static let shared = GameLinkRouter()

    /// The game whose page a link asked for, until the shell shows it.
    @Published var requestedAppID: Int?
    /// The game to start once its page is open. The page clears it.
    @Published var pendingLaunchAppID: Int?

    /// False for anything that isn't a game link.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let link = GameShortcutLink(url: url) else { return false }
        pendingLaunchAppID = link.appID
        requestedAppID = link.appID
        return true
    }
}
