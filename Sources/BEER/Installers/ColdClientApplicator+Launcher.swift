import Foundation

// Some games start through a launcher that isn't wrapped, which then starts
// the game's real exe itself: Fallout4Launcher.exe starts Fallout4.exe with
// ShellExecute. BEER runs the launcher, so the loader never sees the exe
// SteamStub wraps, and that exe quits for want of a running Steam.
//
// So the launcher is started by BEER's beer_launch.exe, which loads
// beer_launch_hook.dll into it (Tools/WindowsHelpers). The hook sends the
// launcher's start of the game to the loader `prepare` laid out for it, which
// starts the game where it is, under its own name: mods that look for
// Fallout4.exe by name find it. Nothing in the game's folder is renamed.
//
// The loader can't wrap the launcher itself: when the launcher exits, it puts
// Steam's registry entries back, out from under the game it just started.
// Wine has no Image File Execution Options to catch the start either.

extension ColdClientApplicator {
    /// The exe beside `launcher` that SteamStub wraps, which the launcher
    /// starts itself. Nil when there's none.
    static func wrappedGame(beside launcher: URL) -> URL? {
        let folder = launcher.deletingLastPathComponent()
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.sorted()
            .filter { $0.lowercased().hasSuffix(".exe") && $0.caseInsensitiveCompare(launcher.lastPathComponent) != .orderedSame }
            .map { folder.appendingPathComponent($0) }
            .first { PortableExecutable(contentsOf: $0)?.isSteamStubWrapped == true }
    }

    /// Lay out beer_launch.exe to start `launcher` with its start of `game`
    /// sent to `gameLoader` (what `prepare` returned for `game`). Returns the
    /// .exe to launch in the launcher's place.
    static func prepareLauncher(_ launcher: URL, game: URL, gameLoader: URL, installDir: URL, helpers: URL) throws -> URL {
        let folder = installDir.appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in [WindowsHelpers.launcher, WindowsHelpers.launchHook] {
            let destination = folder.appendingPathComponent(name)
            if !isSameFile(destination, as: helpers.appendingPathComponent(name)) {
                try FileManager.default.removeItemIfPresent(at: destination)
                try FileManager.default.copyItem(at: helpers.appendingPathComponent(name), to: destination)
            }
        }
        guard let launcherPath = windowsPath(of: launcher, relativeTo: installDir) else {
            throw GoldbergPatchError.unreadableInstallDir(installDir.path)
        }
        try launchConfiguration(launcher: launcherPath, game: game.lastPathComponent, gameLoader: gameLoader.lastPathComponent)
            .write(to: folder.appendingPathComponent(WindowsHelpers.launchConfig), atomically: true, encoding: .utf8)
        return folder.appendingPathComponent(WindowsHelpers.launcher)
    }

    /// Paths are relative to the folder beer_launch.exe sits in.
    static func launchConfiguration(launcher: String, game: String, gameLoader: String) -> String {
        """
        launch=..\\\(launcher)
        redirect=\(game)
        to=\(gameLoader)

        """
    }
}
