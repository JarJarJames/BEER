import XCTest
@testable import BEER

final class DepotDownloaderOutputParsingTests: XCTestCase {
    func testAppLevelNotOwnedIsDetected() {
        XCTAssertEqual(
            parseNotOwned("App 3368600 (Brushes with Death) is not available from this account."),
            "Brushes with Death")
    }

    /// Regression: Kenshi's log contains this line yet downloads fine.
    func testOptionalDepotLineIsNotTreatedAsNotOwned() {
        XCTAssertNil(parseNotOwned("Depot 468550 is not available from this account."))
    }

    func testUnrelatedLineIsIgnored() {
        XCTAssertNil(parseNotOwned("Got 521 licenses for account!"))
    }
}
