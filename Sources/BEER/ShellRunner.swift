import Foundation

struct ProcessResult {
    let exitCode: Int32
    let output: String
}

private final class OutputBuffer: @unchecked Sendable {
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

    fileprivate init(process: Process, stdin: Pipe) {
        self.process = process
        self.stdin = stdin
    }

    var processIdentifier: Int32 { process.processIdentifier }
    var isRunning: Bool { process.isRunning }

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

enum ShellRunner {
    /// Start a process and return immediately, handing back a live handle.
    /// Use `run` instead unless the process must span other work.
    static func spawn(
        executable: String,
        arguments: [String],
        environment: [String: String],
        outputHandler: @escaping @Sendable (String) -> Void
    ) throws -> SpawnedProcess {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let stdin = Pipe()
        process.standardInput = stdin

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            outputHandler(chunk)
        }
        process.terminationHandler = { _ in
            pipe.fileHandleForReading.readabilityHandler = nil
        }

        do {
            try process.run()
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }
        return SpawnedProcess(process: process, stdin: stdin)
    }

    static func run(
        executable: String,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL? = nil,
        outputHandler: @escaping @Sendable (String) -> Void
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
            process.currentDirectoryURL = currentDirectory

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            let buffer = OutputBuffer()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
                buffer.append(chunk)
                outputHandler(chunk)
            }

            process.terminationHandler = { process in
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: ProcessResult(exitCode: process.terminationStatus, output: buffer.output))
            }

            do {
                try process.run()
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
