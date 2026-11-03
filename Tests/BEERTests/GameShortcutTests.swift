import CoreGraphics
import ImageIO
import XCTest
@testable import BEER

/// Game shortcuts: the `beer://` link, the icon, the `.app` on disk, and
/// removing it again. Everything is written to a temporary folder in place of
/// the Desktop and ~/Applications, and artwork comes from memory, not Steam.
@MainActor
final class GameShortcutTests: XCTestCase {
    private var root: URL!
    private var store: GameShortcutStore!
    /// What each artwork address returns. An address missing here fails.
    private final class Artwork: @unchecked Sendable {
        private let lock = NSLock()
        private var served: [URL: Data] = [:]
        subscript(url: URL) -> Data? {
            get { lock.withLock { served[url] } }
            set { lock.withLock { served[url] = newValue } }
        }
        func removeAll() { lock.withLock { served = [:] } }
    }
    private let artwork = Artwork()

    private let coverURL = URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/42/library_600x900_2x.jpg")!
    private let iconURL = URL(string: "https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/42/abc.ico")!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameShortcutTests-\(UUID().uuidString)", isDirectory: true)
        store = GameShortcutStore(locations: .init(
            desktop: root.appendingPathComponent("Desktop", isDirectory: true),
            applications: root.appendingPathComponent("Applications", isDirectory: true),
            records: root.appendingPathComponent("shortcuts.json")
        ))
        artwork.removeAll()
        artwork[coverURL] = TestImages.png(width: 600, height: 900)
        store.fetch = { [artwork] url in
            guard let data = artwork[url] else { throw URLError(.fileDoesNotExist) }
            return data
        }
        store.announce = { _ in }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func game(_ name: String = "Kingdom Come: Deliverance", icon: ShortcutIconChoice? = nil,
                      clientIconURL: URL? = nil) -> SteamLibraryGame {
        SteamLibraryGame(appID: 42, name: name, clientIconURL: clientIconURL?.absoluteString, shortcutIcon: icon)
    }

    // MARK: - Link

    func testLinkRoundTrips() {
        let link = GameShortcutLink(appID: 379430)
        XCTAssertEqual(link.url.absoluteString, "beer://game/379430")
        XCTAssertEqual(GameShortcutLink(url: link.url), link)
    }

    func testLinkCarriesNonSteamGames() {
        // Non-Steam games have negative placeholder IDs.
        XCTAssertEqual(GameShortcutLink(url: GameShortcutLink(appID: -7).url)?.appID, -7)
    }

    func testLinkRejectsAnythingElse() {
        for text in ["https://game/42", "beer://store/42", "beer://game/", "beer://game/abc",
                     "beer://game/42/extra", "beer://game/0"] {
            XCTAssertNil(GameShortcutLink(url: URL(string: text)!), text)
        }
    }

    func testRouterOpensThePageAndAsksForALaunch() {
        let router = GameLinkRouter()
        XCTAssertTrue(router.open(URL(string: "beer://game/42")!))
        XCTAssertEqual(router.requestedAppID, 42)
        XCTAssertEqual(router.pendingLaunchAppID, 42)
        XCTAssertFalse(router.open(URL(string: "https://example.com")!))
    }

    // MARK: - Cover crop

    private let cover = CGSize(width: 600, height: 900)

    func testCenteredCropIsTheMiddleSquare() {
        XCTAssertEqual(CoverCrop.centered.rect(in: cover), CGRect(x: 0, y: 150, width: 600, height: 600))
    }

    func testCropStaysInsideTheImage() {
        let dragged = CoverCrop(centerX: 2, centerY: -1, scale: 0.5)
        XCTAssertEqual(dragged.rect(in: cover), CGRect(x: 300, y: 0, width: 300, height: 300))
        XCTAssertEqual(dragged.clamped(to: cover), CoverCrop(centerX: 0.75, centerY: 1.0 / 6, scale: 0.5))
    }

    func testZoomStopsAtTheLimits() {
        XCTAssertEqual(CoverCrop(centerX: 0.5, centerY: 0.5, scale: 0.01).rect(in: cover).width,
                       600 * CoverCrop.minimumScale)
        XCTAssertEqual(CoverCrop(centerX: 0.5, centerY: 0.5, scale: 3).rect(in: cover).width, 600)
    }

    // MARK: - Steam's icon

    func testReadsTheHelpersIconAnswer() {
        XCTAssertEqual(CloudSyncClient.clientIconURL(appID: 42, from: ["clienticon": "abc"]), iconURL)
        XCTAssertNil(CloudSyncClient.clientIconURL(appID: 42, from: ["clienticon": NSNull()]))
        XCTAssertNil(CloudSyncClient.clientIconURL(appID: 42, from: [:]))
    }

    func testSteamIconNeedsA256Image() {
        XCTAssertNil(ShortcutIconImage.steamIcon(from: TestImages.ico(sides: [16, 32])))
        XCTAssertNil(ShortcutIconImage.steamIcon(from: TestImages.ico(sides: [32, 64, 128])))
        XCTAssertEqual(ShortcutIconImage.steamIcon(from: TestImages.ico(sides: [16, 32, 256]))?.width, 256)
    }

    func testSteamIconTakesTheLargestImage() {
        XCTAssertEqual(ShortcutIconImage.steamIcon(from: TestImages.ico(sides: [256, 32, 512]))?.width, 512)
    }

    func testIcnsHoldsEverySize() throws {
        let square = try XCTUnwrap(ShortcutIconImage.image(from: TestImages.png(width: 600, height: 600)))
        let icns = try XCTUnwrap(ShortcutIconImage.icns(from: square))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(icns as CFData, nil))
        let sides = (0..<CGImageSourceGetCount(source)).compactMap { CGImageSourceCreateImageAtIndex(source, $0, nil)?.width }
        XCTAssertEqual(Set(sides), Set(ShortcutIconLimits.icnsSides))
    }

    func testIconUsesTheChosenCrop() async throws {
        let crop = CoverCrop(centerX: 0.5, centerY: 0.5, scale: 0.5)
        let image = try await store.iconImage(for: game(icon: .cover(crop)))
        XCTAssertEqual(image.width, 300)
    }

    func testIconUsesSteamsIconWhenChosen() async throws {
        artwork[iconURL] = TestImages.ico(sides: [32, 256])
        let image = try await store.iconImage(for: game(icon: .steamIcon, clientIconURL: iconURL))
        XCTAssertEqual(image.width, 256)
    }

    func testSmallSteamIconFallsBackToTheCover() async throws {
        artwork[iconURL] = TestImages.ico(sides: [32])
        let image = try await store.iconImage(for: game(icon: .steamIcon, clientIconURL: iconURL))
        XCTAssertEqual(image.width, 600)
    }

    func testMissingCoverIsAnError() async {
        artwork.removeAll()
        do {
            _ = try await store.iconImage(for: game())
            XCTFail("expected an error")
        } catch {}
    }

    // MARK: - The .app on disk

    func testCreatesAnAppThatOpensTheGame() async throws {
        let url = try await store.create(.application, for: game())
        XCTAssertEqual(url.lastPathComponent, "Kingdom Come - Deliverance.app")
        XCTAssertEqual(url.deletingLastPathComponent(), store.locations.applications)
        XCTAssertEqual(ShortcutAppBundle.appID(at: url), 42)

        let script = url.appendingPathComponent("Contents/MacOS/launch")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: script.path))
        XCTAssertTrue(try String(contentsOf: script, encoding: .utf8).contains("beer://game/42"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Resources/AppIcon.icns").path))
        XCTAssertEqual(store.records, [GameShortcutRecord(appID: 42, kind: .application, path: url.path)])
    }

    func testRecordsSurviveARestart() async throws {
        let url = try await store.create(.desktop, for: game())
        let reopened = GameShortcutStore(locations: store.locations)
        XCTAssertEqual(reopened.records, [GameShortcutRecord(appID: 42, kind: .desktop, path: url.path)])
    }

    func testMakingItAgainReplacesBEERsOwnShortcut() async throws {
        try await store.create(.desktop, for: game())
        try await store.create(.desktop, for: game())
        XCTAssertEqual(store.records.count, 1)
    }

    func testNeverOverwritesSomethingElseWithTheSameName() async throws {
        let theirs = store.locations.desktop.appendingPathComponent("Kingdom Come - Deliverance.app/keep.txt")
        try FileManager.default.createDirectory(at: theirs.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: theirs)

        do {
            try await store.create(.desktop, for: game())
            XCTFail("expected the name to be taken")
        } catch let error as GameShortcutError {
            XCTAssertEqual(error, .nameTaken("Kingdom Come - Deliverance.app"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: theirs.path))
        XCTAssertTrue(store.records.isEmpty)
    }

    func testFileNamesAreSafe() {
        XCTAssertEqual(ShortcutAppBundle.fileName(for: "AC/DC: Live"), "AC-DC - Live.app")
        XCTAssertEqual(ShortcutAppBundle.fileName(for: "  "), "Game.app")
    }

    // MARK: - Uninstall

    func testUninstallRemovesBothShortcuts() async throws {
        let desktop = try await store.create(.desktop, for: game())
        let app = try await store.create(.application, for: game())
        store.removeShortcuts(appID: 42)
        XCTAssertFalse(FileManager.default.fileExists(atPath: desktop.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.path))
        XCTAssertTrue(store.records.isEmpty)
    }

    func testUninstallLeavesAMovedShortcutAlone() async throws {
        let made = try await store.create(.desktop, for: game())
        let moved = root.appendingPathComponent("Elsewhere.app")
        try FileManager.default.moveItem(at: made, to: moved)
        store.removeShortcuts(appID: 42)
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
    }

    func testUninstallLeavesAnotherGamesShortcutAlone() async throws {
        let made = try await store.create(.desktop, for: game())
        // The player removed BEER's and made another game's under the same name.
        try FileManager.default.removeItem(at: made)
        try ShortcutAppBundle.write(at: made, gameName: "Other", appID: 7, icns: Data())
        store.removeShortcuts(appID: 42)
        XCTAssertEqual(ShortcutAppBundle.appID(at: made), 7)
    }

    func testNewIconReachesExistingShortcuts() async throws {
        let made = try await store.create(.application, for: game())
        let icon = made.appendingPathComponent("Contents/Resources/AppIcon.icns")
        let before = try Data(contentsOf: icon)
        artwork[iconURL] = TestImages.ico(sides: [256])
        try await store.updateIcons(for: game(icon: .steamIcon, clientIconURL: iconURL))
        XCTAssertNotEqual(try Data(contentsOf: icon), before)
    }

    // MARK: - Library

    func testLibraryRefreshKeepsShortcutChoices() {
        var existing = game(icon: .steamIcon, clientIconURL: iconURL)
        existing.installedBottleID = UUID()
        let fresh = SteamLibraryGame(appID: 42, name: "Kingdom Come: Deliverance")
        let merged = SteamLibraryStore.merge(existing: [existing], fetched: [fresh])
        XCTAssertEqual(merged.first?.shortcutIcon, .steamIcon)
        XCTAssertEqual(merged.first?.clientIconURL, iconURL.absoluteString)
    }

    func testOldLibraryFilesStillLoad() throws {
        let json = #"{"appID": 42, "name": "Old"}"#
        let decoded = try JSONDecoder().decode(SteamLibraryGame.self, from: Data(json.utf8))
        XCTAssertNil(decoded.shortcutIcon)
        XCTAssertNil(decoded.clientIconURL)
    }

    func testChoiceRoundTrips() throws {
        let choice = ShortcutIconChoice.cover(CoverCrop(centerX: 0.3, centerY: 0.6, scale: 0.8))
        let decoded = try JSONDecoder().decode(ShortcutIconChoice.self, from: JSONEncoder().encode(choice))
        XCTAssertEqual(decoded, choice)
    }

    func testInstallCheckboxesPickTheKinds() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "GameShortcutTests-\(UUID().uuidString)"))
        XCTAssertEqual(GameShortcutPreferences.kindsToCreateOnInstall(defaults), [])
        defaults.set(true, forKey: GameShortcutPreferences.applicationKey)
        XCTAssertEqual(GameShortcutPreferences.kindsToCreateOnInstall(defaults), [.application])
    }
}
