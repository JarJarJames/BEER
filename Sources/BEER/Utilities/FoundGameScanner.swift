import Foundation

/// Looks through a drive's `BEER/Games` for game folders no bottle uses.
enum FoundGameScanner {
    /// Folders with a `.beer-game.json` that no bottle points at. Folders
    /// without one aren't offered: nothing says which game they hold.
    /// `ownedAppIDs` is the signed-in account's Steam library;
    /// `installedAppIDs` the Steam games that already have a bottle.
    static func scan(
        _ drive: InstallVolume, bottles: [Bottle], ownedAppIDs: Set<Int>, installedAppIDs: Set<Int>,
        volumes: VolumeCatalog
    ) -> [FoundGame] {
        let games = AppPaths.driveGamesDirectory(onDriveAt: drive.root)
        // A drive without BEER's folder simply has nothing to offer.
        guard let folders = try? FileManager.default.contentsOfDirectory(
            at: games, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else { return [] }

        let used = Set(bottles.flatMap { bottle -> [String] in
            let stored = bottle.gameInstallDirectory.map { GameFolders.canonicalPath(URL(fileURLWithPath: $0)) }
            let current = bottle.installLocation(volumes: volumes).url.map(GameFolders.canonicalPath)
            return [stored, current].compactMap { $0 }
        })

        return folders
            .filter { FileManager.default.directoryExists(at: $0) && !$0.lastPathComponent.hasSuffix(GameFolders.stagingSuffix) }
            .filter { !used.contains(GameFolders.canonicalPath($0)) }
            .compactMap { folder -> FoundGame? in
                guard let marker = GameFolderMarkerFile.read(in: folder) else { return nil }
                let exe = launchExecutable(in: folder, marker: marker)
                return FoundGame(
                    folder: folder, marker: marker, drive: drive, launchExecutable: exe,
                    blockedReason: blockedReason(marker, exe: exe, owned: ownedAppIDs, installed: installedAppIDs)
                )
            }
            .sorted { $0.marker.name.localizedCaseInsensitiveCompare($1.marker.name) == .orderedAscending }
    }

    /// The .exe the game file names, else the one BEER would pick on install.
    static func launchExecutable(in folder: URL, marker: GameFolderMarker) -> URL? {
        if let relative = marker.launchExecutable {
            let exe = folder.appendingPathComponent(relative)
            if FileManager.default.fileExists(atPath: exe.path) { return exe }
        }
        return LaunchExecutableFinder.find(in: folder, gameName: marker.name)
    }

    private static func blockedReason(_ marker: GameFolderMarker, exe: URL?, owned: Set<Int>, installed: Set<Int>) -> String? {
        if let appID = marker.appID, !marker.isNonSteam {
            if !owned.contains(appID) { return FoundGamesStrings.notOwned }
            if installed.contains(appID) { return FoundGamesStrings.alreadyInstalled }
        }
        if exe == nil { return FoundGamesStrings.noExecutable }
        return nil
    }
}
