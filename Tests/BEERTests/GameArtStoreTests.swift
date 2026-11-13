import CoreGraphics
import XCTest
@testable import BEER

/// Library art: the disk cache, display-size decoding, the byte-capped memory
/// cache, prefetching, and what changes while a game runs. Art comes from a
/// fake fetch and a temporary folder, never Steam.
final class GameArtStoreTests: XCTestCase {
    private var root: URL!
    private let server = ArtServer()

    /// Serves a 600×900 cover for any address unless told otherwise, and
    /// records every request.
    private final class ArtServer: @unchecked Sendable {
        private let lock = NSLock()
        private var _requests: [URL] = []
        private var _failure: (any Error)?
        private var _body = TestImages.png(width: 600, height: 900)

        var requests: [URL] { lock.withLock { _requests } }
        var failure: (any Error)? {
            get { lock.withLock { _failure } }
            set { lock.withLock { _failure = newValue } }
        }
        var body: Data {
            get { lock.withLock { _body } }
            set { lock.withLock { _body = newValue } }
        }

        func fetch(_ url: URL) async throws -> Data {
            let (failure, body) = lock.withLock {
                _requests.append(url)
                return (_failure, _body)
            }
            if let failure { throw failure }
            return body
        }
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("GameArtStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItemIfPresent(at: root)
    }

    private var cacheDirectory: URL { root.appendingPathComponent("GameArt", isDirectory: true) }

    private func makeStore(memoryLimit: Int = 64 * 1024 * 1024, diskLimit: Int = 10 * 1024 * 1024) -> GameArtStore {
        let server = server
        return GameArtStore(
            fetch: { try await server.fetch($0) },
            disk: GameArtDiskCache(directory: cacheDirectory, limit: diskLimit),
            memoryLimit: memoryLimit
        )
    }

    private func cover(_ appID: Int) -> URL {
        URL(string: "https://cdn.akamai.steamstatic.com/steam/apps/\(appID)/library_600x900.jpg")!
    }

    /// A cover card 100×150 points on a 1× screen: 128×192 pixels once
    /// rounded up to the decode step.
    private func request(_ url: URL, fit: GameArtRequest.Fit = .fit,
                         points: CGSize = CGSize(width: 100, height: 150), scale: CGFloat = 1) -> GameArtRequest {
        GameArtRequest(url: url, points: points, scale: scale, fit: fit)!
    }

    // MARK: - Disk cache

    func testSecondRequestForTheSameArtReadsFromDiskNotTheNetwork() async {
        let first = await makeStore().image(for: request(cover(1)))
        XCTAssertNotNil(first)
        XCTAssertEqual(server.requests.count, 1)

        // A new store has nothing in memory, so this can only come from disk.
        let second = await makeStore().image(for: request(cover(1)))
        XCTAssertNotNil(second)
        XCTAssertEqual(server.requests.count, 1, "The second load went to the network")
    }

    func testDiskCacheStaysUnderItsSizeLimitRemovingTheOldestFirst() throws {
        let fileSize = 1000
        let disk = GameArtDiskCache(directory: cacheDirectory, limit: fileSize * 3 + 400)
        let urls = (1...10).map(cover)
        for url in urls {
            disk.store(Data(repeating: 7, count: fileSize), for: url)
            XCTAssertLessThanOrEqual(disk.totalBytes, disk.limit)
        }
        XCTAssertFalse(disk.contains(urls[0]), "The oldest file should have gone first")
        XCTAssertTrue(disk.contains(urls[9]), "The newest file was removed")
    }

    func testReadingAFileKeepsItLongerThanOnesNotRead() {
        let disk = GameArtDiskCache(directory: cacheDirectory, limit: 3400)
        let (a, b, c, d) = (cover(1), cover(2), cover(3), cover(4))
        for url in [a, b, c] { disk.store(Data(repeating: 1, count: 1000), for: url) }
        XCTAssertNotNil(disk.cachedFile(for: a))
        disk.store(Data(repeating: 1, count: 1000), for: d)

        XCTAssertTrue(disk.contains(a), "A file just read was trimmed")
        XCTAssertFalse(disk.contains(b), "The file used longest ago should have gone")
        XCTAssertTrue(disk.contains(c))
        XCTAssertTrue(disk.contains(d))
    }

    // MARK: - Decoding at display size

    func testDecodedImageIsNoLargerThanTheRequestedPixelSize() async throws {
        let store = makeStore()
        let fit = request(cover(1), fit: .fit)
        let fitImage = await store.image(for: fit)
        let fitted = try XCTUnwrap(fitImage)
        XCTAssertLessThanOrEqual(fitted.width, Int(fit.pixelSize.width))
        XCTAssertLessThanOrEqual(fitted.height, Int(fit.pixelSize.height))

        // Fill covers the frame, cropped on one side, and no more.
        let fill = request(cover(1), fit: .fill, points: CGSize(width: 100, height: 150), scale: 2)
        let fillImage = await store.image(for: fill)
        let filled = try XCTUnwrap(fillImage)
        XCTAssertGreaterThanOrEqual(filled.width, Int(fill.pixelSize.width) - 1)
        XCTAssertGreaterThanOrEqual(filled.height, Int(fill.pixelSize.height) - 1)
        XCTAssertTrue(filled.width <= Int(fill.pixelSize.width) || filled.height <= Int(fill.pixelSize.height))
        XCTAssertLessThan(filled.width, 600, "Decoded at full size")

        let backdropImage = await store.image(for: request(cover(1), fit: .backdrop))
        let backdrop = try XCTUnwrap(backdropImage)
        XCTAssertLessThanOrEqual(max(backdrop.width, backdrop.height), Int(GameArtCacheLimits.backdropPixels))
    }

    func testSmallArtIsNotEnlarged() async throws {
        server.body = TestImages.png(width: 32, height: 32)
        let icon = URL(string: "https://cdn.akamai.steamstatic.com/steamcommunity/public/images/apps/1/icon.jpg")!
        let iconImage = await makeStore().image(for: request(icon, fit: .fill, points: CGSize(width: 80, height: 80), scale: 2))
        let image = try XCTUnwrap(iconImage)
        XCTAssertEqual(image.width, 32)
        XCTAssertEqual(image.height, 32)
    }

    func testCustomArtIsDecodedAtDisplaySizeWithoutTheNetworkOrTheCache() async throws {
        let file = root.appendingPathComponent("app1-cover-1.png")
        try TestImages.png(width: 600, height: 900).write(to: file)
        let custom = request(file, fit: .fit)
        let customImage = await makeStore().image(for: custom)
        let image = try XCTUnwrap(customImage)

        XCTAssertLessThanOrEqual(image.height, Int(custom.pixelSize.height))
        XCTAssertTrue(server.requests.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cacheDirectory.path))
    }

    func testCustomCoverWinsOverSteams() {
        var game = SteamLibraryGame(appID: 10, name: "Game")
        game.customArt = CustomGameArt(coverPath: "/tmp/app10-cover-1.png")
        XCTAssertEqual(game.cardArt(for: .cover), URL(fileURLWithPath: "/tmp/app10-cover-1.png"))
    }

    // MARK: - Memory

    func testMemoryCacheStaysUnderItsByteLimitAndEmptiesOnAMemoryWarning() async throws {
        // A fitted cover at 100×150 points, 1×, decodes to 128×192.
        let imageCost = 128 * 192 * 4
        let store = makeStore(memoryLimit: imageCost * 3 + imageCost / 2)
        var last: GameArtRequest!
        for appID in 1...10 {
            last = request(cover(appID))
            let decoded = await store.image(for: last)
            let image = try XCTUnwrap(decoded)
            XCTAssertEqual(image.width * image.height * 4, imageCost)
            XCTAssertLessThanOrEqual(store.memory.totalCost, store.memory.limit)
        }
        XCTAssertGreaterThan(store.memory.totalCost, 0)
        XCTAssertNotNil(store.cachedImage(for: last))

        store.handleMemoryWarning()
        XCTAssertEqual(store.memory.totalCost, 0)
        XCTAssertNil(store.cachedImage(for: last))
    }

    func testPrefetchDownloadsToDiskWithoutDecoding() async {
        let store = makeStore()
        let urls = [cover(1), cover(2)]
        for task in store.prefetch(urls) { await task.value }

        XCTAssertEqual(Set(server.requests), Set(urls))
        XCTAssertTrue(urls.allSatisfy(store.disk.contains))
        XCTAssertEqual(store.memory.totalCost, 0, "Prefetching decoded art")
        // Already on disk: not downloaded again.
        XCTAssertTrue(store.prefetch(urls).isEmpty)
    }

    func testWhileAGameRunsNothingIsPrefetchedAndDecodedArtIsDropped() async throws {
        let store = makeStore()
        let shown = request(cover(1))
        let shownImage = await store.image(for: shown)
        _ = try XCTUnwrap(shownImage)
        XCTAssertGreaterThan(store.memory.totalCost, 0)

        store.setGameRunning(true)
        XCTAssertEqual(store.memory.totalCost, 0)
        XCTAssertTrue(store.prefetch([cover(2)]).isEmpty)
        // A card on screen still gets its art, but it isn't kept in memory.
        let whileRunning = await store.image(for: request(cover(3)))
        XCTAssertNotNil(whileRunning)
        XCTAssertEqual(store.memory.totalCost, 0)
        XCTAssertFalse(server.requests.contains(cover(2)))

        store.setGameRunning(false)
        _ = await store.image(for: shown)
        XCTAssertGreaterThan(store.memory.totalCost, 0)
    }

    // MARK: - Failures

    func testAFailedFetchShowsThePlaceholderAndSavesNothing() async {
        server.failure = URLError(.notConnectedToInternet)
        let image = await makeStore().image(for: request(cover(1)))
        XCTAssertNil(image)
        XCTAssertTrue(GameArtPhase(image).isFailed)
        XCTAssertFalse(GameArtDiskCache(directory: cacheDirectory).contains(cover(1)))

        // Back online, it loads.
        server.failure = nil
        let backOnline = await makeStore().image(for: request(cover(1)))
        XCTAssertNotNil(backOnline)
    }

    func testAnErrorPageIsNotSavedAsArt() async {
        server.body = Data("<html>Access denied</html>".utf8)
        let store = makeStore()
        let errorPage = await store.image(for: request(cover(1)))
        XCTAssertNil(errorPage)
        XCTAssertFalse(store.disk.contains(cover(1)))
    }

    func testArtSteamDoesNotHaveIsNotAskedForAgain() async {
        server.failure = GameArtError.missing
        let store = makeStore()
        let firstTry = await store.image(for: request(cover(1)))
        XCTAssertNil(firstTry)
        let secondTry = await store.image(for: request(cover(1), fit: .fill))
        XCTAssertNil(secondTry)
        XCTAssertEqual(server.requests.count, 1)
    }

    // MARK: - Prefetch list

    @MainActor
    func testPrefetchListIsTheCardsJustAfterTheOneShown() {
        let games = (1...30).map { SteamLibraryGame(appID: $0, name: "Game \($0)") }
        let urls = SteamLibraryGridViewModel().artToPrefetch(after: games[4], in: games, style: .wide)
        XCTAssertEqual(urls, games[5..<(5 + GameArtCacheLimits.prefetchAhead)].map(\.headerImage))
    }
}
