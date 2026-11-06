import Foundation

// ColdClientApplicator starts games that the `steam_api.dll` stub alone
// (see GoldbergApplicator) can't satisfy, through gbe_fork's steamclient build
// and its loader, ColdClientLoader. The loader registers the emulator's
// steamclient.dll as the running Steam, then starts the game. Three kinds of
// game need it (see SteamClientLoaderPlan):
//   • exes wrapped in SteamStub, which look for a running Steam before the
//     game's own code runs. The loader alone isn't enough for every variant —
//     Isaac's still fails with "Application load error 3:0000065432" — so
//     gbe_fork's steamclient_extra dll is injected to patch it in memory.
//   • Steam2-era games built on `Steam.dll`. gbe_fork's steam_old_lib README
//     injects its stand-in with ForceInjectSteamClient=1.
//   • games with no steam_api.dll that load Steam's client library directly.
// A launcher that starts one of these itself gets its start sent through the
// loader (see ColdClientApplicator+Launcher). With a script extender installed,
// the loader also loads BEER's starter for it (see ScriptExtender).
// Per README.experimental_steamclient.md, the loader also wants
// GameOverlayRenderer(64).dll on disk, and its settings beside steamclient.dll.
//
// Everything goes in one folder at the install root, so Restore can remove it
// whole, and no game file is touched. A game's own patched steam_api.dll stays
// as it is, so DLC, identity and achievements work exactly as without it.

enum ColdClientApplicator {
    static let folderName = "beer_coldclient"
    static let configFile = "ColdClientLoader.ini"
    static let injectFolder = "extra_dlls"
    static let loadOrderFile = "load_order.txt"
    static let settingsFolder = "steam_settings"

    /// Lay out the loader for `executable` and return the .exe to launch in
    /// its place. Re-run before every launch, so it picks up settings the DLC
    /// manager or a reinstall changed. The emulator's DLLs are ~44 MB, so
    /// ones already in place aren't copied again: rewriting them each launch
    /// took seconds on a USB drive.
    ///
    /// `oldSteamLibrary` is gbe_fork's `steam_old_lib/Steam.dll`, needed only
    /// when the plan injects it. `writeSettings` fills a settings folder for a
    /// game that has none of its own to copy (no steam_api.dll was patched).
    static func prepare(
        executable: URL,
        installDir: URL,
        appID: Int,
        plan: SteamClientLoaderPlan,
        loaderSource: URL,
        oldSteamLibrary: URL? = nil,
        helpers: URL? = WindowsHelpers.directory,
        writeSettings: (URL) throws -> Void = { _ in }
    ) throws -> URL {
        let fm = FileManager.default
        let folder = installDir.appendingPathComponent(folderName, isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        let loaderName = plan.is64Bit ? "steamclient_loader_x64.exe" : "steamclient_loader_x86.exe"
        for name in ["steamclient.dll", "steamclient64.dll", "GameOverlayRenderer.dll", "GameOverlayRenderer64.dll", loaderName] {
            let source = loaderSource.appendingPathComponent(name)
            guard fm.fileExists(atPath: source.path) else {
                if name.hasPrefix("GameOverlayRenderer") { continue }  // recommended, not required
                throw GoldbergPatchError.coldClientMissing(name)
            }
            let destination = folder.appendingPathComponent(name)
            if !isSameFile(destination, as: source) {
                try replaceItem(at: destination, with: source, fileManager: fm)
            }
        }

        // Rebuilt every time, so a plan that no longer injects something
        // doesn't leave it behind. The stub patch "must be injected first".
        let extraFolder = folder.appendingPathComponent(injectFolder, isDirectory: true)
        if fm.fileExists(atPath: extraFolder.path) { try fm.removeItem(at: extraFolder) }
        try fm.createDirectory(at: extraFolder, withIntermediateDirectories: true)
        var loadOrder: [String] = []
        if plan.patchesSteamStub {
            // Only the dll matching the game's bitness: the loader skips a
            // mismatched one anyway.
            let name = plan.is64Bit ? "steamclient_extra_x64.dll" : "steamclient_extra_x86.dll"
            let source = loaderSource.appendingPathComponent(injectFolder).appendingPathComponent(name)
            if fm.fileExists(atPath: source.path) {
                try fm.copyItem(at: source, to: extraFolder.appendingPathComponent(name))
                loadOrder.append(name)
            }
        }
        if plan.injectsOldSteamLibrary {
            guard let oldSteamLibrary, fm.fileExists(atPath: oldSteamLibrary.path) else {
                throw GoldbergPatchError.coldClientMissing("Steam.dll")
            }
            try fm.copyItem(at: oldSteamLibrary, to: extraFolder.appendingPathComponent("Steam.dll"))
            loadOrder.append("Steam.dll")
        }
        // After the stub patch: the extender hooks the game it unwrapped.
        if let prefix = plan.scriptExtender {
            if let helpers {
                try fm.copyItem(at: helpers.appendingPathComponent(WindowsHelpers.scriptExtenderStarter),
                                to: extraFolder.appendingPathComponent(WindowsHelpers.scriptExtenderStarter))
                try "prefix=\(prefix)\n".write(to: extraFolder.appendingPathComponent(WindowsHelpers.scriptExtenderConfig),
                                                atomically: true, encoding: .utf8)
                loadOrder.append(WindowsHelpers.scriptExtenderStarter)
            } else {
                Log.install.error("\(prefix, privacy: .public) is installed, but BEER's Windows helpers aren't (run scripts/build_windows_helpers.sh); the game runs without it.")
            }
        }
        if !loadOrder.isEmpty {
            try (loadOrder.joined(separator: "\n") + "\n")
                .write(to: extraFolder.appendingPathComponent(loadOrderFile), atomically: true, encoding: .utf8)
        }

        // The emulator reads its settings beside steamclient.dll. Reuse the
        // folder GoldbergApplicator wrote beside the game's steam_api.dll, so
        // the loader presents the same app ID and account the game does.
        let settings = folder.appendingPathComponent(settingsFolder, isDirectory: true)
        if let existing = steamSettings(for: executable, in: installDir) {
            try replaceItem(at: settings, with: existing, fileManager: fm)
        } else {
            if fm.fileExists(atPath: settings.path) { try fm.removeItem(at: settings) }
            try writeSettings(settings)
        }

        guard let exePath = windowsPath(of: executable, relativeTo: installDir) else {
            throw GoldbergPatchError.unreadableInstallDir(installDir.path)
        }
        try configuration(executablePath: exePath, appID: appID, plan: plan)
            .write(to: folder.appendingPathComponent(configFile), atomically: true, encoding: .utf8)
        return folder.appendingPathComponent(loaderName)
    }

    /// Remove everything `prepare` wrote. Returns whether there was anything.
    @discardableResult
    static func remove(installDir: URL) throws -> Bool {
        let folder = installDir.appendingPathComponent(folderName, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else { return false }
        try FileManager.default.removeItem(at: folder)
        return true
    }

    /// The loader's .ini. `Exe` is relative to the loader, which lives one
    /// level below the install root. Arguments are passed on the loader's own
    /// command line, which it forwards to the game.
    static func configuration(executablePath: String, appID: Int, plan: SteamClientLoaderPlan) -> String {
        func flag(_ on: Bool) -> Int { on ? 1 : 0 }
        return """
        [SteamClient]
        Exe=..\\\(executablePath)
        ExeRunDir=
        ExeCommandLine=
        AppId=\(appID)
        SteamClientDll=steamclient.dll
        SteamClient64Dll=steamclient64.dll

        [Injection]
        ForceInjectSteamClient=\(flag(plan.injectsOldSteamLibrary))
        ForceInjectGameOverlayRenderer=\(flag(plan.injectsOverlay))
        DllsToInjectFolder=\(injectFolder)
        IgnoreInjectionError=1
        IgnoreLoaderArchDifference=0

        [Persistence]
        Mode=\(flag(plan.staysOpen))

        [Debug]
        ResumeByDebugger=0

        """
    }

    /// `executable`'s path inside the install, with Windows separators.
    static func windowsPath(of executable: URL, relativeTo installDir: URL) -> String? {
        let exe = executable.standardizedFileURL.pathComponents
        let root = installDir.standardizedFileURL.pathComponents
        guard exe.count > root.count, Array(exe.prefix(root.count)) == root else { return nil }
        return exe.dropFirst(root.count).joined(separator: "\\")
    }

    /// The `steam_settings` beside the game's exe, else the first one in the
    /// install outside our own folder.
    private static func steamSettings(for executable: URL, in installDir: URL) -> URL? {
        let fm = FileManager.default
        let besideExe = executable.deletingLastPathComponent().appendingPathComponent(settingsFolder, isDirectory: true)
        if fm.fileExists(atPath: besideExe.path) { return besideExe }
        guard let enumerator = fm.enumerator(at: installDir, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
        for case let url as URL in enumerator {
            if url.lastPathComponent == folderName { enumerator.skipDescendants(); continue }
            if url.lastPathComponent == settingsFolder { return url }
        }
        return nil
    }

    /// Whether `copy` is already `source` as copied before: same size and
    /// modification date, which a copy keeps. A new emulator release changes
    /// both.
    static func isSameFile(_ copy: URL, as source: URL) -> Bool {
        // Read fresh: URL resource values are cached on the URL.
        let fm = FileManager.default
        guard let a = try? fm.attributesOfItem(atPath: copy.path), let b = try? fm.attributesOfItem(atPath: source.path),
              a[.type] as? FileAttributeType == .typeRegular, b[.type] as? FileAttributeType == .typeRegular,
              let size = a[.size] as? Int, let date = a[.modificationDate] as? Date else { return false }
        return size == b[.size] as? Int && date == b[.modificationDate] as? Date
    }

    private static func replaceItem(at destination: URL, with source: URL, fileManager fm: FileManager) throws {
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }
}
