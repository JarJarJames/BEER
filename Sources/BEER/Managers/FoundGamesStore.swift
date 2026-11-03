import Foundation

/// Games on connected drives that aren't in BEER, offered in a banner above
/// the library, and adding the ones the player picks.
@MainActor
final class FoundGamesStore: ObservableObject {
    @Published private(set) var found: [FoundGame] = []
    /// Drives whose banner the player closed, until BEER restarts.
    @Published private(set) var dismissedDriveIDs: Set<String> = []
    @Published private(set) var isAdding = false
    @Published var errors: [String] = []

    var volumes: VolumeCatalog = .system
    /// Bumped by each scan, so a slow one finishing after a newer one can't
    /// put back games the newer one knew were added.
    private var scanGeneration = 0

    /// Found games grouped by drive, without the drives the player dismissed.
    var byDrive: [(drive: InstallVolume, games: [FoundGame])] {
        let visible = found.filter { !dismissedDriveIDs.contains($0.drive.id) }
        let drives = visible.map(\.drive).reduce(into: [InstallVolume]()) { list, drive in
            if !list.contains(where: { $0.id == drive.id }) { list.append(drive) }
        }
        return drives.map { drive in (drive, visible.filter { $0.drive.id == drive.id }) }
    }

    func dismiss(driveID: String) {
        dismissedDriveIDs.insert(driveID)
    }

    /// Look again, after a drive was connected or a game added or removed.
    ///
    /// Skipped while games are being added: a bottle exists before it knows
    /// its folder, so a scan then would offer the game being added again.
    /// `add`'s caller scans once it's done.
    func scan(drives: [InstallVolume], bottles: [Bottle], library: [SteamLibraryGame]) async {
        guard !isAdding else { return }
        scanGeneration += 1
        let generation = scanGeneration
        let owned = Set(library.filter { !$0.effectiveIsNonSteam }.map(\.appID))
        let installed = Set(bottles.compactMap(\.steamAppID))
        let volumes = volumes
        let usable = drives.filter { $0.isListed && $0.unsupportedReason == nil }
        // Reads every candidate folder, and may look for its .exe.
        let result = await Task.detached {
            usable.flatMap {
                FoundGameScanner.scan($0, bottles: bottles, ownedAppIDs: owned, installedAppIDs: installed, volumes: volumes)
            }
        }.value
        guard generation == scanGeneration, !isAdding else { return }
        found = result
    }

    /// Give each game a bottle that uses its folder where it is.
    func add(_ games: [FoundGame], runtime: RuntimeCandidate, bottles: BottleStore, library: SteamLibraryStore) async {
        scanGeneration += 1   // a scan already running is out of date
        isAdding = true
        defer { isAdding = false }
        errors = []
        for game in games where game.canAdd {
            guard let exe = game.launchExecutable, let drive = game.drive.link else { continue }
            // The drive may have gone while the sheet was open.
            guard GameFolders.isConnected(drive, volumes: volumes) else {
                errors.append(FoundGamesStrings.addFailed(game.marker.name, InstallDriveStrings.driveNotConnected(drive.name)))
                continue
            }
            let bottle = await bottles.createBottle(name: game.marker.name, runtime: runtime, graphicsBackend: .automatic)
            if let appID = game.marker.appID, !game.marker.isNonSteam {
                await bottles.recordGameInstall(
                    bottle, appID: appID, gameName: game.marker.name, launchExecutable: exe.path,
                    launchArguments: nil, installDirectory: game.folder.path, drive: drive,
                    // Checked against Steam's launch options on first play.
                    steamLaunchConfigChecked: false
                )
                library.markInstalled(appID: appID, bottleID: bottle.id)
            } else {
                await bottles.recordNonSteamInstall(bottle, launchExecutable: exe.path,
                                                    installDirectory: game.folder.path, drive: drive)
                library.addNonSteamGame(name: game.marker.name, bottleID: bottle.id, customImagePath: nil)
            }
        }
        found.removeAll { added in games.contains { $0.id == added.id && $0.canAdd } }
    }
}
