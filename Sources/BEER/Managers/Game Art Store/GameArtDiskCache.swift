import Foundation

/// Downloaded library art, kept on disk as the original compressed files:
/// the cache that makes a card's art show at once the second time. Capped at
/// `limit` bytes; past it, the files used longest ago go first.
final class GameArtDiskCache: @unchecked Sendable {
    let directory: URL
    let limit: Int
    private let lock = NSLock()
    /// The folder's size, measured on the first write and kept up to date
    /// after. Nil until then.
    private var knownBytes: Int?

    init(directory: URL = AppPaths.gameArtCacheDirectory, limit: Int = GameArtCacheLimits.diskBytes) {
        self.directory = directory
        self.limit = limit
    }

    /// Where `url`'s art is kept: named by a hash of the address, so any URL
    /// makes a safe, unique file name.
    func file(for url: URL) -> URL {
        let name = SHA256Digest.hexDigest(Data(url.absoluteString.utf8))
        let ext = url.pathExtension.lowercased()
        return directory.appendingPathComponent(ext.isEmpty || ext.count > 4 ? name : "\(name).\(ext)")
    }

    func contains(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: file(for: url).path)
    }

    /// The saved file for `url`, marked as just used so trimming keeps it
    /// longest. Nil when it isn't saved.
    func cachedFile(for url: URL) -> URL? {
        let file = file(for: url)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        // A file trimmed in the meantime just downloads again; nothing to trace.
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: file.path)
        return file
    }

    func store(_ data: Data, for url: URL) {
        let written: Void? = attempt("Save game art", log: Log.art) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file(for: url), options: .atomic)
        }
        guard written != nil else { return }
        let isFull = lock.withLock {
            let total = knownBytes.map { $0 + data.count } ?? measure().reduce(0) { $0 + $1.bytes }
            knownBytes = total
            return total > limit
        }
        if isFull { trim() }
    }

    /// Removes the files used longest ago until the folder is under its
    /// trim target.
    func trim() {
        lock.withLock {
            let files = measure()
            var total = files.reduce(0) { $0 + $1.bytes }
            let target = Int(Double(limit) * GameArtCacheLimits.diskTrimTarget)
            for file in files.sorted(by: { $0.used < $1.used }) where total > target {
                let removed: Void? = attempt("Trim game art cache", log: Log.art) {
                    try FileManager.default.removeItemIfPresent(at: file.url)
                }
                if removed != nil { total -= file.bytes }
            }
            knownBytes = total
        }
    }

    /// The folder's total size in bytes.
    var totalBytes: Int {
        lock.withLock { measure().reduce(0) { $0 + $1.bytes } }
    }

    private func measure() -> [(url: URL, bytes: Int, used: Date)] {
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey]
        // No folder yet just means nothing is saved.
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: keys, options: .skipsHiddenFiles)) ?? []
        return files.compactMap { file in
            guard let values = try? file.resourceValues(forKeys: Set(keys)) else { return nil }
            return (file, values.fileSize ?? 0, values.contentModificationDate ?? .distantPast)
        }
    }
}
