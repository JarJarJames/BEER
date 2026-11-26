import XCTest
@testable import BEER

/// The game page's install sheet and the checks before a download: where the
/// game can go, whether it fits there, and what stops an install before any
/// bottle exists. Steam, the drives and free space are faked (see
/// FakeGamePage); nothing downloads.
@MainActor
final class GameDetailInstallTests: XCTestCase {
    private let portal = SteamLibraryGame(appID: 620, name: "Portal 2")
    private let gb: Int64 = 1_000_000_000
    private var fake: FakeGamePage!

    override func setUp() async throws {
        fake = try FakeGamePage()
        fake.auth.account = FakeGamePage.account
        fake.steam.installSizes = [620: 12 * gb]
    }

    override func tearDown() async throws {
        // `confirmInstall` remembers the drive in the test runner's defaults.
        UserDefaults.standard.removeObject(forKey: InstallPreferences.lastDriveKey)
        fake.remove()
    }

    private func plugIn(_ name: String, freeBytes: Int64 = 500_000_000_000, exFAT: Bool = false) throws -> InstallVolume {
        let drive = try fake.drives.plugIn(name, at: fake.root.appendingPathComponent(name, isDirectory: true),
                                           format: exFAT ? "ExFAT" : "APFS", symlinks: !exFAT, freeBytes: freeBytes)
        fake.volumes.refresh()
        return drive
    }

    /// The install sheet, once Steam has given the size and the space is checked.
    private func openInstallSheet(_ model: GameDetailViewModel) async {
        model.requestInstall()
        XCTAssertEqual(model.sheet, .install)
        await waitUntil { model.installSpaceReport != nil }
    }

    // MARK: - Where it can go

    func testNewInstallOffersThisMacAndEachConnectedDrive() async throws {
        let ssd = try plugIn("Games SSD")
        let stick = try plugIn("USB Stick", exFAT: true)
        let model = fake.page(for: portal)

        await openInstallSheet(model)

        XCTAssertEqual(model.installOptions.map(\.target), [.thisMac, .drive(ssd), .drive(stick)])
        XCTAssertEqual(model.installOptions.map(\.isEnabled), [true, true, false], "an exFAT drive can't hold a game")
        XCTAssertNil(model.installNote)
    }

    func testDriveChoiceIsCheckedForSpaceOnThatDrive() async throws {
        let small = try plugIn("Small SSD", freeBytes: 10 * gb)
        let model = fake.page(for: portal)
        await openInstallSheet(model)
        XCTAssertEqual(model.installSpaceReport?.verdict, .fits, "this Mac has room")

        model.selectInstallTarget(.drive(small))
        await waitUntil { model.installSpaceReport != nil }

        guard case .short(let shortfall) = model.installSpaceReport?.verdict else {
            return XCTFail("12 GB won't fit in 10 GB: \(String(describing: model.installSpaceReport))")
        }
        XCTAssertEqual(shortfall.volumeName, "Small SSD")
    }

    func testLeavingOutDLCChecksTheSpaceAgain() async throws {
        let ssd = try plugIn("Games SSD", freeBytes: 100 * gb)
        let pack = InstallableDLC(appID: 621, name: "Texture Pack", bytes: 30 * gb, depotIDs: [622])
        fake.steam.installSizes = [620: 120 * gb]
        fake.steam.installDLC = [620: [pack]]
        let model = fake.page(for: portal)
        await openInstallSheet(model)
        model.selectInstallTarget(.drive(ssd))
        await waitUntil { model.installSpaceReport != nil }
        XCTAssertNotEqual(model.installSpaceReport?.verdict, .fits)

        model.setDLC(621, included: false)
        await waitUntil { model.installSpaceReport != nil }

        XCTAssertEqual(model.installSpaceReport?.verdict, .fits, "90 GB fits in 100")
        XCTAssertEqual(fake.steam.calls().filter { $0.command == "installsize" }.count, 1, "Steam is asked the size once")
    }

    func testStoppedDownloadStaysWhereItsFilesAre() async throws {
        _ = try plugIn("Games SSD")
        var bottle = try fake.installedBottle(for: portal)
        bottle.gameInstallStatus = .installing
        bottle.gameLaunchExecutable = nil
        try await fake.seed(bottles: [bottle])
        let model = fake.page(for: portal)

        await openInstallSheet(model)

        XCTAssertEqual(model.installOptions.map(\.target), [.thisMac], "no other place is offered")
        XCTAssertEqual(model.installNote, InstallDriveStrings.resumeHere)
        let folder = bottle.downloadDirectory(gameName: portal.name)
        XCTAssertEqual(model.installDestination(for: .thisMac).partial, folder, "only the rest still needs room")
    }

    func testStoppedDownloadOnAnUnpluggedDriveOffersNowhere() async throws {
        let ssd = try plugIn("Games SSD")
        var bottle = try fake.installedBottle(for: portal, on: ssd)
        bottle.gameInstallStatus = .installing
        bottle.gameLaunchExecutable = nil
        try await fake.seed(bottles: [bottle])
        fake.drives.unplug(ssd)
        fake.volumes.refresh()
        let model = fake.page(for: portal)

        model.requestInstall()

        XCTAssertEqual(model.sheet, .install)
        XCTAssertEqual(model.installOptions, [])
        XCTAssertNil(model.installTarget, "Install stays off")
        XCTAssertEqual(model.installNote, InstallDriveStrings.resumeDriveMissing("Games SSD"))
    }

    // MARK: - Refused before any bottle exists

    func testInstallThatWontFitShowsTheShortfallAndMakesNothing() async throws {
        fake.steam.installSizes = [620: 600 * gb]
        let model = fake.page(for: portal)

        // As Update First and Resume start it: no sheet, so the check runs here.
        model.startInstall(to: .thisMac)
        await waitUntil { model.dialog != nil }

        guard case .diskSpaceShortfall(let shortfall) = model.dialog else {
            return XCTFail("expected the shortfall, got \(String(describing: model.dialog))")
        }
        XCTAssertEqual(shortfall.volumeName, "Macintosh HD")
        XCTAssertFalse(model.isStartingInstall)
        XCTAssertNil(fake.downloads.entry(for: 620), "the Downloads entry goes")
        XCTAssertTrue(fake.bottles.bottles.isEmpty)
    }

    func testInstallToADrivePulledSinceTheSheetFailsAndMakesNothing() async throws {
        let ssd = try plugIn("Games SSD")
        let model = fake.page(for: portal)
        await openInstallSheet(model)
        model.selectInstallTarget(.drive(ssd))
        await waitUntil { model.installSpaceReport != nil }

        // Pulled before the monitor heard: the sheet still lists it.
        fake.drives.unplug(ssd)
        model.confirmInstall()
        await waitUntil { !model.isStartingInstall }

        XCTAssertEqual(fake.downloads.entry(for: 620)?.status, .failed(InstallDriveStrings.driveNotConnected("Games SSD")))
        XCTAssertTrue(fake.bottles.bottles.isEmpty)
    }
}
