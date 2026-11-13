import XCTest
@testable import BEER

/// The update check run after a library refresh, driven against `FakeSteam`.
/// Nothing talks to Steam and nothing outside a temp folder is written.
@MainActor
final class GameUpdateCheckTests: XCTestCase {
    private let account = SteamCloudAccount(accountName: "fake-steam", steamID64: "76561197960287930",
                                            refreshToken: "not-a-real-token", connectedAt: Date())
    private var root: URL!
    private var fakeSteam: FakeSteam!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameUpdateCheckTests-\(UUID().uuidString)", isDirectory: true)
        fakeSteam = try FakeSteam(in: root.appendingPathComponent("FakeSteam", isDirectory: true))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func bottle(_ name: String, status: SteamGameInstallStatus? = .installed) -> Bottle {
        var bottle = Bottle.make(
            name: name,
            runtime: RuntimeCandidate(kind: .gameNativeWine, executablePath: "/tmp/wine", displayName: "Test Wine"),
            graphicsBackend: .automatic
        )
        bottle.gameInstallStatus = status
        return bottle
    }

    private func game(_ appID: Int, in bottle: Bottle?, nonSteam: Bool = false) -> SteamLibraryGame {
        SteamLibraryGame(appID: appID, name: "Game \(appID)", installedBottleID: bottle?.id,
                         isNonSteam: nonSteam ? true : nil)
    }

    private func folder(_ name: String) -> URL { root.appendingPathComponent(name, isDirectory: true) }

    private func target(_ appID: Int, _ name: String) -> GameUpdateCheck.Target {
        GameUpdateCheck.Target(appID: appID, directory: folder(name))
    }

    // MARK: - What gets checked

    func testChecksOnlyInstalledSteamGamesWithReachableFiles() {
        let installed = bottle("Installed")
        let unplugged = bottle("Unplugged")
        let downloading = bottle("Downloading", status: .installing)
        let found = bottle("Found")
        let games = [
            game(1, in: installed),
            game(2, in: unplugged),
            game(3, in: downloading),
            game(-4, in: found, nonSteam: true),
            game(5, in: nil),
        ]

        let targets = GameUpdateCheck.targets(games: games, bottles: [installed, unplugged, downloading, found]) {
            $0.id == unplugged.id ? nil : self.folder($0.name)
        }

        XCTAssertEqual(targets.map(\.appID), [1])
        XCTAssertEqual(targets.map(\.directory), [folder("Installed")])
    }

    /// DLC left out of the download goes with the game, so Steam updating it
    /// doesn't mark a game out of date that Update wouldn't change.
    func testSendsTheDLCLeftOutOfTheDownload() async throws {
        var installed = bottle("Installed")
        installed.skippedDLC = [
            InstallableDLC(appID: 900, name: "Pack", bytes: nil, depotIDs: [150, 151]),
            InstallableDLC(appID: 901, name: "Soundtrack", bytes: nil, depotIDs: [160]),
        ]
        let targets = GameUpdateCheck.targets(games: [game(1, in: installed)], bottles: [installed]) {
            self.folder($0.name)
        }
        XCTAssertEqual(targets.map(\.leftOutDepots), [[150, 151, 160]])

        _ = try await GameUpdateCheck(client: fakeSteam.client).run(
            targets: targets + [target(2, "Two")], account: account
        )
        XCTAssertEqual(fakeSteam.calls().first?.leftOutDepots, [[150, 151, 160], []])
    }

    // MARK: - What Steam says

    func testReportsUpdatesAndLeavesUnknownGamesOut() async throws {
        fakeSteam.gameUpdates = [1: .update, 2: .current]
        let check = GameUpdateCheck(client: fakeSteam.client)

        let results = try await check.run(
            targets: [target(1, "One"), target(2, "Two"), target(3, "Three")], account: account
        )

        XCTAssertEqual(results, [1: .update, 2: .current])
        let calls = fakeSteam.calls()
        XCTAssertEqual(calls.map(\.command), ["updatecheck"])
        XCTAssertEqual(calls.first?.appIDs, [1, 2, 3])
        XCTAssertEqual(calls.first?.directories, [folder("One").path, folder("Two").path, folder("Three").path])
    }

    func testAFailedCheckThrowsSoNothingChanges() async {
        fakeSteam.signInExpired = true
        let check = GameUpdateCheck(client: fakeSteam.client)
        do {
            _ = try await check.run(targets: [target(1, "One")], account: account)
            XCTFail("expected the expired sign-in to throw")
        } catch CloudSyncClientError.authExpired {
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testNoInstalledGamesMeansNoLogon() async throws {
        let results = try await GameUpdateCheck(client: fakeSteam.client).run(targets: [], account: account)
        XCTAssertEqual(results, [:])
        XCTAssertTrue(fakeSteam.calls().isEmpty)
    }

    func testReadsTheHelpersAnswer() {
        let statuses = CloudSyncClient.updateStatuses(from: [
            ["appid": 1, "status": "update"],
            ["appid": 2, "status": "current"],
            ["appid": 3, "status": "something new"],
            ["appid": 4, "status": "untracked"],
            ["status": "update"],
        ])
        XCTAssertEqual(statuses, [1: .update, 2: .current, 3: .unknown, 4: .untracked])
    }

    // MARK: - Found games

    /// A game added from the found-games banner is a BEER download on a drive,
    /// so it's checked like any other, from its folder on that drive.
    func testAFoundGameOnADriveIsChecked() async throws {
        let drives = FakeDrives()
        let drive = try drives.plugIn("Big Drive", at: root.appendingPathComponent("BigDrive", isDirectory: true))
        let folder = AppPaths.driveGamesDirectory(onDriveAt: drive.root).appendingPathComponent("Fallout 4", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(count: 1024).write(to: folder.appendingPathComponent("Fallout4.exe"))
        try GameFolderMarkerFile.write(
            GameFolderMarker(appID: 377160, name: "Fallout 4", isNonSteam: false, launchExecutable: "Fallout4.exe"),
            in: folder
        )
        let found = try XCTUnwrap(FoundGameScanner.scan(
            drive, bottles: [], ownedAppIDs: [377160], installedAppIDs: [], volumes: drives.catalog
        ).first)
        XCTAssertTrue(found.canAdd)

        // The bottle `FoundGamesStore.add` makes for it.
        var bottle = bottle("Fallout 4")
        bottle.steamAppID = 377160
        bottle.gameInstallDirectory = found.folder.path
        bottle.gameDrive = found.drive.link
        let library = [game(377160, in: bottle)]
        let targets = GameUpdateCheck.targets(games: library, bottles: [bottle]) {
            $0.installLocation(volumes: drives.catalog).url
        }
        XCTAssertEqual(targets.map(\.appID), [377160])
        XCTAssertEqual(targets.map { GameFolders.canonicalPath($0.directory) }, [GameFolders.canonicalPath(folder)])

        fakeSteam.gameUpdates = [377160: .update]
        let results = try await GameUpdateCheck(client: fakeSteam.client).run(targets: targets, account: account)
        XCTAssertEqual(results, [377160: .update])

        // Unplugged, it isn't asked about and keeps what it had.
        drives.unplug(drive)
        XCTAssertTrue(GameUpdateCheck.targets(games: library, bottles: [bottle]) {
            $0.installLocation(volumes: drives.catalog).url
        }.isEmpty)
    }

    // MARK: - The library's statuses

    func testStatusesChangeOnlyForCheckedGames() throws {
        var outdated = game(1, in: nil)
        outdated.updateStatus = .update
        var unplugged = game(3, in: nil)
        unplugged.updateStatus = .update
        let games = [outdated, game(2, in: nil), unplugged, game(4, in: nil)]

        let updated = try XCTUnwrap(SteamLibraryStore.applying(
            updateCheck: [1: .current, 2: .update, 4: .untracked], to: games
        ))

        XCTAssertEqual(updated.map(\.updateStatus), [.current, .update, .update, .untracked])
        XCTAssertEqual(updated.map(\.effectiveUpdateAvailable), [false, true, true, false])
        XCTAssertEqual(updated.map(\.isUpdateUntracked), [false, false, false, true])
    }

    func testUnknownNeverOverwritesAnAnswer() {
        var outdated = game(1, in: nil)
        outdated.updateStatus = .update
        XCTAssertNil(SteamLibraryStore.applying(updateCheck: [1: .unknown], to: [outdated]))
    }

    func testNoChangeMeansNothingToSave() {
        var outdated = game(1, in: nil)
        outdated.updateStatus = .update
        XCTAssertNil(SteamLibraryStore.applying(updateCheck: [1: .update, 99: .update], to: [outdated, game(2, in: nil)]))
    }

    func testUntrackedGamesReportedSoTheyCanBeChecked() async throws {
        fakeSteam.gameUpdates = [480: .untracked]
        let results = try await GameUpdateCheck(client: fakeSteam.client).run(targets: [target(480, "Spacewar")], account: account)
        XCTAssertEqual(results, [480: .untracked])
    }

    func testRefreshKeepsTheStatus() {
        var outdated = game(1, in: nil)
        outdated.updateStatus = .update
        let merged = SteamLibraryStore.merge(existing: [outdated], fetched: [SteamLibraryGame(appID: 1, name: "Fresh")])
        XCTAssertEqual(merged.first?.updateStatus, .update)
    }

    func testOldSavedGamesDecodeWithoutTheStatus() throws {
        let decoded = try JSONDecoder().decode(SteamLibraryGame.self, from: Data(#"{"appID": 5, "name": "Old"}"#.utf8))
        XCTAssertNil(decoded.updateStatus)
        XCTAssertFalse(decoded.effectiveUpdateAvailable)
    }
}
