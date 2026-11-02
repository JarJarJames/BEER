import XCTest
@testable import BEER

/// The check game and DLC installs run before downloading, driven end to end
/// against `FakeSteam` and a faked free-space reading.
/// Nothing talks to Steam and nothing big is written to disk.
@MainActor
final class InstallSpaceCheckTests: XCTestCase {
    private let gb: Int64 = 1024 * 1024 * 1024
    private let margin = DiskSpaceLimits.safetyMarginBytes
    private let account = SteamCloudAccount(accountName: "fake-steam", steamID64: "76561197960287930",
                                            refreshToken: "not-a-real-token", connectedAt: Date())
    private var root: URL!
    private var fakeSteam: FakeSteam!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallSpaceCheckTests-\(UUID().uuidString)", isDirectory: true)
        fakeSteam = try FakeSteam(in: root.appendingPathComponent("FakeSteam", isDirectory: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func check(freeBytes: Int64?) -> InstallSpaceCheck {
        InstallSpaceCheck(client: fakeSteam.client, freeSpace: { _ in
            freeBytes.map { VolumeSpace(availableBytes: $0, name: "Macintosh HD") }
        })
    }

    func testRefusesAGameTheDiskCantHold() async {
        fakeSteam.installSizes = [1: 100 * gb]
        let result = await check(freeBytes: 64 * gb).run(appIDs: [1], account: account, destination: root)
        XCTAssertEqual(result, .short(DiskSpaceShortfall(
            neededBytes: 100 * gb + margin, availableBytes: 64 * gb, volumeName: "Macintosh HD")))
        XCTAssertEqual(fakeSteam.calls().map(\.command), ["installsize"])
        XCTAssertEqual(fakeSteam.calls().map(\.appIDs), [[1]])
    }

    func testAllowsAGameThatFitsWithTheMargin() async {
        fakeSteam.installSizes = [1: 100 * gb]
        let result = await check(freeBytes: 100 * gb + margin + 1).run(appIDs: [1], account: account, destination: root)
        XCTAssertEqual(result, .fits)
    }

    func testRefusesWhenOnlyTheMarginWontFit() async {
        fakeSteam.installSizes = [1: 100 * gb]
        let result = await check(freeBytes: 101 * gb).run(appIDs: [1], account: account, destination: root)
        guard case .short = result else { return XCTFail("expected a refusal, got \(result)") }
    }

    func testResumedDownloadCountsWhatsAlreadyThere() async throws {
        // Steam says 10 MB; 8 MB came down before the download stopped.
        let installDir = root.appendingPathComponent("drive_c/Games/Game", isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        try Data(count: 8_000_000).write(to: installDir.appendingPathComponent("data.pak"))
        fakeSteam.installSizes = [1: 10_000_000]

        // Enough for the last 2 MB plus the margin, not for all 10 MB.
        let free = margin + 5_000_000
        let fresh = await check(freeBytes: free).run(appIDs: [1], account: account, destination: root)
        let resumed = await check(freeBytes: free).run(appIDs: [1], account: account, destination: installDir, partialDownload: installDir)

        guard case .short = fresh else { return XCTFail("a fresh install shouldn't fit, got \(fresh)") }
        XCTAssertEqual(resumed, .fits)
    }

    func testUnknownSizeLetsTheInstallGoAhead() async {
        fakeSteam.installSizes = [:]
        let result = await check(freeBytes: 0).run(appIDs: [1], account: account, destination: root)
        XCTAssertEqual(result, .unchecked(DiskSpaceStrings.unknownSize))
    }

    func testHelperFailureLetsTheInstallGoAhead() async {
        fakeSteam.installSizes = [1: 100 * gb]
        fakeSteam.signInExpired = true
        let result = await check(freeBytes: 0).run(appIDs: [1], account: account, destination: root)
        guard case .unchecked = result else { return XCTFail("expected the install to go ahead, got \(result)") }
    }

    func testUnreadableVolumeLetsTheInstallGoAhead() async {
        fakeSteam.installSizes = [1: 100 * gb]
        let result = await check(freeBytes: nil).run(appIDs: [1], account: account, destination: root)
        XCTAssertEqual(result, .fits)
    }

    // MARK: - Install sheet

    func testReportCarriesTheNumbersTheSheetShows() async {
        fakeSteam.installSizes = [1: 35 * gb]
        let report = await check(freeBytes: 266 * gb).report(appIDs: [1], account: account, destination: root)
        XCTAssertEqual(report, InstallSpaceReport(
            installBytes: 35 * gb, volume: VolumeSpace(availableBytes: 266 * gb, name: "Macintosh HD"), verdict: .fits))
    }

    func testReportStillShowsFreeSpaceWhenTheSizeIsUnknown() async {
        fakeSteam.installSizes = [:]
        let report = await check(freeBytes: 266 * gb).report(appIDs: [1], account: account, destination: root)
        XCTAssertNil(report.installBytes)
        XCTAssertEqual(report.volume, VolumeSpace(availableBytes: 266 * gb, name: "Macintosh HD"))
        XCTAssertEqual(report.verdict, .unchecked(DiskSpaceStrings.unknownSize))
    }

    // MARK: - DLC

    func testDLCBatchIsCheckedTogetherInOneCall() async {
        // Each DLC fits alone; all three together don't.
        fakeSteam.installSizes = [10: 3 * gb, 11: 3 * gb, 12: 3 * gb]
        let free = margin + 5 * gb
        let result = await check(freeBytes: free).run(appIDs: [10, 11, 12], account: account, destination: root)

        XCTAssertEqual(result, .short(DiskSpaceShortfall(
            neededBytes: 9 * gb + margin, availableBytes: free, volumeName: "Macintosh HD")))
        XCTAssertEqual(fakeSteam.calls().map(\.appIDs), [[10, 11, 12]])
    }

    func testDLCIgnoresTheBaseGameAlreadyInTheFolder() async throws {
        // The game's folder is full of base-game files; none of them are the DLC.
        let installDir = root.appendingPathComponent("drive_c/Games/Game", isDirectory: true)
        try FileManager.default.createDirectory(at: installDir, withIntermediateDirectories: true)
        try Data(count: 8_000_000).write(to: installDir.appendingPathComponent("base.pak"))
        fakeSteam.installSizes = [10: 8_000_000]

        let result = await check(freeBytes: margin + 1_000_000).run(appIDs: [10], account: account, destination: installDir)
        guard case .short = result else { return XCTFail("the DLC shouldn't fit, got \(result)") }
    }

    func testDLCWithoutAListedSizeStillCountsTheOthers() async {
        fakeSteam.installSizes = [10: 50 * gb]
        let result = await check(freeBytes: 20 * gb).run(appIDs: [10, 11], account: account, destination: root)
        guard case .short = result else { return XCTFail("the listed DLC alone shouldn't fit, got \(result)") }
    }
}
