import SwiftUI

struct GameActionRow: View {
    let model: GameDetailViewModel
    @Environment(BottleStore.self) private var bottles
    @Environment(ToolchainDetector.self) private var detector

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
                    } else if model.download?.isPaused == true {
                        // A paused update leaves the files half written, so
                        // it finishes before the game can run.
                        resumeButton
                    } else if let phase = bottles.launchPhase(for: bottle.id), phase.isInProgress {
                        LaunchStatusView(phase: phase, onShowLog: { bottles.revealLog(bottle) })
                    } else {
                        VStack(alignment: .leading, spacing: LaunchStatusLayout.spacing) {
                            Button(action: { model.launch(bottle) }) {
                                Label("Play", systemImage: "play.fill")
                                    .font(.title3.bold())
                                    .frame(minWidth: 180, minHeight: 36)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(bottles.activeBottleIDs.contains(bottle.id) || model.mover.isMoving(bottle.id))

                            // The last launch stopped on this; Play tries again.
                            if case .failed(let message) = bottles.launchPhase(for: bottle.id) {
                                LaunchNote(text: message, isError: true, onShowLog: { bottles.revealLog(bottle) })
                            }
                        }

                        if let update = updateButton {
                            Button(action: model.startInstallOrLogin) {
                                Label(update.title, systemImage: "arrow.down.circle")
                            }
                            .controlSize(.large)
                            .help(update.help)
                            .disabled(bottles.activeBottleIDs.contains(bottle.id) || model.mover.isMoving(bottle.id)
                                      || model.isStartingInstall)
                        }
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
                    model.cancelInstall()
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .controlSize(.large)
                .disabled(entry.status == .cancelling)
            } else if model.download?.isPaused == true {
                resumeButton
                Button(role: .destructive) {
                    model.cancelInstall()
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

    private var resumeButton: some View {
        Button(action: model.resumeInstall) {
            if model.isStartingInstall {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Starting…")
                }
                .frame(minWidth: 180, minHeight: 36)
            } else {
                Label(DownloadsStrings.resume, systemImage: "play.circle.fill")
                    .font(.title3.bold())
                    .frame(minWidth: 180, minHeight: 36)
            }
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(model.isStartingInstall)
    }

    /// Update for a game Steam has a newer build of; Check for Updates for one
    /// BEER can't judge yet. Both run the Reinstall / Validate download.
    private var updateButton: (title: String, help: String)? {
        if model.offersUpdateBeforePlay { return (GameUpdateStrings.updateButton, GameUpdateStrings.updateHelp) }
        if !model.game.effectiveIsNonSteam, model.game.isUpdateUntracked {
            return (GameUpdateStrings.checkButton, GameUpdateStrings.checkHelp)
        }
        return nil
    }
}
