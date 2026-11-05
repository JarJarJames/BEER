import SwiftUI

/// "INSTALLED", or a warning when the game's drive isn't connected.
struct InstalledBadge: View {
    let isDriveMissing: Bool

    var body: some View {
        Text(isDriveMissing ? InstallDriveStrings.cardBadge : "INSTALLED")
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((isDriveMissing ? Color.orange : Color.green).opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
    }
}
