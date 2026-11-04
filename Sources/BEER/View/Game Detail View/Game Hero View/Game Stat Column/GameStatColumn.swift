import SwiftUI

/// A stat in the Steam-style bar: a bright heading over a dimmer value.
struct GameStatColumn: View {
    let stat: GameStat

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(stat.title)
                .font(.callout.weight(.medium))
                .tracking(GameBannerLayout.statTitleTracking)
                .foregroundStyle(.white.opacity(0.9))
            Text(stat.value)
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.55))
        }
        .fixedSize()
    }
}
