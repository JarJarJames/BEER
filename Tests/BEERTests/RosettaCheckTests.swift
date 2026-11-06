import XCTest
@testable import BEER

/// GPTK's Wine is Intel-only. On a Mac without Rosetta it fails with "Bad CPU
/// type in executable", so BEER asks to install Rosetta instead of running it.
@MainActor
final class RosettaCheckTests: XCTestCase {
    private func bottle() -> Bottle {
        let wine = "/nonexistent/runtime/bin/wine64"
        return Bottle.make(
            name: "Fallout 4",
            runtime: RuntimeCandidate(kind: .systemWine, executablePath: wine, displayName: "Managed GPTK",
                                      entrypoints: RuntimeEntrypoints(wine: wine, wineboot: nil, wineserver: nil)),
            graphicsBackend: .automatic
        )
    }

    private func store(rosetta: Bool) -> BottleStore {
        let store = BottleStore()
        store.rosettaInstalled = { rosetta }
        return store
    }

    func testWineCommandWithoutRosettaAsksForItAndRunsNothing() async {
        let store = store(rosetta: false)
        let bottle = bottle()

        let exit = await store.runBottleCommand(bottle, operation: "Initializing bottle", mode: .wineboot)

        XCTAssertNil(exit)
        XCTAssertTrue(store.isShowingRosettaPrompt)
        XCTAssertNil(store.lastError, "The raw 'Bad CPU type' error must not reach the user")
        XCTAssertTrue(store.logs[bottle.id]?.isEmpty ?? true, "Nothing was started, so nothing is logged")
        XCTAssertFalse(store.activeBottleIDs.contains(bottle.id))
    }

    func testStoppingWithoutRosettaDoesNotAsk() async {
        let store = store(rosetta: false)

        let exit = await store.runBottleCommand(bottle(), operation: "Stopping bottle processes", mode: .winebootKill)

        XCTAssertNil(exit)
        XCTAssertFalse(store.isShowingRosettaPrompt)
    }

    func testRequireRosettaPassesWhenInstalled() {
        let store = store(rosetta: true)

        XCTAssertTrue(store.requireRosetta())
        XCTAssertFalse(store.isShowingRosettaPrompt)
    }

    func testRequireRosettaAsksWhenMissing() {
        let store = store(rosetta: false)

        XCTAssertFalse(store.requireRosetta())
        XCTAssertTrue(store.isShowingRosettaPrompt)
    }
}
