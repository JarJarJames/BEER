import CryptoKit
import XCTest
@testable import BEER

// A restored backup meeting a real sync. The engine runs end to end against
// a stand-in for the CloudSync helper (see CloudSyncStandIn), with a bottle
// and backups in a temporary folder. The account below is made up and never
// stored: nothing here reaches Steam or the Keychain.
@MainActor
final class CloudSaveRestoreSyncTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var saves: URL!
    private var standIn: CloudSyncStandIn!
    private var engine: CloudSyncEngine!
    private var auth: SteamAuthStore!
    private let appID = 379430
    private let cloudName = "%WinSavedGames%/kingdomcome/saves/quicksave.whs"
    private let bottle = Bottle.make(
        name: "Test",
        runtime: RuntimeCandidate(kind: .gameNativeWine, executablePath: "/tmp/wine", displayName: "Test Wine"),
        graphicsBackend: .automatic
    )

    override func setUp() async throws {
        // The real path, as in CloudSaveRestoreTests: folder listings report
        // /private/var for /var.
        let temp = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(temp) }
        root = URL(fileURLWithPath: String(cString: temp), isDirectory: true)
            .appendingPathComponent("CloudSaveRestoreSyncTests-\(UUID().uuidString)", isDirectory: true)
        let prefix = root.appendingPathComponent("Bottle", isDirectory: true)
        home = prefix.appendingPathComponent("drive_c/users/crossover", isDirectory: true)
        saves = home.appendingPathComponent("Saved Games/kingdomcome/saves", isDirectory: true)
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try Data("chapter 3".utf8).write(to: saves.appendingPathComponent("quicksave.whs"))

        standIn = try CloudSyncStandIn(in: root.appendingPathComponent("StandIn", isDirectory: true))
        let backups = root.appendingPathComponent("CloudSaveBackups", isDirectory: true)
        engine = CloudSyncEngine()
        engine.client = standIn.client
        engine.backupsDirectory = { backups.appendingPathComponent(String($0), isDirectory: true) }
        engine.bottlePrefix = { _ in prefix }
        auth = SteamAuthStore()
        auth.account = SteamCloudAccount(accountName: "stand-in", steamID64: "76561197960287930",
                                         refreshToken: "not-a-real-token", connectedAt: Date())
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Ordinary syncs

    func testSyncWithNothingToDoSpendsOneLogon() async throws {
        steamHas("chapter 3")

        let report = try await engine.sync(bottle: bottle, appID: appID, auth: auth)

        XCTAssertEqual(report.downloaded + report.uploaded, 0)
        XCTAssertEqual(standIn.calls().map(\.command), ["enumerate"], "no batch when nothing changed")
    }

    // MARK: - A pending restore

    func testSyncStopsOnAPendingRestoreBeforeWritingAnything() async throws {
        try restoreBackupOfChapter3()
        steamHas("chapter 5")
        let backupsBefore = engine.saveBackups(appID: appID).count

        do {
            _ = try await engine.sync(bottle: bottle, appID: appID, auth: auth)
            XCTFail("the sync should have stopped for the player to choose")
        } catch CloudSyncError.restoreConflict(let conflict) {
            XCTAssertEqual(conflict.differingCloudFiles.map(\.filename), [cloudName])
        }

        XCTAssertEqual(standIn.calls().map(\.command), ["enumerate"], "nothing downloaded or uploaded")
        XCTAssertEqual(try localSave(), "chapter 3")
        XCTAssertEqual(engine.saveBackups(appID: appID).count, backupsBefore, "stopped before even backing up")
        XCTAssertNotNil(engine.pendingRestore(appID: appID))
    }

    func testPrelaunchPullStopsOnAPendingRestoreToo() async throws {
        try restoreBackupOfChapter3()
        steamHas("chapter 5")

        do {
            _ = try await engine.pull(bottle: bottle, appID: appID, auth: auth)
            XCTFail("the pull should have stopped for the player to choose")
        } catch CloudSyncError.restoreConflict {}

        XCTAssertEqual(try localSave(), "chapter 3")
    }

    func testRestoredSavesMatchingSteamLetTheSyncThrough() async throws {
        try restoreBackupOfChapter3()
        steamHas("chapter 3")

        _ = try await engine.sync(bottle: bottle, appID: appID, auth: auth)

        XCTAssertNil(engine.pendingRestore(appID: appID))
    }

    // MARK: - Keep Restored Saves

    func testKeepingRestoredSavesSavesSteamsCopyThenUploads() async throws {
        try restoreBackupOfChapter3()
        steamHas("chapter 5")

        let report = try await engine.keepRestoredSaves(bottle: bottle, appID: appID, auth: auth)

        let calls = standIn.calls()
        XCTAssertEqual(calls.map(\.command), ["enumerate", "batch", "batch"])
        XCTAssertEqual(calls[1].downloads.map(\.filename), [cloudName], "Steam's copy first…")
        XCTAssertTrue(calls[1].uploads.isEmpty)
        XCTAssertTrue(calls[2].downloads.isEmpty)
        XCTAssertEqual(calls[2].uploads.map(\.filename), [cloudName], "…then the restored save")
        XCTAssertGreaterThan(try XCTUnwrap(calls[2].uploads.first).mtime, Date().addingTimeInterval(-60),
                             "uploaded stamped now")
        XCTAssertEqual(report.uploaded, 1)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertNil(engine.pendingRestore(appID: appID))
        XCTAssertEqual(try localSave(), "chapter 3", "keeping never touches the local saves")

        // Steam's copy is an ordinary backup that can itself be restored.
        let copy = try XCTUnwrap(engine.saveBackups(appID: appID).first { $0.label == CloudSaveBackupLimits.steamCloudCopyLabel })
        XCTAssertEqual(report.backupPath?.lastPathComponent, copy.id)
        let plan = try CloudSyncEngine.restorePlan(for: copy, userHome: home, installDir: nil)
        XCTAssertEqual(plan.folders.map(\.target.path), [saves.path])
        XCTAssertEqual(try String(contentsOf: plan.folders[0].stored.appendingPathComponent("quicksave.whs"), encoding: .utf8),
                       "chapter 5")
    }

    func testKeepingUploadsNothingWhenSteamsCopyCantBeSaved() async throws {
        try restoreBackupOfChapter3()
        steamHas("chapter 5")
        standIn.contents = [:]

        do {
            _ = try await engine.keepRestoredSaves(bottle: bottle, appID: appID, auth: auth)
            XCTFail("keeping should have stopped when Steam's copy didn't download")
        } catch CloudSyncError.steamCopyFailed {}

        XCTAssertEqual(standIn.calls().map(\.command), ["enumerate", "batch"])
        XCTAssertTrue(standIn.calls().allSatisfy { $0.uploads.isEmpty }, "Steam Cloud is unchanged")
        XCTAssertFalse(engine.saveBackups(appID: appID).contains { $0.label == CloudSaveBackupLimits.steamCloudCopyLabel },
                       "no half-made copy left behind")
        XCTAssertNotNil(engine.pendingRestore(appID: appID), "still waiting on the player")
    }

    func testKeepingWithAnExpiredSignInChangesNothing() async throws {
        try restoreBackupOfChapter3()
        steamHas("chapter 5")
        standIn.signInExpired = true

        do {
            _ = try await engine.keepRestoredSaves(bottle: bottle, appID: appID, auth: auth)
            XCTFail("an expired sign-in should have stopped it")
        } catch CloudSyncClientError.authExpired {}

        XCTAssertEqual(standIn.calls().map(\.command), ["enumerate"])
        XCTAssertNotNil(engine.pendingRestore(appID: appID))
        XCTAssertEqual(try localSave(), "chapter 3")
    }

    func testARefusedUploadLeavesTheRestorePending() async throws {
        try restoreBackupOfChapter3()
        steamHas("chapter 5")
        standIn.rejectedUploads = [cloudName]

        let report = try await engine.keepRestoredSaves(bottle: bottle, appID: appID, auth: auth)

        XCTAssertEqual(report.failures.map(\.filename), [cloudName])
        XCTAssertNotNil(engine.pendingRestore(appID: appID), "the next sync asks again instead of pulling over it")
    }

    // MARK: - Use Steam Cloud Saves

    func testUsingSteamsSavesLetsThePullBringThemDown() async throws {
        try restoreBackupOfChapter3()
        steamHas("chapter 5")

        engine.useSteamSavesOverRestore(appID: appID)
        let report = try await engine.pull(bottle: bottle, appID: appID, auth: auth)

        XCTAssertEqual(report.downloaded, 1)
        XCTAssertEqual(try localSave(), "chapter 5")
        let before = try XCTUnwrap(report.backupPath)
        XCTAssertEqual(try String(contentsOf: before.appendingPathComponent("Saved Games/kingdomcome/saves/quicksave.whs"), encoding: .utf8),
                       "chapter 3", "the restored saves were backed up before Steam's came down")
    }

    // MARK: - Clearing local saves

    func testClearingLocalSavesEndsAPendingRestore() async throws {
        try restoreBackupOfChapter3()
        steamHas("chapter 5")

        let backup = try await engine.backupAndClearLocalSaves(bottle: bottle, appID: appID, auth: auth)

        XCTAssertNil(engine.pendingRestore(appID: appID), "clearing chooses Steam's saves over the restore")
        XCTAssertFalse(FileManager.default.fileExists(atPath: saves.path))
        XCTAssertEqual(try String(contentsOf: try XCTUnwrap(backup).appendingPathComponent("Saved Games/kingdomcome/saves/quicksave.whs"),
                                  encoding: .utf8), "chapter 3", "the restored saves are backed up before clearing")
    }

    // MARK: - helpers

    /// Back up "chapter 3", play on to "chapter 5", then restore the backup.
    private func restoreBackupOfChapter3() throws {
        let url = try XCTUnwrap(engine.backUpBeforeWriting(appID: appID, dirs: [saves], label: "before-pull"))
        let snapshot = try XCTUnwrap(engine.saveBackups(appID: appID).first { $0.id == url.lastPathComponent })
        try Data("chapter 5".utf8).write(to: saves.appendingPathComponent("quicksave.whs"))
        try engine.restore(CloudSyncEngine.restorePlan(for: snapshot, userHome: home, installDir: nil), appID: appID)
        XCTAssertEqual(try localSave(), "chapter 3")
    }

    /// Steam holds `text` for the quicksave, uploaded later than anything here.
    private func steamHas(_ text: String) {
        standIn.files = [CloudRemoteFile(filename: cloudName, size: text.utf8.count,
                                         timestamp: Date().addingTimeInterval(3600), sha: sha1(of: text))]
        standIn.contents = [cloudName: text]
    }

    private func localSave() throws -> String {
        try String(contentsOf: saves.appendingPathComponent("quicksave.whs"), encoding: .utf8)
    }

    private func sha1(of text: String) -> String {
        Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
