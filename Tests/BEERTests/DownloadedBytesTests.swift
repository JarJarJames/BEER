import XCTest
@testable import BEER

/// The download bar between DepotDownloader's per-file percentages. A temp
/// folder stands in for the game's; nothing downloads.
final class DownloadedBytesTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: folder)
    }

    /// Pre-allocated the way DepotDownloader does it (`File.Create` then
    /// `SetLength`), a 64 MB file with 1 MB written counts as 1 MB.
    func testAPreAllocatedFileCountsOnlyWhatHasArrived() throws {
        let file = folder.appendingPathComponent("BIGFILE.000")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 64 << 20)
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data(repeating: 7, count: 1 << 20))
        try handle.close()

        let bytes = try XCTUnwrap(DownloadedBytes.measure(folder))
        XCTAssertGreaterThanOrEqual(bytes, 1 << 20)
        XCTAssertLessThan(bytes, 4 << 20)
    }

    func testTheTotalIsEveryListedDepot() {
        let sizes = [228982: 9_688_647, 228990: 102_931_551, 238011: 16_000_000_000] as [Int: Int64]
        XCTAssertEqual(DownloadedBytes.total(of: [228982, 238011], sizes: sizes), 16_009_688_647)
        XCTAssertEqual(DownloadedBytes.total(of: nil, sizes: sizes), 16_112_620_198)
    }

    /// An unsized depot would let the folder outgrow the total.
    func testNoTotalWhenADepotHasNoSize() {
        XCTAssertNil(DownloadedBytes.total(of: [228982, 238011], sizes: [238011: 1000]))
        XCTAssertNil(DownloadedBytes.total(of: nil, sizes: [:]))
        XCTAssertNil(DownloadedBytes.total(of: [], sizes: [1: 10]))
    }

    /// Only DepotDownloader's own "done" fills the bar.
    func testTheFolderNeverFinishesTheBar() {
        XCTAssertEqual(DownloadedBytes.fraction(25, of: 100), 0.25)
        XCTAssertEqual(DownloadedBytes.fraction(100, of: 100), 0.99)
        XCTAssertEqual(DownloadedBytes.fraction(150, of: 100), 0.99)
    }
}
