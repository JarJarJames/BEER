import XCTest
@testable import BEER

/// The status that replaces Play while a game starts: it follows the launch
/// steps in order, ends on the error of a step that fails, and only says
/// "Playing" once the bottle has a window. Every step and the window check
/// are faked; nothing runs Wine.
@MainActor
final class LaunchStatusTests: XCTestCase {
    /// Stands in for the bottle's window appearing on screen.
    private final class FakeWindow {
        var isUp = false
    }

    private let window = FakeWindow()
    private var recorded: [LaunchPhase?] = []
    /// The steps that ran, in order.
    private var ran: [String] = []

    private func bottle() -> Bottle {
        let wine = "/nonexistent/runtime/bin/wine64"
        return Bottle.make(
            name: "Hades",
            runtime: RuntimeCandidate(kind: .systemWine, executablePath: wine, displayName: "Managed GPTK",
                                      entrypoints: RuntimeEntrypoints(wine: wine, wineboot: nil, wineserver: nil)),
            graphicsBackend: .automatic
        )
    }

    /// A store whose window check reads `window`, recording every phase the
    /// bottle goes through.
    private func store(for bottle: Bottle, slowAfter: Duration = .seconds(60)) -> BottleStore {
        let store = BottleStore()
        store.gameWindowWatch = GameWindowWatch(
            isShown: { [window] _ in window.isUp },
            pollInterval: .milliseconds(2),
            slowAfter: slowAfter
        )
        recorded = [store.launchPhase(for: bottle.id)]
        store.launchPhasesChanged = { [weak self] phases in
            guard let self, self.recorded.last != phases[bottle.id] else { return }
            self.recorded.append(phases[bottle.id])
        }
        return store
    }

    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<2000 where !condition() {
            try? await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition(), "Timed out", file: file, line: line)
    }

    /// Steps that all succeed. `runGame` shows a window, waits for the status
    /// to notice, then exits with `exitCode`.
    private func steps(
        store: BottleStore, bottle: Bottle, syncs: Bool = true, showsWindow: Bool = true, exitCode: Int32? = 0
    ) -> BottleStore.LaunchSteps {
        var syncSaves: (@MainActor () async -> Bool)?
        if syncs {
            syncSaves = { self.ran.append("syncSaves"); return true }
        }
        return BottleStore.LaunchSteps(
            setUpWine: { self.ran.append("setUpWine") },
            syncSaves: syncSaves,
            prepareGame: { self.ran.append("prepareGame") },
            runGame: { [window] in
                self.ran.append("runGame")
                guard exitCode != nil else { return nil }
                if showsWindow {
                    window.isUp = true
                    await self.waitUntil { store.launchPhase(for: bottle.id) == .playing }
                    window.isUp = false
                }
                return exitCode
            },
            afterPlay: { self.ran.append("afterPlay") }
        )
    }

    func testPhasesComeOutInOrder() async {
        let bottle = bottle()
        let store = store(for: bottle)

        await store.runLaunch(bottle, steps: steps(store: store, bottle: bottle))

        XCTAssertEqual(recorded, [nil, .settingUpWine, .syncingSaves, .startingGame(isSlow: false), .playing, nil])
        XCTAssertEqual(ran, ["setUpWine", "syncSaves", "prepareGame", "runGame", "afterPlay"])
    }

    func testNonSteamGameSkipsSyncingSaves() async {
        let bottle = bottle()
        let store = store(for: bottle)

        await store.runLaunch(bottle, steps: steps(store: store, bottle: bottle, syncs: false))

        XCTAssertEqual(recorded, [nil, .settingUpWine, .startingGame(isSlow: false), .playing, nil])
    }

    func testOnlyConnectedSteamGamesPullSavesBeforePlay() {
        XCTAssertTrue(GameDetailViewModel.pullsSavesBeforePlay(isNonSteam: false, isSteamConnected: true))
        XCTAssertFalse(GameDetailViewModel.pullsSavesBeforePlay(isNonSteam: true, isSteamConnected: true))
        XCTAssertFalse(GameDetailViewModel.pullsSavesBeforePlay(isNonSteam: true, isSteamConnected: false))
        XCTAssertFalse(GameDetailViewModel.pullsSavesBeforePlay(isNonSteam: false, isSteamConnected: false))
    }

    func testFailingSetupEndsOnItsErrorAndRunsNothingElse() async {
        let bottle = bottle()
        let store = store(for: bottle)
        var steps = steps(store: store, bottle: bottle)
        steps.setUpWine = { throw LaunchError.clientLoader("the loader is missing") }

        await store.runLaunch(bottle, steps: steps)

        let message = LaunchStatusStrings.clientLoaderFailed("the loader is missing")
        XCTAssertEqual(recorded, [nil, .settingUpWine, .failed(message)])
        XCTAssertEqual(store.launchPhase(for: bottle.id), .failed(message), "The error stays until Play is clicked again")
        XCTAssertEqual(ran, [], "Nothing after the failed step runs, and there's no play to wrap up")
    }

    func testFailingPrepareEndsOnItsError() async {
        let bottle = bottle()
        let store = store(for: bottle)
        var steps = steps(store: store, bottle: bottle)
        steps.prepareGame = { throw LaunchError.runtimeMissing("Hades's runtime is gone.") }

        await store.runLaunch(bottle, steps: steps)

        XCTAssertEqual(recorded, [nil, .settingUpWine, .syncingSaves, .startingGame(isSlow: false),
                                  .failed("Hades's runtime is gone.")])
    }

    func testGameThatNeverRanEndsOnError() async {
        let bottle = bottle()
        let store = store(for: bottle)

        await store.runLaunch(bottle, steps: steps(store: store, bottle: bottle, exitCode: nil))

        XCTAssertEqual(store.launchPhase(for: bottle.id), .failed(LaunchStatusStrings.gameDidNotStart))
    }

    func testCrashBeforeAnyWindowEndsOnError() async {
        let bottle = bottle()
        let store = store(for: bottle)

        await store.runLaunch(bottle, steps: steps(store: store, bottle: bottle, showsWindow: false, exitCode: 3))

        XCTAssertEqual(recorded.last, .failed(LaunchStatusStrings.closedBeforeWindow(exitCode: 3)))
        XCTAssertFalse(recorded.contains(.playing))
        XCTAssertEqual(ran.last, "afterPlay", "The game ran, so play is still wrapped up (presence, saves)")
    }

    func testCleanExitWithoutWindowEndsQuietly() async {
        let bottle = bottle()
        let store = store(for: bottle)

        await store.runLaunch(bottle, steps: steps(store: store, bottle: bottle, showsWindow: false, exitCode: 0))

        XCTAssertEqual(recorded, [nil, .settingUpWine, .syncingSaves, .startingGame(isSlow: false), nil],
                       "Stays on Starting game until the session ends, never guessing Playing")
    }

    func testErrorExitAfterPlayingIsNotALaunchFailure() async {
        let bottle = bottle()
        let store = store(for: bottle)

        await store.runLaunch(bottle, steps: steps(store: store, bottle: bottle, exitCode: 1))

        XCTAssertNil(store.launchPhase(for: bottle.id))
    }

    func testSaveConflictStopsWithoutAnError() async {
        let bottle = bottle()
        let store = store(for: bottle)
        var steps = steps(store: store, bottle: bottle)
        steps.syncSaves = { false }

        await store.runLaunch(bottle, steps: steps)

        XCTAssertEqual(recorded, [nil, .settingUpWine, .syncingSaves, nil])
        XCTAssertEqual(ran, ["setUpWine"])
    }

    func testWindowDuringPrepareIsNotTheGame() async {
        let bottle = bottle()
        let store = store(for: bottle)
        var steps = steps(store: store, bottle: bottle, showsWindow: false)
        // A redistributable's installer showing a window.
        steps.prepareGame = { [window] in
            window.isUp = true
            try? await Task.sleep(for: .milliseconds(20))
            window.isUp = false
        }

        await store.runLaunch(bottle, steps: steps)

        XCTAssertFalse(recorded.contains(.playing))
    }

    func testSlowStartAddsTheHint() async {
        let bottle = bottle()
        let store = store(for: bottle, slowAfter: .milliseconds(10))
        var steps = steps(store: store, bottle: bottle)
        steps.runGame = { [window] in
            await self.waitUntil { store.launchPhase(for: bottle.id) == .startingGame(isSlow: true) }
            window.isUp = true
            await self.waitUntil { store.launchPhase(for: bottle.id) == .playing }
            return 0
        }

        await store.runLaunch(bottle, steps: steps)

        XCTAssertEqual(recorded, [nil, .settingUpWine, .syncingSaves, .startingGame(isSlow: false),
                                  .startingGame(isSlow: true), .playing, nil])
    }

    // MARK: - Finding the bottle's window

    func testReadsTheEnvironmentPastArgumentsIncludingEmptyOnes() {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: Int32(3)) { bytes += $0 }
        for part in ["/runtime/bin/wine-preloader", "", "", "wine", "", "C:\\Game.exe"] {
            bytes += Array(part.utf8) + [0]
        }
        for part in ["WINEPREFIX=/Bottles/Hades", "USER=crossover", "ptr_munge=0x1"] {
            bytes += Array(part.utf8) + [0]
        }

        let environment = WineWindowProbe.environment(fromProcArgs: bytes)

        XCTAssertEqual(environment, ["WINEPREFIX=/Bottles/Hades", "USER=crossover", "ptr_munge=0x1"])
        XCTAssertEqual(environment.flatMap { WineWindowProbe.value(of: "WINEPREFIX", in: $0) }, "/Bottles/Hades")
    }

    func testTruncatedProcArgsReadAsNothing() {
        var bytes: [UInt8] = []
        withUnsafeBytes(of: Int32(4)) { bytes += $0 }
        bytes += Array("/runtime/bin/wine".utf8) + [0, 0] + Array("wine".utf8) + [0]

        XCTAssertNil(WineWindowProbe.environment(fromProcArgs: bytes))
    }

    func testReadsARealProcessEnvironment() {
        // The test runner itself: same user, not one of the system's binaries.
        let environment = WineWindowProbe.environment(of: ProcessInfo.processInfo.processIdentifier)

        XCTAssertEqual(environment.flatMap { WineWindowProbe.value(of: "HOME", in: $0) },
                       ProcessInfo.processInfo.environment["HOME"])
    }

    func testOnlyAProcessInThisBottleCounts() {
        let prefix = URL(fileURLWithPath: "/Bottles/Hades")
        let environments: [pid_t: [String]] = [
            10: ["WINEPREFIX=/Bottles/Celeste"],
            11: ["HOME=/var/empty"],
            12: ["WINEPREFIX=/Bottles/Hades/"],
        ]

        XCTAssertTrue(WineWindowProbe.containsProcess(in: prefix, among: [10, 11, 12], environment: { environments[$0] }))
        XCTAssertFalse(WineWindowProbe.containsProcess(in: prefix, among: [10, 11, 99], environment: { environments[$0] }))
    }
}
