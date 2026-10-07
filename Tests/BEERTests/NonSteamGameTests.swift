import XCTest
@testable import BEER

final class NonSteamGameTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NonSteamGameTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Folder transfer

    func testMoveRelocatesFolderAndLeavesNoSource() throws {
        let source = try makeGame(named: "Game")
        let dest = root.appendingPathComponent("prefix/drive_c/Games/Game")

        try GameFolderTransfer.transfer(from: source, to: dest, mode: .move)

        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("bin/game.exe").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
    }

    func testCopyKeepsTheOriginal() throws {
        let source = try makeGame(named: "Game")
        let dest = root.appendingPathComponent("prefix/Games/Game")

        try GameFolderTransfer.transfer(from: source, to: dest, mode: .copy)

        XCTAssertTrue(FileManager.default.fileExists(atPath: dest.appendingPathComponent("save.dat").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.appendingPathComponent("save.dat").path))
    }

    func testNeverOverwritesExistingDestination() throws {
        let source = try makeGame(named: "Game")
        let dest = try makeGame(named: "Existing")

        XCTAssertThrowsError(try GameFolderTransfer.transfer(from: source, to: dest, mode: .move)) {
            guard case GameFolderTransfer.TransferError.destinationExists = $0 else { return XCTFail("\($0)") }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testRejectsDestinationInsideSource() throws {
        let source = try makeGame(named: "Game")

        XCTAssertThrowsError(try GameFolderTransfer.transfer(
            from: source, to: source.appendingPathComponent("nested"), mode: .copy
        ))
    }

    func testRejectsMissingSource() {
        XCTAssertThrowsError(try GameFolderTransfer.transfer(
            from: root.appendingPathComponent("nope"), to: root.appendingPathComponent("dest"), mode: .move
        ))
    }

    func testRelocatedKeepsPathInsideGameFolder() {
        let source = URL(fileURLWithPath: "/Volumes/Games/Game")
        let dest = URL(fileURLWithPath: "/bottle/drive_c/Games/Game")
        let exe = source.appendingPathComponent("bin/game.exe")

        XCTAssertEqual(
            GameFolderTransfer.relocated(exe, from: source, to: dest).path,
            "/bottle/drive_c/Games/Game/bin/game.exe"
        )
    }

    // MARK: - Executable picking

    func testRankedExecutablesPutNameMatchFirstAndDropInstallers() throws {
        let source = try makeGame(named: "Cool Game")
        try Data(count: 5_000_000).write(to: source.appendingPathComponent("bigtool.exe"))
        try Data(count: 10).write(to: source.appendingPathComponent("unins000.exe"))

        let ranked = LaunchExecutableFinder.rankedExecutables(in: source, gameName: "Cool Game")
            .map(\.lastPathComponent)

        XCTAssertEqual(ranked, ["coolgame.exe", "bigtool.exe", "game.exe"])
    }

    // MARK: - Library state

    func testMergeKeepsNonSteamGamesAndBottleLinks() {
        let bottleID = UUID()
        let nonSteam = SteamLibraryGame(appID: -42, name: "Mine", isNonSteam: true)
        let installed = SteamLibraryGame(appID: 10, name: "Old", installedBottleID: bottleID)
        let fresh = SteamLibraryGame(appID: 20, name: "New")

        let merged = SteamLibraryStore.merge(existing: [nonSteam, installed], fetched: [fresh])

        XCTAssertEqual(Set(merged.map(\.appID)), [-42, 10, 20])
        XCTAssertEqual(merged.filter { $0.appID == -42 }.count, 1)
    }

    func testOldLibraryJSONDecodesAsSteamGame() throws {
        let json = #"{"appID": 5, "name": "Old Game"}"#.data(using: .utf8)!

        let game = try JSONDecoder().decode(SteamLibraryGame.self, from: json)

        XCTAssertFalse(game.effectiveIsNonSteam)
        XCTAssertNotNil(game.headerImage)
    }

    func testNonSteamGameNeverPointsAtSteamArtwork() {
        let game = SteamLibraryGame(appID: -1, name: "Mine", isNonSteam: true)

        XCTAssertNil(game.headerImage)
        XCTAssertNil(game.libraryHeroImage)
        XCTAssertNil(game.libraryLogoImage)
    }

    // MARK: - Helpers

    @discardableResult
    private func makeGame(named name: String) throws -> URL {
        let dir = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("bin"), withIntermediateDirectories: true)
        try Data(count: 1000).write(to: dir.appendingPathComponent("bin/game.exe"))
        try Data(count: 2000).write(to: dir.appendingPathComponent("coolgame.exe"))
        try Data("save".utf8).write(to: dir.appendingPathComponent("save.dat"))
        return dir
    }
}
