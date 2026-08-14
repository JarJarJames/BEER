import AppKit
import Foundation

@MainActor
final class BottleStore: ObservableObject {
    @Published private(set) var bottles: [Bottle] = []
    @Published var selectedBottleID: Bottle.ID?
    @Published private(set) var logs: [Bottle.ID: [BottleLogEntry]] = [:]
    @Published private(set) var activeBottleIDs: Set<Bottle.ID> = []
    @Published private(set) var webHelperHealth: [Bottle.ID: WebHelperHealth] = [:]
    @Published var lastError: String?

    var selectedBottle: Bottle? {
        guard let selectedBottleID else { return bottles.first }
        return bottles.first { $0.id == selectedBottleID } ?? bottles.first
    }

    func load() async {
        do {
            try AppPaths.ensureBaseDirectories()
            guard FileManager.default.fileExists(atPath: AppPaths.metadataURL.path) else {
                bottles = []
                return
            }
            let data = try Data(contentsOf: AppPaths.metadataURL)
            bottles = try JSONDecoder.gamenative.decode([Bottle].self, from: data)

            var metadataChanged = false

            // Older Library bottles stored game flags in the Steam-only field.
            // Move custom values once, then keep the two launch paths separate.
            for index in bottles.indices where bottles[index].migrateLegacyLibraryLaunchArguments() {
                metadataChanged = true
            }

            // One-time fix-up after the GameNativeMac → BEER rename: rewrite any
            // stored absolute paths still pointing at the old support dir.
            let current = AppPaths.applicationSupport.path
            let legacy = AppPaths.applicationSupport.deletingLastPathComponent()
                .appendingPathComponent("GameNativeMac", isDirectory: true).path
            if legacy != current {
                for i in bottles.indices where bottles[i].rewriteStoragePaths(from: legacy, to: current) {
                    metadataChanged = true
                }
            }
            if metadataChanged { await save() }

            selectedBottleID = bottles.first?.id
            loadPersistedLogs()
        } catch {
            lastError = "Could not load bottles: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func createBottle(name: String, runtime: RuntimeCandidate, graphicsBackend: GraphicsBackend) async -> Bottle {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let bottle = Bottle.make(name: trimmed.isEmpty ? "Steam Bottle" : trimmed, runtime: runtime, graphicsBackend: graphicsBackend)
        bottles.insert(bottle, at: 0)
        selectedBottleID = bottle.id
        appendLog("Created metadata for \(bottle.name).", bottleID: bottle.id)
        await save()
        await initializeBottle(bottle)
        return bottle
    }

    /// Claim a freshly-created bottle for a specific Steam app. Sets steamAppID
    /// + steamGameName + gameInstallStatus = .installing IMMEDIATELY (before the
    /// long DepotDownloader phase) so retries can find and reuse this bottle
    /// instead of leaving an orphan behind.
    func claimForSteamApp(_ bottle: Bottle, appID: Int, gameName: String) async {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[index].steamAppID = appID
        bottles[index].steamGameName = gameName
        bottles[index].gameInstallStatus = .installing
        bottles[index].launchArguments = ""
        bottles[index].updatedAt = Date()
        await save()
    }

    /// Find any existing bottle that belongs to the given Steam app — used to
    /// recover from a previous failed install instead of starting over.
    func findBottle(forAppID appID: Int) -> Bottle? {
        bottles.first { $0.steamAppID == appID }
    }

    /// Delete every bottle for this appID except the one we want to keep.
    /// Used to remove orphans accumulated by previous bugs.
    func cleanupOrphans(forAppID appID: Int, keep keepID: UUID? = nil) async {
        let victims = bottles.filter {
            $0.steamAppID == appID &&
            $0.id != keepID &&
            $0.gameInstallStatus != .installed
        }
        for victim in victims {
            await delete(victim)
        }
    }

    func initializeBottle(_ bottle: Bottle) async {
        await runBottleCommand(
            bottle,
            operation: "Initializing bottle",
            mode: .wineboot
        )
    }

    func installSteam(in bottle: Bottle, installerURL: URL) async {
        await runBottleCommand(
            bottle,
            operation: "Installing Steam",
            mode: .wine(arguments: [installerURL.path])
        )
    }

    /// Launch a specific .exe (Wine-style path like `C:\Games\Hades\x64\Hades.exe`)
    /// inside the bottle's prefix. Used by the per-game Library flow once
    /// the game is installed.
    ///
    /// We run the game's .exe directly (no `wine explorer /desktop` wrapper).
    /// `configureDisplayMode` applies the selected Wine Mac driver resolution
    /// mode before the game starts.
    func launchGameExecutable(_ bottle: Bottle, executable: String, arguments: String? = nil) async {
        resetLog(for: bottle, reason: "Launching \(bottle.steamGameName ?? bottle.name)")
        await configureDisplayMode(bottle)

        var args: [String] = [executable]
        if let arguments, !arguments.isEmpty {
            args.append(contentsOf: arguments.split(separator: " ").map(String.init))
        }
        await runBottleCommand(
            bottle,
            operation: "Launching \(bottle.steamGameName ?? bottle.name)",
            mode: .wine(arguments: args)
        )
    }

    /// High Resolution mirrors CrossOver's mode: Retina backing, 192 DPI, and a
    /// Wine 10 compatibility override so games misclassified as DPI-unaware are
    /// not silently pixel-doubled back to Standard dimensions.
    private func configureDisplayMode(_ bottle: Bottle) async {
        let highResolution = bottle.effectiveDisplayResolutionMode == .highResolution
        let retina = highResolution ? "Y" : "N"
        let logPixels = highResolution ? "192" : "96"
        let dpiAwareness = highResolution ? "~ HIGHDPIAWARE" : ""

        await runBottleCommand(
            bottle,
            operation: "Configuring display capture",
            mode: .wine(arguments: [
                "reg", "add", #"HKEY_CURRENT_USER\Software\Wine\Mac Driver"#,
                "/v", "CaptureDisplaysForFullscreen", "/t", "REG_SZ", "/d", "N", "/f"
            ])
        )
        await runBottleCommand(
            bottle,
            operation: "Configuring \(bottle.effectiveDisplayResolutionMode.label) mode",
            mode: .wine(arguments: [
                "reg", "add", #"HKEY_CURRENT_USER\Software\Wine\Mac Driver"#,
                "/v", "RetinaMode", "/t", "REG_SZ", "/d", retina, "/f"
            ])
        )
        await runBottleCommand(
            bottle,
            operation: "Configuring display DPI",
            mode: .wine(arguments: [
                "reg", "add", #"HKEY_CURRENT_USER\Control Panel\Desktop"#,
                "/v", "LogPixels", "/t", "REG_DWORD", "/d", logPixels, "/f"
            ])
        )
        await runBottleCommand(
            bottle,
            operation: "Configuring DPI awareness",
            mode: .wine(arguments: [
                "reg", "add", #"HKEY_CURRENT_USER\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers"#,
                "/ve", "/t", "REG_SZ", "/d", dpiAwareness, "/f"
            ])
        )

        // These values are process-wide. Ensure the game starts in a fresh Wine
        // session instead of inheriting the mode used by the registry commands.
        await runBottleCommand(
            bottle,
            operation: "Restarting Wine display services",
            mode: .winebootKill
        )
    }

    /// Record install metadata on a bottle (called by the Library install flow).
    func recordGameInstall(
        _ bottle: Bottle,
        appID: Int,
        gameName: String,
        launchExecutable: String,
        launchArguments: String?,
        installDirectory: String? = nil
    ) async {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[index].steamAppID = appID
        bottles[index].steamGameName = gameName
        bottles[index].gameLaunchExecutable = launchExecutable
        bottles[index].gameInstallDirectory = installDirectory
        bottles[index].gameInstallStatus = .installed
        if let launchArguments, !launchArguments.isEmpty {
            bottles[index].gameLaunchArguments = launchArguments
        }
        bottles[index].updatedAt = Date()
        await save()
    }

    func launchSteam(in bottle: Bottle) async {
        resetLog(for: bottle, reason: "Launching Steam")
        webHelperHealth[bottle.id] = nil
        scheduleWebHelperHealthChecks(for: bottle)
        var args = ["C:\\Program Files (x86)\\Steam\\steam.exe"]
        args.append(contentsOf: bottle.launchArguments.split(separator: " ").map(String.init))
        await runBottleCommand(
            bottle,
            operation: "Launching Steam",
            mode: .wine(arguments: args)
        )
    }

    func launchSteamDiagnostic(in bottle: Bottle) async {
        resetLog(for: bottle, reason: "Launching Steam with Wine diagnostics")
        webHelperHealth[bottle.id] = nil
        scheduleWebHelperHealthChecks(for: bottle)
        var args = ["C:\\Program Files (x86)\\Steam\\steam.exe"]
        args.append(contentsOf: bottle.launchArguments.split(separator: " ").map(String.init))
        await runBottleCommand(
            bottle,
            operation: "Launching Steam with Wine diagnostics",
            mode: .wine(arguments: args),
            environmentOverrides: [
                "WINEDEBUG": "+timestamp,+pid,+tid,+seh,+loaddll,+module"
            ]
        )
    }

    func launchSteamBigPicture(in bottle: Bottle) async {
        resetLog(for: bottle, reason: "Launching Steam (Big Picture / -tenfoot)")
        webHelperHealth[bottle.id] = nil
        scheduleWebHelperHealthChecks(for: bottle)
        var args = ["C:\\Program Files (x86)\\Steam\\steam.exe"]
        args.append(contentsOf: SteamLaunchDefaults.bigPictureArguments.split(separator: " ").map(String.init))
        // Append any user-set launch args that don't conflict with -tenfoot.
        for token in bottle.launchArguments.split(separator: " ").map(String.init) where !args.contains(token) {
            args.append(token)
        }
        await runBottleCommand(
            bottle,
            operation: "Launching Steam (Big Picture)",
            mode: .wine(arguments: args)
        )
    }

    func stopBottleProcesses(_ bottle: Bottle) async {
        await runBottleCommand(
            bottle,
            operation: "Stopping bottle processes",
            mode: .winebootKill,
            allowWhileActive: true
        )
    }

    func restartSteamWithWebHelperFix(_ bottle: Bottle) async {
        var fixedBottle = bottle
        fixedBottle.launchArguments = SteamLaunchDefaults.mergedWithWebHelperSafeArguments(bottle.launchArguments)
        await update(fixedBottle)
        await stopBottleProcesses(fixedBottle)
        try? await Task.sleep(for: .seconds(1))
        await launchSteam(in: fixedBottle)
    }

    func resetSteamArguments(_ bottle: Bottle) async {
        var resetBottle = bottle
        resetBottle.launchArguments = SteamLaunchDefaults.basicArguments
        await update(resetBottle)
        appendLog("Reset Steam launch arguments to \(SteamLaunchDefaults.basicArguments).", bottleID: bottle.id)
    }

    func writeSteamUpdateLock(_ bottle: Bottle) async {
        let steamDirectory = steamDirectoryURL(for: bottle)
        let configURL = steamDirectory.appendingPathComponent("steam.cfg")

        do {
            try FileManager.default.createDirectory(at: steamDirectory, withIntermediateDirectories: true)
            let contents = """
            BootStrapperInhibitAll=enable
            BootStrapperForceSelfUpdate=disable

            """
            try contents.write(to: configURL, atomically: true, encoding: .utf8)
            appendLog("Wrote Steam update lock to \(configURL.path).", bottleID: bottle.id)
        } catch {
            appendLog("Could not write Steam update lock: \(error.localizedDescription)", bottleID: bottle.id, isError: true)
            lastError = error.localizedDescription
        }
    }

    func removeSteamUpdateLock(_ bottle: Bottle) async {
        let configURL = steamDirectoryURL(for: bottle).appendingPathComponent("steam.cfg")

        do {
            guard FileManager.default.fileExists(atPath: configURL.path) else {
                appendLog("Steam update lock is already removed.", bottleID: bottle.id)
                return
            }
            try FileManager.default.removeItem(at: configURL)
            appendLog("Removed Steam update lock from \(configURL.path).", bottleID: bottle.id)
        } catch {
            appendLog("Could not remove Steam update lock: \(error.localizedDescription)", bottleID: bottle.id, isError: true)
            lastError = error.localizedDescription
        }
    }

    func refreshSteamClientPackage(_ bottle: Bottle) async {
        resetLog(for: bottle, reason: "Refreshing Steam client package")
        await stopBottleProcesses(bottle)
        await removeSteamUpdateLock(bottle)

        let steamDirectory = steamDirectoryURL(for: bottle)
        let packageURL = steamDirectory.appendingPathComponent("package", isDirectory: true)

        do {
            if FileManager.default.fileExists(atPath: packageURL.path) {
                let backupURL = steamDirectory.appendingPathComponent("package.gamenative-backup-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
                try FileManager.default.moveItem(at: packageURL, to: backupURL)
                appendLog("Moved Steam package cache to \(backupURL.path).", bottleID: bottle.id)
            } else {
                appendLog("No Steam package cache was present.", bottleID: bottle.id)
            }
        } catch {
            appendLog("Could not move Steam package cache: \(error.localizedDescription)", bottleID: bottle.id, isError: true)
            lastError = error.localizedDescription
            return
        }

        await runBottleCommand(
            bottle,
            operation: "Forcing Steam client refresh",
            mode: .wine(arguments: [
                "C:\\Program Files (x86)\\Steam\\steam.exe",
                "-forcesteamupdate",
                "-forcepackagedownload",
                "-exitsteam"
            ]),
            allowWhileActive: true
        )
    }

    func downgradeSteamClient(_ bottle: Bottle) async {
        resetLog(for: bottle, reason: "Downgrading Steam client")
        await stopBottleProcesses(bottle)
        await writeSteamUpdateLock(bottle)
        await runBottleCommand(
            bottle,
            operation: "Downgrading Steam client",
            mode: .wine(arguments: [
                "C:\\Program Files (x86)\\Steam\\steam.exe",
                "-forcesteamupdate",
                "-forcepackagedownload",
                "-overridepackageurl",
                "http://web.archive.org/web/20240520if_/media.steampowered.com/client",
                "-exitsteam"
            ]),
            allowWhileActive: true
        )
    }

    func reveal(_ bottle: Bottle) {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.prefixURL(for: bottle)])
    }

    func revealLog(_ bottle: Bottle) {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.logsURL(for: bottle)])
    }

    func revealSteamLogs(_ bottle: Bottle) {
        let url = AppPaths.steamLogsDirectoryURL(for: bottle)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            appendLog("No Steam logs directory yet at \(url.path). Launch Steam first.", bottleID: bottle.id)
        }
    }

    func revealSteamLog(_ bottle: Bottle, file: SteamLogFile) {
        let url = AppPaths.steamLogURL(for: bottle, name: file.rawValue)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            appendLog("Steam log \(file.rawValue) does not exist yet at \(url.path).", bottleID: bottle.id)
        }
    }

    func copyLogToClipboard(_ bottle: Bottle) {
        let text: String
        if let data = try? Data(contentsOf: AppPaths.logsURL(for: bottle)),
           let fileText = String(data: data, encoding: .utf8),
           !fileText.isEmpty {
            text = fileText
        } else {
            text = logs[bottle.id, default: []]
                .map(\.message)
                .joined(separator: "\n")
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        appendLog("Copied log to clipboard.", bottleID: bottle.id)
    }

    func delete(_ bottle: Bottle) async {
        do {
            let url = AppPaths.prefixURL(for: bottle)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            bottles.removeAll { $0.id == bottle.id }
            logs[bottle.id] = nil
            selectedBottleID = bottles.first?.id
            await save()
        } catch {
            lastError = "Could not delete bottle: \(error.localizedDescription)"
        }
    }

    func update(_ bottle: Bottle) async {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        var updated = bottle
        updated.updatedAt = Date()
        bottles[index] = updated
        await save()
    }

    /// Synchronous mutation helper so Toggle / Picker bindings can observe
    /// the change in the next render without the @Published lag that `update`'s
    /// async wrapper introduces. The disk save is fired off afterward.
    func mutate(bottleID: UUID, _ apply: (inout Bottle) -> Void) {
        guard let index = bottles.firstIndex(where: { $0.id == bottleID }) else { return }
        var copy = bottles[index]
        apply(&copy)
        copy.updatedAt = Date()
        bottles[index] = copy   // synchronous @Published fire
        Task { await save() }   // best-effort persist
    }

    private func runBottleCommand(
        _ bottle: Bottle,
        operation: String,
        mode: BottleCommandMode,
        allowWhileActive: Bool = false,
        environmentOverrides: [String: String] = [:]
    ) async {
        guard allowWhileActive || !activeBottleIDs.contains(bottle.id) else { return }

        activeBottleIDs.insert(bottle.id)
        appendLog("\(operation)...", bottleID: bottle.id)

        do {
            try AppPaths.ensureBaseDirectories()
            let prefix = AppPaths.prefixURL(for: bottle)
            try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)

            let command = command(for: bottle, prefix: prefix, mode: mode)

            // Log the exact command we're about to run so launch configuration
            // issues are diagnosable from beer.log instead of guesswork.
            let renderedArgs = command.arguments
                .map { $0.contains(" ") ? "\"\($0)\"" : $0 }
                .joined(separator: " ")
            appendLog("$ \(command.executable) \(renderedArgs)", bottleID: bottle.id)

            let result = try await ShellRunner.run(
                executable: command.executable,
                arguments: command.arguments,
                environment: environment(for: bottle, prefix: prefix).merging(environmentOverrides) { _, new in new },
                outputHandler: { [weak self] chunk in
                    Task { @MainActor in
                        self?.appendLog(chunk.trimmingCharacters(in: .newlines), bottleID: bottle.id)
                    }
                }
            )

            if result.exitCode == 0 {
                appendLog("\(operation) finished.", bottleID: bottle.id)
            } else {
                appendLog("\(operation) exited with code \(result.exitCode).", bottleID: bottle.id, isError: true)
            }
        } catch {
            appendLog("\(operation) failed: \(error.localizedDescription)", bottleID: bottle.id, isError: true)
            lastError = error.localizedDescription
        }

        activeBottleIDs.remove(bottle.id)
    }

    private func resetLog(for bottle: Bottle, reason: String) {
        logs[bottle.id] = []
        let url = AppPaths.logsURL(for: bottle)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data().write(to: url, options: .atomic)
        appendLog("\(reason) at \(Date.formattedLogDate).", bottleID: bottle.id)
    }

    private func command(for bottle: Bottle, prefix: URL, mode: BottleCommandMode) -> BottleCommand {
        if isRuntimeBundleBottle(bottle) {
            switch mode {
            case .wineboot:
                if let wineboot = runtimeWinebootPath(for: bottle) {
                    return BottleCommand(executable: wineboot, arguments: ["-u"])
                }
                return BottleCommand(executable: runtimeWinePath(for: bottle), arguments: ["wineboot", "-u"])
            case .winebootKill:
                if let wineserver = runtimeWineserverPath(for: bottle) {
                    return BottleCommand(executable: wineserver, arguments: ["-k"])
                }
                if let wineboot = runtimeWinebootPath(for: bottle) {
                    return BottleCommand(executable: wineboot, arguments: ["-k"])
                }
                return BottleCommand(executable: runtimeWinePath(for: bottle), arguments: ["wineboot", "-k"])
            case .wine(let arguments):
                return BottleCommand(executable: runtimeWinePath(for: bottle), arguments: arguments)
            }
        }

        if bottle.runtimeKind == .gamePortingToolkit {
            switch mode {
            case .wineboot:
                return BottleCommand(executable: bottle.runtimePath, arguments: [prefix.path, "wineboot", "-u"])
            case .winebootKill:
                return BottleCommand(executable: bottle.runtimePath, arguments: [prefix.path, "wineboot", "-k"])
            case .wine(let arguments):
                return BottleCommand(executable: bottle.runtimePath, arguments: [prefix.path] + arguments)
            }
        }

        switch mode {
        case .wineboot:
            let wineboot = URL(fileURLWithPath: bottle.runtimePath)
                .deletingLastPathComponent()
                .appendingPathComponent("wineboot")
                .path
            if FileManager.default.isExecutableFile(atPath: wineboot) {
                return BottleCommand(executable: wineboot, arguments: ["-u"])
            }
            return BottleCommand(executable: bottle.runtimePath, arguments: ["wineboot", "-u"])
        case .winebootKill:
            let wineboot = URL(fileURLWithPath: bottle.runtimePath)
                .deletingLastPathComponent()
                .appendingPathComponent("wineboot")
                .path
            if FileManager.default.isExecutableFile(atPath: wineboot) {
                return BottleCommand(executable: wineboot, arguments: ["-k"])
            }
            return BottleCommand(executable: bottle.runtimePath, arguments: ["wineboot", "-k"])
        case .wine(let arguments):
            return BottleCommand(executable: bottle.runtimePath, arguments: arguments)
        }
    }

    private func isRuntimeBundleBottle(_ bottle: Bottle) -> Bool {
        bottle.runtimeKind == .gameNativeWine || bottle.runtimeBundlePath != nil
    }

    private func runtimeWinePath(for bottle: Bottle) -> String {
        bottle.runtimeEntrypoints?.wine ?? bottle.runtimePath
    }

    private func runtimeWinebootPath(for bottle: Bottle) -> String? {
        if let wineboot = bottle.runtimeEntrypoints?.wineboot,
           FileManager.default.isExecutableFile(atPath: wineboot) {
            return wineboot
        }

        let sibling = URL(fileURLWithPath: runtimeWinePath(for: bottle))
            .deletingLastPathComponent()
            .appendingPathComponent("wineboot")
            .path
        return FileManager.default.isExecutableFile(atPath: sibling) ? sibling : nil
    }

    private func runtimeWineserverPath(for bottle: Bottle) -> String? {
        if let wineserver = bottle.runtimeEntrypoints?.wineserver,
           FileManager.default.isExecutableFile(atPath: wineserver) {
            return wineserver
        }

        let sibling = URL(fileURLWithPath: runtimeWinePath(for: bottle))
            .deletingLastPathComponent()
            .appendingPathComponent("wineserver")
            .path
        return FileManager.default.isExecutableFile(atPath: sibling) ? sibling : nil
    }

    private func steamDirectoryURL(for bottle: Bottle) -> URL {
        AppPaths.steamDirectoryURL(for: bottle)
    }

    // Steam's UI is rendered by `steamwebhelper.exe` (CEF). On Wine/macOS the
    // helper often crashes inside Chromium's `NetworkChangeNotifierWin` because
    // `ws2_32.WSALookupServiceBeginW` is incomplete in vanilla Wine / GPTK. The
    // helper dies, Steam respawns it, and the loop continues forever — the
    // parent Wine process stays alive and looks "healthy" so the launch never
    // reports a failure.
    //
    // We fire three checks (+15s, +45s, +90s after launch). Each one reads
    // `steamui_html.txt` and counts recent webhelper start/shutdown events,
    // plus grabs the tail of `cef_log.txt` for the actual error snippet. We
    // only log the warning once per launch (when state transitions to
    // crash-looping) so the UI doesn't fill up with duplicate messages.
    private func scheduleWebHelperHealthChecks(for bottle: Bottle) {
        let bottleID = bottle.id
        for delay in [15, 45, 90] {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                self?.checkWebHelperHealth(bottleID: bottleID, isFinal: delay == 90)
            }
        }
    }

    private func checkWebHelperHealth(bottleID: Bottle.ID, isFinal: Bool) {
        guard let bottle = bottles.first(where: { $0.id == bottleID }) else { return }

        let uiLogURL = AppPaths.steamLogURL(for: bottle, name: SteamLogFile.steamui.rawValue)
        let cefLogURL = AppPaths.steamLogURL(for: bottle, name: SteamLogFile.cef.rawValue)

        guard let uiLog = readTail(of: uiLogURL, lines: 400) else {
            if isFinal {
                appendLog("Webhelper health: \(SteamLogFile.steamui.rawValue) is missing. Steam may not have started.", bottleID: bottleID)
            }
            return
        }

        let started = uiLog.filter { $0.contains("Started webhelper process") }.count
        let shutdown = uiLog.filter { $0.contains("Shutting down webhelper process") }.count
        // Threshold: ≥2 start/shutdown pairs is enough to call it a loop. A
        // healthy Steam starts exactly one webhelper and keeps it alive.
        let isLooping = started >= 2 && shutdown >= 2

        let snippet = (readTail(of: cefLogURL, lines: 8) ?? [])
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let next = WebHelperHealth(restartCount: started, lastCEFError: snippet.isEmpty ? nil : snippet)
        let previous = webHelperHealth[bottleID]
        webHelperHealth[bottleID] = next

        // Only log on a transition (or on the final check, so the user always
        // gets a definitive answer).
        let wasLooping = previous?.isCrashLooping ?? false
        if isLooping && !wasLooping {
            appendLog(
                "Steam UI failed to render: steamwebhelper.exe restarted \(started) times. Almost certainly Wine's ws2_32.WSALookupServiceBeginW failing — see cef_log.txt and the banner above for options.",
                bottleID: bottleID,
                isError: true
            )
        } else if isFinal && !isLooping && previous == nil {
            appendLog("Webhelper looks stable (\(started) start / \(shutdown) shutdown events).", bottleID: bottleID)
        }
    }

    private func readTail(of url: URL, lines: Int) -> [String]? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .suffix(lines)
            .map(String.init)
    }

    private func environment(for bottle: Bottle, prefix: URL) -> [String: String] {
        var env = bottle.environmentOverrides
        let runtimeDirectory = runtimeBinDirectory(for: bottle)
        let inheritedPath = env["PATH"] ?? ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"

        env["WINEPREFIX"] = prefix.path
        env["WINEARCH"] = "win64"
        // Pin the Wine username to "crossover" for ALL runtimes so the user
        // home — and therefore every game's save path
        // (drive_c/users/<name>/…) — is identical no matter which Wine the
        // bottle runs on.
        //
        // Why "crossover" specifically (and not, say, "beer"): Apple's
        // GPTK is built on CrossOver's Wine and hardcodes the user "crossover"
        // regardless of $USER. Mainline Wine instead uses the macOS login name.
        // If those differ, switching a bottle's runtime strands its saves in a
        // different users/ folder. We match GPTK's fixed name so saves line up
        // across runtimes with zero migration. This is NOT a CrossOver
        // dependency or endorsement — purely a compatibility constant.
        env["USER"] = "crossover"
        env["USERNAME"] = "crossover"
        env["WINEDLLOVERRIDES"] = dllOverrides(for: bottle.effectiveGraphicsBackend)
        env["WINEDEBUG"] = env["WINEDEBUG"] ?? "-all"
        env["WINEESYNC"] = env["WINEESYNC"] ?? "1"
        env["PATH"] = "\(runtimeDirectory):\(inheritedPath)"

        let libraryPaths = runtimeLibraryDirectories(for: bottle)
        if !libraryPaths.isEmpty {
            let inheritedLibraryPath = env["DYLD_FALLBACK_LIBRARY_PATH"] ?? ProcessInfo.processInfo.environment["DYLD_FALLBACK_LIBRARY_PATH"]
            env["DYLD_FALLBACK_LIBRARY_PATH"] = (libraryPaths + [inheritedLibraryPath].compactMap { $0 })
                .filter { !$0.isEmpty }
                .joined(separator: ":")
        }

        switch bottle.effectiveGraphicsBackend {
        case .d3dMetal:
            env["MTL_HUD_ENABLED"] = env["MTL_HUD_ENABLED"] ?? "0"
        case .dxmt:
            env["DXMT_CONFIG"] = env["DXMT_CONFIG"] ?? "hud=0"
            if let unix = dxmtUnixLibDirectory() {
                let existing = env["WINEDLLPATH"].map { "\($0):" } ?? ""
                env["WINEDLLPATH"] = existing + unix
            }
        case .dxvk:
            env["DXVK_HUD"] = env["DXVK_HUD"] ?? "0"
            // Lets MoltenVK use Metal's private API so it can disable primitive
            // restart (and other features DXVK needs) — without this, pipelines
            // fail with "Metal does not support disabling primitive restart".
            env["MVK_CONFIG_USE_METAL_PRIVATE_API"] = env["MVK_CONFIG_USE_METAL_PRIVATE_API"] ?? "1"
        case .automatic, .wineD3D:
            break
        }

        return env
    }

    private func runtimeBinDirectory(for bottle: Bottle) -> String {
        if let runtimeBundlePath = bottle.runtimeBundlePath {
            return URL(fileURLWithPath: runtimeBundlePath, isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .path
        }

        return URL(fileURLWithPath: runtimeWinePath(for: bottle))
            .deletingLastPathComponent()
            .path
    }

    private func runtimeLibraryDirectories(for bottle: Bottle) -> [String] {
        var candidates: [URL] = []

        if let runtimeBundlePath = bottle.runtimeBundlePath {
            let bundleURL = URL(fileURLWithPath: runtimeBundlePath, isDirectory: true)
            candidates.append(bundleURL.appendingPathComponent("lib", isDirectory: true))
            candidates.append(bundleURL.appendingPathComponent("Frameworks", isDirectory: true))
        }

        let executableURL = URL(fileURLWithPath: runtimeWinePath(for: bottle))
        let binDirectory = executableURL.deletingLastPathComponent()
        let wineRoot = binDirectory.deletingLastPathComponent()
        candidates.append(wineRoot.appendingPathComponent("lib", isDirectory: true))
        candidates.append(wineRoot.appendingPathComponent("lib/external", isDirectory: true))
        candidates.append(wineRoot.appendingPathComponent("Frameworks", isDirectory: true))

        var seen: Set<String> = []
        return candidates
            .map(\.path)
            .filter { FileManager.default.fileExists(atPath: $0) }
            .filter { seen.insert($0).inserted }
    }

    private func dllOverrides(for backend: GraphicsBackend) -> String {
        switch backend {
        case .automatic: ""
        case .d3dMetal: "d3d12,d3d11,dxgi=n,b"
        case .dxmt: "d3d11,d3d10core,dxgi,winemetal=n,b"
        case .dxvk: "dxgi,d3d11,d3d10core,d3d9=n,b"
        case .wineD3D: "d3d11,dxgi,d3d12=b"
        }
    }

    /// DXMT ships a host-side `winemetal.so`; point Wine at it via WINEDLLPATH
    /// so it loads alongside the winemetal.dll we copied into the prefix.
    private func dxmtUnixLibDirectory() -> String? {
        let root = AppPaths.translatorsDirectory.appendingPathComponent("DXMT", isDirectory: true)
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let url as URL in e where url.lastPathComponent == "x86_64-unix" {
            return url.path
        }
        return nil
    }

    private func appendLog(_ message: String, bottleID: Bottle.ID, isError: Bool = false) {
        // Drop the MoltenVK boilerplate (it dumps ~150 "VK_KHR_…" extension
        // lines + GPU-feature lines on every device probe) so the log stays
        // readable and copyable. Keep the version/GPU summary lines.
        let filtered = message
            .split(separator: "\n", omittingEmptySubsequences: false)
            .filter { line in
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("VK_") { return false }
                if t == "The following 153 Vulkan extensions are supported:" { return false }
                if t.hasPrefix("GPU Family ") || t == "Read-Write Texture Tier 2" { return false }
                if t == "supports the following GPU Features:" { return false }
                return true
            }
            .joined(separator: "\n")
        let trimmed = filtered.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        logs[bottleID, default: []].append(BottleLogEntry(date: Date(), message: trimmed, isError: isError))
        writeLogLine(trimmed, bottleID: bottleID)
    }

    private func loadPersistedLogs() {
        for bottle in bottles {
            let url = AppPaths.logsURL(for: bottle)
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8),
                  !text.isEmpty else {
                continue
            }

            logs[bottle.id] = text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .suffix(500)
                .map { line in
                    BottleLogEntry(date: Date(), message: String(line), isError: line.localizedCaseInsensitiveContains("error") || line.localizedCaseInsensitiveContains("failed"))
                }
        }
    }

    private func writeLogLine(_ message: String, bottleID: Bottle.ID) {
        guard let bottle = bottles.first(where: { $0.id == bottleID }) else { return }
        let line = "[\(Date.formattedLogDate)] \(message)\n"
        let url = AppPaths.logsURL(for: bottle)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private func save() async {
        do {
            try AppPaths.ensureBaseDirectories()
            let data = try JSONEncoder.gamenative.encode(bottles)
            try data.write(to: AppPaths.metadataURL, options: .atomic)
        } catch {
            lastError = "Could not save bottles: \(error.localizedDescription)"
        }
    }
}

private enum BottleCommandMode {
    case wineboot
    case winebootKill
    case wine(arguments: [String])
}

private struct BottleCommand {
    let executable: String
    let arguments: [String]
}

private extension JSONEncoder {
    static var gamenative: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var gamenative: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension Date {
    static var formattedLogDate: String {
        ISO8601DateFormatter().string(from: Date())
    }
}
