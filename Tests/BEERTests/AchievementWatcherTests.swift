import XCTest
@testable import BEER

// AchievementWatcher's only genuinely fallible piece that doesn't need a
// running game or Steam session is parsing gbe_fork's per-user
// achievements.json save state. These cover that parser directly against
// fixture files on disk — no DispatchSource, no network, no account.
final class AchievementWatcherParsingTests: XCTestCase {

    private var fileURL: URL!

    override func setUpWithError() throws {
        fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("beer-achievement-save-\(UUID().uuidString).json")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func write(_ json: String) throws {
        try Data(json.utf8).write(to: fileURL)
    }

    func testParsesEarnedAchievementsWithTimestamps() throws {
        try write("""
        [
          {"name": "ACH_WIN", "earned": true, "earned_time": 1700000000},
          {"name": "ACH_LOSE", "earned": false, "earned_time": 0}
        ]
        """)
        let earned = AchievementWatcher.parseEarned(at: fileURL)
        XCTAssertEqual(earned, ["ACH_WIN": 1700000000])
    }

    func testMissingFileReturnsEmptyRatherThanThrowing() {
        XCTAssertEqual(AchievementWatcher.parseEarned(at: fileURL), [:])
    }

    func testMalformedJSONReturnsEmptyRatherThanThrowing() throws {
        try write("not json")
        XCTAssertEqual(AchievementWatcher.parseEarned(at: fileURL), [:])
    }

    func testEntriesMissingEarnedFlagAreIgnored() throws {
        try write("""
        [ {"name": "ACH_NO_FLAG"} ]
        """)
        XCTAssertEqual(AchievementWatcher.parseEarned(at: fileURL), [:])
    }
}
