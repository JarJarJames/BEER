import Foundation

final class OutputBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    func append(_ chunk: String) {
        lock.lock()
        storage += chunk
        lock.unlock()
    }

    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
