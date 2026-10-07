import AppKit
import Foundation

@MainActor
final class BottleStore: ObservableObject {
    @Published private(set) var bottles: [Bottle] = []
    @Published private(set) var logs: [Bottle.ID: [BottleLogEntry]] = [:]
    @Published private(set) var activeBottleIDs: Set<Bottle.ID> = []
    @Published var lastError: String?

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

            loadPersistedLogs()
        } catch {
            lastError = "Could not load bottles: \(error.localizedDescription)"
        }
    }

    @discardableResult
    func createBottle(name: String, runtime: RuntimeCandidate, graphicsBackend: GraphicsBackend) async -> Bottle {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let bottle = Bottle.make(name: trimmed.isEmpty ? "Game" : trimmed, runtime: runtime, graphicsBackend: graphicsBackend)
        bottles.insert(bottle, at: 0)
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

    /// Launch a specific .exe (Wine-style path like `C:\Games\Hades\x64\Hades.exe`)
    /// inside the bottle's prefix. Used by the per-game Library flow once
    /// the game is installed.
    ///
    /// We run the game's .exe directly (no `wine explorer /desktop` wrapper).
    /// `configureDisplayMode` applies the selected Wine Mac driver resolution
    /// mode before the game starts.
    func launchGameExecutable(_ bottle: Bottle, executable: String, arguments: String? = nil) async {
        resetLog(for: bottle, reason: "Launching \(bottle.steamGameName ?? bottle.name)")
        await configureControllers(bottle)
        let controllerHelper = await prepareControllerFix(bottle, executable: executable)
        await configureDisplayMode(bottle)

        var args: [String] = [executable]
        if let arguments, !arguments.isEmpty {
            args.append(contentsOf: arguments.split(separator: " ").map(String.init))
        }
        // Run the game from its own folder. Windows starts an executable with
        // its directory as the working directory — that is what Explorer and
        // Steam do — and games routinely open their data by relative path.
        // Without this they inherit BEER's working directory and simply cannot
        // find their own assets, which surfaces as a crash deep inside the
        // game's resource loader rather than as a missing-file error.
        let gameDirectory = URL(fileURLWithPath: executable).deletingLastPathComponent()
        let launchDirectory = FileManager.default.fileExists(atPath: gameDirectory.path)
            ? gameDirectory
            : nil

        await runBottleCommand(
            bottle,
            operation: "Launching \(bottle.steamGameName ?? bottle.name)",
            mode: .wine(arguments: args),
            workingDirectory: launchDirectory
        )

        // The launched .exe returning is not the end of play. Plenty of games
        // hand off to a child process and exit immediately, and the bottle is
        // BEER's real unit of work — so play is over when the prefix goes idle,
        // not when the one process we happened to spawn returns.
        //
        // Three things hang off getting this boundary right: the play time we
        // record, the post-play cloud push (which could otherwise start
        // uploading saves the game was still writing), and the controller
        // helper below, which would otherwise be killed out from under a game
        // that is still running.
        await waitForWineSessionExit(bottle)

        // The helper only exists to feed the running game; it has no reason to
        // outlive it, and leaving it behind would hold the pad open.
        controllerHelper?.terminate()
    }

    /// Set up the opt-in controller fix, returning the macOS-side helper so the
    /// caller can stop it when the game exits. A failure here is logged and the
    /// game still launches — a broken D-pad beats refusing to start.
    ///
    /// Everything here — IOHID enumeration, spawning `dpad_helper` — runs on
    /// this @MainActor class, i.e. the main thread. HID enumeration against a
    /// Bluetooth pad has been observed to stall indefinitely, which froze the
    /// whole app stone dead before Wine ever started (nothing after it in
    /// beer.log, no wine process spawned). `withTimeout` below caps that risk
    /// so a stuck HID/helper call degrades to "no controller fix this launch"
    /// instead of taking the app down with it.
    private func prepareControllerFix(_ bottle: Bottle, executable: String) async -> Process? {
        guard bottle.effectiveControllerFix else { return nil }

        guard let identifiers = await withTimeout(seconds: 3, { ControllerSupport.connectedDeviceIdentifiers() }),
              let device = identifiers.first else {
            appendLog("Controller fix enabled but no gamepad is connected.", bottleID: bottle.id)
            return nil
        }

        do {
            try ControllerSupport.installShim(
                forExecutable: executable,
                runtimeHid: runtimeHidURL(for: bottle)
            )
        } catch {
            appendLog(
                "Controller fix unavailable: \(error.localizedDescription)",
                bottleID: bottle.id,
                isError: true
            )
            return nil
        }

        let prefix = AppPaths.prefixURL(for: bottle)
        let helperResult = await withTimeout(seconds: 3) { ControllerSupport.startHelper(prefix: prefix, device: device) }
        guard let helper = helperResult ?? nil else {
            appendLog("Controller fix helper failed to start.", bottleID: bottle.id, isError: true)
            return nil
        }

        appendLog("Controller fix active for \(device).", bottleID: bottle.id)
        return helper
    }

    /// Runs `work` on a background thread with a hard deadline, returning
    /// `nil` if it hasn't finished by `seconds`. `work` itself is abandoned,
    /// not cancelled — this only stops it from blocking the caller, which is
    /// enough for the controller-fix path: everything it guards is optional
    /// and already designed to no-op cleanly on `nil`.
    private func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { work() as T? }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }

    /// Wine's own hid.dll, which the shim forwards all but two exports to.
    private func runtimeHidURL(for bottle: Bottle) -> URL? {
        let wineRoot = URL(fileURLWithPath: runtimeWinePath(for: bottle))
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        let candidates = [
            wineRoot.appendingPathComponent("lib/wine/x86_64-windows/hid.dll"),
            wineRoot.appendingPathComponent("lib64/wine/x86_64-windows/hid.dll")
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Register the Mac's connected gamepads with Wine's HID bus driver, which
    /// otherwise drops them and leaves every game reporting no controller. See
    /// `ControllerSupport` for why this is needed at all.
    ///
    /// The list is rewritten on every launch so it tracks whatever is plugged in
    /// now, and runs *before* `configureDisplayMode` so the `wineboot -k` at the
    /// end of that call restarts the bus driver onto the new value.
    private func configureControllers(_ bottle: Bottle) async {
        guard let identifiers = await withTimeout(seconds: 3, { ControllerSupport.connectedDeviceIdentifiers() }),
              !identifiers.isEmpty else { return }

        await runBottleCommand(
            bottle,
            operation: "Configuring controllers",
            mode: .wine(arguments: [
                "reg", "add", #"HKLM\System\CurrentControlSet\Services\winebus"#,
                "/v", "EnableHidraw", "/t", "REG_SZ",
                "/d", identifiers.joined(separator: ","), "/f"
            ])
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

        // The bottle's Windows version. `winecfg /v` writes the whole set of
        // version registry values (HKLM product name, build number, CSD) that a
        // hand-rolled `reg add` would have to know, and it runs headless.
        //
        // This is also the audio fix for SDL games that crackle on WASAPI: SDL
        // only reaches for WASAPI on Vista and newer, so reporting winxp drops
        // it onto DirectSound.
        let winver = bottle.windowsVersion.trimmingCharacters(in: .whitespaces)
        if !winver.isEmpty {
            await runBottleCommand(
                bottle,
                operation: "Configuring Windows version (\(winver))",
                mode: .wine(arguments: ["winecfg", "/v", winver])
            )
        }

        // These values are process-wide. Ensure the game starts in a fresh Wine
        // session instead of inheriting the mode used by the registry commands.
        await runBottleCommand(
            bottle,
            operation: "Restarting Wine display services",
            mode: .winebootKill
        )
        await waitForWineSessionExit(bottle)
    }

    /// Block until the prefix's previous Wine session is really gone.
    ///
    /// `wineboot -k` only *requests* shutdown — it returns while wineserver and
    /// winedevice are still tearing down. Launching a game into that window
    /// leaves the new session's `winebus` unable to claim the Mac's HID devices
    /// from the dying one, and it gives up: the game then runs with no
    /// controllers at all, for its whole lifetime, even though XInput is
    /// otherwise healthy. `wineserver -w` waits for the old session to exit.
    ///
    /// Without a preceding kill this returns immediately, so it is cheap.
    private func waitForWineSessionExit(_ bottle: Bottle) async {
        guard let wineserver = runtimeWineserverPath(for: bottle) else { return }

        await runBottleCommand(
            bottle,
            operation: "Waiting for previous Wine session to exit",
            mode: .executable(path: wineserver, arguments: ["-w"])
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

    func stopBottleProcesses(_ bottle: Bottle) async {
        await runBottleCommand(
            bottle,
            operation: "Stopping bottle processes",
            mode: .winebootKill,
            allowWhileActive: true
        )
    }

    func reveal(_ bottle: Bottle) {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.prefixURL(for: bottle)])
    }

    func revealLog(_ bottle: Bottle) {
        NSWorkspace.shared.activateFileViewerSelecting([AppPaths.logsURL(for: bottle)])
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
            await save()
        } catch {
            lastError = "Could not delete bottle: \(error.localizedDescription)"
        }
    }

    /// The store's current copy of `bottle`, or `bottle` itself if it has been
    /// removed. Views and long-running tasks hold a snapshot that goes stale
    /// while they work; this names that fact instead of re-deriving it.
    func live(_ bottle: Bottle) -> Bottle {
        bottles.first { $0.id == bottle.id } ?? bottle
    }

    func update(_ bottle: Bottle) async {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        var updated = bottle
        updated.updatedAt = Date()
        bottles[index] = updated
        await save()
    }

    /// Schedule a control-originated mutation for the next main run-loop turn.
    /// SwiftUI may invoke Picker bindings while it is still updating the view;
    /// publishing synchronously from that setter causes undefined behavior.
    func scheduleMutation(
        bottleID: UUID,
        _ apply: @escaping @MainActor @Sendable (inout Bottle) -> Void
    ) {
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self,
                  let index = self.bottles.firstIndex(where: { $0.id == bottleID }) else { return }
            var copy = self.bottles[index]
            apply(&copy)
            copy.updatedAt = Date()
            self.bottles[index] = copy
            Task { await self.save() }
        }
    }

    private func runBottleCommand(
        _ bottle: Bottle,
        operation: String,
        mode: BottleCommandMode,
        allowWhileActive: Bool = false,
        environmentOverrides: [String: String] = [:],
        workingDirectory: URL? = nil
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
                currentDirectory: workingDirectory,
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
            case .executable:
                break
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
            case .executable:
                break
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
        case .executable(let path, let arguments):
            return BottleCommand(executable: path, arguments: arguments)
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
        env["WINEDLLOVERRIDES"] = dllOverrides(
            for: bottle.effectiveGraphicsBackend,
            controllerFix: bottle.effectiveControllerFix,
            userOverrides: bottle.environmentOverrides["WINEDLLOVERRIDES"]
        )
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

    /// DLL overrides for a launch: the graphics backend's translator DLLs, the
    /// GameInput preference, then whatever the bottle's own environment asks
    /// for — the user's entry goes last so it wins any conflict. (Previously
    /// this value overwrote `environmentOverrides["WINEDLLOVERRIDES"]`, so a
    /// user override was silently discarded.)
    private func dllOverrides(for backend: GraphicsBackend, controllerFix: Bool, userOverrides: String?) -> String {
        var entries: [String] = []

        switch backend {
        case .automatic: break
        case .d3dMetal: entries.append("d3d12,d3d11,dxgi=n,b")
        case .dxmt: entries.append("d3d11,d3d10core,dxgi,winemetal=n,b")
        case .dxvk: entries.append("dxgi,d3d11,d3d10core,d3d9=n,b")
        case .wineD3D: entries.append("d3d11,dxgi,d3d12=b")
        }

        // Prefer native input DLLs when a bottle has them beside the executable.
        // Both are "n,b", so a bottle without them falls back to Wine's builtins
        // and nothing changes.
        //
        // gameinput: Wine's builtin is a stub whose GameInputCreate returns
        // E_NOTIMPL, so GDK-era titles that detect controllers through GameInput
        // (Kingdom Come: Deliverance II, Stalker 2) report zero pads.
        //
        entries.append("gameinput=n,b")

        // hid: only when the per-game controller fix is on, so a bottle that
        // does not need it never loads the shim — see ControllerSupport.
        if controllerFix { entries.append("hid=n,b") }

        if let userOverrides, !userOverrides.isEmpty { entries.append(userOverrides) }
        return entries.joined(separator: ";")
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
    /// A runtime helper binary invoked directly (e.g. `wineserver -w`).
    case executable(path: String, arguments: [String])
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
