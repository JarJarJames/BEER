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
        .onReceive(GameLinkRouter.shared.$pendingLaunchAppID.receive(on: DispatchQueue.main)) { appID in
            guard appID == model.appID else { return }
            GameLinkRouter.shared.pendingLaunchAppID = nil
            model.launchFromShortcut()
        }
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
        .sheet(isPresented: $model.isShowingInstallSheet) {
            InstallSheet(
                game: model.game,
                report: model.installSpaceReport,
                onInstall: model.confirmInstall,
                onCancel: { model.isShowingInstallSheet = false }
            )
        }
        .sheet(isPresented: $model.isShowingShortcutIcon) {
            ShortcutIconSheet(
                game: model.game,
                account: model.isSteamConnected ? model.cloudAuth.account : nil,
                rememberClientIcon: { model.library.setClientIconURL($0, appID: model.appID) },
                onSave: model.shortcutIconSaved,
                onCancel: { model.isShowingShortcutIcon = false }
            )
        }
        .sheet(isPresented: $model.isShowingSaveBackups) {
            if let bottle = model.installedBottle {
                SaveBackupsSheet(bottle: bottle, model: model)
            }
        }
        .sheet(item: $model.restoreConflictPrompt) { prompt in
            RestoreConflictSheet(
                prompt: prompt,
                onKeepRestored: { model.resolveRestoreConflict(prompt, keepRestored: true) },
                onUseCloud: { model.resolveRestoreConflict(prompt, keepRestored: false) },
                onCancel: { model.restoreConflictPrompt = nil }
            )
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
            "Remove \(model.game.name)?",
            isPresented: $model.confirmRemoveNonSteamGame
        ) {
            Button("Remove Game", role: .destructive, action: model.uninstall)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The game's folder inside BEER is deleted. If you moved it in, this is the only copy; if you copied it, your original is untouched.")
        }
        .alert(
            DiskSpaceStrings.alertTitle,
            isPresented: Binding(get: { model.diskSpaceShortfall != nil }, set: { if !$0 { model.diskSpaceShortfall = nil } }),
            presenting: model.diskSpaceShortfall
        ) { _ in
            Button(DiskSpaceStrings.okButton, role: .cancel) { model.diskSpaceShortfall = nil }
        } message: { shortfall in
            Text(DiskSpaceStrings.shortfall(shortfall))
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
