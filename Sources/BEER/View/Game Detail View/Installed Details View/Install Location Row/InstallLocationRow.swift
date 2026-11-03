import SwiftUI

/// Which drive the game is on, with Move and, while it moves, its progress.
struct InstallLocationRow: View {
    let bottle: Bottle
    @ObservedObject var model: GameDetailViewModel

    var body: some View {
        let live = model.bottles.live(bottle)
        let progress = model.mover.progress[live.id]
        let blocked = model.moveBlockedReason(live)
        let isAvailable = model.bottles.installLocation(of: live).url != nil

        SettingsRow(title: InstallDriveStrings.locationTitle) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: live.gameDrive == nil ? "internaldrive" : "externaldrive")
                    Text(live.gameDrive?.name ?? InstallDriveStrings.thisMac)
                        .font(.callout)
                    if let progress {
                        ProgressView(value: progress.fraction)
                            .frame(width: InstallLocationRowLayout.progressWidth)
                        Text(progress.label)
                            .font(.caption)
                            .monospacedDigit()
                        Button(GameMoveStrings.cancelMove) { model.cancelMove(live) }
                    } else {
                        Button(GameMoveStrings.moveButton) { model.showMoveSheet(for: live) }
                            .disabled(blocked != nil)
                            .help(blocked ?? "")
                        Button(InstallDriveStrings.revealFiles) { model.bottles.revealGameFiles(live) }
                            .disabled(!isAvailable)
                    }
                    Spacer()
                }
                .controlSize(.small)

                if let message = model.moveMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(model.moveIsError ? Color.orange : Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
