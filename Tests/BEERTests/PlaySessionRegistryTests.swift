import XCTest
@testable import BEER

final class PlaySessionRegistryTests: XCTestCase {
    func testThisRunsOwnHelperIsNotAnOrphan() {
        let record = PlaySessionRegistry.Record(pid: 500, owner: 100)

        XCTAssertFalse(PlaySessionRegistry.isOrphan(record, currentPID: 100))
    }

    func testHelperFromAnEarlierRunIsAnOrphan() {
        let record = PlaySessionRegistry.Record(pid: 500, owner: 99)

        XCTAssertTrue(PlaySessionRegistry.isOrphan(record, currentPID: 100))
    }

    func testRecordWrittenBeforeOwnersWereTrackedIsAnOrphan() throws {
        let record = try JSONDecoder().decode(PlaySessionRegistry.Record.self, from: Data(#"{"pid":500}"#.utf8))

        XCTAssertNil(record.owner)
        XCTAssertTrue(PlaySessionRegistry.isOrphan(record, currentPID: 100))
    }
}
