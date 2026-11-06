import AppKit
import Foundation

@MainActor
final class BottleStore: ObservableObject {

    @Published private(set) var bottles: [Bottle] = []

    @Published var logs: [Bottle.ID: [BottleLogEntry]] = [:]

    @Published var activeBottleIDs: Set<Bottle.ID> = []

    @Published var lastError: String?

    /// The mounted drives, for games whose files are on one.
    var volumes: VolumeCatalog = .system

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
            await relinkMovedRuntimes()
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
    ///
    /// The folder the download goes to is recorded now too, so a resume after
    /// a failure (or an unplugged drive) continues there rather than starting
    /// over inside the bottle.
    func claimForSteamApp(_ bottle: Bottle, appID: Int, gameName: String, installDirectory: URL, drive: GameDrive?) async {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[index].steamAppID = appID
        bottles[index].steamGameName = gameName
        bottles[index].gameInstallStatus = .installing
        bottles[index].gameInstallDirectory = installDirectory.path
        bottles[index].gameDrive = drive
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

    /// Record install metadata on a bottle (called by the Library install flow).
    func recordGameInstall(
        _ bottle: Bottle,
        appID: Int,
        gameName: String,
        launchExecutable: String,
        launchArguments: String?,
        installDirectory: String? = nil,
        drive: GameDrive? = nil,
        steamLaunchConfigChecked: Bool = false
    ) async {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[index].steamAppID = appID
        bottles[index].steamGameName = gameName
        bottles[index].gameLaunchExecutable = launchExecutable
        bottles[index].gameInstallDirectory = installDirectory
        bottles[index].gameDrive = drive
        bottles[index].gameInstallStatus = .installed
        bottles[index].steamLaunchConfigChecked = steamLaunchConfigChecked
        if let launchArguments, !launchArguments.isEmpty {
            bottles[index].gameLaunchArguments = launchArguments
        }
        bottles[index].updatedAt = Date()
        await save()
    }

    /// Point an existing install at what Steam's launch config lists, if it
    /// listed something in the install, and remember it has been checked.
    /// Arguments the user already set are kept.
    func recordSteamLaunchConfig(_ bottle: Bottle, target: SteamLaunchResolver.Target?) async {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[index].steamLaunchConfigChecked = true
        if let target {
            bottles[index].gameLaunchExecutable = target.executable.path
            if bottles[index].gameLaunchArguments == nil, !target.arguments.isEmpty {
                bottles[index].gameLaunchArguments = target.arguments
            }
        }
        bottles[index].updatedAt = Date()
        await save()
    }

    /// Record a game the user brought in from a folder (no Steam app behind it).
    func recordNonSteamInstall(_ bottle: Bottle, launchExecutable: String, installDirectory: String, drive: GameDrive? = nil) async {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[index].gameLaunchExecutable = launchExecutable
        bottles[index].gameInstallDirectory = installDirectory
        bottles[index].gameDrive = drive
        bottles[index].gameInstallStatus = .installed
        bottles[index].updatedAt = Date()
        await save()
    }

    /// Delete the bottle, and the game's folder when that's on a connected
    /// drive (see `GameFolders.driveFolderToDelete`). With the drive unplugged
    /// its files stay there, and BEER offers to add them back when it returns.
    func delete(_ bottle: Bottle) async {
        do {
            let driveFolder = GameFolders.driveFolderToDelete(for: bottle, among: bottles, volumes: volumes)
            let url = AppPaths.prefixURL(for: bottle)
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            if let driveFolder {
                try FileManager.default.removeItemIfPresent(at: driveFolder)
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

    /// Point games on a drive at where it's mounted now, after it was renamed.
    func followRenamedDrives() async {
        var changed = false
        for index in bottles.indices where bottles[index].followRenamedDrive(volumes: volumes) {
            changed = true
        }
        if changed { await save() }
    }

    /// Rename game folders Wine can't open (a trailing dot, like
    /// "Easy Delivery Co."). Skips games that are running.
    func renameFoldersWineCannotOpen() async {
        var changed = false
        for index in bottles.indices where !activeBottleIDs.contains(bottles[index].id) {
            let renamed = attempt("Rename game folder for Wine", log: Log.install) {
                try bottles[index].renameFolderWineCannotOpen(volumes: volumes)
            }
            if renamed == true { changed = true }
        }
        if changed { await save() }
    }

    /// Record that the game's files now live at `installDirectory`, after a
    /// move. The launch .exe moves with them.
    func relocateGame(bottleID: UUID, from oldDirectory: URL, to installDirectory: URL, drive: GameDrive?) throws {
        guard let index = bottles.firstIndex(where: { $0.id == bottleID }) else {
            throw GameFolderError.notAGameFolder(installDirectory.path)
        }
        let before = bottles[index]
        if let exe = bottles[index].gameLaunchExecutable {
            bottles[index].gameLaunchExecutable = GameFolderTransfer.relocated(
                URL(fileURLWithPath: exe), from: oldDirectory, to: installDirectory
            ).path
        }
        bottles[index].gameInstallDirectory = installDirectory.path
        bottles[index].gameDrive = drive
        bottles[index].updatedAt = Date()
        do {
            try persist()
        } catch {
            bottles[index] = before
            throw error
        }
    }

    func update(_ bottle: Bottle) async {
        guard let index = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        var updated = bottle
        updated.updatedAt = Date()
        bottles[index] = updated
        await save()
    }

    /// Points bottles whose runtime moved within its Runtimes/ folder at where
    /// it is now, so they keep working. Bottles whose runtime is gone are left
    /// for the player to switch (the game page offers one).
    func relinkMovedRuntimes(in runtimesDirectory: URL = AppPaths.runtimesDirectory) async {
        var changed = false
        for index in bottles.indices {
            guard let runtime = bottles[index].movedRuntime(in: runtimesDirectory) else { continue }
            bottles[index].useRuntime(runtime)
            bottles[index].updatedAt = Date()
            appendLog(RuntimeStrings.runtimeRelinked(runtime.displayName), bottleID: bottles[index].id)
            changed = true
        }
        if changed { await save() }
    }

    /// `bottle` as it can run now: re-linked if its runtime moved. nil when its
    /// runtime is gone, after saying so unless `quiet`.
    func withAvailableRuntime(_ bottle: Bottle, quiet: Bool = false) async -> Bottle? {
        guard bottle.runtimeIsMissing else { return bottle }
        if let runtime = bottle.movedRuntime(in: AppPaths.runtimesDirectory) {
            await relinkMovedRuntimes()   // the stored bottle too
            var updated = bottle
            updated.useRuntime(runtime)
            return updated
        }
        if !quiet {
            let message = RuntimeStrings.runtimeMissingError(bottle.steamGameName ?? bottle.name, runtime: bottle.runtimeLabel)
            appendLog(message, bottleID: bottle.id, isError: true)
            lastError = message
        }
        return nil
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

    func save() async {
        do {
            try persist()
        } catch {
            lastError = "Could not save bottles: \(error.localizedDescription)"
        }
    }

    /// `save`, for a caller that must not carry on if it failed: a move
    /// deletes the game's old copy only once the bottle is saved pointing at
    /// the new one.
    func persist() throws {
        try AppPaths.ensureBaseDirectories()
        let data = try JSONEncoder.gamenative.encode(bottles)
        try data.write(to: AppPaths.metadataURL, options: .atomic)
    }
}
