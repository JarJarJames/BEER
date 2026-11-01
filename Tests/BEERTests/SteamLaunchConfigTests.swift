import XCTest
@testable import BEER

/// Steam's launch config → a file in the install. Offline: the helper's
/// `launchinfo` output is fed in as JSON, never fetched.
final class SteamLaunchConfigTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SteamLaunchConfigTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - Helper output

    func testParsesLaunchInfoEntries() {
        let json: [[String: Any]] = [
            ["executable": "isaac-ng.exe", "arguments": "", "workingdir": "", "type": "", "description": "Launch"],
            ["executable": "", "arguments": "-x"],
            ["arguments": "-y"],
            ["executable": "Game.exe", "arguments": "-windowed"],
        ]

        XCTAssertEqual(json.compactMap(CloudSyncClient.LaunchEntry.init(json:)), [
            CloudSyncClient.LaunchEntry(executable: "isaac-ng.exe"),
            CloudSyncClient.LaunchEntry(executable: "Game.exe", arguments: "-windowed"),
        ])
    }

    // MARK: - Resolving

    func testPicksSteamsExeOverTheBiggerModUploader() throws {
        try makeFile("isaac-ng.exe", size: 10)
        try makeFile("tools/ModUploader/ModUploader.exe", size: 1_000)

        let target = SteamLaunchResolver.resolve(
            [CloudSyncClient.LaunchEntry(executable: "isaac-ng.exe")], in: root
        )

        XCTAssertEqual(target?.executable.lastPathComponent, "isaac-ng.exe")
    }

    func testFollowsBackslashPaths() throws {
        try makeFile("Bin/Win64/KingdomCome.exe")

        let target = SteamLaunchResolver.resolve(
            [CloudSyncClient.LaunchEntry(executable: #"Bin\Win64\KingdomCome.exe"#, arguments: "-devmode")], in: root
        )

        XCTAssertEqual(target?.executable.standardizedFileURL.path,
                       root.appendingPathComponent("Bin/Win64/KingdomCome.exe").standardizedFileURL.path)
        XCTAssertEqual(target?.arguments, "-devmode")
    }

    func testMatchesComponentsCaseInsensitively() throws {
        try makeFile("bin/game.exe")

        let url = SteamLaunchResolver.locate(#".\BIN\Game.EXE"#, in: root)

        XCTAssertNotNil(url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url!.path))
    }

    func testSkipsEntriesThatAreNotInTheInstall() throws {
        try makeFile("Game.exe")

        let target = SteamLaunchResolver.resolve([
            CloudSyncClient.LaunchEntry(executable: "Missing.exe"),
            CloudSyncClient.LaunchEntry(executable: "Game.exe"),
        ], in: root)

        XCTAssertEqual(target?.executable.lastPathComponent, "Game.exe")
    }

    func testNothingResolvesWhenNoEntryIsOnDisk() {
        XCTAssertNil(SteamLaunchResolver.resolve([CloudSyncClient.LaunchEntry(executable: "Missing.exe")], in: root))
        XCTAssertNil(SteamLaunchResolver.resolve([], in: root))
    }

    func testRejectsPathsOutsideTheInstallAndDirectories() throws {
        try makeFile("Bin/Game.exe")

        XCTAssertNil(SteamLaunchResolver.locate(#"..\Bin\Game.exe"#, in: root.appendingPathComponent("Bin")))
        XCTAssertNil(SteamLaunchResolver.locate("Bin", in: root))
        XCTAssertNil(SteamLaunchResolver.locate("", in: root))
    }

    // MARK: - Bottle metadata

    func testOlderBottlesDecodeAsNotYetChecked() throws {
        let bottle = Bottle.make(
            name: "Isaac",
            runtime: RuntimeCandidate(kind: .gameNativeWine, executablePath: "/tmp/wine", displayName: "Test Wine"),
            graphicsBackend: .automatic
        )
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(bottle)) as? [String: Any])
        json.removeValue(forKey: "steamLaunchConfigChecked")

        let decoded = try JSONDecoder().decode(Bottle.self, from: JSONSerialization.data(withJSONObject: json))

        XCTAssertNil(decoded.steamLaunchConfigChecked)
    }

    private func makeFile(_ relativePath: String, size: Int = 1) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: size).write(to: url)
    }
}
