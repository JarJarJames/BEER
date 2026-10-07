import Foundation

/// Resumes a `run()` call exactly once, once BOTH the pipe has reached true
/// EOF (nothing more will ever be read) and the exit code is known — in
/// whichever order those two independent events happen to arrive.
final class CompletionGate: @unchecked Sendable {
    private let lock = NSLock()
    private var eofSeen = false
    private var exitCode: Int32?
    private var resumed = false

    func markEOF(_ resume: (Int32) -> Void) {
        lock.lock()
        eofSeen = true
        let code = exitCode
        let shouldResume = !resumed && code != nil
        if shouldResume { resumed = true }
        lock.unlock()
        if shouldResume, let code { resume(code) }
    }

    func markTerminated(exitCode: Int32, _ resume: (Int32) -> Void) {
        lock.lock()
        self.exitCode = exitCode
        let shouldResume = !resumed && eofSeen
        if shouldResume { resumed = true }
        lock.unlock()
        if shouldResume { resume(exitCode) }
    }
}
