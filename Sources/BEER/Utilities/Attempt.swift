import Foundation
import os

/// A `try?` that leaves a trace. Runs `body`; if it throws, logs `action` and
/// the error to `log` and returns nil.
///
/// Use it where a failure is unexpected but safe to continue past, such as a
/// log file or cache that didn't write. CONVENTIONS.md covers when a plain
/// `try?` is fine instead, and when the error has to be thrown.
@discardableResult
func attempt<T>(_ action: StaticString, log: Logger, _ body: () throws -> T) -> T? {
    do {
        return try body()
    } catch {
        // The domain and code are safe to publish and enough to search on; the
        // description can carry paths, so it stays private.
        let nsError = error as NSError
        log.error("\(String(describing: action), privacy: .public) failed (\(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)): \(error.localizedDescription)")
        return nil
    }
}
