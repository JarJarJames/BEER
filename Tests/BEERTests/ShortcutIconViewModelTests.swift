import XCTest
@testable import BEER

/// The icon sheet's choices, against `FakeSteam` for Steam's icon and
/// in-memory artwork for the downloads.
@MainActor
final class ShortcutIconViewModelTests: XCTestCase {
    private let account = SteamCloudAccount(accountName: "fake-steam", steamID64: "76561197960287930",
                                            refreshToken: "not-a-real-token", connectedAt: Date())
    private var root: URL!
    private var fakeSteam: FakeSteam!
    private var remembered: [URL] = []

    private let iconHash = "295fac0ec6dbaf1f7f7cdf0c7bf359ab84ccc7cf"
    private var iconURL: URL {
        URL(string: "https://cdn.cloudflare.steamstatic.com/steamcommunity/public/images/apps/42/\(iconHash).ico")!
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ShortcutIconViewModelTests-\(UUID().uuidString)", isDirectory: true)
        fakeSteam = try FakeSteam(in: root.appendingPathComponent("FakeSteam", isDirectory: true))
        remembered = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func model(game: SteamLibraryGame = SteamLibraryGame(appID: 42, name: "Game"),
                       icoSides: [Int]) -> ShortcutIconViewModel {
        let cover = TestImages.png(width: 600, height: 900)
        let ico = TestImages.ico(sides: icoSides)
        return ShortcutIconViewModel(
            game: game, account: account, client: fakeSteam.client,
            fetch: { url in url.pathExtension == "ico" ? ico : cover },
            rememberClientIcon: { [unowned self] in remembered.append($0) }
        )
    }

    func testOffersSteamsIconWhenItHasA256Image() async {
        fakeSteam.clientIcons = [42: iconHash]
        let model = model(icoSides: [32, 256])
        await model.load()
        guard case .available(let image) = model.steamIcon else { return XCTFail("\(model.steamIcon)") }
        XCTAssertEqual(image.width, 256)
        XCTAssertEqual(remembered, [iconURL])
        XCTAssertEqual(fakeSteam.calls().map(\.command), ["clienticon"])
        XCTAssertEqual(fakeSteam.calls().map(\.appIDs), [[42]])
    }

    func testHidesASmallSteamIcon() async {
        fakeSteam.clientIcons = [42: iconHash]
        let model = model(icoSides: [32])
        await model.load()
        XCTAssertEqual(model.steamIcon, .unavailable)
    }

    func testNoIconListedBySteam() async {
        let model = model(icoSides: [256])
        await model.load()
        XCTAssertEqual(model.steamIcon, .unavailable)
        XCTAssertTrue(remembered.isEmpty)
    }

    func testDoesntAskSteamAgainOnceKnown() async {
        let game = SteamLibraryGame(appID: 42, name: "Game", clientIconURL: iconURL.absoluteString)
        let model = model(game: game, icoSides: [256])
        await model.load()
        XCTAssertTrue(fakeSteam.calls().isEmpty)
        guard case .available = model.steamIcon else { return XCTFail("\(model.steamIcon)") }
    }

    func testNonSteamGamesNeverAskSteam() async {
        let game = SteamLibraryGame(appID: -5, name: "Celeste64", isNonSteam: true, customImagePath: "/tmp/cover.png")
        let model = model(game: game, icoSides: [256])
        await model.load()
        XCTAssertTrue(fakeSteam.calls().isEmpty)
        XCTAssertEqual(model.steamIcon, .unavailable)
        XCTAssertNotNil(model.cover)
    }

    func testAPickedSteamIconThatsGoneFallsBackToTheCover() async {
        let game = SteamLibraryGame(appID: 42, name: "Game", shortcutIcon: .steamIcon)
        let model = model(game: game, icoSides: [256])
        await model.load()
        XCTAssertEqual(model.choice, .default)
    }

    func testPreviewFollowsTheCrop() async {
        let model = model(icoSides: [])
        await model.load()
        model.crop = CoverCrop(centerX: 0.5, centerY: 0.5, scale: 0.5)
        XCTAssertEqual(model.previewImage?.width, 300)
    }
}
