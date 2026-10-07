import Foundation

/// Runs a closure the first time it is asked and never again.
final class OnceBox: @unchecked Sendable {
    private let lock = NSLock()
    private var body: (() -> Void)?

    init(_ body: @escaping () -> Void) { self.body = body }

    func run() {
        let action: (() -> Void)? = lock.withLock {
            defer { body = nil }
            return body
        }
        action?()
    }
}
