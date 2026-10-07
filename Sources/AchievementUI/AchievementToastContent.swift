import SwiftUI

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
