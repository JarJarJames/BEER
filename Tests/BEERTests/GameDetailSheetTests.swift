import XCTest
@testable import BEER

/// Which sheet and dialog the game page shows: one at a time, a new one
/// replacing the old, and Install waiting on sign-in carrying on once the
/// sign-in sheet closes signed in. Steam is `FakeSteam` and the drives are
/// fake; nothing signs in or downloads.
@MainActor
final class GameDetailSheetTests: XCTestCase {
    private let account = SteamCloudAccount(accountName: "fake-steam", steamID64: "76561197960287930",
                                            refreshToken: "not-a-real-token", connectedAt: Date())
    private var root: URL!
    private var fakeSteam: FakeSteam!
    private var auth: SteamAuthStore!
    private var model: GameDetailViewModel!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameDetailSheetTests-\(UUID().uuidString)", isDirectory: true)
        fakeSteam = try FakeSteam(in: root.appendingPathComponent("FakeSteam", isDirectory: true))
        fakeSteam.installSizes = [620: 12_000_000_000]
        auth = SteamAuthStore()
        model = makeModel(game: SteamLibraryGame(appID: 620, name: "Portal 2"))
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel(game: SteamLibraryGame) -> GameDetailViewModel {
        let bottles = BottleStore()
        bottles.rosettaInstalled = { true }
        let model = GameDetailViewModel(game: game, dependencies: GameDetailDependencies(
            library: SteamLibraryStore(), bottles: bottles, detector: ToolchainDetector(),
            depotCtl: DepotDownloaderController(), downloads: DownloadsStore(), goldberg: GoldbergInstaller(),
            cloudAuth: auth, cloudSync: CloudSyncEngine(), presence: SteamPresenceStore(),
            graphicsTranslator: GraphicsTranslatorInstaller(), dlcStore: DLCStore(),
            drives: InstallVolumeMonitor(source: FakeDrives().catalog), mover: GameMover()
        ))
        let wine = "/nonexistent/runtime/bin/wine64"
        let runtime = RuntimeCandidate(kind: .systemWine, executablePath: wine, displayName: "Managed GPTK",
                                       entrypoints: RuntimeEntrypoints(wine: wine, wineboot: nil, wineserver: nil))
        model.preferredRuntime = { runtime }
        model.installSpaceCheck = InstallSpaceCheck(client: fakeSteam.client, freeSpace: { _ in
            VolumeSpace(availableBytes: 500_000_000_000, name: "Macintosh HD")
        })
        return model
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2000 where !condition() {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition(), "Timed out", file: file, line: line)
    }

    // MARK: - One sheet at a time

    func testOpeningASheetReplacesTheOneUp() {
        model.sheet = .artwork
        model.requestInstall()   // signed out, so it asks to sign in first
        XCTAssertEqual(model.sheet, .cloudConnect)

        model.sheet = .shortcutIcon
        model.showCloudError(CloudSyncClientError.authExpired)
        XCTAssertEqual(model.sheet, .cloudConnect, "an expired sign-in opens Reconnect in place of the open sheet")
    }

    func testClosingASheetLeavesNothingUp() {
        model.sheet = .move
        model.sheetClosed()
        XCTAssertNil(model.sheet)
    }

    func testTheRestoreAskLivesInTheBackupsSheet() {
        let plan = SaveRestorePlan(
            snapshot: CloudSaveSnapshot(url: root.appendingPathComponent("before-sync"), date: Date(),
                                        label: "before-sync", fileCount: 1, byteCount: 10),
            folders: [], filesRestored: 1, filesRemoved: 0, currentLastChanged: nil
        )
        model.sheet = .saveBackups(confirmingRestore: nil)
        let opened = model.sheet?.id

        model.restorePlanToConfirm = plan
        XCTAssertEqual(model.sheet, .saveBackups(confirmingRestore: plan))
        XCTAssertEqual(model.sheet?.id, opened, "asking mustn't reopen the sheet")

        model.sheetClosed()
        XCTAssertNil(model.restorePlanToConfirm, "closing the sheet drops its question")

        model.restorePlanToConfirm = plan
        XCTAssertNil(model.sheet, "a plan worked out after the sheet closed isn't shown")
    }

    // MARK: - Sign in, then install

    func testSigningInFromInstallOpensTheInstallSheetOnceSignInCloses() async {
        model.requestInstall()
        XCTAssertEqual(model.sheet, .cloudConnect)
        XCTAssertTrue(model.shouldResumeInstallAfterCloudConnect)

        // What SteamCloudQRSheet does: report the sign-in, then close itself.
        auth.account = account
        model.cloudDidConnect()
        XCTAssertEqual(model.sheet, .cloudConnect, "the install sheet waits for sign-in to close")
        model.sheetClosed()

        XCTAssertEqual(model.sheet, .install)
        XCTAssertFalse(model.shouldResumeInstallAfterCloudConnect)
        await waitUntil { self.model.installSize != nil }
        XCTAssertEqual(model.installSize?.bytes, 12_000_000_000)
    }

    func testClosingSignInWithoutSigningInOpensNothing() {
        model.requestInstall()
        model.sheetClosed()

        XCTAssertNil(model.sheet, "neither the install sheet nor sign-in again")
        XCTAssertTrue(model.shouldResumeInstallAfterCloudConnect, "signing in later still carries on to Install")
    }

    func testOtherSheetsClosingDoNotStartAnInstall() {
        model.requestInstall()
        auth.account = account
        model.sheet = .artwork
        model.sheetClosed()

        XCTAssertNil(model.sheet)
    }

    // MARK: - Dialogs

    func testRemovingANonSteamGameAsksWithoutClosingTheSheet() {
        var game = SteamLibraryGame(appID: 620, name: "Portal 2")
        game.isNonSteam = true
        let model = makeModel(game: game)
        model.sheet = .artwork

        model.requestUninstall()

        XCTAssertEqual(model.dialog, .removeNonSteamGame)
        XCTAssertEqual(model.sheet, .artwork)
    }
}
