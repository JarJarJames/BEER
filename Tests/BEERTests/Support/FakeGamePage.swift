import XCTest
@testable import BEER

/// A real `GameDetailViewModel` with the world around it faked: Steam is
/// `FakeSteam`, the drives are `FakeDrives`, the stores and shortcuts save
/// into a temporary folder, and Play runs no Wine and tells neither Discord
/// nor the achievement watcher. Nothing here signs in, downloads, or touches
/// Application Support.
@MainActor
final class FakeGamePage {
    static let account = SteamCloudAccount(accountName: "fake-steam", steamID64: "76561197960287930",
                                           refreshToken: "not-a-real-token", connectedAt: Date())
    /// Free space on this Mac. A fake drive reports its own.
    nonisolated static let macFreeBytes: Int64 = 500_000_000_000

    let root: URL
    let steam: FakeSteam
    let drives = FakeDrives()
    let auth = SteamAuthStore()
    let bottles = BottleStore()
    let library = SteamLibraryStore()
    let downloads = DownloadsStore()
    let cloudSync = CloudSyncEngine()
    let volumes: InstallVolumeMonitor
    let shortcuts: GameShortcutStore

    /// Each step Play's session took, in order.
    private(set) var played: [String] = []
    /// What the game does while it runs.
    var whilePlaying: (Bottle) -> Void = { _ in }

    init() throws {
        // The real path: folder listings report /private/var for /var.
        let temp = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(temp) }
        root = URL(fileURLWithPath: String(cString: temp), isDirectory: true)
            .appendingPathComponent("FakeGamePage-\(UUID().uuidString)", isDirectory: true)
        steam = try FakeSteam(in: root.appendingPathComponent("FakeSteam", isDirectory: true))

        bottles.metadataURL = root.appendingPathComponent("bottles.json")
        bottles.volumes = drives.catalog
        bottles.rosettaInstalled = { true }
        bottles.gameWindowWatch = GameWindowWatch(isShown: { _ in false }, pollInterval: .milliseconds(5),
                                                  slowAfter: .seconds(60))
        library.stateURL = root.appendingPathComponent("steam-library.json")

        let backups = root.appendingPathComponent("CloudSaveBackups", isDirectory: true)
        cloudSync.client = steam.client
        cloudSync.backupsDirectory = { backups.appendingPathComponent(String($0), isDirectory: true) }
        cloudSync.bottlePrefix = { [root] in Self.prefix(of: $0, in: root) }
        cloudSync.volumes = drives.catalog

        volumes = InstallVolumeMonitor(source: drives.catalog)
        shortcuts = GameShortcutStore(locations: .init(
            desktop: root.appendingPathComponent("Desktop", isDirectory: true),
            applications: root.appendingPathComponent("Applications", isDirectory: true),
            records: root.appendingPathComponent("shortcuts.json")
        ))
        shortcuts.fetch = { _ in TestImages.png(width: 600, height: 900) }
        shortcuts.announce = { _ in }
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The game page for `game`, as the app builds it.
    func page(for game: SteamLibraryGame) -> GameDetailViewModel {
        let model = GameDetailViewModel(game: game, dependencies: GameDetailDependencies(
            library: library, bottles: bottles, detector: ToolchainDetector(),
            depotCtl: DepotDownloaderController(), downloads: downloads, goldberg: GoldbergInstaller(),
            cloudAuth: auth, cloudSync: cloudSync, presence: SteamPresenceStore(),
            graphicsTranslator: GraphicsTranslatorInstaller(), dlcStore: DLCStore(),
            drives: volumes, mover: GameMover()
        ))
        model.preferredRuntime = { Self.runtime }
        model.installSpaceCheck = InstallSpaceCheck(client: steam.client, freeSpace: { [drives] url in
            guard let drive = drives.drives.first(where: { url.path.hasPrefix($0.root.path + "/") }) else {
                return VolumeSpace(availableBytes: Self.macFreeBytes, name: "Macintosh HD")
            }
            return drive.availableBytes.map { VolumeSpace(availableBytes: $0, name: drive.name) }
        })
        model.shortcuts = shortcuts
        model.session = session
        return model
    }

    /// Records each step and runs nothing.
    private var session: GameDetailViewModel.GameSession {
        GameDetailViewModel.GameSession(
            setUpWine: { [self] _, bottle in
                played.append("setUpWine")
                return (bottle, bottle.gameLaunchExecutable ?? "")
            },
            prepareGame: { [self] _, bottle in
                played.append("prepareGame")
                return bottle
            },
            runGame: { [self] _, bottle, _ in
                played.append("runGame")
                whilePlaying(bottle)
                return 0
            },
            showOnDiscord: { [self] _ in played.append("showOnDiscord") },
            clearFromDiscord: { [self] _ in played.append("clearFromDiscord") },
            watchAchievements: { [self] _, _, _, _ in
                played.append("watchAchievements")
                return nil
            }
        )
    }

    // MARK: - Games on disk

    static let runtime: RuntimeCandidate = {
        let wine = "/nonexistent/runtime/bin/wine64"
        return RuntimeCandidate(kind: .systemWine, executablePath: wine, displayName: "Managed GPTK",
                                entrypoints: RuntimeEntrypoints(wine: wine, wineboot: nil, wineserver: nil))
    }()

    nonisolated static func prefix(of bottle: Bottle, in root: URL) -> URL {
        root.appendingPathComponent("Bottles", isDirectory: true)
            .appendingPathComponent(bottle.folderName, isDirectory: true)
    }

    /// The Windows user folder saves go under.
    func userHome(of bottle: Bottle) -> URL {
        Self.prefix(of: bottle, in: root).appendingPathComponent("drive_c/users/crossover", isDirectory: true)
    }

    /// An installed game: its folder and .exe on this Mac, or on `drive`, and
    /// a Wine user folder for its saves.
    func installedBottle(for game: SteamLibraryGame, on drive: InstallVolume? = nil) throws -> Bottle {
        var bottle = Bottle.make(name: game.name, runtime: Self.runtime, graphicsBackend: .automatic)
        let games = drive.map { AppPaths.driveGamesDirectory(onDriveAt: $0.root) }
            ?? root.appendingPathComponent("Games", isDirectory: true)
        let folder = games.appendingPathComponent(game.name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: folder.appendingPathComponent("Game.exe"))
        try FileManager.default.createDirectory(at: userHome(of: bottle), withIntermediateDirectories: true)
        bottle.steamAppID = game.effectiveIsNonSteam ? nil : game.appID
        bottle.steamGameName = game.name
        bottle.gameInstallStatus = .installed
        bottle.gameInstallDirectory = folder.path
        bottle.gameLaunchExecutable = folder.appendingPathComponent("Game.exe").path
        bottle.gameDrive = drive?.link
        return bottle
    }

    /// Save `bottles` and `games` where the stores look, and load them, as on
    /// a launch of the app.
    func seed(bottles seeded: [Bottle], games: [SteamLibraryGame] = []) async throws {
        try JSONEncoder.gamenative.encode(seeded).write(to: bottles.metadataURL)
        await bottles.load()
        try JSONEncoder().encode(SavedLibrary(account: .signedOut, games: games)).write(to: library.stateURL)
        library.load()
    }

    /// The library as it was last saved.
    func savedLibrary() -> [SteamLibraryGame] {
        let saved = SteamLibraryStore()
        saved.stateURL = library.stateURL
        saved.load()
        return saved.games
    }

    /// `SteamLibraryStore`'s file.
    private struct SavedLibrary: Encodable {
        let account: SteamAccount
        let games: [SteamLibraryGame]
    }
}

/// Wait up to two seconds for `condition`.
@MainActor
func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
    for _ in 0..<2000 where !condition() {
        try? await Task.sleep(for: .milliseconds(1))
    }
    XCTAssertTrue(condition(), "Timed out", file: file, line: line)
}
