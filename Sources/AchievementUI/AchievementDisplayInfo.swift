import SwiftUI

/// A single achievement's display info as written into
/// `steam_settings/achievements.json` — read back locally (no network) by
/// `AchievementWatcher` to label a toast, since the file already carries
/// everything needed once GoldbergApplicator has written it once.
///
/// Lives in this small library target (not the BEER executable target)
/// specifically so `AchievementToastContent` below can be edited in Xcode's
/// canvas: SwiftUI Previews' dylib-injection mechanism only works for files
/// in a library target, not an `executableTarget` — a real SwiftPM/Xcode
/// limitation, not a build-setting toggle.
public struct AchievementDisplayInfo: Codable, Equatable {
    public let name: String
    public let displayName: String
    public let description: String
    public let hidden: Bool
    public let icon: String?
    public let icongray: String?

    public init(name: String, displayName: String, description: String, hidden: Bool, icon: String?, icongray: String?) {
        self.name = name
        self.displayName = displayName
        self.description = description
        self.hidden = hidden
        self.icon = icon
        self.icongray = icongray
    }
}
