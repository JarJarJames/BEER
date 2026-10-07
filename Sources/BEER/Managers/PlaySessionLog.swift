import Foundation
import SwiftUI

/// Everything the presence helper prints, captured to a file.
///
/// The session outlives every call that talks to it, so its output has nowhere
/// else to go — and without this a presence or play-time problem leaves no
/// trace at all to debug from.
enum PlaySessionLog {
    private static let lock = NSLock()

    static func start() {
        lock.withLock {
            try? AppPaths.ensureBaseDirectories()
            let header = "=== presence session — \(Date()) ===\n"
            try? header.write(to: AppPaths.playSessionLogURL, atomically: true, encoding: .utf8)
        }
    }

    static func append(_ text: String) {
        lock.withLock {
            let stamped = text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .map { "\(Date().formatted(date: .omitted, time: .standard))  \($0)\n" }
                .joined()
            guard !stamped.isEmpty, let data = stamped.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: AppPaths.playSessionLogURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? stamped.write(to: AppPaths.playSessionLogURL, atomically: true, encoding: .utf8)
            }
        }
    }
}
