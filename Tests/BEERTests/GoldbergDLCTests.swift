import XCTest
@testable import BEER

// The `[app::dlcs]` block is what makes a game actually see its DLC, and it is
// spliced into a file the user may also have hand-edited. These cover the
// splice, not the download.
final class GoldbergDLCTests: XCTestCase {

    private var installDir: URL!
    private var settingsDir: URL!
    private var configURL: URL!

    override func setUpWithError() throws {
        installDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("beer-dlc-tests-\(UUID().uuidString)", isDirectory: true)
        settingsDir = installDir
            .appendingPathComponent("Bin/Win64", isDirectory: true)
            .appendingPathComponent("steam_settings", isDirectory: true)
        configURL = settingsDir.appendingPathComponent("configs.app.ini")
        try FileManager.default.createDirectory(at: settingsDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: installDir)
    }

    private func dlc(_ appID: Int, _ name: String) -> InstalledDLC {
        InstalledDLC(appID: appID, name: name, installedAt: Date())
    }

    private func readConfig() throws -> String {
        try String(contentsOf: configURL, encoding: .utf8)
    }

    func testWritesDLCSectionIntoEverySettingsFolder() throws {
        // A second copy of the stub, as games that ship multiple steam_api DLLs have.
        let second = installDir
            .appendingPathComponent("Tools", isDirectory: true)
            .appendingPathComponent("steam_settings", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        let updated = try GoldbergApplicator.updateDLC(
            installDir: installDir,
            dlc: [dlc(3368600, "Brushes with Death"), dlc(3368610, "Legacy of the Forge")]
        )
        XCTAssertEqual(updated, 2)

        for dir in [settingsDir!, second] {
            let text = try String(contentsOf: dir.appendingPathComponent("configs.app.ini"), encoding: .utf8)
            XCTAssertTrue(text.contains("[app::dlcs]"))
            // unlock_all=0 matters: blanket-unlocking answers yes to the fake
            // DLC ids some games probe with to detect an emulator.
            XCTAssertTrue(text.contains("unlock_all=0"))
            XCTAssertTrue(text.contains("3368600=Brushes with Death"))
            XCTAssertTrue(text.contains("3368610=Legacy of the Forge"))
        }
    }

    func testRewriteReplacesPreviousListRatherThanAppending() throws {
        try GoldbergApplicator.updateDLC(installDir: installDir, dlc: [dlc(3368600, "Brushes with Death")])
        try GoldbergApplicator.updateDLC(installDir: installDir, dlc: [dlc(3368610, "Legacy of the Forge")])

        let text = try readConfig()
        XCTAssertEqual(text.components(separatedBy: "[app::dlcs]").count - 1, 1)
        XCTAssertFalse(text.contains("3368600="))
        XCTAssertTrue(text.contains("3368610=Legacy of the Forge"))
    }

    func testPreservesOtherSectionsTheUserMayHaveAdded() throws {
        try """
        [app::general]
        branch_name=public

        [app::dlcs]
        unlock_all=1
        111=Stale entry

        [app::controller]
        steam_input=1
        """.write(to: configURL, atomically: true, encoding: .utf8)

        try GoldbergApplicator.updateDLC(installDir: installDir, dlc: [dlc(3368600, "Brushes with Death")])

        let text = try readConfig()
        XCTAssertTrue(text.contains("branch_name=public"))
        XCTAssertTrue(text.contains("steam_input=1"))
        XCTAssertTrue(text.contains("3368600=Brushes with Death"))
        XCTAssertFalse(text.contains("111=Stale entry"))
        XCTAssertFalse(text.contains("unlock_all=1"))
    }

    func testEmptyListRemovesAFileWeFullyOwn() throws {
        try GoldbergApplicator.updateDLC(installDir: installDir, dlc: [dlc(3368600, "Brushes with Death")])
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path))

        // Turning every DLC off should restore stock emulator behaviour rather
        // than pinning an empty list.
        try GoldbergApplicator.updateDLC(installDir: installDir, dlc: [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: configURL.path))
    }

    func testEmptyListKeepsAFileThatStillHasUserContent() throws {
        try """
        [app::general]
        branch_name=public

        [app::dlcs]
        unlock_all=0
        3368600=Brushes with Death
        """.write(to: configURL, atomically: true, encoding: .utf8)

        try GoldbergApplicator.updateDLC(installDir: installDir, dlc: [])

        let text = try readConfig()
        XCTAssertTrue(text.contains("branch_name=public"))
        XCTAssertFalse(text.contains("[app::dlcs]"))
    }

    func testNameWithNewlineCannotCorruptFollowingEntries() throws {
        try GoldbergApplicator.updateDLC(
            installDir: installDir,
            dlc: [dlc(3368600, "Bad\nunlock_all=1"), dlc(3368610, "Legacy of the Forge")]
        )

        // The newline is folded into the value, so `unlock_all=1` can only
        // survive as part of the name — never as a directive on its own line.
        let lines = try readConfig()
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        XCTAssertFalse(lines.contains("unlock_all=1"))
        XCTAssertTrue(lines.contains("unlock_all=0"))
        XCTAssertTrue(lines.contains("3368600=Bad unlock_all=1"))
        XCTAssertTrue(lines.contains("3368610=Legacy of the Forge"))
    }
}
