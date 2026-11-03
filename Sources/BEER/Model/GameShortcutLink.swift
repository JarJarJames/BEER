import Foundation

/// The `beer://game/<appID>` link a shortcut opens. It goes through BEER, so
/// the game starts with its bottle, runtime, cloud sync and achievements.
struct GameShortcutLink: Equatable {
    static let scheme = "beer"
    private static let host = "game"

    let appID: Int

    var url: URL {
        URL(string: "\(Self.scheme)://\(Self.host)/\(appID)")!
    }

    /// Nil for anything that isn't a well-formed game link.
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme, url.host?.lowercased() == Self.host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 1, let appID = Int(parts[0]), appID != 0 else { return nil }
        self.appID = appID
    }

    init(appID: Int) {
        self.appID = appID
    }
}
