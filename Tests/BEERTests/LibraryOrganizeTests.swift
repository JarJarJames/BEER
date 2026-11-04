import XCTest
@testable import BEER

@MainActor
final class LibraryOrganizeTests: XCTestCase {
    private let bottleID = UUID()
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("LibraryOrganizeTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func game(_ appID: Int, _ name: String, installed: Bool = false, favorite: Bool = false,
                      hidden: Bool = false, minutes: Int? = nil) -> SteamLibraryGame {
        var game = SteamLibraryGame(appID: appID, name: name, playtimeMinutes: minutes,
                                    installedBottleID: installed ? bottleID : nil)
        game.isFavorite = favorite ? true : nil
        game.isHidden = hidden ? true : nil
        return game
    }

    private func names(_ games: [SteamLibraryGame], _ filter: LibraryFilter,
                       _ order: LibrarySortOrder = .name) -> [String] {
        SteamLibraryGridViewModel()
            .filteredGames(from: games, installedBottleIDs: [bottleID], filter: filter, sortOrder: order)
            .map(\.name)
    }

    // MARK: - Hidden

    func testHiddenGamesOnlyShowUnderHidden() {
        let games = [game(1, "Shown"), game(2, "Gone", hidden: true),
                     game(3, "Installed"  , installed: true), game(4, "Installed but hidden", installed: true, hidden: true)]
        XCTAssertEqual(names(games, .all), ["Installed", "Shown"])
        XCTAssertEqual(names(games, .installed), ["Installed"])
        XCTAssertEqual(names(games, .hidden), ["Gone", "Installed but hidden"])
    }

    // MARK: - Favorites

    func testFavoritesStayOnTopWhateverTheSort() {
        let games = [game(1, "Alpha", installed: true, minutes: 900), game(2, "Zulu", favorite: true),
                     game(3, "Mike", favorite: true, minutes: 5)]
        XCTAssertEqual(names(games, .all, .name), ["Mike", "Zulu", "Alpha"])
        XCTAssertEqual(names(games, .all, .installedFirst), ["Mike", "Zulu", "Alpha"])
        XCTAssertEqual(names(games, .all, .mostPlayed), ["Mike", "Zulu", "Alpha"],
                       "favorites first, then the order among them")
    }

    // MARK: - Library refresh

    func testRefreshKeepsFavoriteHiddenAndArtwork() {
        var mine = game(10, "Old name", favorite: true, hidden: true)
        mine.customArt = CustomGameArt(coverPath: "/art/cover.png", bannerPath: nil, logoPath: "/art/logo.png")
        let fresh = SteamLibraryGame(appID: 10, name: "New name")

        let merged = SteamLibraryStore.merge(existing: [mine], fetched: [fresh])

        XCTAssertEqual(merged.first?.name, "New name")
        XCTAssertEqual(merged.first?.isFavorite, true)
        XCTAssertEqual(merged.first?.isHidden, true)
        XCTAssertEqual(merged.first?.customArt, mine.customArt)
    }

    func testOldSavedGamesDecodeWithoutTheNewFields() throws {
        let json = #"{"appID": 5, "name": "Old"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(SteamLibraryGame.self, from: json)
        XCTAssertFalse(decoded.effectiveIsFavorite)
        XCTAssertFalse(decoded.effectiveIsHidden)
        XCTAssertNil(decoded.customArt)
    }

    // MARK: - Custom artwork

    func testPickedArtReplacesSteamsAndFallsBack() {
        var steam = game(220, "Half-Life 2")
        let steamCover = steam.portraitCover, steamHero = steam.libraryHeroImage, steamLogo = steam.libraryLogoImage
        steam.customArt = CustomGameArt(coverPath: "/art/c.png", bannerPath: "/art/b.png", logoPath: "/art/l.png")

        XCTAssertEqual(steam.portraitCover?.path, "/art/c.png")
        XCTAssertEqual(steam.libraryHeroImage?.path, "/art/b.png")
        XCTAssertEqual(steam.libraryLogoImage?.path, "/art/l.png")

        steam.customArt = CustomGameArt(coverPath: nil, bannerPath: "/art/b.png", logoPath: nil)
        XCTAssertEqual(steam.portraitCover, steamCover)
        XCTAssertNotEqual(steam.libraryHeroImage, steamHero)
        XCTAssertEqual(steam.libraryLogoImage, steamLogo)
    }

    func testNonSteamGameCanGetALogoAndCover() {
        var mine = SteamLibraryGame(appID: -1, name: "Mine", isNonSteam: true, customImagePath: "/art/picked.png")
        XCTAssertNil(mine.libraryLogoImage)
        mine.customArt = CustomGameArt(coverPath: "/art/c.png", bannerPath: nil, logoPath: "/art/l.png")
        XCTAssertEqual(mine.libraryLogoImage?.path, "/art/l.png")
        XCTAssertEqual(mine.portraitCover?.path, "/art/c.png")
        XCTAssertEqual(mine.libraryHeroImage?.path, "/art/picked.png", "no banner picked: its one image")
    }

    func testCopyKeepsTheImageAndNamesItForTheGame() throws {
        let source = root.appendingPathComponent("My Cover.PNG")
        try Data("png".utf8).write(to: source)
        let art = root.appendingPathComponent("CustomArt", isDirectory: true)

        let copy = try CustomArtFiles.copy(source, appID: 220, slot: .cover, into: art,
                                           now: Date(timeIntervalSince1970: 1_000))

        XCTAssertEqual(copy.lastPathComponent, "app220-cover-1000.png")
        XCTAssertEqual(try Data(contentsOf: copy), Data("png".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path), "the original is left alone")
    }

    func testRemoveOnlyDeletesBEERsOwnCopies() throws {
        let art = root.appendingPathComponent("CustomArt", isDirectory: true)
        try FileManager.default.createDirectory(at: art, withIntermediateDirectories: true)
        let inside = art.appendingPathComponent("app1-logo-1.png")
        let outside = root.appendingPathComponent("someone-elses.png")
        try Data().write(to: inside)
        try Data().write(to: outside)

        CustomArtFiles.remove(path: outside.path, in: art)
        CustomArtFiles.remove(path: inside.path, in: art)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: inside.path))
    }

    func testSettingAndClearingArtTracksEachPiece() {
        var art = CustomGameArt()
        XCTAssertTrue(art.isEmpty)
        art.setPath("/a.png", for: .logo)
        XCTAssertEqual(art.paths, ["/a.png"])
        art.setPath(nil, for: .logo)
        XCTAssertTrue(art.isEmpty)
    }
}
