import XCTest
@testable import BEER

/// Where an installed game's files are: available, on a drive that isn't
/// connected, or gone. Drives are temporary folders (see FakeDrives).
final class InstallLocationTests: XCTestCase {
    private var root: URL!
    private var fake: FakeDrives!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallLocationTests-\(UUID().uuidString)", isDirectory: true)
        fake = FakeDrives()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    /// A game installed to `drive`, with its folder and .exe on it.
    private func game(on drive: InstallVolume) throws -> Bottle {
        let folder = AppPaths.driveGamesDirectory(onDriveAt: drive.root).appendingPathComponent("Game", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data("MZ".utf8).write(to: folder.appendingPathComponent("bin/Game.exe"))
        var bottle = FakeDrives.bottle()
        bottle.gameInstallDirectory = folder.path
        bottle.gameLaunchExecutable = folder.appendingPathComponent("bin/Game.exe").path
        bottle.gameDrive = drive.link
        return bottle
    }

    // MARK: - On this Mac

    func testGameOnThisMacIsAvailableWhileItsFolderExists() throws {
        let folder = root.appendingPathComponent("prefix/drive_c/Games/Game", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var bottle = FakeDrives.bottle()
        bottle.gameInstallDirectory = folder.path

        XCTAssertEqual(bottle.installLocation(volumes: fake.catalog), .available(folder))
        try FileManager.default.removeItem(at: folder)
        XCTAssertEqual(bottle.installLocation(volumes: fake.catalog), .missing)
    }

    func testOlderBottleIsFoundFromItsExecutable() throws {
        // Installs from before the folder was stored (like the KCD bottle).
        let folder = root.appendingPathComponent("prefix/drive_c/Games/Kingdom Come", isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Bin/Win64"), withIntermediateDirectories: true)
        var bottle = FakeDrives.bottle()
        bottle.gameLaunchExecutable = folder.appendingPathComponent("Bin/Win64/KingdomCome.exe").path

        XCTAssertEqual(bottle.installLocation(volumes: fake.catalog), .available(folder))
    }

    // MARK: - On a drive

    func testGameOnAConnectedDriveIsAvailable() throws {
        let drive = try fake.plugIn("Games", at: root.appendingPathComponent("Games"))
        let bottle = try game(on: drive)
        XCTAssertEqual(bottle.installLocation(volumes: fake.catalog).url?.path, bottle.gameInstallDirectory)
    }

    func testUnpluggedDriveIsNotADeletedGame() throws {
        let drive = try fake.plugIn("Games", at: root.appendingPathComponent("Games"))
        let bottle = try game(on: drive)
        fake.unplug(drive)
        try FileManager.default.removeItem(at: drive.root)

        XCTAssertEqual(bottle.installLocation(volumes: fake.catalog), .driveMissing(driveName: "Games"))
        XCTAssertNil(bottle.resolvedInstallDirectory, "nothing may be written while the drive is gone")
    }

    func testStrayFolderAtTheOldPathIsNotTheGame() throws {
        // With the drive unplugged, a folder is still at its old path (another
        // drive by the same name, or a leftover in /Volumes). Not the game.
        let drive = try fake.plugIn("Games", at: root.appendingPathComponent("Games"))
        let bottle = try game(on: drive)
        fake.unplug(drive)   // the folder stays where it was

        XCTAssertEqual(bottle.installLocation(volumes: fake.catalog), .driveMissing(driveName: "Games"))
    }

    func testRenamedDriveIsFoundByItsID() throws {
        let drive = try fake.plugIn("Games", at: root.appendingPathComponent("Games"))
        var bottle = try game(on: drive)
        // Renamed in Finder: same drive, mounted somewhere else.
        let renamedRoot = root.appendingPathComponent("Big Drive")
        try FileManager.default.moveItem(at: drive.root, to: renamedRoot)
        let renamed = try fake.plugIn("Big Drive", at: renamedRoot, uuid: drive.uuid!)

        let expected = AppPaths.driveGamesDirectory(onDriveAt: renamed.root).appendingPathComponent("Game")
        XCTAssertEqual(bottle.installLocation(volumes: fake.catalog).url?.path, expected.path)

        XCTAssertTrue(bottle.followRenamedDrive(volumes: fake.catalog))
        XCTAssertEqual(bottle.gameInstallDirectory, expected.path)
        XCTAssertEqual(bottle.gameLaunchExecutable, expected.appendingPathComponent("bin/Game.exe").path)
        XCTAssertEqual(bottle.gameDrive, GameDrive(uuid: drive.uuid!, name: "Big Drive", mountPath: renamed.root.path))
        XCTAssertFalse(bottle.followRenamedDrive(volumes: fake.catalog), "nothing left to change")
    }

    func testConnectedDriveWithoutTheFolderIsMissing() throws {
        let drive = try fake.plugIn("Games", at: root.appendingPathComponent("Games"))
        let bottle = try game(on: drive)
        try FileManager.default.removeItem(atPath: try XCTUnwrap(bottle.gameInstallDirectory))
        XCTAssertEqual(bottle.installLocation(volumes: fake.catalog), .missing)
    }

    // MARK: - Resuming a download

    func testResumeGoesWhereTheDownloadStarted() throws {
        let drive = try fake.plugIn("Games", at: root.appendingPathComponent("Games"))
        let bottle = try game(on: drive)
        XCTAssertEqual(bottle.downloadDirectory(gameName: "Game").path, bottle.gameInstallDirectory)
    }

    func testResumeOfAnOlderDownloadStaysInTheBottle() {
        let bottle = FakeDrives.bottle()
        XCTAssertEqual(bottle.downloadDirectory(gameName: "Game"), AppPaths.gameInstallDirectory(for: bottle, gameName: "Game"))
    }
}
