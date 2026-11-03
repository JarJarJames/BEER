import XCTest
@testable import BEER

/// Finding games on a drive that aren't in BEER. The drive is a temporary
/// folder (see FakeDrives).
final class FoundGameScannerTests: XCTestCase {
    private var root: URL!
    private var fake: FakeDrives!
    private var drive: InstallVolume!
    private var games: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FoundGameScannerTests-\(UUID().uuidString)", isDirectory: true)
        fake = FakeDrives()
        drive = try fake.plugIn("Games", at: root.appendingPathComponent("Drive"))
        games = AppPaths.driveGamesDirectory(onDriveAt: drive.root)
        try FileManager.default.createDirectory(at: games, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    @discardableResult
    private func folder(_ name: String, marker: GameFolderMarker?, exe: String? = "bin/Game.exe") throws -> URL {
        let folder = games.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        if let exe { try Data("MZ".utf8).write(to: folder.appendingPathComponent(exe)) }
        if let marker { try GameFolderMarkerFile.write(marker, in: folder) }
        return folder
    }

    private func steam(_ appID: Int, _ name: String, exe: String? = "bin/Game.exe") -> GameFolderMarker {
        GameFolderMarker(appID: appID, name: name, isNonSteam: false, launchExecutable: exe)
    }

    private func scan(bottles: [Bottle] = [], owned: Set<Int> = [10, 20, 30], installed: Set<Int> = []) -> [FoundGame] {
        FoundGameScanner.scan(drive, bottles: bottles, ownedAppIDs: owned, installedAppIDs: installed, volumes: fake.catalog)
    }

    func testFindsGamesNoBottleUses() throws {
        let hades = try folder("Hades", marker: steam(10, "Hades"))
        let found = scan()
        // Folder listings report temporary folders under /private/var.
        XCTAssertEqual(found.map { GameFolders.canonicalPath($0.folder) }, [GameFolders.canonicalPath(hades)])
        XCTAssertEqual(found.first?.launchExecutable?.lastPathComponent, "Game.exe")
        XCTAssertTrue(found.first?.canAdd ?? false)
    }

    func testSkipsFoldersABottleUses() throws {
        let used = try folder("Hades", marker: steam(10, "Hades"))
        var bottle = FakeDrives.bottle()
        bottle.gameInstallDirectory = used.path
        bottle.gameDrive = drive.link
        XCTAssertEqual(scan(bottles: [bottle]), [])
    }

    func testSkipsFoldersWithoutAGameFileAndUnfinishedMoves() throws {
        try folder("Unknown", marker: nil)
        try folder("Hades" + GameFolders.stagingSuffix, marker: steam(10, "Hades"))
        XCTAssertEqual(scan(), [])
    }

    func testGameTheAccountDoesntOwnIsShownButCantBeAdded() throws {
        try folder("Other", marker: steam(99, "Other"))
        XCTAssertEqual(scan().first?.blockedReason, FoundGamesStrings.notOwned)
    }

    func testGameAlreadyInstalledElsewhereCantBeAddedTwice() throws {
        try folder("Hades", marker: steam(10, "Hades"))
        XCTAssertEqual(scan(installed: [10]).first?.blockedReason, FoundGamesStrings.alreadyInstalled)
    }

    func testNonSteamGameNeedsNoOwnership() throws {
        try folder("Doom", marker: GameFolderMarker(appID: nil, name: "Doom", isNonSteam: true, launchExecutable: "bin/Game.exe"))
        XCTAssertTrue(scan(owned: []).first?.canAdd ?? false)
    }

    func testFallsBackToFindingTheExe() throws {
        let game = try folder("Hades", marker: steam(10, "Hades", exe: "gone.exe"), exe: "bin/Hades.exe")
        XCTAssertEqual(scan().first?.launchExecutable?.lastPathComponent, "Hades.exe")
        XCTAssertTrue(FileManager.default.fileExists(atPath: game.appendingPathComponent("bin/Hades.exe").path))
    }

    func testNoExeMeansNothingToLaunch() throws {
        try folder("Hades", marker: steam(10, "Hades"), exe: nil)
        XCTAssertEqual(scan().first?.blockedReason, FoundGamesStrings.noExecutable)
    }

    func testDriveWithoutBEERsFolderHasNothing() throws {
        let empty = try fake.plugIn("Empty", at: root.appendingPathComponent("Empty"))
        XCTAssertEqual(FoundGameScanner.scan(empty, bottles: [], ownedAppIDs: [], installedAppIDs: [], volumes: fake.catalog), [])
    }
}
