import AppKit
import SwiftUI
import UniformTypeIdentifiers

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

