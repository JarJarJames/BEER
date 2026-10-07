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

/// The achievement-unlock toast's visual content — just the card, no window
/// chrome. Hosted inside BEER's `AchievementOverlayWindow`'s borderless panel.
public struct AchievementToastContent: View {
    public let achievement: AchievementDisplayInfo

    public init(achievement: AchievementDisplayInfo) {
        self.achievement = achievement
    }

    public var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: achievement.icon.flatMap(URL.init)) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "trophy.fill").foregroundStyle(.yellow)
            }
            .frame(width: 40, height: 40)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text("Achievement Unlocked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(achievement.displayName)
                    .font(.headline)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 320)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(radius: 8)
    }
}

// The real window is borderless/transparent, so previewing on a plain dark
// backdrop is closer to how this actually sits over a game than a default
// white canvas would be.
#Preview("Achievement Toast") {
    AchievementToastContent(achievement: AchievementDisplayInfo(
        name: "ACH_WIN_ONE_GAME",
        displayName: "Winner",
        description: "Win one game.",
        hidden: false,
        icon: nil,
        icongray: nil
    ))
    .padding(40)
    .background(Color.black)
}

#Preview("Long name, no icon") {
    AchievementToastContent(achievement: AchievementDisplayInfo(
        name: "ACH_LONG",
        displayName: "A Very Long Achievement Title That Might Wrap Or Truncate",
        description: "A longer description to sanity-check layout.",
        hidden: false,
        icon: nil,
        icongray: nil
    ))
    .padding(40)
    .background(Color.black)
}

#Preview("Hidden achievement, with icon") {
    AchievementToastContent(achievement: AchievementDisplayInfo(
        name: "ACH_SECRET",
        displayName: "???",
        description: "A hidden achievement.",
        hidden: true,
        icon: "https://cdn.akamai.steamstatic.com/steamcommunity/public/images/apps/480/e7ec38c518c05199352a54baf7ecc72ba1e9c2e6.jpg",
        icongray: nil
    ))
    .padding(40)
    .background(Color.black)
}
