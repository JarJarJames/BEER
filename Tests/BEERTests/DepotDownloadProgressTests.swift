import XCTest
@testable import BEER

/// One progress bar for a whole multi-depot download. DepotDownloader's
/// percentages are per depot; these feed recorded output for 2–3 depots
/// through `DepotDownloadProgress` and check the overall fraction only rises
/// and ends at 1.
final class DepotDownloadProgressTests: XCTestCase {
    private let game = "/Volumes/Games/BEER/Games/Some Game"

    /// Three depots, shaped like DepotDownloader's real output: every depot is
    /// processed (manifests fetched or already there) before any downloads.
    private func threeDepotRun(depot102: [String]) -> [String] {
        [
            "Processing depot 101",
            "Downloading depot 101 manifest",
            "Manifest 7613356809904826842 (11/2/2026 4:12:09 PM)",
            "Processing depot 102",
            "Already have manifest 1946281937584627310 for depot 102.",
            "Manifest 1946281937584627310 (10/30/2026 9:01:44 AM)",
            "Processing depot 103",
            "Downloading depot 103 manifest",
            "Manifest 4410276540096161234 (11/2/2026 4:12:10 PM)",
            "Downloading depot 101",
            "Pre-allocating \(game)/Data/level0.pak",
            " 50.00% \(game)/Data/level0.pak",
            "100.00% \(game)/Data/level0.pak",
            "Depot 101 - Downloaded 600 bytes (600 bytes uncompressed)",
            "Downloading depot 102",
        ] + depot102 + [
            "Downloading depot 103",
            "Pre-allocating \(game)/Game.exe",
            " 25.00% \(game)/Game.exe",
            "100.00% \(game)/Game.exe",
            "Depot 103 - Downloaded 100 bytes (100 bytes uncompressed)",
            "Total downloaded: 1000 bytes (1000 bytes uncompressed) from 3 depots",
        ]
    }

    private lazy var depot102Downloads = [
        "Pre-allocating \(game)/Data/level1.pak",
        " 50.00% \(game)/Data/level1.pak",
        "100.00% \(game)/Data/level1.pak",
        "Depot 102 - Downloaded 300 bytes (300 bytes uncompressed)",
    ]

    func testWeightsEachDepotBySize() {
        let shown = fractions(for: threeDepotRun(depot102: depot102Downloads),
                              depotBytes: [101: 600, 102: 300, 103: 100])
        assertEqual(shown, [0.3, 0.6, 0.75, 0.9, 0.925, 1.0])
    }

    func testSplitsEquallyWithoutSizes() {
        let shown = fractions(for: threeDepotRun(depot102: depot102Downloads))
        assertEqual(shown, [1.0 / 6, 2.0 / 6, 3.0 / 6, 4.0 / 6, 4.0 / 6 + 1.0 / 12, 1.0])
    }

    /// An update where depot 102 didn't change: it has nothing to fetch and
    /// finishes as soon as it starts, so the bar jumps by its share.
    func testDepotWithNothingToFetchJumpsForward() {
        let instant = ["Depot 102 - Downloaded 0 bytes (0 bytes uncompressed)"]
        let shown = fractions(for: threeDepotRun(depot102: instant), depotBytes: [101: 600, 102: 300, 103: 100])
        assertEqual(shown, [0.3, 0.6, 0.9, 0.925, 1.0])
    }

    /// A depot Steam lists no size for counts as the average of the others.
    func testDepotWithoutASizeCountsAsTheAverage() {
        let shown = fractions(for: threeDepotRun(depot102: depot102Downloads), depotBytes: [101: 600, 103: 200])
        // 101 = 600, 102 = 400 (average), 103 = 200; 1200 in all.
        assertEqual(shown, [0.25, 0.5, 4.0 / 6, 5.0 / 6, 5.0 / 6 + 0.25 / 6, 1.0])
    }

    /// Fetching manifests mustn't move the bar: "Downloading depot <id>
    /// manifest" is not that depot's download starting.
    func testProcessingDepotsDoesNotMoveTheBar() {
        let processing = Array(threeDepotRun(depot102: depot102Downloads).prefix(9))
        XCTAssertEqual(fractions(for: processing, depotBytes: [101: 600, 102: 300, 103: 100]), [])
    }

    /// Two depots where the first never prints 100% (a later depot overwrites
    /// some of its files): it still counts as done once it ends.
    func testDepotThatStopsShortCountsAsDoneWhenItEnds() {
        let shown = fractions(for: [
            "Processing depot 201",
            "Processing depot 202",
            "Downloading depot 201",
            " 40.00% \(game)/a.pak",
            " 80.00% \(game)/b.pak",
            "Depot 201 - Downloaded 800 bytes (800 bytes uncompressed)",
            "Downloading depot 202",
            " 99.99% \(game)/c.pak",
            "Total downloaded: 1800 bytes (1800 bytes uncompressed) from 2 depots",
        ])
        assertEqual(shown, [0.2, 0.4, 0.5, 0.99995, 1.0])
    }

    /// Never backwards, even if a percentage line comes in lower than the last.
    func testNeverGoesBackwards() {
        var progress = DepotDownloadProgress()
        _ = progress.update(with: "Processing depot 1")
        _ = progress.update(with: "Downloading depot 1")
        XCTAssertEqual(progress.update(with: " 60.00% a"), 0.6)
        XCTAssertNil(progress.update(with: " 40.00% b"))
        XCTAssertEqual(progress.fraction, 0.6)
    }

    /// Output with no depot lines (an older DepotDownloader) passes its one
    /// percentage straight through.
    func testOutputWithoutDepotLinesPassesThrough() {
        assertEqual(fractions(for: [" 12.00% a", "Downloaded 50 / 100 MB"]), [0.12, 0.5])
    }

    // MARK: - Helpers

    /// The fractions BEER would show, in order, for `lines`.
    private func fractions(for lines: [String], depotBytes: [Int: Int64] = [:]) -> [Double] {
        var progress = DepotDownloadProgress(depotBytes: depotBytes)
        let shown = lines.compactMap { progress.update(with: $0) }
        XCTAssertEqual(shown, shown.sorted(), "only rises")
        XCTAssertEqual(Set(shown).count, shown.count, "each value moves forward")
        return shown
    }

    private func assertEqual(_ shown: [Double], _ expected: [Double], line: UInt = #line) {
        XCTAssertEqual(shown.count, expected.count, "\(shown)", line: line)
        for (a, b) in zip(shown, expected) {
            XCTAssertEqual(a, b, accuracy: 0.0001, "\(shown)", line: line)
        }
    }
}
