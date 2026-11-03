import XCTest
@testable import BEER

/// Naming game folders on drives, refusing to write to an unplugged drive, and
/// deciding what uninstalling may delete. Drives are faked (see FakeDrives).
@MainActor
final class GameFoldersTests: XCTestCase {
    private var root: URL!
    private var fake: FakeDrives!
    /// A /Volumes path no test machine has mounted.
    private let unplugged = URL(fileURLWithPath: "/Volumes/BEER-Test-\(UUID().uuidString)", isDirectory: true)

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameFoldersTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fake = FakeDrives()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Unplugged drives

    func testDriveRootIsTheVolumesFolder() {
        XCTAssertEqual(GameFolders.driveRoot(of: URL(fileURLWithPath: "/Volumes/Games/BEER/Games/X"))?.path, "/Volumes/Games")
        XCTAssertNil(GameFolders.driveRoot(of: URL(fileURLWithPath: "/Users/someone/Games")))
        XCTAssertNil(GameFolders.driveRoot(of: URL(fileURLWithPath: "/Volumes")))
    }

    func testNothingIsWrittenToAnUnpluggedDrive() {
        XCTAssertFalse(GameFolders.isMounted(unplugged))
        XCTAssertThrowsError(try GameFolders.requireDrive(for: unplugged.appendingPathComponent("BEER/Games/Game"))) {
            XCTAssertEqual($0 as? GameFolderError, .driveNotConnected(unplugged.lastPathComponent))
        }
        XCTAssertNoThrow(try GameFolders.requireDrive(for: root.appendingPathComponent("Game")), "this Mac is always there")
    }

    func testUnpluggedDriveHasNoFreeSpace() {
        // Walking up would reach /Volumes on the Mac's disk and report its space.
        XCTAssertNil(DiskSpaceCheck.freeSpace(at: unplugged.appendingPathComponent("BEER/Games/Game")))
        XCTAssertNotNil(DiskSpaceCheck.freeSpace(at: root.appendingPathComponent("not/made/yet")))
    }

    func testDownloadRefusesAnUnpluggedDrive() async {
        do {
            _ = try await DepotDownloaderController().installGame(
                appID: 1, gameName: "Game", installDir: unplugged.appendingPathComponent("BEER/Games/Game"),
                auth: SteamCloudAccount(accountName: "fake", steamID64: "1", refreshToken: "not-real", connectedAt: Date()),
                events: { _ in }
            )
            XCTFail("expected a refusal")
        } catch {
            XCTAssertEqual(error as? GameFolderError, .driveNotConnected(unplugged.lastPathComponent))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: unplugged.path), "no stray folder in /Volumes")
    }

    // MARK: - Folder names

    func testFreeFolderUsesTheGamesName() {
        XCTAssertEqual(GameFolders.freeFolder(for: "Hades: II", in: root).lastPathComponent, "Hades_ II")
    }

    func testFolderNameDropsTheTrailingDotWindowsCantOpen() {
        XCTAssertEqual("Easy Delivery Co.".safeGameFolderName, "Easy Delivery Co")
        XCTAssertEqual("...".safeGameFolderName, "Game")
    }

    func testFolderWithATrailingDotIsRenamed() throws {
        let (bottle, folder, _) = try gameOnDrive(named: "Easy Delivery Co.")
        var renamed = bottle

        XCTAssertTrue(try renamed.renameFolderWineCannotOpen(volumes: fake.catalog))
        let fixed = folder.deletingLastPathComponent().appendingPathComponent("Easy Delivery Co", isDirectory: true)
        XCTAssertEqual(renamed.gameInstallDirectory, fixed.path)
        XCTAssertEqual(renamed.gameLaunchExecutable, fixed.appendingPathComponent("bin/Game.exe").path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixed.appendingPathComponent("bin").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertEqual(renamed.installLocation(volumes: fake.catalog), .available(fixed))
    }

    func testFolderIsNotRenamedOntoAnotherFolder() throws {
        let (bottle, folder, _) = try gameOnDrive(named: "Easy Delivery Co.")
        let taken = folder.deletingLastPathComponent().appendingPathComponent("Easy Delivery Co", isDirectory: true)
        try FileManager.default.createDirectory(at: taken, withIntermediateDirectories: true)
        var unchanged = bottle

        XCTAssertFalse(try unchanged.renameFolderWineCannotOpen(volumes: fake.catalog))
        XCTAssertEqual(unchanged.gameInstallDirectory, folder.path)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testFolderOutsideGamesIsNotRenamed() throws {
        var bottle = FakeDrives.bottle()
        let folder = root.appendingPathComponent("My Stuff/Easy Delivery Co.", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        bottle.gameInstallDirectory = folder.path

        XCTAssertFalse(try bottle.renameFolderWineCannotOpen(volumes: fake.catalog))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testAnotherGamesFolderIsNeverReused() throws {
        try makeFolder("Game", appID: 2)
        XCTAssertEqual(GameFolders.freeFolder(for: "Game", in: root).lastPathComponent, "Game 2")
    }

    func testLeftoverOfTheSameGameIsNeverAdopted() throws {
        // Cancelling an install deletes its folder; an adopted leftover could
        // hold saves. It's offered back through the found-games list instead.
        try makeFolder("Game", appID: 1)
        XCTAssertEqual(GameFolders.freeFolder(for: "Game", in: root).lastPathComponent, "Game 2")
    }

    func testUnfinishedMoveKeepsItsName() throws {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Game" + GameFolders.stagingSuffix),
                                                withIntermediateDirectories: true)
        XCTAssertEqual(GameFolders.freeFolder(for: "Game", in: root).lastPathComponent, "Game 2")
    }

    // MARK: - Uninstalling

    func testUninstallDeletesTheGamesFolderOnItsDrive() throws {
        let (bottle, folder, _) = try gameOnDrive()
        XCTAssertEqual(GameFolders.driveFolderToDelete(for: bottle, among: [bottle], volumes: fake.catalog)?.path, folder.path)
    }

    func testUninstallLeavesFilesOnAnUnpluggedDrive() throws {
        let (bottle, _, drive) = try gameOnDrive()
        fake.unplug(drive)
        XCTAssertNil(GameFolders.driveFolderToDelete(for: bottle, among: [bottle], volumes: fake.catalog))
    }

    func testUninstallNeverDeletesOutsideBEERsFolder() throws {
        let (bottle, _, drive) = try gameOnDrive()
        var elsewhere = bottle
        let personal = drive.root.appendingPathComponent("My Stuff", isDirectory: true)
        try FileManager.default.createDirectory(at: personal, withIntermediateDirectories: true)
        elsewhere.gameInstallDirectory = personal.path
        XCTAssertNil(GameFolders.driveFolderToDelete(for: elsewhere, among: [elsewhere], volumes: fake.catalog))
    }

    func testUninstallKeepsAFolderAnotherBottleUses() throws {
        let (bottle, _, _) = try gameOnDrive()
        var other = bottle
        other.id = UUID()
        XCTAssertNil(GameFolders.driveFolderToDelete(for: bottle, among: [bottle, other], volumes: fake.catalog))
    }

    func testGameOnThisMacHasNoDriveFolder() throws {
        var bottle = FakeDrives.bottle()
        let folder = root.appendingPathComponent("prefix/drive_c/Games/Game", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        bottle.gameInstallDirectory = folder.path
        XCTAssertNil(GameFolders.driveFolderToDelete(for: bottle, among: [bottle], volumes: fake.catalog))
    }

    // MARK: - Game file

    func testGameFileRecordsTheExeRelativeToTheFolder() throws {
        let (bottle, folder, _) = try gameOnDrive()
        let marker = GameFolderMarkerFile.marker(for: bottle, installDir: folder)
        XCTAssertEqual(marker, GameFolderMarker(appID: 42, name: "Game", isNonSteam: false, launchExecutable: "bin/Game.exe"))

        try GameFolderMarkerFile.write(marker, in: folder)
        XCTAssertEqual(GameFolderMarkerFile.read(in: folder), marker)
    }

    func testNonSteamGameFileHasNoAppID() {
        var bottle = FakeDrives.bottle(named: "Doom")
        bottle.gameLaunchExecutable = root.appendingPathComponent("Doom/doom.exe").path
        let marker = GameFolderMarkerFile.marker(for: bottle, installDir: root.appendingPathComponent("Doom"))
        XCTAssertEqual(marker, GameFolderMarker(appID: nil, name: "Doom", isNonSteam: true, launchExecutable: "doom.exe"))
    }

    // MARK: - Helpers

    private func makeFolder(_ name: String, appID: Int) throws {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try GameFolderMarkerFile.write(GameFolderMarker(appID: appID, name: name, isNonSteam: false, launchExecutable: nil), in: folder)
    }

    private func gameOnDrive(named folderName: String = "Game") throws -> (Bottle, URL, InstallVolume) {
        let drive = try fake.plugIn("Games", at: root.appendingPathComponent("Drive"))
        let folder = AppPaths.driveGamesDirectory(onDriveAt: drive.root).appendingPathComponent(folderName, isDirectory: true)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("bin"), withIntermediateDirectories: true)
        var bottle = FakeDrives.bottle()
        bottle.steamAppID = 42
        bottle.steamGameName = "Game"
        bottle.gameInstallDirectory = folder.path
        bottle.gameLaunchExecutable = folder.appendingPathComponent("bin/Game.exe").path
        bottle.gameDrive = drive.link
        return (bottle, folder, drive)
    }
}
