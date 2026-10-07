import SwiftUI

struct GameDetailScreen: View {
    let onBack: () -> Void
    @StateObject private var model: GameDetailViewModel

    init(game: SteamLibraryGame, onBack: @escaping () -> Void, dependencies: GameDetailDependencies) {
        self.onBack = onBack
        _model = StateObject(wrappedValue: GameDetailViewModel(game: game, dependencies: dependencies))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                GameHeroView(model: model)
                if let download = model.download, download.isActive {
                    Divider()
                    DownloadProgressView(entry: download)
                }
                if let bottle = model.installedBottle {
                    Divider()
                    InstalledDetailsView(bottle: bottle, model: model)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Structured, so navigating away actually cancels the Steam query
        // instead of leaving a detached logon running to completion.
        .task(id: model.appID) { await model.loadDLC(force: false) }
        .task(id: model.patchStatusProbeID) { await model.refreshPatchStatus() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Label("Library", systemImage: "chevron.backward")
                }
            }
        }
        .sheet(isPresented: $model.isShowingCloudConnect) {
            SteamCloudQRSheet(onConnected: model.cloudDidConnect)
        }
        .sheet(isPresented: $model.isShowingDLCManager) {
            if let bottle = model.installedBottle, let installDir = bottle.resolvedInstallDirectory {
                DLCManagerView(
                    game: model.game,
                    bottle: bottle,
                    installDir: installDir,
                    emulatorApplied: model.cachedPatchStatus == .applied,
                    dependencies: model.dependencies,
                    onDone: {
                        model.isShowingDLCManager = false
                        // The manager may have written configs.app.ini, so the
                        // emulator row's on-disk probe is now stale.
                        model.patchProbeTick &+= 1
                    }
                )
            }
        }
        .confirmationDialog(
            "Back up and clear local saves?",
            isPresented: Binding(get: { model.confirmClearBottle != nil }, set: { if !$0 { model.confirmClearBottle = nil } }),
            presenting: model.confirmClearBottle
        ) { bottle in
            Button("Back up & clear", role: .destructive) {
                model.clearLocalSaves(for: bottle)
                model.confirmClearBottle = nil
            }
            Button("Cancel", role: .cancel) { model.confirmClearBottle = nil }
        } message: { _ in
            Text("Your current local saves for this game are copied to a timestamped backup, then removed from the bottle. Nothing is uploaded or deleted from Steam Cloud. You can restore by pulling from cloud, or from the backup folder.")
        }
    }
}
