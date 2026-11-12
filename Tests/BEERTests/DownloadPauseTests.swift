import XCTest
@testable import BEER

/// Pause and Resume: the Downloads entry moving between downloading, pausing
/// and paused, a paused download surviving a relaunch through its bottle, and
/// Pause actually stopping the process.
@MainActor
final class DownloadPauseTests: XCTestCase {
    // MARK: - Entry states

    func testPauseMovesThroughPausingToPaused() {
        let store = DownloadsStore()
        store.start(appID: 1, name: "One", bottleID: UUID())
        store.setProgress(appID: 1, fraction: 0.4, downloaded: nil, total: nil)

        store.markPausing(appID: 1)
        XCTAssertEqual(store.entry(for: 1)?.status, .pausing)
        XCTAssertEqual(store.entry(for: 1)?.isActive, true, "DepotDownloader is still running")

        store.pause(appID: 1)
        let entry = store.entry(for: 1)
        XCTAssertEqual(entry?.status, .paused)
        XCTAssertEqual(entry?.isActive, false)
        XCTAssertEqual(entry?.isInProgress, true)
        XCTAssertEqual(entry?.fraction ?? -1, 0.4, accuracy: 0.0001, "the bar stays where it stopped")
    }

    /// A resumed download checks the files on disk first and its progress
    /// climbs back from 0; the bar stays where it was paused until it passes.
    func testResumeKeepsThePausedProgress() {
        let store = DownloadsStore()
        store.start(appID: 1, name: "One", bottleID: UUID())
        store.setProgress(appID: 1, fraction: 0.4, downloaded: nil, total: nil)
        store.pause(appID: 1)

        store.start(appID: 1, name: "One", bottleID: UUID())
        XCTAssertEqual(store.entry(for: 1)?.fraction ?? -1, 0.4, accuracy: 0.0001)
        store.setProgress(appID: 1, fraction: 0.1, downloaded: nil, total: nil)
        XCTAssertEqual(store.entry(for: 1)?.fraction ?? -1, 0.4, accuracy: 0.0001)
        store.setProgress(appID: 1, fraction: 0.5, downloaded: nil, total: nil)
        XCTAssertEqual(store.entry(for: 1)?.fraction ?? -1, 0.5, accuracy: 0.0001)
    }

    func testRetryAfterAFailureStartsFromZero() {
        let store = DownloadsStore()
        store.start(appID: 1, name: "One", bottleID: UUID())
        store.setProgress(appID: 1, fraction: 0.4, downloaded: nil, total: nil)
        store.fail(appID: 1, reason: "Disk full")

        store.start(appID: 1, name: "One", bottleID: UUID())
        XCTAssertEqual(store.entry(for: 1)?.fraction, 0)
    }

    func testPausedDownloadIsListedAsInProgressNotRecent() {
        let store = DownloadsStore()
        store.start(appID: 1, name: "One", bottleID: UUID())
        store.pause(appID: 1)

        XCTAssertEqual(store.inProgress.map(\.id), [1])
        XCTAssertTrue(store.recent.isEmpty)
        XCTAssertTrue(store.active.isEmpty)
    }

    func testPausedDownloadDropsOutOfOverallProgress() {
        let store = DownloadsStore()
        store.start(appID: 1, name: "One", bottleID: UUID())
        store.start(appID: 2, name: "Two", bottleID: UUID())
        store.setProgress(appID: 1, fraction: 0.2, downloaded: nil, total: nil)
        store.setProgress(appID: 2, fraction: 0.6, downloaded: nil, total: nil)

        store.pause(appID: 1)
        XCTAssertEqual(store.overallFraction ?? -1, 0.6, accuracy: 0.0001)

        store.pause(appID: 2)
        XCTAssertNil(store.overallFraction)
    }

    func testLateOutputDoesNotUndoPause() {
        let store = DownloadsStore()
        store.start(appID: 1, name: "One", bottleID: UUID())

        store.markPausing(appID: 1)
        store.setStatus(appID: 1, phase: "Downloading…")
        XCTAssertEqual(store.entry(for: 1)?.status, .pausing)

        store.pause(appID: 1)
        store.setStatus(appID: 1, phase: "Downloading…")
        XCTAssertEqual(store.entry(for: 1)?.status, .paused)
    }

    func testResumeRunsTheSameEntryAgain() {
        let store = DownloadsStore()
        store.start(appID: 1, name: "One", bottleID: UUID())
        store.pause(appID: 1)

        store.start(appID: 1, name: "One", bottleID: UUID())
        store.setStatus(appID: 1, phase: "Validating…")
        XCTAssertEqual(store.entry(for: 1)?.status, .running("Validating…"))
        XCTAssertEqual(store.entries.count, 1)
    }

    // MARK: - After a relaunch

    func testPausedBottleComesBackAsPausedRow() {
        var bottle = makeBottle()
        bottle.steamAppID = 620
        bottle.steamGameName = "Portal 2"
        bottle.pausedDownload = PausedDownload(fraction: 0.35, pausedAt: Date(timeIntervalSince1970: 100))

        let store = DownloadsStore()
        store.restorePaused(from: [bottle, makeBottle()])

        XCTAssertEqual(store.entries.count, 1, "only the bottle with a paused download gets a row")
        let entry = store.entry(for: 620)
        XCTAssertEqual(entry?.name, "Portal 2")
        XCTAssertEqual(entry?.bottleID, bottle.id)
        XCTAssertEqual(entry?.status, .paused)
        XCTAssertEqual(entry?.fraction ?? -1, 0.35, accuracy: 0.0001)
    }

    func testRestoreLeavesARunningRowAlone() {
        var bottle = makeBottle()
        bottle.steamAppID = 620
        bottle.pausedDownload = PausedDownload(fraction: 0.35, pausedAt: Date())

        let store = DownloadsStore()
        store.start(appID: 620, name: "Portal 2", bottleID: bottle.id)
        store.restorePaused(from: [bottle])

        XCTAssertEqual(store.entries.count, 1)
        XCTAssertEqual(store.entry(for: 620)?.status, .running("Connecting…"))
    }

    func testPausedDownloadRoundTripsOnTheBottle() throws {
        var bottle = makeBottle()
        bottle.pausedDownload = PausedDownload(fraction: 0.5, pausedAt: Date(timeIntervalSince1970: 100))
        let decoded = try JSONDecoder().decode(Bottle.self, from: JSONEncoder().encode(bottle))
        XCTAssertEqual(decoded.pausedDownload, bottle.pausedDownload)
    }

    func testBottleFromOlderBuildDecodesWithNothingPaused() throws {
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(makeBottle())) as? [String: Any]
        )
        object.removeValue(forKey: "pausedDownload")
        let decoded = try JSONDecoder().decode(Bottle.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.pausedDownload)
    }

    // MARK: - Stopping the process

    func testStopEndsARunningProcess() async throws {
        let stopper = ProcessStopper()
        let started = Date()
        let run = Task {
            try await ShellRunner.run(executable: "/bin/sleep", arguments: ["30"], environment: [:],
                                      stopper: stopper, outputHandler: { _ in })
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        stopper.stop()

        let result = try await run.value
        XCTAssertTrue(stopper.wasStopped)
        XCTAssertNotEqual(result.exitCode, 0)
        XCTAssertLessThan(Date().timeIntervalSince(started), DownloadPauseLimits.stopGraceSeconds)
    }

    func testStopBeforeStartEndsItAsSoonAsItRuns() async throws {
        let stopper = ProcessStopper()
        stopper.stop()
        let started = Date()
        _ = try await ShellRunner.run(executable: "/bin/sleep", arguments: ["30"], environment: [:],
                                      stopper: stopper, outputHandler: { _ in })
        XCTAssertLessThan(Date().timeIntervalSince(started), DownloadPauseLimits.stopGraceSeconds)
    }

    func testUnstoppedProcessIsNotMarkedStopped() async throws {
        let stopper = ProcessStopper()
        let result = try await ShellRunner.run(executable: "/usr/bin/true", arguments: [], environment: [:],
                                               stopper: stopper, outputHandler: { _ in })
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(stopper.wasStopped)
    }

    private func makeBottle() -> Bottle {
        Bottle.make(
            name: "Test",
            runtime: RuntimeCandidate(kind: .gameNativeWine, executablePath: "/tmp/wine", displayName: "Test Wine"),
            graphicsBackend: .automatic
        )
    }
}
