import XCTest
@testable import BEER

/// The check a game install runs before downloading, driven end to end against
/// a stand-in for the CloudSync helper and a faked free-space reading. Nothing
/// talks to Steam and nothing big is written to disk.
@MainActor
final class InstallSpaceCheckTests: XCTestCase {
    private let gb: Int64 = 1024 * 1024 * 1024
    private let margin = DiskSpaceLimits.safetyMarginBytes
    private let account = SteamCloudAccount(accountName: "stand-in", steamID64: "76561197960287930",
                                            refreshToken: "not-a-real-token", connectedAt: Date())
    private var root: URL!
    private var standIn: CloudSyncStandIn!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallSpaceCheckTests-\(UUID().uuidString)", isDirectory: true)
        standIn = try CloudSyncStandIn(in: root.appendingPathComponent("StandIn", isDirectory: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func check(freeBytes: Int64?) -> InstallSpaceCheck {
        InstallSpaceCheck(client: standIn.client, freeSpace: { _ in freeBytes.map { ($0, "Macintosh HD") } })
    }

    func testRefusesAGameTheDiskCantHold() async {
        standIn.installBytes = 100 * gb
        let result = await check(freeBytes: 64 * gb).run(appID: 1, account: account, installDir: nil)
        XCTAssertEqual(result, .short(DiskSpaceShortfall(
            neededBytes: 100 * gb + margin, availableBytes: 64 * gb, volumeName: "Macintosh HD")))
        XCTAssertEqual(standIn.calls().map(\.command), ["installsize"])
    }

    func testAllowsAGameThatFitsWithTheMargin() async {
        standIn.installBytes = 100 * gb
        let result = await check(freeBytes: 100 * gb + margin + 1).run(appID: 1, account: account, installDir: nil)
        XCTAssertEqual(result, .fits)
    }

    func testRefusesWhenOnlyTheMarginWontFit() async {
        standIn.installBytes = 100 * gb
        let result = await check(freeBytes: 101 * gb).run(appID: 1, account: account, installDir: nil)
        guard case .short = result else { return XCTFail("expected a refusal, got \(result)") }
    }

    func testResumedDownloadCountsWhatsAlreadyThere() async throws {
        // Steam says 10 MB; 8 MB came down before the download stopped.
        let installDir = root.appendingPathComponent("drive_c/Games/Game", isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        try Data(count: 8_000_000).write(to: installDir.appendingPathComponent("data.pak"))
        standIn.installBytes = 10_000_000

        // Enough for the last 2 MB plus the margin, not for all 10 MB.
        let free = margin + 5_000_000
        let fresh = await check(freeBytes: free).run(appID: 1, account: account, installDir: nil)
        let resumed = await check(freeBytes: free).run(appID: 1, account: account, installDir: installDir)

        guard case .short = fresh else { return XCTFail("a fresh install shouldn't fit, got \(fresh)") }
        XCTAssertEqual(resumed, .fits)
    }

    func testUnknownSizeLetsTheInstallGoAhead() async {
        standIn.installBytes = nil
        let result = await check(freeBytes: 0).run(appID: 1, account: account, installDir: nil)
        XCTAssertEqual(result, .unchecked(DiskSpaceStrings.unknownSize))
    }

    func testHelperFailureLetsTheInstallGoAhead() async {
        standIn.installBytes = 100 * gb
        standIn.signInExpired = true
        let result = await check(freeBytes: 0).run(appID: 1, account: account, installDir: nil)
        guard case .unchecked = result else { return XCTFail("expected the install to go ahead, got \(result)") }
    }

    func testUnreadableVolumeLetsTheInstallGoAhead() async {
        standIn.installBytes = 100 * gb
        let result = await check(freeBytes: nil).run(appID: 1, account: account, installDir: nil)
        XCTAssertEqual(result, .fits)
    }
}
