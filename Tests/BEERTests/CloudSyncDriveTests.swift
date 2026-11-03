import CryptoKit
import XCTest
@testable import BEER

/// Cloud sync for a game whose files are on a drive. Steam is FakeSteam and the
/// drive a temporary folder (see FakeDrives); the account is made up and never
/// stored, so nothing reaches Steam or the Keychain.
@MainActor
final class CloudSyncDriveTests: XCTestCase {
    private var root: URL!
    private var fake: FakeDrives!
    private var drive: InstallVolume!
    private var gameFolder: URL!
    private var fakeSteam: FakeSteam!
    private var engine: CloudSyncEngine!
    private var auth: SteamAuthStore!
    private var bottle: Bottle!
    private let appID = 4000
    /// A game that keeps its saves in its own folder.
    private let cloudName = "%GameInstall%/saves/slot1.sav"

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncDriveTests-\(UUID().uuidString)", isDirectory: true)
        let prefix = root.appendingPathComponent("Bottle", isDirectory: true)
        try FileManager.default.createDirectory(at: prefix.appendingPathComponent("drive_c/users/crossover"),
                                                withIntermediateDirectories: true)

        fake = FakeDrives()
        drive = try fake.plugIn("Games", at: root.appendingPathComponent("Drive"))
        gameFolder = AppPaths.driveGamesDirectory(onDriveAt: drive.root).appendingPathComponent("Game", isDirectory: true)
        try FileManager.default.createDirectory(at: gameFolder, withIntermediateDirectories: true)

        bottle = FakeDrives.bottle()
        bottle.steamAppID = appID
        bottle.gameInstallDirectory = gameFolder.path
        bottle.gameDrive = drive.link

        fakeSteam = try FakeSteam(in: root.appendingPathComponent("FakeSteam", isDirectory: true))
        let backups = root.appendingPathComponent("CloudSaveBackups", isDirectory: true)
        engine = CloudSyncEngine()
        engine.client = fakeSteam.client
        engine.backupsDirectory = { backups.appendingPathComponent(String($0), isDirectory: true) }
        engine.bottlePrefix = { _ in prefix }
        engine.volumes = fake.catalog
        auth = SteamAuthStore()
        auth.account = SteamCloudAccount(accountName: "fake-steam", steamID64: "76561197960287930",
                                         refreshToken: "not-a-real-token", connectedAt: Date())

        let text = "level 9"
        fakeSteam.files = [CloudRemoteFile(filename: cloudName, size: text.utf8.count,
                                           timestamp: Date().addingTimeInterval(3600), sha: sha1(of: text))]
        fakeSteam.contents = [cloudName: text]
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testSavesInTheGameFolderSyncWhileTheDriveIsConnected() async throws {
        _ = try await engine.pull(bottle: bottle, appID: appID, auth: auth)

        let save = gameFolder.appendingPathComponent("saves/slot1.sav")
        XCTAssertEqual(try String(contentsOf: save, encoding: .utf8), "level 9")
    }

    func testSyncRefusesWhileTheDriveIsUnplugged() async throws {
        fake.unplug(drive)
        try FileManager.default.removeItem(at: drive.root)

        for run in [engine.pull, engine.push, engine.sync] {
            do {
                _ = try await run(bottle, appID, auth)
                XCTFail("expected the sync to refuse")
            } catch CloudSyncError.installDriveMissing(let name) {
                XCTAssertEqual(name, "Games")
            }
        }

        XCTAssertEqual(fakeSteam.calls().map(\.command), [], "refused before spending a Steam logon")
        XCTAssertFalse(FileManager.default.fileExists(atPath: drive.root.path), "nothing written to the drive's old path")
    }

    func testClearingAndKeepingRestoredSavesRefuseToo() async throws {
        fake.unplug(drive)

        do {
            _ = try await engine.backupAndClearLocalSaves(bottle: bottle, appID: appID, auth: auth)
            XCTFail("expected a refusal")
        } catch CloudSyncError.installDriveMissing {}
        do {
            _ = try await engine.keepRestoredSaves(bottle: bottle, appID: appID, auth: auth)
            XCTFail("expected a refusal")
        } catch CloudSyncError.installDriveMissing {}
        XCTAssertEqual(fakeSteam.calls().map(\.command), [])
    }

    func testMoveBacksUpTheSavesSyncsFoundInTheGameFolder() async throws {
        _ = try await engine.pull(bottle: bottle, appID: appID, auth: auth)
        XCTAssertTrue(engine.saveBackups(appID: appID).allSatisfy { $0.label != "before-move" })

        try engine.backUpSaves(inside: gameFolder, appID: appID)

        let backup = try XCTUnwrap(engine.saveBackups(appID: appID).first { $0.label == "before-move" })
        let stored = try FileManager.default.subpathsOfDirectory(atPath: backup.url.path)
        XCTAssertTrue(stored.contains { $0.hasSuffix("slot1.sav") }, "got \(stored)")
    }

    private func sha1(of text: String) -> String {
        Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
