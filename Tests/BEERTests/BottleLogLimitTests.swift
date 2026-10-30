import XCTest
@testable import BEER

@MainActor
final class BottleLogLimitTests: XCTestCase {
    func testInMemoryLogKeepsOnlyTheNewestEntries() {
        let store = BottleStore()
        let bottleID = UUID()
        let total = BottleLogLimits.inMemoryEntries + 250

        for index in 0..<total {
            store.appendLog("line \(index)", bottleID: bottleID)
        }

        let entries = store.logs[bottleID] ?? []
        XCTAssertEqual(entries.count, BottleLogLimits.inMemoryEntries)
        XCTAssertEqual(entries.first?.message, "line 250")
        XCTAssertEqual(entries.last?.message, "line \(total - 1)")
    }
}
