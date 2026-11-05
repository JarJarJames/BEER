import XCTest
@testable import BEER

/// Runtime downloads report their bytes as they arrive, and only write the
/// file when the server answers with it. Served by a fake URLProtocol, so
/// nothing touches the network.
final class FileDownloadTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileDownloadTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChunkedServer.self]
        return configuration
    }

    func testReportsProgressAndWritesFile() async throws {
        let body = Data((0..<1_200_000).map { UInt8($0 % 251) })
        ChunkedServer.answer = (200, body)
        let destination = folder.appendingPathComponent("runtime.tar.xz")
        let reports = Reports()

        let response = try await FileDownload.run(
            from: URL(string: "https://example.com/runtime.tar.xz")!, to: destination,
            configuration: configuration, progress: { reports.add($0, $1) }
        )

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try Data(contentsOf: destination), body)
        let seen = reports.all
        XCTAssertGreaterThan(seen.count, 1, "a download in chunks reports more than once")
        XCTAssertEqual(seen.map(\.received), seen.map(\.received).sorted())
        XCTAssertEqual(seen.last?.received, Int64(body.count))
        XCTAssertTrue(seen.allSatisfy { $0.expected == Int64(body.count) })
    }

    func testFailedAnswerLeavesNoFile() async throws {
        ChunkedServer.answer = (404, Data("Not Found".utf8))
        let destination = folder.appendingPathComponent("runtime.tar.xz")

        let response = try await FileDownload.run(
            from: URL(string: "https://example.com/missing.tar.xz")!, to: destination,
            configuration: configuration, progress: { _, _ in }
        )

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 404)
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
    }

    func testReplacesAnEarlierPartialFile() async throws {
        let destination = folder.appendingPathComponent("runtime.tar.xz")
        try Data("old".utf8).write(to: destination)
        ChunkedServer.answer = (200, Data("new archive".utf8))

        _ = try await FileDownload.run(
            from: URL(string: "https://example.com/runtime.tar.xz")!, to: destination,
            configuration: configuration, progress: { _, _ in }
        )

        XCTAssertEqual(try Data(contentsOf: destination), Data("new archive".utf8))
    }
}

private final class Reports: @unchecked Sendable {
    private let lock = NSLock()
    private var reports: [ByteProgress] = []

    func add(_ received: Int64, _ expected: Int64) {
        lock.lock(); reports.append(ByteProgress(received: received, expected: expected)); lock.unlock()
    }

    var all: [ByteProgress] { lock.lock(); defer { lock.unlock() }; return reports }
}

/// Answers every request with `answer`, sent in several chunks with its
/// length, the way a real server streams a big file.
private final class ChunkedServer: URLProtocol {
    nonisolated(unsafe) static var answer: (status: Int, body: Data) = (200, Data())
    private static let chunkSize = 100_000

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let (status, body) = Self.answer
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Length": "\(body.count)"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        var offset = 0
        while offset < body.count {
            let end = min(offset + Self.chunkSize, body.count)
            client?.urlProtocol(self, didLoad: body.subdata(in: offset..<end))
            offset = end
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
