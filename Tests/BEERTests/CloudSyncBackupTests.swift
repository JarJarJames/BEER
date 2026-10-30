import XCTest
@testable import BEER

// Every sync and "clear local saves" goes through backUpBeforeWriting before it
// touches a save. If the backup can't be made, nothing may be written: these
// tests pin that a failed backup throws instead of letting the sync continue.
@MainActor
final class CloudSyncBackupTests: XCTestCase {
    private var root: URL!
    private var saves: URL!
    private var backups: URL!
    private let appID = 379430

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSyncBackupTests-\(UUID().uuidString)", isDirectory: true)
        saves = root.appendingPathComponent("drive_c/users/crossover/Saved Games/kingdomcome/saves", isDirectory: true)
        backups = root.appendingPathComponent("CloudSaveBackups", isDirectory: true)
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try Data("chapter 3".utf8).write(to: saves.appendingPathComponent("quicksave.whs"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func engine() -> CloudSyncEngine {
        let engine = CloudSyncEngine()
        engine.backupsDirectory = { [backups] appID in
            backups!.appendingPathComponent(String(appID), isDirectory: true)
        }
        return engine
    }

    func testBackupCopiesSavesIntoATimestampedFolder() throws {
        let backup = try engine().backUpBeforeWriting(appID: appID, dirs: [saves], label: "before-pull")

        XCTAssertTrue(backup.lastPathComponent.hasSuffix("-before-pull"))
        // Backups keep the last three path components of each save folder.
        let copied = backup.appendingPathComponent("Saved Games/kingdomcome/saves/quicksave.whs")
        XCTAssertEqual(try Data(contentsOf: copied), Data("chapter 3".utf8))
    }

    func testFailedBackupThrowsAndLeavesSavesAlone() throws {
        // A plain file where the app's backup folder should be makes every
        // directory create beneath it fail, like a full or read-only disk.
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try Data().write(to: backups.appendingPathComponent(String(appID)))

        XCTAssertThrowsError(try engine().backUpBeforeWriting(appID: appID, dirs: [saves], label: "before-sync")) { error in
            guard case CloudSyncError.backupFailed = error else {
                return XCTFail("expected backupFailed, got \(error)")
            }
            XCTAssertTrue(
                (error as? LocalizedError)?.errorDescription?.contains("nothing was synced") == true,
                "the message should tell the user nothing was synced"
            )
        }
        XCTAssertEqual(try Data(contentsOf: saves.appendingPathComponent("quicksave.whs")), Data("chapter 3".utf8))
    }

    func testBackupWithNoLocalSavesStillNeedsAWritableBackupFolder() throws {
        // First pull on a new Mac: nothing to copy yet, but an unwritable
        // backup location is still a broken disk and must stop the sync.
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try Data().write(to: backups.appendingPathComponent(String(appID)))
        let missing = root.appendingPathComponent("not-created-yet", isDirectory: true)

        XCTAssertThrowsError(try engine().backUpBeforeWriting(appID: appID, dirs: [missing], label: "before-pull"))
    }
}
