import XCTest
@testable import BEER

/// Leaving DLC out of a game's download from the install sheet: the size the
/// sheet shows and checks, and the depots DepotDownloader is told to fetch.
/// Driven against `FakeSteam`; nothing talks to Steam.
@MainActor
final class InstallDLCChoiceTests: XCTestCase {
    private let gb: Int64 = 1024 * 1024 * 1024
    private let account = SteamCloudAccount(accountName: "fake-steam", steamID64: "76561197960287930",
                                            refreshToken: "not-a-real-token", connectedAt: Date())
    private var root: URL!
    private var fakeSteam: FakeSteam!

    /// Shaped like Fallout 4: the game, a story DLC, and a big texture pack,
    /// all among the game's own depots.
    private lazy var storyDLC = InstallableDLC(appID: 20, name: "Far Harbor", bytes: 5 * gb, depotIDs: [21])
    private lazy var texturePack = InstallableDLC(appID: 30, name: "HD Texture Pack", bytes: 58 * gb, depotIDs: [31, 32])

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallDLCChoiceTests-\(UUID().uuidString)", isDirectory: true)
        fakeSteam = try FakeSteam(in: root.appendingPathComponent("FakeSteam", isDirectory: true))
        fakeSteam.installSizes = [10: 93 * gb]
        fakeSteam.installDepots = [10: [11, 12, 21, 31, 32]]
        fakeSteam.installDLC = [10: [storyDLC, texturePack]]
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func check(freeBytes: Int64) -> InstallSpaceCheck {
        InstallSpaceCheck(client: fakeSteam.client, freeSpace: { _ in
            VolumeSpace(availableBytes: freeBytes, name: "Macintosh HD")
        })
    }

    func testSizeListsTheDLCThatComeWithTheGame() async {
        let size = await check(freeBytes: 500 * gb).size(appIDs: [10], account: account)

        XCTAssertEqual(size.bytes, 93 * gb)
        XCTAssertEqual(size.dlc, [storyDLC, texturePack])
        XCTAssertEqual(size.depotIDs, [11, 12, 21, 31, 32])
    }

    func testLeavingTheTexturePackOutMakesItFit() async {
        let check = check(freeBytes: 64 * gb)
        let size = await check.size(appIDs: [10], account: account)

        let everything = await check.assess(size, destination: root)
        guard case .short = everything.verdict else { return XCTFail("93 GB shouldn't fit in 64 GB") }

        let withoutPack = await check.assess(size.leavingOut([30]), destination: root)
        XCTAssertEqual(withoutPack.installBytes, 35 * gb)
        XCTAssertEqual(withoutPack.verdict, .fits)
    }

    func testLeavingDLCOutPassesTheRestAsDepots() {
        let size = InstallSize(bytes: 93 * gb, uncheckedReason: nil,
                               dlc: [storyDLC, texturePack], depotIDs: [11, 12, 21, 31, 32])

        XCTAssertEqual(size.depots(leavingOut: [texturePack]), [11, 12, 21])
        XCTAssertNil(size.depots(leavingOut: []), "with everything ticked DepotDownloader picks the depots itself")
    }

    func testNoDepotListMeansNothingCanBeLeftOut() {
        let size = InstallSize(bytes: 93 * gb, uncheckedReason: nil, dlc: [texturePack], depotIDs: [])
        XCTAssertNil(size.depots(leavingOut: [texturePack]))
    }

    func testDepotsReachDepotDownloader() {
        let args = DepotDownloaderController.downloadArguments(
            appID: 10, installDir: URL(fileURLWithPath: "/tmp/game"),
            accountName: "someone", loginID: 1234, depots: [11, 12, 21])

        let flag = args.firstIndex(of: "-depot")
        XCTAssertNotNil(flag)
        XCTAssertEqual(flag.map { Array(args[($0 + 1)...]) }, ["11", "12", "21"])
    }

    func testNoDepotsLeavesTheChoiceToDepotDownloader() {
        let args = DepotDownloaderController.downloadArguments(
            appID: 10, installDir: URL(fileURLWithPath: "/tmp/game"),
            accountName: "someone", loginID: 1234)
        XCTAssertFalse(args.contains("-depot"))
    }

    func testOlderHelperOutputHasNoDLC() {
        let contents = CloudSyncClient.installContents(from: ["bytes": NSNumber(value: 5 * gb)])
        XCTAssertEqual(contents, CloudSyncClient.InstallContents(bytes: 5 * gb, depotIDs: [], dlc: []))
    }
}
