import SwiftUI

struct SteamEmulatorRow: View {
    let bottle: Bottle
    @ObservedObject var model: GameDetailViewModel

    var body: some View {
        SettingsRow(title: "Steam emulator") {

            HStack(spacing: 8) {
                switch model.cachedPatchStatus {
                case nil:
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .applied:
                    Label("Applied", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                case .notApplied:
                    Label("Not applied", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                case .noDLLsFound:
                    Label("Game has no Steam DLLs", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                case .installDirMissing:
                    Label("Install folder not found", systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }

                if model.isPatching {
                    ProgressView().controlSize(.small)
                }
            }

            Spacer()

            switch model.cachedPatchStatus {
            case .notApplied:
                Button {
                    model.applyGoldbergPatch(to: bottle)
                } label: {
                    Label("Apply", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(model.isPatching)
            case .applied:
                Menu {
                    Button {
                        model.applyGoldbergPatch(to: bottle)
                    } label: {
                        Label("Reapply (after GBE_Fork upgrade)", systemImage: "arrow.clockwise")
                    }
                    Button {
                        model.triggerTestAchievementUnlock(for: bottle)
                    } label: {
                        Label("Test: unlock next achievement", systemImage: "star.fill")
                    }
                    Button {
                        model.resetLocalTestAchievements(for: bottle)
                    } label: {
                        Label("Test: reset local unlocks", systemImage: "arrow.counterclockwise")
                    }
                    Button(role: .destructive) {
                        model.restoreOriginalDLLs(for: bottle)
                    } label: {
                        Label("Restore original Steam DLLs", systemImage: "arrow.uturn.backward")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(model.isPatching)
            case nil, .noDLLsFound, .installDirMissing:
                EmptyView()
            }
        }

        if let message = model.patchStatusMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(model.patchStatusIsError ? .red : .green)
                .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
