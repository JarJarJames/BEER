import XCTest
@testable import BEER

final class BottleMigrationTests: XCTestCase {
    func testMigratesCustomLibraryArguments() {
        var bottle = makeBottle()
        bottle.steamAppID = 794260
        bottle.launchArguments = "-screen-width 3024 -screen-height 1964"

        XCTAssertTrue(bottle.migrateLegacyLibraryLaunchArguments())
        XCTAssertEqual(bottle.gameLaunchArguments, "-screen-width 3024 -screen-height 1964")
        XCTAssertEqual(bottle.launchArguments, "")
    }

    func testDropsSteamDefaultForLibraryGame() {
        var bottle = makeBottle()
        bottle.steamAppID = 794260

        XCTAssertTrue(bottle.migrateLegacyLibraryLaunchArguments())
        XCTAssertNil(bottle.gameLaunchArguments)
        XCTAssertEqual(bottle.launchArguments, "")
    }

    func testDoesNotChangeManualBottle() {
        var bottle = makeBottle()

        XCTAssertFalse(bottle.migrateLegacyLibraryLaunchArguments())
        XCTAssertEqual(bottle.launchArguments, SteamLaunchDefaults.basicArguments)
    }

    private func makeBottle() -> Bottle {
        Bottle.make(
            name: "Test",
            runtime: RuntimeCandidate(
                kind: .gameNativeWine,
                executablePath: "/tmp/wine",
                displayName: "Test Wine"
            ),
            graphicsBackend: .automatic
        )
    }
}
