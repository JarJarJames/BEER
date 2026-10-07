import AppKit
import Foundation

@MainActor
final class BottleStore: ObservableObject {

    @Published private(set) var bottles: [Bottle] = []

    @Published var logs: [Bottle.ID: [BottleLogEntry]] = [:]

    @Published var activeBottleIDs: Set<Bottle.ID> = []

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

    func save() async {
        do {
            try AppPaths.ensureBaseDirectories()
            let data = try JSONEncoder.gamenative.encode(bottles)
            try data.write(to: AppPaths.metadataURL, options: .atomic)
        } catch {
            lastError = "Could not save bottles: \(error.localizedDescription)"
        }
    }
}
