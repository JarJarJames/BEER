import XCTest
@testable import BEER

// Saves in a folder with no cloud files used to be invisible to push: it only
// looked where the cloud already had files, so a game's first saves made here,
// or a new save folder per playthrough, never uploaded. The game's Steam Cloud
// save rules now name those folders. These tests stub the helper's
// `enumerate` output and a bottle on disk; nothing talks to Steam.
@MainActor
final class CloudSaveRuleTests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private let steamID64 = "76561197960287930"

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CloudSaveRuleTests-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("drive_c/users/crossover", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - enumerate output

    func testListingReadsFilesAndSaveRules() throws {
        let listing = try CloudListing(json: [
            "files": [["filename": "%WinSavedGames%/game/a.sav", "size": 3, "timestamp": 100, "sha": "ab"]],
            "savefiles": [["root": "WinSavedGames", "path": "game", "pattern": "*.sav",
                           "recursive": true, "platforms": ["Windows"]]],
        ])
        XCTAssertEqual(listing.files, [CloudRemoteFile(filename: "%WinSavedGames%/game/a.sav", size: 3,
                                                        timestamp: Date(timeIntervalSince1970: 100), sha: "ab")])
        XCTAssertEqual(listing.saveRules, [CloudSaveRule(root: "WinSavedGames", path: "game", pattern: "*.sav",
                                                          recursive: true, platforms: ["Windows"])])
    }

    func testListingFromAnOlderHelperHasNoRules() throws {
        let listing = try CloudListing(json: ["files": []])
        XCTAssertEqual(listing.saveRules, [])
    }

    func testListingWithoutFilesIsBadOutput() {
        XCTAssertThrowsError(try CloudListing(json: ["savefiles": []]))
    }

    func testRuleWithEmptyPatternMatchesEverything() throws {
        XCTAssertEqual(CloudSaveRule(json: ["root": "WinSavedGames", "pattern": ""])?.pattern, "*")
        XCTAssertNil(CloudSaveRule(json: ["path": "game"]))
    }

    // MARK: - resolving rules

    func testSteamIDPlaceholdersAreFilledIn() {
        let engine = CloudSyncEngine()
        XCTAssertEqual(engine.expandSavePath("game\\{64BitSteamID}\\saves", steamID64: steamID64),
                       "game/76561197960287930/saves")
        XCTAssertEqual(engine.expandSavePath("game/{Steam3AccountID}", steamID64: steamID64), "game/22202")
    }

    func testPathsNeedingAnUnknownIDOrPlaceholderAreDropped() {
        let engine = CloudSyncEngine()
        XCTAssertNil(engine.expandSavePath("game/{64BitSteamID}", steamID64: "0"))
        XCTAssertNil(engine.expandSavePath("game/{SomethingElse}", steamID64: steamID64))
        XCTAssertEqual(engine.expandSavePath("/game/", steamID64: "0"), "game")
    }

    func testOnlyWindowsRulesOnKnownRootsResolve() {
        let rules = [
            CloudSaveRule(root: "WinSavedGames", path: "a", platforms: ["Windows"]),
            CloudSaveRule(root: "WinAppDataLocal", path: "b", platforms: ["all"]),
            CloudSaveRule(root: "WinMyDocuments", path: "c"),
            CloudSaveRule(root: "MacAppSupport", path: "d", platforms: ["MacOS"]),
            CloudSaveRule(root: "WinSavedGames", path: "e", platforms: ["MacOS"]),
            CloudSaveRule(root: "SomeUnknownRoot", path: "f"),
        ]
        let resolved = CloudSyncEngine().resolveSaveRules(rules, userHome: home, installDir: nil, steamID64: steamID64)
        XCTAssertEqual(resolved.map(\.folder), [
            home.appendingPathComponent("Saved Games/a", isDirectory: true),
            home.appendingPathComponent("AppData/Local/b", isDirectory: true),
            home.appendingPathComponent("Documents/c", isDirectory: true),
        ])
    }

    func testInstallFolderRulesNeedAnInstallFolder() {
        let rule = CloudSaveRule(root: "gameinstall", path: "saves")
        let engine = CloudSyncEngine()
        XCTAssertEqual(engine.resolveSaveRules([rule], userHome: home, installDir: nil, steamID64: steamID64), [])
        let install = root.appendingPathComponent("Game", isDirectory: true)
        XCTAssertEqual(engine.resolveSaveRules([rule], userHome: home, installDir: install, steamID64: steamID64).map(\.folder),
                       [install.appendingPathComponent("saves", isDirectory: true)])
    }

    func testRulesWithoutAPathAreNotSnapshotted() {
        let engine = CloudSyncEngine()
        let resolved = engine.resolveSaveRules([
            CloudSaveRule(root: "WinMyDocuments", path: "", pattern: "*.sav"),
            CloudSaveRule(root: "WinSavedGames", path: "game"),
        ], userHome: home, installDir: nil, steamID64: steamID64)
        XCTAssertEqual(engine.saveFoldersToTrack(resolved), [home.appendingPathComponent("Saved Games/game", isDirectory: true)])
    }

    func testNestedFoldersCollapseToTheOutermost() {
        let outer = home.appendingPathComponent("Saved Games/game", isDirectory: true)
        let inner = outer.appendingPathComponent("saves/slot1", isDirectory: true)
        let other = home.appendingPathComponent("Documents/game", isDirectory: true)
        XCTAssertEqual(CloudSyncEngine().outermostFolders([outer, inner, other]), [outer, other])
    }

    // MARK: - planning uploads

    func testFirstSavesWithAnEmptyCloudUpload() throws {
        let saves = try makeFolder("Saved Games/MyGame/saves")
        try write("slot1.SAV", in: saves)
        try write("notes.txt", in: saves)

        let plan = planUploads(remote: [], rules: [CloudSaveRule(root: "WinSavedGames", path: "MyGame/saves", pattern: "*.sav")])

        XCTAssertEqual(plan.uploads.map(\.filename), ["%WinSavedGames%/MyGame/saves/slot1.SAV"])
        XCTAssertEqual(plan.uploads.map(\.local.lastPathComponent), ["slot1.SAV"])
        XCTAssertTrue(plan.failures.isEmpty)
    }

    func testNewPlaythroughFolderUploadsNextToExistingCloudSaves() throws {
        let old = try write("a.whs", in: try makeFolder("Saved Games/kingdomcome/saves/playline1"))
        try write("b.whs", in: try makeFolder("Saved Games/kingdomcome/saves/playline2"))
        let cloudTime = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: cloudTime], ofItemAtPath: old.path)

        let plan = planUploads(
            remote: [CloudRemoteFile(filename: "%WinSavedGames%/kingdomcome/saves/playline1/a.whs",
                                     size: 4, timestamp: cloudTime, sha: "")],
            rules: [CloudSaveRule(root: "WinSavedGames", path: "kingdomcome/saves", recursive: true)]
        )

        XCTAssertEqual(plan.uploads.map(\.filename), ["%WinSavedGames%/kingdomcome/saves/playline2/b.whs"])
        XCTAssertEqual(plan.skipped, 1, "the save already in the cloud is up to date")
    }

    func testNonRecursiveRulesLeaveSubfoldersAlone() throws {
        let saves = try makeFolder("Saved Games/game")
        try write("top.sav", in: saves)
        try write("deep.sav", in: try makeFolder("Saved Games/game/backup"))

        let plan = planUploads(remote: [], rules: [CloudSaveRule(root: "WinSavedGames", path: "game")])

        XCTAssertEqual(plan.uploads.map(\.filename), ["%WinSavedGames%/game/top.sav"])
    }

    func testSteamsOwnNameForAFolderBeatsTheRule() throws {
        let saves = try makeFolder("Saved Games/game")
        let existing = try write("old.sav", in: saves)
        try write("new.sav", in: saves)
        let cloudTime = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: cloudTime], ofItemAtPath: existing.path)

        let plan = planUploads(
            remote: [CloudRemoteFile(filename: "%WINSAVEDGAMES%/game/old.sav", size: 4, timestamp: cloudTime, sha: "")],
            rules: [CloudSaveRule(root: "WinSavedGames", path: "game")]
        )

        XCTAssertEqual(plan.uploads.map(\.filename), ["%WINSAVEDGAMES%/game/new.sav"])
    }

    func testPlaceholderFoldersUploadUnderTheExpandedName() throws {
        let saves = try makeFolder("AppData/Roaming/game/22202")
        try write("profile.dat", in: saves)

        let plan = planUploads(remote: [], rules: [CloudSaveRule(root: "WinAppDataRoaming", path: "game/{Steam3AccountID}")])

        XCTAssertEqual(plan.uploads.map(\.filename), ["%WinAppDataRoaming%/game/22202/profile.dat"])
    }

    func testWithoutRulesANewFolderStaysUnseen() throws {
        try write("slot1.sav", in: try makeFolder("Saved Games/MyGame/saves"))

        let plan = planUploads(remote: [], rules: [])

        XCTAssertTrue(plan.uploads.isEmpty)
        XCTAssertTrue(plan.failures.isEmpty)
    }

    // MARK: - helpers

    private func planUploads(remote: [CloudRemoteFile], rules: [CloudSaveRule]) -> CloudSyncEngine.UploadPlan {
        let engine = CloudSyncEngine()
        let resolved = engine.resolveSaveRules(rules, userHome: home, installDir: nil, steamID64: steamID64)
        let cloudDirs = Set(remote.compactMap {
            engine.mapToLocal($0.filename, userHome: home, installDir: nil)?.deletingLastPathComponent()
        })
        return engine.planUploads(remote: remote, cloudDirs: cloudDirs, ruleMatches: resolved.flatMap(engine.matches(of:)),
                                  userHome: home, installDir: nil)
    }

    private func makeFolder(_ relative: String) throws -> URL {
        let url = home.appendingPathComponent(relative, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    private func write(_ name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data("save".utf8).write(to: url)
        return url
    }
}
