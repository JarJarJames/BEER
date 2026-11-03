import XCTest
@testable import BEER

/// Which drives are offered for a game, and which are greyed out and why.
/// Drives are faked; nothing reads a real disk's properties.
final class InstallDriveTests: XCTestCase {
    private var root: URL!
    private var fake: FakeDrives!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("InstallDriveTests-\(UUID().uuidString)", isDirectory: true)
        fake = FakeDrives()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func drive(_ name: String, _ configure: (inout DriveSpec) -> Void = { _ in }) throws -> InstallVolume {
        var spec = DriveSpec()
        configure(&spec)
        return try fake.plugIn(name, at: root.appendingPathComponent(UUID().uuidString), format: spec.format,
                               symlinks: spec.symlinks, caseSensitive: spec.caseSensitive, readOnly: spec.readOnly,
                               local: spec.local, diskImage: spec.diskImage)
    }

    private struct DriveSpec {
        var format = "APFS"
        var symlinks = true
        var caseSensitive = false
        var readOnly = false
        var local = true
        var diskImage = false
    }

    // MARK: - What a drive can hold

    func testAPFSDriveCanHoldAGame() throws {
        XCTAssertNil(try drive("Games").unsupportedReason)
    }

    func testExFATDriveIsGreyedOutWithTheReason() throws {
        let exfat = try drive("Stick") { $0.format = "ExFAT"; $0.symlinks = false }
        XCTAssertEqual(exfat.unsupportedReason, InstallDriveStrings.unsupportedFormat("ExFAT"))
        XCTAssertTrue(exfat.isListed, "shown, so the player learns why it can't be used")
    }

    func testCaseSensitiveDriveIsGreyedOut() throws {
        let drive = try drive("Dev") { $0.format = "APFS (Case-sensitive)"; $0.caseSensitive = true }
        XCTAssertEqual(drive.unsupportedReason, InstallDriveStrings.caseSensitive)
    }

    func testNetworkReadOnlyAndDiskImagesAreNotListed() throws {
        let network = try drive("NAS") { $0.local = false }
        let readOnly = try drive("NTFS") { $0.readOnly = true }
        let image = try drive("Installer") { $0.diskImage = true }
        XCTAssertFalse(network.isListed)
        XCTAssertFalse(readOnly.isListed)
        XCTAssertFalse(image.isListed)
        XCTAssertEqual(InstallTargets.options(drives: fake.drives, macFreeBytes: nil).map(\.target), [.thisMac])
    }

    // MARK: - The list

    func testListStartsWithThisMacThenDrivesByName() throws {
        let zebra = try drive("Zebra")
        let alpha = try drive("alpha")
        let options = InstallTargets.options(drives: fake.drives, macFreeBytes: 10)
        XCTAssertEqual(options.map(\.target), [.thisMac, .drive(alpha), .drive(zebra)])
        XCTAssertEqual(options.first?.availableBytes, 10)
    }

    func testTwoDrivesWithTheSameNameAreBothOffered() throws {
        let first = try drive("Untitled")
        let second = try drive("Untitled")
        let options = InstallTargets.options(drives: fake.drives, macFreeBytes: nil)
        XCTAssertEqual(Set(options.compactMap(\.target.volume?.uuid)), [first.uuid, second.uuid])
        XCTAssertEqual(Set(options.map(\.id)).count, 3, "told apart by ID, not name")
    }

    func testRemembersTheLastDriveWhenItsBack() throws {
        let games = try drive("Games")
        let options = InstallTargets.options(drives: fake.drives, macFreeBytes: nil)
        XCTAssertEqual(InstallTargets.initialSelection(options, rememberedDriveUUID: games.uuid), .drive(games))
        XCTAssertEqual(InstallTargets.initialSelection(options, rememberedDriveUUID: "gone"), .thisMac)
    }

    func testNeverPreselectsADriveThatCantHoldGames() throws {
        let exfat = try drive("Stick") { $0.symlinks = false }
        let options = InstallTargets.options(drives: fake.drives, macFreeBytes: nil)
        XCTAssertEqual(InstallTargets.initialSelection(options, rememberedDriveUUID: exfat.uuid), .thisMac)
    }

    func testMovingGreysOutWhereTheGameAlreadyIs() throws {
        let games = try drive("Games")
        let options = InstallTargets.options(drives: fake.drives, macFreeBytes: nil,
                                             alreadyHere: { $0.holds(games.link) })
        XCTAssertEqual(options.first { $0.target == .drive(games) }?.disabledReason, GameMoveStrings.alreadyHere)
        XCTAssertTrue(options.first { $0.target == .thisMac }?.isEnabled ?? false)
        XCTAssertEqual(InstallTargets.initialSelection(options, rememberedDriveUUID: nil), .thisMac)
    }
}
