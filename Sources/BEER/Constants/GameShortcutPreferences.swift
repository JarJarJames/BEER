import Foundation

/// The install sheet's shortcut checkboxes, remembered between installs.
enum GameShortcutPreferences {
    static let desktopKey = "createDesktopShortcutOnInstall"
    static let applicationKey = "createApplicationShortcutOnInstall"

    static func kindsToCreateOnInstall(_ defaults: UserDefaults = .standard) -> [GameShortcutKind] {
        var kinds: [GameShortcutKind] = []
        if defaults.bool(forKey: desktopKey) { kinds.append(.desktop) }
        if defaults.bool(forKey: applicationKey) { kinds.append(.application) }
        return kinds
    }
}
