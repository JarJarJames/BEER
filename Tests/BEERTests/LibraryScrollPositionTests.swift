import XCTest
@testable import BEER

/// Going back from a game page scrolls the library to the game that was
/// opened, unless the list it was opened from has changed.
@MainActor
final class LibraryScrollPositionTests: XCTestCase {
    private let games = [
        SteamLibraryGame(appID: 10, name: "Alpha"),
        SteamLibraryGame(appID: 20, name: "Beta"),
        SteamLibraryGame(appID: 30, name: "Gamma"),
    ]

    func testReturnsToTheOpenedGame() {
        let model = SteamLibraryGridViewModel()
        model.gameOpened(20, filter: .all, cardStyle: .wide)
        XCTAssertEqual(model.takeReturnScrollTarget(in: games, filter: .all, cardStyle: .wide), 20)
    }

    func testKeepsItWithTheSameSearch() {
        let model = SteamLibraryGridViewModel()
        model.searchText = "ga"
        model.gameOpened(30, filter: .all, cardStyle: .wide)
        XCTAssertEqual(model.takeReturnScrollTarget(in: games, filter: .all, cardStyle: .wide), 30)
    }

    func testAnswersOncePerReturn() {
        let model = SteamLibraryGridViewModel()
        model.gameOpened(20, filter: .all, cardStyle: .wide)
        _ = model.takeReturnScrollTarget(in: games, filter: .all, cardStyle: .wide)
        XCTAssertNil(model.takeReturnScrollTarget(in: games, filter: .all, cardStyle: .wide))
    }

    func testNothingOpenedStartsAtTheTop() {
        XCTAssertNil(SteamLibraryGridViewModel().takeReturnScrollTarget(in: games, filter: .all, cardStyle: .wide))
    }

    func testFilterChangeStartsAtTheTop() {
        let model = SteamLibraryGridViewModel()
        model.gameOpened(20, filter: .all, cardStyle: .wide)
        XCTAssertNil(model.takeReturnScrollTarget(in: games, filter: .installed, cardStyle: .wide))
    }

    func testSearchChangeStartsAtTheTop() {
        let model = SteamLibraryGridViewModel()
        model.gameOpened(20, filter: .all, cardStyle: .wide)
        model.searchText = "be"
        XCTAssertNil(model.takeReturnScrollTarget(in: games, filter: .all, cardStyle: .wide))
    }

    func testCardStyleChangeStartsAtTheTop() {
        let model = SteamLibraryGridViewModel()
        model.gameOpened(20, filter: .all, cardStyle: .wide)
        XCTAssertNil(model.takeReturnScrollTarget(in: games, filter: .all, cardStyle: .list))
    }

    /// Hidden or uninstalled while its page was open.
    func testGameNoLongerInTheListStartsAtTheTop() {
        let model = SteamLibraryGridViewModel()
        model.gameOpened(20, filter: .all, cardStyle: .wide)
        XCTAssertNil(model.takeReturnScrollTarget(in: games.filter { $0.appID != 20 }, filter: .all, cardStyle: .wide))
    }
}
