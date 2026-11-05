import XCTest
@testable import BEER

@MainActor
final class DownloadsStoreProgressTests: XCTestCase {
    func testNothingDownloadingHasNoProgress() {
        XCTAssertNil(DownloadsStore().overallFraction)
    }

    func testRunningDownloadsAreAveraged() {
        let store = DownloadsStore()
        store.start(appID: 1, name: "One", bottleID: UUID())
        store.start(appID: 2, name: "Two", bottleID: UUID())
        store.setProgress(appID: 1, fraction: 0.2, downloaded: nil, total: nil)
        store.setProgress(appID: 2, fraction: 0.6, downloaded: nil, total: nil)
        XCTAssertEqual(store.overallFraction ?? -1, 0.4, accuracy: 0.0001)
    }

    func testFinishedOrFailedDownloadsDropOut() {
        let store = DownloadsStore()
        store.start(appID: 1, name: "One", bottleID: UUID())
        store.start(appID: 2, name: "Two", bottleID: UUID())
        store.setProgress(appID: 2, fraction: 0.5, downloaded: nil, total: nil)
        store.fail(appID: 1, reason: "Cancelled.")
        XCTAssertEqual(store.overallFraction ?? -1, 0.5, accuracy: 0.0001)
    }
}
