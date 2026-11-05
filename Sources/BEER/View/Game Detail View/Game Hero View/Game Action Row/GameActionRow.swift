import SwiftUI

struct GameActionRow: View {
    @ObservedObject var model: GameDetailViewModel
    @EnvironmentObject private var bottles: BottleStore
    @EnvironmentObject private var detector: ToolchainDetector

    var body: some View {
        HStack(spacing: 12) {
            if let bottle = model.installedBottle, bottle.gameLaunchExecutable != nil {
                switch model.installLocation {
                case .driveMissing(let name):
                    Label(InstallDriveStrings.connectToPlay(name), systemImage: "externaldrive.badge.xmark")
                        .font(.title3.bold())
                        .frame(minWidth: 180, minHeight: 36)
                        .padding(.horizontal, 12)
                        .background(Color.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
                case .missing where !model.game.effectiveIsNonSteam:
                    Button(action: model.startInstallOrLogin) {
                        Label("Reinstall", systemImage: "arrow.down.circle.fill")
                            .font(.title3.bold())
                            .frame(minWidth: 180, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isStartingInstall)
                    Text(InstallDriveStrings.filesMissing)
                        .foregroundStyle(.white.opacity(0.78))
                case .missing:
                    Text(InstallDriveStrings.filesMissing)
                        .foregroundStyle(.white.opacity(0.78))
                default:
                    if bottle.runtimeIsMissing {
                        MissingRuntimeNotice(bottle: bottle)
                    } else {
                        Button(action: { model.launch(bottle) }) {
                            Label("Play", systemImage: "play.fill")
                                .font(.title3.bold())
                                .frame(minWidth: 180, minHeight: 36)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(bottles.activeBottleIDs.contains(bottle.id) || model.mover.isMoving(bottle.id))
                    }
                }
            } else if let entry = model.download, entry.isActive {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(entry.phaseWithPercent).monospacedDigit()
                }
                .frame(minWidth: 180, minHeight: 36)
                .padding(.horizontal, 12)
                .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))

                Button(role: .destructive) {
                    model.cancelInstall(reason: "Cancelled.")
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .controlSize(.large)
            } else if model.game.effectiveIsNonSteam {
                // The bottle is gone, so there is nothing left to launch.
                Text("This game's files are missing.")
                    .foregroundStyle(.white.opacity(0.78))
                Button(role: .destructive, action: model.uninstall) {
                    Label("Remove from Library", systemImage: "trash")
                }
                .controlSize(.large)
            } else {
                Button(action: model.startInstallOrLogin) {
                    if model.isStartingInstall {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Starting…")
                        }
                        .frame(minWidth: 180, minHeight: 36)
                    } else {
                        Label(model.installedBottle == nil ? "Install" : "Resume / Reinstall", systemImage: "arrow.down.circle.fill")
                            .font(.title3.bold())
                            .frame(minWidth: 180, minHeight: 36)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(detector.candidates.isEmpty || model.isStartingInstall)

                if model.installedBottle != nil {
                    Button(role: .destructive, action: model.uninstall) {
                        Label("Uninstall", systemImage: "trash")
                    }
                    .controlSize(.large)
                }

                if detector.candidates.isEmpty {
                    Text(RuntimeStrings.noRuntime)
                        .font(.caption)
                        .foregroundStyle(.orange)
                    InstallRuntimeButton()
                }
            }

            GameMoreMenu(model: model)
        }
    }
}
