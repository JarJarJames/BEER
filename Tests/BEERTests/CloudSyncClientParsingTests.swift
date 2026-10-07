import XCTest
@testable import BEER

// CloudSync (the C# helper) streams one JSON object per stdout line, mixed
// with plain diagnostic text on other lines; LineBox is what turns that raw
// chunked stream back into whole lines for CloudSyncClient to decode. It is
// the one piece of that parsing that doesn't need a live helper process or
// Steam account to exercise — every command (achievements-get included) goes
// through it, so a regression here breaks all of them silently.
final class CloudSyncClientParsingTests: XCTestCase {

    func testSplitsCompleteLines() {
        let box = LineBox()
        let lines = box.feed("{\"a\":1}\n{\"b\":2}\n")
        XCTAssertEqual(lines, ["{\"a\":1}", "{\"b\":2}"])
        XCTAssertEqual(box.flush(), [])
    }

    func testHoldsBackAPartialLineUntilItsNewlineArrives() {
        let box = LineBox()
        XCTAssertEqual(box.feed("{\"a\":"), [])
        XCTAssertEqual(box.feed("1}\n"), ["{\"a\":1}"])
    }

    func testChunkBoundariesDoNotDropOrDuplicateLines() {
        let box = LineBox()
        var all: [String] = []
        all += box.feed("line one\nline t")
        all += box.feed("wo\nline three")
        all += box.flush()
        XCTAssertEqual(all, ["line one", "line two", "line three"])
    }

    func testFlushWithNothingBufferedReturnsNothing() {
        let box = LineBox()
        _ = box.feed("complete\n")
        XCTAssertEqual(box.flush(), [])
    }

    func testEmptyLinesAreDropped() {
        let box = LineBox()
        XCTAssertEqual(box.feed("\n\nreal\n\n"), ["real"])
    }
}
