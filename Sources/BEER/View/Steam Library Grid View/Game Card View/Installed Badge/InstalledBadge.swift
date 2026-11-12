import SwiftUI

/// "INSTALLED", "UPDATE" when Steam has a newer build, or a warning when the
/// game's drive isn't connected.
struct InstalledBadge: View {
    let isDriveMissing: Bool
    var hasUpdate: Bool = false

    var body: some View {
        Text(text)
            .font(.caption2.weight(.heavy))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
    }

    private var text: String {
        if isDriveMissing { return InstallDriveStrings.cardBadge }
        return hasUpdate ? GameUpdateStrings.cardBadge : "INSTALLED"
    }

    private var color: Color {
        if isDriveMissing { return .orange }
        return hasUpdate ? .blue : .green
    }
}
