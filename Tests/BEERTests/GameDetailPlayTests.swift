import CryptoKit
import XCTest
@testable import BEER

/// Play on the game page: ask about an update first, pull saves, run the
/// game, push what it wrote. Steam is `FakeSteam` and the saves are real files
/// in a temporary bottle; Wine, Discord and the achievement watcher are faked
/// (see FakeGamePage), so nothing runs and nothing signs in.
@MainActor
final class GameDetailPlayTests: XCTestCase {
    private let portal = SteamLibraryGame(appID: 620, name: "Portal 2")
    private let cloudName = "%WinSavedGames%/portal2/save.sav"
    private var fake: FakeGamePage!

    override func setUp() async throws {
        fake = try FakeGamePage()
        fake.auth.account = FakeGamePage.account
    }

    override func tearDown() async throws {
        fake.remove()
    }

    private func saveFile(in bottle: Bottle) -> URL {
        fake.userHome(of: bottle).appendingPathComponent("Saved Games/portal2/save.sav")
    }

    private func localSave(in bottle: Bottle) -> String? {
        try? String(contentsOf: saveFile(in: bottle), encoding: .utf8)
    }

    private func writeSave(_ text: String, in bottle: Bottle) throws {
        let file = saveFile(in: bottle)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file)
    }

    /// Steam holds `text` for the save, uploaded an hour ago.
    private func steamHas(_ text: String) {
        let sha = Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        fake.steam.files = [CloudRemoteFile(filename: cloudName, size: text.utf8.count,
                                            timestamp: Date().addingTimeInterval(-3600), sha: sha)]
        fake.steam.contents = [cloudName: text]
    }

    /// Click Play and wait for the game to exit. What comes after (the push)
    /// is still running: wait for its message.
    private func play(_ model: GameDetailViewModel, _ bottle: Bottle) async {
        model.launch(bottle)
        await waitUntil { self.fake.played.last == "clearFromDiscord" }
    }

    // MARK: - Pull, play, push

    func testPlayPullsSavesThenRunsTheGameThenPushesWhatItWrote() async throws {
        let bottle = try fake.installedBottle(for: portal)
        steamHas("chapter 3")
        var saveWhenStarted: String?
        fake.whilePlaying = { [self] in
            saveWhenStarted = localSave(in: $0)
            try? writeSave("chapter 4", in: $0)
        }
        let model = fake.page(for: portal)

        await play(model, bottle)
        await waitUntil { model.cloudSyncMessage == "Pushed 1 save to cloud after play." }

        XCTAssertEqual(saveWhenStarted, "chapter 3", "Steam's save was down before the game started")
        XCTAssertEqual(fake.played, ["setUpWine", "prepareGame", "showOnDiscord", "watchAchievements",
                                     "runGame", "clearFromDiscord"])
        let uploads = fake.steam.calls().flatMap(\.uploads).map(\.filename)
        XCTAssertEqual(uploads, [cloudName], "what the game wrote went up after play")
        XCTAssertFalse(model.cloudSyncIsError)
    }

    func testGameThatWritesNothingPushesNothing() async throws {
        let bottle = try fake.installedBottle(for: portal)
        steamHas("chapter 3")
        let model = fake.page(for: portal)

        await play(model, bottle)
        await waitUntil { model.cloudSyncMessage == "No save changes to upload." }

        XCTAssertEqual(fake.steam.calls().map(\.command), ["enumerate", "batch"],
                       "only the pull reached Steam: a crash on start costs no push")
    }

    // MARK: - Out of date

    func testOutOfDateGameAsksBeforeTouchingSavesOrWine() throws {
        let bottle = try fake.installedBottle(for: portal)
        var game = portal
        game.updateStatus = .update
        let model = fake.page(for: game)

        model.launch(bottle)

        XCTAssertEqual(model.dialog, .updateBeforePlay(bottle))
        XCTAssertEqual(fake.played, [])
        XCTAssertEqual(fake.steam.calls().count, 0)
        XCTAssertNil(fake.bottles.launchPhase(for: bottle.id))
    }

    func testUpdateFirstOpensTheInstallSheetInsteadOfPlaying() throws {
        let bottle = try fake.installedBottle(for: portal)
        var game = portal
        game.updateStatus = .update
        let model = fake.page(for: game)
        model.launch(bottle)

        model.updateInsteadOfPlaying()

        XCTAssertNil(model.dialog)
        XCTAssertEqual(model.sheet, .install)
        XCTAssertEqual(fake.played, [])
    }

    func testPlayAnywayRunsTheOutOfDateGame() async throws {
        let bottle = try fake.installedBottle(for: portal)
        steamHas("chapter 3")
        var game = portal
        game.updateStatus = .update
        let model = fake.page(for: game)
        model.launch(bottle)

        model.playWithoutUpdating()
        await waitUntil { self.fake.played.last == "clearFromDiscord" }

        XCTAssertNil(model.dialog)
        XCTAssertTrue(fake.played.contains("runGame"))
        XCTAssertEqual(localSave(in: bottle), "chapter 3", "saves were still pulled first")
    }

    // MARK: - No sync

    func testSignedOutPlaysWithoutReachingSteam() async throws {
        fake.auth.account = nil
        let bottle = try fake.installedBottle(for: portal)
        let model = fake.page(for: portal)

        await play(model, bottle)

        XCTAssertEqual(fake.steam.calls().count, 0)
        XCTAssertEqual(fake.played, ["setUpWine", "prepareGame", "showOnDiscord", "runGame", "clearFromDiscord"],
                       "no achievements to watch without an account")
    }

    func testNonSteamGameIsShownOnDiscordButNeverSynced() async throws {
        var game = SteamLibraryGame(appID: -5, name: "Mod Launcher")
        game.isNonSteam = true
        let bottle = try fake.installedBottle(for: game)
        let model = fake.page(for: game)

        await play(model, bottle)

        XCTAssertEqual(fake.steam.calls().count, 0)
        XCTAssertEqual(fake.played, ["setUpWine", "prepareGame", "showOnDiscord", "runGame", "clearFromDiscord"])
    }

    // MARK: - When the pull can't go ahead

    func testExpiredSignInStillLaunches() async throws {
        let bottle = try fake.installedBottle(for: portal)
        fake.steam.signInExpired = true
        let model = fake.page(for: portal)

        await play(model, bottle)
        try await Task.sleep(for: .milliseconds(100))   // time for a push, if one were tried

        XCTAssertTrue(fake.played.contains("runGame"))
        XCTAssertTrue(fake.auth.sessionExpired, "the Steam Cloud row offers Reconnect")
        XCTAssertTrue(model.cloudSyncIsError)
        XCTAssertEqual(fake.steam.calls().count, 1, "no push is tried on the expired sign-in")
    }

    func testRestoredBackupAsksWhichSavesBeforeTheGameRuns() async throws {
        let bottle = try fake.installedBottle(for: portal)
        let saves = saveFile(in: bottle).deletingLastPathComponent()
        try writeSave("chapter 3", in: bottle)
        // Back up chapter 3, play on to chapter 5, then restore the backup.
        let backup = try XCTUnwrap(fake.cloudSync.backUpBeforeWriting(appID: 620, dirs: [saves], label: "before-pull"))
        let snapshot = try XCTUnwrap(fake.cloudSync.saveBackups(appID: 620).first { $0.id == backup.lastPathComponent })
        try writeSave("chapter 5", in: bottle)
        try fake.cloudSync.restore(CloudSyncEngine.restorePlan(for: snapshot, userHome: fake.userHome(of: bottle),
                                                               installDir: nil), appID: 620)
        steamHas("chapter 5")
        let model = fake.page(for: portal)

        model.launch(bottle)
        await waitUntil { model.sheet != nil }

        guard case .restoreConflict(let prompt) = model.sheet else {
            return XCTFail("expected the restore question, got \(String(describing: model.sheet))")
        }
        guard case .launch = prompt.retry else { return XCTFail("choosing should carry on to Play") }
        await waitUntil { self.fake.bottles.launchPhase(for: bottle.id) == nil }
        XCTAssertEqual(fake.played, ["setUpWine"], "the game didn't start on either set of saves")
        XCTAssertEqual(localSave(in: bottle), "chapter 3")
    }

    func testUnpluggedDriveStopsPlayBeforeAnything() async throws {
        let ssd = try fake.drives.plugIn("Games SSD", at: fake.root.appendingPathComponent("Games SSD", isDirectory: true))
        let bottle = try fake.installedBottle(for: portal, on: ssd)
        fake.drives.unplug(ssd)
        let model = fake.page(for: portal)

        model.launch(bottle)

        XCTAssertEqual(model.cloudSyncMessage, InstallDriveStrings.driveMissingDetail("Games SSD"))
        XCTAssertEqual(fake.played, [])
        XCTAssertNil(fake.bottles.launchPhase(for: bottle.id))
    }
}
