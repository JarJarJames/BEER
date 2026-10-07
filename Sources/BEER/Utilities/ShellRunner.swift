import Foundation

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
            guard !data.isEmpty else {
                // True EOF — nothing more will ever arrive on this pipe.
                pipe.fileHandleForReading.readabilityHandler = nil
                return
            }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
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

            // `terminationHandler` (the process exited) and the pipe reaching
            // EOF (every byte the child ever wrote has been delivered here)
            // are two DIFFERENT events with no ordering guarantee between
            // them — a child that prints its result and exits immediately can
            // have its final, possibly multi-read-sized write still winding
            // its way through the pipe when termination is reported. Resuming
            // on termination (as this used to) loses that tail silently.
            // EOF — `readabilityHandler` firing with empty data — is the only
            // signal that actually means "nothing more is ever coming", so
            // that's what gates completion; the exit code still comes from
            // `terminationHandler`, and whichever of the two fires second is
            // what actually resumes the continuation.
            let completion = CompletionGate()

            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard !data.isEmpty else {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    completion.markEOF { exitCode in
                        continuation.resume(returning: ProcessResult(exitCode: exitCode, output: buffer.output))
                    }
                    return
                }
                guard let chunk = String(data: data, encoding: .utf8) else { return }
                buffer.append(chunk)
                outputHandler(chunk)
            }

            process.terminationHandler = { process in
                completion.markTerminated(exitCode: process.terminationStatus) { exitCode in
                    continuation.resume(returning: ProcessResult(exitCode: exitCode, output: buffer.output))
                }
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
