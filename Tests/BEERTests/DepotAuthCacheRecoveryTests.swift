import XCTest
@testable import BEER

// DepotDownloader needs the refresh token in its own cache file while it runs.
// BEER records that file's path first, so if the app dies mid-download the next
// launch can delete it. These tests pin that the record is only dropped once
// the cache is really gone.
@MainActor
final class DepotAuthCacheRecoveryTests: XCTestCase {
    private var root: URL!
    private var cacheFolder: URL!
    private var cache: URL!
    private var record: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DepotAuthCacheRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        cacheFolder = root.appendingPathComponent("IsolatedStorage", isDirectory: true)
        cache = cacheFolder.appendingPathComponent("account.config")
        record = root.appendingPathComponent("depotdownloader-state.json")
        try FileManager.default.createDirectory(at: cacheFolder, withIntermediateDirectories: true)
        try Data("not a real token".utf8).write(to: cache)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cacheFolder.path)
        try? FileManager.default.removeItem(at: root)
    }

    private func writeRecord(_ json: String) throws {
        try Data(json.utf8).write(to: record)
    }

    private func controller() -> DepotDownloaderController {
        let controller = DepotDownloaderController()
        controller.stateURL = record
        return controller
    }

    func testLaunchDeletesALeftoverCacheAndItsRecord() throws {
        try writeRecord(#"{"authCachePath":"\#(cache.path)"}"#)

        controller().load()

        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
    }

    func testRecordSurvivesWhenTheCacheCantBeDeleted() throws {
        try writeRecord(#"{"authCachePath":"\#(cache.path)"}"#)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: cacheFolder.path)

        controller().load()

        XCTAssertTrue(FileManager.default.fileExists(atPath: cache.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: record.path),
                      "the record must survive so the next launch retries the delete")
    }

    func testARecordForAnAlreadyDeletedCacheIsCleared() throws {
        try FileManager.default.removeItem(at: cache)
        try writeRecord(#"{"authCachePath":"\#(cache.path)"}"#)

        controller().load()

        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
    }

    func testAnUnreadableRecordIsCleared() throws {
        try writeRecord("{ not json")

        controller().load()

        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
    }
}
