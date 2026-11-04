import XCTest
@testable import BEER

@MainActor
final class LibraryAppearanceTests: XCTestCase {
    private let bottleID = UUID()

    private func game(_ appID: Int, _ name: String, installed: Bool = false,
                      minutes: Int? = nil, lastPlayed: Date? = nil) -> SteamLibraryGame {
        SteamLibraryGame(appID: appID, name: name, lastPlayed: lastPlayed, playtimeMinutes: minutes,
                         installedBottleID: installed ? bottleID : nil)
    }

    private func sorted(_ games: [SteamLibraryGame], by order: LibrarySortOrder) -> [String] {
        SteamLibraryGridViewModel()
            .filteredGames(from: games, installedBottleIDs: [bottleID], filter: .all, sortOrder: order)
            .map(\.name)
    }

    // MARK: - Sort order

    func testInstalledFirstPutsInstalledGamesAheadOfTheAlphabet() {
        let games = [game(1, "Alpha"), game(2, "Zulu", installed: true), game(3, "Bravo")]
        XCTAssertEqual(sorted(games, by: .installedFirst), ["Zulu", "Alpha", "Bravo"])
    }

    func testNameIgnoresInstalledAndCase() {
        let games = [game(1, "bravo"), game(2, "Zulu", installed: true), game(3, "Alpha")]
        XCTAssertEqual(sorted(games, by: .name), ["Alpha", "bravo", "Zulu"])
    }

    func testRecentlyPlayedPutsNeverPlayedLastByName() {
        let games = [
            game(1, "Never B"), game(2, "Old", lastPlayed: Date(timeIntervalSince1970: 1_000)),
            game(3, "Never A"), game(4, "New", lastPlayed: Date(timeIntervalSince1970: 2_000))
        ]
        XCTAssertEqual(sorted(games, by: .recentlyPlayed), ["New", "Old", "Never A", "Never B"])
    }

    func testMostPlayedTiesFallBackToName() {
        let games = [game(1, "Some", minutes: 30), game(2, "Lots", minutes: 900),
                     game(3, "Also", minutes: 30), game(4, "None")]
        XCTAssertEqual(sorted(games, by: .mostPlayed), ["Lots", "Also", "Some", "None"])
    }

    func testSearchStillFiltersWhateverTheOrder() {
        let model = SteamLibraryGridViewModel()
        model.searchText = "al"
        let names = model.filteredGames(from: [game(1, "Alpha"), game(2, "Bravo")],
                                        installedBottleIDs: [], filter: .all, sortOrder: .mostPlayed)
            .map(\.name)
        XCTAssertEqual(names, ["Alpha"])
    }

    // MARK: - Caption

    func testCaptions() {
        let played = game(10, "Played", minutes: 90, lastPlayed: Date(timeIntervalSince1970: 0))
        let unplayed = game(20, "Unplayed")
        let nonSteam = SteamLibraryGame(appID: -1, name: "Mine", isNonSteam: true)

        XCTAssertEqual(LibraryCardLabel.appID.text(for: played), "appID 10")
        XCTAssertEqual(LibraryCardLabel.appID.text(for: nonSteam), "Non-Steam")
        XCTAssertEqual(LibraryCardLabel.playtime.text(for: played), "1.5 hours")
        XCTAssertEqual(LibraryCardLabel.playtime.text(for: unplayed), "Never played")
        XCTAssertEqual(LibraryCardLabel.playtime.text(for: nonSteam), "Non-Steam")
        XCTAssertTrue(LibraryCardLabel.lastPlayed.text(for: played)?.hasPrefix("Last played: ") ?? false)
        XCTAssertEqual(LibraryCardLabel.playtime.text(for: played, playtime: .hoursAndMinutes), "1h 30m")
        XCTAssertEqual(LibraryCardLabel.lastPlayed.text(for: unplayed), "Never played")
        XCTAssertNil(LibraryCardLabel.nameOnly.text(for: played))
        XCTAssertNil(LibraryCardLabel.artOnly.text(for: played))
        XCTAssertTrue(LibraryCardLabel.nameOnly.showsName)
        XCTAssertFalse(LibraryCardLabel.artOnly.showsName)
    }

    // MARK: - Card art

    func testSteamGameCoverIsThePortraitCapsule() {
        let steam = game(220, "Half-Life 2")
        XCTAssertEqual(steam.portraitCover, steam.libraryCapsuleImage)
        XCTAssertNil(steam.listIcon, "no community icon known yet")

        var withIcon = steam
        withIcon.iconURL = "https://example.invalid/icon.jpg"
        XCTAssertEqual(withIcon.listIcon?.absoluteString, "https://example.invalid/icon.jpg")
    }

    func testNonSteamGameShowsItsPickedImageWholeNotCropped() {
        let nonSteam = SteamLibraryGame(appID: -1, name: "Mine", isNonSteam: true,
                                        customImagePath: "/tmp/art.png")
        XCTAssertNil(nonSteam.portraitCover)
        XCTAssertEqual(nonSteam.listIcon, nonSteam.headerImage)
    }

    // MARK: - Stored settings

    func testUnknownStoredValuesAreRejectedSoTheDefaultApplies() {
        XCTAssertNil(LibraryCardStyle(rawValue: "carousel"))
        XCTAssertNil(LibrarySortOrder(rawValue: "random"))
        XCTAssertNil(GamePageLayout(rawValue: "huge"))
    }

    func testDefaultWidthKeepsTheOriginalCard() {
        XCTAssertEqual(LibraryGridLayout.cardWidth(style: .wide, chosen: LibraryGridLayout.defaultCardWidth, available: 1200),
                       220...(220 * CGFloat(LibraryGridLayout.rowStretch)))
    }

    func testBiggestCardNeverGoesOffScreen() {
        let biggest = LibraryGridLayout.cardWidthRange.upperBound
        for style in LibraryCardStyle.allCases {
            let width = LibraryGridLayout.cardWidth(style: style, chosen: biggest, available: 900)
            XCTAssertEqual(width, 900...900, "\(style) should fill the row, no wider")
        }
    }

    func testCardsGrowAlongTheSlider() {
        let small = LibraryGridLayout.cardWidth(style: .wide, chosen: 200, available: 3000)
        let large = LibraryGridLayout.cardWidth(style: .wide, chosen: 800, available: 3000)
        XCTAssertLessThan(small.lowerBound, large.lowerBound)
    }

    func testUnmeasuredWidthUsesTheChosenWidth() {
        XCTAssertEqual(LibraryGridLayout.cardWidth(style: .wide, chosen: 400, available: 0).lowerBound, 400)
    }
}
