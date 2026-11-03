/// Where a game shortcut lives.
enum GameShortcutKind: String, Codable, CaseIterable {
    /// On the Mac desktop.
    case desktop
    /// In `/Applications`, beside the user's other apps.
    case application
}
