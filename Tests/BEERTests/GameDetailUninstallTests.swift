import XCTest
@testable import BEER

/// Uninstall on the game page: what's deleted, what's kept, and when it asks
/// first. The bottle, library, shortcuts and drives all live in a temporary
/// folder (see FakeGamePage); nothing in Application Support is touched.
@MainActor
final class GameDetailUninstallTests: XCTestCase {
    private var fake: FakeGamePage!
    private var ssd: InstallVolume!

    override func setUp() async throws {
        fake = try FakeGamePage()
        ssd = try fake.drives.plugIn("Games SSD", at: fake.root.appendingPathComponent("Games SSD", isDirectory: true))
    }

    override func tearDown() async throws {
        fake.remove()
    }

    /// `game`, installed and in the library, with a desktop shortcut when
    /// it's a Steam game (one brought in from a folder has no art for one).
    private func installed(
        _ game: SteamLibraryGame, onDrive: Bool = true
    ) async throws -> (GameDetailViewModel, Bottle) {
        let bottle = try fake.installedBottle(for: game, on: onDrive ? ssd : nil)
        var game = game
        game.installedBottleID = bottle.id
        try await fake.seed(bottles: [bottle], games: [game])
        if !game.effectiveIsNonSteam {
            try await fake.shortcuts.create(.desktop, for: game)
        }
        return (fake.page(for: game), bottle)
    }

    private func folder(of bottle: Bottle) throws -> URL {
        URL(fileURLWithPath: try XCTUnwrap(bottle.gameInstallDirectory), isDirectory: true)
    }

    func testUninstallingASteamGameRemovesItsBottleFilesAndShortcuts() async throws {
        let (model, bottle) = try await installed(SteamLibraryGame(appID: 620, name: "Portal 2"))
        fake.downloads.start(appID: 620, name: "Portal 2", bottleID: bottle.id)
        let gameFolder = try folder(of: bottle)

        model.requestUninstall()   // can be downloaded again, so it doesn't ask
        await waitUntil { self.fake.downloads.entry(for: 620) == nil }

        XCTAssertNil(model.dialog)
        XCTAssertTrue(fake.bottles.bottles.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: gameFolder.path), "its folder on the drive goes")
        XCTAssertNil(fake.library.games.first?.installedBottleID, "the game stays in the library, uninstalled")
        XCTAssertEqual(fake.savedLibrary().map(\.appID), [620])
        XCTAssertNil(fake.savedLibrary().first?.installedBottleID, "and is saved that way")
        XCTAssertEqual(fake.shortcuts.records, [])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fake.shortcuts.locations.desktop.path), [])
    }

    func testUninstallingWithItsDriveUnpluggedAsksThenKeepsTheFiles() async throws {
        let (model, bottle) = try await installed(SteamLibraryGame(appID: 620, name: "Portal 2"))
        let gameFolder = try folder(of: bottle)
        fake.drives.unplug(ssd)

        model.requestUninstall()

        XCTAssertEqual(model.dialog, .removeWithDriveMissing)
        XCTAssertEqual(fake.bottles.bottles.map(\.id), [bottle.id], "nothing goes until confirmed")

        model.uninstall()
        await waitUntil { self.fake.bottles.bottles.isEmpty }

        XCTAssertTrue(FileManager.default.fileExists(atPath: gameFolder.path),
                      "the files stay on the drive; BEER offers to add them back when it returns")
    }

    func testRemovingANonSteamGameAsksThenTakesItOffTheLibrary() async throws {
        var game = SteamLibraryGame(appID: -5, name: "Mod Launcher")
        game.isNonSteam = true
        let (model, _) = try await installed(game, onDrive: false)

        model.requestUninstall()

        XCTAssertEqual(model.dialog, .removeNonSteamGame, "its folder is the only copy, so it asks")
        XCTAssertEqual(fake.bottles.bottles.count, 1)

        model.uninstall()
        await waitUntil { self.fake.library.games.isEmpty }

        XCTAssertTrue(fake.bottles.bottles.isEmpty)
        XCTAssertEqual(fake.savedLibrary().count, 0)
    }
}
