import XCTest
@testable import BEER

// Achievements support seeds gbe_fork's steam_settings/achievements.json from
// real Steam data and reads it back locally (no network) to label toasts.
// These cover both directions of that file, plus that Restore cleans it up
// like every other managed file.
final class GoldbergAchievementsTests: XCTestCase {

    private var installDir: URL!
    private var settingsDir: URL!

    override func setUpWithError() throws {
        installDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("beer-achievements-tests-\(UUID().uuidString)", isDirectory: true)
        settingsDir = installDir
            .appendingPathComponent("Bin/Win64", isDirectory: true)
            .appendingPathComponent("steam_settings", isDirectory: true)
        try FileManager.default.createDirectory(at: settingsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: installDir)
    }

    private func achievement(_ name: String, _ display: String, hidden: Bool = false, icon: String? = nil) -> CloudSyncClient.AchievementInfo {
        CloudSyncClient.AchievementInfo(
            name: name, displayName: display, description: "desc for \(name)",
            hidden: hidden, icon: icon, iconGray: nil, unlocked: false, unlockTime: nil
        )
    }

    func testUpdateAchievementsWritesEveryFieldAndIsReadableLocally() throws {
        let n = try GoldbergApplicator.updateAchievements(
            installDir: installDir,
            achievements: [
                achievement("ACH_WIN", "Win the Game", icon: "https://example.com/win.jpg"),
                achievement("ACH_SECRET", "???", hidden: true),
            ]
        )
        XCTAssertEqual(n, 1)

        let data = try Data(contentsOf: settingsDir.appendingPathComponent("achievements.json"))
        let decoded = try JSONDecoder().decode([AchievementDisplayInfo].self, from: data)
        XCTAssertEqual(decoded.count, 2)
        XCTAssertEqual(decoded.first(where: { $0.name == "ACH_WIN" })?.displayName, "Win the Game")
        XCTAssertEqual(decoded.first(where: { $0.name == "ACH_WIN" })?.icon, "https://example.com/win.jpg")
        XCTAssertEqual(decoded.first(where: { $0.name == "ACH_SECRET" })?.hidden, true)

        // readAchievementsSchema is what AchievementWatcher actually calls —
        // must round-trip through the same file with no network involved.
        let readBack = GoldbergApplicator.readAchievementsSchema(installDir: installDir)
        XCTAssertEqual(Set(readBack.map(\.name)), ["ACH_WIN", "ACH_SECRET"])
    }

    func testUpdateAchievementsIntoEverySettingsFolder() throws {
        let second = installDir
            .appendingPathComponent("Tools", isDirectory: true)
            .appendingPathComponent("steam_settings", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let n = try GoldbergApplicator.updateAchievements(
            installDir: installDir, achievements: [achievement("ACH_A", "A")]
        )
        XCTAssertEqual(n, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.appendingPathComponent("achievements.json").path))
    }

    func testRestoreRemovesAchievementsAndStatsFiles() throws {
        _ = try GoldbergApplicator.updateAchievements(installDir: installDir, achievements: [achievement("ACH_A", "A")])
        let statsURL = settingsDir.appendingPathComponent("stats.json")
        try Data("[]".utf8).write(to: statsURL)
        let dllURL = installDir.appendingPathComponent("Bin/Win64/steam_api64.dll")
        try Data("original".utf8).write(to: dllURL)
        try Data("stub".utf8).write(to: dllURL.appendingPathExtension("original"))

        let restored = try GoldbergApplicator.restore(installDir: installDir)
        XCTAssertEqual(restored, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: settingsDir.path))
    }
}
