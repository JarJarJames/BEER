import XCTest
@testable import BEER

/// The library card's corner badge: a download's progress, a warning for one
/// that never finished, and the installed states as before.
@MainActor
final class LibraryCardBadgeTests: XCTestCase {
    private func resolve(
        isInstalled: Bool = true, isComplete: Bool = true, isDriveMissing: Bool = false,
        hasUpdate: Bool = false, download: DownloadsStore.Entry? = nil
    ) -> LibraryCardBadge? {
        LibraryCardBadge.resolve(isInstalled: isInstalled, isComplete: isComplete,
                                 isDriveMissing: isDriveMissing, hasUpdate: hasUpdate, download: download)
    }

    private func entry(_ configure: (DownloadsStore) -> Void) -> DownloadsStore.Entry? {
        let store = DownloadsStore()
        store.start(appID: 1, name: "Game", bottleID: UUID())
        configure(store)
        return store.entry(for: 1)
    }

    func testInstalledStatesAreUnchanged() {
        XCTAssertEqual(resolve(), .installed)
        XCTAssertEqual(resolve(hasUpdate: true), .update)
        XCTAssertEqual(resolve(isDriveMissing: true, hasUpdate: true), .driveMissing)
        XCTAssertNil(resolve(isInstalled: false))
    }

    func testUnfinishedDownloadWarnsItIsNotInstalled() {
        XCTAssertEqual(resolve(isComplete: false), .notInstalled)
        XCTAssertEqual(resolve(isComplete: false, hasUpdate: true), .notInstalled)
    }

    func testRunningDownloadShowsItsProgress() {
        let running = entry { $0.setProgress(appID: 1, fraction: 0.42, downloaded: nil, total: nil) }
        XCTAssertEqual(resolve(isComplete: false, download: running), .downloading(0.42))
        // Its first steps come before the game is marked installed.
        XCTAssertEqual(resolve(isInstalled: false, download: running), .downloading(0.42))
        // An update to an installed game.
        XCTAssertEqual(resolve(hasUpdate: true, download: running), .downloading(0.42))
    }

    func testPausedDownloadShowsWhereItStopped() {
        let paused = entry {
            $0.setProgress(appID: 1, fraction: 0.3, downloaded: nil, total: nil)
            $0.pause(appID: 1)
        }
        XCTAssertEqual(resolve(isComplete: false, download: paused), .paused(0.3))
    }

    func testFinishedOrFailedDownloadFallsBackToTheBottle() {
        let failed = entry { $0.fail(appID: 1, reason: "Install failed") }
        XCTAssertEqual(resolve(isComplete: false, download: failed), .notInstalled)
        let done = entry { $0.complete(appID: 1) }
        XCTAssertEqual(resolve(download: done), .installed)
    }

    func testTextAndFill() {
        XCTAssertEqual(LibraryCardBadge.downloading(0.42).text, "DOWNLOADING 42%")
        XCTAssertEqual(LibraryCardBadge.paused(0.3).text, "PAUSED 30%")
        XCTAssertEqual(LibraryCardBadge.notInstalled.text, "NOT INSTALLED")
        XCTAssertEqual(LibraryCardBadge.paused(0.3).fraction, 0.3)
        XCTAssertNil(LibraryCardBadge.installed.fraction)
    }
}
