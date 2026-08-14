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
    @State private var isShowingCloudConnect: Bool = false
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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Windows version")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                TextField("win10", text: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.windowsVersion
                            ?? liveBottle.windowsVersion
                    },
                    set: { newValue in
                        bottles.mutate(bottleID: bottleID) { $0.windowsVersion = newValue }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                Spacer()
            }

            HStack(alignment: .top, spacing: 12) {
                Text("Notes")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)
                TextField("Compatibility notes", text: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.notes
                            ?? liveBottle.notes
                    },
                    set: { newValue in
                        bottles.mutate(bottleID: bottleID) { $0.notes = newValue }
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
        let bottleID = bottle.id
        let liveBottle = bottles.bottles.first(where: { $0.id == bottleID }) ?? bottle
        let resolutionMode = liveBottle.effectiveDisplayResolutionMode

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Resolution")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)

                Picker("Resolution", selection: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.effectiveDisplayResolutionMode ?? resolutionMode
                    },
                    set: { newValue in
                        bottles.mutate(bottleID: bottleID) { $0.displayResolutionMode = newValue }
                    }
                )) {
                    ForEach(DisplayResolutionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 240)

                Spacer()
            }

            Text(resolutionMode == .highResolution
                ? "Exposes Retina resolutions to the game (up to twice the width and height) and treats it as DPI-aware. Sharper, but substantially more demanding; some games may not handle high-DPI mode correctly."
                : "Uses macOS point dimensions for better performance and compatibility. On Retina displays this limits games to half the high-resolution width and height.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 142)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func gameLaunchArgumentsRow(bottle: Bottle) -> some View {
        let bottleID = bottle.id

        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Launch arguments")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(width: 130, alignment: .leading)

                TextField("Optional game arguments", text: Binding(
                    get: {
                        bottles.bottles.first(where: { $0.id == bottleID })?.effectiveGameLaunchArguments
                            ?? bottle.effectiveGameLaunchArguments
                    },
                    set: { newValue in
                        bottles.mutate(bottleID: bottleID) { $0.gameLaunchArguments = newValue }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 520)

                Spacer()
            }

            Text("Passed directly to the game executable. For Unity games, for example: -screen-width 3024 -screen-height 1964 -screen-fullscreen 0")
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
                    events: { event in
                        switch event {
                        case .log(let line):
                            downloads.append(appID: game.appID, log: line)
                        case .status(let phase):
                            downloads.setStatus(appID: game.appID, phase: phase)
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
