import XCTest
@testable import BEER

/// DepotDownloader's output in a pseudo-terminal, as `Ansi.Progress` and its
/// prompts write it (3.4.0). No DepotDownloader runs.
final class DepotDownloaderOutputTests: XCTestCase {
    private let esc = "\u{1B}"
    private let bel = "\u{07}"

    private func progress(_ state: Int, _ percent: Int) -> String { "\(esc)]9;4;\(state);\(percent)\(bel)" }

    /// One per chunk, with no newline, in among the per-file lines.
    func testReadsTheWholeRunsProgress() {
        var output = DepotDownloaderOutput()
        let read = output.consume(progress(3, 0) + progress(1, 41) + progress(1, 42)
                                  + " 12.50% C:\\Games\\BIGFILE.000\r\n" + progress(1, 43))
        XCTAssertEqual(read.progress, [0.41, 0.42, 0.43])
        XCTAssertEqual(read.lines, [" 12.50% C:\\Games\\BIGFILE.000"])
    }

    func testASequenceSplitAcrossReadsIsReadOnce() {
        var output = DepotDownloaderOutput()
        XCTAssertEqual(output.consume("\(esc)]9;4;1;5").progress, [])
        XCTAssertEqual(output.consume("7\(bel)Depot 238011 - Downloaded 5 bytes\r\n").progress, [0.57])
    }

    /// Indeterminate at the start, hidden at the end: no percentage.
    func testOnlyAPercentageCounts() {
        var output = DepotDownloaderOutput()
        XCTAssertEqual(output.consume(progress(3, 0) + progress(0, 0) + progress(2, 50) + "\n").progress, [])
    }

    /// It waits at these for input that never comes, so they can't wait for a newline.
    func testAPromptIsReportedWithoutItsNewline() {
        var output = DepotDownloaderOutput()
        XCTAssertEqual(output.consume("Logging 'player' into Steam3...\r\n Done!\r\nEnter account password for \"player\": ").prompt,
                       "Enter account password for \"player\": ")
        XCTAssertEqual(output.consume("Please enter your 2 factor auth code from your authenticator app: ").prompt,
                       "Please enter your 2 factor auth code from your authenticator app: ")
        XCTAssertEqual(output.consume("Please enter the authentication code sent to your email address: ").prompt,
                       "Please enter the authentication code sent to your email address: ")
    }

    func testOrdinaryPartialOutputWaitsForItsLine() {
        var output = DepotDownloaderOutput()
        let first = output.consume("Connecting to Steam3...")
        XCTAssertEqual(first, DepotDownloaderOutput.Read())
        XCTAssertEqual(output.consume(" Done!\r\n").lines, ["Connecting to Steam3... Done!"])
        _ = output.consume("Total downloaded: 9 bytes")
        XCTAssertEqual(output.finish(), "Total downloaded: 9 bytes")
    }

    /// The runtime switches the terminal's modes before the first line.
    func testTerminalModesAreScrubbed() {
        var output = DepotDownloaderOutput()
        let read = output.consume("\(esc)[?1h\(esc)=\(esc)[32mProcessing depot 238011\(esc)[0m\r\n\r\n")
        XCTAssertEqual(read.lines, ["Processing depot 238011"])
    }
}
