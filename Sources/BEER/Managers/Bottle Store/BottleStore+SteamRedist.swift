import Foundation

extension BottleStore {
    /// Run the redistributable installers Steam runs on a game's first launch.
    /// DepotDownloader already fetches the redist depots a game lists (VC++,
    /// DirectX, PhysX, …) into `_CommonRedist`, each with Steam's own
    /// `installscript.vdf`; without this they sat there unused, and a game
    /// like Kenshi died at startup on a missing `mfc100u.dll`.
    ///
    /// Each entry runs once per bottle. One that fails is logged and retried
    /// next launch, and the game launches regardless: a missing DLL in the log
    /// says more than a launch that refuses to start.
    func installSteamRedistributables(_ bottle: Bottle) async {
        guard let installDirectory = bottle.resolvedInstallDirectory else { return }
        let prefix = AppPaths.prefixURL(for: bottle)
        let receiptURL = prefix.appendingPathComponent(SteamRedist.receiptFileName)
        // No receipt yet just means nothing has run.
        var completed = SteamRedist.parseReceipt((try? String(contentsOf: receiptURL, encoding: .utf8)) ?? "")
        let completedBefore = completed

        for scriptPath in SteamRedist.installScripts(in: installDirectory) where !SteamRedist.isSkipped(scriptPath) {
            let scriptURL = installDirectory.appendingPathComponent(scriptPath)
            guard let text = attempt("Read install script", log: Log.install, {
                try String(contentsOf: scriptURL, encoding: .utf8)
            }) else { continue }

            let script = SteamInstallScript(parsing: text, installDirectory: SteamRedist.windowsPath(installDirectory))
            let pending = script.runProcesses.filter {
                !completed.contains(SteamRedist.receiptID(for: $0, scriptPath: scriptPath))
            }
            guard !pending.isEmpty else { continue }

            let vcYear = SteamRedist.vcRedistYear(ofScript: scriptPath)
            if let vcYear {
                attempt("Clear Wine's VC++ placeholders", log: Log.install) {
                    try WindowsDependencyInstaller.removeWinePlaceholders(
                        WindowsDependencyManifest.steamVCPlaceholderDLLs(year: vcYear), inPrefix: prefix
                    )
                }
            }

            for process in pending where await runRedistProcess(process, scriptPath: scriptPath, bottle: bottle) {
                completed.insert(SteamRedist.receiptID(for: process, scriptPath: scriptPath))
            }

            if let vcYear {
                let dlls = WindowsDependencyManifest.steamVCRuntimeDLLs(year: vcYear)
                if !dlls.isEmpty { await applyNativeDLLOverrides(dlls, to: bottle) }
            }
        }

        if completed != completedBefore {
            attempt("Write Steam redist receipt", log: Log.install) {
                try SteamRedist.receipt(completed).write(to: receiptURL, atomically: true, encoding: .utf8)
            }
        }
    }

    /// Run one `Run Process` entry's commands in order, from the script's
    /// folder. True when every command finished with a success code.
    private func runRedistProcess(_ process: SteamInstallScript.RunProcess, scriptPath: String, bottle: Bottle) async -> Bool {
        for command in process.commands {
            let exitCode = await runBottleCommand(
                bottle,
                operation: "Installing \((scriptPath as NSString).deletingLastPathComponent) (\(process.name))",
                mode: .wine(arguments: [command.executable] + command.arguments)
            )
            // MSI work continues after the bootstrapper returns.
            await waitForWineSessionExit(bottle)
            guard let exitCode, SteamRedist.successExitCodes.contains(exitCode) else { return false }
        }
        return true
    }

    /// Set `dlls` to native-then-builtin by importing a `.reg` file, so the
    /// Microsoft runtime an installer just put down is the one that loads.
    /// True when regedit succeeded.
    @discardableResult
    func applyNativeDLLOverrides(_ dlls: [String], to bottle: Bottle) async -> Bool {
        let name = "beer-dll-overrides.reg"
        let file = AppPaths.prefixURL(for: bottle)
            .appendingPathComponent(WindowsDependencyInstaller.prefixTempPath)
            .appendingPathComponent(name)
        let written = attempt("Write DLL override file", log: Log.install) {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try WindowsDependencyInstaller.dllOverrideRegistry(dlls).write(to: file, atomically: true, encoding: .utf8)
        }
        guard written != nil else { return false }
        defer { attempt("Remove DLL override file", log: Log.install) { try FileManager.default.removeItemIfPresent(at: file) } }

        let exitCode = await runBottleCommand(
            bottle,
            operation: "Setting DLL overrides",
            mode: .wine(arguments: ["regedit", "/S", WindowsDependencyInstaller.windowsTempPath + #"\"# + name])
        )
        await waitForWineSessionExit(bottle)
        return exitCode == 0
    }
}
