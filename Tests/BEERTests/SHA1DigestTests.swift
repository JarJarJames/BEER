import Foundation
import XCTest
@testable import BEER

final class SHA1DigestTests: XCTestCase {
    func testMatchesSteamBase64Digest() throws {
        let file = try temporaryFile(containing: Data("abc".utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertTrue(SHA1Digest.fileMatches(
            file,
            remoteDigest: "qZk+NkcGgWq6PiVxeFDCbJzQ2J0="
        ))
    }

    func testMatchesHexDigestCaseInsensitively() throws {
        let file = try temporaryFile(containing: Data("abc".utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertTrue(SHA1Digest.fileMatches(
            file,
            remoteDigest: "A9993E364706816ABA3E25717850C26C9CD0D89D"
        ))
    }

    func testRejectsDifferentContent() throws {
        let file = try temporaryFile(containing: Data("changed".utf8))
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertFalse(SHA1Digest.fileMatches(
            file,
            remoteDigest: "qZk+NkcGgWq6PiVxeFDCbJzQ2J0="
        ))
    }

    private func temporaryFile(containing data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("beer-sha1-test-\(UUID().uuidString)")
        try data.write(to: url, options: .atomic)
        return url
    }
}
