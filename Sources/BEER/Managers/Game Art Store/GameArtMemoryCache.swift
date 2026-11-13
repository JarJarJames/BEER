import CoreGraphics
import Foundation

/// Decoded art for cards that just scrolled away, so scrolling back doesn't
/// decode it again. Capped by bytes, not images: a card's decoded image
/// costs width × height × 4. Cards on screen hold their own images; this
/// only decides how many more stay around.
final class GameArtMemoryCache: NSObject, NSCacheDelegate, @unchecked Sendable {
    private final class Entry {
        let image: CGImage
        let cost: Int
        init(image: CGImage, cost: Int) {
            self.image = image
            self.cost = cost
        }
    }

    let limit: Int
    private let cache = NSCache<NSString, Entry>()
    private let lock = NSLock()
    private var cost = 0

    init(limit: Int) {
        self.limit = limit
        super.init()
        cache.totalCostLimit = limit
        cache.delegate = self
    }

    /// The bytes held now.
    var totalCost: Int { lock.withLock { cost } }

    func image(for key: String) -> CGImage? {
        cache.object(forKey: key as NSString)?.image
    }

    func insert(_ image: CGImage, for key: String) {
        let entryCost = image.width * image.height * 4
        // Already there (another card decoded it too), or bigger than the
        // whole cache.
        guard entryCost <= limit, cache.object(forKey: key as NSString) == nil else { return }
        // Counted first: the cache evicts to make room inside `setObject`,
        // and the evictions are subtracted as they happen.
        lock.withLock { cost += entryCost }
        cache.setObject(Entry(image: image, cost: entryCost), forKey: key as NSString, cost: entryCost)
    }

    func removeAll() {
        cache.removeAllObjects()
        lock.withLock { cost = 0 }
    }

    func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        guard let entry = obj as? Entry else { return }
        lock.withLock { cost = max(0, cost - entry.cost) }
    }
}
