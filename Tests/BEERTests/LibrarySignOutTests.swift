import XCTest
@testable import BEER

/// Signing out and back in lost every installed game's link to its bottle, and
/// with it favorites, hidden and custom art: sign-out dropped the Steam games
/// and sign-in rebuilt them from Steam, which knows none of that.
@MainActor
final class LibrarySignOutTests: XCTestCase {
    private func bottle(appID: Int?, status: SteamGameInstallStatus? = .installed,
                        updated: Date = Date()) -> Bottle {
        var bottle = Bottle.make(
            name: "Game \(appID ?? 0)",
            runtime: RuntimeCandidate(kind: .gameNativeWine, executablePath: "/tmp/wine", displayName: "Test Wine"),
            graphicsBackend: .automatic
        )
        bottle.steamAppID = appID
        bottle.gameInstallStatus = status
        bottle.updatedAt = updated
        return bottle
    }

    func testSigningBackInKeepsInstallsAndFavorites() {
        let bottleID = UUID()
        var existing = SteamLibraryGame(appID: 1, name: "Installed", installedBottleID: bottleID)
        existing.isFavorite = true
        let merged = SteamLibraryStore.merge(existing: [existing], fetched: [SteamLibraryGame(appID: 1, name: "Installed")])
        XCTAssertEqual(merged.first?.installedBottleID, bottleID)
        XCTAssertEqual(merged.first?.isFavorite, true)
    }

    func testRelinksAGameToItsInstalledBottle() throws {
        let bottle = bottle(appID: 1)
        let relinked = try XCTUnwrap(SteamLibraryStore.relinking(
            [SteamLibraryGame(appID: 1, name: "Lost link"), SteamLibraryGame(appID: 2, name: "Never installed")],
            to: [bottle]))
        XCTAssertEqual(relinked.map(\.installedBottleID), [bottle.id, nil])
    }

    func testPicksTheLatestOfTwoBottles() throws {
        let older = bottle(appID: 1, updated: Date(timeIntervalSince1970: 1_000))
        let newer = bottle(appID: 1, updated: Date(timeIntervalSince1970: 2_000))
        let relinked = try XCTUnwrap(SteamLibraryStore.relinking(
            [SteamLibraryGame(appID: 1, name: "Two bottles")], to: [older, newer]))
        XCTAssertEqual(relinked.first?.installedBottleID, newer.id)
    }

    func testLeavesLinksAndUninstalledBottlesAlone() {
        let kept = UUID()
        XCTAssertNil(SteamLibraryStore.relinking(
            [SteamLibraryGame(appID: 1, name: "Linked", installedBottleID: kept),
             SteamLibraryGame(appID: 2, name: "Removed")],
            to: [bottle(appID: 1), bottle(appID: 2, status: .notInstalled)]))
    }
}
