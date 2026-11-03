import XCTest
@testable import BEER

/// The free-space check that refuses installs the disk can't hold. Offline:
/// the helper's `installsize` output is fed in as JSON, never fetched.
final class DiskSpaceCheckTests: XCTestCase {
    private let gb: Int64 = 1024 * 1024 * 1024

    // MARK: - Fitting

    func testFitsWithTheMarginToSpare() {
        XCTAssertNil(DiskSpaceCheck.shortfall(installBytes: 50 * gb, availableBytes: 60 * gb, volumeName: "Macintosh HD", margin: 5 * gb))
    }

    func testRefusesWhenOnlyTheMarginWontFit() {
        let shortfall = DiskSpaceCheck.shortfall(installBytes: 50 * gb, availableBytes: 52 * gb, volumeName: "Macintosh HD", margin: 5 * gb)
        XCTAssertEqual(shortfall, DiskSpaceShortfall(neededBytes: 55 * gb, availableBytes: 52 * gb, volumeName: "Macintosh HD"))
        XCTAssertEqual(shortfall?.missingBytes, 3 * gb)
    }

    func testResumedDownloadOnlyNeedsWhatsLeft() {
        // 90 of 100 GB already downloaded, 20 GB free: the rest fits.
        XCTAssertNil(DiskSpaceCheck.shortfall(installBytes: 100 * gb, alreadyOnDisk: 90 * gb, availableBytes: 20 * gb, volumeName: "Macintosh HD", margin: 5 * gb))
    }

    func testCompleteInstallStillKeepsTheMargin() {
        let shortfall = DiskSpaceCheck.shortfall(installBytes: 10 * gb, alreadyOnDisk: 12 * gb, availableBytes: 1 * gb, volumeName: "Macintosh HD", margin: 5 * gb)
        XCTAssertEqual(shortfall?.neededBytes, 5 * gb)
    }

    func testShortfallMessageNamesTheNumbers() {
        let message = DiskSpaceStrings.shortfall(DiskSpaceShortfall(neededBytes: 112_000_000_000, availableBytes: 64_000_000_000, volumeName: "Macintosh HD"))
        XCTAssertTrue(message.contains("112 GB"), message)
        XCTAssertTrue(message.contains("64 GB"), message)
        XCTAssertTrue(message.contains("Macintosh HD"), message)
        XCTAssertTrue(message.contains("48 GB"), message)
    }

    // MARK: - Disk

    func testFreeSpaceWalksUpToAnExistingFolder() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("DiskSpaceCheckTests-\(UUID().uuidString)/a/b")
        XCTAssertNotNil(DiskSpaceCheck.freeSpace(at: missing))
    }

    func testAllocatedSizeCountsFilesAndIgnoresAMissingFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DiskSpaceCheckTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertEqual(DiskSpaceCheck.allocatedSize(of: root), 0)

        try FileManager.default.createDirectory(at: root.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try Data(count: 100_000).write(to: root.appendingPathComponent("sub/game.pak"))
        XCTAssertGreaterThanOrEqual(DiskSpaceCheck.allocatedSize(of: root), 100_000)
    }

    // MARK: - Helper output

    func testParsesInstallSize() {
        XCTAssertEqual(CloudSyncClient.installBytes(from: ["bytes": NSNumber(value: 123_456_789_012 as Int64)]), 123_456_789_012)
    }

    func testUnknownOrMalformedSizeIsNil() {
        XCTAssertNil(CloudSyncClient.installBytes(from: ["bytes": NSNull()]))
        XCTAssertNil(CloudSyncClient.installBytes(from: ["bytes": NSNumber(value: 0)]))
        XCTAssertNil(CloudSyncClient.installBytes(from: ["bytes": "lots"]))
        XCTAssertNil(CloudSyncClient.installBytes(from: [:]))
    }
}
