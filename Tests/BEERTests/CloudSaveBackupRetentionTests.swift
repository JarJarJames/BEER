import XCTest
@testable import BEER

// Retention is what keeps CloudSaveBackups from growing without limit: before
// it, two Kingdom Come games collected 400+ GB of full save copies.
final class CloudSaveBackupRetentionTests: XCTestCase {
    private var root: URL!
    private var app: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSaveBackupRetentionTests-\(UUID().uuidString)", isDirectory: true)
        app = root.appendingPathComponent("1771300", isDirectory: true)
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testKeepsTheNewestSnapshots() throws {
        for minute in 0..<5 { try snapshot("2026-01-01_10-0\(minute)-00-before-pull", in: app) }

        CloudSaveBackupRetention.prune(appDirectory: app, keep: 3)

        XCTAssertEqual(names(), [
            "2026-01-01_10-04-00-before-pull",
            "2026-01-01_10-03-00-before-pull",
            "2026-01-01_10-02-00-before-pull",
        ])
    }

    func testRemovesEmptySnapshotsEvenWhenUnderTheLimit() throws {
        try snapshot("2026-01-01_10-00-00-before-pull", in: app)
        let empty = app.appendingPathComponent("2026-01-01_10-01-00-before-pull", isDirectory: true)
        try FileManager.default.createDirectory(at: empty.appendingPathComponent("saves"), withIntermediateDirectories: true)

        CloudSaveBackupRetention.prune(appDirectory: app, keep: 3)

        XCTAssertEqual(names(), ["2026-01-01_10-00-00-before-pull"])
    }

    func testNeverPrunesBeforeClearSnapshots() throws {
        try snapshot("2025-01-01_10-00-00-before-clear", in: app)
        for minute in 0..<3 { try snapshot("2026-01-01_10-0\(minute)-00-before-sync", in: app) }

        CloudSaveBackupRetention.prune(appDirectory: app, keep: 1)

        XCTAssertEqual(names(), ["2026-01-01_10-02-00-before-sync", "2025-01-01_10-00-00-before-clear"])
    }

    func testNeverPrunesTheProtectedSnapshot() throws {
        for minute in 0..<3 { try snapshot("2026-01-01_10-0\(minute)-00-before-pull", in: app) }
        let justMade = app.appendingPathComponent("2026-01-01_10-00-00-before-pull", isDirectory: true)

        CloudSaveBackupRetention.prune(appDirectory: app, keep: 1, protecting: justMade)

        XCTAssertEqual(names(), ["2026-01-01_10-02-00-before-pull", "2026-01-01_10-00-00-before-pull"])
    }

    func testLeavesEverythingElseInTheFolderAlone() throws {
        for minute in 0..<3 { try snapshot("2026-01-01_10-0\(minute)-00-before-pull", in: app) }
        try Data("log".utf8).write(to: app.appendingPathComponent("last-sync.log"))
        try snapshot("my manual copy", in: app)

        CloudSaveBackupRetention.prune(appDirectory: app, keep: 1)

        let left = try FileManager.default.contentsOfDirectory(atPath: app.path).sorted()
        XCTAssertEqual(left, ["2026-01-01_10-02-00-before-pull", "last-sync.log", "my manual copy"])
    }

    func testCleanupPlanCoversEveryGame() throws {
        let other = root.appendingPathComponent("379430", isDirectory: true)
        for minute in 0..<4 {
            try snapshot("2026-01-01_10-0\(minute)-00-before-pull", in: app)
            try snapshot("2026-01-01_10-0\(minute)-00-before-sync", in: other)
        }

        let plan = CloudSaveBackupRetention.cleanupPlan(root: root, keep: 3)

        XCTAssertEqual(Set(plan.snapshots.map(\.lastPathComponent)),
                       ["2026-01-01_10-00-00-before-pull", "2026-01-01_10-00-00-before-sync"])
        XCTAssertGreaterThan(plan.bytes, 0)
        // Planning deletes nothing.
        XCTAssertEqual(names().count, 4)
    }

    func testFingerprintChangesWhenASaveChanges() throws {
        let saves = root.appendingPathComponent("saves", isDirectory: true)
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        let save = saves.appendingPathComponent("autosave.whs")
        try Data("a".utf8).write(to: save)
        let before = CloudSaveBackupRetention.fingerprint(of: [saves])

        try Data("ab".utf8).write(to: save)

        XCTAssertNotNil(before)
        XCTAssertNotEqual(CloudSaveBackupRetention.fingerprint(of: [saves]), before)
        XCTAssertNil(CloudSaveBackupRetention.fingerprint(of: [root.appendingPathComponent("missing")]))
    }

    // MARK: - Helpers

    private func snapshot(_ name: String, in dir: URL) throws {
        let saves = dir.appendingPathComponent(name, isDirectory: true).appendingPathComponent("saves", isDirectory: true)
        try FileManager.default.createDirectory(at: saves, withIntermediateDirectories: true)
        try Data("save".utf8).write(to: saves.appendingPathComponent("quicksave.whs"))
    }

    private func names() -> [String] {
        CloudSaveBackupRetention.snapshots(in: app).map(\.lastPathComponent)
    }
}
