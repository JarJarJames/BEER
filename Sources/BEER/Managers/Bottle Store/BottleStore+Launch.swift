import AppKit
import Foundation

extension BottleStore {
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
    func prepareControllerFix(_ bottle: Bottle, executable: String) async -> Process? {
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
    func withTimeout<T: Sendable>(seconds: Double, _ work: @escaping @Sendable () -> T) async -> T? {
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
    func runtimeHidURL(for bottle: Bottle) -> URL? {
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
    func configureControllers(_ bottle: Bottle) async {
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
    func configureDisplayMode(_ bottle: Bottle) async {
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
    func waitForWineSessionExit(_ bottle: Bottle) async {
        guard let wineserver = runtimeWineserverPath(for: bottle) else { return }

        await runBottleCommand(
            bottle,
            operation: "Waiting for previous Wine session to exit",
            mode: .executable(path: wineserver, arguments: ["-w"])
        )
    }
}
