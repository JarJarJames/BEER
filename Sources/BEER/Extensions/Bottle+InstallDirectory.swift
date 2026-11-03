import Foundation

extension Bottle {
    /// The game's folder, when it can be used right now. Nil while its drive is
    /// unplugged or the folder is gone; `installLocation` says which.
    var resolvedInstallDirectory: URL? {
        installLocation().url
    }

    /// Where the game's files are right now.
    ///
    /// A game on a drive is only `.available` when the folder is on that very
    /// drive, checked by the drive's ID. A folder at the old path that isn't on
    /// it (another drive mounted under the same name, or a leftover folder in
    /// /Volumes) is not the game.
    func installLocation(volumes: VolumeCatalog = .system) -> InstallLocation {
        if let drive = gameDrive {
            return location(onDrive: drive, volumes: volumes)
        }
        if let stored = gameInstallDirectory {
            let url = URL(fileURLWithPath: stored)
            if FileManager.default.directoryExists(at: url) { return .available(url) }
        }
        // Bottles from before the install directory was stored (like the
        // user's KCD) walk up from the .exe to the folder inside "Games".
        guard let exe = gameLaunchExecutable else { return .missing }
        var current = URL(fileURLWithPath: exe).deletingLastPathComponent()
        for _ in 0..<12 {
            if current.deletingLastPathComponent().lastPathComponent == "Games" {
                return FileManager.default.directoryExists(at: current) ? .available(current) : .missing
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }   // hit /
            current = parent
        }
        return .missing
    }

    private func location(onDrive drive: GameDrive, volumes: VolumeCatalog) -> InstallLocation {
        guard let stored = gameInstallDirectory else { return .missing }
        let url = URL(fileURLWithPath: stored)
        if FileManager.default.directoryExists(at: url), volumes.volumeUUID(url) == drive.uuid {
            return .available(url)
        }
        guard let mounted = volumes.drive(withUUID: drive.uuid) else {
            return .driveMissing(driveName: drive.name)
        }
        // Renamed since: same drive, new mount point.
        if let moved = drive.rebase(stored, onto: mounted.root).map(URL.init(fileURLWithPath:)),
           FileManager.default.directoryExists(at: moved) {
            return .available(moved)
        }
        return .missing
    }

    /// Point the stored paths at where the game's drive is mounted now, after
    /// it was renamed. Returns whether anything changed.
    mutating func followRenamedDrive(volumes: VolumeCatalog = .system) -> Bool {
        guard let drive = gameDrive, let mounted = volumes.drive(withUUID: drive.uuid) else { return false }
        let newRoot = mounted.root.standardizedFileURL
        guard newRoot.path != URL(fileURLWithPath: drive.mountPath).standardizedFileURL.path
                || mounted.name != drive.name else { return false }
        if let dir = gameInstallDirectory, let moved = drive.rebase(dir, onto: newRoot) {
            gameInstallDirectory = moved
        }
        if let exe = gameLaunchExecutable, let moved = drive.rebase(exe, onto: newRoot) {
            gameLaunchExecutable = moved
        }
        gameDrive = GameDrive(uuid: drive.uuid, name: mounted.name, mountPath: newRoot.path)
        return true
    }

    /// Rename a game folder in a `Games` folder whose name Wine can't open
    /// (see `windowsFolderName`), and point the stored paths at the new name.
    /// Earlier builds named folders after the game, trailing dot and all.
    /// Returns whether anything changed; nothing does when the new name is
    /// already taken.
    mutating func renameFolderWineCannotOpen(volumes: VolumeCatalog = .system) throws -> Bool {
        guard let folder = installLocation(volumes: volumes).url,
              folder.deletingLastPathComponent().lastPathComponent == "Games" else { return false }
        let fixedName = folder.lastPathComponent.windowsFolderName
        guard !fixedName.isEmpty, fixedName != folder.lastPathComponent else { return false }
        let fixed = folder.deletingLastPathComponent().appendingPathComponent(fixedName, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: fixed.path) else { return false }

        try FileManager.default.moveItem(at: folder, to: fixed)
        if let exe = gameLaunchExecutable {
            gameLaunchExecutable = GameFolderTransfer.relocated(URL(fileURLWithPath: exe), from: folder, to: fixed).path
        }
        gameInstallDirectory = fixed.path
        return true
    }

    /// Where the game's files go when downloading into this bottle: the folder
    /// an earlier install or unfinished download recorded, so a resume picks up
    /// where it stopped, else the default inside the bottle.
    func downloadDirectory(gameName: String) -> URL {
        gameInstallDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? AppPaths.gameInstallDirectory(for: self, gameName: gameName)
    }
}
