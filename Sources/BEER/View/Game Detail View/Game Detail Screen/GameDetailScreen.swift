import SwiftUI

struct GameDetailScreen: View {
    let onBack: () -> Void
    @State private var model: GameDetailViewModel
    @AppStorage(AppearancePreferences.showsBackdropKey) private var showsBackdrop = AppearanceDefaults.showsBackdrop
    @AppStorage(AppearancePreferences.layoutKey) private var layout = AppearanceDefaults.layout
    @AppStorage(AppearancePreferences.shownStatsKey) private var shownStats = AppearanceDefaults.shownStats

    /// Remeasured when the game is installed, removed, or the stat turned on.
    private var sizeProbeID: String? {
        guard GamePageStat.decode(shownStats).contains(.size), let bottle = model.installedBottle else { return nil }
        return "\(bottle.id)-\(model.installLocation?.url?.path ?? "")"
    }

    init(game: SteamLibraryGame, onBack: @escaping () -> Void, dependencies: GameDetailDependencies) {
        self.onBack = onBack
        _model = State(initialValue: GameDetailViewModel(game: game, dependencies: dependencies))
    }

    var body: some View {
        page
            .sheet(item: sheetBinding) { sheet in
                sheetContent(sheet)
            }
            .confirmationDialog(
                confirmationTitleText,
                isPresented: isShowingConfirmation,
                presenting: model.dialog
            ) { dialog in
                confirmationActions(dialog)
            } message: { dialog in
                confirmationMessage(dialog)
            }
            .alert(
                DiskSpaceStrings.alertTitle,
                isPresented: isShowingShortfall,
                presenting: model.dialog?.shortfall
            ) { _ in
                Button(DiskSpaceStrings.okButton, role: .cancel) { model.dialog = nil }
            } message: { shortfall in
                Text(DiskSpaceStrings.shortfall(shortfall))
            }
    }

    /// The page, without the sheets and dialogs it shows.
    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Steam-style runs edge to edge and fades into the page, so
                // it sits outside the margin with no divider under it.
                if layout == .steam { GameHeroView(model: model) }
                VStack(alignment: .leading, spacing: 22) {
                    if layout == .overlay { GameHeroView(model: model) }
                    if let download = model.download, download.isInProgress {
                        if layout == .overlay { Divider() }
                        DownloadProgressView(entry: download, onPause: model.pauseDownload)
                    }
                    if let bottle = model.installedBottle {
                        if layout == .overlay { Divider() }
                        InstalledDetailsView(bottle: bottle, model: model)
                    }
                }
                .padding(GameBannerLayout.pageInset)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // The page's height follows its width, so its scroll bar must
            // never take width; see `OverlayScrollers`.
            .background(OverlayScrollers())
        }
        .background {
            if showsBackdrop { GamePageBackdrop(game: model.game) }
        }
        // Structured, so navigating away actually cancels the Steam query
        // instead of leaving a detached logon running to completion.
        .task(id: model.appID) { await model.loadDLC(force: false) }
        .task(id: model.patchStatusProbeID) { await model.refreshPatchStatus() }
        .task(id: sizeProbeID) {
            if sizeProbeID != nil { await model.measureInstalledSize() }
        }
        // Plugging a drive in or pulling it out updates any open sheet's list.
        .onChange(of: model.drives.drives) { model.drivesChanged() }
        // A link waiting when the page opens counts too. Handled on the next
        // turn of the run loop, not mid-update.
        .onChange(of: GameLinkRouter.shared.pendingLaunchAppID, initial: true) { _, appID in
            Task {
                guard appID == model.appID else { return }
                GameLinkRouter.shared.pendingLaunchAppID = nil
                model.launchFromShortcut()
            }
        }
        .onChange(of: GameLinkRouter.shared.pendingResumeID, initial: true) { _, id in
            Task { model.resumeIfRequested(id) }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Label("Library", systemImage: "chevron.backward")
                }
            }
        }
    }

    // Bindings are typed here, not inline in `body`, and the page is split
    // from what it presents: as one chain, CI's compiler gave up type-checking it.

    /// SwiftUI writes nil when a sheet closes itself or Esc closes it.
    private var sheetBinding: Binding<GameDetailSheet?> {
        Binding(get: { model.sheet }, set: { if $0 == nil { model.sheetClosed() } })
    }

    private var confirmationTitleText: String {
        guard let dialog = model.dialog else { return "" }
        return confirmationTitle(dialog)
    }

    /// Every dialog but the disk-space one, which is an alert.
    private var isShowingConfirmation: Binding<Bool> {
        Binding(
            get: { model.dialog != nil && model.dialog?.shortfall == nil },
            set: { if !$0, model.dialog?.shortfall == nil { model.dialog = nil } }
        )
    }

    private var isShowingShortfall: Binding<Bool> {
        Binding(
            get: { model.dialog?.shortfall != nil },
            set: { if !$0, model.dialog?.shortfall != nil { model.dialog = nil } }
        )
    }

    @ViewBuilder
    private func sheetContent(_ sheet: GameDetailSheet) -> some View {
        switch sheet {
        case .artwork:
            CustomArtworkSheet(
                game: model.game,
                error: model.artworkError,
                onChoose: { model.chooseArtwork($0, for: $1) },
                onReset: { model.resetArtwork($0) },
                onDone: { model.sheet = nil }
            )
        case .cloudConnect:
            SteamCloudQRSheet(onConnected: model.cloudDidConnect)
        case .install:
            InstallSheet(
                game: model.game,
                size: model.installSize?.leavingOut(model.skippedDLC),
                skippedDLC: model.skippedDLC,
                onSetDLC: { model.setDLC($0, included: $1) },
                report: model.installSpaceReport,
                options: model.installOptions,
                // A closure, not `set: model.selectInstallTarget`: Swift 6.3
                // crashes generating the wrapper for that method reference.
                selection: Binding(get: { model.installTarget }, set: { model.selectInstallTarget($0) }),
                note: model.installNote,
                onInstall: model.confirmInstall,
                onCancel: { model.sheet = nil }
            )
        case .move:
            if let bottle = model.installedBottle {
                MoveGameSheet(bottle: bottle, model: model)
            }
        case .shortcutIcon:
            ShortcutIconSheet(
                game: model.game,
                account: model.isSteamConnected ? model.cloudAuth.account : nil,
                rememberClientIcon: { model.library.setClientIconURL($0, appID: model.appID) },
                onSave: model.shortcutIconSaved,
                onCancel: { model.sheet = nil }
            )
        case .saveBackups:
            if let bottle = model.installedBottle {
                SaveBackupsSheet(bottle: bottle, model: model)
            }
        case .restoreConflict(let prompt):
            RestoreConflictSheet(
                prompt: prompt,
                onKeepRestored: { model.resolveRestoreConflict(prompt, keepRestored: true) },
                onUseCloud: { model.resolveRestoreConflict(prompt, keepRestored: false) },
                onCancel: { model.sheet = nil }
            )
        case .dlcManager:
            if let bottle = model.installedBottle, let installDir = bottle.resolvedInstallDirectory {
                DLCManagerView(
                    game: model.game,
                    bottle: bottle,
                    installDir: installDir,
                    emulatorApplied: model.cachedPatchStatus == .applied,
                    dependencies: model.dependencies,
                    onDone: {
                        model.sheet = nil
                        // The manager may have written configs.app.ini, so the
                        // emulator row's on-disk probe is now stale.
                        model.patchProbeTick &+= 1
                    }
                )
            }
        }
    }

    private func confirmationTitle(_ dialog: GameDetailDialog) -> String {
        switch dialog {
        case .updateBeforePlay: GameUpdateStrings.beforePlayTitle(model.game.name)
        case .removeNonSteamGame: "Remove \(model.game.name)?"
        case .removeWithDriveMissing: InstallDriveStrings.removeWhileMissingTitle(model.game.name)
        case .clearLocalSaves: "Back up and clear local saves?"
        case .diskSpaceShortfall: ""
        }
    }

    @ViewBuilder
    private func confirmationActions(_ dialog: GameDetailDialog) -> some View {
        switch dialog {
        case .updateBeforePlay:
            Button(GameUpdateStrings.updateFirst, action: model.updateInsteadOfPlaying)
            Button(GameUpdateStrings.playAnyway, action: model.playWithoutUpdating)
            Button(GameUpdateStrings.cancel, role: .cancel) {}
        case .removeNonSteamGame:
            Button("Remove Game", role: .destructive, action: model.uninstall)
            Button("Cancel", role: .cancel) {}
        case .removeWithDriveMissing:
            Button(InstallDriveStrings.removeButton, role: .destructive, action: model.uninstall)
            Button(InstallDriveStrings.cancelButton, role: .cancel) {}
        case .clearLocalSaves(let bottle):
            Button("Back up & clear", role: .destructive) {
                model.clearLocalSaves(for: bottle)
                model.dialog = nil
            }
            Button("Cancel", role: .cancel) { model.dialog = nil }
        case .diskSpaceShortfall:
            EmptyView()
        }
    }

    @ViewBuilder
    private func confirmationMessage(_ dialog: GameDetailDialog) -> some View {
        switch dialog {
        case .updateBeforePlay:
            Text(GameUpdateStrings.beforePlayMessage)
        case .removeNonSteamGame:
            Text("The game's folder in BEER is deleted, on this Mac or on its drive. If you moved it in, this is the only copy; if you copied it, your original is untouched.")
        case .removeWithDriveMissing:
            Text(InstallDriveStrings.removeWhileMissingMessage(model.installLocation?.missingDriveName ?? ""))
        case .clearLocalSaves:
            Text("Your current local saves for this game are copied to a timestamped backup, then removed from the bottle. Nothing is uploaded or deleted from Steam Cloud. You can restore by pulling from cloud, or from the backup folder.")
        case .diskSpaceShortfall:
            EmptyView()
        }
    }
}
