import Foundation

// Not private: exercised directly by CloudSyncClientParsingTests (via
// @testable import) so its line-splitting logic — the one place a helper
// invocation's raw stdout is actually parsed — has offline coverage that
// doesn't need a live helper process or Steam account.
final class LineBox: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func feed(_ chunk: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        buffer += chunk
        var lines = buffer.components(separatedBy: "\n")
        if buffer.hasSuffix("\n") {
            buffer = ""
        } else {
            buffer = lines.removeLast()
        }
        return lines.filter { !$0.isEmpty }
    }

    func flush() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let rest = buffer
        buffer = ""
        return rest.isEmpty ? [] : [rest]
    }
}
