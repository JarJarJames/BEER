import XCTest
@testable import BEER

// The pieces that replace silent `try?`: a delete that only forgives "already
// gone", and `attempt`, which logs and returns nil instead of hiding a failure.
final class ErrorHandlingTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ErrorHandlingTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    func testRemoveItemIfPresentDeletesAFile() throws {
        let file = root.appendingPathComponent("cache")
        try Data("x".utf8).write(to: file)

        try FileManager.default.removeItemIfPresent(at: file)

        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testRemoveItemIfPresentForgivesAMissingFile() {
        XCTAssertNoThrow(try FileManager.default.removeItemIfPresent(at: root.appendingPathComponent("never-existed")))
    }

    func testRemoveItemIfPresentStillThrowsWhenDeleteIsRefused() throws {
        let file = root.appendingPathComponent("cache")
        try Data("x".utf8).write(to: file)
        // Deleting a file needs write permission on its folder.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)

        XCTAssertThrowsError(try FileManager.default.removeItemIfPresent(at: file))
    }

    func testAttemptReturnsTheValueOnSuccess() {
        XCTAssertEqual(attempt("add", log: Log.cloudSync) { 2 + 2 }, 4)
    }

    func testAttemptReturnsNilOnFailure() {
        struct Failure: Error {}
        let result: Int? = attempt("fail", log: Log.cloudSync) { throw Failure() }

        XCTAssertNil(result)
    }
}
