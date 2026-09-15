import AppKit
import SwiftUI

struct GameDetailView: View {
    let game: SteamLibraryGame
    let onBack: () -> Void

    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var bottles: BottleStore
    @EnvironmentObject private var detector: ToolchainDetector
    @EnvironmentObject private var depotCtl: DepotDownloaderController
    @EnvironmentObject private var downloads: DownloadsStore
    @EnvironmentObject private var goldberg: GoldbergInstaller
    @EnvironmentObject private var cloudAuth: SteamAuthStore
    @EnvironmentObject private var cloudSync: CloudSyncEngine
    @EnvironmentObject private var graphicsTranslator: GraphicsTranslatorInstaller
    @EnvironmentObject private var dlcStore: DLCStore
    @State private var isShowingCloudConnect: Bool = false
    @State private var isShowingDLCManager: Bool = false
    @State private var shouldResumeInstallAfterCloudConnect: Bool = false
    @State private var cloudSyncMessage: String?
    @State private var cloudSyncIsError: Bool = false
    @State private var confirmClearBottle: Bottle?
    @State private var patchStatusMessage: String?
    @State private var patchStatusIsError: Bool = false
    @State private var isPatching: Bool = false
    @State private var isAdvancedExpanded: Bool = false
    /// Bumped after every Apply/Restore so the patch-status row re-reads
    /// the install dir from disk.
    @State private var patchProbeTick: Int = 0
    /// Cached result of the install-directory probe. `patchStatus(at:)` walks
    /// the game's whole install tree, so it must never run from `body` — every
    /// published change anywhere (a download progress tick, say) would re-walk
    /// it. Refreshed only when the tick changes or the bottle does.
    @State private var cachedPatchStatus: PatchStatus?
    /// Synchronous re-entry guard for the Install button. Prevents the
    /// 20-second wineboot phase from being kicked off multiple times if the
    /// user clicks Install rapidly.
    @State private var isStartingInstall: Bool = false

    private var installedBottle: Bottle? {
        guard let id = game.installedBottleID else { return nil }
        return bottles.bottles.first { $0.id == id }
    }

    private var download: DownloadsStore.Entry? {
        downloads.entry(for: game.appID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                hero
                if let download, download.isActive {
                    Divider()
                    downloadProgressView(download)
                }
                if installedBottle != nil {
                    Divider()
                    installedDetails
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Structured, so navigating away actually cancels the Steam query
        // instead of leaving a detached logon running to completion.
        .task(id: game.appID) { await loadDLC(force: false) }
        .task(id: patchStatusProbeID) { await refreshPatchStatus() }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Label("Library", systemImage: "chevron.backward")
                }
            }
        }
        .sheet(isPresented: $isShowingCloudConnect) {
            SteamCloudQRSheet(onConnected: {
                cloudSyncMessage = "Connected to Steam Cloud as \(cloudAuth.account?.accountName ?? "?")."
                cloudSyncIsError = false
                if shouldResumeInstallAfterCloudConnect {
                    shouldResumeInstallAfterCloudConnect = false
                    startInstall()
                }
            })
        }
        .sheet(isPresented: $isShowingDLCManager) {
            if let bottle = installedBottle, let installDir = resolvedInstallDirectory(for: bottle) {
                DLCManagerView(
                    game: game,
                    bottle: bottle,
                    installDir: installDir,
                    emulatorApplied: cachedPatchStatus == .applied,
                    onDone: {
                        isShowingDLCManager = false
                        // The manager may have written configs.app.ini, so the
                        // emulator row's on-disk probe is now stale.
                        patchProbeTick &+= 1
                    }
                )
            }
        }
        .confirmationDialog(
            "Back up and clear local saves?",
            isPresented: Binding(get: { confirmClearBottle != nil }, set: { if !$0 { confirmClearBottle = nil } }),
            presenting: confirmClearBottle
        ) { bottle in
            Button("Back up & clear", role: .destructive) {
                clearLocalSaves(for: bottle)
                confirmClearBottle = nil
            }
            Button("Cancel", role: .cancel) { confirmClearBottle = nil }
        } message: { _ in
            Text("Your current local saves for this game are copied to a timestamped backup, then removed from the bottle. Nothing is uploaded or deleted from Steam Cloud. You can restore by pulling from cloud, or from the backup folder.")
        }
    }

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            SteamHeroArtwork(game: game)

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0.28),
                    .init(color: .black.opacity(0.34), location: 0.55),
                    .init(color: .black.opacity(0.88), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [.black.opacity(0.38), .clear],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 10) {
                SteamLibraryLogo(game: game)
                    .frame(maxWidth: 420, maxHeight: 150, alignment: .leading)

                HStack(spacing: 12) {
                    Label("appID \(game.appID)", systemImage: "number")
                    if installedBottle != nil {
                        Label("Installed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("Not installed", systemImage: "circle.dashed")
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }
                .font(.callout)
                .foregroundStyle(.white.opacity(0.78))

                actionRow
            }
            .padding(26)
            .environment(\.colorScheme, .dark)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(1920.0 / 620.0, contentMode: .fit)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(.white.opacity(0.10), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
    }

    private var actionRow: some View {
        HStack(spacing: 12) {
            if let bottle = installedBottle, bottle.gameLaunchExecutable != nil {
                Button(action: { launch(bottle) }) {
                    Label("Play", systemImage: "play.fill")
                        .font(.title3.bold())
                        .frame(minWidth: 180, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(bottles.activeBottleIDs.contains(bottle.id))

                Menu {
                    Button(action: { bottles.reveal(bottle) }) {
                        Label("Reveal Files", systemImage: "folder")
                    }
                    Divider()
                    Button("Reinstall / Validate", action: startInstallOrLogin)
                    Button("Uninstall", role: .destructive, action: uninstall)
                } label: {
                    Label("More", systemImage: "ellipsis")
                }
                .menuStyle(.borderedButton)
                .controlSize(.large)
                .fixedSize()
            } else if let entry = download, entry.isActive {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(entry.phaseText)
                }
                .frame(minWidth: 180, minHeight: 36)
                .padding(.horizontal, 12)
                .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))

                Button(role: .destructive) {
                    cancelInstall(reason: "Cancelled.")
                } label: {
                    Label("Cancel", systemImage: "xmark.circle")
                }
                .controlSize(.large)
            } else {
                Button(action: startInstallOrLogin) {
                    if isStartingInstall {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Starting…")
                        }
                        .frame(minWidth: 180, minHeight: 36)
                    } else {
                        Label(installedBottle == nil ? "Install" : "Resume / Reinstall", systemImage: "arrow.down.circle.fill")
                            .font(.title3.bold())
                            .frame(minWidth: 180, minHeight: 36)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(detector.candidates.isEmpty || isStartingInstall)

                if installedBottle != nil {
                    Button(role: .destructive, action: uninstall) {
                        Label("Uninstall", systemImage: "trash")
                    }
                    .controlSize(.large)
                }

                if detector.candidates.isEmpty {
                    Text("No Wine runtime available. Open Runtime Manager in the sidebar.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    @ViewBuilder
    private func downloadProgressView(_ entry: DownloadsStore.Entry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.phaseText).font(.callout.bold())
                Spacer()
                Text(formatPercent(entry.fraction)).font(.callout.monospacedDigit())
            }
            ProgressView(value: entry.fraction)
                .progressViewStyle(.linear)
            if let downloaded = entry.downloadedBytes, let total = entry.totalBytes, total > 0 {
                Text("\(formatBytes(downloaded)) / \(formatBytes(total))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if !entry.logTail.isEmpty {
                DisclosureGroup("DepotDownloader output") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(entry.logTail.enumerated()), id: \.0) { _, line in
                                Text(line)
                                    .font(.system(.caption2, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(8)
                    }
                    .frame(maxHeight: 160)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private var installedDetails: some View {
        if let bottle = installedBottle {
            VStack(alignment: .leading, spacing: 10) {
                Text("Game Settings").font(.headline)
                runtimeRow(bottle: bottle)
                graphicsRow(bottle: bottle)
                displayModeRow(bottle: bottle)
                gameLaunchArgumentsRow(bottle: bottle)
                steamEmulatorRow(bottle: bottle)
                dlcRow(bottle: bottle)
                steamCloudRow(bottle: bottle)

                DisclosureGroup(isExpanded: $isAdvancedExpanded) {
                    advancedSettings(bottle: bottle)
                        .padding(.top, 10)
                } label: {
                    Label("Advanced", systemImage: "gearshape.2")
                        .font(.headline)
                }
                .padding(.top, 6)

                Text("Changing the runtime swaps the Wine build this game runs on. Install additional Wine or GPTK versions from Runtime Manager in the sidebar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func advancedSettings(bottle: Bottle) -> some View {
        let bottleID = bottle.id
        let liveBottle = bottles.bottles.first(where: { $0.id == bottleID }) ?? bottle
        let isBusy = bottles.activeBottleIDs.contains(bottleID)
        let logEntries = bottles.logs[bottleID] ?? []

        VStack(alignment: .leading, spacing: 12) {
            SettingsRow(title: "Windows version") {
                TextField("win10", text: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.windowsVersion
                            ?? liveBottle.windowsVersion
                    },
                    set: { newValue in
                        bottles.scheduleMutation(bottleID: bottleID) { $0.windowsVersion = newValue }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                Spacer()
            }

            SettingsRow(title: "Notes", alignment: .top) {
                TextField("Compatibility notes", text: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.notes
                            ?? liveBottle.notes
                    },
                    set: { newValue in
                        bottles.scheduleMutation(bottleID: bottleID) { $0.notes = newValue }
                    }
                ), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .frame(maxWidth: 520)
                Spacer()
            }

            Divider()

            if let exe = liveBottle.gameLaunchExecutable {
                LabeledValue(key: "Launch executable", value: exe)
            }
            if let installDir = resolvedInstallDirectory(for: liveBottle) {
                LabeledValue(key: "Install location", value: installDir.path)
            }
            LabeledValue(key: "Bottle path", value: AppPaths.prefixURL(for: liveBottle).path)
            LabeledValue(key: "Runtime path", value: liveBottle.runtimeLocationPath)

            HStack(spacing: 10) {
                Button {
                    Task { await bottles.initializeBottle(liveBottle) }
                } label: {
                    Label("Repair Prefix", systemImage: "wrench.adjustable")
                }
                .disabled(isBusy)

                Button {
                    Task { await bottles.stopBottleProcesses(liveBottle) }
                } label: {
                    Label("Stop Processes", systemImage: "stop.fill")
                }

                Button {
                    bottles.reveal(liveBottle)
                } label: {
                    Label("Reveal Bottle", systemImage: "folder")
                }

                Button {
                    bottles.copyLogToClipboard(liveBottle)
                } label: {
                    Label("Copy Log", systemImage: "doc.on.doc")
                }

                Button {
                    bottles.revealLog(liveBottle)
                } label: {
                    Label("Reveal Log", systemImage: "doc.text.magnifyingglass")
                }
            }
            .controlSize(.small)

            Text("Repair reinitializes the Wine prefix without reinstalling the game. Stop ends processes running inside this bottle.")
                .font(.caption)
                .foregroundStyle(.secondary)

            DisclosureGroup("Wine log") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(logEntries) { entry in
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(entry.isError ? .red : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(10)
                }
                .frame(minHeight: 120, maxHeight: 240)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if logEntries.isEmpty {
                        Text("No log output yet.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 6)
            }
            .font(.callout)
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func runtimeRow(bottle: Bottle) -> some View {
        let bottleID = bottle.id
        SettingsRow(title: "Runtime") {

            if detector.candidates.isEmpty {
                Text(bottle.runtimeLabel).font(.callout)
            } else {
                Picker("Runtime", selection: Binding(
                    get: { bottles.bottles.first(where: { $0.id == bottleID })?.runtimeLocationPath ?? bottle.runtimeLocationPath },
                    set: { newID in
                        guard let runtime = detector.candidates.first(where: { $0.id == newID }) else { return }
                        bottles.scheduleMutation(bottleID: bottleID) { $0.useRuntime(runtime) }
                    }
                )) {
                    ForEach(detector.candidates) { rt in
                        Text(rt.displayName).tag(rt.id)
                    }
                }
                .labelsHidden().pickerStyle(.menu).fixedSize()
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func graphicsRow(bottle: Bottle) -> some View {
        let bottleID = bottle.id
        SettingsRow(title: "Graphics") {
            Picker("Graphics", selection: Binding(
                get: { bottles.bottles.first(where: { $0.id == bottleID })?.effectiveGraphicsBackend ?? bottle.effectiveGraphicsBackend },
                set: { newValue in bottles.scheduleMutation(bottleID: bottleID) { $0.graphicsBackend = newValue } }
            )) {
                ForEach(bottle.availableGraphicsBackends) { Text($0.label).tag($0) }
            }
            .labelsHidden().pickerStyle(.menu).fixedSize()
            if graphicsTranslator.busy != nil {
                ProgressView().controlSize(.small)
            }
            Spacer()
        }
    }

    @ViewBuilder
    private func displayModeRow(bottle: Bottle) -> some View {
        let bottleID = bottle.id
        let liveBottle = bottles.bottles.first(where: { $0.id == bottleID }) ?? bottle
        let resolutionMode = liveBottle.effectiveDisplayResolutionMode

        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(title: "Resolution") {

                Picker("Resolution", selection: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.effectiveDisplayResolutionMode ?? resolutionMode
                    },
                    set: { newValue in
                        bottles.scheduleMutation(bottleID: bottleID) { $0.displayResolutionMode = newValue }
                    }
                )) {
                    ForEach(DisplayResolutionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .fixedSize()
                .frame(width: 240, alignment: .leading)

                Spacer()
            }

            Text(resolutionMode == .highResolution
                ? "Exposes Retina resolutions to the game (up to twice the width and height) and treats it as DPI-aware. Sharper, but substantially more demanding; some games may not handle high-DPI mode correctly."
                : "Uses macOS point dimensions for better performance and compatibility. On Retina displays this limits games to half the high-resolution width and height.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func gameLaunchArgumentsRow(bottle: Bottle) -> some View {
        let bottleID = bottle.id

        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(title: "Launch arguments") {

                TextField("Optional game arguments", text: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.effectiveGameLaunchArguments
                            ?? bottle.effectiveGameLaunchArguments
                    },
                    set: { newValue in
                        bottles.scheduleMutation(bottleID: bottleID) { $0.gameLaunchArguments = newValue }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 520)

                Spacer()
            }

            Text("Passed directly to the game executable. For Unity games, for example: -screen-width 3024 -screen-height 1964 -screen-fullscreen 0")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func steamEmulatorRow(bottle: Bottle) -> some View {
        SettingsRow(title: "Steam emulator") {

            HStack(spacing: 8) {
                switch cachedPatchStatus {
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

                if isPatching {
                    ProgressView().controlSize(.small)
                }
            }

            Spacer()

            switch cachedPatchStatus {
            case .notApplied:
                Button {
                    applyGoldbergPatch(to: bottle)
                } label: {
                    Label("Apply", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isPatching)
            case .applied:
                Menu {
                    Button {
                        applyGoldbergPatch(to: bottle)
                    } label: {
                        Label("Reapply (after GBE_Fork upgrade)", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive) {
                        restoreOriginalDLLs(for: bottle)
                    } label: {
                        Label("Restore original Steam DLLs", systemImage: "arrow.uturn.backward")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(isPatching)
            case nil, .noDLLsFound, .installDirMissing:
                EmptyView()
            }
        }

        if let message = patchStatusMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(patchStatusIsError ? .red : .green)
                .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - DLC row

    /// Collapses away once we know the account owns no DLC for this game.
    /// The lookup is kicked off from `body` — see `loadDLC`.
    private enum DLCRowState {
        case installed(owned: Int, installed: Int)
        case loading
        case failed
        case unchecked
    }

    private func dlcRowState(bottle: Bottle) -> DLCRowState? {
        if let owned = dlcStore.ownedCount(for: game.appID) {
            guard owned > 0 else { return nil }   // owns none — hide the row
            return .installed(owned: owned, installed: bottle.effectiveInstalledDLC.count)
        }
        switch dlcStore.state(for: game.appID) {
        case .loading: return .loading
        case .failed: return .failed
        case .idle, .loaded:
            // Not looked yet. Offer the check rather than rendering nothing —
            // a silent empty row is how a broken lookup hid the first time.
            return isSteamConnected ? .unchecked : nil
        }
    }

    private var isSteamConnected: Bool {
        cloudAuth.account != nil && !cloudAuth.sessionExpired
    }

    @ViewBuilder
    private func dlcRow(bottle: Bottle) -> some View {
        if let state = dlcRowState(bottle: bottle) {
            SettingsRow(title: "DLC") {
                switch state {
                case .installed(let owned, let installed):
                    if installed >= owned {
                        Label("All \(owned) installed", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                            .font(.callout)
                    } else {
                        Label("\(installed) of \(owned) installed", systemImage: "shippingbox.fill")
                            .foregroundStyle(installed == 0 ? .orange : .primary)
                            .font(.callout)
                    }
                    Spacer()
                    Button("Manage…") { isShowingDLCManager = true }
                        .controlSize(.small)

                case .loading:
                    ProgressView().controlSize(.small)
                    Text("Checking your Steam licences…")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                case .failed:
                    Label("Couldn't check for DLC", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.callout)
                    Spacer()
                    Button("Retry") { reloadDLC() }
                        .controlSize(.small)

                case .unchecked:
                    Text("Not checked yet")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Check for DLC") { reloadDLC() }
                        .controlSize(.small)
                }
            }
        }
    }

    /// Discovery costs a Steam logon, so this runs once per game per session
    /// (DLCStore caches and coalesces) and only for installed games.
    private func loadDLC(force: Bool) async {
        guard isSteamConnected, let auth = cloudAuth.account else { return }
        guard installedBottle != nil else { return }
        await dlcStore.load(appID: game.appID, auth: auth, force: force)
    }

    private func reloadDLC() {
        Task { await loadDLC(force: true) }
    }

    // MARK: - Steam Cloud row

    @ViewBuilder
    private func steamCloudRow(bottle: Bottle) -> some View {
        let connected = cloudAuth.account != nil
        let expired = cloudAuth.sessionExpired

        VStack(alignment: .leading, spacing: 6) {
            SettingsRow(title: "Steam Cloud") {

                if connected && expired {
                    Label("Sign-in expired", systemImage: "exclamationmark.icloud")
                        .foregroundStyle(.orange)
                        .font(.callout)
                } else if connected {
                    Label(cloudAuth.account?.accountName ?? "Connected", systemImage: "checkmark.icloud.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                } else {
                    Label("Not connected", systemImage: "icloud.slash")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }

                if cloudSync.isSyncing {
                    ProgressView().controlSize(.small)
                }

                Spacer()

                if !connected || expired {
                    Button {
                        cloudSyncMessage = nil
                        isShowingCloudConnect = true
                    } label: {
                        Label(expired ? "Reconnect" : "Connect", systemImage: "icloud")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    if expired {
                        Button(role: .destructive) {
                            cloudAuth.signOut()
                            cloudSyncMessage = "Disconnected from Steam Cloud."
                            cloudSyncIsError = false
                        } label: {
                            Label("Sign Out", systemImage: "icloud.slash")
                        }
                        .controlSize(.small)
                    }
                } else {
                    Button {
                        syncSaves(for: bottle, pull: true, push: true)
                    } label: {
                        Label("Sync now", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(cloudSync.isSyncing)

                    Menu {
                        Button {
                            syncSaves(for: bottle, pull: true, push: false)
                        } label: {
                            Label("Pull from cloud", systemImage: "icloud.and.arrow.down")
                        }
                        Button {
                            syncSaves(for: bottle, pull: false, push: true)
                        } label: {
                            Label("Push to cloud", systemImage: "icloud.and.arrow.up")
                        }
                        Divider()
                        Button(role: .destructive) {
                            confirmClearBottle = bottle
                        } label: {
                            Label("Back up & clear local saves…", systemImage: "trash")
                        }
                        Divider()
                        Button(role: .destructive) {
                            cloudAuth.signOut()
                            cloudSyncMessage = "Disconnected from Steam Cloud."
                            cloudSyncIsError = false
                        } label: {
                            Label("Sign Out", systemImage: "icloud.slash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(cloudSync.isSyncing)
                }
            }

            if cloudSync.isSyncing && !cloudSync.phase.isEmpty {
                Text(cloudSync.phase)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let message = cloudSyncMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(cloudSyncIsError ? .red : .green)
                    .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                    .fixedSize(horizontal: false, vertical: true)
            } else if connected && expired {
                Text("Your Steam sign-in expired or was revoked. Click Reconnect to resume syncing — your local saves and backups are untouched.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                    .fixedSize(horizontal: false, vertical: true)
            } else if connected, let last = cloudSync.lastSyncAt {
                Text("Last synced \(last.formatted(.relative(presentation: .named))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, SettingsRow<EmptyView>.captionIndent)
            } else if connected {
                Text("Saves sync both ways with Steam Cloud, so you can move between your PC and this Mac. Every sync backs up your local saves first — nothing is overwritten without a recoverable copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, SettingsRow<EmptyView>.captionIndent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Pull and/or push saves. `syncSaves(pull:true, push:true)` is the default
    /// two-way sync; the menu offers one-direction variants.
    private func syncSaves(for bottle: Bottle, pull: Bool, push: Bool) {
        Task {
            cloudSyncMessage = nil
            do {
                let report: CloudSyncReport
                if pull && push {
                    report = try await cloudSync.sync(bottle: bottle, appID: game.appID, auth: cloudAuth)
                } else if push {
                    report = try await cloudSync.push(bottle: bottle, appID: game.appID, auth: cloudAuth)
                } else {
                    report = try await cloudSync.pull(bottle: bottle, appID: game.appID, auth: cloudAuth)
                }
                cloudSyncIsError = !report.failures.isEmpty
                var parts: [String] = []
                if pull { parts.append("\(report.downloaded) pulled") }
                if push { parts.append("\(report.uploaded) pushed") }
                parts.append("\(report.skipped) up-to-date")
                if !report.failures.isEmpty { parts.append("\(report.failures.count) failed") }
                cloudSyncMessage = parts.joined(separator: ", ") + "."
            } catch CloudSyncClientError.authExpired {
                // Token went stale — flag it and pop the QR reconnect right away,
                // since the user explicitly asked to sync.
                cloudAuth.sessionExpired = true
                cloudSyncIsError = true
                cloudSyncMessage = "Steam sign-in expired — reconnect to finish syncing."
                isShowingCloudConnect = true
            } catch let err as SteamAuthError {
                cloudSyncIsError = true
                cloudSyncMessage = err.errorDescription
            } catch let err as CloudSyncClientError {
                cloudSyncIsError = true
                cloudSyncMessage = err.errorDescription
            } catch let err as CloudSyncError {
                cloudSyncIsError = true
                cloudSyncMessage = err.errorDescription
            } catch {
                cloudSyncIsError = true
                cloudSyncMessage = error.localizedDescription
            }
        }
    }

    private func clearLocalSaves(for bottle: Bottle) {
        Task {
            cloudSyncMessage = nil
            do {
                let backup = try await cloudSync.backupAndClearLocalSaves(bottle: bottle, appID: game.appID, auth: cloudAuth)
                cloudSyncIsError = false
                cloudSyncMessage = "Local saves cleared. Backed up to \(backup.lastPathComponent). Use “Pull from cloud” to restore from Steam."
            } catch {
                cloudAuth.noteCloudError(error)
                cloudSyncIsError = true
                cloudSyncMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    // MARK: - Install directory + patch status

    fileprivate enum PatchStatus: Equatable {
        case applied            // .original files present alongside stubs
        case notApplied         // steam_api*.dll present but no .original
        case noDLLsFound        // game doesn't use Steamworks
        case installDirMissing  // can't read install dir
    }

    /// Resolve the game's install directory. Bottles created after this change
    /// have it stored explicitly; older bottles (like the user's existing KCD)
    /// fall back to walking up from `gameLaunchExecutable` until we hit a
    /// directory whose parent is named "Games".
    private func resolvedInstallDirectory(for bottle: Bottle) -> URL? {
        if let stored = bottle.gameInstallDirectory {
            let url = URL(fileURLWithPath: stored)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        guard let exe = bottle.gameLaunchExecutable else { return nil }
        var current = URL(fileURLWithPath: exe).deletingLastPathComponent()
        // Walk up at most 12 levels looking for a directory whose parent is "Games".
        for _ in 0..<12 {
            if current.deletingLastPathComponent().lastPathComponent == "Games" {
                return current
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }   // hit /
            current = parent
        }
        return nil
    }

    /// Changes whenever the cached probe needs redoing: a different bottle, or
    /// an Apply/Restore/DLC write bumping the tick.
    private var patchStatusProbeID: String {
        "\(installedBottle?.id.uuidString ?? "none")-\(patchProbeTick)"
    }

    private func refreshPatchStatus() async {
        guard let bottle = installedBottle else {
            cachedPatchStatus = nil
            return
        }
        // Off the main actor: this walks the game's entire install tree.
        let probed = await Task.detached { [dir = resolvedInstallDirectory(for: bottle)] in
            GameDetailView.patchStatus(at: dir)
        }.value
        cachedPatchStatus = probed
    }

    nonisolated fileprivate static func patchStatus(at installDir: URL?) -> PatchStatus {
        guard let installDir,
              let enumerator = FileManager.default.enumerator(
                  at: installDir, includingPropertiesForKeys: nil,
                  options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else {
            return .installDirMissing
        }
        var anyDLL = false
        for case let url as URL in enumerator {
            switch url.lastPathComponent.lowercased() {
            case "steam_api.dll.original", "steam_api64.dll.original":
                return .applied          // terminal — no need to walk the rest
            case "steam_api.dll", "steam_api64.dll":
                anyDLL = true
            default:
                break
            }
        }
        return anyDLL ? .notApplied : .noDLLsFound
    }

    private func applyGoldbergPatch(to bottle: Bottle) {
        guard let installDir = resolvedInstallDirectory(for: bottle) else {
            patchStatusMessage = "Could not locate the game's install directory."
            patchStatusIsError = true
            return
        }
        isPatching = true
        patchStatusMessage = nil
        Task {
            defer { isPatching = false }
            if !goldberg.isInstalled {
                await goldberg.install()
            }
            guard goldberg.isInstalled else {
                patchStatusMessage = goldberg.lastError ?? "Could not install the Steam emulator."
                patchStatusIsError = true
                return
            }
            do {
                let report = try GoldbergApplicator.apply(
                    installDir: installDir,
                    appID: game.appID,
                    account: cloudAuth.account?.accountName,
                    steamID64: cloudAuth.account?.steamID64,
                    // Re-declare the enabled DLC; a bare reapply would
                    // otherwise drop the [app::dlcs] block and the game would
                    // stop seeing DLC it already has on disk.
                    dlc: bottles.live(bottle).effectiveInstalledDLC,
                    using: goldberg
                )
                // Make sure the bottle has the install dir recorded for future ops.
                if bottle.gameInstallDirectory == nil {
                    var updated = bottle
                    updated.gameInstallDirectory = installDir.path
                    await bottles.update(updated)
                }
                let total = report.patched.count + report.alreadyPatched
                patchStatusMessage = "Steam emulator applied to \(total) DLL\(total == 1 ? "" : "s")."
                patchStatusIsError = false
            } catch {
                patchStatusMessage = error.localizedDescription
                patchStatusIsError = true
            }
            patchProbeTick &+= 1
        }
    }

    private func restoreOriginalDLLs(for bottle: Bottle) {
        guard let installDir = resolvedInstallDirectory(for: bottle) else {
            patchStatusMessage = "Could not locate the game's install directory."
            patchStatusIsError = true
            return
        }
        do {
            let n = try GoldbergApplicator.restore(installDir: installDir)
            patchStatusMessage = n > 0
                ? "Restored \(n) original DLL\(n == 1 ? "" : "s")."
                : "No backed-up originals to restore."
            patchStatusIsError = false
        } catch {
            patchStatusMessage = error.localizedDescription
            patchStatusIsError = true
        }
        patchProbeTick &+= 1
    }

    // MARK: - Actions

    private func startInstallOrLogin() {
        startInstall()
    }

    /// New game bottles default to GPTK (fastest, D3DMetal). Managed GPTK
    /// runtimes are named "Managed GPTK-…" but resolve to a wine64 executable
    /// (kind .systemWine), so match by name as well as kind. Falls back to the
    /// first available runtime.
    private var preferredDefaultRuntime: RuntimeCandidate? {
        let c = detector.candidates
        return c.first { $0.displayName.localizedCaseInsensitiveContains("GPTK") || $0.displayName.localizedCaseInsensitiveContains("Game Porting") }
            ?? c.first { $0.kind == .gamePortingToolkit }
            ?? c.first
    }

    private func startInstall() {
        // Synchronous re-entry guard: a second click while the first is
        // still doing wineboot must be a no-op, not a fresh bottle.
        guard !isStartingInstall else { return }
        guard let runtime = preferredDefaultRuntime else { return }
        guard let steamAccount = cloudAuth.account, !cloudAuth.sessionExpired else {
            shouldResumeInstallAfterCloudConnect = true
            isShowingCloudConnect = true
            return
        }
        isStartingInstall = true

        Task { @MainActor in
            defer { isStartingInstall = false }

            // Fire the Downloads entry FIRST so the UI shows something
            // immediately. The bottleID is patched in below.
            downloads.start(appID: game.appID, name: game.name, bottleID: UUID())
            downloads.setStatus(appID: game.appID, phase: "Initializing bottle…")

            // Resolve the bottle for this Steam appID:
            //   - Reuse any bottle already claimed for this appID (skips wineboot)
            //   - Otherwise create a fresh bottle + claim it immediately
            // After this point the bottle is tagged with steamAppID +
            // gameInstallStatus = .installing, so a future retry can find it.
            let bottle: Bottle
            if let existing = bottles.findBottle(forAppID: game.appID) {
                bottle = existing
                downloads.append(appID: game.appID, log: "Reusing existing bottle for this game (skipping wineboot).")
                // Defensive: clean up any other orphans for this appID.
                await bottles.cleanupOrphans(forAppID: game.appID, keep: existing.id)
            } else {
                let fresh = await bottles.createBottle(name: game.name, runtime: runtime, graphicsBackend: .automatic)
                await bottles.claimForSteamApp(fresh, appID: game.appID, gameName: game.name)
                bottle = fresh
            }
            let bottleID = bottle.id
            library.markInstalled(appID: game.appID, bottleID: bottleID)

            do {
                let result = try await depotCtl.installGame(
                    appID: game.appID,
                    gameName: game.name,
                    bottle: bottle,
                    auth: steamAccount,
                    events: downloads.consume(appID: game.appID)
                )

                // Apply the Steam emulator (GBE_Fork) so the game launches
                // without a running Steam process. Lazily install the
                // emulator on first use, then patch this game's install.
                downloads.setStatus(appID: game.appID, phase: "Installing Steam emulator…")
                if !goldberg.isInstalled {
                    await goldberg.install()
                }
                if goldberg.isInstalled {
                    downloads.setStatus(appID: game.appID, phase: "Patching with Steam emulator…")
                    do {
                        let report = try GoldbergApplicator.apply(
                            installDir: result.installDirectory,
                            appID: game.appID,
                            account: cloudAuth.account?.accountName,
                            steamID64: cloudAuth.account?.steamID64,
                            dlc: bottles.live(bottle).effectiveInstalledDLC,
                            using: goldberg
                        )
                        downloads.append(
                            appID: game.appID,
                            log: "Goldberg: patched \(report.patched.count) DLLs (already-patched: \(report.alreadyPatched), settings: \(report.settingsDirs.count))."
                        )
                    } catch {
                        // Patch failure isn't fatal — the user can still
                        // launch, just may need a Steam process. Surface as
                        // a warning in the log.
                        downloads.append(appID: game.appID, log: "Goldberg patch warning: \(error.localizedDescription)")
                    }
                } else if let err = goldberg.lastError {
                    downloads.append(appID: game.appID, log: "Goldberg installer warning: \(err)")
                }

                let launchExeHost = result.launchExecutableHostPath.path
                if let refreshed = bottles.bottles.first(where: { $0.id == bottleID }) {
                    await bottles.recordGameInstall(
                        refreshed,
                        appID: game.appID,
                        gameName: game.name,
                        launchExecutable: launchExeHost,
                        launchArguments: nil,
                        installDirectory: result.installDirectory.path
                    )
                }
                downloads.complete(appID: game.appID)
            } catch DepotDownloaderError.sessionExpired {
                cloudAuth.sessionExpired = true
                shouldResumeInstallAfterCloudConnect = true
                downloads.fail(appID: game.appID, reason: "Steam sign-in expired. Reconnect to resume the download.")
                isShowingCloudConnect = true
            } catch let err as DepotDownloaderError {
                downloads.fail(appID: game.appID, reason: err.errorDescription ?? "Install failed")
            } catch {
                downloads.fail(appID: game.appID, reason: error.localizedDescription)
            }
        }
    }

    private func cancelInstall(reason: String) {
        // We don't have process-kill plumbing yet; mark the UI state and
        // remove the bottle. The running DepotDownloader will eventually
        // exit on its own (it'll fail when its install dir disappears).
        downloads.fail(appID: game.appID, reason: reason)
        if let bottle = installedBottle {
            Task {
                await bottles.delete(bottle)
                library.markUninstalled(appID: game.appID)
                downloads.remove(appID: game.appID)
            }
        }
    }

    private func launch(_ bottle: Bottle) {
        guard let exe = bottle.gameLaunchExecutable else { return }
        Task {
            // Ensure the selected graphics translator (DXVK/DXMT) is downloaded
            // and its DLLs are in the prefix before launch. No-op for D3DMetal /
            // WineD3D / automatic.
            let backend = bottle.effectiveGraphicsBackend
            if GraphicsTranslator.from(backend) != nil {
                do {
                    try await graphicsTranslator.apply(backend, to: bottle)
                } catch {
                    cloudSyncIsError = true
                    cloudSyncMessage = "Couldn't set up \(backend.label): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)"
                    return
                }
            }
            // Auto cloud sync: pull the latest saves down before play, and push
            // whatever changed back up after the game exits. Best-effort — a
            // sync hiccup must never block launching the game. Backups are taken
            // inside the engine before anything is overwritten.
            // Only auto-sync if the session is actually usable. If it's already
            // flagged expired, skip silently and let the Cloud row's Reconnect
            // prompt handle it — don't nag mid-launch.
            let cloudUsable = cloudAuth.account != nil && !cloudAuth.sessionExpired
            if cloudUsable {
                cloudSyncMessage = nil
                do {
                    let r = try await cloudSync.pull(bottle: bottle, appID: game.appID, auth: cloudAuth)
                    cloudSyncIsError = !r.failures.isEmpty
                    cloudSyncMessage = "Pulled \(r.downloaded) save\(r.downloaded == 1 ? "" : "s") before launch."
                } catch CloudSyncClientError.authExpired {
                    cloudAuth.sessionExpired = true
                    cloudSyncIsError = true
                    cloudSyncMessage = "Steam sign-in expired — launching anyway. Reconnect from the Steam Cloud row to sync."
                } catch {
                    cloudSyncIsError = true
                    cloudSyncMessage = "Pre-launch cloud pull failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription). Launching anyway."
                }
            }

            await bottles.launchGameExecutable(
                bottle,
                executable: exe,
                arguments: bottle.effectiveGameLaunchArguments
            )

            // Re-check: the token may have expired during the pull above.
            if cloudAuth.account != nil && !cloudAuth.sessionExpired {
                do {
                    let r = try await cloudSync.push(bottle: bottle, appID: game.appID, auth: cloudAuth)
                    cloudSyncIsError = !r.failures.isEmpty
                    cloudSyncMessage = "Pushed \(r.uploaded) save\(r.uploaded == 1 ? "" : "s") to cloud after play."
                } catch CloudSyncClientError.authExpired {
                    cloudAuth.sessionExpired = true
                    cloudSyncIsError = true
                    cloudSyncMessage = "Steam sign-in expired before your saves could upload. Your progress is safe locally and backed up — reconnect, then Push to cloud."
                } catch {
                    cloudSyncIsError = true
                    cloudSyncMessage = "Post-play cloud push failed: \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription). Your saves are safe locally and backed up."
                }
            }
        }
    }

    private func uninstall() {
        guard let bottle = installedBottle else { return }
        Task {
            await bottles.delete(bottle)
            library.markUninstalled(appID: game.appID)
            downloads.remove(appID: game.appID)
        }
    }

    private func formatPercent(_ fraction: Double) -> String {
        String(format: "%.0f%%", fraction * 100)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct SteamHeroArtwork: View {
    let game: SteamLibraryGame

    var body: some View {
        AsyncImage(url: game.libraryHeroImage) { phase in
            switch phase {
            case .empty:
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay { ProgressView().controlSize(.small) }
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                fallbackArtwork
            @unknown default:
                fallbackArtwork
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var fallbackArtwork: some View {
        AsyncImage(url: game.headerImage) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
                    .blur(radius: 2)
            } else {
                Rectangle()
                    .fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            }
        }
    }
}

private struct SteamLibraryLogo: View {
    let game: SteamLibraryGame

    var body: some View {
        AsyncImage(url: game.libraryLogoImage) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFit()
                    .accessibilityLabel(game.name)
            } else {
                Text(game.name)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .shadow(color: .black.opacity(0.65), radius: 8, y: 2)
    }
}

/// A Game Settings row: fixed-width secondary label, then whatever control the
/// row needs. The label column's width lives here only — `SettingsRow.labelWidth`
/// is what the caption indent below a row is derived from, instead of the magic
/// 142 that used to be hardcoded at each site.
struct SettingsRow<Content: View>: View {
    static var labelWidth: CGFloat { 130 }
    static var spacing: CGFloat { 12 }
    /// Left inset that lines a caption up under the row's content.
    static var captionIndent: CGFloat { labelWidth + spacing }

    let title: String
    var alignment: VerticalAlignment = .firstTextBaseline
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: alignment, spacing: Self.spacing) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            content
        }
    }
}

private struct LabeledValue: View {
    let key: String
    let value: String

    var body: some View {
        SettingsRow(title: key) {
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
        }
    }
}

// MARK: - Downloads pane (stub)
