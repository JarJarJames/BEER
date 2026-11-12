import Foundation

/// Lets the main thread stop a process `ShellRunner.run` started, which only
/// hands back a result once the process has ended. `ShellRunner` attaches the
/// process from whatever thread started it, so both sides take the lock.
final class ProcessStopper: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopRequested = false

    /// True once `stop()` was called, so the caller can tell a stop it asked
    /// for from the process failing on its own.
    var wasStopped: Bool { lock.withLock { stopRequested } }

    /// Called once the process is running. A stop that came first applies now.
    func attach(_ process: Process) {
        let stopNow = lock.withLock { () -> Bool in
            self.process = process
            return stopRequested
        }
        if stopNow { Self.end(process) }
    }

    func stop() {
        let process = lock.withLock { () -> Process? in
            stopRequested = true
            return self.process
        }
        if let process { Self.end(process) }
    }

    /// SIGTERM, then SIGKILL if the process is still there after the grace
    /// period. `ShellRunner.run` returns once it has gone either way.
    private static func end(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()
        let pid = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + DownloadPauseLimits.stopGraceSeconds) {
            if process.isRunning { kill(pid, SIGKILL) }
        }
    }
}
