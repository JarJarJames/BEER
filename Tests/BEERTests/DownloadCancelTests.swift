import XCTest
@testable import BEER

/// A cancelled download stays cancelled until its install deletes what it
/// put on disk, whatever DepotDownloader prints on its way out.
@MainActor
final class DownloadCancelTests: XCTestCase {
    private func running() -> DownloadsStore {
        let store = DownloadsStore()
        store.start(appID: 238010, name: "Deus Ex", bottleID: UUID())
        store.setProgress(appID: 238010, fraction: 0.5, downloaded: nil, total: nil)
        return store
    }

    func testCancelWithNothingRunningMarksTheDownload() {
        let downloads = running()
        DepotDownloaderController().cancel(238010, in: downloads)

        XCTAssertTrue(downloads.isCancelling(238010))
        XCTAssertTrue(downloads.entry(for: 238010)?.isActive == true)
        XCTAssertEqual(downloads.entry(for: 238010)?.phaseText, DownloadsStrings.cancelling)
    }

    func testLateOutputDoesNotUndoACancel() {
        let downloads = running()
        downloads.markCancelling(appID: 238010)

        downloads.setStatus(appID: 238010, phase: "Downloading…")
        downloads.markPausing(appID: 238010)

        XCTAssertTrue(downloads.isCancelling(238010))
    }

    func testCancelOverridesAPauseInProgress() {
        let downloads = running()
        downloads.markPausing(appID: 238010)
        downloads.markCancelling(appID: 238010)
        XCTAssertTrue(downloads.isCancelling(238010))
    }
}
