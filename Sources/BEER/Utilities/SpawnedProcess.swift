import Foundation

/// A helper process that deliberately outlives the call that started it.
///
/// The parent holds the write end of the child's stdin. Closing it is the
/// child's cue to shut down — and it closes on its own if BEER dies by any
/// means, including a force quit, because the kernel tears the pipe down with
/// the process. macOS has no parent-death signal, so this is the only teardown
/// that survives a crash.
final class SpawnedProcess: @unchecked Sendable {
    private let process: Process
    private let stdin: Pipe
    private let lock = NSLock()
    private var hasEnded = false

    init(process: Process, stdin: Pipe) {
        self.process = process
        self.stdin = stdin
    }

    var processIdentifier: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }

    /// Send one newline-terminated command to the child's stdin.
    /// Silently ignored once the child is gone — a command racing teardown is
    /// expected, not an error worth propagating to a caller.
    func send(_ line: String) {
        lock.withLock {
            guard !hasEnded, process.isRunning,
                  let data = (line + "\n").data(using: .utf8) else { return }
            try? stdin.fileHandleForWriting.write(contentsOf: data)
        }
    }

    /// Close stdin and give the child `timeout` to wind down on its own —
    /// a graceful exit matters here, since the child may need the time to tell
    /// a remote server it is finished. Escalates to SIGTERM only if it overstays.
    func end(timeout: TimeInterval = 10) async {
        // `withLock` rather than lock()/unlock(): the bare calls are banned in
        // async contexts, since a suspension while holding one would deadlock.
        let alreadyEnded = lock.withLock { () -> Bool in
            defer { hasEnded = true }
            return hasEnded
        }
        if alreadyEnded { return }

        try? stdin.fileHandleForWriting.close()

        if await waitForExit(within: timeout) { return }

        // Escalate. `terminate()` only *sends* SIGTERM, so keep waiting after
        // it rather than assuming: returning while the child is still alive
        // would let its work overlap whatever the caller does next.
        process.terminate()
        if await waitForExit(within: 3) { return }
        kill(process.processIdentifier, SIGKILL)
        _ = await waitForExit(within: 2)
    }

    /// True if the process is gone before the deadline.
    private func waitForExit(within timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return !process.isRunning
    }
}
