import XCTest
@testable import BEER

/// Regression: DepotDownloader without `-loginid` logs on with the same ID the
/// real Steam client on this Mac uses, so every install signed that client out.
@MainActor
final class DepotDownloaderLoginIDTests: XCTestCase {
    func testDownloadPassesItsOwnLoginID() {
        let args = DepotDownloaderController.downloadArguments(
            appID: 570940, installDir: URL(fileURLWithPath: "/tmp/game"),
            accountName: "someone", loginID: 1234)

        let flag = args.firstIndex(of: "-loginid")
        XCTAssertNotNil(flag, "without -loginid DepotDownloader replaces the real Steam client's session")
        XCTAssertEqual(flag.map { args[$0 + 1] }, "1234")
    }

    func testLoginIDNeverCollidesWithPresenceSession() {
        let presenceLoginID: UInt32 = 0x42454552 // CloudSync's SteamSession.SessionLoginID
        for _ in 0..<1000 {
            let id = DepotDownloaderController.newLoginID()
            XCTAssertNotEqual(id, 0)
            XCTAssertNotEqual(id, presenceLoginID)
        }
    }
}
