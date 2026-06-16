import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Root

// ContentView is just a router. Onboarding flows take over the entire window
// until the user has DepotDownloader installed and is signed in. After that, the
// main app shell (sidebar + content) takes over. Bottles are never shown to
// users on the primary path — they live behind the Compatibility sidebar
// item, for power users.
struct ContentView: View {
    @EnvironmentObject private var depot: DepotDownloaderInstaller
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var runtimeInstaller: RuntimeInstaller
    @EnvironmentObject private var cloudAuth: SteamAuthStore

    var body: some View {
        Group {
            if !depot.isInstalled {
                DepotDownloaderSetupView()
            } else if !library.account.isLoggedIn {
                // SteamSignInView surfaces library.lastError inline; don't alert.
                SteamSignInView()
            } else {
                MainShellView()
            }
        }
        // Modal alerts only for errors that aren't already shown inline
        // (i.e. after the user is signed in).
        .alert("BEER", isPresented: Binding(
            get: {
                library.account.isLoggedIn &&
                (store.lastError != nil || runtimeInstaller.lastError != nil ||
                 library.lastError != nil || depot.lastError != nil)
            },
            set: {
                if !$0 {
                    store.lastError = nil
                    runtimeInstaller.lastError = nil
                    library.lastError = nil
                    depot.lastError = nil
                }
            }
        )) {
            Button("OK", role: .cancel) {
                store.lastError = nil
                runtimeInstaller.lastError = nil
                library.lastError = nil
                depot.lastError = nil
            }
        } message: {
            Text(store.lastError ?? runtimeInstaller.lastError ?? library.lastError ?? depot.lastError ?? "")
        }
        .task {
            await runtimeInstaller.refresh()
            if library.account.isLoggedIn {
                await library.fetchLibrary(auth: cloudAuth)
            }
        }
    }
}

// MARK: - Main shell (after onboarding)

enum AppSidebarItem: String, Hashable, CaseIterable, Identifiable {
    case library
    case installed
    case downloads
    case compatibility

    var id: String { rawValue }

    var label: String {
        switch self {
        case .library: "Library"
        case .installed: "Installed"
        case .downloads: "Downloads"
        case .compatibility: "Compatibility"
        }
    }

    var systemImage: String {
        switch self {
        case .library: "rectangle.stack.fill"
        case .installed: "internaldrive.fill"
        case .downloads: "arrow.down.circle"
        case .compatibility: "wineglass"
        }
    }
}

struct MainShellView: View {
    @EnvironmentObject private var library: SteamLibraryStore
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var cloudAuth: SteamAuthStore
    @State private var sidebar: AppSidebarItem = .library
    @State private var selectedGameAppID: Int?

    var body: some View {
        NavigationSplitView {
            List(selection: $sidebar) {
                Section {
                    ForEach(AppSidebarItem.allCases) { item in
                        Label(item.label, systemImage: item.systemImage).tag(item)
                    }
                }
            }
            .navigationTitle("BEER")
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    HStack(spacing: 10) {
                        if let urlString = library.account.avatarURL, let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let image):
                                    image.resizable().aspectRatio(contentMode: .fill)
                                default:
                                    Image(systemName: "person.crop.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                        } else {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.title)
                                .foregroundStyle(.tint)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(library.account.username).font(.callout.bold()).lineLimit(1)
                            Text("\(library.games.count) games").font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Menu {
                            Button("Refresh Library") { Task { await library.fetchLibrary(auth: cloudAuth) } }
                            Button("Sign Out", role: .destructive) { library.signOut() }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                }
            }
            .frame(minWidth: 200)
        } detail: {
            switch sidebar {
            case .library:
                LibraryPane(selectedGameAppID: $selectedGameAppID)
            case .installed:
                LibraryPane(selectedGameAppID: $selectedGameAppID, installedOnly: true)
            case .downloads:
                DownloadsPane()
            case .compatibility:
                CompatibilityPane()
            }
        }
        // Switching tabs returns to that tab's grid rather than carrying a
        // selected game across (e.g. Library → Installed shouldn't show a detail).
        .onChange(of: sidebar) { _, _ in selectedGameAppID = nil }
    }
}

// MARK: - Library pane (grid + detail)

struct LibraryPane: View {
    @Binding var selectedGameAppID: Int?
    var installedOnly: Bool = false
    @EnvironmentObject private var library: SteamLibraryStore

    var body: some View {
        if let appID = selectedGameAppID,
           let game = library.games.first(where: { $0.appID == appID }) {
            GameDetailView(
                game: game,
                onBack: { selectedGameAppID = nil }
            )
        } else {
            SteamLibraryGridView(
                onSelectGame: { selectedGameAppID = $0.appID },
                installedOnly: installedOnly
            )
        }
    }
}

// MARK: - Game detail (Steam-style hero + actions)

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
    @State private var qrArt: String = ""
    @State private var isShowingQR: Bool = false
    @State private var isShowingCloudConnect: Bool = false
    @State private var cloudSyncMessage: String?
    @State private var cloudSyncIsError: Bool = false
    @State private var confirmClearBottle: Bottle?
    @State private var patchStatusMessage: String?
    @State private var patchStatusIsError: Bool = false
    @State private var isPatching: Bool = false
    /// Bumped after every Apply/Restore so the patch-status row re-reads
    /// the install dir from disk.
    @State private var patchProbeTick: Int = 0
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
                heroImage
                titleRow
                actionRow
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
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: onBack) {
                    Label("Library", systemImage: "chevron.backward")
                }
            }
        }
        .sheet(isPresented: $isShowingQR) {
            QRCodeSheet(
                asciiArt: qrArt,
                gameName: game.name,
                onCancel: { cancelInstall(reason: "Cancelled.") }
            )
            .interactiveDismissDisabled(true)
        }
        .sheet(isPresented: $isShowingCloudConnect) {
            SteamCloudQRSheet(onConnected: {
                cloudSyncMessage = "Connected to Steam Cloud as \(cloudAuth.account?.accountName ?? "?")."
                cloudSyncIsError = false
            })
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

    private var heroImage: some View {
        AsyncImage(url: game.headerImage) { phase in
            switch phase {
            case .empty:
                Rectangle().fill(Color.secondary.opacity(0.15))
            case .success(let image):
                image.resizable().aspectRatio(contentMode: .fill)
            case .failure:
                Rectangle().fill(Color.secondary.opacity(0.15))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
            @unknown default:
                Rectangle().fill(Color.secondary.opacity(0.15))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(game.name).font(.system(size: 36, weight: .bold))
            HStack(spacing: 12) {
                Label("appID \(game.appID)", systemImage: "number")
                if installedBottle != nil {
                    Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Label("Not installed", systemImage: "circle.dashed").foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
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

                Button(action: { bottles.reveal(bottle) }) {
                    Label("Reveal Files", systemImage: "folder")
                }
                .controlSize(.large)

                Menu {
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
                    Text("No Wine runtime available. Open Compatibility → Runtime Manager.")
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
                Text("Compatibility").font(.headline)
                runtimeRow(bottle: bottle)
                graphicsRow(bottle: bottle)
                if let exe = bottle.gameLaunchExecutable {
                    LabeledValue(key: "Launch executable", value: exe)
                }
                if let installDir = resolvedInstallDirectory(for: bottle) {
                    LabeledValue(key: "Install location", value: installDir.path)
                }
                LabeledValue(key: "Bottle path", value: AppPaths.prefixURL(for: bottle).path)

                displayModeRow(bottle: bottle)
                steamEmulatorRow(bottle: bottle)
                steamCloudRow(bottle: bottle)

                Text("Changing the runtime swaps the Wine build this game runs on — useful if a game crashes on GPTK (try a mainline-Wine runtime). For launch arguments and advanced tweaks, use the Compatibility tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func runtimeRow(bottle: Bottle) -> some View {
        let bottleID = bottle.id
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Runtime")
                .font(.callout).foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)

            if detector.candidates.isEmpty {
                Text(bottle.runtimeLabel).font(.callout)
            } else {
                Picker("Runtime", selection: Binding(
                    get: { bottles.bottles.first(where: { $0.id == bottleID })?.runtimeLocationPath ?? bottle.runtimeLocationPath },
                    set: { newID in
                        guard let runtime = detector.candidates.first(where: { $0.id == newID }) else { return }
                        bottles.mutate(bottleID: bottleID) { $0.useRuntime(runtime) }
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
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Graphics")
                .font(.callout).foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
            Picker("Graphics", selection: Binding(
                get: { bottles.bottles.first(where: { $0.id == bottleID })?.effectiveGraphicsBackend ?? bottle.effectiveGraphicsBackend },
                set: { newValue in bottles.mutate(bottleID: bottleID) { $0.graphicsBackend = newValue } }
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
        // Read live from the store on every render so the Toggle binding
        // reflects canonical state, not a snapshot at first call.
        let bottleID = bottle.id
        let liveBottle = bottles.bottles.first(where: { $0.id == bottleID }) ?? bottle
        let windowedOn = liveBottle.effectiveUseVirtualDesktop

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Display")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)

                Toggle("Keep my display resolution", isOn: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.effectiveUseVirtualDesktop ?? windowedOn
                    },
                    set: { newValue in
                        bottles.mutate(bottleID: bottleID) { $0.useVirtualDesktop = newValue }
                    }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)
                .fixedSize()

                Spacer()
            }

            Text(windowedOn
                ? "Fullscreen scales to your current display resolution instead of switching modes — avoids stretching on unusual Mac resolutions. Note: GPTK runs games borderless and controls the window itself, so there's no macOS title bar or green fullscreen button. Use the game's own Windowed video option if you want a smaller view."
                : "Lets the game take exclusive fullscreen and change your screen resolution (closer to a real PC, but may flicker the display and hide the menu bar).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 142)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func steamEmulatorRow(bottle: Bottle) -> some View {
        // Use patchProbeTick to force re-evaluation after Apply/Restore.
        let _ = patchProbeTick
        let status = currentPatchStatus(for: bottle)

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Steam emulator")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)

            HStack(spacing: 8) {
                switch status {
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

            switch status {
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
                    Label("Manage", systemImage: "ellipsis.circle")
                }
                .menuStyle(.borderedButton)
                .controlSize(.small)
                .fixedSize()
                .disabled(isPatching)
            case .noDLLsFound, .installDirMissing:
                EmptyView()
            }
        }

        if let message = patchStatusMessage {
            Text(message)
                .font(.caption)
                .foregroundStyle(patchStatusIsError ? .red : .green)
                .padding(.leading, 142)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Steam Cloud row

    @ViewBuilder
    private func steamCloudRow(bottle: Bottle) -> some View {
        let connected = cloudAuth.account != nil
        let expired = cloudAuth.sessionExpired

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Steam Cloud")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)

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
                    .padding(.leading, 142)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let message = cloudSyncMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(cloudSyncIsError ? .red : .green)
                    .padding(.leading, 142)
                    .fixedSize(horizontal: false, vertical: true)
            } else if connected && expired {
                Text("Your Steam sign-in expired or was revoked. Click Reconnect to resume syncing — your local saves and backups are untouched.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.leading, 142)
                    .fixedSize(horizontal: false, vertical: true)
            } else if connected, let last = cloudSync.lastSyncAt {
                Text("Last synced \(last.formatted(.relative(presentation: .named))).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 142)
            } else if connected {
                Text("Saves sync both ways with Steam Cloud, so you can move between your PC and this Mac. Every sync backs up your local saves first — nothing is overwritten without a recoverable copy.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 142)
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

    private enum PatchStatus {
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

    private func currentPatchStatus(for bottle: Bottle) -> PatchStatus {
        guard let installDir = resolvedInstallDirectory(for: bottle) else {
            return .installDirMissing
        }
        guard let enumerator = FileManager.default.enumerator(at: installDir, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return .installDirMissing
        }
        var anyOriginal = false
        var anyDLL = false
        for case let url as URL in enumerator {
            let name = url.lastPathComponent.lowercased()
            if name == "steam_api.dll.original" || name == "steam_api64.dll.original" {
                anyOriginal = true
            } else if name == "steam_api.dll" || name == "steam_api64.dll" {
                anyDLL = true
            }
        }
        if anyOriginal { return .applied }
        if anyDLL { return .notApplied }
        return .noDLLsFound
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
                    events: { event in
                        switch event {
                        case .log(let line):
                            downloads.append(appID: game.appID, log: line)
                        case .status(let phase):
                            downloads.setStatus(appID: game.appID, phase: phase)
                        case .qrCode(let ascii):
                            qrArt = ascii
                            isShowingQR = true
                        case .loggedIn:
                            isShowingQR = false
                            downloads.setStatus(appID: game.appID, phase: "Signed in. Preparing download…")
                        case .progress(let fraction):
                            downloads.setProgress(appID: game.appID, fraction: fraction,
                                                   downloaded: nil, total: nil)
                        case .downloadComplete:
                            downloads.setStatus(appID: game.appID, phase: "Finalizing…")
                        }
                    }
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
                isShowingQR = false
            } catch let err as DepotDownloaderError {
                downloads.fail(appID: game.appID, reason: err.errorDescription ?? "Install failed")
                isShowingQR = false
            } catch {
                downloads.fail(appID: game.appID, reason: error.localizedDescription)
                isShowingQR = false
            }
        }
    }

    private func cancelInstall(reason: String) {
        // We don't have process-kill plumbing yet; mark the UI state and
        // remove the bottle. The running DepotDownloader will eventually
        // exit on its own (it'll fail when its install dir disappears).
        isShowingQR = false
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

            await bottles.launchGameExecutable(bottle, executable: exe, arguments: nil)

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

// MARK: - QR sheet shown during first-time DepotDownloader auth

private struct QRCodeSheet: View {
    let asciiArt: String
    let gameName: String
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(alignment: .center, spacing: 6) {
                Image(systemName: "qrcode")
                    .font(.title)
                    .foregroundStyle(.tint)
                Text("Sign in with Steam Mobile")
                    .font(.title2.bold())
                Text("Open the Steam Mobile App, tap the QR icon at the top, scan this code, then tap **Approve**.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 380)
            }

            QRBitmapView(asciiArt: asciiArt)
                .frame(width: 280, height: 280)
                .padding(16)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(spacing: 4) {
                Text("Installing **\(gameName)**")
                    .font(.callout)
                Text("Session is cached after approval — future installs skip the QR step.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 380)

            HStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Waiting for approval…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive, action: onCancel) {
                    Text("Cancel")
                }
            }
            .frame(maxWidth: 380)
        }
        .padding(28)
        .frame(width: 440)
    }
}

// Renders DepotDownloader's ASCII QR as a proper square bitmap. QRCoder's
// default ASCII rendering uses TWO characters per module ("██" dark, "  "
// light, one line tall) so the input is twice as wide as it is tall — we
// must collapse pairs back into single modules to draw a square QR. We also
// tolerate the 1-char-per-module variant just in case.
private struct QRBitmapView: View {
    let asciiArt: String

    private struct ParsedQR {
        var matrix: [[Bool]]
        var size: Int  // square dimension
    }

    private var parsed: ParsedQR {
        let lines = asciiArt
            .split(whereSeparator: { $0 == "\n" })
            .map(String.init)
        guard let first = lines.first, !first.isEmpty else {
            return ParsedQR(matrix: [], size: 0)
        }
        let cols = first.count
        // 2-char modules: rows == cols/2. 1-char modules: rows == cols.
        let moduleWidth: Int = (lines.count * 2 == cols) ? 2
                              : (lines.count == cols ? 1 : 2)   // assume 2 as fallback
        let modulesPerRow = cols / moduleWidth

        let matrix: [[Bool]] = lines.map { line in
            let chars = Array(line)
            var row: [Bool] = []
            row.reserveCapacity(modulesPerRow)
            var i = 0
            while i < chars.count && row.count < modulesPerRow {
                // Module is dark iff the first char of its slot is a block char.
                let c = chars[i]
                row.append(c == "█" || c == "▀" || c == "▄" || c == "▌" || c == "▐")
                i += moduleWidth
            }
            while row.count < modulesPerRow { row.append(false) }
            return row
        }

        return ParsedQR(matrix: matrix, size: max(matrix.count, modulesPerRow))
    }

    var body: some View {
        let p = parsed
        Canvas(rendersAsynchronously: false) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            guard p.size > 0, !p.matrix.isEmpty else { return }
            let cell = min(size.width, size.height) / CGFloat(p.size)
            for (y, row) in p.matrix.enumerated() {
                for (x, dark) in row.enumerated() where dark {
                    let rect = CGRect(
                        x: CGFloat(x) * cell,
                        y: CGFloat(y) * cell,
                        width: cell + 0.5,   // small overlap to kill hairline gaps
                        height: cell + 0.5
                    )
                    context.fill(Path(rect), with: .color(.black))
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct LabeledValue: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
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

struct DownloadsPane: View {
    @EnvironmentObject private var downloads: DownloadsStore
    @EnvironmentObject private var depotCtl: DepotDownloaderController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Downloads").font(.largeTitle.bold())

                if !depotCtl.isBusy && downloads.entries.isEmpty {
                    emptyView
                } else {
                    if !downloads.active.isEmpty {
                        sectionHeader("Active")
                        VStack(spacing: 10) {
                            ForEach(downloads.active) { entry in
                                DownloadRow(entry: entry)
                            }
                        }
                    }
                    if !downloads.recent.isEmpty {
                        sectionHeader("Recent")
                        VStack(spacing: 10) {
                            ForEach(downloads.recent) { entry in
                                DownloadRow(entry: entry)
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.down.circle").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("No downloads yet").font(.headline)
            Text("Pick a game from your Library and click Install to start a download.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.title3.bold())
            .foregroundStyle(.secondary)
            .padding(.top, 4)
    }
}

private struct DownloadRow: View {
    let entry: DownloadsStore.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.name).font(.callout.bold())
                Spacer()
                Text(entry.phaseText)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
            if entry.isActive {
                ProgressView(value: entry.fraction).progressViewStyle(.linear)
                HStack {
                    Text(String(format: "%.0f%%", entry.fraction * 100))
                        .font(.caption.monospacedDigit())
                    Spacer()
                    if let d = entry.downloadedBytes, let t = entry.totalBytes, t > 0 {
                        Text("\(byteString(d)) / \(byteString(t))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
    }

    private var statusColor: Color {
        switch entry.status {
        case .completed: return .green
        case .failed: return .red
        default: return .secondary
        }
    }

    private func byteString(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - Compatibility pane (power-user bottle access)

struct CompatibilityPane: View {
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var detector: ToolchainDetector
    @State private var isShowingCreateSheet = false
    @State private var isShowingRuntimeManager = false

    var body: some View {
        NavigationSplitView {
            List(selection: $store.selectedBottleID) {
                Section("Bottles") {
                    if store.bottles.isEmpty {
                        Text("No bottles yet. Bottles are created automatically when you install a game from your Library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.bottles) { bottle in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bottle.name).lineLimit(1)
                                Text(bottle.runtimeLabel).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: bottle.steamAppID != nil ? "gamecontroller.fill" : "shippingbox")
                        }
                        .tag(bottle.id)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()
                    RuntimeSummaryView()
                    Button {
                        isShowingRuntimeManager = true
                    } label: {
                        Label("Runtime Manager", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    Button {
                        isShowingCreateSheet = true
                    } label: {
                        Label("New Manual Bottle", systemImage: "plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
            }
            .frame(minWidth: 240)
            .toolbar {
                Button {
                    Task { await detector.refresh() }
                } label: {
                    Label("Refresh Runtimes", systemImage: "arrow.clockwise")
                }
                .disabled(detector.isRefreshing)
            }
        } detail: {
            if let bottle = store.selectedBottle {
                BottleDetailView(bottle: bottle)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "wineglass").font(.system(size: 56)).foregroundStyle(.secondary)
                    Text("Compatibility").font(.title2.bold())
                    Text("This is where Wine prefixes ('bottles') live. Select a bottle on the left to see its runtime, graphics backend, launch args, and logs.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 480)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $isShowingCreateSheet) {
            CreateBottleView()
        }
        .sheet(isPresented: $isShowingRuntimeManager) {
            RuntimeManagerView()
        }
    }
}

struct RuntimeSummaryView: View {
    @EnvironmentObject private var detector: ToolchainDetector

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Runtime")
                .font(.caption)
                .foregroundStyle(.secondary)
            if detector.isRefreshing {
                Label("Scanning...", systemImage: "magnifyingglass")
                    .font(.callout)
            } else if detector.candidates.isEmpty {
                Label("No Wine runtime found", systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                Label("\(detector.candidates.count) available", systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.green)
            }
        }
    }
}

struct RuntimeManagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var detector: ToolchainDetector
    @EnvironmentObject private var runtimeInstaller: RuntimeInstaller
    @EnvironmentObject private var translators: GraphicsTranslatorInstaller

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runtime Manager")
                        .font(.title2.bold())
                    Text("Download Game Porting Toolkit versions. Different games run best on different builds — assign one per game in its Compatibility section.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button("Done") { dismiss() }
            }

            HStack {
                Text("Game Porting Toolkit versions").font(.headline)
                if runtimeInstaller.isRefreshing { ProgressView().controlSize(.small) }
                Spacer()
                Button {
                    Task { await runtimeInstaller.refresh(); await detector.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                }
                .disabled(runtimeInstaller.isRefreshing || runtimeInstaller.isInstalling)
            }

            ScrollView {
                VStack(spacing: 0) {
                    if runtimeInstaller.availableReleases.isEmpty {
                        Text(runtimeInstaller.isRefreshing ? "Loading releases…" : "No releases loaded. Click Refresh.")
                            .font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(runtimeInstaller.availableReleases, id: \.tag) { release in
                            releaseRow(release)
                            Divider()
                        }
                    }

                    if !runtimeInstaller.availableWineBuilds.isEmpty {
                        HStack(spacing: 6) {
                            Text("Mainline Wine").font(.headline)
                            Image(systemName: "info.circle").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.top, 14)
                        Text("Newer Wine for games GPTK can't run (e.g. missing-function crashes). No D3DMetal — set the game's Graphics to WineD3D. Slower than GPTK, but it runs. (DXVK needs separate setup; that's coming later.)")
                            .font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 4)
                        ForEach(runtimeInstaller.availableWineBuilds, id: \.tag) { release in
                            releaseRow(release)
                            Divider()
                        }
                    }

                    HStack(spacing: 6) {
                        Text("Graphics translators").font(.headline)
                        Spacer()
                    }
                    .padding(.top, 14)
                    Text("D3D→Metal/Vulkan layers for mainline Wine (GPTK has its own D3DMetal). Auto-installed into a game's bottle when you pick that backend; download here to pre-stage.")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 4)
                    ForEach(GraphicsTranslator.allCases) { t in
                        translatorRow(t)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 340)

            Text(runtimeInstaller.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(24)
        .frame(width: 640)
        .task {
            if runtimeInstaller.availableReleases.isEmpty {
                await runtimeInstaller.refresh()
            }
        }
    }

    @ViewBuilder
    private func releaseRow(_ release: RuntimeRelease) -> some View {
        let installed = runtimeInstaller.isInstalled(release)
        let busy = runtimeInstaller.installingTag == release.tag
        HStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(release.tag).font(.callout.weight(.medium))
                Text("\(release.assetName) · \(release.displaySize)")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else if installed {
                Label("Installed", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Button {
                    Task { await runtimeInstaller.install(release); await detector.refresh() }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
                .disabled(runtimeInstaller.isInstalling)
            }
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func translatorRow(_ t: GraphicsTranslator) -> some View {
        let downloaded = translators.installed.contains(t)
        let busy = translators.busy == t
        HStack(spacing: 12) {
            Image(systemName: "cpu")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            Text(t.displayName).font(.callout.weight(.medium))
            Spacer()
            if busy {
                ProgressView().controlSize(.small)
            } else if downloaded {
                Label("Downloaded", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Button {
                    Task { try? await translators.ensureDownloaded(t) }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .controlSize(.small)
                .disabled(translators.busy != nil)
            }
        }
        .padding(.vertical, 8)
    }
}

struct CreateBottleView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var detector: ToolchainDetector
    @State private var name = "Steam Bottle"
    @State private var selectedRuntimeID: RuntimeCandidate.ID?
    @State private var customRuntime: RuntimeCandidate?
    @State private var customRuntimeError: String?
    @State private var graphicsBackend: GraphicsBackend = .automatic

    private var customRuntimeID: String { "custom-runtime" }

    private var selectedRuntime: RuntimeCandidate? {
        if selectedRuntimeID == customRuntimeID {
            return customRuntime
        }

        let id = selectedRuntimeID ?? detector.candidates.first?.id
        return detector.candidates.first { $0.id == id }
    }

    private var canCreate: Bool {
        selectedRuntime != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("New Bottle")
                .font(.title2.bold())

            Form {
                TextField("Name", text: $name)

                if detector.candidates.isEmpty {
                    LabeledContent("Runtime") {
                        VStack(alignment: .leading, spacing: 8) {
                            runtimeSelectionSummary
                            Button {
                                chooseRuntime()
                            } label: {
                                Label("Choose Wine Runtime", systemImage: "folder")
                            }
                        }
                    }
                } else {
                    Picker("Runtime", selection: Binding(
                        get: { selectedRuntimeID ?? detector.candidates.first?.id ?? "" },
                        set: { selectedRuntimeID = $0 }
                    )) {
                        ForEach(detector.candidates) { runtime in
                            Text("\(runtime.displayName) - \(runtime.locationPath)")
                                .tag(runtime.id)
                        }
                        Text("Choose manually...")
                            .tag(customRuntimeID)
                    }

                    if selectedRuntimeID == customRuntimeID {
                        LabeledContent("Runtime") {
                            HStack {
                                runtimeSelectionSummary
                                Button("Choose") {
                                    chooseRuntime()
                                }
                            }
                        }
                    }
                }

                if let customRuntimeError {
                    Text(customRuntimeError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Graphics", selection: $graphicsBackend) {
                    ForEach(GraphicsBackend.allCases) { backend in
                        Text(backend.label).tag(backend)
                    }
                }
            }

            Text("The app will create a WINEPREFIX, run Wine initialization, then keep this bottle isolated from your other Steam installs.")
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    guard let selectedRuntime else { return }
                    Task {
                        await store.createBottle(name: name, runtime: selectedRuntime, graphicsBackend: graphicsBackend)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            selectedRuntimeID = detector.candidates.first?.id ?? customRuntimeID
        }
    }

    @ViewBuilder
    private var runtimeSelectionSummary: some View {
        if let customRuntime {
            VStack(alignment: .leading, spacing: 2) {
                Text(customRuntime.displayName)
                    .lineLimit(1)
                Text(customRuntime.locationPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            Text("No Wine runtime selected")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func chooseRuntime() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Select a Wine executable or a GameNative .runtime bundle directory."
        if panel.runModal() == .OK, let url = panel.url {
            do {
                let values = try url.resourceValues(forKeys: [.isDirectoryKey])
                if values.isDirectory == true {
                    customRuntime = try RuntimeBundle.candidate(from: url)
                } else {
                    guard FileManager.default.isExecutableFile(atPath: url.path) else {
                        customRuntimeError = "The selected file is not executable."
                        return
                    }
                    customRuntime = RuntimeCandidate(
                        kind: .custom,
                        executablePath: url.path,
                        displayName: url.lastPathComponent
                    )
                }
                customRuntimeError = nil
                selectedRuntimeID = customRuntimeID
            } catch {
                customRuntime = nil
                customRuntimeError = error.localizedDescription
                selectedRuntimeID = customRuntimeID
            }
        }
    }
}

private struct RuntimeMenuView: View {
    @EnvironmentObject private var detector: ToolchainDetector
    @Binding var bottle: Bottle
    @Binding var selectedRuntimeID: RuntimeCandidate.ID?
    @Binding var runtimeSelectionError: String?
    let isBusy: Bool

    private var runtimeOptions: [RuntimeCandidate] {
        let current = RuntimeCandidate(
            kind: bottle.runtimeKind,
            executablePath: bottle.runtimePath,
            displayName: bottle.runtimeLabel,
            bundlePath: bottle.runtimeBundlePath,
            version: bottle.runtimeVersion,
            entrypoints: bottle.runtimeEntrypoints
        )
        var options = detector.candidates
        if !options.contains(where: { $0.id == current.id }) {
            options.insert(current, at: 0)
        }
        return options
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Menu {
                    ForEach(runtimeOptions) { runtime in
                        Button {
                            selectRuntime(runtime)
                        } label: {
                            Text(runtime.displayName)
                        }
                    }

                    Divider()

                    Button {
                        chooseRuntimeForBottle()
                    } label: {
                        Text("Choose manually...")
                    }
                } label: {
                    Label(bottle.runtimeLabel, systemImage: "wineglass")
                        .frame(width: 260, alignment: .leading)
                }
                .menuStyle(.button)
                .disabled(isBusy)

                Button {
                    Task {
                        await detector.refresh()
                        selectedRuntimeID = bottle.runtimeLocationPath
                    }
                } label: {
                    Label("Refresh Runtimes", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .disabled(isBusy || detector.isRefreshing)
            }

            Text(bottle.runtimeLocationPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)

            if let runtimeSelectionError {
                Text(runtimeSelectionError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func selectRuntime(_ runtime: RuntimeCandidate) {
        bottle.useRuntime(runtime)
        selectedRuntimeID = runtime.id
        runtimeSelectionError = nil
    }

    private func chooseRuntimeForBottle() {
        let previousID = bottle.runtimeLocationPath
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.treatsFilePackagesAsDirectories = true
        panel.message = "Select a Wine executable or a GameNative .runtime bundle directory."

        guard panel.runModal() == .OK, let url = panel.url else {
            selectedRuntimeID = previousID
            return
        }

        do {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey])
            let runtime: RuntimeCandidate
            if values.isDirectory == true {
                runtime = try RuntimeBundle.candidate(from: url)
            } else {
                guard FileManager.default.isExecutableFile(atPath: url.path) else {
                    runtimeSelectionError = "The selected file is not executable."
                    selectedRuntimeID = previousID
                    return
                }
                runtime = RuntimeCandidate(
                    kind: .custom,
                    executablePath: url.path,
                    displayName: url.lastPathComponent
                )
            }

            bottle.useRuntime(runtime)
            selectedRuntimeID = runtime.id
            runtimeSelectionError = nil
        } catch {
            selectedRuntimeID = previousID
            runtimeSelectionError = error.localizedDescription
        }
    }
}

struct BottleDetailView: View {
    @EnvironmentObject private var store: BottleStore
    @EnvironmentObject private var detector: ToolchainDetector
    @State var bottle: Bottle
    @State private var selectedInstallerURL: URL?
    @State private var selectedRuntimeID: RuntimeCandidate.ID?
    @State private var runtimeSelectionError: String?

    private var isBusy: Bool {
        store.activeBottleIDs.contains(bottle.id)
    }

    private var logEntries: [BottleLogEntry] {
        store.logs[bottle.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    configuration
                    actions
                    logs
                }
                .padding(22)
            }
        }
        .onChange(of: bottle) { _, newValue in
            Task { await store.update(newValue) }
        }
        .onChange(of: store.selectedBottle?.id) { _, _ in
            if let selected = store.selectedBottle {
                bottle = selected
                selectedRuntimeID = selected.runtimeLocationPath
                runtimeSelectionError = nil
            }
        }
        .onAppear {
            selectedRuntimeID = bottle.runtimeLocationPath
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 34))
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                TextField("Bottle name", text: $bottle.name)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                Text(AppPaths.prefixURL(for: bottle).path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Button(role: .destructive) {
                Task { await store.delete(bottle) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(isBusy)
        }
        .padding(22)
    }

    private var configuration: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Configuration")
                .font(.headline)

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Runtime")
                        .foregroundStyle(.secondary)
                    RuntimeMenuView(
                        bottle: $bottle,
                        selectedRuntimeID: $selectedRuntimeID,
                        runtimeSelectionError: $runtimeSelectionError,
                        isBusy: isBusy
                    )
                }
                GridRow {
                    Text("Graphics")
                        .foregroundStyle(.secondary)
                    Picker("Graphics", selection: $bottle.graphicsBackend) {
                        ForEach(GraphicsBackend.allCases) { backend in
                            Text(backend.label).tag(backend)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                }
                GridRow {
                    Text("Windows")
                        .foregroundStyle(.secondary)
                    TextField("Windows version", text: $bottle.windowsVersion)
                        .frame(width: 220)
                }
                GridRow {
                    Text("Steam args")
                        .foregroundStyle(.secondary)
                    TextField("Launch arguments", text: $bottle.launchArguments)
                }
                GridRow {
                    Text("Notes")
                        .foregroundStyle(.secondary)
                    TextField("Compatibility notes", text: $bottle.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.headline)

            HStack(spacing: 10) {
                Button {
                    Task { await store.initializeBottle(bottle) }
                } label: {
                    Label("Repair", systemImage: "wrench.adjustable")
                }
                .disabled(isBusy)

                Button {
                    chooseSteamInstaller()
                } label: {
                    Label("Choose SteamSetup.exe", systemImage: "square.and.arrow.down")
                }
                .disabled(isBusy)

                Button {
                    guard let selectedInstallerURL else { return }
                    Task { await store.installSteam(in: bottle, installerURL: selectedInstallerURL) }
                } label: {
                    Label("Install Steam", systemImage: "play.circle")
                }
                .disabled(selectedInstallerURL == nil || isBusy)

                Button {
                    Task { await store.launchSteam(in: bottle) }
                } label: {
                    Label("Launch Steam", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isBusy)

                Button {
                    Task { await store.launchSteamBigPicture(in: bottle) }
                } label: {
                    Label("Big Picture", systemImage: "tv")
                }
                .disabled(isBusy)

                Button {
                    Task { await store.launchSteamDiagnostic(in: bottle) }
                } label: {
                    Label("Debug Launch", systemImage: "stethoscope")
                }
                .disabled(isBusy)

                Button {
                    Task { await store.stopBottleProcesses(bottle) }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }

                Button {
                    applyWebHelperFixAndRestart()
                } label: {
                    Label("Fix WebHelper", systemImage: "bandage")
                }

                Button {
                    resetSteamArgs()
                } label: {
                    Label("Reset Args", systemImage: "arrow.uturn.backward")
                }

                Menu {
                    Button {
                        Task { await store.removeSteamUpdateLock(bottle) }
                    } label: {
                        Label("Allow Steam Updates", systemImage: "lock.open")
                    }

                    Button {
                        Task { await store.refreshSteamClientPackage(bottle) }
                    } label: {
                        Label("Refresh Steam Client", systemImage: "arrow.triangle.2.circlepath")
                    }

                    Divider()

                    Button {
                        Task { await store.writeSteamUpdateLock(bottle) }
                    } label: {
                        Label("Lock Steam Updates", systemImage: "lock")
                    }

                    Button {
                        Task { await store.downgradeSteamClient(bottle) }
                    } label: {
                        Label("Downgrade Steam Client", systemImage: "clock.arrow.circlepath")
                    }
                } label: {
                    Label("Steam Repair", systemImage: "cross.case")
                }

                Button {
                    store.reveal(bottle)
                } label: {
                    Label("Reveal", systemImage: "folder")
                }
            }

            if let selectedInstallerURL {
                Text(selectedInstallerURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Text("Each Steam launch starts a fresh log. If Steam webhelper still fails, use Debug Launch for Wine diagnostics or Steam Repair to try the known GPTK Steam client downgrade/update-lock workaround.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var logs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Log")
                .font(.headline)

            if let health = store.webHelperHealth[bottle.id], health.isCrashLooping {
                webHelperWarning(health: health)
            }

            HStack {
                Button {
                    store.copyLogToClipboard(bottle)
                } label: {
                    Label("Copy Log", systemImage: "doc.on.doc")
                }

                Button {
                    store.revealLog(bottle)
                } label: {
                    Label("Reveal Wine Log", systemImage: "doc.text.magnifyingglass")
                }

                Menu {
                    Button {
                        store.revealSteamLogs(bottle)
                    } label: {
                        Label("Open Steam Logs Folder", systemImage: "folder")
                    }
                    Divider()
                    ForEach(SteamLogFile.allCases) { file in
                        Button {
                            store.revealSteamLog(bottle, file: file)
                        } label: {
                            Text(file.label)
                        }
                    }
                } label: {
                    Label("Steam Logs", systemImage: "doc.text.below.ecg")
                }

                Spacer()
            }

            Text("The Wine log above only captures the parent Steam bootstrap, which exits within ~1s when Steam is already running. If the UI never appears, the actual error is in Steam's CEF/webhelper logs.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(logEntries) { entry in
                            Text(entry.message)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(entry.isError ? .red : .primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .frame(minHeight: 190)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if logEntries.isEmpty {
                        Text("No log output yet.")
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: logEntries.count) { _, _ in
                    if let last = logEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // Runtimes other than the one currently bound to this bottle. Used by the
    // "Try a different runtime" button in the webhelper-crash warning banner —
    // a CrossOver/Whisky/system Wine often has a `ws2_32.WSALookupServiceBeginW`
    // that doesn't trip the Chromium `NOTREACHED()`, where GPTK 3.0-3 does.
    private var alternativeRuntimes: [RuntimeCandidate] {
        let current = bottle.runtimeLocationPath
        return detector.candidates.filter { $0.locationPath != current }
    }

    @ViewBuilder
    private func webHelperWarning(health: WebHelperHealth) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 8) {
                Text("Steam UI is crash-looping")
                    .font(.callout.bold())
                Text("steamwebhelper.exe has restarted \(health.restartCount) times. Chromium's NetworkChangeNotifier is calling `ws2_32.WSALookupServiceBeginW`, which this Wine runtime returns an error for, so Chromium hits NOTREACHED() and the helper exits. Big Picture / CEF flags don't help — modern Steam Big Picture uses CEF too, and no Steam launch flag reaches inside Chromium to disable that code path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("The reliable fix is a Wine runtime that ships `ws2_32` patches. Whisky is free, CrossOver has a 14-day trial. Once installed, click Refresh Runtimes in the sidebar and the option will appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let snippet = health.lastCEFError, !snippet.isEmpty {
                    Text(snippet)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .textBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    if alternativeRuntimes.isEmpty {
                        Button {
                            NSWorkspace.shared.open(URL(string: "https://github.com/Whisky-App/Whisky/releases/latest")!)
                        } label: {
                            Label("Get Whisky", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.borderedProminent)

                        Button {
                            NSWorkspace.shared.open(URL(string: "https://www.codeweavers.com/crossover/download")!)
                        } label: {
                            Label("Get CrossOver", systemImage: "arrow.down.circle")
                        }
                    } else {
                        Menu {
                            ForEach(alternativeRuntimes) { runtime in
                                Button {
                                    swapRuntimeAndRelaunch(to: runtime)
                                } label: {
                                    Text(runtime.displayName)
                                }
                            }
                        } label: {
                            Label("Swap Runtime & Relaunch", systemImage: "wineglass")
                        }
                        .menuStyle(.borderedButton)
                    }

                    Menu {
                        Button {
                            store.revealSteamLog(bottle, file: .cef)
                        } label: {
                            Label("Open cef_log.txt", systemImage: "doc.text.magnifyingglass")
                        }
                        Button {
                            Task {
                                await store.stopBottleProcesses(bottle)
                                try? await Task.sleep(for: .seconds(1))
                                await store.launchSteamBigPicture(in: bottle)
                            }
                        } label: {
                            Label("Retry as Big Picture (long shot)", systemImage: "tv")
                        }
                        Button {
                            applyWebHelperFixAndRestart()
                        } label: {
                            Label("Apply WebHelper safe-args (long shot)", systemImage: "bandage")
                        }
                        Button {
                            Task { await store.downgradeSteamClient(bottle) }
                        } label: {
                            Label("Downgrade Steam Client (long shot)", systemImage: "clock.arrow.circlepath")
                        }
                    } label: {
                        Label("Other Attempts…", systemImage: "ellipsis.circle")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.4), lineWidth: 1)
        )
    }

    private func swapRuntimeAndRelaunch(to runtime: RuntimeCandidate) {
        bottle.useRuntime(runtime)
        Task {
            await store.update(bottle)
            await store.stopBottleProcesses(bottle)
            try? await Task.sleep(for: .seconds(1))
            await store.launchSteam(in: bottle)
        }
    }

    private func chooseSteamInstaller() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.exe]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Select SteamSetup.exe downloaded from Valve."
        if panel.runModal() == .OK {
            selectedInstallerURL = panel.url
        }
    }

    private func applyWebHelperFixAndRestart() {
        bottle.launchArguments = SteamLaunchDefaults.mergedWithWebHelperSafeArguments(bottle.launchArguments)
        Task {
            await store.update(bottle)
            await store.restartSteamWithWebHelperFix(bottle)
        }
    }

    private func resetSteamArgs() {
        bottle.launchArguments = SteamLaunchDefaults.basicArguments
        Task {
            await store.resetSteamArguments(bottle)
        }
    }
}

private extension UTType {
    static let exe = UTType(filenameExtension: "exe")!
}
