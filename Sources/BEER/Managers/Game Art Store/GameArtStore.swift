import CoreGraphics
import Foundation
import ImageIO

/// Library art for the cards: from memory if it was just decoded, else from
/// the disk cache, else downloaded into it. Each image is decoded at the
/// size its card shows it.
///
/// BEER runs beside the game it launched, so art lives on disk, not in
/// memory: memory holds only a few screens' worth of decoded images, and
/// none while a game is running.
final class GameArtStore: @unchecked Sendable {
    static let shared = GameArtStore()

    /// Reads art from the network. Swappable so tests don't need it.
    let fetch: @Sendable (URL) async throws -> Data
    let disk: GameArtDiskCache
    let memory: GameArtMemoryCache

    private let lock = NSLock()
    private var isGameRunning = false
    /// Art being downloaded ahead of its card.
    private var prefetching: Set<URL> = []
    /// Art Steam doesn't have, so a card scrolling back doesn't ask again.
    private var missing: Set<URL> = []
    private let pressure: DispatchSourceMemoryPressure

    init(
        fetch: @escaping @Sendable (URL) async throws -> Data = GameArtStore.download,
        disk: GameArtDiskCache = GameArtDiskCache(),
        memoryLimit: Int = GameArtStore.screenMemoryLimit
    ) {
        self.fetch = fetch
        self.disk = disk
        memory = GameArtMemoryCache(limit: memoryLimit)
        pressure = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .global(qos: .utility))
        pressure.setEventHandler { [weak self] in self?.handleMemoryWarning() }
        pressure.activate()
    }

    deinit { pressure.cancel() }

    /// The art if it's decoded already, with no disk or network: what a card
    /// draws in its first frame.
    func cachedImage(for request: GameArtRequest) -> CGImage? {
        memory.image(for: request.cacheKey)
    }

    /// The art for `request`, or nil when there's none or it couldn't load.
    @concurrent
    func image(for request: GameArtRequest) async -> CGImage? {
        if let image = cachedImage(for: request) { return image }
        guard let image = await decode(request) else { return nil }
        if !lock.withLock({ isGameRunning }) { memory.insert(image, for: request.cacheKey) }
        return image
    }

    /// Downloads art for cards about to scroll into view, to disk only:
    /// nothing is decoded until its card shows. Skipped while a game runs.
    /// The tasks are returned for tests to wait on.
    @discardableResult
    func prefetch(_ urls: [URL]) -> [Task<Void, Never>] {
        urls.compactMap { url in
            guard !url.isFileURL, !disk.contains(url) else { return nil }
            let claimed = lock.withLock {
                guard !isGameRunning, prefetching.count < GameArtCacheLimits.prefetchConcurrency,
                      !missing.contains(url), prefetching.insert(url).inserted else { return false }
                return true
            }
            guard claimed else { return nil }
            return Task.detached(priority: .utility) { [self] in
                _ = await download(url)
                lock.withLock { _ = prefetching.remove(url) }
            }
        }
    }

    /// While a game runs, BEER keeps as little as it can: decoded art that
    /// isn't on screen is dropped, and nothing is downloaded ahead.
    func setGameRunning(_ running: Bool) {
        lock.withLock { isGameRunning = running }
        if running { memory.removeAll() }
    }

    func handleMemoryWarning() {
        memory.removeAll()
    }

    private func decode(_ request: GameArtRequest) async -> CGImage? {
        let url = request.url
        // The player's own art is already on disk.
        if url.isFileURL { return GameArtDecoder.image(at: url, for: request) }
        // A file that won't decode (cut short, or trimmed meanwhile) is
        // downloaded again.
        if let file = disk.cachedFile(for: url), let image = GameArtDecoder.image(at: file, for: request) {
            return image
        }
        guard let data = await download(url) else { return nil }
        return GameArtDecoder.image(from: data, for: request)
    }

    /// Downloads `url` into the disk cache. Nil if it failed or isn't an image.
    private func download(_ url: URL) async -> Data? {
        if lock.withLock({ missing.contains(url) }) { return nil }
        let data: Data
        do {
            data = try await fetch(url)
        } catch GameArtError.missing {
            lock.withLock { _ = missing.insert(url) }
            return nil
        } catch {
            // A card that scrolled away cancels its download; that's no failure.
            if !Task.isCancelled {
                Log.art.error("Game art download failed: \(error.localizedDescription, privacy: .public)")
            }
            return nil
        }
        // Only images reach the disk: an error page saved as art would fail
        // every load after it.
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return nil }
        disk.store(data, for: url)
        return data
    }
}

extension GameArtStore {
    /// No memory cache of its own: the art cache on disk is the cache, so
    /// URLSession keeping a second copy would only cost memory and disk.
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.urlCache = URLCache(memoryCapacity: 0, diskCapacity: 0)
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    @Sendable
    static func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 404 { throw GameArtError.missing }
            guard (200..<300).contains(http.statusCode) else { throw GameArtError.status(http.statusCode) }
        }
        return data
    }

    /// `GameArtCacheLimits.memoryScreens` of the main display's pixels, at
    /// 4 bytes each. Read through Core Graphics, which any thread may call.
    static var screenMemoryLimit: Int {
        let mode = CGDisplayCopyDisplayMode(CGMainDisplayID())
        let pixels = mode.map { $0.pixelWidth * $0.pixelHeight } ?? 0
        return GameArtCacheLimits.memoryScreens * 4 * (pixels > 0 ? pixels : GameArtCacheLimits.fallbackScreenPixels)
    }
}
